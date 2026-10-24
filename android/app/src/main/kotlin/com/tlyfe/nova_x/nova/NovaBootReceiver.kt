package com.tlyfe.nova_x.nova

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * After the phone restarts or NOVA X is updated, "Hey NOVA" would stay off
 * until the user happened to open NOVA X. If the user had it on, NOVA tries to
 * resume; Android 11+ only gives the microphone to a service the user
 * started, so in that case the one-tap "turn Hey NOVA back on" notification
 * is shown (NovaWakeService falls back to it by itself).
 */
class NovaBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val app = context.applicationContext
        if (!NovaWakePrefs.isEnabled(app)) return
        if (!NovaWakeService.start(app)) NovaWakeService.showResumeNotice(app)
    }
}
