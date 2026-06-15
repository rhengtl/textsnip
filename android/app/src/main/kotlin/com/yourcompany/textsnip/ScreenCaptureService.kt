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
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.FileOutputStream

class ScreenCaptureService : Service() {

    companion object {
        var resultCallback: ((String) -> Unit)? = null
    }

    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private val handler = Handler(Looper.getMainLooper())

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

        captureOneFrame()
        return START_NOT_STICKY
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
            .setContentText("Capturing screen region…")
            .setSmallIcon(R.mipmap.ic_launcher)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(1, notification)
        }
    }

    private fun captureOneFrame() {
        val metrics = resources.displayMetrics
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val density = metrics.densityDpi

        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

        virtualDisplay = projection?.createVirtualDisplay(
            "textsnip-capture",
            width, height, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface, null, null
        )

        imageReader!!.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val plane = image.planes[0]
                val rowStride = plane.rowStride
                val pixelStride = plane.pixelStride
                val rowPadding = rowStride - pixelStride * width

                // Create bitmap accounting for row padding, then trim to exact screen size.
                var bitmap = Bitmap.createBitmap(
                    width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888
                )
                bitmap.copyPixelsFromBuffer(plane.buffer)
                val trimmed = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                bitmap.recycle()

                // Crop to the rectangle chosen by the user; clamp to avoid out-of-bounds.
                val r = CaptureManager.pendingRect!!
                val left   = r["left"]!!.coerceIn(0, width - 1)
                val top    = r["top"]!!.coerceIn(0, height - 1)
                val cw     = r["width"]!!.coerceIn(1, width - left)
                val ch     = r["height"]!!.coerceIn(1, height - top)
                val cropped = Bitmap.createBitmap(trimmed, left, top, cw, ch)
                trimmed.recycle()

                val file = File(cacheDir, "snip_${System.currentTimeMillis()}.png")
                FileOutputStream(file).use { out ->
                    cropped.compress(Bitmap.CompressFormat.PNG, 100, out)
                }
                cropped.recycle()

                handler.post {
                    resultCallback?.invoke(file.absolutePath)
                    resultCallback = null
                }
            } finally {
                image.close()
                cleanup()
            }
        }, handler)
    }

    private fun cleanup() {
        virtualDisplay?.release(); virtualDisplay = null
        imageReader?.close();     imageReader = null
        projection?.stop();       projection = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
}
