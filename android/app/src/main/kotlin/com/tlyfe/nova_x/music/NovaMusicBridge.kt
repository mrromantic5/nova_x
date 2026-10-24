package com.tlyfe.nova_x.music

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Channel "com.tlyfe.nova_x/music" for the NOVA Music screen.
 *
 * Dart → Android:
 *   library{refresh} → {status: ok|permission_required, songs:[{id,title,artist,album,durationMs}]}
 *   playSongs{ids,index,shuffle?} · playAll · toggle · pause · resume · next · previous · stop
 *   seekTo{ms} · setShuffle{on} · setRepeat{mode: off|all|one} · state
 * Android → Dart:
 *   onMusicState(snapshot)  — see NovaMusicPlayer.snapshot()
 *
 * Permission requests go through the NOVA channel (kind "audio").
 */
class NovaMusicBridge(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.tlyfe.nova_x/music"
    }

    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var disposed = false

    private val listener: (Map<String, Any?>) -> Unit = { state ->
        main.post { if (!disposed) channel.invokeMethod("onMusicState", state) }
    }

    init {
        NovaMusicPlayer.init(appContext)
        NovaMusicPlayer.addListener(listener)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "library" -> library(call.argument<Boolean>("refresh") ?: false, result)
                "playSongs" -> playSongs(call, result)
                "playAll" -> {
                    val songs = NovaMusicLibrary.songs(appContext)
                    if (songs.isEmpty()) {
                        result.success(false)
                    } else {
                        result.success(NovaMusicPlayer.playQueue(appContext, songs, songs.indices.random(), true))
                    }
                }
                "toggle" -> { NovaMusicPlayer.toggle(); result.success(null) }
                "pause" -> { NovaMusicPlayer.pause(); result.success(null) }
                "resume" -> { NovaMusicPlayer.resume(); result.success(null) }
                "next" -> { NovaMusicPlayer.next(); result.success(null) }
                "previous" -> { NovaMusicPlayer.previous(); result.success(null) }
                "stop" -> { NovaMusicPlayer.stop(); result.success(null) }
                "seekTo" -> {
                    val ms = (call.argument<Any>("ms") as? Number)?.toLong() ?: 0L
                    NovaMusicPlayer.seekTo(ms)
                    result.success(null)
                }
                "setShuffle" -> {
                    NovaMusicPlayer.setShuffle(call.argument<Boolean>("on") ?: false)
                    result.success(null)
                }
                "setRepeat" -> {
                    val mode = when (call.argument<String>("mode")) {
                        "all" -> NovaMusicPlayer.Repeat.ALL
                        "one" -> NovaMusicPlayer.Repeat.ONE
                        else -> NovaMusicPlayer.Repeat.OFF
                    }
                    NovaMusicPlayer.setRepeat(mode)
                    result.success(null)
                }
                "state" -> result.success(NovaMusicPlayer.snapshot())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("nova_music_error", e.message ?: "Music error", null)
        }
    }

    private fun library(refresh: Boolean, result: MethodChannel.Result) {
        if (!NovaMusicLibrary.hasPermission(appContext)) {
            result.success(mapOf("status" to "permission_required", "songs" to emptyList<Any>()))
            return
        }
        // Reading thousands of songs can take a moment: off the UI thread.
        Thread {
            val songs = try {
                NovaMusicLibrary.songs(appContext, refresh)
            } catch (e: Exception) {
                emptyList()
            }
            val payload = mapOf("status" to "ok", "songs" to songs.map { it.toMap() })
            main.post { if (!disposed) result.success(payload) }
        }.start()
    }

    private fun playSongs(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<List<Any?>>("ids") ?: emptyList()
        val ids = raw.mapNotNull { (it as? Number)?.toLong() }
        val start = (call.argument<Any>("index") as? Number)?.toInt() ?: 0
        val shuffle = call.argument<Boolean>("shuffle")
        val byId = NovaMusicLibrary.songs(appContext).associateBy { it.id }
        val songs = ids.mapNotNull { byId[it] }
        if (songs.isEmpty()) {
            result.success(false)
            return
        }
        val startId = ids.getOrNull(start)
        val startIndex = songs.indexOfFirst { it.id == startId }.coerceAtLeast(0)
        result.success(NovaMusicPlayer.playQueue(appContext, songs, startIndex, shuffle))
    }

    /** [clearChannel] false: a newer bridge already serves this engine — leave its handler. */
    fun dispose(clearChannel: Boolean = true) {
        disposed = true
        NovaMusicPlayer.removeListener(listener)
        if (clearChannel) channel.setMethodCallHandler(null)
    }
}
