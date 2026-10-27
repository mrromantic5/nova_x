package com.tlyfe.nova_x.capture

import android.Manifest
import android.app.Activity
import android.app.KeyguardManager
import android.app.Notification
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.tlyfe.nova_x.capture.CaptureContract.ACTIVE
import com.tlyfe.nova_x.capture.CaptureContract.AWAITING_CONSENT
import com.tlyfe.nova_x.capture.CaptureContract.CANCELLED
import com.tlyfe.nova_x.capture.CaptureContract.FAILED
import com.tlyfe.nova_x.capture.CaptureContract.FINALIZING
import com.tlyfe.nova_x.capture.CaptureContract.IDLE
import com.tlyfe.nova_x.capture.CaptureContract.PAUSED
import com.tlyfe.nova_x.capture.CaptureContract.RECORDING
import com.tlyfe.nova_x.capture.CaptureContract.SAVED
import com.tlyfe.nova_x.capture.CaptureContract.STARTING
import com.tlyfe.nova_x.capture.CaptureContract.STOPPING
import com.tlyfe.nova_x.MainActivity
import com.tlyfe.nova_x.nova.NovaMicArbiter
import java.io.File
import java.lang.ref.WeakReference
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import kotlin.math.max

/**
 * The single, authoritative NOVA Capture state for the whole process (main
 * app engine, floating NOVA panel engine, notification actions and the
 * overlay all go through here). Every public method runs on the main thread
 * and validates the current state before doing anything; invalid requests get
 * a stable error code, never a fake success.
 *
 * Recording lifecycle:
 *   idle → awaiting_consent → starting (countdown) → recording ⇄ paused
 *        → stopping → finalizing → saved
 *   (any active state → cancelled / failed)
 *
 * Nothing is captured before Android's consent dialog returns OK, and every
 * session asks again (Android 14+ requires it; NOVA X does it on every version).
 */
object CaptureCoordinator {

    interface Listener {
        fun onCapture(method: String, payload: Map<String, Any?>)
    }

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val listeners = CopyOnWriteArrayList<Listener>()

    @Volatile var state: String = IDLE
        private set
    private var sessionId = 0
    private var app: Context? = null
    private var config = RecordingConfig()

    private var projection: MediaProjection? = null
    private var projectionCb: MediaProjection.Callback? = null
    private var releasingProjection = false
    private var consentCode = 0
    private var consentData: Intent? = null
    private var serviceMode: String? = null

    private var engine: ScreenRecorderEngine? = null
    private var spec: VideoSpec? = null
    private var audioMode = CaptureContract.AUDIO_NONE
    private var micHeld = false
    private var recordStart = 0L
    private var pausedAccum = 0L
    private var pauseStart = 0L
    private var finalElapsed = 0L
    private var countdown = 0
    private var stopReason = "user"
    private var lastError: Pair<String, String>? = null
    private var lastItem: Map<String, Any?>? = null
    private val warnings = ArrayList<String>()
    private var pendingStart: ((Map<String, Any?>) -> Unit)? = null
    private var unsavedFile: File? = null
    private var lostOnStart = 0
    private var cleanedUp = false

    private var overlay: FloatingControlsOverlay? = null
    private var ticks = 0

    // Full-device screenshot
    private var shotDone: ((Map<String, Any?>) -> Unit)? = null
    private var shotHide = true
    private var shotDelay = 0
    private var hostActivity: WeakReference<Activity>? = null

    // ── Listeners ─────────────────────────────────────────────────────────────

    fun addListener(l: Listener) { listeners.addIfAbsent(l) }
    fun removeListener(l: Listener) { listeners.remove(l) }

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block)
    }

    private fun emitState() {
        val snap = snapshot()
        onMain { for (l in listeners) try { l.onCapture("capture.state", snap) } catch (e: Exception) { } }
    }

    private fun emitEvent(type: String, vararg extra: Pair<String, Any?>) {
        val payload = mapOf("type" to type, "sessionId" to sessionId, "state" to state, *extra)
        onMain { for (l in listeners) try { l.onCapture("capture.event", payload) } catch (e: Exception) { } }
    }

    // ── State ─────────────────────────────────────────────────────────────────

    fun elapsedMs(): Long = when (state) {
        RECORDING -> SystemClock.elapsedRealtime() - recordStart - pausedAccum
        PAUSED -> pauseStart - recordStart - pausedAccum
        STOPPING, FINALIZING, SAVED -> finalElapsed
        else -> 0L
    }.coerceAtLeast(0L)

    fun isRecordingActive(): Boolean = state == RECORDING || state == PAUSED

    fun snapshot(): Map<String, Any?> {
        val s = spec
        return mapOf(
            "state" to state,
            "sessionId" to sessionId,
            "elapsedMs" to elapsedMs(),
            "paused" to (state == PAUSED),
            "countdown" to countdown,
            "audio" to audioMode,
            "micInUse" to (micHeld && state == RECORDING),
            "width" to (s?.width ?: 0),
            "height" to (s?.height ?: 0),
            "fps" to (s?.fps ?: 0),
            "bitrate" to (s?.bitrate ?: 0),
            "errorCode" to lastError?.first,
            "userMessage" to lastError?.second,
            "lastItem" to lastItem,
            "warnings" to ArrayList(warnings),
            "stopReason" to stopReason,
            "screenshotBusy" to (shotDone != null),
            "overlayShowing" to (overlay?.isShowing == true),
            "hasUnsaved" to (unsavedFile?.exists() == true),
        )
    }

    private fun setState(to: String): Boolean {
        if (state == to) return true
        if (!CaptureContract.canMove(state, to)) return false
        state = to
        emitState()
        updateNotification()
        return true
    }

    private fun warn(message: String) {
        if (warnings.contains(message)) return
        warnings.add(message)
        emitEvent(CaptureContract.EVENT_WARNING, "userMessage" to message)
        emitState()
    }

    private fun sidOk(sid: Int?): Boolean = sid == null || sid == sessionId

    // ── Checks ────────────────────────────────────────────────────────────────

    fun granted(ctx: Context, permission: String): Boolean =
        ctx.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    fun needsStoragePermission(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q && !granted(ctx, Manifest.permission.WRITE_EXTERNAL_STORAGE)

    private fun isLocked(ctx: Context): Boolean =
        (ctx.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)?.isKeyguardLocked == true

    /** Called when a NOVA X screen with a capture channel opens. */
    fun attach(ctx: Context, activity: Activity?) {
        app = ctx.applicationContext
        if (activity is MainActivity) hostActivity = WeakReference(activity)
        if (!cleanedUp && state !in ACTIVE) {
            cleanedUp = true
            val c = ctx.applicationContext
            io.execute {
                val n = CaptureMediaRepository.cleanupTemp(c, unsavedFile)
                main.post { lostOnStart = n }
            }
        }
    }

    /** Recordings that were in progress when NOVA X was closed by the system (reported once). */
    fun takeLostCount(): Int { val n = lostOnStart; lostOnStart = 0; return n }

    // ── Recording ─────────────────────────────────────────────────────────────

    fun startRecording(activity: Activity, cfg: RecordingConfig, done: (Map<String, Any?>) -> Unit) {
        val ctx = activity.applicationContext
        app = ctx
        if (state in ACTIVE) {
            return done(CaptureContract.error(CaptureContract.E_BUSY, "A screen recording is already in progress.", "state" to state))
        }
        if (shotDone != null || serviceMode != null) {
            return done(CaptureContract.error(CaptureContract.E_BUSY, "NOVA X is finishing a screenshot. Try again in a moment."))
        }
        if (isLocked(ctx)) return done(CaptureContract.error(CaptureContract.E_LOCKED, "Unlock your phone first, then start the recording."))
        val free = CaptureMediaRepository.freeBytes(ctx)
        if (free in 0 until CaptureContract.MIN_FREE_TO_START) {
            return done(CaptureContract.error(CaptureContract.E_LOW_STORAGE,
                "Your phone is almost full. Free up at least 300 MB to record your screen.", "freeBytes" to free))
        }
        if (CaptureContract.usesDevice(cfg.audio) && !CaptureAudioSource.deviceAudioSupported()) {
            return done(CaptureContract.error(CaptureContract.E_AUDIO, "Recording sound from apps needs Android 10 or newer."))
        }
        if (cfg.audio != CaptureContract.AUDIO_NONE && !granted(ctx, Manifest.permission.RECORD_AUDIO)) {
            emitEvent(CaptureContract.EVENT_PERMISSION_REQUIRED, "permission" to "mic")
            return done(CaptureContract.error(CaptureContract.E_PERMISSION,
                "Allow the microphone to record sound, or choose “No audio”.", "permission" to "mic"))
        }
        if (needsStoragePermission(ctx)) {
            emitEvent(CaptureContract.EVENT_PERMISSION_REQUIRED, "permission" to "storage")
            return done(CaptureContract.error(CaptureContract.E_PERMISSION,
                "Allow storage access so NOVA X can save the video.", "permission" to "storage"))
        }

        config = cfg
        sessionId++
        lastError = null
        lastItem = null
        warnings.clear()
        stopReason = "user"
        countdown = 0
        spec = null
        audioMode = CaptureContract.AUDIO_NONE
        if (state != IDLE) state = IDLE // leave saved/cancelled/failed
        setState(AWAITING_CONSENT)
        pendingStart = done
        emitEvent(CaptureContract.EVENT_PERMISSION_REQUIRED, "permission" to "screen_capture")
        if (!launchConsent(activity, "record")) {
            failRecording(CaptureContract.E_NO_ACTIVITY, "Android's screen-capture request couldn't be shown.")
            return
        }
        main.removeCallbacks(consentWatchdog)
        main.postDelayed(consentWatchdog, 120_000)
    }

    private fun launchConsent(activity: Activity, mode: String): Boolean = try {
        activity.startActivity(Intent(activity, CaptureConsentActivity::class.java).putExtra(CaptureConsentActivity.EXTRA_MODE, mode))
        true
    } catch (e: Exception) {
        false
    }

    private val consentWatchdog = Runnable {
        if (state == AWAITING_CONSENT) {
            lastError = Pair(CaptureContract.E_TIMEOUT, "The screen-capture request wasn't answered, so nothing was recorded.")
            setState(CANCELLED)
            emitEvent(CaptureContract.EVENT_RECORDING_CANCELLED, "errorCode" to CaptureContract.E_TIMEOUT)
            finishStart(CaptureContract.error(CaptureContract.E_TIMEOUT, lastError!!.second))
        }
        if (shotDone != null && serviceMode == null) {
            finishShot(CaptureContract.error(CaptureContract.E_TIMEOUT, "The screen-capture request wasn't answered."))
        }
    }

    private val serviceWatchdog = Runnable {
        if (projection == null && serviceMode != null) onServiceFailed()
    }

    /** Answer from Android's consent dialog (CaptureConsentActivity). */
    fun onConsentResult(ctx: Context, mode: String, resultCode: Int, data: Intent?, unsupported: Boolean = false) {
        app = ctx.applicationContext
        main.removeCallbacks(consentWatchdog)
        val granted = resultCode == Activity.RESULT_OK && data != null && !unsupported
        if (mode == "record") {
            if (state != AWAITING_CONSENT) return
            if (!granted) {
                emitEvent(CaptureContract.EVENT_PERMISSION_DENIED, "permission" to "screen_capture")
                if (unsupported) {
                    failRecording(CaptureContract.E_UNSUPPORTED, "Screen recording isn't available on this phone.")
                } else {
                    lastError = Pair(CaptureContract.E_CONSENT_DENIED,
                        "Screen recording didn't start because the screen-capture request was declined.")
                    setState(CANCELLED)
                    emitEvent(CaptureContract.EVENT_RECORDING_CANCELLED, "errorCode" to CaptureContract.E_CONSENT_DENIED)
                    finishStart(CaptureContract.error(CaptureContract.E_CONSENT_DENIED, lastError!!.second))
                }
                return
            }
            emitEvent(CaptureContract.EVENT_PERMISSION_GRANTED, "permission" to "screen_capture")
            consentCode = resultCode
            consentData = data
            countdown = config.countdownSec
            setState(STARTING)
            serviceMode = "record"
            try {
                CaptureService.start(ctx, "record", CaptureContract.usesMic(config.audio))
            } catch (e: Exception) {
                failRecording(CaptureContract.E_ERROR, "Screen recording couldn't start.")
                return
            }
            main.removeCallbacks(serviceWatchdog)
            main.postDelayed(serviceWatchdog, 10_000)
        } else {
            if (shotDone == null) return
            if (!granted) {
                emitEvent(CaptureContract.EVENT_PERMISSION_DENIED, "permission" to "screen_capture")
                finishShot(if (unsupported) {
                    CaptureContract.error(CaptureContract.E_UNSUPPORTED, "Screen capture isn't available on this phone.")
                } else {
                    CaptureContract.error(CaptureContract.E_CONSENT_DENIED,
                        "The screenshot wasn't taken because the screen-capture request was declined.")
                })
                return
            }
            emitEvent(CaptureContract.EVENT_PERMISSION_GRANTED, "permission" to "screen_capture")
            consentCode = resultCode
            consentData = data
            serviceMode = "screenshot"
            try {
                CaptureService.start(ctx, "screenshot", false)
            } catch (e: Exception) {
                serviceMode = null
                finishShot(CaptureContract.error(CaptureContract.E_ERROR, "The screenshot couldn't be taken."))
                return
            }
            main.removeCallbacks(serviceWatchdog)
            main.postDelayed(serviceWatchdog, 10_000)
        }
    }

    /** The foreground service is running: now (and only now) the projection may be created. */
    fun onServiceReady(service: CaptureService, mode: String) {
        main.removeCallbacks(serviceWatchdog)
        val data = consentData
        consentData = null
        if (mode != serviceMode || data == null) {
            CaptureService.stop(service)
            return
        }
        val p = try {
            (service.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager)
                .getMediaProjection(consentCode, data)
        } catch (e: Exception) {
            null
        }
        if (p == null) {
            onServiceFailed()
            return
        }
        val cb = object : MediaProjection.Callback() {
            override fun onStop() {
                main.post { onProjectionStopped() }
            }
        }
        p.registerCallback(cb, main) // Android 14+: must be registered before capturing
        projection = p
        projectionCb = cb
        if (mode == "record") {
            if (state != STARTING) {
                releaseProjection()
                return
            }
            main.removeCallbacks(countdownTick)
            main.post(countdownTick)
        } else {
            if (shotDone == null) {
                releaseProjection()
                return
            }
            if (shotHide) hostActivity?.get()?.let { if (!it.isFinishing) it.moveTaskToBack(true) }
            main.postDelayed({ grabShot() }, max(shotDelay, if (shotHide) 900 else 350).toLong())
            updateNotification()
        }
    }

    fun onServiceFailed() {
        main.removeCallbacks(serviceWatchdog)
        if (serviceMode == "screenshot" || (shotDone != null && state !in ACTIVE)) {
            releaseProjection()
            finishShot(CaptureContract.error(CaptureContract.E_ERROR, "The screenshot couldn't be taken."))
        } else if (state in ACTIVE) {
            failRecording(CaptureContract.E_ERROR, "Screen recording couldn't start on this phone.")
        }
    }

    fun onServiceDestroyed() {
        // Destroyed while we still hold a projection (not by us): save what exists.
        if (projection != null && !releasingProjection && isRecordingActive()) stop(null, "interrupted")
    }

    private val countdownTick = object : Runnable {
        override fun run() {
            if (state != STARTING) return
            if (countdown <= 0) {
                beginRecording()
                return
            }
            emitState()
            updateNotification()
            countdown--
            main.postDelayed(this, 1_000)
        }
    }

    private fun beginRecording() {
        val ctx = app ?: return failRecording(CaptureContract.E_ERROR, "Screen recording couldn't start.")
        val p = projection ?: return failRecording(CaptureContract.E_INTERRUPTED, "Screen capture was stopped before recording began.")
        val m = ScreenshotGrabber.realMetrics(ctx)
        val portraitNow = ctx.resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
        val s = ScreenRecorderEngine.choose(m.widthPixels, m.heightPixels, m.densityDpi, config, portraitNow)

        var mode = config.audio
        if (CaptureContract.usesMic(mode) && (CaptureService.micBlocked || !granted(ctx, Manifest.permission.RECORD_AUDIO))) {
            warn("Android didn't allow the microphone for this recording, so your voice isn't recorded.")
            mode = if (CaptureContract.usesDevice(mode)) CaptureContract.AUDIO_DEVICE else CaptureContract.AUDIO_NONE
        }
        if (CaptureContract.usesMic(mode)) {
            // "Hey NOVA" steps aside so the recording gets the microphone.
            NovaMicArbiter.hold("capture_mic", true)
            micHeld = true
        }
        var src: CaptureAudioSource? = null
        if (mode != CaptureContract.AUDIO_NONE) {
            val a = CaptureAudioSource(mode, p)
            if (a.open()) src = a else a.release()
            a.warning?.let { warn(it) }
        }
        if (src == null && micHeld) {
            NovaMicArbiter.hold("capture_mic", false)
            micHeld = false
        }
        audioMode = if (src == null) CaptureContract.AUDIO_NONE else mode

        val file = File(CaptureMediaRepository.tempDir(ctx), "rec_${sessionId}_${System.currentTimeMillis()}.mp4")
        val sid = sessionId
        val e = ScreenRecorderEngine(p, s, src, file, object : ScreenRecorderEngine.Listener {
            override fun onFinished(file: File, durationUs: Long, interrupted: Boolean) {
                main.post { if (sid == sessionId) onEngineFinished(file, durationUs, interrupted) else file.delete() }
            }

            override fun onFailed(code: String, message: String) {
                main.post { if (sid == sessionId && state != CANCELLED) failRecording(code, message) }
            }

            override fun onWarning(message: String) {
                main.post { if (sid == sessionId) warn(message) }
            }
        })
        try {
            e.start()
        } catch (ex: Exception) {
            e.cancel()
            src?.release()
            failRecording(CaptureContract.E_ENCODER,
                "This phone's video encoder couldn't start. Try a lower resolution in Recording settings.")
            return
        }
        engine = e
        spec = s
        recordStart = SystemClock.elapsedRealtime()
        pausedAccum = 0
        finalElapsed = 0
        setState(RECORDING)
        emitEvent(CaptureContract.EVENT_RECORDING_STARTED, "width" to s.width, "height" to s.height, "fps" to s.fps, "audio" to audioMode)
        finishStart(CaptureContract.ok("state" to state, "sessionId" to sessionId))
        ticks = 0
        main.removeCallbacks(ticker)
        main.postDelayed(ticker, 1_000)
    }

    private fun finishStart(result: Map<String, Any?>) {
        val cb = pendingStart ?: return
        pendingStart = null
        cb(result)
    }

    fun pause(sid: Int?): Map<String, Any?> {
        if (!sidOk(sid)) return stale()
        if (state != RECORDING) {
            return CaptureContract.error(CaptureContract.E_INVALID_STATE,
                if (state == PAUSED) "The recording is already paused." else "Nothing is being recorded right now.", "state" to state)
        }
        engine?.pause()
        pauseStart = SystemClock.elapsedRealtime()
        setState(PAUSED)
        emitEvent(CaptureContract.EVENT_RECORDING_PAUSED, "elapsedMs" to elapsedMs())
        syncOverlay()
        return CaptureContract.ok("state" to state, "elapsedMs" to elapsedMs())
    }

    fun resume(sid: Int?): Map<String, Any?> {
        if (!sidOk(sid)) return stale()
        if (state != PAUSED) {
            return CaptureContract.error(CaptureContract.E_INVALID_STATE,
                if (state == RECORDING) "The recording isn't paused." else "Nothing is being recorded right now.", "state" to state)
        }
        pausedAccum += SystemClock.elapsedRealtime() - pauseStart
        engine?.resume()
        setState(RECORDING)
        emitEvent(CaptureContract.EVENT_RECORDING_RESUMED, "elapsedMs" to elapsedMs())
        syncOverlay()
        return CaptureContract.ok("state" to state, "elapsedMs" to elapsedMs())
    }

    /** Stop and save. Repeated stops are harmless (they report the current state). */
    fun stop(sid: Int?, reason: String): Map<String, Any?> {
        if (!sidOk(sid)) return stale()
        return when (state) {
            RECORDING, PAUSED -> {
                finalElapsed = elapsedMs()
                stopReason = reason
                setState(STOPPING)
                if (reason == "interrupted") {
                    emitEvent(CaptureContract.EVENT_RECORDING_INTERRUPTED, "elapsedMs" to finalElapsed)
                }
                emitEvent(CaptureContract.EVENT_RECORDING_STOPPED, "reason" to reason, "elapsedMs" to finalElapsed)
                overlay?.hide()
                overlay = null
                main.removeCallbacks(ticker)
                engine?.stop() ?: failRecording(CaptureContract.E_SAVE, "The video couldn't be finished.")
                main.removeCallbacks(stopWatchdog)
                main.postDelayed(stopWatchdog, 20_000)
                CaptureContract.ok("state" to state, "elapsedMs" to finalElapsed)
            }
            STARTING -> cancel(sid)
            STOPPING, FINALIZING -> CaptureContract.ok("state" to state, "alreadyStopping" to true)
            AWAITING_CONSENT -> CaptureContract.error(CaptureContract.E_INVALID_STATE,
                "Answer Android's screen-capture question first.", "state" to state)
            else -> CaptureContract.error(CaptureContract.E_INVALID_STATE, "Nothing is being recorded right now.", "state" to state)
        }
    }

    private val stopWatchdog = Runnable {
        if (state == STOPPING) {
            engine?.cancel()
            engine = null
            failRecording(CaptureContract.E_SAVE, "The video couldn't be finished.")
        }
    }

    /** Ends without saving. */
    fun cancel(sid: Int?): Map<String, Any?> {
        if (!sidOk(sid)) return stale()
        return when (state) {
            RECORDING, PAUSED, STARTING -> {
                main.removeCallbacks(countdownTick)
                engine?.cancel()
                engine = null
                lastError = null
                setState(CANCELLED)
                emitEvent(CaptureContract.EVENT_RECORDING_CANCELLED)
                releaseProjection()
                finishStart(CaptureContract.error(CaptureContract.E_CANCELLED, "The recording was cancelled."))
                CaptureContract.ok("state" to state)
            }
            AWAITING_CONSENT -> CaptureContract.error(CaptureContract.E_INVALID_STATE,
                "Answer Android's screen-capture question first.", "state" to state)
            STOPPING, FINALIZING -> CaptureContract.error(CaptureContract.E_INVALID_STATE,
                "The recording is already being saved.", "state" to state)
            else -> CaptureContract.error(CaptureContract.E_INVALID_STATE, "Nothing is being recorded right now.", "state" to state)
        }
    }

    private fun stale() = CaptureContract.error(CaptureContract.E_STALE_SESSION,
        "That recording has already ended.", "state" to state, "sessionId" to sessionId)

    private fun onEngineFinished(file: File, durationUs: Long, interrupted: Boolean) {
        main.removeCallbacks(stopWatchdog)
        if (isRecordingActive()) {
            // The encoder ended by itself (error part-way): keep what was recorded.
            finalElapsed = elapsedMs()
            stopReason = "interrupted"
            setState(STOPPING)
            emitEvent(CaptureContract.EVENT_RECORDING_INTERRUPTED, "elapsedMs" to finalElapsed)
        }
        if (state != STOPPING) {
            file.delete()
            return
        }
        if (interrupted) warn("The recording stopped early, but everything up to that point was saved.")
        engine = null
        setState(FINALIZING)
        releaseProjection()
        val ctx = app ?: return failRecording(CaptureContract.E_SAVE, "The video couldn't be saved.")
        val durationMs = if (durationUs > 0) durationUs / 1000 else finalElapsed
        val sid = sessionId
        io.execute {
            val r = CaptureMediaRepository.saveVideo(ctx, file)
            val ok = r["success"] == true
            if (ok) file.delete()
            main.post {
                if (sid != sessionId) return@post
                if (ok) {
                    unsavedFile = null
                    @Suppress("UNCHECKED_CAST")
                    val item = ((r["item"] as? Map<String, Any?>) ?: emptyMap()) + ("durationMs" to durationMs)
                    lastItem = item
                    setState(SAVED)
                    emitEvent(CaptureContract.EVENT_RECORDING_SAVED, "item" to item, "reason" to stopReason)
                    emitEvent(CaptureContract.EVENT_MEDIA_AVAILABLE, "item" to item)
                    CaptureNotifications.saved(ctx, "Recording saved",
                        "${CaptureNotifications.format(durationMs)} · Movies/NOVA X/Recordings. Tap to watch or share.")
                } else {
                    unsavedFile = file
                    failRecording(r["errorCode"] as? String ?: CaptureContract.E_SAVE,
                        "The recording couldn't be saved to your phone. Free up space, then tap Try again.")
                }
            }
        }
    }

    /** Saves a recording that failed to save earlier (kept privately until then). */
    fun retrySave(done: (Map<String, Any?>) -> Unit) {
        val ctx = app
        val f = unsavedFile
        if (ctx == null || f == null || !f.exists()) {
            return done(CaptureContract.error(CaptureContract.E_NOT_FOUND, "There is no unsaved recording."))
        }
        io.execute {
            val r = CaptureMediaRepository.saveVideo(ctx, f)
            if (r["success"] == true) f.delete()
            main.post {
                if (r["success"] == true) {
                    unsavedFile = null
                    @Suppress("UNCHECKED_CAST")
                    (r["item"] as? Map<String, Any?>)?.let {
                        lastItem = it
                        emitEvent(CaptureContract.EVENT_RECORDING_SAVED, "item" to it, "reason" to "retry")
                        emitEvent(CaptureContract.EVENT_MEDIA_AVAILABLE, "item" to it)
                    }
                }
                emitState()
                done(r)
            }
        }
    }

    fun discardUnsaved(): Map<String, Any?> {
        unsavedFile?.delete()
        unsavedFile = null
        emitState()
        return CaptureContract.ok()
    }

    private fun failRecording(code: String, message: String) {
        main.removeCallbacks(countdownTick)
        main.removeCallbacks(ticker)
        main.removeCallbacks(stopWatchdog)
        lastError = Pair(code, message)
        engine?.cancel()
        engine = null
        if (state in ACTIVE) setState(FAILED) else emitState()
        emitEvent(CaptureContract.EVENT_RECORDING_FAILED, "errorCode" to code, "userMessage" to message)
        releaseProjection()
        finishStart(CaptureContract.error(code, message))
    }

    private fun onProjectionStopped() {
        if (releasingProjection) return
        projectionCb = null
        projection = null
        when {
            isRecordingActive() -> stop(null, "interrupted")
            state == STARTING -> failRecording(CaptureContract.E_INTERRUPTED, "Screen capture was stopped before recording began.")
            shotDone != null -> {
                releaseProjection()
                finishShot(CaptureContract.error(CaptureContract.E_INTERRUPTED, "Screen capture was stopped before the screenshot was taken."))
            }
        }
    }

    private fun releaseProjection() {
        releasingProjection = true
        val p = projection
        projectionCb?.let { cb -> try { p?.unregisterCallback(cb) } catch (e: Exception) { } }
        try { p?.stop() } catch (e: Exception) { }
        projection = null
        projectionCb = null
        releasingProjection = false
        app?.let { CaptureService.stop(it) }
        serviceMode = null
        main.removeCallbacks(ticker)
        overlay?.hide()
        overlay = null
        if (micHeld) {
            NovaMicArbiter.hold("capture_mic", false)
            micHeld = false
        }
    }

    // ── Ticker: overlay, storage and duration limits ──────────────────────────

    private val ticker = object : Runnable {
        override fun run() {
            if (!isRecordingActive()) return
            ticks++
            syncOverlay()
            val ctx = app
            if (ctx != null && ticks % 5 == 0) {
                val free = CaptureMediaRepository.freeBytes(ctx)
                if (free in 0 until CaptureContract.MIN_FREE_WHILE_RECORDING) {
                    warn("Your phone was almost out of space, so the recording was stopped and saved.")
                    stop(null, "low_storage")
                    return
                }
            }
            if (config.maxDurationSec > 0 && state == RECORDING && elapsedMs() >= config.maxDurationSec * 1000L) {
                warn("The recording reached the time limit you set, so it was stopped and saved.")
                stop(null, "max_duration")
                return
            }
            main.postDelayed(this, 1_000)
        }
    }

    private fun syncOverlay() {
        val ctx = app ?: return
        val want = config.overlayEnabled && isRecordingActive() &&
            FloatingControlsOverlay.permitted(ctx) && !NovaMicArbiter.appVisible()
        if (!want) {
            if (overlay != null) { overlay?.hide(); overlay = null }
            return
        }
        val o = overlay ?: FloatingControlsOverlay(ctx).also {
            it.show(object : FloatingControlsOverlay.Actions {
                override fun onPauseResume() {
                    if (state == RECORDING) pause(null) else if (state == PAUSED) resume(null)
                }

                override fun onStop() { stop(null, "user") }
            })
            overlay = it
        }
        o.update(state == PAUSED, elapsedMs())
    }

    private fun updateNotification() {
        val ctx = app ?: return
        if (CaptureService.running == null) return
        CaptureNotifications.update(ctx, currentNotification(ctx))
    }

    fun currentNotification(ctx: Context): Notification =
        CaptureNotifications.active(ctx, state, elapsedMs(), countdown, screenshot = serviceMode == "screenshot")

    // ── Full-device screenshot ────────────────────────────────────────────────

    /**
     * One screenshot of the whole screen after Android's consent. With
     * [hideApp] NOVA X steps back first, so the screen behind it is captured;
     * [delayMs] gives the user time to open what they want to capture.
     */
    fun captureScreen(activity: Activity, hideApp: Boolean, delayMs: Int, done: (Map<String, Any?>) -> Unit) {
        val ctx = activity.applicationContext
        app = ctx
        if (state in ACTIVE) {
            return done(CaptureContract.error(CaptureContract.E_BUSY_RECORDING,
                "A screen recording is running. Stop it first, or use your phone's screenshot buttons."))
        }
        if (shotDone != null || serviceMode != null) {
            return done(CaptureContract.error(CaptureContract.E_BUSY, "A screenshot is already being taken."))
        }
        if (isLocked(ctx)) return done(CaptureContract.error(CaptureContract.E_LOCKED, "Unlock your phone first."))
        if (needsStoragePermission(ctx)) {
            return done(CaptureContract.error(CaptureContract.E_PERMISSION,
                "Allow storage access so NOVA X can save the screenshot.", "permission" to "storage"))
        }
        val free = CaptureMediaRepository.freeBytes(ctx)
        if (free in 0 until 20L * 1024 * 1024) {
            return done(CaptureContract.error(CaptureContract.E_LOW_STORAGE, "Your phone is out of space. Free some up and try again."))
        }
        shotDone = done
        shotHide = hideApp
        shotDelay = delayMs.coerceIn(0, 10_000)
        if (activity is MainActivity) hostActivity = WeakReference(activity)
        emitEvent(CaptureContract.EVENT_SCREENSHOT_STARTED)
        emitEvent(CaptureContract.EVENT_PERMISSION_REQUIRED, "permission" to "screen_capture")
        emitState()
        if (!launchConsent(activity, "screenshot")) {
            finishShot(CaptureContract.error(CaptureContract.E_NO_ACTIVITY, "Android's screen-capture request couldn't be shown."))
            return
        }
        main.removeCallbacks(consentWatchdog)
        main.postDelayed(consentWatchdog, 120_000)
    }

    private fun grabShot() {
        val ctx = app
        val p = projection
        if (ctx == null || p == null || shotDone == null) {
            releaseProjection()
            finishShot(CaptureContract.error(CaptureContract.E_INTERRUPTED, "The screenshot couldn't be taken."))
            return
        }
        ScreenshotGrabber.grab(ctx, p) { bitmap, code ->
            releaseProjection()
            if (bitmap == null) {
                val msg = when (code) {
                    CaptureContract.E_PROTECTED -> "The app on screen blocks screenshots, so nothing was captured."
                    else -> "The screenshot couldn't be taken. Please try again."
                }
                emitEvent(CaptureContract.EVENT_SCREENSHOT_FAILED, "errorCode" to (code ?: CaptureContract.E_ERROR))
                finishShot(CaptureContract.error(code ?: CaptureContract.E_ERROR, msg))
                return@grab
            }
            io.execute {
                val r = CaptureMediaRepository.saveBitmap(ctx, bitmap)
                bitmap.recycle()
                main.post {
                    @Suppress("UNCHECKED_CAST")
                    val item = r["item"] as? Map<String, Any?>
                    if (r["success"] == true && item != null) {
                        emitEvent(CaptureContract.EVENT_SCREENSHOT_COMPLETED, "item" to item)
                        emitEvent(CaptureContract.EVENT_MEDIA_AVAILABLE, "item" to item)
                        CaptureNotifications.saved(ctx, "Screenshot saved", "Pictures/NOVA X/Screenshots. Tap to view, edit or share.")
                    } else {
                        emitEvent(CaptureContract.EVENT_SCREENSHOT_FAILED, "errorCode" to r["errorCode"])
                    }
                    finishShot(r)
                }
            }
        }
    }

    private fun finishShot(result: Map<String, Any?>) {
        val cb = shotDone
        shotDone = null
        emitState()
        cb?.invoke(result)
    }
}
