package com.rhengtl.textsnip

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import flutter.overlay.window.flutter_overlay_window.OverlayService
import java.io.File
import java.io.FileOutputStream

/// Holds a single MediaProjection alive for the whole bubble session so that
/// captures triggered from other apps don't need to re-request consent (which
/// can only be granted while TextSnip is in the foreground).
///
/// Android 14+ forbids calling MediaProjection#createVirtualDisplay more than
/// once per projection instance ("Don't take multiple captures by invoking
/// MediaProjection#createVirtualDisplay multiple times on the same instance" —
/// a SecurityException that also tears the projection down). So we create ONE
/// long-lived VirtualDisplay + ImageReader when the projection starts and pull
/// a fresh frame from it for every snip, instead of recreating per capture.
///
/// A session can end in several ways — Dart calling stopCapture, the "Stop"
/// action on our notification, the system revoking the projection (the user
/// tapping "Stop sharing" in the status bar / cast tile), or a failure while
/// starting. All of them funnel through [endSession], which is idempotent,
/// fails any capture still in flight, takes the floating bubble down with it
/// (so the user is never left with a bubble that can't capture), and reports
/// the end to [listener] so the Dart side can resync its state.
class ScreenCaptureService : Service() {

    /// Session lifecycle callbacks, delivered on the main thread.
    interface SessionListener {
        fun onSessionStarted()
        fun onSessionEnded()
    }

    companion object {
        private const val TAG = "ScreenCaptureService"
        const val ACTION_STOP = "com.rhengtl.textsnip.action.STOP_CAPTURE"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_DATA = "data"

        /// How long a capture waits for a fresh mirrored frame when none is
        /// buffered yet (e.g. a completely static screen) before giving up.
        private const val FRAME_TIMEOUT_MS = 2000L

        /// Non-null only while a projection is live and ready to serve captures.
        var instance: ScreenCaptureService? = null
            private set

        var listener: SessionListener? = null

        val isActive: Boolean get() = instance != null
    }

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private val handler = Handler(Looper.getMainLooper())

    // True from a successful start until endSession() runs, so the teardown
    // side effects (bubble removal, listener callback) fire exactly once.
    private var sessionLive = false

    // The most recent mirrored frame, kept ready so a snip can be served at once.
    // All access happens on the main looper (capture() and the ImageReader
    // listener both run there), so no locking is needed.
    private var latestImage: Image? = null

    // A capture waiting for the next frame. Kept as rect + callback (rather than
    // a closure) so endSession() can fail it explicitly instead of dropping it.
    private var pendingRect: Map<String, Int>? = null
    private var pendingCallback: ((String?) -> Unit)? = null
    private var pendingTimeout: Runnable? = null

    // Display geometry captured when the virtual display was created.
    private var displayWidth = 0
    private var displayHeight = 0

    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // Notification "Stop" action. If nothing is live this is a no-op
            // apart from making sure the service goes away.
            if (sessionLive) endSession() else stopSelf()
            return START_NOT_STICKY
        }

        if (sessionLive) {
            // Duplicate start while a session is already running (MainActivity
            // guards against this, but a second consent token must never be
            // consumed on top of a live projection).
            return START_NOT_STICKY
        }

        // Must call startForeground before getMediaProjection on Android 14+.
        // This can throw (e.g. ForegroundServiceStartNotAllowedException if the
        // app is no longer considered foreground by the time the consent
        // activity returns); treat that as a failed start rather than crashing.
        try {
            startAsForeground()
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed", e)
            listener?.onSessionEnded()
            stopSelf()
            return START_NOT_STICKY
        }

        val consent = intent?.let(::readConsent)
        if (consent == null) {
            Log.w(TAG, "Started without a consent token")
            sessionLive = true // so endSession() performs the full teardown
            endSession()
            return START_NOT_STICKY
        }

        try {
            val mgr = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val proj = mgr.getMediaProjection(consent.first, consent.second)
                ?: throw IllegalStateException("getMediaProjection returned null")
            projection = proj
            // Android 14+ requires a registered callback. onStop fires when the
            // system (or the user, via the status-bar chip) revokes the
            // projection, and also as a consequence of our own projection.stop().
            proj.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    if (sessionLive) endSession()
                }
            }, handler)
            startMirroring(proj)
        } catch (e: Exception) {
            // A consent token can only be used once; a stale/reused token
            // throws SecurityException here.
            Log.w(TAG, "Could not start media projection", e)
            sessionLive = true
            endSession()
            return START_NOT_STICKY
        }

        sessionLive = true
        instance = this
        listener?.onSessionStarted()
        return START_NOT_STICKY
    }

    private fun readConsent(intent: Intent): Pair<Int, Intent>? {
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val data = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_DATA)
        }
        return if (resultCode != 0 && data != null) resultCode to data else null
    }

    /// Create the single VirtualDisplay + ImageReader that mirror the screen for
    /// the whole session. The reader's listener keeps [latestImage] up to date so
    /// each capture can pull the current frame without creating a new display.
    private fun startMirroring(proj: MediaProjection) {
        val metrics = resources.displayMetrics
        displayWidth = metrics.widthPixels
        displayHeight = metrics.heightPixels
        val density = metrics.densityDpi

        val reader = ImageReader.newInstance(
            displayWidth, displayHeight, PixelFormat.RGBA_8888, 2
        )
        reader.setOnImageAvailableListener({ r -> onFrame(r) }, handler)
        imageReader = reader

        virtualDisplay = proj.createVirtualDisplay(
            "textsnip-capture",
            displayWidth, displayHeight, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface, null, handler
        )
    }

    /// Called on the main looper for every mirrored frame. If a capture is
    /// waiting, hand it this fresh frame; otherwise retain it as the latest and
    /// drop the previous one so the pipeline keeps flowing and never goes stale.
    private fun onFrame(reader: ImageReader) {
        val image = try {
            reader.acquireLatestImage()
        } catch (e: Exception) {
            null
        } ?: return

        if (!sessionLive) {
            image.close()
            return
        }

        val rect = pendingRect
        val callback = pendingCallback
        if (rect != null && callback != null) {
            clearPending()
            processFrame(image, rect, callback) // processFrame closes the image
            return
        }

        latestImage?.close()
        latestImage = image
    }

    private fun startAsForeground() {
        SessionNotifications.ensureChannels(this)
        val notification = SessionNotifications.buildCaptureNotification(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                SessionNotifications.CAPTURE_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(SessionNotifications.CAPTURE_NOTIFICATION_ID, notification)
        }
    }

    /// Pull a fresh frame from the running mirror, crop it to [rect] (physical
    /// pixels), save a PNG to cacheDir and return its path via [callback] (null
    /// on failure). The overlay is hidden by the caller before this runs, so the
    /// most recent buffered frame already reflects the real screen.
    ///
    /// [callback] is always invoked exactly once — on success, on failure, on
    /// timeout, or if the session ends while the capture is waiting.
    fun capture(rect: Map<String, Int>, callback: (String?) -> Unit) {
        handler.post {
            if (!sessionLive || imageReader == null) {
                callback(null)
                return@post
            }
            // Only one capture can wait at a time; a newer request supersedes
            // (and fails) an older one instead of silently orphaning it.
            failPending()

            val ready = latestImage
            if (ready != null) {
                latestImage = null
                processFrame(ready, rect, callback)
                return@post
            }
            // No frame buffered yet (static screen): wait for the next one, but
            // never hang — fall back to failure after a short timeout.
            pendingRect = rect
            pendingCallback = callback
            val timeout = Runnable {
                if (pendingCallback === callback) failPending()
            }
            pendingTimeout = timeout
            handler.postDelayed(timeout, FRAME_TIMEOUT_MS)
        }
    }

    private fun clearPending() {
        pendingTimeout?.let { handler.removeCallbacks(it) }
        pendingTimeout = null
        pendingRect = null
        pendingCallback = null
    }

    /// Resolve the waiting capture (if any) with failure.
    private fun failPending() {
        val callback = pendingCallback
        clearPending()
        callback?.invoke(null)
    }

    /// Crop [image] to [rect] (physical pixels), save a PNG and report its path.
    /// Always closes [image].
    private fun processFrame(
        image: Image,
        rect: Map<String, Int>,
        callback: (String?) -> Unit,
    ) {
        val width = displayWidth
        val height = displayHeight
        try {
            val plane = image.planes[0]
            val rowStride = plane.rowStride
            val pixelStride = plane.pixelStride
            val rowPadding = rowStride - pixelStride * width

            // Create bitmap accounting for row padding, then trim to exact screen size.
            val padded = Bitmap.createBitmap(
                width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888
            )
            padded.copyPixelsFromBuffer(plane.buffer)
            val trimmed = Bitmap.createBitmap(padded, 0, 0, width, height)
            padded.recycle()

            // Crop to the rectangle chosen by the user; clamp to avoid out-of-bounds.
            val left = rect["left"]!!.coerceIn(0, width - 1)
            val top = rect["top"]!!.coerceIn(0, height - 1)
            val cw = rect["width"]!!.coerceIn(1, width - left)
            val ch = rect["height"]!!.coerceIn(1, height - top)
            val cropped = Bitmap.createBitmap(trimmed, left, top, cw, ch)
            trimmed.recycle()

            val file = File(cacheDir, "snip_${System.currentTimeMillis()}.png")
            FileOutputStream(file).use { out ->
                cropped.compress(Bitmap.CompressFormat.PNG, 100, out)
            }
            cropped.recycle()

            callback(file.absolutePath)
        } catch (e: Exception) {
            Log.w(TAG, "Frame processing failed", e)
            callback(null)
        } finally {
            image.close()
        }
    }

    /// Stop the projection and the foreground service (ends the session).
    fun stop() = endSession()

    /// Idempotent teardown. Safe to call from any of the end-of-session paths.
    private fun endSession() {
        if (!sessionLive) return
        sessionLive = false
        instance = null

        failPending()
        latestImage?.close()
        latestImage = null
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        // stop() triggers our registered onStop callback asynchronously; the
        // sessionLive guard makes that re-entry a no-op.
        try {
            projection?.stop()
        } catch (_: Exception) {
        }
        projection = null

        // Without a projection the bubble can't do anything; take it down so the
        // user isn't left with a dead button and a "ready" notification.
        dismissOverlayBubble()

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()

        listener?.onSessionEnded()
    }

    private fun dismissOverlayBubble() {
        if (!OverlayService.isRunning) return
        try {
            // Mirrors what flutter_overlay_window's closeOverlay() does natively.
            stopService(Intent(this, OverlayService::class.java))
        } catch (e: Exception) {
            Log.w(TAG, "Could not dismiss overlay bubble", e)
        }
    }

    override fun onDestroy() {
        // The system can destroy the service outside our own stop paths (e.g.
        // low memory). Make sure the projection and the bubble go with it.
        endSession()
        super.onDestroy()
    }
}
