package com.tlyfe.nova_x.nova

import android.app.Activity
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * "Read my screen" for the NOVA assistant panel: ONE screenshot of the app
 * the user is looking at, only after the user agrees in Android's own
 * screen-capture dialog (MediaProjection). Nothing runs in the background:
 *
 *   1. request()  → Android's consent dialog ("Start recording or casting
 *                   with NOVA X?"). The user can cancel.
 *   2. consent    → NovaCaptureService starts as a visible foreground service
 *                   of type mediaProjection (required by Android 10+/14+) and
 *                   NOVA receives a single-use MediaProjection.
 *   3. grab()     → the panel hides itself, one frame is copied, then the
 *                   projection is stopped and the service ends at once.
 *
 * The screenshot is returned to Dart as a JPEG (longest side ≤ 1280 px) and
 * is only kept in memory; Dart shows it to the user, who decides whether to
 * send it to NOVA AI. A consent that is not used within 30 seconds is
 * dropped. Over the lock screen this is refused ("locked"). Apps that block
 * screenshots (FLAG_SECURE, e.g. banking) come back black → "protected".
 */
object NovaScreenCapture {

    const val REQUEST_CODE = 9320
    private const val MAX_SIDE = 1280
    private const val CONSENT_TTL_MS = 30_000L

    private val main = Handler(Looper.getMainLooper())

    private var appContext: Context? = null
    private var pendingConsent: ((Map<String, Any?>) -> Unit)? = null
    private var consentCode = 0
    private var consentData: Intent? = null

    private var projection: MediaProjection? = null
    private var projectionCallback: MediaProjection.Callback? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var grabbing = false
    private val expire = Runnable { release() }

    fun isSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP

    fun isLocked(context: Context): Boolean =
        (context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)?.isKeyguardLocked == true

    /** Step 1: Android's consent dialog. [done] gets {status: granted|denied|locked|busy|unsupported|error}. */
    fun request(activity: Activity, done: (Map<String, Any?>) -> Unit) {
        if (!isSupported()) return done(mapOf("status" to "unsupported"))
        if (isLocked(activity)) return done(mapOf("status" to "locked"))
        if (pendingConsent != null || grabbing) return done(mapOf("status" to "busy"))
        release()
        appContext = activity.applicationContext
        val mpm = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
            ?: return done(mapOf("status" to "unsupported"))
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Whole screen: NOVA reads what the user is looking at right now.
            mpm.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            mpm.createScreenCaptureIntent()
        }
        pendingConsent = done
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (e: Exception) {
            pendingConsent = null
            done(mapOf("status" to "error"))
        }
    }

    /** Called by the host activity; true when the result was ours. */
    fun onActivityResult(context: Context, requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val done = pendingConsent ?: return true
        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingConsent = null
            done(mapOf("status" to "denied"))
            return true
        }
        consentCode = resultCode
        consentData = data
        try {
            val service = Intent(context, NovaCaptureService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(service)
            else context.startService(service)
        } catch (e: Exception) {
            finishConsent(mapOf("status" to "error"))
            release()
        }
        return true
    }

    /** Step 2 (from NovaCaptureService, already in the foreground). */
    internal fun onServiceStarted(service: Service) {
        val data = consentData
        consentData = null
        if (data == null || pendingConsent == null) {
            release()
            return
        }
        try {
            val mpm = service.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val p = mpm.getMediaProjection(consentCode, data) ?: throw IllegalStateException("no projection")
            val cb = object : MediaProjection.Callback() {
                override fun onStop() {
                    main.post { release() }
                }
            }
            p.registerCallback(cb, main)
            projection = p
            projectionCallback = cb
            main.postDelayed(expire, CONSENT_TTL_MS)
            finishConsent(mapOf("status" to "granted"))
        } catch (e: Exception) {
            finishConsent(mapOf("status" to "error"))
            release()
        }
    }

    private fun finishConsent(value: Map<String, Any?>) {
        val done = pendingConsent ?: return
        pendingConsent = null
        main.post { done(value) }
    }

    /** Step 3: one frame of the screen. [done] gets {status: ok, bytes} or {status: expired|protected|error}. */
    fun grab(done: (Map<String, Any?>) -> Unit) {
        val p = projection
        val ctx = appContext
        if (p == null || ctx == null || grabbing) return done(mapOf("status" to "expired"))
        main.removeCallbacks(expire)
        grabbing = true
        var finished = false
        fun finish(value: Map<String, Any?>) {
            main.post {
                if (finished) return@post
                finished = true
                release()
                done(value)
            }
        }

        try {
            val metrics = screenMetrics(ctx)
            val scale = minOf(1f, MAX_SIDE.toFloat() / max(metrics.widthPixels, metrics.heightPixels))
            val w = even((metrics.widthPixels * scale).roundToInt())
            val h = even((metrics.heightPixels * scale).roundToInt())
            val t = HandlerThread("nova-screen").also { it.start() }
            thread = t
            val handler = Handler(t.looper)
            val r = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
            reader = r
            display = p.createVirtualDisplay(
                "NOVA screen", w, h, metrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, r.surface, null, handler,
            )
            var tries = 0
            lateinit var attempt: Runnable
            attempt = Runnable {
                try {
                    val image = r.acquireLatestImage()
                    if (image == null) {
                        if (++tries < 12) handler.postDelayed(attempt, 120) else finish(mapOf("status" to "error"))
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
                        finish(mapOf("status" to "protected"))
                        return@Runnable
                    }
                    val out = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 82, out)
                    bitmap.recycle()
                    finish(mapOf("status" to "ok", "bytes" to out.toByteArray()))
                } catch (e: Exception) {
                    finish(mapOf("status" to "error"))
                }
            }
            // Give the mirror a moment to show the real screen.
            handler.postDelayed(attempt, 350)
            main.postDelayed({ finish(mapOf("status" to "error")) }, 5_000)
        } catch (e: Exception) {
            finish(mapOf("status" to "error"))
        }
    }

    /** The user cancelled after consenting (or the panel closed). */
    fun cancel() {
        if (!grabbing) release()
    }

    private fun release() {
        main.removeCallbacks(expire)
        try { display?.release() } catch (e: Exception) { }
        display = null
        try { reader?.close() } catch (e: Exception) { }
        reader = null
        val p = projection
        projection = null
        projectionCallback?.let { cb -> try { p?.unregisterCallback(cb) } catch (e: Exception) { } }
        projectionCallback = null
        try { p?.stop() } catch (e: Exception) { }
        thread?.quitSafely()
        thread = null
        grabbing = false
        consentData = null
        appContext?.let { NovaCaptureService.stop(it) }
    }

    private fun even(v: Int): Int = max(2, v - (v % 2))

    @Suppress("DEPRECATION")
    private fun screenMetrics(ctx: Context): DisplayMetrics {
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val out = DisplayMetrics()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.maximumWindowMetrics.bounds
            out.widthPixels = bounds.width()
            out.heightPixels = bounds.height()
            out.densityDpi = ctx.resources.displayMetrics.densityDpi
        } else {
            wm.defaultDisplay.getRealMetrics(out)
        }
        return out
    }

    /** All-black frame: the app in front blocks screenshots. */
    private fun isBlank(b: Bitmap): Boolean {
        val stepX = max(1, b.width / 12)
        val stepY = max(1, b.height / 20)
        var y = stepY / 2
        while (y < b.height) {
            var x = stepX / 2
            while (x < b.width) {
                val c = b.getPixel(x, y)
                val r = (c shr 16) and 0xFF
                val g = (c shr 8) and 0xFF
                val bl = c and 0xFF
                if (r > 10 || g > 10 || bl > 10) return false
                x += stepX
            }
            y += stepY
        }
        return true
    }
}

/**
 * Visible foreground service that exists only while NOVA takes the one
 * screenshot the user agreed to (Android requires it for screen capture).
 */
class NovaCaptureService : Service() {

    companion object {
        private const val CHANNEL_ID = "nova_screen_capture"
        private const val NOTIFICATION_ID = 9321

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, NovaCaptureService::class.java))
            } catch (e: Exception) { }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        NovaScreenCapture.onServiceStarted(this)
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
        else stopForeground(true)
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "NOVA screen reading", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while NOVA takes the screenshot you asked for."
                    setShowBadge(false)
                },
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle("NOVA is reading your screen")
            .setContentText("Taking one screenshot you asked for.")
            .setOngoing(true)
            .build()
    }
}
