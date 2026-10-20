package com.tlyfe.nova_x.nova

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.File

/**
 * Plays NOVA's cloud voice (MP3 files produced by the NOVA Voice service and
 * saved in the app cache). Reports progress like the phone voice does —
 * onTtsStart / onTtsDone / onTtsError with the utterance id — so the
 * assistant waits for NOVA to finish talking before listening again.
 *
 * Music lowers its volume while NOVA talks (transient, duckable focus) and
 * "Hey NOVA" steps aside so NOVA never wakes itself. Only .mp3 files inside
 * this app's cache folder can be played; each file is deleted afterwards.
 */
class NovaVoicePlayer(
    context: Context,
    private val emit: (String, Any?) -> Unit,
) {
    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val holdKey = "voicefile${System.identityHashCode(this)}"
    private val attributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANT)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private var player: MediaPlayer? = null
    private var currentId: String? = null
    private var currentFile: File? = null
    private var focusRequest: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { }

    /** Returns false when the file is not an MP3 in this app's cache. */
    fun play(path: String, id: String): Boolean {
        stop()
        val file = File(path)
        val cache = appContext.cacheDir.canonicalFile
        val canonical = try { file.canonicalFile } catch (e: Exception) { return false }
        if (!canonical.path.startsWith(cache.path + File.separator) ||
            !canonical.name.endsWith(".mp3") || !canonical.isFile
        ) {
            return false
        }
        val mp = MediaPlayer()
        mp.setAudioAttributes(attributes)
        mp.setOnPreparedListener { ready ->
            if (player !== ready) return@setOnPreparedListener
            requestFocus()
            try {
                ready.start()
                emit("onTtsStart", id)
            } catch (e: IllegalStateException) {
                finish("onTtsError")
            }
        }
        mp.setOnCompletionListener { done -> if (player === done) finish("onTtsDone") }
        mp.setOnErrorListener { failed, _, _ ->
            if (player === failed) finish("onTtsError")
            true
        }
        player = mp
        currentId = id
        currentFile = canonical
        NovaMicArbiter.hold(holdKey, true)
        return try {
            mp.setDataSource(canonical.path)
            mp.prepareAsync()
            true
        } catch (e: Exception) {
            release(deleteFile = true)
            false
        }
    }

    /**
     * Stops playback. A playing utterance is reported as onTtsError ("stopped
     * early"), so the Dart side ends that utterance instead of moving on to
     * its next part — e.g. when another NOVA screen starts talking.
     */
    fun stop() {
        if (player != null) finish("onTtsError")
    }

    fun shutdown() {
        release(deleteFile = true)
    }

    private fun finish(event: String) {
        val id = currentId
        release(deleteFile = true)
        if (id != null) main.post { emit(event, id) }
    }

    private fun release(deleteFile: Boolean) {
        val p = player
        player = null
        currentId = null
        if (p != null) {
            try { p.reset() } catch (ignored: Exception) { }
            try { p.release() } catch (ignored: Exception) { }
        }
        abandonFocus()
        NovaMicArbiter.hold(holdKey, false)
        val f = currentFile
        currentFile = null
        if (deleteFile && f != null) {
            try { f.delete() } catch (ignored: Exception) { }
        }
    }

    private fun requestFocus() {
        val am = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(focusListener, main)
                .build()
            focusRequest = req
            am.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        }
    }

    private fun abandonFocus() {
        val am = appContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { am.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(focusListener)
        }
    }
}
