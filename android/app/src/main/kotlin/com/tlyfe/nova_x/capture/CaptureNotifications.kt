package com.tlyfe.nova_x.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.tlyfe.nova_x.MainActivity
import com.tlyfe.nova_x.R

/**
 * Notifications for NOVA Capture:
 *  - the ongoing recording notification (required for the foreground service;
 *    it can't be dismissed while recording) with Pause/Resume and Stop & save;
 *  - "Recording saved" / "Screenshot saved" (tap → open it in NOVA X).
 */
object CaptureNotifications {
    const val CHANNEL_ACTIVE = "nova_capture_active"
    const val CHANNEL_SAVED = "nova_capture_saved"
    const val ID_ACTIVE = 9401
    const val ID_SAVED = 9402

    private const val CYAN = 0xFF00D4FF.toInt()
    private const val RED = 0xFFFF3B4E.toInt()

    private fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ACTIVE, "Screen recording", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while NOVA X is recording or capturing your screen."
                setShowBadge(false)
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_SAVED, "Saved captures", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Tells you when a screenshot or recording has been saved."
                setShowBadge(false)
                setSound(null, null)
            },
        )
    }

    private fun builder(ctx: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(ctx, channel)
        else @Suppress("DEPRECATION") Notification.Builder(ctx)

    private fun flags() = PendingIntent.FLAG_UPDATE_CURRENT or
        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

    /** Opens a NOVA X page by its validated feature id (MainActivity.EXTRA_FEATURE). */
    fun openFeature(ctx: Context, feature: String, request: Int): PendingIntent {
        val i = Intent(ctx, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(MainActivity.EXTRA_FEATURE, feature)
        }
        return PendingIntent.getActivity(ctx, request, i, flags())
    }

    private fun serviceAction(ctx: Context, action: String, request: Int): PendingIntent {
        val i = Intent(ctx, CaptureService::class.java).setAction(action)
        return PendingIntent.getService(ctx, request, i, flags())
    }

    /** The ongoing notification for the current state. */
    fun active(ctx: Context, state: String, elapsedMs: Long, countdown: Int, screenshot: Boolean): Notification {
        ensureChannels(ctx)
        val b = builder(ctx, CHANNEL_ACTIVE)
            .setSmallIcon(R.drawable.ic_stat_nova_capture)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openFeature(ctx, "capture", 1))
            .setCategory(Notification.CATEGORY_SERVICE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) b.setColor(if (state == CaptureContract.RECORDING) RED else CYAN)
        if (screenshot) {
            return b.setContentTitle("NOVA X is taking a screenshot")
                .setContentText("Only the screenshot you asked for.")
                .build()
        }
        when (state) {
            CaptureContract.RECORDING -> {
                b.setContentTitle("● NOVA X is recording your screen")
                    .setContentText("Tap to open NOVA Capture")
                    .setUsesChronometer(true)
                    .setWhen(System.currentTimeMillis() - elapsedMs)
                    .setShowWhen(true)
                b.addAction(action(ctx, android.R.drawable.ic_media_pause, "Pause", CaptureService.ACTION_PAUSE, 11))
                b.addAction(action(ctx, android.R.drawable.ic_menu_save, "Stop & save", CaptureService.ACTION_STOP, 12))
            }
            CaptureContract.PAUSED -> {
                b.setContentTitle("Ⅱ Screen recording paused")
                    .setContentText("${format(elapsedMs)} recorded · nothing is being recorded now")
                    .setShowWhen(false)
                b.addAction(action(ctx, android.R.drawable.ic_media_play, "Resume", CaptureService.ACTION_RESUME, 13))
                b.addAction(action(ctx, android.R.drawable.ic_menu_save, "Stop & save", CaptureService.ACTION_STOP, 12))
            }
            CaptureContract.STARTING -> b.setContentTitle(
                if (countdown > 0) "Screen recording starts in $countdown…" else "Starting screen recording…",
            ).setContentText("Switch to what you want to record.")
                .addAction(action(ctx, android.R.drawable.ic_menu_close_clear_cancel, "Cancel", CaptureService.ACTION_CANCEL, 14))
            else -> b.setContentTitle("Saving your recording…").setContentText("Please wait a moment.")
        }
        return b.build()
    }

    @Suppress("DEPRECATION")
    private fun action(ctx: Context, icon: Int, label: String, act: String, request: Int): Notification.Action =
        Notification.Action.Builder(icon, label, serviceAction(ctx, act, request)).build()

    fun update(ctx: Context, notification: Notification) {
        try {
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(ID_ACTIVE, notification)
        } catch (e: Exception) { }
    }

    /** "Saved" notification; tapping it opens the newest capture in NOVA X. */
    fun saved(ctx: Context, title: String, text: String) {
        try {
            ensureChannels(ctx)
            val b = builder(ctx, CHANNEL_SAVED)
                .setSmallIcon(R.drawable.ic_stat_nova_capture)
                .setContentTitle(title)
                .setContentText(text)
                .setAutoCancel(true)
                .setContentIntent(openFeature(ctx, "capture_latest", 2))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) b.setColor(CYAN)
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(ID_SAVED, b.build())
        } catch (e: Exception) { }
    }

    fun format(ms: Long): String {
        val s = ms / 1000
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%d:%02d", m, sec)
    }
}
