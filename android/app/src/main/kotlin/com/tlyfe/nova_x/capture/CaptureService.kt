package com.tlyfe.nova_x.capture

import android.app.Activity
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder

/**
 * Visible foreground service that exists only while NOVA Capture is capturing
 * (a recording, or the one screenshot the user asked for). Android requires a
 * foreground service of type mediaProjection for screen capture (Android 10+,
 * and from Android 14 it must be started after the user's consent, which is
 * how [CaptureCoordinator] uses it). Type microphone is added only when the
 * user chose a recording with microphone narration and allowed the mic.
 *
 * Notification actions (Pause/Resume, Stop & save, Cancel) arrive here as
 * intents and go through the same validated coordinator methods as the app.
 */
class CaptureService : Service() {

    companion object {
        const val ACTION_PAUSE = "com.tlyfe.nova_x.capture.PAUSE"
        const val ACTION_RESUME = "com.tlyfe.nova_x.capture.RESUME"
        const val ACTION_STOP = "com.tlyfe.nova_x.capture.STOP"
        const val ACTION_CANCEL = "com.tlyfe.nova_x.capture.CANCEL"
        private const val EXTRA_MODE = "mode"
        private const val EXTRA_MIC = "mic"

        @Volatile var running: CaptureService? = null
            private set

        /** True when the service could not add the microphone type (Android 11+ rules). */
        @Volatile var micBlocked = false
            private set

        fun start(ctx: Context, mode: String, mic: Boolean) {
            val i = Intent(ctx, CaptureService::class.java).putExtra(EXTRA_MODE, mode).putExtra(EXTRA_MIC, mic)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) ctx.startForegroundService(i) else ctx.startService(i)
        }

        fun stop(ctx: Context) {
            try { ctx.stopService(Intent(ctx, CaptureService::class.java)) } catch (e: Exception) { }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action in setOf(ACTION_PAUSE, ACTION_RESUME, ACTION_STOP, ACTION_CANCEL)) {
            when (action) {
                ACTION_PAUSE -> CaptureCoordinator.pause(null)
                ACTION_RESUME -> CaptureCoordinator.resume(null)
                ACTION_STOP -> CaptureCoordinator.stop(null, "user")
                ACTION_CANCEL -> CaptureCoordinator.cancel(null)
            }
            // A tap on an old notification after the session ended: don't linger.
            if (running == null) stopSelf(startId)
            return START_NOT_STICKY
        }
        val mode = intent?.getStringExtra(EXTRA_MODE)
        if (mode == null) {
            // Restarted by the system without a session (START_NOT_STICKY makes this rare).
            stopSelf()
            return START_NOT_STICKY
        }
        val mic = intent.getBooleanExtra(EXTRA_MIC, false)
        val notification = CaptureCoordinator.currentNotification(this)
        micBlocked = false
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                if (mic && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                try {
                    startForeground(CaptureNotifications.ID_ACTIVE, notification, types)
                } catch (e: SecurityException) {
                    if (!mic) throw e
                    // Microphone not allowed for this service right now: record without it.
                    micBlocked = true
                    startForeground(CaptureNotifications.ID_ACTIVE, notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
                }
            } else {
                startForeground(CaptureNotifications.ID_ACTIVE, notification)
            }
        } catch (e: Exception) {
            running = null
            CaptureCoordinator.onServiceFailed()
            stopSelf()
            return START_NOT_STICKY
        }
        running = this
        CaptureCoordinator.onServiceReady(this, mode)
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    override fun onDestroy() {
        running = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else stopForeground(true)
        CaptureCoordinator.onServiceDestroyed()
        super.onDestroy()
    }

    /** The user swiped NOVA X away from Recents: finish and save what was recorded. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        CaptureCoordinator.stop(null, "interrupted")
        super.onTaskRemoved(rootIntent)
    }
}

/**
 * Invisible screen that shows Android's own screen-capture consent dialog
 * ("Start recording or casting with NOVA X?") and hands the answer to
 * [CaptureCoordinator]. Used for every new capture session — Android 14+
 * requires a fresh consent each time, and NOVA X never reuses an old one.
 * On Android 14+ the dialog is set to the entire screen.
 */
class CaptureConsentActivity : Activity() {

    companion object {
        const val EXTRA_MODE = "mode"
        private const val REQ = 7101
        private const val KEY_LAUNCHED = "launched"
    }

    private var mode = "record"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        mode = intent?.getStringExtra(EXTRA_MODE)?.takeIf { it == "record" || it == "screenshot" } ?: "record"
        if (savedInstanceState?.getBoolean(KEY_LAUNCHED) == true) return // waiting for the dialog's answer
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
        if (mpm == null) {
            CaptureCoordinator.onConsentResult(applicationContext, mode, RESULT_CANCELED, null, unsupported = true)
            finishQuietly()
            return
        }
        try {
            val i = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                mpm.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
            } else {
                mpm.createScreenCaptureIntent()
            }
            @Suppress("DEPRECATION")
            startActivityForResult(i, REQ)
        } catch (e: Exception) {
            CaptureCoordinator.onConsentResult(applicationContext, mode, RESULT_CANCELED, null, unsupported = true)
            finishQuietly()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean(KEY_LAUNCHED, true)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ) {
            CaptureCoordinator.onConsentResult(applicationContext, mode, resultCode, data)
            finishQuietly()
        }
    }

    private fun finishQuietly() {
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }
}
