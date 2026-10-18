package com.tlyfe.nova_x

import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity is required by the local_auth (biometric) plugin.
 *
 * Hosts two MethodChannels:
 *   1. com.tlyfe.nova_x/default_browser  — default-browser request/check + incoming URL relay
 *   2. com.tlyfe.nova_x/permissions      — microphone permission request
 *
 * Default-browser flow (Android 10+):
 *   Flutter calls "request"
 *     → MainActivity calls startActivityForResult(RoleManager intent, REQ_BROWSER)
 *     → onActivityResult fires when user dismisses the dialog
 *     → result is sent back to Flutter via the "onRoleResult" method
 *
 * Default-browser flow (Android 9 and below):
 *   Opens ACTION_MANAGE_DEFAULT_APPS_SETTINGS; no result callback (OS limitation).
 *
 * Incoming URL relay:
 *   • Cold-start: url is stored in pendingUrl; Flutter reads it via "getInitialUrl"
 *   • Warm/hot (singleTop onNewIntent): url is sent via "onNewUrl" when channel is ready
 *     If the channel isn't ready yet the URL is queued in pendingUrl so getInitialUrl
 *     still returns it.
 */
class MainActivity : FlutterFragmentActivity() {

    private val channelName = "com.tlyfe.nova_x/default_browser"
    private var channel: MethodChannel? = null

    /** URL waiting to be delivered to Flutter (cold-start or pre-channel onNewIntent). */
    private var pendingUrl: String? = null

    /** Request code for RoleManager.createRequestRoleIntent(ROLE_BROWSER). */
    private val REQ_BROWSER = 4242

    // ── Engine configuration ──────────────────────────────────────────────────
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Capture URL from the intent that started the Activity (cold start or
        // singleTop re-launch before the channel was set up).
        if (pendingUrl == null) pendingUrl = extractUrl(intent)

        // ── Default-browser channel ───────────────────────────────────────────
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {

                "isDefault" ->
                    result.success(isDefaultBrowser())

                "request" -> {
                    requestDefaultBrowser()
                    result.success(true)
                }

                "getInitialUrl" -> {
                    val url = pendingUrl
                    pendingUrl = null
                    result.success(url)
                }

                else -> result.notImplemented()
            }
        }

        // ── Microphone permission channel ─────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.tlyfe.nova_x/permissions"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestMicrophone" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        requestPermissions(
                            arrayOf(android.Manifest.permission.RECORD_AUDIO),
                            9001
                        )
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── New intent (singleTop warm/hot launch from another app) ───────────────
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val url = extractUrl(intent) ?: return
        val ch  = channel
        if (ch != null) {
            // Flutter is running — deliver immediately.
            ch.invokeMethod("onNewUrl", url)
        } else {
            // Flutter not ready yet — queue it so getInitialUrl returns it.
            pendingUrl = url
        }
    }

    // ── RoleManager result (Android 10+ default-browser dialog) ──────────────
    @Suppress("DEPRECATION")          // startActivityForResult is fine inside an Activity
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_BROWSER) {
            // resultCode == RESULT_OK means the user granted the role.
            val granted = (resultCode == Activity.RESULT_OK)
            channel?.invokeMethod("onRoleResult", granted)
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /** Extract an http/https URL from a VIEW intent, or return null. */
    private fun extractUrl(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val data: Uri = intent.data ?: return null
        val scheme = data.scheme?.lowercase() ?: return null
        return if (scheme == "http" || scheme == "https") data.toString() else null
    }

    /** True if NOVA X is the current default browser. */
    private fun isDefaultBrowser(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = getSystemService(Context.ROLE_SERVICE) as RoleManager
            rm.isRoleHeld(RoleManager.ROLE_BROWSER)
        } else {
            val probe = Intent(Intent.ACTION_VIEW, Uri.parse("http://example.com"))
            val res   = packageManager.resolveActivity(probe, 0)
            res?.activityInfo?.packageName == packageName
        }
    }

    /**
     * On Android 10+ (Q): shows the system role-request dialog.
     * Result arrives in onActivityResult(REQ_BROWSER, ...).
     * On Android 9 and below, or when the role isn't available yet (manifest
     * not deployed / app not recognised as a browser candidate): opens Default
     * Apps settings so the user can set it manually, and sends onRoleResult(false)
     * immediately so Flutter doesn't spin forever waiting for a callback.
     */
    private fun requestDefaultBrowser() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = getSystemService(Context.ROLE_SERVICE) as RoleManager
            if (rm.isRoleAvailable(RoleManager.ROLE_BROWSER)) {
                // Role is available — show the proper system dialog.
                // Result arrives in onActivityResult(REQ_BROWSER, ...).
                @Suppress("DEPRECATION")
                startActivityForResult(
                    rm.createRequestRoleIntent(RoleManager.ROLE_BROWSER),
                    REQ_BROWSER
                )
                return
            }
            // Role not available = app isn't recognised as a browser candidate yet.
            // Fall through to settings and notify Flutter immediately so the
            // spinner stops; the user can set it manually in Default Apps.
            channel?.invokeMethod("onRoleResult", false)
        }
        openDefaultAppsSettings()
    }

    private fun openDefaultAppsSettings() {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
            else
                Intent(Settings.ACTION_SETTINGS)
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }
}
