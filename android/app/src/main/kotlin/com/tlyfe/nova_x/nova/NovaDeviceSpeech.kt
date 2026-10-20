package com.tlyfe.nova_x.nova

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.Locale

/**
 * Offline speech recognition for NOVA, used when the phone has no internet
 * (NOVA normally sends a short recording to the NOVA AI service).
 *
 * Uses Android's own speech recogniser and asks it to work on the device
 * (Android 12+: the on-device recogniser when available; otherwise the
 * default recogniser with "prefer offline"). Whether it works offline depends
 * on the phone having offline speech data installed.
 *
 * Events (to Dart): onAmplitude(level) · onDeviceSpeech({kind: partial|result|error, text, code})
 * Must be used on the main thread.
 */
class NovaDeviceSpeech(
    context: Context,
    private val emit: (String, Any?) -> Unit,
) {
    private val appContext = context.applicationContext
    private val holdKey = "devicespeech${System.identityHashCode(this)}"
    private var recognizer: SpeechRecognizer? = null
    private var usingOnDevice = false
    private var triedFallback = false
    private var active = false

    fun available(): Boolean = SpeechRecognizer.isRecognitionAvailable(appContext) || onDeviceAvailable()

    private fun onDeviceAvailable(): Boolean =
        Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(appContext)

    fun start(): Map<String, Any?> {
        cancel()
        if (!available()) return mapOf("status" to "unavailable")
        triedFallback = false
        return if (begin(preferOnDevice = true)) mapOf("status" to "listening") else mapOf("status" to "unavailable")
    }

    /** Finish listening; the final result arrives as an event. */
    fun stop() {
        try { recognizer?.stopListening() } catch (ignored: Exception) { }
    }

    fun cancel() {
        active = false
        val r = recognizer
        recognizer = null
        if (r != null) {
            try { r.cancel() } catch (ignored: Exception) { }
            try { r.destroy() } catch (ignored: Exception) { }
        }
        NovaMicArbiter.hold(holdKey, false)
    }

    fun isActive(): Boolean = active

    private fun begin(preferOnDevice: Boolean): Boolean {
        val onDevice = preferOnDevice && onDeviceAvailable()
        val r = try {
            if (onDevice && Build.VERSION.SDK_INT >= 31) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(appContext)
            } else {
                SpeechRecognizer.createSpeechRecognizer(appContext)
            }
        } catch (e: Exception) {
            return false
        }
        usingOnDevice = onDevice
        recognizer = r
        r.setRecognitionListener(listener)
        val language = Locale.getDefault().takeIf { it.language == "en" }?.toLanguageTag() ?: "en-US"
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, appContext.packageName)
        }
        // "Hey NOVA" releases the microphone first (Android 7–9 allow one recorder).
        NovaMicArbiter.hold(holdKey, true)
        NovaMicArbiter.awaitWakeMicReleased()
        return try {
            r.startListening(intent)
            active = true
            true
        } catch (e: Exception) {
            cancel()
            false
        }
    }

    private fun bestText(results: Bundle?): String {
        val list = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        return list?.firstOrNull { it.isNotBlank() }?.trim() ?: ""
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}

        override fun onBeginningOfSpeech() {}

        override fun onRmsChanged(rmsdB: Float) {
            // Typical range −2..10 dB → 0..1 for the orb.
            emit("onAmplitude", ((rmsdB + 2f) / 12f).coerceIn(0f, 1f).toDouble())
        }

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {}

        override fun onError(error: Int) {
            val languageMissing = error == 12 || error == 13 // LANGUAGE_NOT_SUPPORTED / LANGUAGE_UNAVAILABLE
            if (usingOnDevice && languageMissing && !triedFallback) {
                // No on-device language pack: try the phone's normal recogniser in offline mode.
                triedFallback = true
                cancel()
                if (begin(preferOnDevice = false)) return
            }
            cancel()
            emit("onDeviceSpeech", mapOf("kind" to "error", "code" to codeName(error)))
        }

        override fun onResults(results: Bundle?) {
            val text = bestText(results)
            cancel()
            emit("onDeviceSpeech", mapOf("kind" to "result", "text" to text))
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val text = bestText(partialResults)
            if (text.isNotEmpty()) emit("onDeviceSpeech", mapOf("kind" to "partial", "text" to text))
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun codeName(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "no_speech"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission"
        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER -> "offline_unavailable"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
        12, 13 -> "offline_unavailable"
        else -> "error"
    }
}
