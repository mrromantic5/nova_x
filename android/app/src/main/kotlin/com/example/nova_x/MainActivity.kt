package com.example.nova_x

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
 * Also hosts the default-browser MethodChannel and handles incoming http(s)
 * VIEW intents so links from other apps open inside NOVA X.
 */
class MainActivity : FlutterFragmentActivity() {

    private val channelName = "com.example.nova_x/default_browser"
    private var channel: MethodChannel? = null
    private var pendingUrl: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isDefault"      -> result.success(isDefaultBrowser())
                "request"        -> { requestDefaultBrowser(); result.success(true) }
                "getInitialUrl"  -> { result.success(pendingUrl); pendingUrl = null }
                else             -> result.notImplemented()
            }
        }
        pendingUrl = extractUrl(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val url = extractUrl(intent)
        if (url != null) channel?.invokeMethod("onNewUrl", url)
    }

    private fun extractUrl(intent: Intent?): String? {
        if (intent?.action == Intent.ACTION_VIEW) {
            val data: Uri? = intent.data
            val scheme = data?.scheme?.lowercase()
            if (data != null && (scheme == "http" || scheme == "https")) {
                return data.toString()
            }
        }
        return null
    }

    private fun isDefaultBrowser(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = getSystemService(Context.ROLE_SERVICE) as RoleManager
            rm.isRoleHeld(RoleManager.ROLE_BROWSER)
        } else {
            val probe = Intent(Intent.ACTION_VIEW, Uri.parse("http://example.com"))
            val res = packageManager.resolveActivity(probe, 0)
            res?.activityInfo?.packageName == packageName
        }
    }

    private fun requestDefaultBrowser() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = getSystemService(Context.ROLE_SERVICE) as RoleManager
            if (rm.isRoleAvailable(RoleManager.ROLE_BROWSER) &&
                !rm.isRoleHeld(RoleManager.ROLE_BROWSER)) {
                startActivityForResult(
                    rm.createRequestRoleIntent(RoleManager.ROLE_BROWSER), 4242)
                return
            }
        }
        openDefaultAppsSettings()
    }

    private fun openDefaultAppsSettings() {
        try {
            val i = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
            else Intent(Settings.ACTION_SETTINGS)
            startActivity(i)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }
}
