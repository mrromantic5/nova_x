package com.tlyfe.nova_x.music

import java.text.Normalizer

/**
 * Finds the song the user asked for ("play me Tatiana Like You",
 * "play Like You by Tatiana", "play Burna Boy") among the songs on the phone.
 *
 * Pure Kotlin (no Android classes) so it can be tested on any JVM.
 * Matching is token based and forgiving: accents, punctuation, "feat.",
 * "(Official Video)", "Artist - Title" file names, small spelling slips
 * (one letter) and word prefixes are all handled.
 */
object NovaMusicMatcher {

    sealed class Result {
        /** One clear song. [queue] starts with it (then more by the same artist). */
        data class Song(val song: NovaSong, val queue: List<NovaSong>) : Result()

        /** The user named an artist: play their songs. */
        data class Artist(val name: String, val songs: List<NovaSong>) : Result()

        /** Several songs fit equally well: ask which one. */
        data class Choices(val songs: List<NovaSong>) : Result()

        object None : Result()
    }

    /** Filler words that never decide a match (removed from query and songs alike). */
    private val STOP = setOf(
        "the", "a", "an", "me", "my", "us", "please", "some", "song", "songs", "track",
        "tracks", "music", "tune", "tunes", "by", "of", "to", "for", "from", "on", "in",
        "and", "feat", "ft", "featuring", "official", "audio", "video", "lyrics", "lyric",
        "visualizer", "hd", "hq", "mp3", "m4a", "version", "play", "called", "titled",
    )

    private const val MIN_SCORE = 0.45
    private const val CLEAR_MARGIN = 0.08
    private const val MAX_CHOICES = 4

    private val combiningMarks = Regex("\\p{Mn}+")
    private val nonAlphaNum = Regex("[^\\p{L}\\p{N}]+")
    private val brackets = Regex("[(\\[{][^)\\]}]*[)\\]}]")

    fun normalize(s: String): String {
        val noAccents = combiningMarks.replace(Normalizer.normalize(s.lowercase(), Normalizer.Form.NFD), "")
        return nonAlphaNum.replace(noAccents.replace("&", " and "), " ").trim()
    }

    fun tokens(s: String): List<String> =
        normalize(s).split(' ').filter { it.isNotEmpty() && it !in STOP }

    /** Title without "(Official Video)"-style brackets and without an "Artist - " prefix. */
    private class Parsed(song: NovaSong) {
        val fullTitle: List<String>
        val coreTitle: List<String>
        val artist: List<String>
        val album: List<String>

        init {
            var core = brackets.replace(song.title, " ")
            var artistText = song.artist
            val dash = core.split(" - ", limit = 2)
            if (dash.size == 2 && dash[0].isNotBlank() && dash[1].isNotBlank()) {
                val left = tokens(dash[0])
                val known = tokens(artistText)
                if (known.isEmpty() || left.any { l -> known.any { tokenMatch(l, it) } }) {
                    core = dash[1]
                    if (known.isEmpty()) artistText = dash[0]
                }
            }
            fullTitle = tokens(song.title)
            coreTitle = tokens(core)
            artist = tokens(artistText)
            album = tokens(song.album)
        }
    }

    private data class Scored(
        val song: NovaSong,
        val parsed: Parsed,
        val score: Double,
        val titleCoverage: Double,
        val queryInTitle: Int,
        val queryInArtist: Int,
    )

    fun tokenMatch(q: String, t: String): Boolean {
        if (q == t) return true
        if (q.length >= 4 && t.startsWith(q)) return true
        if (t.length >= 4 && q.startsWith(t) && q.length - t.length <= 2) return true
        if (q.length >= 5 && t.length >= 5 && kotlin.math.abs(q.length - t.length) <= 1 && editDistance(q, t) <= 1) return true
        if (q.length >= 8 && t.length >= 8 && kotlin.math.abs(q.length - t.length) <= 2 && editDistance(q, t) <= 2) return true
        return false
    }

    fun editDistance(a: String, b: String): Int {
        val prev = IntArray(b.length + 1) { it }
        val cur = IntArray(b.length + 1)
        for (i in 1..a.length) {
            cur[0] = i
            for (j in 1..b.length) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                cur[j] = minOf(cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
            }
            System.arraycopy(cur, 0, prev, 0, cur.size)
        }
        return prev[b.length]
    }

    private fun anyMatch(q: String, list: List<String>) = list.any { tokenMatch(q, it) }

    private fun score(query: List<String>, song: NovaSong): Scored? {
        val p = Parsed(song)
        val everything = p.fullTitle + p.coreTitle + p.artist + p.album
        val matched = query.count { anyMatch(it, everything) }
        val queryCoverage = matched.toDouble() / query.size
        if (queryCoverage < 0.5) return null

        val titleMatched = p.coreTitle.count { t -> query.any { tokenMatch(it, t) } }
        val titleCoverage = if (p.coreTitle.isEmpty()) 0.0 else titleMatched.toDouble() / p.coreTitle.size
        val artistMatched = p.artist.count { a -> query.any { tokenMatch(it, a) } }
        val artistCoverage = if (p.artist.isEmpty()) 0.0 else artistMatched.toDouble() / p.artist.size

        val q = " " + query.joinToString(" ") + " "
        val t = p.coreTitle.joinToString(" ")
        val phrase = when {
            t.isNotEmpty() && q.contains(" $t ") -> 0.2
            t.isNotEmpty() && query.joinToString(" ").length >= 4 && t.contains(query.joinToString(" ")) -> 0.1
            else -> 0.0
        }
        val s = 0.55 * queryCoverage + 0.3 * titleCoverage + 0.15 * artistCoverage + phrase
        return Scored(
            song = song,
            parsed = p,
            score = s,
            titleCoverage = titleCoverage,
            queryInTitle = query.count { anyMatch(it, p.fullTitle + p.coreTitle) },
            queryInArtist = query.count { anyMatch(it, p.artist) },
        )
    }

    /** Same song saved twice (e.g. two downloads) → keep one. */
    private fun dedupe(list: List<Scored>): List<Scored> {
        val seen = HashSet<String>()
        return list.filter { seen.add(it.parsed.coreTitle.joinToString(" ") + "|" + it.parsed.artist.joinToString(" ")) }
    }

    fun find(query: String, songs: List<NovaSong>): Result {
        val q = tokens(query)
        if (q.isEmpty() || songs.isEmpty()) return Result.None

        val scored = songs.mapNotNull { score(q, it) }
            .sortedWith(
                compareByDescending<Scored> { it.score }
                    .thenBy { it.parsed.coreTitle.size }
                    .thenByDescending { it.song.dateAdded },
            )
        if (scored.isEmpty() || scored.first().score < MIN_SCORE) return Result.None

        // "play Burna Boy": every word names the artist and no title fits better.
        val fullTitleHit = scored.firstOrNull { it.queryInTitle == q.size && it.titleCoverage >= 0.5 }
        val artistHits = scored.filter { it.queryInArtist == q.size }
        if (fullTitleHit == null && artistHits.isNotEmpty()) {
            val bySongs = dedupe(artistHits).map { it.song }
            val name = bySongs.groupingBy { it.artist }.eachCount().maxByOrNull { it.value }?.key ?: query
            return Result.Artist(name, bySongs.sortedBy { normalize(it.title) })
        }

        val unique = dedupe(scored)
        val top = unique.first()
        val close = unique.filter { top.score - it.score < CLEAR_MARGIN }
        if (close.size > 1) return Result.Choices(close.take(MAX_CHOICES).map { it.song })

        val sameArtist = if (top.parsed.artist.isEmpty()) emptyList() else songs.filter { s ->
            s.id != top.song.id && tokens(s.artist) == top.parsed.artist
        }.sortedBy { normalize(it.title) }
        return Result.Song(top.song, listOf(top.song) + sameArtist)
    }
}
