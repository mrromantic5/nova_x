package com.tlyfe.nova_x.capture

/**
 * NOVA Capture — the contract shared with Dart (lib/features/nova_capture).
 *
 * Channel: com.tlyfe.nova_x/capture (one MethodChannel per Flutter engine).
 *
 * Dart → Kotlin methods (all return a Map):
 *   getState                         → snapshot (see CaptureCoordinator.snapshot)
 *   capabilities                     → {sdk, deviceAudio, micAudio, overlayPermission, notificationsGranted, micGranted, storageGranted, needsStoragePermission}
 *   startRecording {config}          → {success, state, sessionId} | {success:false, errorCode, userMessage}
 *   pauseRecording {sessionId?}      → result
 *   resumeRecording {sessionId?}     → result
 *   stopRecording {sessionId?}       → result (the file is reported later by a "capture.event" recordingSaved)
 *   cancelRecording {sessionId?}     → result
 *   captureScreen {hideApp, delayMs} → {success, item} | error   (full-device screenshot)
 *   saveImage {bytes, name?, format, quality} → {success, item}
 *   listMedia {}                     → {success, items:[item]}
 *   readBytes {uri}                  → {success, bytes}
 *   thumbnail {uri, kind, size}      → {success, bytes}
 *   rename {uri, name}               → {success, item}
 *   delete {uri}                     → {success} | {errorCode: NEEDS_USER_APPROVAL → system dialog, then {success}}
 *   share {uri} · openExternal {uri} · copyImage {uri} · exportTo {uri} → result
 *   storageInfo                      → {success, freeBytes, totalBytes}
 *   requestPermissions {kinds:[mic|notifications|storage]} → {mic, notifications, storage}
 *   openOverlaySettings · openAppSettings → result
 *
 * Kotlin → Dart (invokeMethod):
 *   capture.state {snapshot}         — every state change (the single source of truth)
 *   capture.event {type, ...}        — one-off events (EVENT_* below)
 */
object CaptureContract {
    const val CHANNEL = "com.tlyfe.nova_x/capture"

    // ── Recording states ────────────────────────────────────────────────────
    const val IDLE = "idle"
    const val AWAITING_CONSENT = "awaiting_consent"
    const val STARTING = "starting"
    const val RECORDING = "recording"
    const val PAUSED = "paused"
    const val STOPPING = "stopping"
    const val FINALIZING = "finalizing"
    const val SAVED = "saved"
    const val CANCELLED = "cancelled"
    const val FAILED = "failed"

    /** States in which a session exists (a new one can't start). */
    val ACTIVE = setOf(AWAITING_CONSENT, STARTING, RECORDING, PAUSED, STOPPING, FINALIZING)

    private val TRANSITIONS: Map<String, Set<String>> = mapOf(
        IDLE to setOf(AWAITING_CONSENT),
        SAVED to setOf(AWAITING_CONSENT, IDLE),
        CANCELLED to setOf(AWAITING_CONSENT, IDLE),
        FAILED to setOf(AWAITING_CONSENT, IDLE),
        AWAITING_CONSENT to setOf(STARTING, CANCELLED, FAILED),
        STARTING to setOf(RECORDING, CANCELLED, FAILED),
        RECORDING to setOf(PAUSED, STOPPING, CANCELLED, FAILED),
        PAUSED to setOf(RECORDING, STOPPING, CANCELLED, FAILED),
        STOPPING to setOf(FINALIZING, CANCELLED, FAILED),
        FINALIZING to setOf(SAVED, FAILED),
    )

    fun canMove(from: String, to: String): Boolean = TRANSITIONS[from]?.contains(to) == true

    // ── Events (capture.event → type) ───────────────────────────────────────
    const val EVENT_PERMISSION_REQUIRED = "capture.permissionRequired"
    const val EVENT_PERMISSION_GRANTED = "capture.permissionGranted"
    const val EVENT_PERMISSION_DENIED = "capture.permissionDenied"
    const val EVENT_SCREENSHOT_STARTED = "capture.screenshotStarted"
    const val EVENT_SCREENSHOT_COMPLETED = "capture.screenshotCompleted"
    const val EVENT_SCREENSHOT_FAILED = "capture.screenshotFailed"
    const val EVENT_RECORDING_STARTED = "capture.recordingStarted"
    const val EVENT_RECORDING_PAUSED = "capture.recordingPaused"
    const val EVENT_RECORDING_RESUMED = "capture.recordingResumed"
    const val EVENT_RECORDING_STOPPED = "capture.recordingStopped"
    const val EVENT_RECORDING_SAVED = "capture.recordingSaved"
    const val EVENT_RECORDING_CANCELLED = "capture.recordingCancelled"
    const val EVENT_RECORDING_INTERRUPTED = "capture.recordingInterrupted"
    const val EVENT_RECORDING_FAILED = "capture.recordingFailed"
    const val EVENT_MEDIA_AVAILABLE = "capture.mediaAvailable"
    const val EVENT_WARNING = "capture.warning"

    // ── Stable error codes ──────────────────────────────────────────────────
    const val E_CONSENT_DENIED = "CONSENT_DENIED"
    const val E_PERMISSION = "PERMISSION_REQUIRED"
    const val E_BUSY = "BUSY"
    const val E_BUSY_RECORDING = "BUSY_RECORDING"
    const val E_INVALID_STATE = "INVALID_STATE"
    const val E_STALE_SESSION = "STALE_SESSION"
    const val E_UNSUPPORTED = "UNSUPPORTED"
    const val E_LOW_STORAGE = "LOW_STORAGE"
    const val E_LOCKED = "DEVICE_LOCKED"
    const val E_ENCODER = "ENCODER_FAILED"
    const val E_AUDIO = "AUDIO_UNAVAILABLE"
    const val E_SAVE = "SAVE_FAILED"
    const val E_TOO_SHORT = "TOO_SHORT"
    const val E_INTERRUPTED = "INTERRUPTED"
    const val E_PROTECTED = "PROTECTED_CONTENT"
    const val E_NOT_FOUND = "NOT_FOUND"
    const val E_INVALID_ARGUMENT = "INVALID_ARGUMENT"
    const val E_NEEDS_APPROVAL = "NEEDS_USER_APPROVAL"
    const val E_NO_ACTIVITY = "NO_ACTIVITY"
    const val E_TIMEOUT = "TIMEOUT"
    const val E_CANCELLED = "CANCELLED"
    const val E_ERROR = "ERROR"

    // ── Audio modes ─────────────────────────────────────────────────────────
    const val AUDIO_NONE = "none"
    const val AUDIO_MIC = "mic"
    const val AUDIO_DEVICE = "device"
    const val AUDIO_BOTH = "mic_device"

    fun usesMic(mode: String) = mode == AUDIO_MIC || mode == AUDIO_BOTH
    fun usesDevice(mode: String) = mode == AUDIO_DEVICE || mode == AUDIO_BOTH

    // ── Storage ─────────────────────────────────────────────────────────────
    const val SCREENSHOT_DIR = "Pictures/NOVA X/Screenshots"
    const val RECORDING_DIR = "Movies/NOVA X/Recordings"

    /** Refuse to start below this much free space; stop & save below the second. */
    const val MIN_FREE_TO_START = 300L * 1024 * 1024
    const val MIN_FREE_WHILE_RECORDING = 150L * 1024 * 1024

    fun ok(vararg pairs: Pair<String, Any?>): Map<String, Any?> = mapOf("success" to true, *pairs)

    fun error(code: String, message: String, vararg pairs: Pair<String, Any?>): Map<String, Any?> =
        mapOf("success" to false, "errorCode" to code, "userMessage" to message, *pairs)
}

/** Recording settings chosen in NOVA Capture (validated; unknown values fall back to defaults). */
data class RecordingConfig(
    val resolution: String = "auto",   // auto | 1080 | 720 | 480
    val fps: Int = 30,                 // 24 | 30 | 60
    val bitrate: String = "auto",      // auto | low | medium | high
    val orientation: String = "auto",  // auto | portrait | landscape
    val audio: String = CaptureContract.AUDIO_NONE,
    val maxDurationSec: Int = 0,       // 0 = no limit
    val countdownSec: Int = 3,         // 0..10
    val overlayEnabled: Boolean = false,
) {
    companion object {
        fun from(raw: Any?): RecordingConfig {
            val m = raw as? Map<*, *> ?: return RecordingConfig()
            fun s(k: String) = m[k] as? String
            fun i(k: String) = (m[k] as? Number)?.toInt()
            return RecordingConfig(
                resolution = s("resolution")?.takeIf { it in setOf("auto", "1080", "720", "480") } ?: "auto",
                fps = i("fps")?.takeIf { it in setOf(24, 30, 60) } ?: 30,
                bitrate = s("bitrate")?.takeIf { it in setOf("auto", "low", "medium", "high") } ?: "auto",
                orientation = s("orientation")?.takeIf { it in setOf("auto", "portrait", "landscape") } ?: "auto",
                audio = s("audio")?.takeIf {
                    it in setOf(CaptureContract.AUDIO_NONE, CaptureContract.AUDIO_MIC,
                        CaptureContract.AUDIO_DEVICE, CaptureContract.AUDIO_BOTH)
                } ?: CaptureContract.AUDIO_NONE,
                maxDurationSec = (i("maxDurationSec") ?: 0).coerceIn(0, 4 * 3600),
                countdownSec = (i("countdownSec") ?: 3).coerceIn(0, 10),
                overlayEnabled = m["overlayEnabled"] == true,
            )
        }
    }
}
