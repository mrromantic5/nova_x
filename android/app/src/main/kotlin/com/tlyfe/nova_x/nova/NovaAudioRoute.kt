package com.tlyfe.nova_x.nova

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.SystemClock

/**
 * Which microphone NOVA listens with.
 *
 *  - Wired / USB-C earphones and headsets with a microphone: used whenever
 *    they are plugged in (no side effects).
 *  - Bluetooth headsets and earbuds: their microphone only works over the
 *    Bluetooth "call" link (SCO). NOVA opens that link while it records a
 *    command, and — when "Use headset microphone" is on — while it listens
 *    for "Hey NOVA". Music cannot play in full quality over that link, so
 *    "Hey NOVA" falls back to the phone's microphone while music or video is
 *    playing and returns to the headset when it stops.
 *
 * NOVA never takes the link from a call: nothing is changed while a call or
 * VoIP app is using audio, and NOVA only undoes what it set itself.
 */
object NovaAudioRoute {

    private const val FILE = "nova_wake"
    private const val KEY_HEADSET = "headset_mic"

    /** "Use headset microphone" (on by default). */
    fun headsetEnabled(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY_HEADSET, true)

    fun setHeadsetEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean(KEY_HEADSET, enabled).apply()
    }

    /** Kind of the best headset microphone connected now: "wired", "bluetooth" or null. */
    fun headsetKind(context: Context): String? {
        val d = headsetInput(context) ?: return null
        return if (isBluetooth(d)) "bluetooth" else "wired"
    }

    /** A connected headset microphone, best first (wired/USB, then Bluetooth). */
    fun headsetInput(context: Context): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return null
        val inputs = try { am.getDevices(AudioManager.GET_DEVICES_INPUTS) } catch (e: Exception) { return null }
        return inputs.filter { rank(it) > 0 }.maxByOrNull { rank(it) }
    }

    private fun rank(d: AudioDeviceInfo): Int = when (d.type) {
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> 4
        AudioDeviceInfo.TYPE_USB_HEADSET -> 4
        TYPE_BLE_HEADSET -> 3
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> 2
        else -> 0
    }

    // AudioDeviceInfo.TYPE_BLE_HEADSET (Android 12); the constant is 26.
    private const val TYPE_BLE_HEADSET = 26

    fun isBluetooth(d: AudioDeviceInfo): Boolean =
        d.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || d.type == TYPE_BLE_HEADSET

    /** True while a call or a VoIP app is using audio (never touch routing then). */
    fun inCall(context: Context): Boolean {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        val mode = am.mode
        return mode == AudioManager.MODE_IN_CALL || mode == AudioManager.MODE_IN_COMMUNICATION ||
            mode == AudioManager.MODE_RINGTONE
    }

    fun musicActive(context: Context): Boolean =
        (context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager)?.isMusicActive == true

    /**
     * One use of a headset microphone. [begin] picks the device (opening the
     * Bluetooth link if needed) and returns it for AudioRecord /
     * MediaRecorder.setPreferredDevice; [end] undoes what [begin] did.
     */
    class Session(context: Context) {
        private val app = context.applicationContext
        private val am = app.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        private var setCommDevice = false
        private var startedSco = false

        /** The device in use, or null for the phone's own microphone. */
        var device: AudioDeviceInfo? = null
            private set

        /**
         * [allowBluetooth] false = wired only. [waitMs] how long to wait for
         * the Bluetooth link (0 = don't wait: audio moves over once it's up).
         */
        fun begin(allowBluetooth: Boolean, waitMs: Long = 0L): AudioDeviceInfo? {
            end()
            val d = headsetInput(app) ?: return null
            if (!isBluetooth(d)) {
                device = d
                return d
            }
            if (!allowBluetooth || am == null || inCall(app)) return null
            val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val target = try {
                    am.availableCommunicationDevices.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || it.type == TYPE_BLE_HEADSET
                    }
                } catch (e: Exception) { null }
                val current = try { am.communicationDevice } catch (e: Exception) { null }
                when {
                    target == null -> false
                    current != null && current.id == target.id -> true // already routed (not ours to undo)
                    else -> try { am.setCommunicationDevice(target).also { setCommDevice = it } } catch (e: Exception) { false }
                }
            } else {
                @Suppress("DEPRECATION")
                try {
                    if (!am.isBluetoothScoAvailableOffCall) {
                        false
                    } else {
                        am.startBluetoothSco()
                        am.isBluetoothScoOn = true
                        startedSco = true
                        true
                    }
                } catch (e: Exception) { false }
            }
            if (!ok) {
                end()
                return null
            }
            if (waitMs > 0) waitForLink(waitMs)
            device = d
            return d
        }

        private fun waitForLink(waitMs: Long) {
            val until = SystemClock.elapsedRealtime() + waitMs
            while (SystemClock.elapsedRealtime() < until) {
                if (linkUp()) return
                try { Thread.sleep(40) } catch (e: InterruptedException) { Thread.currentThread().interrupt(); return }
            }
        }

        @Suppress("DEPRECATION")
        private fun linkUp(): Boolean = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val c = am?.communicationDevice
                c != null && (c.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || c.type == TYPE_BLE_HEADSET)
            } else {
                am?.isBluetoothScoOn == true
            }
        } catch (e: Exception) { false }

        fun end() {
            val m = am
            if (m != null) {
                if (setCommDevice && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    try { m.clearCommunicationDevice() } catch (ignored: Exception) { }
                }
                if (startedSco) {
                    @Suppress("DEPRECATION")
                    try {
                        m.isBluetoothScoOn = false
                        m.stopBluetoothSco()
                    } catch (ignored: Exception) { }
                }
            }
            setCommDevice = false
            startedSco = false
            device = null
        }
    }
}
