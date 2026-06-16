package com.yourcompany.textsnip

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
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
class ScreenCaptureService : Service() {

    companion object {
        var instance: ScreenCaptureService? = null
    }

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private val handler = Handler(Looper.getMainLooper())

    // The most recent mirrored frame, kept ready so a snip can be served at once.
    // All access happens on the main looper (capture() and the ImageReader
    // listener both run there), so no locking is needed.
    private var latestImage: Image? = null
    private var pending: ((Image) -> Unit)? = null
    private var pendingTimeout: Runnable? = null

    // Display geometry captured when the virtual display was created.
    private var displayWidth = 0
    private var displayHeight = 0

    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Must call startForeground before getMediaProjection on Android 14+.
        startAsForeground()

        val resultCode = intent!!.getIntExtra("resultCode", 0)
        val data = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra("data", Intent::class.java)!!
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Intent>("data")!!
        }

        val mgr = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        projection = mgr.getMediaProjection(resultCode, data)

        // Android 14+ requires a registered callback.
        projection?.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() = cleanup()
        }, handler)

        startMirroring()

        instance = this
        return START_NOT_STICKY
    }

    /// Create the single VirtualDisplay + ImageReader that mirror the screen for
    /// the whole session. The reader's listener keeps [latestImage] up to date so
    /// each capture can pull the current frame without creating a new display.
    private fun startMirroring() {
        val proj = projection ?: return

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

        val waiter = pending
        if (waiter != null) {
            pending = null
            pendingTimeout?.let { handler.removeCallbacks(it) }
            pendingTimeout = null
            waiter(image) // the waiter owns closing the image
            return
        }

        latestImage?.close()
        latestImage = image
    }

    private fun startAsForeground() {
        val channelId = "textsnip_capture"
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(channelId) == null) {
            nm.createNotificationChannel(
                NotificationChannel(channelId, "Screen capture", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val notification = Notification.Builder(this, channelId)
            .setContentTitle("TextSnip")
            .setContentText("Ready to capture text")
            .setSmallIcon(R.mipmap.ic_launcher)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(1, notification)
        }
    }

    /// Pull a fresh frame from the running mirror, crop it to [rect] (physical
    /// pixels), save a PNG to cacheDir and return its path via [callback] (null
    /// on failure). The overlay is hidden by the caller before this runs, so the
    /// most recent buffered frame already reflects the real screen.
    fun capture(rect: Map<String, Int>, callback: (String?) -> Unit) {
        if (projection == null || imageReader == null) {
            callback(null)
            return
        }
        handler.post {
            val ready = latestImage
            if (ready != null) {
                latestImage = null
                processFrame(ready, rect, callback)
                return@post
            }
            // No frame buffered yet (static screen): wait for the next one, but
            // never hang — fall back to failure after a short timeout.
            pending = { img -> processFrame(img, rect, callback) }
            val timeout = Runnable {
                if (pending != null) {
                    pending = null
                    pendingTimeout = null
                    callback(null)
                }
            }
            pendingTimeout = timeout
            handler.postDelayed(timeout, 2000)
        }
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
            callback(null)
        } finally {
            image.close()
        }
    }

    /// Stop the projection and the foreground service (ends the session).
    fun stop() = cleanup()

    private fun cleanup() {
        instance = null
        pendingTimeout?.let { handler.removeCallbacks(it) }
        pendingTimeout = null
        pending = null
        latestImage?.close()
        latestImage = null
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        projection?.stop()
        projection = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
}
