package com.tlyfe.nova_x.music

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.MediaPlayer
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import java.util.concurrent.CopyOnWriteArrayList

/**
 * NOVA Music's player: one queue, one MediaPlayer, shared by every screen and
 * by NOVA's voice commands. Plays files from the phone only, so it works
 * offline.
 *
 * Plays nicely with the rest of the phone: takes audio focus, pauses for
 * calls and for NOVA listening (transient focus loss) and resumes after,
 * lowers its volume while NOVA speaks (ducking), pauses when headphones are
 * unplugged, and shows lock-screen / notification controls through a
 * MediaSession and NovaMusicService.
 *
 * Every method must be called on the main thread (bridge calls, service
 * intents and MediaSession callbacks all arrive there).
 */
object NovaMusicPlayer {

    enum class Repeat { OFF, ALL, ONE }

    private const val IDLE_STOP_MS = 10 * 60 * 1000L // paused this long → release and hide the notification
    private const val MAX_CONSECUTIVE_ERRORS = 5

    private val main = Handler(Looper.getMainLooper())
    private var app: Context? = null

    private var player: MediaPlayer? = null
    private var prepared = false
    private var playWhenReady = true
    private var stopped = true
    private var errorsInARow = 0

    private var original: List<NovaSong> = emptyList()
    private var queue: List<NovaSong> = emptyList()
    private var index = -1

    var shuffle = false
        private set
    var repeat = Repeat.OFF
        private set

    private var session: MediaSession? = null
    private var focusRequest: AudioFocusRequest? = null
    private var resumeOnFocusGain = false
    private var ducked = false
    private var noisyRegistered = false

    private val listeners = CopyOnWriteArrayList<(Map<String, Any?>) -> Unit>()

    private val attributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    private val idleStop = Runnable { if (!isPlayingNow()) stop() }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        main.post { onFocusChange(change) }
    }

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) pause()
        }
    }

    fun init(context: Context) {
        if (app == null) app = context.applicationContext
    }

    fun addListener(listener: (Map<String, Any?>) -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: (Map<String, Any?>) -> Unit) {
        listeners.remove(listener)
    }

    // ── Queue ────────────────────────────────────────────────────────────────

    /** Plays [songs] starting at [startIndex]. [shuffleOn] null keeps the current setting. */
    fun playQueue(context: Context, songs: List<NovaSong>, startIndex: Int, shuffleOn: Boolean? = null): Boolean {
        init(context)
        if (songs.isEmpty()) return false
        if (shuffleOn != null) shuffle = shuffleOn
        val unique = songs.distinctBy { it.id }
        val start = unique[startIndex.coerceIn(0, unique.size - 1)]
        original = unique
        queue = if (shuffle) listOf(start) + unique.filter { it.id != start.id }.shuffled() else unique
        index = queue.indexOfFirst { it.id == start.id }.coerceAtLeast(0)
        errorsInARow = 0
        startCurrent()
        return true
    }

    fun current(): NovaSong? = queue.getOrNull(index)

    fun hasSong(): Boolean = current() != null && !stopped

    fun isPlayingNow(): Boolean = try {
        player?.isPlaying == true
    } catch (e: IllegalStateException) {
        false
    }

    // ── Controls ─────────────────────────────────────────────────────────────

    fun toggle() {
        if (isPlayingNow()) pause() else resume()
    }

    fun pause() {
        resumeOnFocusGain = false
        playWhenReady = false
        val p = player
        if (p != null && isPlayingNow()) {
            try { p.pause() } catch (ignored: IllegalStateException) { }
        }
        afterPause()
    }

    fun resume() {
        val ctx = app ?: return
        if (current() == null) return
        val p = player
        if (p == null) {
            startCurrent()
            return
        }
        playWhenReady = true
        if (!prepared) return // starts when ready
        if (requestFocus(ctx)) {
            try {
                p.start()
                onPlaybackStarted()
            } catch (ignored: IllegalStateException) {
                startCurrent()
            }
        } else {
            publish()
        }
    }

    fun next() {
        if (queue.isEmpty()) return
        index = if (index < queue.size - 1) index + 1 else 0
        errorsInARow = 0
        startCurrent()
    }

    fun previous() {
        if (queue.isEmpty()) return
        if (positionMs() > 3000) {
            seekTo(0)
            return
        }
        index = if (index > 0) index - 1 else queue.size - 1
        errorsInARow = 0
        startCurrent()
    }

    fun seekTo(ms: Long) {
        val p = player ?: return
        if (!prepared) return
        try {
            p.seekTo(ms.coerceIn(0L, durationMs().coerceAtLeast(0L)).toInt())
        } catch (ignored: IllegalStateException) { }
        publish()
    }

    fun setShuffle(on: Boolean) {
        shuffle = on
        val now = current() ?: run { publish(); return }
        queue = if (on) listOf(now) + original.filter { it.id != now.id }.shuffled() else original
        index = queue.indexOfFirst { it.id == now.id }.coerceAtLeast(0)
        publish()
    }

    fun setRepeat(mode: Repeat) {
        repeat = mode
        publish()
    }

    /** Stops playback, releases the player and removes the notification. */
    fun stop() {
        main.removeCallbacks(idleStop)
        resumeOnFocusGain = false
        playWhenReady = false
        releasePlayer()
        abandonFocus()
        unregisterNoisy()
        stopped = true
        session?.let {
            updateSession()
            it.isActive = false
        }
        app?.let { NovaMusicService.stop(it) }
        publish(updateNotification = false)
    }

    // ── State for the NOVA X screens ─────────────────────────────────────────

    fun positionMs(): Long {
        val p = player ?: return 0L
        if (!prepared) return 0L
        return try { p.currentPosition.toLong() } catch (e: IllegalStateException) { 0L }
    }

    fun durationMs(): Long {
        val p = player
        if (p != null && prepared) {
            val d = try { p.duration.toLong() } catch (e: IllegalStateException) { -1L }
            if (d > 0) return d
        }
        return current()?.durationMs ?: 0L
    }

    fun stateName(): String = when {
        stopped || current() == null -> "stopped"
        player != null && !prepared -> "buffering"
        isPlayingNow() -> "playing"
        else -> "paused"
    }

    fun snapshot(): Map<String, Any?> {
        val song = current()
        return mapOf(
            "state" to stateName(),
            "id" to song?.id,
            "title" to song?.title,
            "artist" to song?.artist,
            "album" to song?.album,
            "durationMs" to durationMs(),
            "positionMs" to positionMs(),
            "index" to index,
            "queueLength" to queue.size,
            "shuffle" to shuffle,
            "repeat" to repeat.name.lowercase(),
        )
    }

    fun sessionToken(): MediaSession.Token? = session?.sessionToken

    // ── Playback internals ───────────────────────────────────────────────────

    private fun startCurrent() {
        val ctx = app ?: return
        val song = current() ?: run { stop(); return }
        main.removeCallbacks(idleStop)
        releasePlayer()
        stopped = false
        playWhenReady = true
        val mp = MediaPlayer()
        mp.setAudioAttributes(attributes)
        try {
            mp.setWakeMode(ctx, PowerManager.PARTIAL_WAKE_LOCK)
        } catch (ignored: Exception) { }
        mp.setOnPreparedListener { ready ->
            if (player !== ready) return@setOnPreparedListener
            prepared = true
            errorsInARow = 0
            if (playWhenReady && requestFocus(ctx)) {
                try {
                    ready.start()
                    onPlaybackStarted()
                    return@setOnPreparedListener
                } catch (ignored: IllegalStateException) { }
            }
            afterPause()
        }
        mp.setOnCompletionListener { done -> if (player === done) onCompletion() }
        mp.setOnErrorListener { failed, _, _ ->
            if (player === failed) onPlaybackError()
            true
        }
        player = mp
        prepared = false
        try {
            mp.setDataSource(ctx, Uri.parse(song.uri))
            mp.prepareAsync()
        } catch (e: Exception) {
            onPlaybackError()
            return
        }
        ensureSession(ctx)
        updateSession()
        if (NovaMusicService.running) NovaMusicService.refresh(ctx) else NovaMusicService.start(ctx)
        publish(updateNotification = false)
    }

    private fun onCompletion() {
        when {
            repeat == Repeat.ONE -> {
                try {
                    player?.seekTo(0)
                    player?.start()
                    onPlaybackStarted()
                } catch (e: IllegalStateException) {
                    startCurrent()
                }
            }
            index < queue.size - 1 -> {
                index++
                startCurrent()
            }
            repeat == Repeat.ALL && queue.isNotEmpty() -> {
                index = 0
                startCurrent()
            }
            else -> {
                // End of the queue: stay on the last song, paused at the start.
                playWhenReady = false
                try { player?.seekTo(0) } catch (ignored: IllegalStateException) { }
                afterPause()
            }
        }
    }

    private fun onPlaybackError() {
        releasePlayer()
        errorsInARow++
        if (errorsInARow >= MAX_CONSECUTIVE_ERRORS || errorsInARow >= queue.size || index >= queue.size - 1) {
            stop()
            return
        }
        index++
        startCurrent()
    }

    private fun onPlaybackStarted() {
        main.removeCallbacks(idleStop)
        if (ducked) player?.setVolume(0.2f, 0.2f) else player?.setVolume(1f, 1f)
        registerNoisy()
        updateSession()
        session?.isActive = true
        publish()
    }

    private fun afterPause() {
        main.removeCallbacks(idleStop)
        main.postDelayed(idleStop, IDLE_STOP_MS)
        updateSession()
        publish()
    }

    private fun releasePlayer() {
        val p = player ?: return
        player = null
        prepared = false
        try { p.reset() } catch (ignored: Exception) { }
        try { p.release() } catch (ignored: Exception) { }
    }

    // ── Audio focus ──────────────────────────────────────────────────────────

    private fun requestFocus(context: Context): Boolean {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return true
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(focusListener, main)
                .setWillPauseWhenDucked(false)
                .build()
                .also { focusRequest = it }
            am.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocus() {
        val am = app?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(focusListener)
        }
        ducked = false
    }

    private fun onFocusChange(change: Int) {
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (ducked) {
                    ducked = false
                    try { player?.setVolume(1f, 1f) } catch (ignored: IllegalStateException) { }
                }
                if (resumeOnFocusGain) {
                    resumeOnFocusGain = false
                    val p = player
                    if (p != null && prepared && !isPlayingNow()) {
                        try {
                            p.start()
                            onPlaybackStarted()
                        } catch (ignored: IllegalStateException) { }
                    }
                }
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                // Another app started playing: stop for good (the user can press play again).
                pause()
                abandonFocus()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                // A call, or NOVA listening: pause and come back afterwards.
                if (isPlayingNow()) {
                    try { player?.pause() } catch (ignored: IllegalStateException) { }
                    resumeOnFocusGain = true
                    updateSession()
                    publish()
                }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                // NOVA (or a navigation app) is speaking: play quietly.
                ducked = true
                try { player?.setVolume(0.2f, 0.2f) } catch (ignored: IllegalStateException) { }
            }
        }
    }

    // ── Headphones unplugged ─────────────────────────────────────────────────

    private fun registerNoisy() {
        val ctx = app ?: return
        if (noisyRegistered) return
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                ctx.registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                ctx.registerReceiver(noisyReceiver, filter)
            }
            noisyRegistered = true
        } catch (ignored: Exception) { }
    }

    private fun unregisterNoisy() {
        if (!noisyRegistered) return
        noisyRegistered = false
        try { app?.unregisterReceiver(noisyReceiver) } catch (ignored: Exception) { }
    }

    // ── Media session (lock screen, headphones, Bluetooth, notification) ────

    private fun ensureSession(context: Context): MediaSession {
        session?.let { return it }
        val s = MediaSession(context, "NovaMusic")
        s.setCallback(object : MediaSession.Callback() {
            override fun onPlay() {
                resume()
            }

            override fun onPause() {
                pause()
            }

            override fun onSkipToNext() {
                next()
            }

            override fun onSkipToPrevious() {
                previous()
            }

            override fun onStop() {
                stop()
            }

            override fun onSeekTo(pos: Long) {
                seekTo(pos)
            }
        })
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            s.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
        }
        session = s
        return s
    }

    private fun updateSession() {
        val s = session ?: return
        val song = current()
        if (song != null) {
            s.setMetadata(
                MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, song.title)
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, song.artist)
                    .putString(MediaMetadata.METADATA_KEY_ALBUM, song.album)
                    .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs())
                    .build()
            )
        }
        val state = when (stateName()) {
            "playing" -> PlaybackState.STATE_PLAYING
            "buffering" -> PlaybackState.STATE_BUFFERING
            "paused" -> PlaybackState.STATE_PAUSED
            else -> PlaybackState.STATE_STOPPED
        }
        s.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SKIP_TO_NEXT or
                        PlaybackState.ACTION_SKIP_TO_PREVIOUS or PlaybackState.ACTION_STOP or
                        PlaybackState.ACTION_SEEK_TO
                )
                .setState(state, positionMs(), if (state == PlaybackState.STATE_PLAYING) 1f else 0f)
                .build()
        )
    }

    private fun publish(updateNotification: Boolean = true) {
        val snap = snapshot()
        for (l in listeners) {
            try { l(snap) } catch (ignored: Exception) { }
        }
        if (updateNotification) app?.let { NovaMusicService.refresh(it) }
    }
}
