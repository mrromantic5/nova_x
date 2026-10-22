package com.tlyfe.nova_x.nova

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.provider.Settings
import android.telephony.TelephonyManager
import android.util.DisplayMetrics
import android.view.WindowManager
import java.net.Inet4Address
import java.net.Inet6Address

/**
 * NOVA Network: details about this phone and its connection, read on the
 * phone with no dangerous permission (no location, no phone-state access):
 *
 *   device  — name, maker, model, Android version
 *   battery — %, charging and how, temperature, health, battery saver
 *   network — Wi-Fi / mobile data / Ethernet / VPN, metered, internet
 *             validated, Wi-Fi link speed, band, signal (RSSI, 0–4 bars),
 *             mobile operator name, bandwidth estimates, local IP addresses,
 *             DNS servers, Private DNS, IPv6, MTU
 *   system  — RAM, storage, CPU cores and ABI, screen size, refresh rate
 *
 * The Wi-Fi network name (SSID) is not read: Android only gives it to apps
 * with location permission, which NOVA X does not ask for here.
 * Nothing is sent anywhere — the map goes to Dart only.
 */
object NovaDeviceInfo {

    fun read(ctx: Context): Map<String, Any?> = mapOf(
        "device" to safe { device(ctx) },
        "battery" to safe { battery(ctx) },
        "network" to safe { network(ctx) },
        "system" to safe { system(ctx) },
    )

    private inline fun safe(block: () -> Map<String, Any?>): Map<String, Any?> =
        try { block() } catch (e: Exception) { emptyMap() }

    private fun device(ctx: Context): Map<String, Any?> {
        val userName = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                Settings.Global.getString(ctx.contentResolver, Settings.Global.DEVICE_NAME)
            } else null
        } catch (e: Exception) { null }
        val maker = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        val model = Build.MODEL ?: ""
        val name = userName?.takeIf { it.isNotBlank() }
            ?: if (model.startsWith(maker, ignoreCase = true)) model else "$maker $model"
        return mapOf(
            "name" to name,
            "manufacturer" to maker,
            "model" to model,
            "brand" to Build.BRAND,
            "android" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    private fun battery(ctx: Context): Map<String, Any?> {
        val bm = ctx.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val sticky = ctx.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        var level = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        if (level !in 0..100 && sticky != null) {
            val raw = sticky.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = sticky.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
            if (raw >= 0 && scale > 0) level = raw * 100 / scale
        }
        val status = sticky?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val plugged = sticky?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val temp = sticky?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE) ?: Int.MIN_VALUE
        val health = sticky?.getIntExtra(BatteryManager.EXTRA_HEALTH, 0) ?: 0
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return mapOf(
            "level" to level.takeIf { it in 0..100 },
            "charging" to (status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL),
            "full" to (status == BatteryManager.BATTERY_STATUS_FULL),
            "plugged" to when (plugged) {
                BatteryManager.BATTERY_PLUGGED_AC -> "Charger"
                BatteryManager.BATTERY_PLUGGED_USB -> "USB"
                BatteryManager.BATTERY_PLUGGED_WIRELESS -> "Wireless"
                else -> null
            },
            "temperature" to if (temp == Int.MIN_VALUE) null else temp / 10.0,
            "health" to when (health) {
                BatteryManager.BATTERY_HEALTH_GOOD -> "Good"
                BatteryManager.BATTERY_HEALTH_OVERHEAT -> "Overheating"
                BatteryManager.BATTERY_HEALTH_DEAD -> "Dead"
                BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "Over voltage"
                BatteryManager.BATTERY_HEALTH_COLD -> "Cold"
                BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "Failure"
                else -> null
            },
            "powerSave" to (pm?.isPowerSaveMode == true),
        )
    }

    @Suppress("DEPRECATION")
    private fun network(ctx: Context): Map<String, Any?> {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return mapOf("transport" to "none")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            val info = cm.activeNetworkInfo
            return mapOf(
                "transport" to when {
                    info == null || !info.isConnected -> "none"
                    info.type == ConnectivityManager.TYPE_WIFI -> "wifi"
                    info.type == ConnectivityManager.TYPE_MOBILE -> "cellular"
                    info.type == ConnectivityManager.TYPE_ETHERNET -> "ethernet"
                    else -> "other"
                },
                "metered" to cm.isActiveNetworkMetered,
            )
        }
        val network = cm.activeNetwork ?: return mapOf("transport" to "none")
        val caps = cm.getNetworkCapabilities(network) ?: return mapOf("transport" to "none")
        val link = cm.getLinkProperties(network)
        val transport = when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "bluetooth"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            else -> "other"
        }
        val out = mutableMapOf<String, Any?>(
            "transport" to transport,
            "vpn" to caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN),
            "metered" to cm.isActiveNetworkMetered,
            "validated" to caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
            "downKbps" to caps.linkDownstreamBandwidthKbps,
            "upKbps" to caps.linkUpstreamBandwidthKbps,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val strength = caps.signalStrength
            if (strength != NetworkCapabilities.SIGNAL_STRENGTH_UNSPECIFIED) out["signalDbm"] = strength
        }
        if (link != null) {
            val addresses = link.linkAddresses.map { it.address }
            out["localIps"] = addresses.filter { !it.isLoopbackAddress && !it.isLinkLocalAddress }
                .mapNotNull { it.hostAddress?.substringBefore('%') }
            out["ipv6"] = addresses.any { it is Inet6Address && !it.isLinkLocalAddress && !it.isLoopbackAddress }
            out["ipv4"] = addresses.any { it is Inet4Address }
            out["dnsServers"] = link.dnsServers.mapNotNull { it.hostAddress?.substringBefore('%') }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                out["privateDns"] = link.isPrivateDnsActive
                out["privateDnsServer"] = link.privateDnsServerName
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && link.mtu > 0) out["mtu"] = link.mtu
        }
        if (transport == "wifi") wifi(ctx, caps, out)
        if (transport == "cellular") {
            val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            out["carrier"] = tm?.networkOperatorName?.takeIf { it.isNotBlank() }
            out["roaming"] = try { tm?.isNetworkRoaming } catch (e: Exception) { null }
            (out["signalDbm"] as? Int)?.let { out["signalLevel"] = cellLevel(it) }
        }
        return out
    }

    @Suppress("DEPRECATION")
    private fun wifi(ctx: Context, caps: NetworkCapabilities, out: MutableMap<String, Any?>) {
        val info: WifiInfo? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            caps.transportInfo as? WifiInfo
        } else null
        val fallback: WifiInfo? = info ?: try {
            (ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager)?.connectionInfo
        } catch (e: Exception) { null }
        val wifi = fallback ?: return
        if (wifi.linkSpeed > 0) out["wifiLinkMbps"] = wifi.linkSpeed
        if (wifi.frequency > 0) out["wifiFrequency"] = wifi.frequency
        val rssi = wifi.rssi
        if (rssi in -126..-1) {
            out["wifiRssi"] = rssi
            out["signalDbm"] = rssi
            out["signalLevel"] = wifiLevel(rssi)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            out["wifiStandard"] = when (wifi.wifiStandard) {
                4 -> "Wi-Fi 4 (802.11n)"
                5 -> "Wi-Fi 5 (802.11ac)"
                6 -> "Wi-Fi 6 (802.11ax)"
                7 -> "Wi-Fi 7 (802.11be)"
                1 -> "802.11a/b/g"
                else -> null
            }
        }
    }

    /** 0–4 bars, as Android shows them. */
    private fun wifiLevel(rssi: Int): Int = when {
        rssi >= -55 -> 4
        rssi >= -66 -> 3
        rssi >= -77 -> 2
        rssi >= -88 -> 1
        else -> 0
    }

    private fun cellLevel(dbm: Int): Int = when {
        dbm >= -85 -> 4
        dbm >= -95 -> 3
        dbm >= -105 -> 2
        dbm >= -115 -> 1
        else -> 0
    }

    @Suppress("DEPRECATION")
    private fun system(ctx: Context): Map<String, Any?> {
        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val mem = ActivityManager.MemoryInfo().also { am?.getMemoryInfo(it) }
        val stat = StatFs(Environment.getDataDirectory().path)
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        val dm = DisplayMetrics()
        var refresh: Float? = null
        if (wm != null) {
            wm.defaultDisplay.getRealMetrics(dm)
            refresh = wm.defaultDisplay.refreshRate
        }
        return mapOf(
            "ramTotalMb" to mem.totalMem / (1024 * 1024),
            "ramFreeMb" to mem.availMem / (1024 * 1024),
            "storageTotalMb" to stat.totalBytes / (1024 * 1024),
            "storageFreeMb" to stat.availableBytes / (1024 * 1024),
            "cpuCores" to Runtime.getRuntime().availableProcessors(),
            "abi" to Build.SUPPORTED_ABIS.firstOrNull(),
            "screen" to if (dm.widthPixels > 0) "${dm.widthPixels} × ${dm.heightPixels}" else null,
            "refreshRate" to refresh?.toDouble(),
        )
    }
}
