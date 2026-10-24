package com.tlyfe.nova_x.nova

import android.app.ActivityManager
import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * A ready-to-use Flutter engine for NOVA's floating window.
 *
 * Starting a Flutter engine (Dart VM isolate, plugins, first frame) takes one
 * to two seconds on a mid-range phone, and used to happen every time the user
 * said "Hey NOVA". While "Hey NOVA" is on, the engine for the floating window
 * (Dart entrypoint `novaAssistantMain`) is started in advance and kept, so the
 * window opens almost at once and NOVA starts listening sooner.
 *
 * It is skipped on low-RAM phones, released when "Hey NOVA" is turned off, and
 * NovaAssistActivity falls back to a fresh engine whenever none is ready.
 * The warm engine does nothing until a window attaches: the Dart side only
 * starts listening when the window tells it to (onAssistInvoked).
 */
object NovaAssistEngine {
    const val ID = "nova_assistant_engine"

    @Volatile private var attachedWindows = 0

    fun isWarm(): Boolean = try {
        FlutterEngineCache.getInstance().contains(ID)
    } catch (t: Throwable) {
        false
    }

    /** Main thread only. */
    fun prewarm(context: Context) {
        if (isWarm()) return
        val app = context.applicationContext
        val am = app.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        if (am?.isLowRamDevice == true) return
        try {
            val engine = FlutterEngine(app)
            val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(bundle, "novaAssistantMain"),
            )
            FlutterEngineCache.getInstance().put(ID, engine)
        } catch (t: Throwable) {
            // Not available (e.g. out of memory): the window starts its own engine.
        }
    }

    fun windowAttached() {
        attachedWindows++
    }

    fun windowDetached() {
        if (attachedWindows > 0) attachedWindows--
    }

    /** Frees the engine when no NOVA window uses it (main thread). */
    fun releaseIfIdle() {
        if (attachedWindows > 0) return
        try {
            val cache = FlutterEngineCache.getInstance()
            val engine = cache.get(ID) ?: return
            cache.remove(ID)
            engine.destroy()
        } catch (ignored: Throwable) { }
    }
}
