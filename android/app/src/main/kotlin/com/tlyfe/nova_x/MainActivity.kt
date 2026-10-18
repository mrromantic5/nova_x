package com.tlyfe.nova_x

import android.app.Activity
import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * NOVA X host Activity.
 *
 * Hosts three MethodChannels used by the Dart side:
 *   • com.tlyfe.nova_x/default_browser — default-browser role + incoming links
 *   • com.tlyfe.nova_x/permissions     — microphone runtime permission
 *   • com.tlyfe.nova_x/shortcuts       — launcher shortcuts (main.dart)
 *
 * Extends FlutterFragmentActivity because the local_auth plugin (biometric
 * unlock for saved passwords) requires a FragmentActivity.
 *
 * Launch mode is singleTask (see AndroidManifest.xml) so a link tapped in
 * another app is delivered to the running instance via onNewIntent().
 *
 * IMPORTANT: this file is the source of truth. The CI workflow must NOT
 * overwrite it (it previously replaced it with a stub that had none of the
 * default-browser logic, which is why the "Set as default" buttons did nothing
 * and incoming links only opened the home page).
 */
class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val BROWSER_CHANNEL     = "com.tlyfe.nova_x/default_browser"
        private const val PERMISSIONS_CHANNEL = "com.tlyfe.nova_x/permissions"
        private const val SHORTCUT_CHANNEL    = "com.tlyfe.nova_x/shortcuts"

        private const val REQ_BROWSER_ROLE = 4242
        private const val REQ_MICROPHONE   = 9001

        /**
         * If the role dialog returns "cancelled" faster than a human could
         * react, Android rejected it without showing UI (the user previously
         * declined it twice, or the OEM blocks the dialog). In that case we
         * fall back to the system Default-apps screen.
         */
        private const val AUTO_DENY_WINDOW_MS = 700L

        private const val SHORTCUT_ACTION_MARKER = "nova_x."
    }

    private var browserChannel: MethodChannel? = null

    /** Link waiting for Dart to collect via getInitialUrl (one-shot). */
    private var pendingUrl: String? = null

    /** Launcher shortcut action waiting for Dart (one-shot). */
    private var pendingShortcut: String = ""

    /** Dart call awaiting the result of the browser-role dialog. */
    private var pendingRoleResult: MethodChannel.Result? = null
    private var roleRequestStartedAt = 0L

    /** True when Android recreated this Activity from saved state. */
    private var isRestoredInstance = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // Must be set before super.onCreate(): the Flutter engine may be
        // configured during it, and a restored instance must not re-open the
        // link that originally launched the app.
        isRestoredInstance = savedInstanceState != null
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        if (!isRestoredInstance) {
            pendingUrl = extractUrl(intent)
            pendingShortcut = extractShortcut(intent)
        }

        // ── Default browser ────────────────────────────────────────────────
        browserChannel = MethodChannel(messenger, BROWSER_CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDefault"     -> result.success(isDefaultBrowser())
                    "request"       -> requestDefaultBrowser(result)
                    "openSettings"  -> result.success(openDefaultAppsSettings())
                    "getInitialUrl" -> {
                        result.success(pendingUrl)
                        pendingUrl = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // ── Microphone permission (PermissionSlidesScreen, slide 2) ────────
        MethodChannel(messenger, PERMISSIONS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestMicrophone" -> {
                    requestPermissions(
                        arrayOf(android.Manifest.permission.RECORD_AUDIO),
                        REQ_MICROPHONE
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // ── Launcher shortcuts (main.dart → getShortcut) ───────────────────
        // Same behaviour as the shortcut handler the CI used to generate.
        MethodChannel(messenger, SHORTCUT_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getShortcut") {
                result.success(pendingShortcut)
                pendingShortcut = ""
            } else {
                result.notImplemented()
            }
        }
    }

    // ── A link / shortcut arrives while NOVA X is already running ──────────
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingShortcut = extractShortcut(intent)
        extractUrl(intent)?.let { deliverUrl(it) }
    }

    /**
     * Push the URL to Dart immediately. If Dart can't open it yet (no home
     * screen mounted, e.g. user is on the login screen), keep it so
     * getInitialUrl() hands it over as soon as the home screen appears.
     */
    private fun deliverUrl(url: String) {
        val ch = browserChannel
        if (ch == null) {
            pendingUrl = url
            return
        }
        ch.invokeMethod("onNewUrl", url, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (result != true) pendingUrl = url
            }
            override fun error(code: String, message: String?, details: Any?) {
                pendingUrl = url
            }
            override fun notImplemented() {
                pendingUrl = url
            }
        })
    }

    // ── Result of the system "Set as default browser" dialog ───────────────
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // Always forward first: image_picker, file_picker etc. rely on it.
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_BROWSER_ROLE) return

        val result = pendingRoleResult ?: return
        pendingRoleResult = null

        val granted = resultCode == Activity.RESULT_OK || isDefaultBrowser()
        if (!granted &&
            SystemClock.elapsedRealtime() - roleRequestStartedAt < AUTO_DENY_WINDOW_MS) {
            // Dialog was suppressed by the system — open Default apps instead.
            openDefaultAppsSettings()
        }
        result.success(granted)
    }

    // ── Helpers ─────────────────────────────────────────────────────────────
    private fun extractUrl(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        // Re-launch from Recents re-delivers the original link — ignore it.
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return null
        val data: Uri = intent.data ?: return null
        val scheme = data.scheme?.lowercase() ?: return null
        return if (scheme == "http" || scheme == "https") data.toString() else null
    }

    private fun extractShortcut(intent: Intent?): String =
        intent?.action?.takeIf { it.contains(SHORTCUT_ACTION_MARKER) } ?: ""

    private fun isDefaultBrowser(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = getSystemService(Context.ROLE_SERVICE) as? RoleManager
            if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_BROWSER) &&
                rm.isRoleHeld(RoleManager.ROLE_BROWSER)) {
                return true
            }
        }
        // Fallback (Android 7–9, and OEMs whose settings don't update the role).
        return try {
            val probe = Intent(Intent.ACTION_VIEW, Uri.parse("http://example.com"))
                .addCategory(Intent.CATEGORY_BROWSABLE)
            val info = packageManager.resolveActivity(probe, PackageManager.MATCH_DEFAULT_ONLY)
            info?.activityInfo?.packageName == packageName
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Android 10+: shows the system role dialog and answers [result] only
     * after the user accepts/declines (see onActivityResult).
     * Android 7–9 (no role API): opens Default apps settings, answers false;
     * the Dart side re-checks when the app is resumed.
     */
    @Suppress("DEPRECATION")
    private fun requestDefaultBrowser(result: MethodChannel.Result) {
        if (isDefaultBrowser()) {
            result.success(true)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = getSystemService(Context.ROLE_SERVICE) as? RoleManager
            if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_BROWSER)) {
                // Settle any earlier request still waiting so its Future never hangs.
                pendingRoleResult?.success(false)
                pendingRoleResult = result
                roleRequestStartedAt = SystemClock.elapsedRealtime()
                try {
                    startActivityForResult(
                        rm.createRequestRoleIntent(RoleManager.ROLE_BROWSER),
                        REQ_BROWSER_ROLE
                    )
                    return
                } catch (e: Exception) {
                    pendingRoleResult = null // fall through to settings
                }
            }
        }

        openDefaultAppsSettings()
        result.success(false)
    }

    private fun openDefaultAppsSettings(): Boolean {
        val candidates = listOf(
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
            Intent(Settings.ACTION_SETTINGS)
        )
        for (candidate in candidates) {
            try {
                startActivity(candidate)
                return true
            } catch (e: Exception) {
                // try next
            }
        }
        return false
    }
}
