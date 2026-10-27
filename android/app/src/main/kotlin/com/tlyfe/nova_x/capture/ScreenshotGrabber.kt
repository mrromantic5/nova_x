package com.tlyfe.nova_x.capture

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * One full-resolution frame of the whole screen from a MediaProjection the
 * user just agreed to. Longest side is capped at 4096 px to bound memory.
 * An all-black frame means the app in front blocks capture (FLAG_SECURE,
 * DRM video) — reported as PROTECTED_CONTENT, never saved as a blank image.
 */
object ScreenshotGrabber {

    private const val MAX_SIDE = 4096

    @Suppress("DEPRECATION")
    fun realMetrics(ctx: Context): DisplayMetrics {
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val out = DisplayMetrics()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = wm.maximumWindowMetrics.bounds
            out.widthPixels = b.width()
            out.heightPixels = b.height()
            out.densityDpi = ctx.resources.displayMetrics.densityDpi
        } else {
            wm.defaultDisplay.getRealMetrics(out)
        }
        return out
    }

    /** [done] runs on the main thread with a bitmap, or null and an error code. */
    fun grab(ctx: Context, projection: MediaProjection, done: (Bitmap?, String?) -> Unit) {
        val main = Handler(Looper.getMainLooper())
        val metrics = realMetrics(ctx)
        val scale = min(1f, MAX_SIDE.toFloat() / max(metrics.widthPixels, metrics.heightPixels))
        val w = max(2, (metrics.widthPixels * scale).roundToInt())
        val h = max(2, (metrics.heightPixels * scale).roundToInt())
        val thread = HandlerThread("nova-shot").also { it.start() }
        val handler = Handler(thread.looper)
        var reader: ImageReader? = null
        var display: VirtualDisplay? = null
        var finished = false

        fun finish(bitmap: Bitmap?, code: String?) {
            main.post {
                if (finished) { bitmap?.recycle(); return@post }
                finished = true
                try { display?.release() } catch (e: Exception) { }
                try { reader?.close() } catch (e: Exception) { }
                thread.quitSafely()
                done(bitmap, code)
            }
        }

        try {
            val r = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
            reader = r
            display = projection.createVirtualDisplay(
                "NOVA X screenshot", w, h, metrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, r.surface, null, handler,
            )
            var tries = 0
            lateinit var attempt: Runnable
            attempt = Runnable {
                try {
                    val image = r.acquireLatestImage()
                    if (image == null) {
                        if (++tries < 15) handler.postDelayed(attempt, 100) else finish(null, CaptureContract.E_ERROR)
                        return@Runnable
                    }
                    val bitmap = image.use {
                        val plane = it.planes[0]
                        val pixelStride = plane.pixelStride
                        val rowPadding = plane.rowStride - pixelStride * w
                        val full = Bitmap.createBitmap(w + rowPadding / pixelStride, h, Bitmap.Config.ARGB_8888)
                        full.copyPixelsFromBuffer(plane.buffer)
                        if (full.width == w) full else Bitmap.createBitmap(full, 0, 0, w, h).also { full.recycle() }
                    }
                    if (isBlank(bitmap)) {
                        bitmap.recycle()
                        finish(null, CaptureContract.E_PROTECTED)
                    } else {
                        finish(bitmap, null)
                    }
                } catch (e: Exception) {
                    finish(null, CaptureContract.E_ERROR)
                }
            }
            handler.postDelayed(attempt, 250)
            main.postDelayed({ finish(null, CaptureContract.E_TIMEOUT) }, 6_000)
        } catch (e: Exception) {
            finish(null, CaptureContract.E_ERROR)
        }
    }

    private fun isBlank(b: Bitmap): Boolean {
        val stepX = max(1, b.width / 16)
        val stepY = max(1, b.height / 24)
        var y = stepY / 2
        while (y < b.height) {
            var x = stepX / 2
            while (x < b.width) {
                val c = b.getPixel(x, y)
                if (((c shr 16) and 0xFF) > 8 || ((c shr 8) and 0xFF) > 8 || (c and 0xFF) > 8) return false
                x += stepX
            }
            y += stepY
        }
        return true
    }
}
