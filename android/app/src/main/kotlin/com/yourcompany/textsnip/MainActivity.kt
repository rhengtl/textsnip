package com.yourcompany.textsnip

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "textsnip/capture"
    private var pendingResult: MethodChannel.Result? = null
    private val requestCode = 1001
    private lateinit var projectionManager: MediaProjectionManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        projectionManager =
            getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "captureRegion" -> {
                        @Suppress("UNCHECKED_CAST")
                        CaptureManager.pendingRect = call.arguments as Map<String, Int>
                        pendingResult = result
                        startActivityForResult(
                            projectionManager.createScreenCaptureIntent(),
                            requestCode
                        )
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
            ScreenCaptureService.resultCallback = { path ->
                pendingResult?.success(path)
                pendingResult = null
            }
        } else {
            pendingResult?.error("DENIED", "Screen capture permission denied", null)
            pendingResult = null
        }
    }
}
