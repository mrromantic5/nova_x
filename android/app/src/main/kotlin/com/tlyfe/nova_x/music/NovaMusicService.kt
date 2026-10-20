package com.tlyfe.nova_x.music

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder

/**
 * Keeps NOVA Music playing while NOVA X is in the background and shows the
 * media notification (play/pause, next, previous; also on the lock screen).
 *
 * Started only when the user starts music (from NOVA X, the NOVA panel or a
 * voice command while NOVA is on screen). Stops itself when music stops or
 * has been paused for a while (see NovaMusicPlayer).
 */
class NovaMusicService : Service() {

    companion object {
        const val ACTION_UPDATE = "com.tlyfe.nova_x.music.UPDATE"
        const val ACTION_TOGGLE = "com.tlyfe.nova_x.music.TOGGLE"
        const val ACTION_NEXT = "com.tlyfe.nova_x.music.NEXT"
        const val ACTION_PREVIOUS = "com.tlyfe.nova_x.music.PREVIOUS"
        const val ACTION_STOP = "com.tlyfe.nova_x.music.STOP"

        private const val CHANNEL_ID = "nova_music"
        private const val NOTIFICATION_ID = 7321

        @Volatile
        var running = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, NovaMusicService::class.java).setAction(ACTION_UPDATE)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // Android refused a background start: music still plays while
                // NOVA X is open; the notification appears on the next start.
            }
        }

        fun refresh(context: Context) {
            if (!running) return
            try {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(NOTIFICATION_ID, build(context))
            } catch (ignored: Exception) { }
        }

        fun stop(context: Context) {
            if (!running) return
            try {
                context.stopService(Intent(context, NovaMusicService::class.java))
            } catch (ignored: Exception) { }
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "NOVA Music", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Music playback controls"
                    setShowBadge(false)
                }
            )
        }

        private fun servicePending(context: Context, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, NovaMusicService::class.java).setAction(action)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            // The service is running while its notification is shown, so a plain
            // service intent is enough (and never needs a new startForeground call).
            return PendingIntent.getService(context, requestCode, intent, flags)
        }

        private fun action(context: Context, icon: Int, title: String, action: String, code: Int) =
            Notification.Action.Builder(Icon.createWithResource(context, icon), title, servicePending(context, action, code))
                .build()

        private fun build(context: Context): Notification {
            ensureChannel(context)
            val song = NovaMusicPlayer.current()
            val playing = NovaMusicPlayer.isPlayingNow()
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launch != null) {
                builder.setContentIntent(
                    PendingIntent.getActivity(
                        context, 7400, launch,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                )
            }
            val style = Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2)
            NovaMusicPlayer.sessionToken()?.let { style.setMediaSession(it) }
            return builder
                .setSmallIcon(if (playing) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause)
                .setContentTitle(song?.title ?: "NOVA Music")
                .setContentText(song?.artist?.takeIf { it.isNotBlank() } ?: "NOVA Music")
                .setSubText("NOVA Music")
                .setShowWhen(false)
                .setOngoing(playing)
                .setCategory(Notification.CATEGORY_TRANSPORT)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setDeleteIntent(servicePending(context, ACTION_STOP, 7405))
                .addAction(action(context, android.R.drawable.ic_media_previous, "Previous", ACTION_PREVIOUS, 7401))
                .addAction(
                    if (playing) action(context, android.R.drawable.ic_media_pause, "Pause", ACTION_TOGGLE, 7402)
                    else action(context, android.R.drawable.ic_media_play, "Play", ACTION_TOGGLE, 7402)
                )
                .addAction(action(context, android.R.drawable.ic_media_next, "Next", ACTION_NEXT, 7403))
                .setStyle(style)
                .build()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        NovaMusicPlayer.init(applicationContext)
        when (intent?.action) {
            ACTION_TOGGLE -> NovaMusicPlayer.toggle()
            ACTION_NEXT -> NovaMusicPlayer.next()
            ACTION_PREVIOUS -> NovaMusicPlayer.previous()
        }
        // Every start must promote the service to the foreground quickly,
        // including the "stop" action (Android requires it).
        try {
            val n = build(this)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIFICATION_ID, n)
            }
        } catch (e: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_STOP || NovaMusicPlayer.current() == null) {
            if (intent?.action == ACTION_STOP) NovaMusicPlayer.stop()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // NOVA X swiped away from Recents: keep playing music, but don't
        // keep a paused player alive.
        if (!NovaMusicPlayer.isPlayingNow()) {
            NovaMusicPlayer.stop()
            stopSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }
}
