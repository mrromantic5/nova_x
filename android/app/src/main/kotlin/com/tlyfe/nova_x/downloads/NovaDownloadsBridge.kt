package com.tlyfe.nova_x.downloads

import android.Manifest
import android.app.Activity
import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * NOVA X downloads (3.13.1) — the native half of the download manager.
 *
 * The Dart side (lib/features/downloads/download_manager.dart) downloads the
 * file into the app's private folder (with progress, pause, resume and
 * cancel). When it is complete, this bridge copies it to where the user
 * wants it:
 *   • Download/NOVA X — MediaStore on Android 10+ (no permission needed),
 *     the public Download folder on Android 7–9 (WRITE_EXTERNAL_STORAGE,
 *     which the manifest limits to Android 9 and older);
 *   • a folder the user picked — Storage Access Framework tree, permission
 *     kept with takePersistableUriPermission.
 * It also opens / shares / deletes saved files and shows progress
 * notifications (tap opens NOVA X's Downloads screen).
 */
class NovaDownloadsBridge(private val activity: Activity, messenger: BinaryMessenger) {

    companion object {
        const val CHANNEL = "com.tlyfe.nova_x/downloads"
        private const val REQ_TREE = 7311
        private const val REQ_WRITE = 7312
        private const val REQ_NOTIFY = 7313
        private const val NOTIF_CHANNEL = "nova_downloads"
        private const val SUBFOLDER = "NOVA X"
        private const val EXTRA_FEATURE = "com.tlyfe.nova_x.extra.NOVA_FEATURE"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingTree: MethodChannel.Result? = null
    private var pendingWrite: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result -> onCall(call, result) }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> pickFolder(result)
            "folderName" -> result.success(folderName(call.argument<String>("tree") ?: ""))
            "hasFolderAccess" -> result.success(hasTreeAccess(call.argument<String>("tree") ?: ""))
            "needsWritePermission" -> requestWriteIfNeeded(result)
            "saveToDownloads" -> background(result) {
                saveToDownloads(
                    File(call.argument<String>("path")!!),
                    call.argument<String>("name")!!,
                    call.argument<String>("mime") ?: "",
                )
            }
            "saveToFolder" -> background(result) {
                saveToFolder(
                    File(call.argument<String>("path")!!),
                    call.argument<String>("name")!!,
                    call.argument<String>("mime") ?: "",
                    Uri.parse(call.argument<String>("tree")!!),
                )
            }
            "open" -> result.success(open(call.argument<String>("uri") ?: "", call.argument<String>("mime") ?: ""))
            "share" -> result.success(share(call.argument<String>("uri") ?: "", call.argument<String>("mime") ?: ""))
            "openDownloadsApp" -> result.success(openDownloadsApp())
            "delete" -> background(result) { mapOf("ok" to delete(call.argument<String>("uri") ?: "")) }
            "exists" -> background(result) { mapOf("ok" to exists(call.argument<String>("uri") ?: "")) }
            "notify" -> {
                notifyProgress(
                    call.argument<Int>("id") ?: 0,
                    call.argument<String>("title") ?: "Download",
                    call.argument<String>("text") ?: "",
                    call.argument<Int>("progress") ?: 0,
                    call.argument<Boolean>("indeterminate") ?: false,
                    call.argument<Boolean>("ongoing") ?: false,
                )
                result.success(true)
            }
            "cancelNotify" -> {
                try { nm().cancel(call.argument<Int>("id") ?: 0) } catch (_: Exception) { }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /** Runs [work] off the main thread and answers with its map (or an error). */
    private fun background(result: MethodChannel.Result, work: () -> Map<String, Any?>) {
        io.execute {
            try {
                val r = work()
                main.post { result.success(r) }
            } catch (e: Exception) {
                main.post { result.error("download_save", e.message ?: e.toString(), null) }
            }
        }
    }

    // ── Folder choice (Storage Access Framework) ─────────────────────────────

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingTree != null) { result.error("busy", "A folder picker is already open", null); return }
        pendingTree = result
        try {
            val i = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
            @Suppress("DEPRECATION")
            activity.startActivityForResult(i, REQ_TREE)
        } catch (e: Exception) {
            pendingTree = null
            result.error("no_picker", "This phone has no folder picker", null)
        }
    }

    /** Returns true when the result belonged to this bridge. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_TREE) return false
        val result = pendingTree ?: return true
        pendingTree = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return true }
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (_: Exception) { }
        result.success(mapOf("tree" to uri.toString(), "name" to folderName(uri.toString())))
        return true
    }

    private fun hasTreeAccess(tree: String): Boolean {
        if (tree.isEmpty()) return false
        return activity.contentResolver.persistedUriPermissions.any { it.uri.toString() == tree && it.isWritePermission }
    }

    private fun folderName(tree: String): String {
        if (tree.isEmpty()) return ""
        return try {
            val uri = Uri.parse(tree)
            val doc = DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
            activity.contentResolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: DocumentsContract.getTreeDocumentId(uri).substringAfterLast(':')
        } catch (_: Exception) { "Chosen folder" }
    }

    // ── Write permission (Android 7–9 only) ──────────────────────────────────

    private fun requestWriteIfNeeded(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) { result.success(false); return }
        if (activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) {
            result.success(false); return
        }
        pendingWrite = result
        activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), REQ_WRITE)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQ_WRITE) return
        val r = pendingWrite ?: return
        pendingWrite = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        // Answer: still needs permission?
        r.success(!granted)
    }

    // ── Saving ───────────────────────────────────────────────────────────────

    private fun mimeFor(name: String, mime: String): String {
        if (mime.isNotBlank() && mime != "application/octet-stream") return mime
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }

    private fun saveToDownloads(src: File, name: String, mime: String): Map<String, Any?> {
        val type = mimeFor(name, mime)
        val resolver = activity.contentResolver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, type)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + SUBFOLDER)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Couldn't create the file in Downloads")
            try {
                resolver.openOutputStream(uri)?.use { out -> FileInputStream(src).use { it.copyTo(out, 256 * 1024) } }
                    ?: throw IllegalStateException("Couldn't write the file")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                try { resolver.delete(uri, null, null) } catch (_: Exception) { }
                throw e
            }
            // The name actually used (Android adds " (1)" when it already exists).
            val shown = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: name
            return mapOf("uri" to uri.toString(), "name" to shown, "location" to "Download/$SUBFOLDER")
        }
        // Android 7–9: the public Download folder.
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), SUBFOLDER)
        if (!dir.exists() && !dir.mkdirs()) throw IllegalStateException("Couldn't create Download/$SUBFOLDER")
        val target = uniqueFile(dir, name)
        src.copyTo(target, overwrite = false)
        val scanned = AtomicReference<Uri?>(null)
        val latch = CountDownLatch(1)
        MediaScannerConnection.scanFile(activity, arrayOf(target.absolutePath), arrayOf(type)) { _, u ->
            scanned.set(u); latch.countDown()
        }
        latch.await(4, TimeUnit.SECONDS)
        return mapOf(
            "uri" to (scanned.get()?.toString() ?: Uri.fromFile(target).toString()),
            "name" to target.name,
            "location" to "Download/$SUBFOLDER",
        )
    }

    private fun uniqueFile(dir: File, name: String): File {
        var f = File(dir, name)
        if (!f.exists()) return f
        val base = name.substringBeforeLast('.', name)
        val ext = if (name.contains('.')) "." + name.substringAfterLast('.') else ""
        var n = 1
        while (f.exists() && n < 1000) { f = File(dir, "$base ($n)$ext"); n++ }
        return f
    }

    private fun saveToFolder(src: File, name: String, mime: String, tree: Uri): Map<String, Any?> {
        val resolver = activity.contentResolver
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val doc = DocumentsContract.createDocument(resolver, parent, mimeFor(name, mime), name)
            ?: throw IllegalStateException("Couldn't create the file in the chosen folder (is it still available?)")
        try {
            resolver.openOutputStream(doc)?.use { out -> FileInputStream(src).use { it.copyTo(out, 256 * 1024) } }
                ?: throw IllegalStateException("Couldn't write the file")
        } catch (e: Exception) {
            try { DocumentsContract.deleteDocument(resolver, doc) } catch (_: Exception) { }
            throw e
        }
        val shown = resolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: name
        return mapOf("uri" to doc.toString(), "name" to shown, "location" to folderName(tree.toString()))
    }

    // ── Using saved files ────────────────────────────────────────────────────

    private fun open(uri: String, mime: String): Boolean {
        if (uri.isEmpty()) return false
        return try {
            val u = Uri.parse(uri)
            val type = activity.contentResolver.getType(u) ?: mime.ifBlank { "*/*" }
            val i = Intent(Intent.ACTION_VIEW).setDataAndType(u, type)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(Intent.createChooser(i, "Open with").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) { false }
    }

    private fun share(uri: String, mime: String): Boolean {
        if (uri.isEmpty()) return false
        return try {
            val u = Uri.parse(uri)
            val type = activity.contentResolver.getType(u) ?: mime.ifBlank { "*/*" }
            val i = Intent(Intent.ACTION_SEND).setType(type).putExtra(Intent.EXTRA_STREAM, u)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            activity.startActivity(Intent.createChooser(i, "Share"))
            true
        } catch (_: Exception) { false }
    }

    private fun openDownloadsApp(): Boolean = try {
        activity.startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: Exception) { false }

    private fun delete(uri: String): Boolean {
        if (uri.isEmpty()) return false
        return try {
            val u = Uri.parse(uri)
            when {
                u.scheme == "file" -> File(u.path ?: "").delete()
                DocumentsContract.isDocumentUri(activity, u) && u.authority != "media" ->
                    DocumentsContract.deleteDocument(activity.contentResolver, u)
                else -> activity.contentResolver.delete(u, null, null) > 0
            }
        } catch (_: Exception) { false }
    }

    private fun exists(uri: String): Boolean {
        if (uri.isEmpty()) return false
        return try {
            val u = Uri.parse(uri)
            if (u.scheme == "file") return File(u.path ?: "").exists()
            activity.contentResolver.openFileDescriptor(u, "r")?.use { true } ?: false
        } catch (_: Exception) { false }
    }

    // ── Notifications ────────────────────────────────────────────────────────

    private fun nm() = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private var askedNotifications = false

    /** Android 13+: ask once (per launch) to show download notifications, like Chrome. */
    private fun askNotificationsOnce() {
        if (askedNotifications || Build.VERSION.SDK_INT < 33) return
        askedNotifications = true
        if (activity.checkSelfPermission("android.permission.POST_NOTIFICATIONS") == PackageManager.PERMISSION_GRANTED) return
        try { activity.requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), REQ_NOTIFY) } catch (_: Exception) { }
    }

    private fun notifyProgress(id: Int, title: String, text: String, progress: Int, indeterminate: Boolean, ongoing: Boolean) {
        if (ongoing) askNotificationsOnce()
        try {
            val nm = nm()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm.getNotificationChannel(NOTIF_CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(NOTIF_CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW).apply {
                        description = "Progress of files you download in NOVA X"
                        setShowBadge(false)
                    }
                )
            }
            val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(activity, NOTIF_CHANNEL)
            else @Suppress("DEPRECATION") Notification.Builder(activity)
            val open = Intent(activity, activity.javaClass)
                .putExtra(EXTRA_FEATURE, "downloads")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            b.setContentIntent(
                PendingIntent.getActivity(activity, 7320, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            )
            b.setSmallIcon(if (ongoing) android.R.drawable.stat_sys_download else android.R.drawable.stat_sys_download_done)
                .setContentTitle(title)
                .setContentText(text)
                .setOngoing(ongoing)
                .setOnlyAlertOnce(true)
                .setAutoCancel(!ongoing)
                .setShowWhen(!ongoing)
                .setCategory(Notification.CATEGORY_PROGRESS)
            if (ongoing) b.setProgress(100, progress.coerceIn(0, 100), indeterminate)
            nm.notify(id, b.build())
        } catch (_: Exception) { }
    }
}
