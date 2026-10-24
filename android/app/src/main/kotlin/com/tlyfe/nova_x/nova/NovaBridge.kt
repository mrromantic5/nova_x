package com.tlyfe.nova_x.nova

import android.Manifest
import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import com.tlyfe.nova_x.music.NovaMusicBridge
import com.tlyfe.nova_x.music.NovaMusicCommands
import com.tlyfe.nova_x.music.NovaMusicLibrary
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The single, typed boundary between Dart and Android for NOVA
 * (channel "com.tlyfe.nova_x/nova").
 *
 * Dart → Android methods:
 *   startRecording{maxSeconds,autoStop} · stopRecording · cancelRecording
 *   speak{text,id} · stopSpeaking
 *   permissionStatus{kind} · requestPermission{kind} · openAppPermissionSettings
 *   runAction{action,args}   — action ∈ ALLOWED_ACTIONS only
 *   assistantStatus · openAssistantSettings · closeAssistant · launchReason
 *   wakeStatus · setWakeEnabled{enabled} · setWakeHold{reason,held} · openOverlaySettings
 *   saveImageToGallery{path}  — a NOVA AI photo → Pictures/NOVA X (Android 10+)
 *   screenCaptureRequest · screenCaptureGrab · screenCaptureCancel — "Read my screen"
 *     in the assistant panel: one screenshot after Android's consent dialog
 *     (NovaScreenCapture) · assistantKeepOpen{open} — keep the floating panel
 *     open while the photo picker / camera is in front · phoneLocked
 *   setWakeScreenOff{enabled} · openBatterySettings  — "Listen when the screen is off"
 *   (over the lock screen, runAction asks for the PIN first, except music)
 *   playVoiceFile{path,id} · stopVoiceFile          — NOVA's cloud voice (MP3 in the app cache)
 *   deviceInfo — NOVA Network: device, battery, connection, system (NovaDeviceInfo)
 *   networkStatus · startDeviceSpeech · stopDeviceSpeech · cancelDeviceSpeech — offline voice input
 *
 * Android → Dart events:
 *   onAmplitude(double) · onRecordingAutoStopped(reason)
 *   onTtsStart(id) · onTtsDone(id) · onTtsError(id) · onAssistInvoked(reason)
 *   onDeviceSpeech({kind: partial|result|error, text, code})
 *
 * NOVA Music has its own channel (NovaMusicBridge, created here).
 *
 * One instance per Flutter engine (MainActivity and NovaAssistActivity each
 * create their own and dispose it in onDestroy).
 */
class NovaBridge(
    private val activity: Activity,
    private val messenger: BinaryMessenger,
    private val onCloseRequested: (() -> Unit)? = null,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.tlyfe.nova_x/nova"
        const val REQ_PERMISSION = 9310

        /**
         * The bridge currently serving each engine: an old bridge being
         * disposed late must never unregister a newer one's channel handlers.
         */
        private val owners = java.util.WeakHashMap<BinaryMessenger, NovaBridge>()

        private val PERMISSIONS = mapOf(
            "microphone" to Manifest.permission.RECORD_AUDIO,
            "contacts" to Manifest.permission.READ_CONTACTS,
            // Only a runtime permission from Android 13; granted before that.
            "notifications" to "android.permission.POST_NOTIFICATIONS",
            // NOVA Music: "Music and audio" (Android 13+) or storage read access (older).
            "audio" to NovaMusicLibrary.permissionName(),
            // Saving NOVA AI images to the gallery on Android 9 and older only
            // (Android 10+ needs no permission for that).
            "storage" to Manifest.permission.WRITE_EXTERNAL_STORAGE,
        )

        private val ALLOWED_ACTIONS = setOf(
            "open_app", "search_in_app", "dial_number", "search_contacts",
            "open_settings", "navigate", "open_in_nova", "open_feature", "play_music", "music_control",
        )

        /** Allowed over the lock screen without unlocking (nothing private is shown). */
        private val LOCK_SCREEN_SAFE = setOf("play_music", "music_control")
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    /** Set by NovaAssistActivity: keeps the floating panel open while the
     *  photo picker or camera is in front. */
    var keepOpenHandler: ((Boolean) -> Unit)? = null
    private val main = Handler(Looper.getMainLooper())
    private val recorder = NovaRecorder(activity.applicationContext) { event, arg -> emit(event, arg) }
    private val speaker = NovaSpeaker(activity.applicationContext) { event, arg -> emit(event, arg) }
    private val actions = NovaDeviceActions(activity)
    private val voicePlayer = NovaVoicePlayer(activity.applicationContext) { event, arg -> emit(event, arg) }
    private val deviceSpeech = NovaDeviceSpeech(activity.applicationContext) { event, arg -> emit(event, arg) }
    private val music = NovaMusicBridge(activity.applicationContext, messenger)

    private var pendingPermission: MethodChannel.Result? = null
    private var disposed = false

    /**
     * Why this window opened: "assist" (gesture) or "wake" ("Hey NOVA").
     * Handed to Dart once; null when there is nothing to start (main app).
     */
    var launchReason: String? = null

    // "Hey NOVA" steps aside while this engine's NOVA screens are open and visible.
    private val dartHolds: MutableSet<String> = java.util.concurrent.ConcurrentHashMap.newKeySet()
    @Volatile private var hostStarted = true
    private val holdProvider: () -> Boolean = { hostStarted && dartHolds.isNotEmpty() }

    init {
        channel.setMethodCallHandler(this)
        NovaMicArbiter.addProvider(holdProvider)
        synchronized(owners) { owners[messenger] = this }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "startRecording" -> {
                    if (!isGranted(Manifest.permission.RECORD_AUDIO)) {
                        result.success(mapOf("status" to "permission_required"))
                    } else {
                        val maxSeconds = call.argument<Int>("maxSeconds") ?: 30
                        val autoStop = call.argument<Boolean>("autoStop") ?: true
                        recorder.startAsync(maxSeconds, autoStop) { status ->
                            if (!disposed) result.success(status)
                        }
                    }
                }
                "stopRecording" -> result.success(recorder.stop())
                "cancelRecording" -> {
                    recorder.cancel()
                    result.success(null)
                }
                "speak" -> {
                    val text = (call.argument<String>("text") ?: "").take(4000)
                    val id = (call.argument<String>("id") ?: "nova").take(64)
                    result.success(speaker.speak(text, id))
                }
                "stopSpeaking" -> {
                    speaker.stop()
                    result.success(null)
                }
                "permissionStatus" -> {
                    val kind = call.argument<String>("kind") ?: ""
                    val permission = PERMISSIONS[kind]
                    result.success(
                        when {
                            permission == null -> "unsupported"
                            kind == "notifications" && Build.VERSION.SDK_INT < 33 -> "granted"
                            isGranted(permission) -> "granted"
                            else -> "denied"
                        }
                    )
                }
                "requestPermission" -> requestPermission(call.argument<String>("kind") ?: "", result)
                "openAppPermissionSettings" -> result.success(actions.openAppDetailsSettings())
                "runAction" -> {
                    val action = call.argument<String>("action") ?: ""
                    if (action !in LOCK_SCREEN_SAFE && phoneLocked()) {
                        // NOVA is showing over the lock screen: ask for the PIN first.
                        unlockThen(result) { runActionNow(call, it) }
                    } else {
                        runActionNow(call, result)
                    }
                }
                "playVoiceFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    val id = (call.argument<String>("id") ?: "nova").take(64)
                    result.success(voicePlayer.play(path, id))
                }
                "stopVoiceFile" -> {
                    voicePlayer.stop()
                    result.success(null)
                }
                "networkStatus" -> result.success(mapOf("online" to isOnline()))
                "deviceInfo" -> {
                    // NOVA Network: device, battery, connection and system details.
                    val ctx = activity.applicationContext
                    Thread {
                        val info = NovaDeviceInfo.read(ctx)
                        main.post { if (!disposed) result.success(info) }
                    }.start()
                }
                "startDeviceSpeech" -> {
                    if (!isGranted(Manifest.permission.RECORD_AUDIO)) {
                        result.success(mapOf("status" to "permission_required"))
                    } else if (recorder.isActive()) {
                        result.success(mapOf("status" to "busy"))
                    } else {
                        speaker.stop()
                        voicePlayer.stop()
                        result.success(deviceSpeech.start())
                    }
                }
                "stopDeviceSpeech" -> {
                    deviceSpeech.stop()
                    result.success(null)
                }
                "cancelDeviceSpeech" -> {
                    deviceSpeech.cancel()
                    result.success(null)
                }
                "assistantStatus" -> result.success(NovaAssistantRole.status(activity))
                "openAssistantSettings" -> result.success(NovaAssistantRole.openSettings(activity))
                "closeAssistant" -> {
                    result.success(null)
                    main.post { onCloseRequested?.invoke() }
                }
                "launchReason" -> {
                    result.success(launchReason)
                    launchReason = null
                }
                "wakeStatus" -> wakeStatus(result)
                "setWakeEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val ctx = activity.applicationContext
                    if (enabled) {
                        NovaWakePrefs.setEnabled(ctx, true)
                        val started = NovaWakeService.start(activity)
                        if (!started) NovaWakePrefs.setEnabled(ctx, false)
                        result.success(started)
                    } else {
                        NovaWakePrefs.setEnabled(ctx, false)
                        NovaWakeService.stop(ctx)
                        result.success(true)
                    }
                }
                "setWakeHold" -> {
                    val reason = (call.argument<String>("reason") ?: "").take(32)
                    val held = call.argument<Boolean>("held") ?: false
                    if (reason.isNotEmpty()) {
                        if (held) dartHolds.add(reason) else if (dartHolds.remove(reason)) NovaMicArbiter.startCooldown()
                    }
                    result.success(null)
                }
                "openOverlaySettings" -> result.success(openOverlaySettings())
                "setWakeScreenOff" -> {
                    NovaWakePrefs.setScreenOffEnabled(activity.applicationContext, call.argument<Boolean>("enabled") ?: false)
                    result.success(true)
                }
                "setupStatus" -> {
                    // Rewards: every NOVA assistant setting the "NOVA setup" bonus needs.
                    val ctx = activity.applicationContext
                    val role = NovaAssistantRole.status(activity)
                    result.success(mapOf(
                        "assistant" to (role["held"] == true),
                        "microphone" to isGranted(Manifest.permission.RECORD_AUDIO),
                        "contacts" to isGranted(Manifest.permission.READ_CONTACTS),
                        "audio" to isGranted(NovaMusicLibrary.permissionName()),
                        "overlay" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(ctx)),
                        "battery" to batteryUnrestricted(ctx),
                    ))
                }
                "installId" -> result.success(installId(activity.applicationContext))
                "setBluetoothWake" -> {
                    NovaAudioRoute.setBluetoothWakeEnabled(activity.applicationContext, call.argument<Boolean>("enabled") ?: false)
                    result.success(true)
                }
                "setHeadsetMic" -> {
                    NovaAudioRoute.setHeadsetEnabled(activity.applicationContext, call.argument<Boolean>("enabled") ?: true)
                    result.success(true)
                }
                "openBatterySettings" -> result.success(openBatterySettings())
                "screenCaptureRequest" -> {
                    // Only the floating assistant reads other apps' screens.
                    if (activity !is com.tlyfe.nova_x.NovaAssistActivity) {
                        result.success(mapOf("status" to "unsupported"))
                    } else {
                        NovaScreenCapture.request(activity) { if (!disposed) result.success(it) }
                    }
                }
                "screenCaptureGrab" -> NovaScreenCapture.grab { if (!disposed) result.success(it) }
                "screenCaptureCancel" -> {
                    NovaScreenCapture.cancel()
                    result.success(true)
                }
                "assistantKeepOpen" -> {
                    keepOpenHandler?.invoke(call.argument<Boolean>("open") ?: false)
                    result.success(keepOpenHandler != null)
                }
                "phoneLocked" -> result.success(phoneLocked())
                "saveImageToGallery" -> {
                    val path = call.argument<String>("path") ?: ""
                    val ctx = activity.applicationContext
                    Thread {
                        val ok = saveImageToGallery(ctx, path)
                        main.post { if (!disposed) result.success(ok) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("nova_native_error", e.message ?: "Unexpected native error", null)
        }
    }

    private fun runActionNow(call: MethodCall, result: MethodChannel.Result) {
        if (call.argument<String>("action") == "play_music") playMusicAsync(call, result)
        else result.success(runAction(call))
    }

    private fun phoneLocked(): Boolean =
        (activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)?.isKeyguardLocked == true

    /** Shows Android's unlock prompt; runs [then] after a successful unlock. */
    private fun unlockThen(result: MethodChannel.Result, then: (MethodChannel.Result) -> Unit) {
        val km = activity.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (km == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(mapOf("status" to "locked"))
            return
        }
        var answered = false
        fun answer(block: () -> Unit) {
            if (answered || disposed) return
            answered = true
            block()
        }
        try {
            km.requestDismissKeyguard(activity, object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() {
                    main.post { answer { then(result) } }
                }
                override fun onDismissCancelled() {
                    main.post { answer { result.success(mapOf("status" to "locked")) } }
                }
                override fun onDismissError() {
                    main.post { answer { result.success(mapOf("status" to "locked")) } }
                }
            })
        } catch (e: Exception) {
            answer { result.success(mapOf("status" to "locked")) }
        }
        // Never leave NOVA waiting if the prompt is ignored or never answers.
        main.postDelayed({ answer { result.success(mapOf("status" to "locked")) } }, 60_000L)
    }

    private fun runAction(call: MethodCall): Map<String, Any?> {
        val name = call.argument<String>("action") ?: ""
        if (name !in ALLOWED_ACTIONS) return mapOf("status" to "unsupported")
        val rawArgs: Map<*, *> = call.argument<Map<*, *>>("args") ?: emptyMap<String, String>()
        val args = HashMap<String, String>()
        for ((k, v) in rawArgs) {
            if (k is String && v is String) args[k] = v.take(2048)
        }
        return when (name) {
            "open_app" -> actions.openApp(args["app"])
            "search_in_app" -> actions.searchInApp(args["app"], args["query"])
            "dial_number" -> actions.dial(args["number"])
            "search_contacts" ->
                if (isGranted(Manifest.permission.READ_CONTACTS)) actions.searchContacts(args["query"])
                else mapOf("status" to "permission_required")
            "open_settings" -> actions.openSettings(args["target"])
            "navigate" -> actions.navigate(args["destination"])
            "open_in_nova" -> actions.openInNova(args["url"])
            "open_feature" -> actions.openFeature(args["feature"])
            "music_control" -> NovaMusicCommands.control(activity.applicationContext, args["command"])
            else -> mapOf("status" to "unsupported")
        }
    }

    /** Reading the music library can take a moment: warm it off the UI thread, then play. */
    private fun playMusicAsync(call: MethodCall, result: MethodChannel.Result) {
        val rawArgs: Map<*, *> = call.argument<Map<*, *>>("args") ?: emptyMap<String, String>()
        val query = (rawArgs["query"] as? String)?.take(200)
        val songId = (rawArgs["song_id"] as? String)?.take(24)
        val ctx = activity.applicationContext
        Thread {
            try { NovaMusicLibrary.songs(ctx) } catch (ignored: Exception) { }
            main.post {
                if (disposed) return@post
                try {
                    result.success(NovaMusicCommands.play(ctx, query, songId))
                } catch (e: Exception) {
                    result.success(mapOf("status" to "error"))
                }
            }
        }.start()
    }

    private fun isOnline(): Boolean {
        val cm = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return true
        return try {
            val network = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(network) ?: return false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } catch (e: Exception) {
            true
        }
    }

    private fun requestPermission(kind: String, result: MethodChannel.Result) {
        val permission = PERMISSIONS[kind]
        if (permission == null) {
            result.success(false)
            return
        }
        if ((kind == "notifications" && Build.VERSION.SDK_INT < 33) ||
            (kind == "storage" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ||
            isGranted(permission)) {
            result.success(true)
            return
        }
        // Settle any request that is still waiting so its Future never hangs.
        pendingPermission?.success(false)
        pendingPermission = result
        activity.requestPermissions(arrayOf(permission), REQ_PERMISSION)
    }

    /** Called from the host Activity. Returns true when the result was ours. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQ_PERMISSION) return false
        val pending = pendingPermission ?: return true
        pendingPermission = null
        pending.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
        return true
    }

    /** The host is visible again. */
    fun onHostStart() {
        hostStarted = true
    }

    /** The host went to the background: never keep the microphone open,
     *  and stop talking to a user who has left. */
    fun onHostStop() {
        hostStarted = false
        if (recorder.isActive()) {
            recorder.cancel()
            emit("onRecordingAutoStopped", "interrupted")
        }
        speaker.stop()
        voicePlayer.stop()
        if (deviceSpeech.isActive()) {
            deviceSpeech.cancel()
            emit("onDeviceSpeech", mapOf("kind" to "error", "code" to "interrupted"))
        }
    }

    /** NOVA was invoked again (e.g. assistant gesture or "Hey NOVA" while already showing). */
    fun emitAssistInvoked(reason: String = "assist") = emit("onAssistInvoked", reason)

    private fun wakeStatus(result: MethodChannel.Result) {
        val ctx = activity.applicationContext
        // Loading the detector once to check support takes a moment: off the UI thread.
        Thread {
            val supported = try { NovaWakeService.isSupported(ctx) } catch (t: Throwable) { false }
            val status = mapOf(
                "supported" to supported,
                "enabled" to NovaWakePrefs.isEnabled(ctx),
                "running" to NovaWakeService.running,
                "background" to NovaWakeService.backgroundSupported(),
                "overlay" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(ctx)),
                "notifications" to (Build.VERSION.SDK_INT < 33 || isGranted("android.permission.POST_NOTIFICATIONS")),
                "microphone" to isGranted(Manifest.permission.RECORD_AUDIO),
                "error" to NovaWakeService.lastError,
                "screenOff" to NovaWakePrefs.screenOffEnabled(ctx),
                "batteryUnrestricted" to batteryUnrestricted(ctx),
                "headsetMic" to NovaAudioRoute.headsetEnabled(ctx),
                "btWake" to NovaAudioRoute.bluetoothWakeEnabled(ctx),
                "headset" to NovaAudioRoute.headsetKind(ctx),
            )
            main.post { if (!disposed) result.success(status) }
        }.start()
    }

    /**
     * Copies one of NOVA AI's saved photos to Pictures/NOVA X (Android 10+,
     * no storage permission needed). Only files inside NOVA X's own
     * nova_media folder are accepted.
     */
    private fun saveImageToGallery(ctx: Context, path: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return saveImageLegacy(ctx, path)
        return try {
            val root = java.io.File(ctx.getDir("flutter", Context.MODE_PRIVATE), "nova_media").canonicalPath + "/"
            val file = java.io.File(path).canonicalFile
            if (!file.path.startsWith(root) || !file.isFile || file.length() > 20L * 1024 * 1024) return false
            val name = file.name.lowercase()
            val mime = when {
                name.endsWith(".png") -> "image/png"
                name.endsWith(".webp") -> "image/webp"
                name.endsWith(".jpg") -> "image/jpeg"
                else -> return false
            }
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, "nova_${System.currentTimeMillis()}_${file.name}")
                put(android.provider.MediaStore.Images.Media.MIME_TYPE, mime)
                put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, "Pictures/NOVA X")
                put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
            }
            val resolver = ctx.contentResolver
            val uri = resolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: return false
            try {
                resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
                    ?: throw IllegalStateException("no stream")
                values.clear()
                values.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                true
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Android 7–9: copy into Pictures/NOVA X (needs the storage permission the
     * app asks for first) and let the gallery know about it.
     */
    @Suppress("DEPRECATION")
    private fun saveImageLegacy(ctx: Context, path: String): Boolean = try {
        val root = java.io.File(ctx.getDir("flutter", Context.MODE_PRIVATE), "nova_media").canonicalPath + "/"
        val file = java.io.File(path).canonicalFile
        val name = file.name.lowercase()
        if (!file.path.startsWith(root) || !file.isFile || file.length() > 20L * 1024 * 1024 ||
            !(name.endsWith(".jpg") || name.endsWith(".png") || name.endsWith(".webp")) ||
            !isGranted(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        ) {
            false
        } else {
            val dir = java.io.File(
                android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_PICTURES),
                "NOVA X",
            )
            dir.mkdirs()
            val out = java.io.File(dir, "nova_${System.currentTimeMillis()}_${file.name}")
            file.inputStream().use { input -> out.outputStream().use { input.copyTo(it) } }
            android.media.MediaScannerConnection.scanFile(ctx, arrayOf(out.absolutePath), null, null)
            true
        }
    } catch (e: Exception) {
        false
    }

    /**
     * A one-way identifier of this phone for NOVA X (SHA-256 of Android's
     * per-app ANDROID_ID with a NOVA X prefix). Used only so one phone's
     * setup bonuses can't be claimed again by switching accounts; the raw ID
     * never leaves the phone.
     */
    private fun installId(ctx: Context): String? = try {
        val raw = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ANDROID_ID)
        if (raw.isNullOrEmpty()) {
            null
        } else {
            val md = java.security.MessageDigest.getInstance("SHA-256")
            md.digest("novax-device:$raw".toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
        }
    } catch (e: Exception) {
        null
    }

    private fun batteryUnrestricted(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return try { pm.isIgnoringBatteryOptimizations(ctx.packageName) } catch (e: Exception) { false }
    }

    /** Android's battery-optimisation list (no special permission needed), else app info. */
    private fun openBatterySettings(): Boolean = try {
        activity.startActivity(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (e: Exception) {
        actions.openAppDetailsSettings()
    }

    private fun openOverlaySettings(): Boolean = try {
        activity.startActivity(
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${activity.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (e: Exception) {
        actions.openAppDetailsSettings()
    }

    fun dispose() {
        disposed = true
        NovaMicArbiter.removeProvider(holdProvider)
        dartHolds.clear()
        recorder.cancel()
        speaker.shutdown()
        voicePlayer.shutdown()
        deviceSpeech.cancel()
        val stillOwner = synchronized(owners) {
            (owners[messenger] === this).also { if (it) owners.remove(messenger) }
        }
        music.dispose(clearChannel = stillOwner)
        pendingPermission?.success(false)
        pendingPermission = null
        if (stillOwner) channel.setMethodCallHandler(null)
    }

    private fun isGranted(permission: String): Boolean =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun emit(event: String, arg: Any?) {
        main.post {
            if (!disposed) channel.invokeMethod(event, arg)
        }
    }
}
