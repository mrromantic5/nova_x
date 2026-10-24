package com.tlyfe.nova_x.nova

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Tap-to-talk recorder for NOVA.
 *
 * - Records a single command clip (AAC in MPEG-4 → "audio/mp4", accepted by
 *   the NOVA Worker's /transcribe endpoint) into the app cache.
 * - Never runs continuously: recording only starts after an explicit user
 *   action (mic tap or assistant invocation) and always ends on silence,
 *   timeout, interruption, cancel or stop.
 * - Emits a normalised input level for the audio-reactive orb.
 * - Only one recording can exist at a time (duplicate starts return "busy").
 *
 * All methods must be called on the main thread (MethodChannel calls and the
 * internal Handler both run there).
 */
class NovaRecorder(
    private val context: Context,
    private val emit: (String, Any?) -> Unit,
) {
    private companion object {
        const val METER_INTERVAL_MS = 60L
        const val MAX_AMPLITUDE = 32767.0
    }

    /** Headset microphone for this recording (wired, or Bluetooth when allowed). */
    private val route = NovaAudioRoute.Session(context)

    private val handler = Handler(Looper.getMainLooper())
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var startedAt = 0L
    private var peak = 0
    private var endpointer = NovaEndpointer()
    private var autoStop = true
    private var maxDurationMs = 30_000L

    /** A start is waiting for the Bluetooth link (startAsync). */
    private var starting = false

    /** Result of a recording that ended automatically, waiting for stop(). */
    private var finishedResult: Map<String, Any?>? = null

    private var focusRequest: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change == AudioManager.AUDIOFOCUS_LOSS ||
            change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
            // A call or another recorder took the microphone.
            if (recorder != null) autoFinish("interrupted")
        }
    }

    private val meter = object : Runnable {
        override fun run() {
            val r = recorder ?: return
            val amp = try { r.maxAmplitude } catch (e: Exception) { 0 }
            val now = SystemClock.elapsedRealtime()
            val elapsed = now - startedAt
            peak = max(peak, amp)
            val decision = endpointer.feed(elapsed, amp)

            emit("onAmplitude", min(1.0, sqrt(amp / MAX_AMPLITUDE)))

            when {
                elapsed >= maxDurationMs -> { autoFinish("max_duration"); return }
                autoStop && decision == NovaEndpointer.Decision.SILENCE -> { autoFinish("silence"); return }
                autoStop && decision == NovaEndpointer.Decision.NO_SPEECH -> { autoFinish("no_speech"); return }
            }
            handler.postDelayed(this, METER_INTERVAL_MS)
        }
    }

    /** True while the microphone is open. */
    fun isActive(): Boolean = recorder != null || starting

    /** This recorder's name in NovaMicArbiter ("Hey NOVA" pauses while it records). */
    private val holdKey = "recorder@" + System.identityHashCode(this)

    private var startCancelled = false

    /**
     * Starts recording and calls [done] with the status. With a Bluetooth
     * headset (and "Use headset microphone" on) NOVA first waits up to 1.5 s,
     * off the UI thread, for the headset's microphone link; if it doesn't come
     * up, the phone's microphone records instead — never silence.
     */
    fun startAsync(maxSeconds: Int, autoStopOnSilence: Boolean, done: (Map<String, Any?>) -> Unit) {
        if (recorder != null || starting) {
            done(mapOf("status" to "busy"))
            return
        }
        discardFinished()
        val headset = NovaAudioRoute.headsetInput(context)
        val useBluetooth = headset != null && NovaAudioRoute.isBluetooth(headset) &&
            NovaAudioRoute.headsetEnabled(context) && !NovaAudioRoute.inCall(context)
        if (!useBluetooth) {
            done(start(maxSeconds, autoStopOnSilence, route.begin(allowBluetooth = false)))
            return
        }
        starting = true
        startCancelled = false
        Thread({
            route.begin(allowBluetooth = true, waitMs = 1500L)
            val ready = route.isReady()
            val device = if (ready) route.device else null
            if (!ready) route.end()
            handler.post {
                starting = false
                if (startCancelled) {
                    route.end()
                    done(mapOf("status" to "idle"))
                } else {
                    done(start(maxSeconds, autoStopOnSilence, device))
                }
            }
        }, "nova-mic-route").start()
    }

    private fun start(maxSeconds: Int, autoStopOnSilence: Boolean, headset: android.media.AudioDeviceInfo?): Map<String, Any?> {
        if (recorder != null) return mapOf("status" to "busy")
        // Let the "Hey NOVA" listener release the microphone first.
        NovaMicArbiter.hold(holdKey, true)
        NovaMicArbiter.awaitWakeMicReleased()

        val out = File(context.cacheDir, "nova_voice_${System.currentTimeMillis()}.m4a")
        val r: MediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        try {
            // 3.8.1: the regular MIC source. Android requires VOICE_RECOGNITION
            // to be unprocessed (no automatic gain), so a voice from across
            // the room was recorded very quietly; MIC applies the phone's own
            // gain control, which the speech recogniser handles much better.
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioChannels(1)
            r.setAudioSamplingRate(16_000)
            r.setAudioEncodingBitRate(48_000)
            r.setOutputFile(out.absolutePath)
            if (headset != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try { r.setPreferredDevice(headset) } catch (ignored: Exception) { }
            }
            r.prepare()
            requestFocus()
            r.start()
        } catch (e: Exception) {
            try { r.release() } catch (ignored: Exception) { }
            out.delete()
            abandonFocus()
            route.end()
            NovaMicArbiter.hold(holdKey, false)
            return mapOf("status" to "error", "message" to "The microphone is unavailable right now.")
        }

        recorder = r
        file = out
        startedAt = SystemClock.elapsedRealtime()
        peak = 0
        endpointer = NovaEndpointer()
        autoStop = autoStopOnSilence
        maxDurationMs = maxSeconds.coerceIn(3, 60) * 1000L
        handler.postDelayed(meter, METER_INTERVAL_MS)
        return mapOf("status" to "recording")
    }

    /** Stops (or collects an auto-stopped) recording and returns its details. */
    fun stop(): Map<String, Any?> {
        finishedResult?.let {
            finishedResult = null
            return it
        }
        if (recorder == null) return mapOf("status" to "idle")
        return finish()
    }

    /** Stops and deletes the recording; nothing is returned or uploaded. */
    fun cancel() {
        if (starting) startCancelled = true
        handler.removeCallbacks(meter)
        val r = recorder
        recorder = null
        if (r != null) {
            try { r.stop() } catch (ignored: Exception) { }
            try { r.release() } catch (ignored: Exception) { }
        }
        file?.delete()
        file = null
        abandonFocus()
        route.end()
        discardFinished()
        NovaMicArbiter.hold(holdKey, false)
    }

    private fun autoFinish(reason: String) {
        finishedResult = finish()
        emit("onRecordingAutoStopped", reason)
    }

    private fun finish(): Map<String, Any?> {
        handler.removeCallbacks(meter)
        val r = recorder ?: return mapOf("status" to "idle")
        recorder = null
        val out = file
        file = null
        val durationMs = SystemClock.elapsedRealtime() - startedAt

        var valid = true
        try {
            r.stop()
        } catch (e: RuntimeException) {
            // Thrown when stop() is called before any audio was captured.
            valid = false
        }
        try { r.release() } catch (ignored: Exception) { }
        abandonFocus()
        route.end()
        NovaMicArbiter.hold(holdKey, false)

        if (!valid || out == null || !out.exists() || out.length() == 0L) {
            out?.delete()
            return mapOf("status" to "empty", "durationMs" to durationMs, "hadSpeech" to false)
        }
        return mapOf(
            "status" to "ok",
            "path" to out.absolutePath,
            "durationMs" to durationMs,
            "hadSpeech" to endpointer.heardSpeech,
            "peak" to peak / MAX_AMPLITUDE,
        )
    }

    private fun discardFinished() {
        val previous = finishedResult ?: return
        finishedResult = null
        (previous["path"] as? String)?.let { File(it).delete() }
    }

    private fun requestFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(focusListener)
                .build()
            focusRequest = req
            audioManager.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
            )
        }
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
    }
}
