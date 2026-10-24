package com.tlyfe.nova_x

import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import com.tlyfe.nova_x.nova.NovaBridge
import com.tlyfe.nova_x.nova.NovaMicArbiter
import com.tlyfe.nova_x.nova.NovaScreenCapture
import com.tlyfe.nova_x.nova.NovaWakePrefs
import com.tlyfe.nova_x.nova.NovaWakeService
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * NOVA's floating assistant window.
 *
 * Android launches this Activity (android.intent.action.ASSIST) when the user
 * invokes the digital assistant — long-press Home, hold the power button or
 * the assistant gesture, depending on the phone — and NOVA X is selected as
 * the "Digital assistant app". It runs the separate Dart entrypoint
 * `novaAssistantMain` (declared in the manifest via io.flutter.Entrypoint)
 * on a transparent window, so NOVA's panel floats over whatever app the user
 * is in. Opening from the assistant gesture needs no overlay permission;
 * "Display over other apps" (optional, user-granted) only lets "Hey NOVA"
 * open this window directly while another app is in front.
 *
 * It also opens when the user says "Hey NOVA" (NovaWakeService); the launch
 * reason ("assist" or "wake") is passed to Dart so a wake word skips the
 * greeting and listens straight away.
 *
 * Privacy: the microphone is released whenever this window stops, and the
 * window finishes when the user leaves it.
 */
class NovaAssistActivity : FlutterFragmentActivity() {

    companion object {
        const val EXTRA_REASON = "com.tlyfe.nova_x.NOVA_REASON"

        /** "Hey NOVA" with the screen off/locked: show over the lock screen. */
        const val EXTRA_LOCK_SCREEN = "com.tlyfe.nova_x.NOVA_LOCK_SCREEN"

        /** elapsedRealtime of the last start (lets the wake service detect a blocked launch). */
        @Volatile var lastStartedAt = 0L
            private set
    }

    private var bridge: NovaBridge? = null

    /** True while the photo picker / camera (opened from the panel) is in front. */
    private var keepOpen = false

    override fun onCreate(savedInstanceState: Bundle?) {
        lastStartedAt = SystemClock.elapsedRealtime()
        clearWakeAlert()
        applyLockScreen(intent)
        // Ask the Flutter embedding for a transparent surface
        // (FlutterActivityLaunchConfigs.EXTRA_BACKGROUND_MODE).
        intent.putExtra("background_mode", "transparent")
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = NovaBridge(this, flutterEngine.dartExecutor.binaryMessenger) { closeAssistant() }.also {
            it.launchReason = reasonOf(intent)
            it.keepOpenHandler = { open -> keepOpen = open }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        lastStartedAt = SystemClock.elapsedRealtime()
        clearWakeAlert()
        applyLockScreen(intent)
        // Invoked again while already open — start listening again.
        bridge?.emitAssistInvoked(reasonOf(intent))
    }

    override fun onStart() {
        super.onStart()
        NovaMicArbiter.activityStarted()
        NovaMicArbiter.hold("assistant_window", true)
    }

    /**
     * Shows NOVA over the lock screen and turns the screen on — only for
     * "Hey NOVA" when the user turned on "Listen when the screen is off".
     * Actions that need the phone unlocked ask for the PIN first (NovaBridge).
     */
    private fun applyLockScreen(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_LOCK_SCREEN, false) != true) return
        if (!NovaWakePrefs.screenOffEnabled(this)) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    private fun reasonOf(intent: Intent?): String =
        if (intent?.getStringExtra(EXTRA_REASON) == "wake") "wake" else "assist"

    private fun clearWakeAlert() {
        try {
            (getSystemService(NOTIFICATION_SERVICE) as? NotificationManager)
                ?.cancel(NovaWakeService.ALERT_NOTIFICATION_ID)
        } catch (ignored: Exception) { }
    }

    @Suppress("DEPRECATION")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bridge?.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onResume() {
        super.onResume()
        // Back from the photo picker / camera / screen-capture dialog.
        keepOpen = false
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (NovaScreenCapture.onActivityResult(applicationContext, requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onStop() {
        super.onStop()
        NovaMicArbiter.activityStopped()
        NovaMicArbiter.hold("assistant_window", false)
        bridge?.onHostStop()
        if (!isChangingConfigurations && !keepOpen) closeAssistant()
    }

    override fun onDestroy() {
        NovaScreenCapture.cancel()
        bridge?.dispose()
        bridge = null
        super.onDestroy()
    }

    private fun closeAssistant() {
        if (isFinishing) return
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, android.R.anim.fade_out)
    }
}
