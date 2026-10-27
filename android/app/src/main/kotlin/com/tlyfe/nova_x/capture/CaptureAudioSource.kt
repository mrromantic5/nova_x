package com.tlyfe.nova_x.capture

import android.annotation.SuppressLint
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.os.Build
import kotlin.math.max

/**
 * PCM audio for a screen recording: 44.1 kHz, mono, 16-bit.
 *
 *  - mic        — the microphone (narration). Needs RECORD_AUDIO.
 *  - device     — sound played by apps (Android 10+, AudioPlaybackCapture).
 *                 Apps can opt out (calls, many banking/DRM apps): their sound
 *                 is simply not captured. Needs RECORD_AUDIO too.
 *  - mic_device — both, mixed in software.
 *
 * Opened only for a recording the user started; [stop] is called on pause so
 * the microphone (and its privacy indicator) is off while paused.
 */
class CaptureAudioSource(private val mode: String, private val projection: MediaProjection) {

    companion object {
        const val SAMPLE_RATE = 44_100
        const val CHUNK_BYTES = 4096 // 2048 samples ≈ 46 ms

        fun deviceAudioSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    }

    private var mic: AudioRecord? = null
    private var playback: AudioRecord? = null
    private val micBuf = ByteArray(CHUNK_BYTES)
    private val pbBuf = ByteArray(CHUNK_BYTES)

    /** Short note for the user when part of the requested audio is unavailable. */
    var warning: String? = null
        private set

    /** Opens the requested sources. Returns false when none could be opened. */
    @SuppressLint("MissingPermission") // checked by CaptureCoordinator before starting
    fun open(): Boolean {
        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val size = max(minBuf, CHUNK_BYTES) * 4
        if (CaptureContract.usesMic(mode)) {
            mic = try {
                AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, size).takeIf { it.state == AudioRecord.STATE_INITIALIZED }
            } catch (e: Exception) { null }
            if (mic == null) warning = "The microphone couldn't be used, so your voice isn't recorded."
        }
        if (CaptureContract.usesDevice(mode)) {
            playback = if (deviceAudioSupported()) openPlayback(size) else null
            if (playback == null) {
                warning = if (mic == null && CaptureContract.usesMic(mode)) {
                    "Audio couldn't be recorded on this phone, so the video has no sound."
                } else {
                    "Sound from apps couldn't be recorded on this phone."
                }
            }
        }
        return mic != null || playback != null
    }

    @SuppressLint("MissingPermission", "NewApi")
    private fun openPlayback(size: Int): AudioRecord? = try {
        val cfg = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()
        AudioRecord.Builder()
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(size)
            .setAudioPlaybackCaptureConfig(cfg)
            .build()
            .takeIf { it.state == AudioRecord.STATE_INITIALIZED }
    } catch (e: Exception) {
        null
    }

    fun start() {
        try { mic?.startRecording() } catch (e: Exception) { }
        try { playback?.startRecording() } catch (e: Exception) { }
    }

    /** Stops capturing (pause or end). Unblocks a pending [read]. */
    fun stop() {
        try { mic?.stop() } catch (e: Exception) { }
        try { playback?.stop() } catch (e: Exception) { }
    }

    /**
     * Fills [out] with one chunk of mono PCM. Returns the byte count (0 when no
     * audio was available, negative on a fatal read error).
     */
    fun read(out: ByteArray): Int {
        val m = mic
        val p = playback
        if (m != null && p == null) return m.read(out, 0, CHUNK_BYTES)
        if (p != null && m == null) return p.read(out, 0, CHUNK_BYTES)
        if (m == null || p == null) return -1
        // Mixed: the microphone sets the pace; app sound is added when there is some.
        val n = m.read(micBuf, 0, CHUNK_BYTES)
        if (n <= 0) return n
        val pn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            p.read(pbBuf, 0, n, AudioRecord.READ_NON_BLOCKING)
        } else {
            0
        }
        var i = 0
        while (i + 1 < n) {
            val a = (micBuf[i].toInt() and 0xFF) or (micBuf[i + 1].toInt() shl 8)
            val b = if (i + 1 < pn) (pbBuf[i].toInt() and 0xFF) or (pbBuf[i + 1].toInt() shl 8) else 0
            val mixed = (a.toShort() + b.toShort()).coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            out[i] = (mixed and 0xFF).toByte()
            out[i + 1] = ((mixed shr 8) and 0xFF).toByte()
            i += 2
        }
        return n
    }

    fun release() {
        stop()
        try { mic?.release() } catch (e: Exception) { }
        try { playback?.release() } catch (e: Exception) { }
        mic = null
        playback = null
    }
}
