package com.tlyfe.nova_x.capture

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.app.RecoverableSecurityException
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * The NOVA Capture MethodChannel for one Flutter engine (main app or the
 * floating NOVA panel). See [CaptureContract] for the method list. All state
 * lives in [CaptureCoordinator]; this class validates arguments, runs file
 * work off the main thread and relays state/events to Dart.
 */
class CaptureChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, CaptureCoordinator.Listener {

    companion object {
        const val REQ_PERMISSIONS = 9411
        const val REQ_EXPORT = 9412
        const val REQ_DELETE = 9413
        private const val MAX_IMAGE_BYTES = 60 * 1024 * 1024
    }

    private val channel = MethodChannel(messenger, CaptureContract.CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val ctx: Context = activity.applicationContext
    private var disposed = false

    private var pendingPermissions: MethodChannel.Result? = null
    private var pendingExport: Pair<Uri, MethodChannel.Result>? = null
    private var pendingDelete: Pair<Uri, MethodChannel.Result>? = null

    init {
        channel.setMethodCallHandler(this)
        CaptureCoordinator.addListener(this)
        CaptureCoordinator.attach(activity, activity)
    }

    override fun onCapture(method: String, payload: Map<String, Any?>) {
        if (disposed) return
        try { channel.invokeMethod(method, payload) } catch (e: Exception) { }
    }

    fun dispose() {
        disposed = true
        CaptureCoordinator.removeListener(this)
        channel.setMethodCallHandler(null)
        pendingPermissions = null
        pendingExport = null
        pendingDelete = null
        io.shutdown()
    }

    private fun reply(result: MethodChannel.Result, value: Map<String, Any?>) {
        if (disposed) return
        try { result.success(value) } catch (e: Exception) { }
    }

    /** Runs [work] off the main thread and replies on the main thread. */
    private fun background(result: MethodChannel.Result, work: () -> Map<String, Any?>) {
        try {
            io.execute {
                val r = try { work() } catch (e: Exception) { CaptureContract.error(CaptureContract.E_ERROR, "Something went wrong.") }
                main.post { reply(result, r) }
            }
        } catch (e: Exception) {
            reply(result, CaptureContract.error(CaptureContract.E_ERROR, "Something went wrong."))
        }
    }

    private fun notFound() = CaptureContract.error(CaptureContract.E_NOT_FOUND,
        "That capture isn't available any more. It may have been moved or deleted.")

    private fun sid(call: MethodCall): Int? = (call.argument<Any>("sessionId") as? Number)?.toInt()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getState" -> reply(result, CaptureCoordinator.snapshot())
                "capabilities" -> reply(result, capabilities())

                // ── Recording ──
                "startRecording" -> CaptureCoordinator.startRecording(
                    activity, RecordingConfig.from(call.argument<Any>("config")),
                ) { reply(result, it) }
                "pauseRecording" -> reply(result, CaptureCoordinator.pause(sid(call)))
                "resumeRecording" -> reply(result, CaptureCoordinator.resume(sid(call)))
                "stopRecording" -> reply(result, CaptureCoordinator.stop(sid(call), "user"))
                "cancelRecording" -> reply(result, CaptureCoordinator.cancel(sid(call)))
                "retrySave" -> CaptureCoordinator.retrySave { reply(result, it) }
                "discardUnsaved" -> reply(result, CaptureCoordinator.discardUnsaved())

                // ── Screenshots ──
                "captureScreen" -> CaptureCoordinator.captureScreen(
                    activity,
                    call.argument<Boolean>("hideApp") ?: true,
                    (call.argument<Any>("delayMs") as? Number)?.toInt() ?: 0,
                ) { reply(result, it) }
                "saveImage" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val format = call.argument<String>("format")?.takeIf { it in setOf("png", "jpeg", "webp") } ?: "png"
                    val quality = (call.argument<Any>("quality") as? Number)?.toInt() ?: 92
                    val name = call.argument<String>("name")
                    if (bytes == null || bytes.isEmpty() || bytes.size > MAX_IMAGE_BYTES) {
                        reply(result, CaptureContract.error(CaptureContract.E_INVALID_ARGUMENT, "That image is empty or too large."))
                    } else if (CaptureCoordinator.needsStoragePermission(ctx)) {
                        reply(result, CaptureContract.error(CaptureContract.E_PERMISSION,
                            "Allow storage access so NOVA X can save the screenshot.", "permission" to "storage"))
                    } else {
                        background(result) { CaptureMediaRepository.saveImage(ctx, bytes, name, format, quality) }
                    }
                }

                // ── Library ──
                "listMedia" -> background(result) { CaptureContract.ok("items" to CaptureMediaRepository.list(ctx)) }
                "readBytes" -> background(result) {
                    val owned = CaptureMediaRepository.parseOwned(ctx, call.argument<String>("uri")) ?: return@background notFound()
                    if (owned.second["kind"] != CaptureMediaRepository.KIND_IMAGE) {
                        return@background CaptureContract.error(CaptureContract.E_INVALID_ARGUMENT, "Only screenshots can be opened in the editor.")
                    }
                    val bytes = CaptureMediaRepository.readBytes(ctx, owned.first) ?: return@background notFound()
                    CaptureContract.ok("bytes" to bytes)
                }
                "thumbnail" -> background(result) {
                    val owned = CaptureMediaRepository.parseOwned(ctx, call.argument<String>("uri")) ?: return@background notFound()
                    val size = (call.argument<Any>("size") as? Number)?.toInt() ?: 320
                    val bytes = CaptureMediaRepository.thumbnail(ctx, owned.first, owned.second["kind"] as String, size)
                        ?: return@background CaptureContract.error(CaptureContract.E_ERROR, "No preview available.")
                    CaptureContract.ok("bytes" to bytes)
                }
                "describe" -> background(result) {
                    val owned = CaptureMediaRepository.parseOwned(ctx, call.argument<String>("uri")) ?: return@background notFound()
                    CaptureContract.ok("item" to owned.second)
                }
                "rename" -> background(result) {
                    val owned = CaptureMediaRepository.parseOwned(ctx, call.argument<String>("uri")) ?: return@background notFound()
                    CaptureMediaRepository.rename(ctx, owned.first, owned.second, call.argument<String>("name"))
                }
                "delete" -> deleteItem(call.argument<String>("uri"), result)
                "share" -> withOwned(call.argument<String>("uri"), result) { uri, item -> share(uri, item) }
                "openExternal" -> withOwned(call.argument<String>("uri"), result) { uri, item -> openExternal(uri, item) }
                "copyImage" -> withOwned(call.argument<String>("uri"), result) { uri, item -> copyImage(uri, item) }
                "exportTo" -> withOwned(call.argument<String>("uri"), result) { uri, item -> export(uri, item, result) }
                "storageInfo" -> background(result) {
                    CaptureContract.ok(
                        "freeBytes" to CaptureMediaRepository.freeBytes(ctx),
                        "totalBytes" to CaptureMediaRepository.totalBytes(ctx),
                    )
                }

                // ── Permissions ──
                "requestPermissions" -> requestPermissions(call.argument<List<String>>("kinds") ?: emptyList(), result)
                "openOverlaySettings" -> reply(result, openSettings(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.ACTION_MANAGE_OVERLAY_PERMISSION else null,
                ))
                "openAppSettings" -> reply(result, openSettings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS))
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            reply(result, CaptureContract.error(CaptureContract.E_ERROR, "Something went wrong."))
        }
    }

    private fun capabilities(): Map<String, Any?> = mapOf(
        "sdk" to Build.VERSION.SDK_INT,
        "deviceAudio" to CaptureAudioSource.deviceAudioSupported(),
        "micGranted" to CaptureCoordinator.granted(ctx, Manifest.permission.RECORD_AUDIO),
        "notificationsGranted" to notificationsGranted(),
        "overlayPermission" to FloatingControlsOverlay.permitted(ctx),
        "needsStoragePermission" to CaptureCoordinator.needsStoragePermission(ctx),
        "lostRecordings" to CaptureCoordinator.takeLostCount(),
    )

    private fun notificationsGranted(): Boolean = try {
        if (Build.VERSION.SDK_INT >= 33 && !CaptureCoordinator.granted(ctx, "android.permission.POST_NOTIFICATIONS")) false
        else (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
    } catch (e: Exception) {
        true
    }

    // ── Media actions (must run on the main thread with the activity) ─────────

    private fun withOwned(raw: String?, result: MethodChannel.Result, action: (Uri, Map<String, Any?>) -> Map<String, Any?>?) {
        try {
            io.execute {
                val owned = CaptureMediaRepository.parseOwned(ctx, raw)
                main.post {
                    if (owned == null) { reply(result, notFound()); return@post }
                    val r = try { action(owned.first, owned.second) } catch (e: Exception) {
                        CaptureContract.error(CaptureContract.E_ERROR, "Something went wrong.")
                    }
                    if (r != null) reply(result, r) // null = answered later (export)
                }
            }
        } catch (e: Exception) {
            reply(result, CaptureContract.error(CaptureContract.E_ERROR, "Something went wrong."))
        }
    }

    private fun mimeOf(item: Map<String, Any?>) = item["mime"] as? String
        ?: if (item["kind"] == CaptureMediaRepository.KIND_IMAGE) "image/png" else "video/mp4"

    private fun share(uri: Uri, item: Map<String, Any?>): Map<String, Any?> {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mimeOf(item)
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri(item["name"] as? String ?: "", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return try {
            activity.startActivity(Intent.createChooser(send, "Share").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
            CaptureContract.ok()
        } catch (e: ActivityNotFoundException) {
            CaptureContract.error(CaptureContract.E_NOT_FOUND, "No app on your phone can share this.")
        }
    }

    private fun openExternal(uri: Uri, item: Map<String, Any?>): Map<String, Any?> = try {
        activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, mimeOf(item))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
        CaptureContract.ok()
    } catch (e: ActivityNotFoundException) {
        CaptureContract.error(CaptureContract.E_NOT_FOUND, "No app on your phone can open this file.")
    }

    private fun copyImage(uri: Uri, item: Map<String, Any?>): Map<String, Any?> {
        if (item["kind"] != CaptureMediaRepository.KIND_IMAGE) {
            return CaptureContract.error(CaptureContract.E_INVALID_ARGUMENT, "Only screenshots can be copied.")
        }
        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newUri(ctx.contentResolver, "NOVA X screenshot", uri))
        return CaptureContract.ok()
    }

    private fun export(uri: Uri, item: Map<String, Any?>, result: MethodChannel.Result): Map<String, Any?>? {
        if (pendingExport != null) return CaptureContract.error(CaptureContract.E_BUSY, "An export is already in progress.")
        val i = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeOf(item)
            putExtra(Intent.EXTRA_TITLE, item["name"] as? String ?: "NOVA capture")
        }
        return try {
            pendingExport = Pair(uri, result)
            @Suppress("DEPRECATION")
            activity.startActivityForResult(i, REQ_EXPORT)
            null
        } catch (e: Exception) {
            pendingExport = null
            CaptureContract.error(CaptureContract.E_NOT_FOUND, "Your phone has no app for choosing where to save.")
        }
    }

    private fun deleteItem(raw: String?, result: MethodChannel.Result) {
        try {
            io.execute {
                val owned = CaptureMediaRepository.parseOwned(ctx, raw)
                val r = if (owned == null) notFound() else CaptureMediaRepository.delete(ctx, owned.first)
                main.post {
                    if (owned != null && r["errorCode"] == CaptureContract.E_NEEDS_APPROVAL) {
                        askDeleteApproval(owned.first, result)
                    } else {
                        reply(result, r)
                    }
                }
            }
        } catch (e: Exception) {
            reply(result, CaptureContract.error(CaptureContract.E_ERROR, "It couldn't be deleted."))
        }
    }

    /** Android's own "Allow NOVA X to delete this?" dialog (files from before a reinstall). */
    private fun askDeleteApproval(uri: Uri, result: MethodChannel.Result) {
        val sender: IntentSender? = try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                    MediaStore.createDeleteRequest(ctx.contentResolver, listOf(uri)).intentSender
                Build.VERSION.SDK_INT == Build.VERSION_CODES.Q -> try {
                    ctx.contentResolver.delete(uri, null, null)
                    null
                } catch (e: RecoverableSecurityException) {
                    e.userAction.actionIntent.intentSender
                }
                else -> null
            }
        } catch (e: Exception) {
            null
        }
        if (sender == null) {
            reply(result, if (CaptureMediaRepository.describe(ctx, uri) == null) CaptureContract.ok()
            else CaptureContract.error(CaptureContract.E_PERMISSION, "Android doesn't let NOVA X delete this file. Delete it in your Gallery."))
            return
        }
        try {
            pendingDelete = Pair(uri, result)
            @Suppress("DEPRECATION")
            activity.startIntentSenderForResult(sender, REQ_DELETE, null, 0, 0, 0)
        } catch (e: Exception) {
            pendingDelete = null
            reply(result, CaptureContract.error(CaptureContract.E_ERROR, "It couldn't be deleted."))
        }
    }

    // ── Permissions ───────────────────────────────────────────────────────────

    private fun permissionFor(kind: String): String? = when (kind) {
        "mic" -> Manifest.permission.RECORD_AUDIO
        "notifications" -> if (Build.VERSION.SDK_INT >= 33) "android.permission.POST_NOTIFICATIONS" else null
        "storage" -> if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) Manifest.permission.WRITE_EXTERNAL_STORAGE else null
        else -> null
    }

    private fun permissionStatus(): Map<String, Any?> = CaptureContract.ok(
        "mic" to CaptureCoordinator.granted(ctx, Manifest.permission.RECORD_AUDIO),
        "notifications" to notificationsGranted(),
        "storage" to !CaptureCoordinator.needsStoragePermission(ctx),
        "micCanAsk" to activity.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO),
    )

    private fun requestPermissions(kinds: List<String>, result: MethodChannel.Result) {
        val wanted = kinds.mapNotNull { permissionFor(it) }
            .filter { !CaptureCoordinator.granted(ctx, it) }
            .distinct()
        if (wanted.isEmpty()) return reply(result, permissionStatus())
        if (pendingPermissions != null) {
            return reply(result, CaptureContract.error(CaptureContract.E_BUSY, "A permission request is already open."))
        }
        pendingPermissions = result
        activity.requestPermissions(wanted.toTypedArray(), REQ_PERMISSIONS)
    }

    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode != REQ_PERMISSIONS) return
        val r = pendingPermissions ?: return
        pendingPermissions = null
        reply(r, permissionStatus())
    }

    private fun openSettings(action: String?): Map<String, Any?> {
        if (action == null) return CaptureContract.ok()
        return try {
            activity.startActivity(Intent(action, Uri.parse("package:${ctx.packageName}")))
            CaptureContract.ok()
        } catch (e: Exception) {
            CaptureContract.error(CaptureContract.E_NOT_FOUND, "Settings couldn't be opened.")
        }
    }

    // ── Activity results ──────────────────────────────────────────────────────

    /** True when the result was for NOVA Capture. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        when (requestCode) {
            REQ_EXPORT -> {
                val p = pendingExport ?: return true
                pendingExport = null
                val dst = data?.data
                if (resultCode != Activity.RESULT_OK || dst == null) {
                    reply(p.second, CaptureContract.error(CaptureContract.E_CANCELLED, "Export cancelled."))
                    return true
                }
                background(p.second) {
                    if (CaptureMediaRepository.copyTo(ctx, p.first, dst)) CaptureContract.ok()
                    else CaptureContract.error(CaptureContract.E_SAVE, "It couldn't be saved there.")
                }
                return true
            }
            REQ_DELETE -> {
                val p = pendingDelete ?: return true
                pendingDelete = null
                if (resultCode != Activity.RESULT_OK) {
                    reply(p.second, CaptureContract.error(CaptureContract.E_CANCELLED, "Not deleted."))
                    return true
                }
                background(p.second) {
                    // Android 10 needs a second delete after the user allowed it; 11+ already deleted it.
                    if (CaptureMediaRepository.describe(ctx, p.first) != null) {
                        try { ctx.contentResolver.delete(p.first, null, null) } catch (e: Exception) { }
                    }
                    if (CaptureMediaRepository.describe(ctx, p.first) == null) CaptureContract.ok()
                    else CaptureContract.error(CaptureContract.E_ERROR, "It couldn't be deleted.")
                }
                return true
            }
        }
        return false
    }
}
