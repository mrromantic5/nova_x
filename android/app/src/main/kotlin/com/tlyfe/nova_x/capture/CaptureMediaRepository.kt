package com.tlyfe.nova_x.capture

import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * NOVA Capture media in the phone's shared storage, through MediaStore only:
 *
 *   Pictures/NOVA X/Screenshots   (PNG / JPEG / WebP)
 *   Movies/NOVA X/Recordings      (MP4)
 *
 * Android 10+: no storage permission is needed for files NOVA X saves itself.
 * Android 7–9: WRITE_EXTERNAL_STORAGE (declared maxSdkVersion 28) is asked
 * before the first save. Every operation that takes a uri first checks that
 * it is a MediaStore item inside one of the two NOVA X folders, so a request
 * can never touch any other media on the phone.
 *
 * All methods do I/O: call them off the main thread.
 */
object CaptureMediaRepository {

    const val KIND_IMAGE = "screenshot"
    const val KIND_VIDEO = "recording"

    private val NAME_OK = Regex("^[A-Za-z0-9 _().,'+&-]{1,80}$")

    fun timestamp(): String = SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", Locale.US).format(Date())

    private fun imagesUri(): Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        else MediaStore.Images.Media.EXTERNAL_CONTENT_URI

    private fun videosUri(): Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        else MediaStore.Video.Media.EXTERNAL_CONTENT_URI

    @Suppress("DEPRECATION")
    private fun legacyDir(kind: String): File {
        val base = Environment.getExternalStoragePublicDirectory(
            if (kind == KIND_IMAGE) Environment.DIRECTORY_PICTURES else Environment.DIRECTORY_MOVIES,
        )
        return File(base, if (kind == KIND_IMAGE) "NOVA X/Screenshots" else "NOVA X/Recordings").also { it.mkdirs() }
    }

    /** Safe display name: user text cleaned, NOVA X extension enforced. */
    fun cleanName(raw: String?, ext: String): String? {
        var t = (raw ?: "").trim().replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "").replace(Regex("\\s+"), " ")
        if (t.lowercase(Locale.US).endsWith(".$ext")) t = t.dropLast(ext.length + 1)
        t = t.trim().trimStart('.')
        if (t.isEmpty() || !NAME_OK.matches(t)) return null
        return "$t.$ext"
    }

    // ── Save ──────────────────────────────────────────────────────────────────

    /** Saves an encoded image. [format] png | jpeg | webp. */
    fun saveImage(ctx: Context, bytes: ByteArray, name: String?, format: String, quality: Int): Map<String, Any?> {
        val ext = when (format) { "jpeg" -> "jpg"; "webp" -> "webp"; else -> "png" }
        val mime = when (format) { "jpeg" -> "image/jpeg"; "webp" -> "image/webp"; else -> "image/png" }
        var data = bytes
        if (format != "png") {
            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                ?: return CaptureContract.error(CaptureContract.E_INVALID_ARGUMENT, "That image couldn't be read.")
            val out = ByteArrayOutputStream()
            @Suppress("DEPRECATION")
            val cf = if (format == "jpeg") Bitmap.CompressFormat.JPEG else Bitmap.CompressFormat.WEBP
            bmp.compress(cf, quality.coerceIn(40, 100), out)
            bmp.recycle()
            data = out.toByteArray()
        }
        val display = uniqueName(ctx, KIND_IMAGE, cleanName(name, ext) ?: "NOVA_Screenshot_${timestamp()}.$ext")
        return insert(ctx, KIND_IMAGE, display, mime) { os -> os.write(data) }
    }

    fun saveBitmap(ctx: Context, bitmap: Bitmap): Map<String, Any?> {
        val display = uniqueName(ctx, KIND_IMAGE, "NOVA_Screenshot_${timestamp()}.png")
        return insert(ctx, KIND_IMAGE, display, "image/png") { os -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, os) }
    }

    /** Moves a finished private recording into Movies/NOVA X/Recordings. */
    fun saveVideo(ctx: Context, file: File): Map<String, Any?> {
        val display = uniqueName(ctx, KIND_VIDEO, "NOVA_Recording_${timestamp()}.mp4")
        return insert(ctx, KIND_VIDEO, display, "video/mp4") { os ->
            FileInputStream(file).use { it.copyTo(os, 256 * 1024) }
        }
    }

    private fun insert(
        ctx: Context, kind: String, display: String, mime: String,
        write: (java.io.OutputStream) -> Unit,
    ): Map<String, Any?> {
        val resolver = ctx.contentResolver
        val collection = if (kind == KIND_IMAGE) imagesUri() else videosUri()
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, display)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, if (kind == KIND_IMAGE) CaptureContract.SCREENSHOT_DIR else CaptureContract.RECORDING_DIR)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            } else {
                @Suppress("DEPRECATION")
                put(MediaStore.MediaColumns.DATA, File(legacyDir(kind), display).absolutePath)
            }
        }
        var uri: Uri? = null
        return try {
            uri = resolver.insert(collection, values) ?: throw IllegalStateException("insert")
            resolver.openOutputStream(uri)?.use { write(it) } ?: throw IllegalStateException("stream")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            }
            val item = describe(ctx, uri, kind)
                ?: mapOf("uri" to uri.toString(), "name" to display, "kind" to kind, "mime" to mime)
            CaptureContract.ok("item" to item)
        } catch (e: SecurityException) {
            uri?.let { try { resolver.delete(it, null, null) } catch (x: Exception) { } }
            CaptureContract.error(CaptureContract.E_PERMISSION, "NOVA X needs permission to save to your phone's storage.")
        } catch (e: Exception) {
            uri?.let { try { resolver.delete(it, null, null) } catch (x: Exception) { } }
            CaptureContract.error(CaptureContract.E_SAVE, "It couldn't be saved. Check that your phone has free space.")
        }
    }

    private fun uniqueName(ctx: Context, kind: String, wanted: String): String {
        val existing = list(ctx).mapNotNull { it["name"] as? String }.toSet()
        if (wanted !in existing) return wanted
        val dot = wanted.lastIndexOf('.')
        val stem = if (dot > 0) wanted.substring(0, dot) else wanted
        val ext = if (dot > 0) wanted.substring(dot) else ""
        var i = 2
        while ("${stem}_$i$ext" in existing && i < 1000) i++
        return "${stem}_$i$ext"
    }

    // ── Query ─────────────────────────────────────────────────────────────────

    fun list(ctx: Context): List<Map<String, Any?>> = query(ctx, KIND_IMAGE, null) + query(ctx, KIND_VIDEO, null)

    private fun query(ctx: Context, kind: String, only: Uri?): List<Map<String, Any?>> {
        val collection = if (kind == KIND_IMAGE) imagesUri() else videosUri()
        val dir = if (kind == KIND_IMAGE) CaptureContract.SCREENSHOT_DIR else CaptureContract.RECORDING_DIR
        val cols = mutableListOf(
            MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_ADDED, MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.WIDTH, MediaStore.MediaColumns.HEIGHT,
        )
        if (kind == KIND_VIDEO) cols.add(MediaStore.Video.VideoColumns.DURATION)
        val sel: String
        val args: Array<String>
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            sel = "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?"
            args = arrayOf("$dir%")
        } else {
            @Suppress("DEPRECATION")
            sel = "${MediaStore.MediaColumns.DATA} LIKE ?"
            args = arrayOf("%/$dir/%")
        }
        val out = ArrayList<Map<String, Any?>>()
        val target = only ?: collection
        try {
            ctx.contentResolver.query(target, cols.toTypedArray(), sel, args, "${MediaStore.MediaColumns.DATE_ADDED} DESC")?.use { c ->
                val iId = c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val iName = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val iSize = c.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                val iDate = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
                val iMime = c.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
                val iW = c.getColumnIndex(MediaStore.MediaColumns.WIDTH)
                val iH = c.getColumnIndex(MediaStore.MediaColumns.HEIGHT)
                val iDur = if (kind == KIND_VIDEO) c.getColumnIndex(MediaStore.Video.VideoColumns.DURATION) else -1
                while (c.moveToNext()) {
                    val id = c.getLong(iId)
                    val uri = ContentUris.withAppendedId(collection, id)
                    out.add(mapOf(
                        "uri" to uri.toString(),
                        "name" to (c.getString(iName) ?: ""),
                        "size" to c.getLong(iSize),
                        "createdMs" to c.getLong(iDate) * 1000,
                        "mime" to (c.getString(iMime) ?: if (kind == KIND_IMAGE) "image/png" else "video/mp4"),
                        "kind" to kind,
                        "width" to (if (iW >= 0) c.getInt(iW) else 0),
                        "height" to (if (iH >= 0) c.getInt(iH) else 0),
                        "durationMs" to (if (iDur >= 0) c.getLong(iDur) else 0L),
                    ))
                }
            }
        } catch (e: Exception) {
            // Storage unavailable / permission withdrawn: an empty list, not a crash.
        }
        return out
    }

    /** The NOVA X item at [uri], or null when it isn't one of ours. */
    fun describe(ctx: Context, uri: Uri, kindHint: String? = null): Map<String, Any?>? {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT || uri.authority != MediaStore.AUTHORITY) return null
        val id = try { ContentUris.parseId(uri) } catch (e: Exception) { return null }
        if (id < 0) return null
        val kinds = if (kindHint != null) listOf(kindHint) else {
            val s = uri.toString()
            when {
                s.contains("/images/") -> listOf(KIND_IMAGE)
                s.contains("/video/") -> listOf(KIND_VIDEO)
                else -> return null
            }
        }
        for (k in kinds) {
            val collection = if (k == KIND_IMAGE) imagesUri() else videosUri()
            val match = query(ctx, k, ContentUris.withAppendedId(collection, id)).firstOrNull()
            if (match != null) return match
        }
        return null
    }

    fun parseOwned(ctx: Context, raw: Any?): Pair<Uri, Map<String, Any?>>? {
        val s = raw as? String ?: return null
        if (s.length > 300) return null
        val uri = try { Uri.parse(s) } catch (e: Exception) { return null }
        val item = describe(ctx, uri) ?: return null
        return Pair(Uri.parse(item["uri"] as String), item)
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    fun readBytes(ctx: Context, uri: Uri, maxBytes: Long = 60L * 1024 * 1024): ByteArray? = try {
        ctx.contentResolver.openInputStream(uri)?.use { input ->
            val out = ByteArrayOutputStream()
            val buf = ByteArray(64 * 1024)
            var total = 0L
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                total += n
                if (total > maxBytes) return null
                out.write(buf, 0, n)
            }
            out.toByteArray()
        }
    } catch (e: Exception) {
        null
    }

    @Suppress("DEPRECATION")
    fun thumbnail(ctx: Context, uri: Uri, kind: String, size: Int): ByteArray? = try {
        val s = size.coerceIn(64, 640)
        val bmp: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ctx.contentResolver.loadThumbnail(uri, Size(s, s), null)
        } else if (kind == KIND_VIDEO) {
            val path = legacyPath(ctx, uri)
            if (path != null) ThumbnailUtils.createVideoThumbnail(path, MediaStore.Video.Thumbnails.MINI_KIND) else frameAt(ctx, uri)
        } else {
            val bytes = readBytes(ctx, uri, 40L * 1024 * 1024)
            bytes?.let {
                val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(it, 0, it.size, o)
                var sample = 1
                while (o.outWidth / (sample * 2) >= s && o.outHeight / (sample * 2) >= s) sample *= 2
                BitmapFactory.decodeByteArray(it, 0, it.size, BitmapFactory.Options().apply { inSampleSize = sample })
            }
        }
        bmp?.let {
            val out = ByteArrayOutputStream()
            it.compress(Bitmap.CompressFormat.JPEG, 80, out)
            it.recycle()
            out.toByteArray()
        }
    } catch (e: Exception) {
        null
    }

    private fun frameAt(ctx: Context, uri: Uri): Bitmap? {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(ctx, uri)
            r.getFrameAtTime(0)
        } catch (e: Exception) {
            null
        } finally {
            try { r.release() } catch (e: Exception) { }
        }
    }

    @Suppress("DEPRECATION")
    private fun legacyPath(ctx: Context, uri: Uri): String? = try {
        ctx.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    } catch (e: Exception) {
        null
    }

    // ── Change ────────────────────────────────────────────────────────────────

    /** Renames; returns the updated item, or an error map. */
    fun rename(ctx: Context, uri: Uri, item: Map<String, Any?>, newName: String?): Map<String, Any?> {
        val kind = item["kind"] as String
        val oldName = item["name"] as String
        val ext = oldName.substringAfterLast('.', if (kind == KIND_IMAGE) "png" else "mp4")
        val clean = cleanName(newName, ext)
            ?: return CaptureContract.error(CaptureContract.E_INVALID_ARGUMENT,
                "Use letters, numbers, spaces, dashes or underscores (up to 80 characters).")
        if (clean == oldName) return CaptureContract.ok("item" to item)
        if (list(ctx).any { it["name"] == clean }) {
            return CaptureContract.error(CaptureContract.E_INVALID_ARGUMENT, "A capture with that name already exists.")
        }
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ctx.contentResolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.DISPLAY_NAME, clean) }, null, null)
            } else {
                val path = legacyPath(ctx, uri) ?: throw IllegalStateException("path")
                val src = File(path)
                val dst = File(src.parentFile, clean)
                if (!src.renameTo(dst)) throw IllegalStateException("rename")
                @Suppress("DEPRECATION")
                ctx.contentResolver.update(uri, ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, clean)
                    put(MediaStore.MediaColumns.DATA, dst.absolutePath)
                }, null, null)
            }
            CaptureContract.ok("item" to (describe(ctx, uri, kind) ?: item + ("name" to clean)))
        } catch (e: SecurityException) {
            CaptureContract.error(CaptureContract.E_PERMISSION,
                "Android doesn't let NOVA X rename this file (it was probably saved before NOVA X was reinstalled). Rename it in your Gallery or Files app.")
        } catch (e: Exception) {
            CaptureContract.error(CaptureContract.E_ERROR, "It couldn't be renamed.")
        }
    }

    /** Deletes; a SecurityException is returned for the caller to ask Android's own confirmation. */
    fun delete(ctx: Context, uri: Uri): Map<String, Any?> = try {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) legacyPath(ctx, uri)?.let { File(it).delete() }
        val n = ctx.contentResolver.delete(uri, null, null)
        if (n > 0 || describe(ctx, uri) == null) CaptureContract.ok()
        else CaptureContract.error(CaptureContract.E_ERROR, "It couldn't be deleted.")
    } catch (e: SecurityException) {
        CaptureContract.error(CaptureContract.E_NEEDS_APPROVAL, "Android needs you to confirm this deletion.")
    } catch (e: Exception) {
        CaptureContract.error(CaptureContract.E_ERROR, "It couldn't be deleted.")
    }

    fun copyTo(ctx: Context, src: Uri, dst: Uri): Boolean = try {
        ctx.contentResolver.openInputStream(src)?.use { input ->
            ctx.contentResolver.openOutputStream(dst, "w")?.use { output -> input.copyTo(output, 256 * 1024); true }
        } ?: false
    } catch (e: Exception) {
        false
    }

    // ── Storage ───────────────────────────────────────────────────────────────

    fun freeBytes(ctx: Context): Long = try {
        val dir = ctx.getExternalFilesDir(null) ?: ctx.filesDir
        StatFs(dir.absolutePath).availableBytes
    } catch (e: Exception) {
        -1L
    }

    fun totalBytes(ctx: Context): Long = try {
        val dir = ctx.getExternalFilesDir(null) ?: ctx.filesDir
        StatFs(dir.absolutePath).totalBytes
    } catch (e: Exception) {
        -1L
    }

    /** Private folder for recordings in progress (never shown to other apps). */
    fun tempDir(ctx: Context): File = File(ctx.filesDir, "capture_tmp").also { it.mkdirs() }

    /** Leftovers from a recording that never finished (app killed): removed at start-up. */
    fun cleanupTemp(ctx: Context, keep: File? = null): Int {
        var removed = 0
        tempDir(ctx).listFiles()?.forEach { f ->
            if (f != keep && f.delete()) removed++
        }
        return removed
    }
}
