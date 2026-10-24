package com.tlyfe.nova_x.nova

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Software automatic gain control for the "Hey NOVA" detector (pure Kotlin,
 * no Android dependencies, unit-tested on the desktop with the real wake
 * word model).
 *
 * Android's VOICE_RECOGNITION microphone source is deliberately unprocessed
 * on most phones: no gain control, so a voice from across the room arrives
 * 20–30 dB quieter than the same voice at arm's length. This brings speech
 * up to a steady level before the detector sees it:
 *
 *  - The gain follows the loudness of the last moments (fast to come down for
 *    loud sounds, slow to go up again), so a far voice is lifted and a near
 *    voice is left alone.
 *  - The background noise is never lifted above [noiseCeiling]: in a quiet
 *    room NOVA does not "hear" amplified hiss (which would cause false
 *    wake-ups), only speech gets louder.
 *  - Gain changes are ramped sample by sample (no clicks) and peaks are
 *    softly limited (no clipping).
 *
 * Works on 16-bit PCM chunks (0.1 s at 16 kHz) and returns floats in −1…1,
 * the format the detector takes. Not thread-safe: one instance per stream.
 */
class NovaMicGain(
    private val targetRms: Float = 0.08f,     // about −22 dBFS: normal close speech
    private val maxGain: Float = 20f,         // +26 dB at most (≈ 4–5 m away)
    private val noiseCeiling: Float = 0.006f, // background never louder than ≈ −44 dBFS
) {
    private var level = 0f      // loudness envelope of recent sound
    private var noise = 0f      // estimated background-noise floor
    private var gain = 1f
    private var chunks = 0

    /** Current gain (for diagnostics and tests). */
    val currentGain: Float get() = gain

    fun reset() {
        level = 0f
        noise = 0f
        gain = 1f
        chunks = 0
    }

    /** Processes [n] samples of [pcm] into a new float array. */
    fun process(pcm: ShortArray, n: Int = pcm.size): FloatArray {
        val count = min(n, pcm.size)
        val out = FloatArray(count)
        if (count == 0) return out
        var sum = 0.0
        for (i in 0 until count) {
            val v = pcm[i] / 32768f
            out[i] = v
            sum += v * v
        }
        apply(out, sqrt(sum / count).toFloat())
        return out
    }

    /** Same as [process] for float input (tests, other sources). */
    fun process(samples: FloatArray): FloatArray {
        val out = samples.copyOf()
        if (out.isEmpty()) return out
        var sum = 0.0
        for (v in out) sum += v * v
        apply(out, sqrt(sum / out.size).toFloat())
        return out
    }

    private fun apply(out: FloatArray, rms: Float) {
        val r = max(rms, 1e-6f)
        chunks++
        // Background floor: follows quiet moments down quickly, rises slowly
        // (about 4 % a second) so speech doesn't count as background.
        noise = when {
            chunks == 1 -> r
            r < noise -> noise * 0.6f + r * 0.4f
            else -> min(r, noise * 1.004f)
        }
        // Loudness envelope: up at once on loud sound, down over ~1.5 s.
        level = if (r > level) r else level * 0.93f + r * 0.07f

        val wanted = minOf(
            maxGain,
            targetRms / max(level, 1e-6f),
            noiseCeiling / max(noise, 1e-6f),
        ).coerceAtLeast(1f)
        // Gain goes down quickly (loud sound) and up gently.
        val next = if (wanted < gain) wanted else gain + (wanted - gain) * 0.25f

        val step = (next - gain) / out.size
        var g = gain
        for (i in out.indices) {
            g += step
            out[i] = limit(out[i] * g)
        }
        gain = next
    }

    /** Soft limiter: linear up to 0.7, then a smooth knee that never exceeds 1. */
    private fun limit(x: Float): Float {
        val a = abs(x)
        if (a <= 0.7f) return x
        val over = a - 0.7f
        val y = 0.7f + 0.3f * (over / (over + 0.3f))
        return if (x < 0) -y else y
    }
}
