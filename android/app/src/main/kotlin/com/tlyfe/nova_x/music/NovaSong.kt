package com.tlyfe.nova_x.music

/**
 * One song saved on the phone (read from Android's media library).
 * Songs never leave the phone: only id/title/artist/album/duration are
 * passed to the NOVA X screens.
 */
data class NovaSong(
    val id: Long,
    val title: String,
    val artist: String,
    val album: String,
    val durationMs: Long,
    /** content://media/external/audio/media/<id> */
    val uri: String,
    val dateAdded: Long = 0L,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "title" to title,
        "artist" to artist,
        "album" to album,
        "durationMs" to durationMs,
    )
}
