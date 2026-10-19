package com.tlyfe.nova_x.nova

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
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
 *
 * Android → Dart events:
 *   onAmplitude(double) · onRecordingAutoStopped(reason)
 *   onTtsStart(id) · onTtsDone(id) · onTtsError(id) · onAssistInvoked(reason)
 *
 * One instance per Flutter engine (MainActivity and NovaAssistActivity each
 * create their own and dispose it in onDestroy).
 */
class NovaBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val onCloseRequested: (() -> Unit)? = null,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.tlyfe.nova_x/nova"
        const val REQ_PERMISSION = 9310

        private val PERMISSIONS = mapOf(
            "microphone" to Manifest.permission.RECORD_AUDIO,
            "contacts" to Manifest.permission.READ_CONTACTS,
            // Only a runtime permission from Android 13; granted before that.
            "notifications" to "android.permission.POST_NOTIFICATIONS",
        )

        private val ALLOWED_ACTIONS = setOf(
            "open_app", "search_in_app", "dial_number", "search_contacts",
            "open_settings", "navigate", "open_in_nova",
        )
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val recorder = NovaRecorder(activity.applicationContext) { event, arg -> emit(event, arg) }
    private val speaker = NovaSpeaker(activity.applicationContext) { event, arg -> emit(event, arg) }
    private val actions = NovaDeviceActions(activity)

    private var pendingPermission: MethodChannel.Result? = null
    private var disposed = false

    /** Why this window opened: "assist" (gesture) or "wake" ("Hey NOVA"). */
    var launchReason: String = "assist"

    // "Hey NOVA" steps aside while this engine's NOVA screens are open and visible.
    private val dartHolds: MutableSet<String> = java.util.concurrent.ConcurrentHashMap.newKeySet()
    @Volatile private var hostStarted = true
    private val holdProvider: () -> Boolean = { hostStarted && dartHolds.isNotEmpty() }

    init {
        channel.setMethodCallHandler(this)
        NovaMicArbiter.addProvider(holdProvider)
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
                        result.success(recorder.start(maxSeconds, autoStop))
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
                "runAction" -> result.success(runAction(call))
                "assistantStatus" -> result.success(NovaAssistantRole.status(activity))
                "openAssistantSettings" -> result.success(NovaAssistantRole.openSettings(activity))
                "closeAssistant" -> {
                    result.success(null)
                    main.post { onCloseRequested?.invoke() }
                }
                "launchReason" -> {
                    result.success(launchReason)
                    launchReason = "assist"
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
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("nova_native_error", e.message ?: "Unexpected native error", null)
        }
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
            else -> mapOf("status" to "unsupported")
        }
    }

    private fun requestPermission(kind: String, result: MethodChannel.Result) {
        val permission = PERMISSIONS[kind]
        if (permission == null) {
            result.success(false)
            return
        }
        if ((kind == "notifications" && Build.VERSION.SDK_INT < 33) || isGranted(permission)) {
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
            )
            main.post { if (!disposed) result.success(status) }
        }.start()
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
        pendingPermission?.success(false)
        pendingPermission = null
        channel.setMethodCallHandler(null)
    }

    private fun isGranted(permission: String): Boolean =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun emit(event: String, arg: Any?) {
        main.post {
            if (!disposed) channel.invokeMethod(event, arg)
        }
    }
}
