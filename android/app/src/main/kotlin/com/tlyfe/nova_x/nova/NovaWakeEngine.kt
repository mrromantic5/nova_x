package com.tlyfe.nova_x.nova

import android.content.Context
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.KeywordSpotter
import com.k2fsa.sherpa.onnx.KeywordSpotterConfig
import com.k2fsa.sherpa.onnx.OnlineModelConfig
import com.k2fsa.sherpa.onnx.OnlineStream
import com.k2fsa.sherpa.onnx.OnlineTransducerModelConfig

/**
 * On-device "Hey NOVA" detector (sherpa-onnx keyword spotting, Apache-2.0).
 *
 * Model: sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01 (int8), bundled
 * in assets/nova_kws/. Phrases are listed in assets/nova_kws/keywords.txt as
 * model tokens. Audio never leaves the phone; nothing is stored.
 *
 * Not thread-safe: use one instance from one thread (the wake service's).
 */
class NovaWakeEngine private constructor(private val spotter: KeywordSpotter) {

    companion object {
        const val SAMPLE_RATE = 16_000
        private const val DIR = "nova_kws"

        // Tuned on synthetic speech (16 voices x 2 speeds, 20 dB background
        // noise): see NOVA_IMPLEMENTATION_REPORT.md. "Hi NOVA" and "OK NOVA"
        // are deliberately not wake phrases: NOVA's own greeting starts with
        // "Hi, NOVA…" and "OK NOVA" fired on "open NOVA X".
        private const val THRESHOLD = 0.20f
        private const val BOOST = 2.5f
        private const val ACTIVE_PATHS = 8

        /** True when the model files are present in the APK. */
        fun assetsPresent(context: Context): Boolean = try {
            val files = context.assets.list(DIR)?.toSet() ?: emptySet()
            listOf("encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt", "keywords.txt")
                .all { it in files }
        } catch (e: Exception) {
            false
        }

        /** Loads the detector, or returns null on phones it cannot run on. */
        fun create(context: Context): NovaWakeEngine? {
            if (!assetsPresent(context)) return null
            return try {
                val config = KeywordSpotterConfig(
                    featConfig = FeatureConfig(sampleRate = SAMPLE_RATE, featureDim = 80),
                    modelConfig = OnlineModelConfig(
                        transducer = OnlineTransducerModelConfig(
                            encoder = "$DIR/encoder.int8.onnx",
                            decoder = "$DIR/decoder.int8.onnx",
                            joiner = "$DIR/joiner.int8.onnx",
                        ),
                        tokens = "$DIR/tokens.txt",
                        modelType = "zipformer2",
                        numThreads = 1,
                        provider = "cpu",
                    ),
                    maxActivePaths = ACTIVE_PATHS,
                    keywordsFile = "$DIR/keywords.txt",
                    keywordsScore = BOOST,
                    keywordsThreshold = THRESHOLD,
                    numTrailingBlanks = 1,
                )
                NovaWakeEngine(KeywordSpotter(context.assets, config))
            } catch (t: Throwable) {
                // UnsatisfiedLinkError (no native library for this CPU, e.g. x86
                // emulators), missing/corrupt model, out of memory…
                null
            }
        }
    }

    private var stream: OnlineStream = spotter.createStream()

    /** Feeds 16 kHz mono samples; returns true when a wake phrase was heard. */
    fun accept(samples: FloatArray): Boolean {
        stream.acceptWaveform(samples, SAMPLE_RATE)
        while (spotter.isReady(stream)) {
            spotter.decode(stream)
            if (spotter.getResult(stream).keyword.isNotEmpty()) {
                spotter.reset(stream)
                return true
            }
        }
        return false
    }

    /** Forget buffered audio (after a pause). */
    fun restart() {
        stream.release()
        stream = spotter.createStream()
    }

    fun release() {
        try { stream.release() } catch (ignored: Throwable) { }
        try { spotter.release() } catch (ignored: Throwable) { }
    }
}
