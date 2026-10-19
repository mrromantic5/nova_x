package com.tlyfe.nova_x.nova

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.AlarmClock
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import com.tlyfe.nova_x.MainActivity
import java.util.Locale

/**
 * The only device actions NOVA can perform. Each one maps validated, plain
 * arguments onto a fixed Android intent. Nothing here accepts class names,
 * raw intents, URIs with arbitrary schemes or shell commands from Dart/AI.
 *
 * Results are maps with a "status" of: success, not_found, unsupported,
 * invalid, error — plus small display fields (label, opened, matches).
 * Launching an intent is reported as "success" meaning "opened"; it is never
 * reported as the end result (e.g. a call being connected).
 */
class NovaDeviceActions(private val activity: Activity) {

    private val pm: PackageManager get() = activity.packageManager

    /** Canonical app keys → candidate packages (first installed one wins). */
    private val knownPackages: Map<String, List<String>> = mapOf(
        "youtube" to listOf("com.google.android.youtube"),
        "youtube_music" to listOf("com.google.android.apps.youtube.music"),
        "whatsapp" to listOf("com.whatsapp", "com.whatsapp.w4b"),
        "instagram" to listOf("com.instagram.android"),
        "facebook" to listOf("com.facebook.katana", "com.facebook.lite"),
        "messenger" to listOf("com.facebook.orca", "com.facebook.mlite"),
        "tiktok" to listOf("com.zhiliaoapp.musically", "com.ss.android.ugc.trill"),
        "x" to listOf("com.twitter.android"),
        "telegram" to listOf("org.telegram.messenger", "org.telegram.messenger.web"),
        "snapchat" to listOf("com.snapchat.android"),
        "spotify" to listOf("com.spotify.music"),
        "netflix" to listOf("com.netflix.mediaclient"),
        "gmail" to listOf("com.google.android.gm"),
        "maps" to listOf("com.google.android.apps.maps"),
        "play_store" to listOf("com.android.vending"),
        "chrome" to listOf("com.android.chrome"),
        "linkedin" to listOf("com.linkedin.android"),
        "zoom" to listOf("us.zoom.videomeetings"),
        "google" to listOf("com.google.android.googlequicksearchbox"),
        "drive" to listOf("com.google.android.apps.docs"),
        "photos" to listOf("com.google.android.apps.photos"),
        "chatxap" to listOf("com.tlyfe.chatxap"),
        "calculator" to listOf(
            "com.google.android.calculator",
            "com.sec.android.app.popupcalculator",
            "com.miui.calculator",
            "com.oneplus.calculator",
            "com.coloros.calculator",
            "com.android.calculator2"
        ),
    )

    private val displayNames: Map<String, String> = mapOf(
        "youtube" to "YouTube", "youtube_music" to "YouTube Music", "whatsapp" to "WhatsApp",
        "instagram" to "Instagram", "facebook" to "Facebook", "messenger" to "Messenger",
        "tiktok" to "TikTok", "x" to "X", "telegram" to "Telegram", "snapchat" to "Snapchat",
        "spotify" to "Spotify", "netflix" to "Netflix", "gmail" to "Gmail", "maps" to "Maps",
        "play_store" to "Play Store", "chrome" to "Chrome", "linkedin" to "LinkedIn",
        "zoom" to "Zoom", "google" to "Google", "drive" to "Drive", "photos" to "Photos",
        "chatxap" to "ChatXAP", "calculator" to "Calculator", "camera" to "Camera",
        "phone" to "Phone", "messages" to "Messages", "contacts" to "Contacts",
        "email" to "Email", "gallery" to "Gallery", "music" to "Music",
        "calendar" to "Calendar", "clock" to "Clock", "settings" to "Settings",
    )

    // ── Apps ────────────────────────────────────────────────────────────────

    fun openApp(raw: String?): Map<String, Any?> {
        val key = normaliseKey(raw) ?: return status("invalid")
        if (key == "nova_x") {
            // Brings NOVA X's main window to the front (no-op if already there).
            val home = Intent(activity, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return if (start(home)) mapOf("status" to "success", "label" to "NOVA X") else status("error")
        }

        intentForCategory(key)?.let { intent ->
            if (start(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))) {
                return mapOf("status" to "success", "label" to (displayNames[key] ?: key))
            }
        }

        knownPackages[key]?.forEach { pkg ->
            val launch = pm.getLaunchIntentForPackage(pkg)
            if (launch != null && start(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))) {
                return mapOf("status" to "success", "label" to (displayNames[key] ?: key))
            }
        }

        // Last resort: match the spoken name against launcher labels on the
        // device. The lookup happens locally; the app list is never returned
        // to Dart or sent anywhere.
        findLauncherAppByLabel(key.replace('_', ' '))?.let { (pkg, label) ->
            val launch = pm.getLaunchIntentForPackage(pkg)
            if (launch != null && start(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))) {
                return mapOf("status" to "success", "label" to label)
            }
        }
        return status("not_found")
    }

    private fun intentForCategory(key: String): Intent? = when (key) {
        "camera" -> Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA)
        "phone" -> Intent(Intent.ACTION_DIAL)
        "messages" -> Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_MESSAGING)
        "contacts" -> Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_CONTACTS)
        "email" -> Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_EMAIL)
        "gallery" -> Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_GALLERY)
        "music" -> Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_MUSIC)
        "calendar" -> Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_CALENDAR)
        "clock" -> Intent(AlarmClock.ACTION_SHOW_ALARMS)
        "settings" -> Intent(Settings.ACTION_SETTINGS)
        else -> null
    }

    private fun findLauncherAppByLabel(spoken: String): Pair<String, String>? {
        val wanted = spoken.lowercase(Locale.ROOT).trim()
        if (wanted.length < 2) return null
        val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = try {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(query, 0)
        } catch (e: Exception) {
            return null
        }
        var best: Pair<String, String>? = null
        var bestScore = 0
        for (info in apps) {
            val pkg = info.activityInfo?.packageName ?: continue
            if (pkg == activity.packageName) continue
            val label = info.loadLabel(pm)?.toString()?.trim().orEmpty()
            if (label.isEmpty()) continue
            val l = label.lowercase(Locale.ROOT)
            val score = when {
                l == wanted -> 3
                l.startsWith("$wanted ") || l.startsWith(wanted) -> 2
                wanted.length >= 4 && l.contains(wanted) -> 1
                else -> 0
            }
            if (score > bestScore) {
                bestScore = score
                best = pkg to label
                if (score == 3) break
            }
        }
        return best
    }

    // ── Search inside a specific app (validated deep links only) ────────────

    fun searchInApp(rawApp: String?, rawQuery: String?): Map<String, Any?> {
        val app = normaliseKey(rawApp) ?: return status("invalid")
        val query = cleanText(rawQuery, 200) ?: return status("invalid")
        val q = Uri.encode(query)
        val label = displayNames[app] ?: app

        val attempts: List<Intent> = when (app) {
            "youtube" -> listOf(
                Intent(Intent.ACTION_SEARCH).setPackage("com.google.android.youtube")
                    .putExtra("query", query),
                Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/results?search_query=$q"))
                    .setPackage("com.google.android.youtube"),
            )
            "spotify" -> listOf(
                Intent(Intent.ACTION_VIEW, Uri.parse("spotify:search:$q")).setPackage("com.spotify.music"),
            )
            "maps" -> listOf(
                Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=$q")).setPackage("com.google.android.apps.maps"),
                Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=$q")),
            )
            "play_store" -> listOf(
                Intent(Intent.ACTION_VIEW, Uri.parse("market://search?q=$q")).setPackage("com.android.vending"),
            )
            "x" -> listOf(
                Intent(Intent.ACTION_VIEW, Uri.parse("https://twitter.com/search?q=$q"))
                    .setPackage("com.twitter.android"),
            )
            else -> return status("unsupported")
        }
        for (intent in attempts) {
            if (start(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))) {
                return mapOf("status" to "success", "label" to label)
            }
        }
        return mapOf("status" to "not_found", "label" to label)
    }

    // ── Phone ───────────────────────────────────────────────────────────────

    /** Opens the dialer pre-filled. The user still presses Call. */
    fun dial(rawNumber: String?): Map<String, Any?> {
        val number = sanitisePhone(rawNumber) ?: return status("invalid")
        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(number)))
        return if (start(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))) {
            mapOf("status" to "success", "number" to number)
        } else {
            status("not_found")
        }
    }

    /**
     * Searches the device contacts (READ_CONTACTS must already be granted).
     * Runs on the phone only; at most 8 matches are returned to Dart.
     */
    fun searchContacts(rawQuery: String?): Map<String, Any?> {
        val query = cleanText(rawQuery, 60) ?: return status("invalid")
        val escaped = query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
            ContactsContract.CommonDataKinds.Phone.TYPE,
            ContactsContract.CommonDataKinds.Phone.LABEL,
        )
        val selection = "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ? ESCAPE '\\'"
        val matches = ArrayList<Map<String, Any?>>()
        val seenNumbers = HashSet<String>()
        try {
            activity.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                projection,
                selection,
                arrayOf("%$escaped%"),
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC"
            )?.use { c ->
                val iName = c.getColumnIndex(projection[0])
                val iNumber = c.getColumnIndex(projection[1])
                val iType = c.getColumnIndex(projection[2])
                val iLabel = c.getColumnIndex(projection[3])
                while (c.moveToNext() && matches.size < 25) {
                    val name: String = (if (iName >= 0) c.getString(iName) else null)
                        ?.takeIf { it.isNotBlank() } ?: continue
                    val number: String = (if (iNumber >= 0) c.getString(iNumber) else null)
                        ?.takeIf { it.isNotBlank() } ?: continue
                    val key = number.filter { it.isDigit() || it == '+' }
                    if (key.isEmpty() || !seenNumbers.add(key)) continue
                    val type = if (iType >= 0) c.getInt(iType) else 0
                    val label = if (iLabel >= 0) c.getString(iLabel) else null
                    val typeLabel = ContactsContract.CommonDataKinds.Phone
                        .getTypeLabel(activity.resources, type, label).toString()
                    matches.add(mapOf("name" to name, "number" to number, "type" to typeLabel))
                }
            }
        } catch (e: SecurityException) {
            return status("permission_required")
        } catch (e: Exception) {
            return status("error")
        }

        val lower = query.lowercase(Locale.ROOT)
        val ranked = matches.sortedBy {
            val n = (it["name"] as String).lowercase(Locale.ROOT)
            when {
                n == lower -> 0
                n.startsWith(lower) -> 1
                else -> 2
            }
        }.take(8)
        return mapOf("status" to "success", "matches" to ranked)
    }

    // ── Settings screens (opening a screen never changes a setting) ─────────

    fun openSettings(rawTarget: String?): Map<String, Any?> {
        val target = normaliseKey(rawTarget) ?: "general"
        val pkgUri = Uri.fromParts("package", activity.packageName, null)
        val intent: Intent? = when (target) {
            "wifi" -> Intent(Settings.ACTION_WIFI_SETTINGS)
            "bluetooth" -> Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            "display" -> Intent(Settings.ACTION_DISPLAY_SETTINGS)
            "sound" -> Intent(Settings.ACTION_SOUND_SETTINGS)
            "location" -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            "battery" -> Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
            "airplane" -> Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS)
            "language" -> Intent(Settings.ACTION_LOCALE_SETTINGS)
            "storage" -> Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS)
            "security" -> Intent(Settings.ACTION_SECURITY_SETTINGS)
            "date" -> Intent(Settings.ACTION_DATE_SETTINGS)
            "nfc" -> Intent(Settings.ACTION_NFC_SETTINGS)
            "default_apps" -> Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
            "assistant" -> Intent(Settings.ACTION_VOICE_INPUT_SETTINGS)
            "data" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                Intent(Settings.ACTION_DATA_USAGE_SETTINGS)
            } else {
                Intent(Settings.ACTION_WIRELESS_SETTINGS)
            }
            "app" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkgUri)
            "notifications" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkgUri)
            }
            "general" -> Intent(Settings.ACTION_SETTINGS)
            else -> null
        }
        if (intent != null && start(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))) {
            return mapOf("status" to "success", "opened" to target)
        }
        // Device doesn't expose that screen — fall back to the main Settings app.
        if (start(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))) {
            return mapOf("status" to "success", "opened" to "general")
        }
        return status("not_found")
    }

    fun openAppDetailsSettings(): Boolean {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", activity.packageName, null)
        )
        return start(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    // ── Maps ────────────────────────────────────────────────────────────────

    fun navigate(rawDestination: String?): Map<String, Any?> {
        val destination = cleanText(rawDestination, 200) ?: return status("invalid")
        val q = Uri.encode(destination)
        val google = Intent(Intent.ACTION_VIEW, Uri.parse("google.navigation:q=$q"))
            .setPackage("com.google.android.apps.maps")
        if (start(google.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))) return status("success")
        val anyMaps = Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=$q"))
        if (start(anyMaps.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))) return status("success")
        return status("not_found")
    }

    // ── Open a web page inside NOVA X (used by the floating assistant) ─────

    fun openInNova(rawUrl: String?): Map<String, Any?> {
        val url = rawUrl?.trim().orEmpty()
        val uri = try { Uri.parse(url) } catch (e: Exception) { null }
        val scheme = uri?.scheme?.lowercase(Locale.ROOT)
        if (uri == null || (scheme != "https" && scheme != "http") || uri.host.isNullOrBlank() ||
            url.length > 2048) {
            return status("invalid")
        }
        val intent = Intent(activity, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(uri)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return if (start(intent)) status("success") else status("error")
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    private fun start(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        false
    }

    private fun status(value: String): Map<String, Any?> = mapOf("status" to value)

    private fun normaliseKey(raw: String?): String? {
        val k = raw?.trim()?.lowercase(Locale.ROOT)?.replace(' ', '_').orEmpty()
        if (k.isEmpty() || k.length > 40) return null
        if (!k.all { it.isLetterOrDigit() || it == '_' || it == '.' || it == '-' || it == '&' || it == '\'' }) {
            return null
        }
        return k
    }

    private fun cleanText(raw: String?, maxLength: Int): String? {
        val t = raw?.trim().orEmpty()
        if (t.isEmpty() || t.length > maxLength) return null
        if (t.any { it.isISOControl() }) return null
        return t
    }

    private fun sanitisePhone(raw: String?): String? {
        val kept = raw?.filter { it.isDigit() || it == '+' || it == '*' || it == '#' }.orEmpty()
        val digits = kept.count { it.isDigit() }
        if (digits < 3 || kept.length > 20) return null
        if (kept.indexOf('+') > 0) return null
        return kept
    }
}
