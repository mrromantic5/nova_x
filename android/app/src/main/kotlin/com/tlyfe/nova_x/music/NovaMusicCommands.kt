package com.tlyfe.nova_x.music

import android.content.Context
import android.media.AudioManager

/**
 * NOVA's voice commands for music ("Hey NOVA, play me Tatiana Like You",
 * "pause the music", "next song"). Called through the NOVA channel's
 * runAction (actions "play_music" and "music_control"). Everything happens
 * on the phone, so it works offline.
 *
 * Results:
 *   success {kind: song|artist|all, title, artist, count}
 *   choices {matches:[{id,title,artist}]}   — several songs fit equally well
 *   not_found · empty (no music on the phone) · permission_required
 *   not_playing · invalid
 *
 * music_control also adjusts the phone's media volume:
 *   volume_up · volume_down · mute · unmute (Android shows its volume bar)
 * and the player modes: shuffle_on · shuffle_off · repeat_one · repeat_all ·
 *   repeat_off · restart (the current song from the beginning).
 */
object NovaMusicCommands {

    fun play(context: Context, query: String?, songId: String?): Map<String, Any?> {
        if (!NovaMusicLibrary.hasPermission(context)) return mapOf("status" to "permission_required")
        val songs = NovaMusicLibrary.songs(context)
        if (songs.isEmpty()) return mapOf("status" to "empty")

        val id = songId?.trim()?.toLongOrNull()
        if (id != null) {
            val song = songs.firstOrNull { it.id == id } ?: return mapOf("status" to "not_found")
            val queue = listOf(song) + songs.filter {
                it.id != song.id && it.artist.isNotBlank() && it.artist == song.artist
            }
            NovaMusicPlayer.playQueue(context, queue, 0, false)
            return success("song", song, queue.size)
        }

        val q = query?.trim().orEmpty()
        if (q.isEmpty()) {
            NovaMusicPlayer.playQueue(context, songs, songs.indices.random(), true)
            val first = NovaMusicPlayer.current() ?: songs.first()
            return success("all", first, songs.size)
        }

        return when (val r = NovaMusicMatcher.find(q, songs)) {
            is NovaMusicMatcher.Result.Song -> {
                NovaMusicPlayer.playQueue(context, r.queue, 0, false)
                success("song", r.song, r.queue.size)
            }
            is NovaMusicMatcher.Result.Artist -> {
                NovaMusicPlayer.playQueue(context, r.songs, 0, false)
                success("artist", r.songs.first(), r.songs.size) + mapOf("artistName" to r.name)
            }
            is NovaMusicMatcher.Result.Choices -> mapOf(
                "status" to "choices",
                "matches" to r.songs.map {
                    mapOf("id" to it.id.toString(), "title" to it.title, "artist" to it.artist)
                },
            )
            NovaMusicMatcher.Result.None -> mapOf("status" to "not_found")
        }
    }

    fun control(context: Context, command: String?): Map<String, Any?> {
        NovaMusicPlayer.init(context)
        val song = NovaMusicPlayer.current()
        val active = NovaMusicPlayer.hasSong()
        return when (command) {
            "pause" -> {
                if (!NovaMusicPlayer.isPlayingNow()) mapOf("status" to "not_playing")
                else { NovaMusicPlayer.pause(); success("pause", song, 0) }
            }
            "resume" -> {
                if (song == null) mapOf("status" to "not_playing")
                else { NovaMusicPlayer.resume(); success("resume", song, 0) }
            }
            "next" -> {
                if (song == null) mapOf("status" to "not_playing")
                else { NovaMusicPlayer.next(); success("next", NovaMusicPlayer.current(), 0) }
            }
            "previous" -> {
                if (song == null) mapOf("status" to "not_playing")
                else { NovaMusicPlayer.previous(); success("previous", NovaMusicPlayer.current(), 0) }
            }
            "stop" -> {
                if (!active) mapOf("status" to "not_playing")
                else { NovaMusicPlayer.stop(); success("stop", song, 0) }
            }
            "now_playing" -> {
                if (!active || song == null) mapOf("status" to "not_playing")
                else success("now_playing", song, 0) + mapOf("playing" to NovaMusicPlayer.isPlayingNow())
            }
            "shuffle_on", "shuffle_off" -> {
                NovaMusicPlayer.setShuffle(command == "shuffle_on")
                success(command, song, 0)
            }
            "repeat_one", "repeat_all", "repeat_off" -> {
                NovaMusicPlayer.setRepeat(
                    when (command) {
                        "repeat_one" -> NovaMusicPlayer.Repeat.ONE
                        "repeat_all" -> NovaMusicPlayer.Repeat.ALL
                        else -> NovaMusicPlayer.Repeat.OFF
                    },
                )
                success(command, song, 0)
            }
            "restart" -> {
                if (!active || song == null) mapOf("status" to "not_playing")
                else {
                    NovaMusicPlayer.seekTo(0)
                    if (!NovaMusicPlayer.isPlayingNow()) NovaMusicPlayer.resume()
                    success("restart", song, 0)
                }
            }
            "volume_up" -> volume(context, AudioManager.ADJUST_RAISE, "volume_up")
            "volume_down" -> volume(context, AudioManager.ADJUST_LOWER, "volume_down")
            "mute" -> volume(context, AudioManager.ADJUST_MUTE, "mute")
            "unmute" -> volume(context, AudioManager.ADJUST_UNMUTE, "unmute")
            else -> mapOf("status" to "invalid")
        }
    }

    private fun volume(context: Context, direction: Int, kind: String): Map<String, Any?> {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return mapOf("status" to "unsupported")
        return try {
            am.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
            mapOf("status" to "success", "kind" to kind)
        } catch (e: SecurityException) {
            mapOf("status" to "unsupported") // e.g. Do Not Disturb rules
        }
    }

    private fun success(kind: String, song: NovaSong?, count: Int): Map<String, Any?> = mapOf(
        "status" to "success",
        "kind" to kind,
        "title" to song?.title,
        "artist" to song?.artist,
        "count" to count,
    )
}
