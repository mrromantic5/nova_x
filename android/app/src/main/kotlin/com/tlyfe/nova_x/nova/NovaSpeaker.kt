package com.tlyfe.nova_x.nova

import android.content.Context
import android.media.AudioAttributes
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/**
 * NOVA's voice — Android's on-device TextToSpeech engine.
 *
 * Replies are English, so an English voice is selected: the device's own
 * English variant when the phone is set to English, otherwise US English.
 * Progress is reported to Dart as onTtsStart / onTtsDone / onTtsError so the
 * assistant never starts listening while it is still speaking (prevents NOVA
 * from hearing itself).
 */
class NovaSpeaker(
    context: Context,
    private val emit: (String, Any?) -> Unit,
) : TextToSpeech.OnInitListener {

    private var tts: TextToSpeech? = null
    private var ready = false
    private var failed = false

    /** A single request made before the engine finished initialising. */
    private var queued: Pair<String, String>? = null

    /** "Hey NOVA" pauses while NOVA talks, so NOVA never wakes itself. */
    private val holdKey = "speaker@" + System.identityHashCode(this)

    init {
        // Created after the fields above: some devices call onInit(ERROR)
        // synchronously inside this constructor.
        tts = TextToSpeech(context.applicationContext, this)
    }

    override fun onInit(status: Int) {
        val engine = tts
        if (status != TextToSpeech.SUCCESS || engine == null) {
            failed = true
            queued?.let { emit("onTtsError", it.second) }
            queued = null
            return
        }

        val preferred = Locale.getDefault()
            .takeIf { it.language == Locale.ENGLISH.language } ?: Locale.US
        val result = engine.setLanguage(preferred)
        if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
            engine.setLanguage(Locale.US)
        }
        engine.setSpeechRate(1.0f)
        engine.setPitch(1.05f)
        engine.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                NovaMicArbiter.hold(holdKey, true)
                emit("onTtsStart", utteranceId)
            }

            override fun onDone(utteranceId: String?) {
                NovaMicArbiter.hold(holdKey, false)
                emit("onTtsDone", utteranceId)
            }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                NovaMicArbiter.hold(holdKey, false)
                emit("onTtsError", utteranceId)
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                NovaMicArbiter.hold(holdKey, false)
                emit("onTtsError", utteranceId)
            }

            override fun onStop(utteranceId: String?, interrupted: Boolean) {
                NovaMicArbiter.hold(holdKey, false)
                emit("onTtsDone", utteranceId)
            }
        })

        ready = true
        queued?.let { speakNow(it.first, it.second) }
        queued = null
    }

    /** Returns false when no speech engine is available on this device. */
    fun speak(text: String, utteranceId: String): Boolean {
        if (failed || tts == null) return false
        val clean = text.trim()
        if (clean.isEmpty()) return false
        if (!ready) {
            queued = clean to utteranceId
            return true
        }
        return speakNow(clean, utteranceId)
    }

    private fun speakNow(text: String, utteranceId: String): Boolean {
        val engine = tts ?: return false
        val limit = TextToSpeech.getMaxSpeechInputLength()
        val chunk = if (text.length > limit) text.substring(0, limit) else text
        NovaMicArbiter.hold(holdKey, true)
        val ok = engine.speak(chunk, TextToSpeech.QUEUE_FLUSH, null, utteranceId) == TextToSpeech.SUCCESS
        if (!ok) NovaMicArbiter.hold(holdKey, false)
        return ok
    }

    fun stop() {
        // A request still waiting for the engine never started: report it done.
        queued?.let { emit("onTtsDone", it.second) }
        queued = null
        try { tts?.stop() } catch (ignored: Exception) { }
        NovaMicArbiter.hold(holdKey, false)
    }

    fun shutdown() {
        queued = null
        val engine = tts
        tts = null
        ready = false
        try {
            engine?.stop()
            engine?.shutdown()
        } catch (ignored: Exception) { }
        NovaMicArbiter.hold(holdKey, false)
    }
}
