package com.tlyfe.nova_x.capture

/**
 * Pause bookkeeping for a recording, in microseconds of the encoder clock.
 * Pure logic (no Android types) so it is unit-tested on the JVM.
 *
 * [map] turns a capture timestamp into a timestamp in the saved video:
 * samples inside a pause are dropped (-1) and later samples are shifted back
 * by the total paused time, so the video plays straight through.
 */
class PauseTimeline {
    private val pauses = ArrayList<LongArray>() // [start, end); end = OPEN while paused

    companion object {
        const val OPEN = Long.MAX_VALUE
    }

    @Synchronized fun pause(atUs: Long) {
        if (isPaused()) return
        pauses.add(longArrayOf(atUs, OPEN))
    }

    @Synchronized fun resume(atUs: Long) {
        val last = pauses.lastOrNull() ?: return
        if (last[1] == OPEN) last[1] = maxOf(atUs, last[0])
    }

    @Synchronized fun isPaused(): Boolean = pauses.lastOrNull()?.get(1) == OPEN

    /** Total paused time that has ended (µs). */
    @Synchronized fun pausedUs(): Long = pauses.filter { it[1] != OPEN }.sumOf { it[1] - it[0] }

    @Synchronized fun map(ptsUs: Long): Long {
        var shift = 0L
        for (p in pauses) {
            if (ptsUs >= p[0] && ptsUs < p[1]) return -1
            if (p[1] != OPEN && p[1] <= ptsUs) shift += p[1] - p[0]
        }
        return ptsUs - shift
    }
}
