package com.tlyfe.nova_x.nova

import android.Manifest
import android.annotation.SuppressLint
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import com.tlyfe.nova_x.MainActivity
import com.tlyfe.nova_x.NovaAssistActivity

/** The user's "Hey NOVA" choice (native side is the source of truth). */
object NovaWakePrefs {
    private const val FILE = "nova_wake"
    private const val KEY_ENABLED = "enabled"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }
}

/**
 * "Hey NOVA" — a microphone foreground service that runs the on-device wake
 * word detector (NovaWakeEngine). Nothing is recorded, stored or uploaded
 * while it listens; audio is analysed in memory, 0.1 s at a time.
 *
 * Android rules this follows:
 *  - It can only be started while NOVA X is on screen (Android 14+ forbid
 *    starting microphone services from the background), so it starts when the
 *    user turns the setting on and whenever NOVA X is opened.
 *  - A notification is always shown while it listens.
 *  - Apps can't open screens from the background. On "Hey NOVA" the floating
 *    panel opens directly when NOVA X is visible or the user allowed "Display
 *    over other apps"; otherwise a notification asks the user to tap it.
 *  - Android 7–9 allow one recorder at a time, so there it only listens while
 *    NOVA X is open (other apps' voice notes and calls keep working).
 */
class NovaWakeService : Service() {

    companion object {
        const val ACTION_START = "com.tlyfe.nova_x.nova.WAKE_START"
        const val ACTION_STOP = "com.tlyfe.nova_x.nova.WAKE_STOP"
        const val ALERT_NOTIFICATION_ID = 9412

        private const val LISTEN_NOTIFICATION_ID = 9411
        private const val CHANNEL_LISTEN = "nova_wake"
        private const val CHANNEL_ALERT = "nova_wake_alert"
        private const val CHUNK = 1600 // 0.1 s at 16 kHz
        private const val AFTER_DETECTION_PAUSE_MS = 8000L

        @Volatile var running = false
            private set

        /** Why the last start failed, if it did (shown in NOVA settings). */
        @Volatile var lastError: String? = null
            private set

        @Volatile private var engineAvailable: Boolean? = null

        fun micGranted(context: Context) =
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

        /** Model present and the native engine loads on this phone. */
        fun isSupported(context: Context): Boolean {
            engineAvailable?.let { return it }
            val engine = NovaWakeEngine.create(context.applicationContext)
            val ok = engine != null
            engine?.release()
            engineAvailable = ok
            return ok
        }

        /** Android 10+ can share the microphone, so NOVA can listen over other apps. */
        fun backgroundSupported() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

        /** Start if the user turned it on. Call only while NOVA X is visible. */
        fun startIfEnabled(context: Context) {
            if (NovaWakePrefs.isEnabled(context) && !running) start(context)
        }

        /** Returns false when Android refused the start. Call while NOVA X is visible. */
        fun start(context: Context): Boolean {
            if (!micGranted(context)) {
                lastError = "microphone"
                return false
            }
            val intent = Intent(context, NovaWakeService::class.java).setAction(ACTION_START)
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (e: Exception) {
                // ForegroundServiceStartNotAllowedException (Android 12+) when not visible.
                lastError = "start_not_allowed"
                false
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, NovaWakeService::class.java))
        }
    }

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var active = false
    private var worker: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            NovaWakePrefs.setEnabled(this, false)
            stopSelf()
            return START_NOT_STICKY
        }
        if (!micGranted(this)) {
            lastError = "microphone"
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            createChannels()
            val notification = listeningNotification()
            // The "microphone" service type exists from Android 11.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(LISTEN_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(LISTEN_NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            lastError = "start_not_allowed"
            stopSelf()
            return START_NOT_STICKY
        }
        if (worker == null) {
            active = true
            running = true
            lastError = null
            worker = Thread({ listenLoop() }, "nova-wake").also { it.start() }
        }
        // Not sticky: Android may not restart a microphone service from the
        // background, so it resumes the next time NOVA X is opened instead.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        active = false
        running = false
        worker?.interrupt()
        worker = null
        NovaMicArbiter.wakeMicOpen = false
        super.onDestroy()
    }

    // ── Listening ──────────────────────────────────────────────────────────

    private fun listenLoop() {
        val engine = NovaWakeEngine.create(applicationContext)
        if (engine == null) {
            lastError = "unsupported"
            main.post { stopSelf() }
            return
        }
        var record: AudioRecord? = null
        val pcm = ShortArray(CHUNK)
        var failures = 0
        try {
            while (active) {
                if (shouldPause()) {
                    if (record != null) {
                        closeRecord(record)
                        record = null
                        engine.restart()
                    }
                    sleep(150)
                    continue
                }
                if (record == null) {
                    record = openRecord()
                    if (record == null) {
                        failures++
                        sleep(if (failures < 5) 1000L else 5000L)
                        continue
                    }
                    failures = 0
                    NovaMicArbiter.wakeMicOpen = true
                }
                val n = record.read(pcm, 0, CHUNK)
                if (n <= 0) {
                    // Microphone lost (another app, audio server restart…): reopen.
                    closeRecord(record)
                    record = null
                    sleep(300)
                    continue
                }
                val samples = FloatArray(n)
                for (i in 0 until n) samples[i] = pcm[i] / 32768f
                if (engine.accept(samples)) {
                    NovaMicArbiter.pauseFor(AFTER_DETECTION_PAUSE_MS)
                    closeRecord(record)
                    record = null
                    engine.restart()
                    main.post { onWakeWord() }
                }
            }
        } catch (t: Throwable) {
            lastError = "engine_error"
        } finally {
            record?.let { closeRecord(it) }
            NovaMicArbiter.wakeMicOpen = false
            engine.release()
            // Ended without being asked to (engine/microphone failure): never
            // leave a "listening" notification up while nothing listens.
            if (active) {
                active = false
                running = false
                main.post { stopSelf() }
            }
        }
    }

    private fun shouldPause(): Boolean {
        if (NovaMicArbiter.isHeld()) return true
        // Screen off: a detection could only post a notification, so save the
        // battery and listen again as soon as the screen turns on.
        val power = getSystemService(POWER_SERVICE) as? PowerManager
        if (power != null && !power.isInteractive) return true
        if (!backgroundSupported() && !NovaMicArbiter.appVisible()) return true
        val audio = getSystemService(AUDIO_SERVICE) as? AudioManager
        val mode = audio?.mode ?: AudioManager.MODE_NORMAL
        return mode == AudioManager.MODE_IN_CALL || mode == AudioManager.MODE_IN_COMMUNICATION ||
            mode == AudioManager.MODE_RINGTONE
    }

    @SuppressLint("MissingPermission") // checked in micGranted()
    private fun openRecord(): AudioRecord? {
        if (!micGranted(this)) return null
        val min = AudioRecord.getMinBufferSize(
            NovaWakeEngine.SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        if (min <= 0) return null
        return try {
            val r = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                NovaWakeEngine.SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                maxOf(min, CHUNK * 2 * 4),
            )
            if (r.state != AudioRecord.STATE_INITIALIZED) {
                r.release()
                return null
            }
            r.startRecording()
            if (r.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                r.release()
                return null
            }
            r
        } catch (e: Exception) {
            null
        }
    }

    private fun closeRecord(r: AudioRecord) {
        try { r.stop() } catch (ignored: Exception) { }
        try { r.release() } catch (ignored: Exception) { }
        NovaMicArbiter.wakeMicOpen = false
    }

    private fun sleep(ms: Long) {
        try {
            Thread.sleep(ms)
        } catch (e: InterruptedException) {
            active = false
        }
    }

    // ── "Hey NOVA" heard ───────────────────────────────────────────────────

    private fun onWakeWord() {
        if (!running) return
        buzz()
        val locked = (getSystemService(KEYGUARD_SERVICE) as? KeyguardManager)?.isKeyguardLocked == true
        val overlayAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
        if (!locked && (NovaMicArbiter.appVisible() || overlayAllowed)) {
            val requestedAt = SystemClock.elapsedRealtime()
            try {
                startActivity(assistIntent())
            } catch (e: Exception) {
                showTapToTalk()
                return
            }
            // If Android blocked the launch anyway, fall back to the notification.
            main.postDelayed({
                if (NovaAssistActivity.lastStartedAt < requestedAt) showTapToTalk()
            }, 2500)
        } else {
            showTapToTalk()
        }
    }

    private fun assistIntent(): Intent =
        Intent(this, NovaAssistActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra(NovaAssistActivity.EXTRA_REASON, "wake")

    private fun showTapToTalk() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val pi = PendingIntent.getActivity(
            this, 1, assistIntent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(this, CHANNEL_ALERT)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("NOVA heard you")
            .setContentText("Tap to talk to NOVA")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setAutoCancel(true)
            .setTimeoutAfter(20_000)
            .setContentIntent(pi)
            .build()
        try { nm.notify(ALERT_NOTIFICATION_ID, n) } catch (ignored: Exception) { }
    }

    private fun buzz() {
        try {
            val v: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(VIBRATOR_SERVICE) as? Vibrator
            } ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v.vibrate(VibrationEffect.createOneShot(35, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(35)
            }
        } catch (ignored: Exception) { }
    }

    // ── Notifications ──────────────────────────────────────────────────────

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NOTIFICATION_SERVICE) as? NotificationManager ?: return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_LISTEN, "Hey NOVA listening", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while NOVA listens for “Hey NOVA” on this phone."
                setShowBadge(false)
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ALERT, "Hey NOVA heard", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Tap to talk after saying “Hey NOVA” in another app."
                setShowBadge(false)
            },
        )
    }

    private fun listeningNotification(): Notification {
        val open = PendingIntent.getActivity(
            this, 2, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this, 3, Intent(this, NovaWakeService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_LISTEN)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Say “Hey NOVA”")
            .setContentText("NOVA is listening on this phone. Nothing is recorded or sent.")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(open)
            .addAction(0, "Turn off", stop)
            .build()
    }
}
