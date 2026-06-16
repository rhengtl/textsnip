package com.yourcompany.textsnip

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "textsnip/capture"
    private var startResult: MethodChannel.Result? = null
    private val requestCode = 1001
    private lateinit var projectionManager: MediaProjectionManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        projectionManager =
            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Request MediaProjection consent while TextSnip is in the
                    // foreground; the resulting projection is kept alive by the
                    // service for the whole bubble session.
                    "startCapture" -> {
                        if (ScreenCaptureService.instance != null) {
                            result.success(true)
                        } else {
                            startResult = result
                            startActivityForResult(
                                projectionManager.createScreenCaptureIntent(),
                                requestCode
                            )
                        }
                    }
                    // Capture a frame from the already-running projection. Works
                    // even when triggered from another app (no re-consent needed).
                    "captureRegion" -> {
                        @Suppress("UNCHECKED_CAST")
                        val rect = call.arguments as Map<String, Int>
                        val service = ScreenCaptureService.instance
                        if (service == null) {
                            result.error("NO_PROJECTION", "Capture not started", null)
                        } else {
                            service.capture(rect) { path ->
                                if (path != null) {
                                    result.success(path)
                                } else {
                                    result.error("CAPTURE_FAILED", "Could not capture frame", null)
                                }
                            }
                        }
                    }
                    "stopCapture" -> {
                        ScreenCaptureService.instance?.stop()
                        result.success(null)
                    }
                    "isCaptureActive" -> {
                        result.success(ScreenCaptureService.instance != null)
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
    }

    @Deprecated("Required for MediaProjection consent on all supported API levels")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != this.requestCode) return

        if (resultCode == Activity.RESULT_OK && data != null) {
            val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
                putExtra("resultCode", resultCode)
                putExtra("data", data)
            }
            startForegroundService(serviceIntent)
            startResult?.success(true)
            startResult = null
        } else {
            startResult?.success(false)
            startResult = null
        }
    }
}
