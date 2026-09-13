package com.rhengtl.textsnip

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), ScreenCaptureService.SessionListener {

    private companion object {
        const val TAG = "MainActivity"
        const val CHANNEL_NAME = "textsnip/capture"
        const val CONSENT_REQUEST_CODE = 1001
    }

    private var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // The pending startCapture reply. Answered only once the service reports
    // the projection is actually live (or failed), not merely once consent was
    // granted — otherwise Dart could show the bubble for a session that never
    // came up.
    private var startResult: MethodChannel.Result? = null
    private lateinit var projectionManager: MediaProjectionManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        projectionManager =
            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        // Create (and, for the overlay plugin's channel, pre-empt) notification
        // channels before any service can post to them.
        SessionNotifications.ensureChannels(this)
        ScreenCaptureService.listener = this

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(::handleMethodCall)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (ScreenCaptureService.listener === this) ScreenCaptureService.listener = null
        channel?.setMethodCallHandler(null)
        channel = null
        // Never leave a Dart future dangling if the engine goes away mid-consent.
        startResult?.success(false)
        startResult = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Request MediaProjection consent while TextSnip is in the
            // foreground; the resulting projection is kept alive by the
            // service for the whole bubble session.
            "startCapture" -> startCapture(result)

            // Capture a frame from the already-running projection. Works
            // even when triggered from another app (no re-consent needed).
            "captureRegion" -> {
                @Suppress("UNCHECKED_CAST")
                val rect = call.arguments as? Map<String, Int>
                val service = ScreenCaptureService.instance
                when {
                    rect == null ->
                        result.error("BAD_ARGS", "Expected a rect map", null)
                    service == null ->
                        result.error("NO_PROJECTION", "Capture not started", null)
                    else -> service.capture(rect) { path ->
                        if (path != null) {
                            result.success(path)
                        } else if (ScreenCaptureService.isActive) {
                            result.error("CAPTURE_FAILED", "Could not capture frame", null)
                        } else {
                            // The session ended while this capture was waiting.
                            result.error("NO_PROJECTION", "Capture session ended", null)
                        }
                    }
                }
            }

            "stopCapture" -> {
                ScreenCaptureService.instance?.stop()
                result.success(null)
            }

            "isCaptureActive" -> result.success(ScreenCaptureService.isActive)

            // flutter_overlay_window re-creates its notification channel (and
            // resets its user-visible name) every time the bubble is shown.
            // Importance can't be raised that way, but the name can, so
            // re-apply ours shortly after the plugin's service has started.
            "overlayShown" -> {
                for (delayMs in longArrayOf(500L, 2500L)) {
                    mainHandler.postDelayed({ SessionNotifications.ensureChannels(this) }, delayMs)
                }
                result.success(null)
            }

            "bringToFront" -> {
                startActivity(
                    Intent(this, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    }
                )
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun startCapture(result: MethodChannel.Result) {
        if (ScreenCaptureService.isActive) {
            result.success(true)
            return
        }
        // A second request while the consent dialog is still up would
        // otherwise orphan the first reply (its future would never complete).
        startResult?.success(false)
        startResult = result
        try {
            startActivityForResult(createConsentIntent(), CONSENT_REQUEST_CODE)
        } catch (e: Exception) {
            Log.w(TAG, "Could not launch screen-capture consent", e)
            startResult = null
            result.success(false)
        }
    }

    /// Android 14+ shows a "Cast your screen?" dialog that defaults to
    /// "A single app" — which would only ever capture the one app the user
    /// picks, not whatever they later float the bubble over. Asking for the
    /// default display up front removes that option so the dialog is a plain
    /// entire-screen consent.
    private fun createConsentIntent(): Intent =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            projectionManager.createScreenCaptureIntent(
                MediaProjectionConfig.createConfigForDefaultDisplay()
            )
        } else {
            projectionManager.createScreenCaptureIntent()
        }

    @Deprecated("Required for MediaProjection consent on all supported API levels")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CONSENT_REQUEST_CODE) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            startResult?.success(false)
            startResult = null
            return
        }

        val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
            putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
            putExtra(ScreenCaptureService.EXTRA_DATA, data)
        }
        try {
            // Falls back to startService() below API 26.
            ContextCompat.startForegroundService(this, serviceIntent)
            // startResult is answered from onSessionStarted / onSessionEnded.
        } catch (e: Exception) {
            Log.w(TAG, "Could not start capture service", e)
            startResult?.success(false)
            startResult = null
        }
    }

    // ── ScreenCaptureService.SessionListener ────────────────────────────────

    override fun onSessionStarted() {
        mainHandler.post {
            startResult?.success(true)
            startResult = null
        }
    }

    override fun onSessionEnded() {
        mainHandler.post {
            // If the service died while coming up, that is the answer to the
            // pending start request.
            startResult?.success(false)
            startResult = null
            // Otherwise let Dart know the session is gone (Stop action on the
            // notification, projection revoked by the system, etc.) so it can
            // reset the UI and any snip in progress.
            channel?.invokeMethod("sessionEnded", null)
        }
    }
}
