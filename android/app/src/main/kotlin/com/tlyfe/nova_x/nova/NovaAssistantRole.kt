package com.tlyfe.nova_x.nova

import android.app.Activity
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.provider.Settings

/**
 * Default digital-assistant role (RoleManager.ROLE_ASSISTANT).
 *
 * NOVA X qualifies for the role through NovaAssistActivity, which handles
 * android.intent.action.ASSIST. Android does not let apps request the
 * assistant role through a dialog (unlike the browser role), so the user is
 * sent to the system "Digital assistant app" screen and the result is read
 * back with isRoleHeld() when NOVA X resumes.
 */
object NovaAssistantRole {

    fun status(activity: Activity): Map<String, Any?> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = activity.getSystemService(RoleManager::class.java)
            val available = rm != null && rm.isRoleAvailable(RoleManager.ROLE_ASSISTANT)
            val held = available && rm != null && rm.isRoleHeld(RoleManager.ROLE_ASSISTANT)
            return mapOf(
                "supported" to available,
                "held" to held,
                "eligible" to hasAssistActivity(activity),
                "sdk" to Build.VERSION.SDK_INT,
            )
        }
        return mapOf(
            "supported" to true,
            "held" to legacyIsAssistant(activity),
            "eligible" to hasAssistActivity(activity),
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    /** Opens the system screen where the user picks the digital assistant app. */
    fun openSettings(activity: Activity): Boolean {
        val candidates = listOf(
            Intent(Settings.ACTION_VOICE_INPUT_SETTINGS),
            Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (intent in candidates) {
            try {
                activity.startActivity(intent)
                return true
            } catch (e: Exception) {
                // try the next screen
            }
        }
        return false
    }

    private fun hasAssistActivity(activity: Activity): Boolean = try {
        val probe = Intent(Intent.ACTION_ASSIST).setPackage(activity.packageName)
        @Suppress("DEPRECATION")
        activity.packageManager.queryIntentActivities(probe, 0).isNotEmpty()
    } catch (e: Exception) {
        false
    }

    /** Android 7–9: the selected assistant is stored in Settings.Secure "assistant". */
    private fun legacyIsAssistant(activity: Activity): Boolean = try {
        val flat = Settings.Secure.getString(activity.contentResolver, "assistant")
        val component = if (flat.isNullOrEmpty()) null else ComponentName.unflattenFromString(flat)
        component?.packageName == activity.packageName
    } catch (e: Exception) {
        false
    }
}
