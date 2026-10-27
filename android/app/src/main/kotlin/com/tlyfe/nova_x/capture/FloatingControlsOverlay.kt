package com.tlyfe.nova_x.capture

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * Optional recording controls over other apps.
 *
 * Shown only when ALL of these are true: the user turned on "Floating
 * controls over other apps" in NOVA Capture, granted Android's "Display over
 * other apps" special access, a recording is running or paused, and NOVA X
 * itself is not on screen (inside NOVA X the Flutter controls are used).
 * Without the permission the notification controls are the fallback.
 *
 * It is a small, clearly labelled, draggable pill (never full-screen, never
 * disguised, not focusable so it can't take the keyboard), with a visible
 * recording indicator, the elapsed time, Pause/Resume and Stop & save. Tap the
 * dot to shrink it to the indicator only. It never blocks stopping.
 */
class FloatingControlsOverlay(private val ctx: Context) {

    interface Actions {
        fun onPauseResume()
        fun onStop()
    }

    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var root: LinearLayout? = null
    private var time: TextView? = null
    private var dot: TextView? = null
    private var pauseBtn: ImageButton? = null
    private var stopBtn: TextView? = null
    private var params: WindowManager.LayoutParams? = null
    private var collapsed = false

    val isShowing: Boolean get() = root != null

    companion object {
        fun permitted(ctx: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(ctx)
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), ctx.resources.displayMetrics).toInt()

    @SuppressLint("ClickableViewAccessibility")
    fun show(actions: Actions) {
        if (root != null || !permitted(ctx)) return
        val bg = GradientDrawable().apply {
            cornerRadius = dp(28).toFloat()
            setColor(0xEE0F1E35.toInt())
            setStroke(dp(1), 0x66FF3B4E)
        }
        val layout = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = bg
            setPadding(dp(10), dp(4), dp(6), dp(4))
            contentDescription = "NOVA X screen recording controls"
        }
        val d = TextView(ctx).apply {
            text = "●"
            setTextColor(0xFFFF3B4E.toInt())
            textSize = 18f
            gravity = Gravity.CENTER
            minWidth = dp(40)
            minHeight = dp(40)
            contentDescription = "Recording. Tap to shrink or expand the controls"
            setOnClickListener { toggleCollapsed() }
        }
        val t = TextView(ctx).apply {
            text = "0:00"
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = Typeface.MONOSPACE
            setPadding(dp(2), 0, dp(8), 0)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        }
        val p = ImageButton(ctx).apply {
            setImageResource(android.R.drawable.ic_media_pause)
            setBackgroundColor(Color.TRANSPARENT)
            minimumWidth = dp(44)
            minimumHeight = dp(44)
            contentDescription = "Pause recording"
            setOnClickListener { actions.onPauseResume() }
        }
        val s = TextView(ctx).apply {
            text = "■ Stop"
            setTextColor(Color.WHITE)
            textSize = 13f
            gravity = Gravity.CENTER
            minHeight = dp(40)
            setPadding(dp(12), 0, dp(12), 0)
            background = GradientDrawable().apply { cornerRadius = dp(20).toFloat(); setColor(0xFFFF3B4E.toInt()) }
            contentDescription = "Stop and save recording"
            setOnClickListener { actions.onStop() }
        }
        layout.addView(d)
        layout.addView(t)
        layout.addView(p)
        layout.addView(s)

        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(12)
            y = (ctx.resources.displayMetrics.heightPixels * 0.35f).toInt()
        }

        // Drag by the time label (and the whole pill when collapsed).
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        val drag = View.OnTouchListener { v, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY; startX = lp.x; startY = lp.y; moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX
                    val dy = e.rawY - downY
                    if (abs(dx) > dp(6) || abs(dy) > dp(6)) moved = true
                    if (moved) {
                        val m = ctx.resources.displayMetrics
                        lp.x = (startX + dx).toInt().coerceIn(0, m.widthPixels - dp(48))
                        lp.y = (startY + dy).toInt().coerceIn(dp(24), m.heightPixels - dp(96))
                        try { wm.updateViewLayout(layout, lp) } catch (ex: Exception) { }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) v.performClick()
                    true
                }
                else -> false
            }
        }
        t.setOnTouchListener(drag)
        d.setOnTouchListener(drag)

        try {
            wm.addView(layout, lp)
            root = layout; time = t; dot = d; pauseBtn = p; stopBtn = s; params = lp
        } catch (e: Exception) {
            root = null
        }
    }

    private fun toggleCollapsed() {
        collapsed = !collapsed
        val vis = if (collapsed) View.GONE else View.VISIBLE
        time?.visibility = vis
        pauseBtn?.visibility = vis
        stopBtn?.visibility = vis
        dot?.contentDescription = if (collapsed) "Recording. Tap to show the controls" else "Recording. Tap to shrink the controls"
    }

    fun update(paused: Boolean, elapsedMs: Long) {
        time?.text = if (paused) "Ⅱ ${CaptureNotifications.format(elapsedMs)}" else CaptureNotifications.format(elapsedMs)
        time?.contentDescription = (if (paused) "Paused at " else "Recording time ") + CaptureNotifications.format(elapsedMs)
        dot?.setTextColor(if (paused) 0xFFFFAB00.toInt() else 0xFFFF3B4E.toInt())
        pauseBtn?.setImageResource(if (paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause)
        pauseBtn?.contentDescription = if (paused) "Resume recording" else "Pause recording"
    }

    fun hide() {
        val r = root ?: return
        try { wm.removeView(r) } catch (e: Exception) { }
        root = null; time = null; dot = null; pauseBtn = null; stopBtn = null; params = null
        collapsed = false
    }
}
