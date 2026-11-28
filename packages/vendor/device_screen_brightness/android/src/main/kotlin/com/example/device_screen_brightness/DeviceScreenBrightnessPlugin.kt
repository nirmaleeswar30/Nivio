package com.example.device_screen_brightness

import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/** Android channel implementation for app-window and system brightness. */
class DeviceScreenBrightnessPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var resolver: ContentResolver? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var observer: ContentObserver? = null
    private val handler = Handler(Looper.getMainLooper())
    private val emittedValues = mutableMapOf<String, Int>()

    private val appPoller = object : Runnable {
        override fun run() {
            emitMode(MODE_APP)
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        resolver = binding.applicationContext.contentResolver
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getBrightness" -> result.success(valueResult(readBrightness(requiredMode(call))))
                "setBrightness" -> result.success(setBrightness(call))
                "adjustBrightness" -> result.success(adjustBrightness(call))
                "hasPermission" -> result.success(canWriteSystemSettings())
                "requestPermission" -> {
                    requestWriteSettingsPermission()
                    result.success(null)
                }
                "getCapabilities" -> result.success(capabilities())
                else -> result.notImplemented()
            }
        } catch (error: SecurityException) {
            result.error(
                "permission_denied",
                error.message ?: "Android denied the brightness operation.",
                errorDetails(call.method, error),
            )
        } catch (error: IllegalArgumentException) {
            result.error(
                "invalid_brightness_value",
                error.message,
                errorDetails(call.method, error),
            )
        } catch (error: IllegalStateException) {
            result.error(
                "backend_not_available",
                error.message,
                errorDetails(call.method, error),
            )
        } catch (error: Throwable) {
            result.error(
                "native_backend_failure",
                error.message ?: "Android brightness operation failed.",
                errorDetails(call.method, error),
            )
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        emittedValues.clear()
        val contentResolver = resolver
        if (contentResolver == null) {
            events.error(
                "plugin_detached",
                "The Android plugin is not attached to a Flutter engine.",
                mapOf("platform" to "android"),
            )
            return
        }
        observer = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) {
                emitMode(MODE_SYSTEM)
            }
        }.also {
            contentResolver.registerContentObserver(
                Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS),
                false,
                it,
            )
        }
        emitMode(MODE_SYSTEM)
        emitMode(MODE_APP)
        handler.postDelayed(appPoller, POLL_INTERVAL_MS)
    }

    override fun onCancel(arguments: Any?) {
        stopObservation()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        emitMode(MODE_APP)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        emitMode(MODE_APP)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopObservation()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        resolver = null
        applicationContext = null
    }

    private fun requiredMode(call: MethodCall): String = when (call.argument<String>("mode")) {
        MODE_APP -> MODE_APP
        MODE_SYSTEM -> MODE_SYSTEM
        else -> throw IllegalArgumentException("Invalid brightness mode.")
    }

    private fun readBrightness(mode: String): Int {
        if (mode == MODE_APP) {
            val currentActivity = activity
                ?: throw IllegalStateException("No foreground Android Activity is available.")
            val brightness = currentActivity.window.attributes.screenBrightness
            if (brightness >= 0f) return (brightness * 100f).roundToInt().coerceIn(0, 100)
        }
        val contentResolver = resolver
            ?: throw IllegalStateException("The Android plugin is detached.")
        val nativeValue = Settings.System.getInt(
            contentResolver,
            Settings.System.SCREEN_BRIGHTNESS,
        )
        return (nativeValue / 255f * 100f).roundToInt().coerceIn(0, 100)
    }

    private fun setBrightness(call: MethodCall): Map<String, Any> {
        val mode = requiredMode(call)
        val value = call.argument<Int>("value")
            ?: throw IllegalArgumentException("Missing brightness value.")
        require(value in 0..100) { "Brightness must be between 0 and 100." }

        if (mode == MODE_APP) {
            val currentActivity = activity
                ?: throw IllegalStateException("No foreground Android Activity is available.")
            val attributes = currentActivity.window.attributes
            attributes.screenBrightness = value / 100f
            currentActivity.window.attributes = attributes
        } else {
            if (!canWriteSystemSettings()) {
                throw SecurityException("WRITE_SETTINGS permission is not granted.")
            }
            val contentResolver = resolver
                ?: throw IllegalStateException("The Android plugin is detached.")
            val written = Settings.System.putInt(
                contentResolver,
                Settings.System.SCREEN_BRIGHTNESS,
                (value / 100f * 255f).roundToInt(),
            )
            if (!written) throw IllegalStateException("Settings.System rejected the write.")
        }
        val applied = readBrightness(mode)
        emitMode(mode)
        return valueResult(applied)
    }

    private fun adjustBrightness(call: MethodCall): Map<String, Any> {
        val mode = requiredMode(call)
        val current = readBrightness(mode)
        val next = when (call.argument<String>("direction")) {
            "increase" -> (current + STEP).coerceAtMost(100)
            "decrease" -> (current - STEP).coerceAtLeast(0)
            else -> throw IllegalArgumentException("Invalid adjustment direction.")
        }
        return setBrightnessValue(mode, next)
    }

    private fun setBrightnessValue(mode: String, value: Int): Map<String, Any> {
        if (mode == MODE_APP) {
            val currentActivity = activity
                ?: throw IllegalStateException("No foreground Android Activity is available.")
            val attributes: WindowManager.LayoutParams = currentActivity.window.attributes
            attributes.screenBrightness = value / 100f
            currentActivity.window.attributes = attributes
        } else {
            if (!canWriteSystemSettings()) {
                throw SecurityException("WRITE_SETTINGS permission is not granted.")
            }
            val contentResolver = resolver
                ?: throw IllegalStateException("The Android plugin is detached.")
            if (!Settings.System.putInt(
                    contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS,
                    (value / 100f * 255f).roundToInt(),
                )
            ) {
                throw IllegalStateException("Settings.System rejected the write.")
            }
        }
        val applied = readBrightness(mode)
        emitMode(mode)
        return valueResult(applied)
    }

    private fun canWriteSystemSettings(): Boolean {
        val context = applicationContext
            ?: throw IllegalStateException("The Android plugin is detached.")
        return Settings.System.canWrite(context)
    }

    private fun requestWriteSettingsPermission() {
        val context = activity ?: applicationContext
            ?: throw IllegalStateException("The Android plugin is detached.")
        val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
            if (context !is Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    private fun capabilities(): Map<String, Any> = mapOf(
        "canRead" to true,
        "canWrite" to true,
        "canObserve" to true,
        "writeSupport" to "supported",
        "supportedModes" to listOf(MODE_APP, MODE_SYSTEM),
        "requiresWriteSettingsPermission" to true,
        "backend" to "android-window-settings",
    )

    private fun valueResult(value: Int): Map<String, Any> = mapOf("value" to value)

    private fun emitMode(mode: String) {
        val sink = eventSink ?: return
        try {
            val value = readBrightness(mode)
            if (emittedValues[mode] != value) {
                emittedValues[mode] = value
                sink.success(mapOf("value" to value, "mode" to mode))
            }
        } catch (error: Throwable) {
            if (mode == MODE_APP && activity == null) return
            sink.error(
                "brightness_observation_failure",
                error.message ?: "Unable to observe Android brightness.",
                errorDetails("streamBrightness", error),
            )
        }
    }

    private fun stopObservation() {
        handler.removeCallbacks(appPoller)
        observer?.let { resolver?.unregisterContentObserver(it) }
        observer = null
        eventSink = null
        emittedValues.clear()
    }

    private fun errorDetails(operation: String, error: Throwable): Map<String, Any> = mapOf(
        "platform" to "android",
        "operation" to operation,
        "nativeType" to error.javaClass.name,
    )

    private companion object {
        const val METHOD_CHANNEL = "dev.arcas.device_screen_brightness/methods"
        const val EVENT_CHANNEL = "dev.arcas.device_screen_brightness/events"
        const val MODE_APP = "app"
        const val MODE_SYSTEM = "system"
        const val STEP = 5
        const val POLL_INTERVAL_MS = 250L
    }
}
