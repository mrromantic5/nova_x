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
        const val METER_INTERVAL_MS = 80L
        const val CALIBRATION_MS = 350L
        const val SILENCE_AFTER_SPEECH_MS = 1500L
        const val NO_SPEECH_TIMEOUT_MS = 7000L
        const val MIN_SPEECH_AMPLITUDE = 1200
        const val MAX_AMPLITUDE = 32767.0
    }

    private val handler = Handler(Looper.getMainLooper())
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var recorder: MediaRecorder? = null
    private var file: File? = null
    private var startedAt = 0L
    private var lastLoudAt = 0L
    private var heardSpeech = false
    private var peak = 0
    private var ambientSum = 0L
    private var ambientSamples = 0
    private var speechThreshold = MIN_SPEECH_AMPLITUDE
    private var autoStop = true
    private var maxDurationMs = 30_000L

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

            if (elapsed < CALIBRATION_MS) {
                ambientSum += amp
                ambientSamples++
            } else if (ambientSamples > 0) {
                val ambient = (ambientSum / ambientSamples).toInt()
                speechThreshold = max(MIN_SPEECH_AMPLITUDE, (ambient * 2.5).toInt())
                ambientSamples = 0
            }

            if (amp >= speechThreshold && elapsed >= CALIBRATION_MS) {
                heardSpeech = true
                lastLoudAt = now
            }

            emit("onAmplitude", min(1.0, sqrt(amp / MAX_AMPLITUDE)))

            when {
                elapsed >= maxDurationMs -> { autoFinish("max_duration"); return }
                autoStop && heardSpeech && now - lastLoudAt >= SILENCE_AFTER_SPEECH_MS -> {
                    autoFinish("silence"); return
                }
                autoStop && !heardSpeech && elapsed >= NO_SPEECH_TIMEOUT_MS -> {
                    autoFinish("no_speech"); return
                }
            }
            handler.postDelayed(this, METER_INTERVAL_MS)
        }
    }

    /** True while the microphone is open. */
    fun isActive(): Boolean = recorder != null

    /** This recorder's name in NovaMicArbiter ("Hey NOVA" pauses while it records). */
    private val holdKey = "recorder@" + System.identityHashCode(this)

    fun start(maxSeconds: Int, autoStopOnSilence: Boolean): Map<String, Any?> {
        if (recorder != null) return mapOf("status" to "busy")
        discardFinished()
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
            r.setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioChannels(1)
            r.setAudioSamplingRate(16_000)
            r.setAudioEncodingBitRate(48_000)
            r.setOutputFile(out.absolutePath)
            r.prepare()
            requestFocus()
            r.start()
        } catch (e: Exception) {
            try { r.release() } catch (ignored: Exception) { }
            out.delete()
            abandonFocus()
            NovaMicArbiter.hold(holdKey, false)
            return mapOf("status" to "error", "message" to "The microphone is unavailable right now.")
        }

        recorder = r
        file = out
        startedAt = SystemClock.elapsedRealtime()
        lastLoudAt = startedAt
        heardSpeech = false
        peak = 0
        ambientSum = 0L
        ambientSamples = 0
        speechThreshold = MIN_SPEECH_AMPLITUDE
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
        NovaMicArbiter.hold(holdKey, false)

        if (!valid || out == null || !out.exists() || out.length() == 0L) {
            out?.delete()
            return mapOf("status" to "empty", "durationMs" to durationMs, "hadSpeech" to false)
        }
        return mapOf(
            "status" to "ok",
            "path" to out.absolutePath,
            "durationMs" to durationMs,
            "hadSpeech" to heardSpeech,
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
