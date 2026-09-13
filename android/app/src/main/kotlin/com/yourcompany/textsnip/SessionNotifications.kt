package com.yourcompany.textsnip

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/// Everything notification-related for a bubble session lives here so the two
/// foreground services that make up a session (our ScreenCaptureService and
/// flutter_overlay_window's OverlayService) present one coherent, silent set of
/// notifications instead of two unrelated channels with different importance.
object SessionNotifications {

    const val CAPTURE_CHANNEL_ID = "textsnip_capture"
    const val CAPTURE_NOTIFICATION_ID = 1

    /// flutter_overlay_window hard-codes this channel id and creates it with
    /// IMPORTANCE_DEFAULT (audible) the first time the bubble is shown. Because
    /// the bubble is hidden and re-shown on every snip, that would chime and
    /// heads-up on each capture. Android lets an app *lower* a channel's
    /// importance (as long as the user hasn't customised it), so we create the
    /// channel first, silently, with a readable name; the plugin's later
    /// createNotificationChannel() call then cannot raise it again.
    private const val OVERLAY_PLUGIN_CHANNEL_ID = "Overlay Channel"

    /// Idempotent. Safe to call on every activity start and service start.
    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return

        nm.createNotificationChannel(
            NotificationChannel(
                CAPTURE_CHANNEL_ID,
                "Screen capture session",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while TextSnip is able to capture the screen."
                setShowBadge(false)
            }
        )

        nm.createNotificationChannel(
            NotificationChannel(
                OVERLAY_PLUGIN_CHANNEL_ID,
                "Floating bubble",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while the floating snip button is on screen."
                setShowBadge(false)
            }
        )
    }

    /// The persistent notification that backs the media-projection foreground
    /// service. Tapping it opens TextSnip; the action ends the session.
    fun buildCaptureNotification(context: Context): Notification {
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

        // Same as tapping the launcher icon: brings the existing task forward
        // rather than creating a duplicate MainActivity.
        val openIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val openPending = openIntent?.let {
            PendingIntent.getActivity(context, 0, it, flags)
        }

        val stopIntent = Intent(context, ScreenCaptureService::class.java)
            .setAction(ScreenCaptureService.ACTION_STOP)
        val stopPending = PendingIntent.getService(context, 1, stopIntent, flags)

        return NotificationCompat.Builder(context, CAPTURE_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_textsnip)
            .setContentTitle("TextSnip is ready")
            .setContentText("Tap the floating bubble to snip text from any app.")
            .setContentIntent(openPending)
            .addAction(0, "Stop", stopPending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setPriority(NotificationCompat.PRIORITY_LOW) // pre-O devices (no channels)
            .build()
    }
}
