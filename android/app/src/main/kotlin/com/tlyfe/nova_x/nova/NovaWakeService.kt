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
    private const val KEY_SCREEN_OFF = "screen_off"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    /**
     * "Listen when the screen is off" (off by default): keep listening while
     * the screen is off or locked, wake the screen and open NOVA over the
     * lock screen. Uses more battery.
     */
    fun screenOffEnabled(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY_SCREEN_OFF, false)

    fun setScreenOffEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean(KEY_SCREEN_OFF, enabled).apply()
    }
}

/**
 * "Hey NOVA" — a microphone foreground service that runs the on-device wake
 * word detector (NovaWakeEngine). Nothing is recorded, stored or uploaded
 * while it listens; audio is analysed in memory, 0.1 s at a time.
 *
 * 3.8.0:
 *  - Far voices: the audio passes through NovaMicGain (automatic gain with a
 *    noise ceiling) before the detector.
 *  - Headsets: wired/USB headset microphones are used when plugged in;
 *    Bluetooth headset microphones too (NovaAudioRoute), except while music
 *    or video plays (that would drop the headset to call quality).
 *  - Staying on: the service is sticky. When Android closes NOVA X and may
 *    not give the microphone back (Android 14+ background rules), when the
 *    phone restarts, or when Android silences the microphone, NOVA shows a
 *    one-tap "turn Hey NOVA back on" notification instead of failing quietly.
 *  - Faster replies: the floating window's Flutter engine is started in
 *    advance (NovaAssistEngine), so NOVA opens almost instantly.
 *
 * Android rules this follows:
 *  - It can only be started while NOVA X is on screen or from a notification
 *    tap (Android 14+ forbid starting microphone services from the
 *    background).
 *  - A notification is always shown while it listens.
 *  - Apps can't open screens from the background. On "Hey NOVA" the floating
 *    panel opens directly when NOVA X is visible or the user allowed "Display
 *    over other apps"; otherwise a notification asks the user to tap it.
 *  - Android 7–9 allow one recorder at a time, so there it only listens while
 *    NOVA X is open (other apps' voice notes and calls keep working).
 *  - Screen off: by default it pauses (saves battery). With "Listen when the
 *    screen is off" on, it keeps listening (holding a partial wake lock only
 *    while the screen is off), and on "Hey NOVA" it turns the screen on and
 *    opens NOVA over the lock screen.
 */
class NovaWakeService : Service() {

    companion object {
        const val ACTION_START = "com.tlyfe.nova_x.nova.WAKE_START"
        const val ACTION_STOP = "com.tlyfe.nova_x.nova.WAKE_STOP"
        const val ALERT_NOTIFICATION_ID = 9412

        /** "Hey NOVA is paused — tap to turn it back on" (Android stopped it). */
        const val RESUME_NOTIFICATION_ID = 9413

        private const val LISTEN_NOTIFICATION_ID = 9411
        private const val CHANNEL_LISTEN = "nova_wake"
        private const val CHANNEL_ALERT = "nova_wake_alert"
        private const val CHUNK = 1600 // 0.1 s at 16 kHz
        private const val AFTER_DETECTION_PAUSE_MS = 8000L

        /** How often the microphone choice (headset plugged in, music…) is re-checked. */
        private const val ROUTE_CHECK_MS = 2000L

        /** All-zero audio this long = Android is silencing NOVA's microphone. */
        private const val SILENT_CHUNKS_LIMIT = 50 // 5 s

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
            cancelResumeNotice(context)
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
            cancelResumeNotice(context)
            context.stopService(Intent(context, NovaWakeService::class.java))
        }

        fun cancelResumeNotice(context: Context) {
            try {
                (context.getSystemService(NOTIFICATION_SERVICE) as? NotificationManager)?.cancel(RESUME_NOTIFICATION_ID)
            } catch (ignored: Exception) { }
        }

        /**
         * Android stopped "Hey NOVA" (restart after the system closed NOVA X,
         * phone restart, microphone silenced in the background). Android only
         * lets NOVA X open the microphone again after the user does something,
         * so this notification turns it back on in one tap (the tap starts the
         * service directly — the app doesn't need to open).
         */
        fun showResumeNotice(context: Context) {
            if (!NovaWakePrefs.isEnabled(context) || running) return
            val nm = context.getSystemService(NOTIFICATION_SERVICE) as? NotificationManager ?: return
            createChannels(context)
            val start = Intent(context, NovaWakeService::class.java).setAction(ACTION_START)
            val pi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PendingIntent.getForegroundService(
                    context, 4, start, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            } else {
                PendingIntent.getService(
                    context, 4, start, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            }
            val n = NotificationCompat.Builder(context, CHANNEL_LISTEN)
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setContentTitle("“Hey NOVA” is paused")
                .setContentText("Android paused NOVA's microphone. Tap to turn “Hey NOVA” back on.")
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            try { nm.notify(RESUME_NOTIFICATION_ID, n) } catch (ignored: Exception) { }
        }

        private fun createChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(NOTIFICATION_SERVICE) as? NotificationManager ?: return
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
    }

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var active = false
    private var worker: Thread? = null
    private var cpuLock: PowerManager.WakeLock? = null
    private var cpuLockRenewedAt = 0L
    private val route by lazy { NovaAudioRoute.Session(this) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            NovaWakePrefs.setEnabled(this, false)
            cancelResumeNotice(this)
            stopSelf()
            return START_NOT_STICKY
        }
        // intent == null: Android restarted the service after closing NOVA X.
        if (!NovaWakePrefs.isEnabled(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!micGranted(this)) {
            lastError = "microphone"
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            createChannels(this)
            val notification = listeningNotification()
            // The "microphone" service type exists from Android 11.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(LISTEN_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(LISTEN_NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Android 14+: a microphone service can't start while NOVA X is in
            // the background (e.g. Android restarting it after closing the app).
            lastError = "start_not_allowed"
            showResumeNotice(this)
            stopSelf()
            return START_NOT_STICKY
        }
        cancelResumeNotice(this)
        // NOVA's window opens much faster when its engine is already running.
        main.post { NovaAssistEngine.prewarm(applicationContext) }
        if (worker == null) {
            active = true
            running = true
            lastError = null
            worker = Thread({ listenLoop() }, "nova-wake").also { it.start() }
        }
        // Sticky: if Android closes NOVA X to free memory it restarts this
        // service; when the microphone may not be used then, the user gets the
        // one-tap "turn it back on" notification instead of silently losing
        // "Hey NOVA".
        return START_STICKY
    }

    override fun onDestroy() {
        active = false
        running = false
        worker?.interrupt()
        worker = null
        NovaMicArbiter.wakeMicOpen = false
        setCpuAwake(false)
        try { route.end() } catch (ignored: Exception) { }
        if (!NovaWakePrefs.isEnabled(this)) NovaAssistEngine.releaseIfIdle()
        super.onDestroy()
    }

    // ── Listening ──────────────────────────────────────────────────────────

    private fun listenLoop() {
        var engine: NovaWakeEngine? = NovaWakeEngine.create(applicationContext)
        if (engine == null) {
            lastError = "unsupported"
            main.post { stopSelf() }
            return
        }
        var record: AudioRecord? = null
        var routeKey = ""
        var routeCheckedAt = 0L
        val gain = NovaMicGain()
        val pcm = ShortArray(CHUNK)
        var failures = 0
        var engineErrors = 0
        var silentChunks = 0
        var stoppedBySilence = false
        try {
            while (active) {
                val det = engine ?: break
                if (shouldPause()) {
                    if (record != null) {
                        closeRecord(record)
                        record = null
                        det.restart()
                    }
                    route.end()
                    routeKey = ""
                    setCpuAwake(false)
                    sleep(150)
                    continue
                }
                // Screen off (option on): keep the processor awake so listening continues.
                setCpuAwake(!screenIsOn())

                // Headset plugged in / unplugged, music started / stopped: re-pick the microphone.
                val now = SystemClock.elapsedRealtime()
                if (record != null && now - routeCheckedAt >= ROUTE_CHECK_MS) {
                    routeCheckedAt = now
                    if (wantedRouteKey() != routeKey) {
                        closeRecord(record)
                        record = null
                        det.restart()
                    }
                }
                if (record == null) {
                    routeKey = wantedRouteKey()
                    routeCheckedAt = now
                    record = openRecord(routeKey)
                    if (record == null) {
                        failures++
                        sleep(if (failures < 5) 1000L else 5000L)
                        continue
                    }
                    failures = 0
                    silentChunks = 0
                    gain.reset()
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
                // Android delivers exact silence when it blocks a background
                // microphone (or the privacy switch is off): tell the user
                // instead of pretending to listen.
                var allZero = true
                for (i in 0 until n) {
                    if (pcm[i].toInt() != 0) { allZero = false; break }
                }
                silentChunks = if (allZero) silentChunks + 1 else 0
                if (silentChunks >= SILENT_CHUNKS_LIMIT && !NovaMicArbiter.appVisible()) {
                    if (othersRecording(record)) {
                        // Another app is recording (voice note, call): Android
                        // gives NOVA silence until it finishes — just wait.
                        silentChunks = 0
                    } else {
                        lastError = "mic_blocked"
                        stoppedBySilence = true
                        break
                    }
                }
                // Lift far / quiet voices before the detector hears them.
                val samples = gain.process(pcm, n)
                val heard = try {
                    det.accept(samples)
                } catch (t: Throwable) {
                    // Detector error: load a fresh detector instead of stopping.
                    engineErrors++
                    try { det.release() } catch (ignored: Throwable) { }
                    engine = if (engineErrors <= 3) NovaWakeEngine.create(applicationContext) else null
                    if (engine == null) throw t
                    false
                }
                if (heard) {
                    NovaMicArbiter.pauseFor(AFTER_DETECTION_PAUSE_MS)
                    closeRecord(record)
                    record = null
                    route.end()
                    routeKey = ""
                    det.restart()
                    main.post { onWakeWord() }
                }
            }
        } catch (t: Throwable) {
            lastError = "engine_error"
        } finally {
            record?.let { closeRecord(it) }
            try { route.end() } catch (ignored: Exception) { }
            NovaMicArbiter.wakeMicOpen = false
            setCpuAwake(false)
            engine?.release()
            // Ended without being asked to (engine/microphone failure): never
            // leave a "listening" notification up while nothing listens.
            if (active) {
                active = false
                running = false
                main.post {
                    stopSelf()
                    if (stoppedBySilence) showResumeNotice(this)
                }
            }
        }
    }

    /**
     * Which microphone "Hey NOVA" should use now: a wired headset, a
     * Bluetooth headset (when allowed and nothing is playing), or the
     * phone's own microphone ("").
     */
    private fun wantedRouteKey(): String {
        val d = NovaAudioRoute.headsetInput(this) ?: return ""
        if (!NovaAudioRoute.isBluetooth(d)) return "wired:${d.id}"
        if (!NovaAudioRoute.headsetEnabled(this)) return ""
        if (NovaAudioRoute.musicActive(this) || NovaAudioRoute.inCall(this)) return ""
        return "bt:${d.id}"
    }

    /** True when some other app is recording too (Android 10+ can tell). */
    private fun othersRecording(record: AudioRecord): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val am = getSystemService(AUDIO_SERVICE) as? AudioManager ?: return false
        return try {
            val mine = record.audioSessionId
            am.activeRecordingConfigurations.any { it.clientAudioSessionId != mine }
        } catch (e: Exception) {
            false
        }
    }

    private fun shouldPause(): Boolean {
        if (NovaMicArbiter.isHeld()) return true
        // Screen off: pause to save battery unless the user chose
        // "Listen when the screen is off".
        if (!screenIsOn() && !NovaWakePrefs.screenOffEnabled(this)) return true
        if (!backgroundSupported() && !NovaMicArbiter.appVisible()) return true
        val audio = getSystemService(AUDIO_SERVICE) as? AudioManager
        val mode = audio?.mode ?: AudioManager.MODE_NORMAL
        return mode == AudioManager.MODE_IN_CALL || mode == AudioManager.MODE_IN_COMMUNICATION ||
            mode == AudioManager.MODE_RINGTONE
    }

    private fun screenIsOn(): Boolean =
        (getSystemService(POWER_SERVICE) as? PowerManager)?.isInteractive ?: true

    /** Partial wake lock while listening with the screen off (renewed, never left held). */
    private fun setCpuAwake(awake: Boolean) {
        try {
            if (!awake) {
                cpuLock?.let { if (it.isHeld) it.release() }
                return
            }
            val now = SystemClock.elapsedRealtime()
            val lock = cpuLock ?: (getSystemService(POWER_SERVICE) as? PowerManager)
                ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "novax:heynova")
                ?.also { it.setReferenceCounted(false); cpuLock = it }
                ?: return
            if (!lock.isHeld || now - cpuLockRenewedAt > 60_000L) {
                lock.acquire(10 * 60 * 1000L)
                cpuLockRenewedAt = now
            }
        } catch (ignored: Exception) { }
    }

    @SuppressLint("MissingPermission") // checked in micGranted()
    private fun openRecord(routeKey: String): AudioRecord? {
        if (!micGranted(this)) return null
        val min = AudioRecord.getMinBufferSize(
            NovaWakeEngine.SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
        )
        if (min <= 0) return null
        val device = when {
            routeKey.isEmpty() -> { route.end(); null }
            // Waits up to 1.5 s for the Bluetooth link (on this worker thread).
            routeKey.startsWith("bt:") -> route.begin(allowBluetooth = true, waitMs = 1500L)
            else -> route.begin(allowBluetooth = false)
        }
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
            if (device != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try { r.setPreferredDevice(device) } catch (ignored: Exception) { }
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
        val screenOn = screenIsOn()
        val overlayAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
        val lockScreenMode = NovaWakePrefs.screenOffEnabled(this)
        when {
            // Phone in use: open the panel as before.
            !locked && screenOn && (NovaMicArbiter.appVisible() || overlayAllowed) -> launchPanel(false)
            // Screen off or locked, option on: wake the screen, NOVA over the lock screen.
            lockScreenMode && overlayAllowed -> {
                wakeScreen()
                launchPanel(true)
            }
            else -> {
                if (lockScreenMode) wakeScreen()
                showTapToTalk()
            }
        }
    }

    private fun launchPanel(overLockScreen: Boolean) {
        val requestedAt = SystemClock.elapsedRealtime()
        try {
            startActivity(assistIntent(overLockScreen))
        } catch (e: Exception) {
            showTapToTalk()
            return
        }
        // If Android blocked the launch anyway, fall back to the notification.
        main.postDelayed({
            if (NovaAssistActivity.lastStartedAt < requestedAt) showTapToTalk()
        }, 2500)
    }

    /** Turns the screen on for a moment (the NOVA window then keeps it on). */
    @Suppress("DEPRECATION")
    private fun wakeScreen() {
        try {
            (getSystemService(POWER_SERVICE) as? PowerManager)
                ?.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                    "novax:heynova-wake",
                )
                ?.acquire(4000L)
        } catch (ignored: Exception) { }
    }

    private fun assistIntent(overLockScreen: Boolean = false): Intent =
        Intent(this, NovaAssistActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra(NovaAssistActivity.EXTRA_REASON, "wake")
            .putExtra(NovaAssistActivity.EXTRA_LOCK_SCREEN, overLockScreen)

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
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
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
