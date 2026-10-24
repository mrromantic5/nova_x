package com.tlyfe.nova_x.nova

/**
 * Decides when the user has finished speaking (pure Kotlin, unit-tested on
 * the desktop). Fed every ~60 ms with the recorder's peak level (0…32767).
 *
 * 3.8.1 — fixes "NOVA doesn't respond":
 *  - 3.8.0 counted any single loud peak (a click, a breath, a tap on the
 *    phone) as speech and stopped 1 s later — often before the user had
 *    started talking. Speech now has to last ([onsetTicks] readings in a row,
 *    ≈ 0.2 s) before it counts.
 *  - The room level is measured from the median of the first readings, so a
 *    single noise at the start doesn't raise the bar.
 *  - After speech starts, quieter sounds still count as talking (hysteresis),
 *    so the soft ends of words from a distance don't end the request early,
 *    and short pauses between words are allowed ([silenceMs]).
 */
class NovaEndpointer(
    private val calibrationMs: Long = 300L,
    private val minThreshold: Int = 700,
    private val ambientFactor: Double = 3.0,
    private val onsetTicks: Int = 3,
    private val silenceMs: Long = 1200L,
    private val minSpeechMs: Long = 600L,
    private val noSpeechMs: Long = 7000L,
) {
    enum class Decision { CONTINUE, SILENCE, NO_SPEECH }

    var heardSpeech = false
        private set

    /** Current level needed to count as speech. */
    var threshold = minThreshold
        private set

    private val calibration = ArrayList<Int>()
    private var calibrated = false
    private var loudRun = 0
    private var speechStart = 0L
    private var lastLoud = 0L

    fun feed(elapsedMs: Long, amp: Int): Decision {
        if (!calibrated) {
            if (elapsedMs < calibrationMs) {
                calibration.add(amp)
                return Decision.CONTINUE
            }
            calibrated = true
            if (calibration.isNotEmpty()) {
                val sorted = calibration.sorted()
                val median = sorted[sorted.size / 2]
                threshold = maxOf(minThreshold, (median * ambientFactor).toInt())
            }
        }

        if (!heardSpeech) {
            loudRun = if (amp >= threshold) loudRun + 1 else 0
            if (loudRun >= onsetTicks) {
                heardSpeech = true
                speechStart = elapsedMs
                lastLoud = elapsedMs
            } else if (elapsedMs >= noSpeechMs) {
                return Decision.NO_SPEECH
            }
            return Decision.CONTINUE
        }

        // Talking: softer sounds still count (ends of words, a distant voice).
        if (amp >= threshold / 2) lastLoud = elapsedMs
        if (elapsedMs - lastLoud >= silenceMs && elapsedMs - speechStart >= minSpeechMs) {
            return Decision.SILENCE
        }
        return Decision.CONTINUE
    }
}
