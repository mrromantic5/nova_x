package com.tlyfe.nova_x.music

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import android.provider.MediaStore

/**
 * The songs saved on this phone, read from Android's media library
 * (MediaStore). Needs "Music and audio" access (READ_MEDIA_AUDIO on
 * Android 13+, storage read access before that). Works fully offline;
 * nothing is uploaded.
 */
object NovaMusicLibrary {
    private const val TTL_MS = 60_000L
    private const val MIN_DURATION_MS = 20_000L // skip ringtones, notification sounds, short clips

    @Volatile private var cache: List<NovaSong>? = null
    @Volatile private var cachedAt = 0L

    /** The runtime permission that grants access to music files on this Android version. */
    fun permissionName(): String =
        if (Build.VERSION.SDK_INT >= 33) "android.permission.READ_MEDIA_AUDIO"
        else Manifest.permission.READ_EXTERNAL_STORAGE

    fun hasPermission(context: Context): Boolean =
        context.checkSelfPermission(permissionName()) == PackageManager.PERMISSION_GRANTED

    fun songs(context: Context, refresh: Boolean = false): List<NovaSong> {
        if (!hasPermission(context)) return emptyList()
        val now = SystemClock.elapsedRealtime()
        val cached = cache
        if (!refresh && cached != null && now - cachedAt < TTL_MS) return cached
        val fresh = try { query(context) } catch (e: Exception) { cached ?: emptyList() }
        cache = fresh
        cachedAt = now
        return fresh
    }

    fun byId(context: Context, id: Long): NovaSong? = songs(context).firstOrNull { it.id == id }

    fun invalidate() {
        cache = null
    }

    private fun query(context: Context): List<NovaSong> {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.DISPLAY_NAME,
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val out = ArrayList<NovaSong>()
        context.contentResolver.query(collection, projection, selection, null, null)?.use { c ->
            val iId = c.getColumnIndex(MediaStore.Audio.Media._ID)
            val iTitle = c.getColumnIndex(MediaStore.Audio.Media.TITLE)
            val iArtist = c.getColumnIndex(MediaStore.Audio.Media.ARTIST)
            val iAlbum = c.getColumnIndex(MediaStore.Audio.Media.ALBUM)
            val iDuration = c.getColumnIndex(MediaStore.Audio.Media.DURATION)
            val iAdded = c.getColumnIndex(MediaStore.Audio.Media.DATE_ADDED)
            val iName = c.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
            if (iId < 0) return out
            while (c.moveToNext()) {
                val id = c.getLong(iId)
                val duration = if (iDuration >= 0) c.getLong(iDuration) else 0L
                if (duration in 1 until MIN_DURATION_MS) continue
                val fileName = (if (iName >= 0) c.getString(iName) else null)
                    ?.substringBeforeLast('.')
                    ?.replace('_', ' ')
                val title = (if (iTitle >= 0) c.getString(iTitle) else null)
                    ?.takeIf { it.isNotBlank() } ?: fileName ?: continue
                val artist = clean(if (iArtist >= 0) c.getString(iArtist) else null)
                val album = clean(if (iAlbum >= 0) c.getString(iAlbum) else null)
                val added = if (iAdded >= 0) c.getLong(iAdded) else 0L
                out.add(
                    NovaSong(
                        id = id,
                        title = title.trim(),
                        artist = artist,
                        album = album,
                        durationMs = duration,
                        uri = ContentUris.withAppendedId(collection, id).toString(),
                        dateAdded = added,
                    )
                )
            }
        }
        out.sortBy { NovaMusicMatcher.normalize(it.title) }
        return out
    }

    /** MediaStore uses "<unknown>" for missing tags. */
    private fun clean(value: String?): String {
        val v = value?.trim() ?: return ""
        return if (v.isEmpty() || v.equals("<unknown>", ignoreCase = true)) "" else v
    }
}
