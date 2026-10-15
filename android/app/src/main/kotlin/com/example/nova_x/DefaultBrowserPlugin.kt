// android/app/src/main/kotlin/com/techlyfe/nova_x/DefaultBrowserPlugin.kt
//
// Registers a MethodChannel that opens Android's default browser role selector.
// Register it in MainActivity.kt (see note at bottom of file).

package com.techlyfe.nova_x

import android.app.role.RoleManager
import android.content.Intent
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object DefaultBrowserPlugin {

    private const val CHANNEL = "nova_x/default_browser"
    private const val REQUEST_CODE = 1001

    fun register(activity: MainActivity, flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "openDefaultBrowserSettings") {
                openDefaultBrowser(activity, result)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun openDefaultBrowser(activity: MainActivity, result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+: use RoleManager for the proper role picker
                val roleManager = activity.getSystemService(RoleManager::class.java)
                if (roleManager != null && !roleManager.isRoleHeld(RoleManager.ROLE_BROWSER)) {
                    val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_BROWSER)
                    activity.startActivityForResult(intent, REQUEST_CODE)
                }
            } else {
                // Android 9 and below: open Default Apps settings
                val intent = Intent(android.provider.Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
                activity.startActivity(intent)
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("DEFAULT_BROWSER_ERROR", e.message, null)
        }
    }
}

// ─── How to register in MainActivity.kt ──────────────────────────────────────
//
// package com.techlyfe.nova_x
//
// import io.flutter.embedding.android.FlutterActivity
// import io.flutter.embedding.engine.FlutterEngine
//
// class MainActivity : FlutterActivity() {
//     override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
//         super.configureFlutterEngine(flutterEngine)
//         DefaultBrowserPlugin.register(this, flutterEngine)
//     }
// }
