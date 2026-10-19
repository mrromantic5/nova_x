package com.tlyfe.nova_x.nova

import android.os.SystemClock
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

/**
 * Decides when the "Hey NOVA" listener may use the microphone.
 *
 * The wake-word listener steps aside whenever NOVA X itself needs the
 * microphone or is talking:
 *  - NOVA is recording a command (NovaRecorder),
 *  - NOVA is speaking (phone voice or Brains Jet voice) — otherwise NOVA's
 *    own "Hi, NOVA is active…" could wake it again,
 *  - the NOVA panel or NOVA AI chat is open (reported from Dart),
 *  - shortly after any of these end (cool-down).
 *
 * Shared by every Flutter engine in the process (main app + floating panel).
 */
object NovaMicArbiter {
    private const val COOLDOWN_MS = 1500L

    private val holds: MutableSet<String> = ConcurrentHashMap.newKeySet()
    private val providers = CopyOnWriteArrayList<() -> Boolean>()
    private val visibleActivities = AtomicInteger(0)

    @Volatile private var cooldownUntil = 0L
    @Volatile private var pausedUntil = 0L

    /** True while the wake-word listener has the microphone open. */
    @Volatile var wakeMicOpen = false

    fun hold(reason: String, held: Boolean) {
        if (held) {
            holds.add(reason)
        } else if (holds.remove(reason)) {
            cooldownUntil = SystemClock.elapsedRealtime() + COOLDOWN_MS
        }
    }

    /** A dynamic hold (e.g. a Flutter engine's panel state while its screen is visible). */
    fun addProvider(provider: () -> Boolean) {
        providers.add(provider)
    }

    fun removeProvider(provider: () -> Boolean) {
        if (providers.remove(provider)) {
            cooldownUntil = SystemClock.elapsedRealtime() + COOLDOWN_MS
        }
    }

    /** Short pause after NOVA stops using the microphone or speaker. */
    fun startCooldown() {
        cooldownUntil = SystemClock.elapsedRealtime() + COOLDOWN_MS
    }

    /** Pause the listener for a fixed time (after a detection). */
    fun pauseFor(ms: Long) {
        pausedUntil = SystemClock.elapsedRealtime() + ms
    }

    fun isHeld(): Boolean {
        val now = SystemClock.elapsedRealtime()
        if (now < cooldownUntil || now < pausedUntil) return true
        if (holds.isNotEmpty()) return true
        for (p in providers) {
            if (try { p() } catch (ignored: Exception) { false }) return true
        }
        return false
    }

    fun activityStarted() {
        visibleActivities.incrementAndGet()
    }

    fun activityStopped() {
        if (visibleActivities.decrementAndGet() < 0) visibleActivities.set(0)
    }

    /** True while a NOVA X screen (browser or floating panel) is visible. */
    fun appVisible(): Boolean = visibleActivities.get() > 0

    /**
     * Called before NOVA records a command: wait (briefly) until the wake-word
     * listener has released the microphone. Android 7–9 allow only one
     * recorder at a time.
     */
    fun awaitWakeMicReleased(timeoutMs: Long = 400L) {
        val end = SystemClock.elapsedRealtime() + timeoutMs
        while (wakeMicOpen && SystemClock.elapsedRealtime() < end) {
            try {
                Thread.sleep(15)
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            }
        }
    }
}
