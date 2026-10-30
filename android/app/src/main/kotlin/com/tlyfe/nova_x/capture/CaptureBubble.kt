package com.tlyfe.nova_x.capture

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.tlyfe.nova_x.MainActivity
import com.tlyfe.nova_x.R
import kotlin.math.abs
import kotlin.math.hypot

/**
 * NOVA Capture floating button — a small round button that stays on the
 * phone screen (inside NOVA X and over other apps) once the user turns it on.
 *
 *  - Tap: opens the control panel (Record / Stop, Pause / Resume, Screenshot,
 *    open NOVA Capture, close, collapse).
 *  - Drag: move it; it snaps to the nearest side. Drag onto the ✕ that
 *    appears at the bottom to close it.
 *  - While recording it turns red and shows the recording time, so the
 *    recording is always visibly active.
 *
 * Needs Android's "Display over other apps" (SYSTEM_ALERT_WINDOW, already
 * declared and only asked when the user turns this on). It never captures
 * anything by itself: Record and Screenshot still show Android's own consent
 * dialog every time. It hides itself during a screenshot so it isn't in the
 * picture. Settings (on/off, position) are kept in private preferences.
 */
@SuppressLint("StaticFieldLeak") // holds only the application context
object CaptureBubble {

    private const val PREFS = "nova_capture_bubble"
    private const val SIZE_DP = 52
    private const val COLLAPSE_AFTER_MS = 6_000L
    private const val IDLE_ALPHA = 0.72f

    private val main = Handler(Looper.getMainLooper())
    private var app: Context? = null
    private var wm: WindowManager? = null

    private var root: FrameLayout? = null
    private var params: WindowManager.LayoutParams? = null
    private var bubble: FrameLayout? = null
    private var bubbleIcon: ImageView? = null
    private var bubbleTime: TextView? = null
    private var panel: LinearLayout? = null
    private var recordBtn: TextView? = null
    private var pauseBtn: TextView? = null
    private var closeTarget: View? = null
    private var expanded = false
    private var hiddenForCapture = false

    val isShowing: Boolean get() = root != null

    // ── Settings ──────────────────────────────────────────────────────────────

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(ctx: Context): Boolean = prefs(ctx).getBoolean("enabled", false)

    /** Turns the floating button on/off. Returns a CaptureContract result map. */
    fun setEnabled(ctx: Context, on: Boolean): Map<String, Any?> {
        val c = ctx.applicationContext
        if (on && !FloatingPermission.granted(c)) {
            return CaptureContract.error(CaptureContract.E_PERMISSION,
                "Allow “Display over other apps” for NOVA X to show the floating button.", "permission" to "overlay")
        }
        prefs(c).edit().putBoolean("enabled", on).apply()
        if (on) show(c) else hide()
        return CaptureContract.ok("enabled" to on, "showing" to isShowing)
    }

    /** Called when NOVA X starts and after the user returns from Android settings. */
    fun showIfEnabled(ctx: Context) {
        val c = ctx.applicationContext
        if (isEnabled(c) && FloatingPermission.granted(c)) show(c) else if (!FloatingPermission.granted(c)) hide()
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), app!!.resources.displayMetrics).toInt()

    // ── Show / hide ───────────────────────────────────────────────────────────

    @SuppressLint("ClickableViewAccessibility")
    fun show(ctx: Context) {
        if (root != null) { refresh(); return }
        app = ctx.applicationContext
        val c = app!!
        wm = c.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val frame = FrameLayout(c)

        // Collapsed: round button.
        val b = FrameLayout(c).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xF00F1E35.toInt())
                setStroke(dp(2), 0xFF00D4FF.toInt())
            }
            elevation = dp(6).toFloat()
            contentDescription = "NOVA Capture floating button. Tap for controls, drag to move."
            isClickable = true
        }
        val icon = ImageView(c).apply {
            setImageResource(R.drawable.ic_stat_nova_capture)
            setColorFilter(Color.WHITE)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        b.addView(icon, FrameLayout.LayoutParams(dp(26), dp(26), Gravity.CENTER))
        val time = TextView(c).apply {
            setTextColor(Color.WHITE)
            textSize = 11f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            visibility = View.GONE
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        b.addView(time, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        frame.addView(b, FrameLayout.LayoutParams(dp(SIZE_DP), dp(SIZE_DP)))

        // Expanded: control panel.
        val p = LinearLayout(c).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(6), dp(8), dp(6), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(30).toFloat()
                setColor(0xF20B1524.toInt())
                setStroke(dp(1), 0x3300D4FF)
            }
            elevation = dp(8).toFloat()
            visibility = View.GONE
        }
        val rec = roundButton(c, "●", 0xFFFF3B4E.toInt(), Color.WHITE, "Start screen recording") { onRecord() }
        val pause = roundButton(c, "Ⅱ", Color.WHITE, 0xFF111827.toInt(), "Pause recording") { onPauseResume() }
        val shot = roundButton(c, "📷", Color.WHITE, 0xFF111827.toInt(), "Take a screenshot of the screen") { onScreenshot() }
        val home = roundButton(c, "⌂", Color.WHITE, 0xFF111827.toInt(), "Open NOVA Capture") { onOpenApp() }
        val close = roundButton(c, "✕", 0x33FFFFFF, Color.WHITE, "Close the floating button") { onClose() }
        val collapse = roundButton(c, "︾", 0x00000000, Color.WHITE, "Hide controls") { collapse() }
        for (v in listOf(rec, pause, shot, home, close, collapse)) {
            p.addView(v, LinearLayout.LayoutParams(dp(46), dp(46)).apply { setMargins(0, dp(4), 0, dp(4)) })
        }
        frame.addView(p, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT))

        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            val m = c.resources.displayMetrics
            val pr = prefs(c)
            x = pr.getInt("x", m.widthPixels - dp(SIZE_DP) - dp(4))
            y = pr.getInt("y", (m.heightPixels * 0.32f).toInt())
        }

        frame.setOnTouchListener { _, e ->
            if (e.actionMasked == MotionEvent.ACTION_OUTSIDE && expanded) collapse()
            false
        }
        b.setOnTouchListener(dragListener(lp))

        try {
            wm?.addView(frame, lp)
        } catch (e: Exception) {
            return // permission withdrawn: nothing shown
        }
        root = frame; params = lp; bubble = b; bubbleIcon = icon; bubbleTime = time
        panel = p; recordBtn = rec; pauseBtn = pause
        expanded = false
        refresh()
        scheduleDim()
    }

    fun hide() {
        main.removeCallbacksAndMessages(null)
        removeCloseTarget()
        val r = root ?: return
        try { wm?.removeView(r) } catch (e: Exception) { }
        root = null; params = null; bubble = null; bubbleIcon = null; bubbleTime = null
        panel = null; recordBtn = null; pauseBtn = null; expanded = false
    }

    /** Keeps the button out of a screenshot. */
    fun hideForCapture(hidden: Boolean) {
        hiddenForCapture = hidden
        root?.visibility = if (hidden) View.INVISIBLE else View.VISIBLE
    }

    // ── State ─────────────────────────────────────────────────────────────────

    /** Called by CaptureCoordinator on every state change and every second while recording. */
    fun refresh() {
        val b = bubble ?: return
        val state = CaptureCoordinator.state
        val active = state == CaptureContract.RECORDING || state == CaptureContract.PAUSED
        val paused = state == CaptureContract.PAUSED
        val elapsed = CaptureNotifications.format(CaptureCoordinator.elapsedMs())
        (b.background as? GradientDrawable)?.setStroke(dp(2),
            when { paused -> 0xFFFFAB00.toInt(); active -> 0xFFFF3B4E.toInt(); else -> 0xFF00D4FF.toInt() })
        bubbleIcon?.visibility = if (active) View.GONE else View.VISIBLE
        bubbleTime?.visibility = if (active) View.VISIBLE else View.GONE
        bubbleTime?.text = if (paused) "Ⅱ\n$elapsed" else "●\n$elapsed"
        bubbleTime?.setTextColor(if (paused) 0xFFFFAB00.toInt() else Color.WHITE)
        b.contentDescription = when {
            paused -> "Recording paused at $elapsed. Tap for controls."
            active -> "Recording, $elapsed. Tap for controls."
            else -> "NOVA Capture floating button. Tap for controls, drag to move."
        }
        if (active) b.alpha = 1f
        recordBtn?.text = if (active) "■" else "●"
        recordBtn?.contentDescription = if (active) "Stop and save recording" else "Start screen recording"
        pauseBtn?.visibility = if (active) View.VISIBLE else View.GONE
        pauseBtn?.text = if (paused) "▶" else "Ⅱ"
        pauseBtn?.contentDescription = if (paused) "Resume recording" else "Pause recording"
    }

    // ── Actions ───────────────────────────────────────────────────────────────

    private fun onRecord() {
        val c = app ?: return
        collapse()
        if (CaptureCoordinator.isRecordingActive()) {
            CaptureCoordinator.stop(null, "user")
            return
        }
        CaptureCoordinator.startRecordingFromContext(c, RecordingConfig.fromFlutterPrefs(c)) { r ->
            if (r["success"] != true) {
                val msg = r["userMessage"] as? String
                if (msg != null && r["errorCode"] != CaptureContract.E_CONSENT_DENIED) toast(msg)
            }
        }
    }

    private fun onPauseResume() {
        if (CaptureCoordinator.state == CaptureContract.RECORDING) CaptureCoordinator.pause(null)
        else if (CaptureCoordinator.state == CaptureContract.PAUSED) CaptureCoordinator.resume(null)
        scheduleCollapse()
    }

    private fun onScreenshot() {
        val c = app ?: return
        collapse()
        CaptureCoordinator.captureScreenFromContext(c) { r ->
            if (r["success"] == true) toast("Screenshot saved to Pictures › NOVA X")
            else {
                val msg = r["userMessage"] as? String
                if (msg != null && r["errorCode"] != CaptureContract.E_CONSENT_DENIED) toast(msg)
            }
        }
    }

    private fun onOpenApp() {
        val c = app ?: return
        collapse()
        try {
            c.startActivity(Intent(c, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra(MainActivity.EXTRA_FEATURE, "capture")
            })
        } catch (e: Exception) { }
    }

    private fun onClose() {
        val c = app ?: return
        prefs(c).edit().putBoolean("enabled", false).apply()
        hide()
        toast("Floating button closed. Turn it on again in NOVA Capture.")
        CaptureCoordinator.onBubbleChanged()
    }

    private fun toast(msg: String) {
        val c = app ?: return
        main.post { try { Toast.makeText(c, msg, Toast.LENGTH_LONG).show() } catch (e: Exception) { } }
    }

    // ── Expand / collapse ─────────────────────────────────────────────────────

    private fun expand() {
        val b = bubble ?: return
        val p = panel ?: return
        expanded = true
        b.visibility = View.GONE
        p.visibility = View.VISIBLE
        root?.alpha = 1f
        refresh()
        keepOnScreen()
        scheduleCollapse()
    }

    fun collapse() {
        if (!expanded) return
        expanded = false
        panel?.visibility = View.GONE
        bubble?.visibility = View.VISIBLE
        keepOnScreen()
        scheduleDim()
    }

    private val collapseTask = Runnable { collapse() }
    private val dimTask = Runnable {
        if (!expanded && !CaptureCoordinator.isRecordingActive()) bubble?.animate()?.alpha(IDLE_ALPHA)?.setDuration(250)?.start()
    }

    private fun scheduleCollapse() {
        main.removeCallbacks(collapseTask)
        main.postDelayed(collapseTask, COLLAPSE_AFTER_MS)
    }

    private fun scheduleDim() {
        main.removeCallbacks(dimTask)
        bubble?.alpha = 1f
        main.postDelayed(dimTask, 3_000)
    }

    private fun keepOnScreen() {
        val r = root ?: return
        val lp = params ?: return
        r.post {
            val m = app?.resources?.displayMetrics ?: return@post
            val w = r.width.takeIf { it > 0 } ?: dp(SIZE_DP)
            val h = r.height.takeIf { it > 0 } ?: dp(SIZE_DP)
            lp.x = lp.x.coerceIn(0, (m.widthPixels - w).coerceAtLeast(0))
            lp.y = lp.y.coerceIn(dp(24), (m.heightPixels - h - dp(24)).coerceAtLeast(dp(24)))
            try { wm?.updateViewLayout(r, lp) } catch (e: Exception) { }
        }
    }

    // ── Drag, snap, drag-to-close ─────────────────────────────────────────────

    @SuppressLint("ClickableViewAccessibility")
    private fun dragListener(lp: WindowManager.LayoutParams) = View.OnTouchListener { v, e ->
        val c = app ?: return@OnTouchListener false
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                v.tag = floatArrayOf(e.rawX, e.rawY, lp.x.toFloat(), lp.y.toFloat(), 0f)
                v.alpha = 1f
                main.removeCallbacks(dimTask)
                true
            }
            MotionEvent.ACTION_MOVE -> {
                val t = v.tag as? FloatArray ?: return@OnTouchListener true
                val dx = e.rawX - t[0]
                val dy = e.rawY - t[1]
                if (t[4] == 0f && (abs(dx) > dp(8) || abs(dy) > dp(8))) {
                    t[4] = 1f
                    showCloseTarget()
                }
                if (t[4] == 1f) {
                    lp.x = (t[2] + dx).toInt()
                    lp.y = (t[3] + dy).toInt()
                    try { wm?.updateViewLayout(root, lp) } catch (ex: Exception) { }
                    highlightCloseTarget(overCloseTarget(e.rawX, e.rawY))
                }
                true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val t = v.tag as? FloatArray
                val dragged = t != null && t[4] == 1f
                val drop = dragged && overCloseTarget(e.rawX, e.rawY)
                removeCloseTarget()
                when {
                    drop -> onClose()
                    dragged -> snapToEdge(lp, c)
                    e.actionMasked == MotionEvent.ACTION_UP -> { v.performClick(); expand() }
                }
                true
            }
            else -> false
        }
    }

    private fun snapToEdge(lp: WindowManager.LayoutParams, c: Context) {
        val r = root ?: return
        val m = c.resources.displayMetrics
        val w = r.width.takeIf { it > 0 } ?: dp(SIZE_DP)
        val target = if (lp.x + w / 2 < m.widthPixels / 2) dp(4) else m.widthPixels - w - dp(4)
        lp.y = lp.y.coerceIn(dp(24), m.heightPixels - w - dp(48))
        ValueAnimator.ofInt(lp.x, target).apply {
            duration = 220
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                lp.x = it.animatedValue as Int
                try { wm?.updateViewLayout(r, lp) } catch (ex: Exception) { }
            }
            start()
        }
        prefs(c).edit().putInt("x", target).putInt("y", lp.y).apply()
        scheduleDim()
    }

    private fun closeTargetCenter(): Pair<Float, Float> {
        val m = app!!.resources.displayMetrics
        return Pair(m.widthPixels / 2f, m.heightPixels - dp(96).toFloat())
    }

    private fun overCloseTarget(x: Float, y: Float): Boolean {
        val (cx, cy) = closeTargetCenter()
        return hypot(x - cx, y - cy) < dp(64)
    }

    private fun showCloseTarget() {
        val c = app ?: return
        if (closeTarget != null) return
        val v = TextView(c).apply {
            text = "✕"
            textSize = 22f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xCC111827.toInt())
                setStroke(dp(2), 0x88FFFFFF.toInt())
            }
            contentDescription = "Drop here to close the floating button"
        }
        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE
        val size = dp(64)
        val (cx, cy) = closeTargetCenter()
        val lp = WindowManager.LayoutParams(size, size, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (cx - size / 2).toInt()
            y = (cy - size / 2).toInt()
        }
        try { wm?.addView(v, lp); closeTarget = v } catch (e: Exception) { }
    }

    private fun highlightCloseTarget(on: Boolean) {
        val v = closeTarget ?: return
        (v.background as? GradientDrawable)?.setColor(if (on) 0xEEFF3B4E.toInt() else 0xCC111827.toInt())
        v.scaleX = if (on) 1.15f else 1f
        v.scaleY = if (on) 1.15f else 1f
    }

    private fun removeCloseTarget() {
        val v = closeTarget ?: return
        closeTarget = null
        try { wm?.removeView(v) } catch (e: Exception) { }
    }

    private fun roundButton(c: Context, label: String, bg: Int, fg: Int, description: String, onTap: () -> Unit): TextView =
        TextView(c).apply {
            text = label
            textSize = 18f
            setTextColor(fg)
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(bg) }
            contentDescription = description
            isClickable = true
            setOnClickListener { onTap() }
        }
}

/** "Display over other apps" (SYSTEM_ALERT_WINDOW) state. */
object FloatingPermission {
    fun granted(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || android.provider.Settings.canDrawOverlays(ctx)
}
