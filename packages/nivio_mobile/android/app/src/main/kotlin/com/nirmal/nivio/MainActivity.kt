package com.nirmal.nivio

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.graphics.Rect
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.appcompat.app.AppCompatActivity
import cl.puntito.simple_pip_mode.PipCallbackHelper
import io.flutter.embedding.android.FlutterEngineConfigurator
import io.flutter.embedding.android.FlutterFragment
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.embedding.engine.plugins.util.GeneratedPluginRegister
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AppCompatActivity(), FlutterEngineConfigurator {
    private val flutterFragment: FlutterFragment?
        get() = supportFragmentManager.findFragmentByTag("flutter") as? FlutterFragment
    private val pipCallback = PipCallbackHelper()
    private var pipCallbackReady = false
    private var cloudstreamExtensions: CloudstreamExtensions? = null
    private val CHANNEL = "com.nivio/gesture_exclusion"
    private val MEDIA_SESSION_CHANNEL = "com.nivio/media_session"
    private val WATCH_PARTY_CHANNEL = "com.nivio/watch_party_keepalive"
    private val DEVICE_CHANNEL = "com.nivio/device"
    private var methodChannel: MethodChannel? = null
    private var mediaSessionChannel: MethodChannel? = null
    private var mediaSession: MediaSession? = null
    private val audioManager by lazy { getSystemService(AudioManager::class.java) }
    private val mpvRawAudio by lazy {
        @Suppress("DEPRECATION")
        val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
        info.metaData?.getBoolean("com.nivio.mpvRawAudio") == true
    }
    private var dolbyRouteChannel: EventChannel? = null
    private var dolbyRouteSink: EventChannel.EventSink? = null
    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<AudioDeviceInfo>) = publishDolbyRoute()
        override fun onAudioDevicesRemoved(removed: Array<AudioDeviceInfo>) = publishDolbyRoute()
    }
    private var lastMetadataKey: String? = null
    private var canEnterPip = false

    override fun onCreate(savedInstanceState: Bundle?) {
        setTheme(R.style.NormalTheme)
        super.onCreate(savedInstanceState)
        setContentView(FrameLayout(this).apply { id = R.id.nivio_flutter_host })
        if (flutterFragment == null) {
            val fragment = FlutterFragment.withNewEngine()
                .apply {
                    intent.getStringExtra("route")?.let { initialRoute(it) }
                    intent.getStringArrayListExtra("dart_entrypoint_args")?.let { dartEntrypointArgs(it) }
                    if (intent.action == Intent.ACTION_RUN &&
                        applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
                    ) {
                        intent.dataString?.let { appBundlePath(it) }
                    }
                }
                .flutterShellArgs(FlutterShellArgs.fromIntent(intent))
                .handleDeeplinking(false)
                .renderMode(RenderMode.surface)
                .transparencyMode(TransparencyMode.opaque)
                .shouldDelayFirstAndroidViewDraw(true)
                .shouldAutomaticallyHandleOnBackPressed(true)
                .build<FlutterFragment>()
            supportFragmentManager.beginTransaction()
                .add(R.id.nivio_flutter_host, fragment, "flutter")
                .commit()
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        flutterFragment?.onPostResume()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        flutterFragment?.onNewIntent(intent)
    }

    @Deprecated("Needed by Flutter plugins using the activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        flutterFragment?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        flutterFragment?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        flutterFragment?.onUserLeaveHint()
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        flutterFragment?.onTrimMemory(level)
    }

    override fun onPictureInPictureModeChanged(active: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(active, newConfig)
        if (pipCallbackReady) pipCallback.onPictureInPictureModeChanged(active)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegister.registerGeneratedPlugins(flutterEngine)
        pipCallback.configureFlutterEngine(flutterEngine)
        pipCallbackReady = true
        cloudstreamExtensions = CloudstreamExtensions(this, flutterEngine.dartExecutor.binaryMessenger)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "excludeBottomGestures" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val height = call.argument<Int>("height") ?: 200
                        val decorView = window.decorView
                        decorView.post {
                            val rect = Rect(
                                0,
                                decorView.height - height,
                                decorView.width,
                                decorView.height
                            )
                            decorView.systemGestureExclusionRects = listOf(rect)
                        }
                    }
                    result.success(true)
                }
                "clearGestureExclusion" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        window.decorView.systemGestureExclusionRects = emptyList()
                    }
                    result.success(true)
                }
                "setCanEnterPip" -> {
                    canEnterPip = call.argument<Boolean>("value") ?: false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Media session for Bluetooth / wired headset buttons and system media
        // controls. Driven by MediaSessionService on the Dart side.
        mediaSessionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_SESSION_CHANNEL)
        mediaSessionChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    updateMediaSession(
                        title = call.argument<String>("title") ?: "",
                        subtitle = call.argument<String>("subtitle") ?: "",
                        artUrl = call.argument<String>("artUrl") ?: "",
                        durationMs = call.argument<Number>("durationMs")?.toLong() ?: 0L,
                        positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L,
                        playing = call.argument<Boolean>("playing") ?: false
                    )
                    result.success(null)
                }
                "clear" -> {
                    releaseMediaSession()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Lets Dart pick the TV (desktop-style, D-pad driven) layout.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> result.success(isTelevision())
                    "hdrInfo" -> result.success(hdrInfo())
                    "dolbyAudioRouteSupported" -> result.success(dolbyAudioRouteSupported())
                    "mpvRawAudio" -> result.success(mpvRawAudio)
                    // The player's brightness gesture overrides the window's
                    // brightness; this hands it back to the system setting.
                    "resetWindowBrightness" -> {
                        window.attributes = window.attributes.apply {
                            screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        dolbyRouteChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.nivio/dolby_audio_route")
        dolbyRouteChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                stopDolbyRouteUpdates()
                dolbyRouteSink = events
                audioManager?.registerAudioDeviceCallback(audioDeviceCallback, null)
                publishDolbyRoute()
            }

            override fun onCancel(arguments: Any?) = stopDolbyRouteUpdates()
        })

        // SurfaceView for HDR video output (see HdrSurfaceView.kt).
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "nivio/hdr_surface",
            HdrSurfaceViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )

        // Foreground service that keeps a watch party connected in the
        // background. Driven by WatchPartyKeepAlive on the Dart side.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WATCH_PARTY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        try {
                            WatchPartyKeepAliveService.start(
                                applicationContext,
                                call.argument<String>("text") ?: "Watch party in progress"
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            // e.g. ForegroundServiceStartNotAllowedException
                            // when asked while the app is in the background.
                            result.success(false)
                        }
                    }
                    "stop" -> {
                        WatchPartyKeepAliveService.stop(applicationContext)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // The player locks phones to landscape and back to portrait on exit; on a
    // TV a portrait lock squeezes the whole app into a letterboxed column, so
    // orientation requests are ignored there (TVs are always landscape).
    override fun setRequestedOrientation(requestedOrientation: Int) {
        if (isTelevision()) return
        super.setRequestedOrientation(requestedOrientation)
    }

    /** Whether this screen can show HDR, which formats, and its peak brightness. */
    private fun hdrInfo(): Map<String, Any> {
        val info = HashMap<String, Any>()
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay
        val caps = display?.hdrCapabilities
        val types = caps?.supportedHdrTypes?.map {
            when (it) {
                android.view.Display.HdrCapabilities.HDR_TYPE_HDR10 -> "hdr10"
                android.view.Display.HdrCapabilities.HDR_TYPE_HLG -> "hlg"
                android.view.Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> "dolbyVision"
                android.view.Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS -> "hdr10plus"
                else -> "other"
            }
        } ?: emptyList()
        info["types"] = types
        info["isHdr"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            resources.configuration.isScreenHdr
        } else {
            types.isNotEmpty()
        }
        caps?.let {
            info["maxLuminance"] = it.desiredMaxLuminance.toDouble()
            info["minLuminance"] = it.desiredMinLuminance.toDouble()
        }
        return info
    }

    @Suppress("DEPRECATION")
    private fun dolbyAudioRouteSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
            .build()

        // Match the shipped AudioTrack driver, which accepts raw E-AC-3 or
        // the stereo IEC 61937 carrier. A JOC-only profile is insufficient
        // because the driver opens the raw track with ENCODING_E_AC3.
        fun supports(encoding: Int, channels: Int, rate: Int): Boolean {
            val format = AudioFormat.Builder()
                .setEncoding(encoding)
                .setChannelMask(channels)
                .setSampleRate(rate)
                .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val direct = AudioManager.getDirectPlaybackSupport(format, attributes)
                return (direct and AudioManager.DIRECT_PLAYBACK_BITSTREAM_SUPPORTED) != 0
            }
            // Android 10–12 can include connected outputs beyond the active route.
            return AudioTrack.isDirectPlaybackSupported(format, attributes)
        }

        return runCatching {
            listOf(48000, 44100, 32000).any { rate ->
                (mpvRawAudio && (
                    supports(AudioFormat.ENCODING_E_AC3, AudioFormat.CHANNEL_OUT_5POINT1, rate) ||
                    supports(AudioFormat.ENCODING_E_AC3, AudioFormat.CHANNEL_OUT_STEREO, rate)
                )) || supports(AudioFormat.ENCODING_IEC61937, AudioFormat.CHANNEL_OUT_STEREO, rate * 4)
            }
        }.getOrDefault(false)
    }

    private fun publishDolbyRoute() {
        dolbyRouteSink?.success(dolbyAudioRouteSupported())
    }

    private fun stopDolbyRouteUpdates() {
        if (dolbyRouteSink == null) return
        dolbyRouteSink = null
        audioManager?.unregisterAudioDeviceCallback(audioDeviceCallback)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) publishDolbyRoute()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pipCallbackReady = false
        cloudstreamExtensions?.close()
        cloudstreamExtensions = null
        stopDolbyRouteUpdates()
        dolbyRouteChannel?.setStreamHandler(null)
        dolbyRouteChannel = null
    }

    private fun isTelevision(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true
        return packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    private fun sendMediaCommand(command: String, positionMs: Long? = null) {
        val args = HashMap<String, Any>()
        args["command"] = command
        if (positionMs != null) args["positionMs"] = positionMs
        mediaSessionChannel?.invokeMethod("onCommand", args)
    }

    private fun ensureMediaSession(): MediaSession {
        mediaSession?.let { return it }
        val session = MediaSession(this, "NivioPlayer")
        session.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = sendMediaCommand("play")
            override fun onPause() = sendMediaCommand("pause")
            override fun onStop() = sendMediaCommand("stop")
            override fun onSkipToNext() = sendMediaCommand("next")
            override fun onSkipToPrevious() = sendMediaCommand("previous")
            override fun onFastForward() = sendMediaCommand("fastForward")
            override fun onRewind() = sendMediaCommand("rewind")
            override fun onSeekTo(pos: Long) = sendMediaCommand("seek", pos)
        })
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            // Required before Android 8; the default (and deprecated) afterwards.
            @Suppress("DEPRECATION")
            session.setFlags(
                MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
        }
        mediaSession = session
        return session
    }

    private fun updateMediaSession(
        title: String,
        subtitle: String,
        artUrl: String,
        durationMs: Long,
        positionMs: Long,
        playing: Boolean
    ) {
        val session = ensureMediaSession()

        val metadataKey = "$title|$subtitle|$artUrl|$durationMs"
        if (metadataKey != lastMetadataKey) {
            lastMetadataKey = metadataKey
            val metadata = MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, subtitle)
                .putString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE, subtitle)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs)
            if (artUrl.isNotEmpty()) {
                metadata.putString(MediaMetadata.METADATA_KEY_ART_URI, artUrl)
                metadata.putString(MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI, artUrl)
            }
            session.setMetadata(metadata.build())
        }

        // PLAY_PAUSE lets the default onMediaButtonEvent turn a single headset
        // press into onPlay/onPause based on the current state.
        val actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_STOP or
            PlaybackState.ACTION_SEEK_TO or
            PlaybackState.ACTION_SKIP_TO_NEXT or
            PlaybackState.ACTION_SKIP_TO_PREVIOUS or
            PlaybackState.ACTION_FAST_FORWARD or
            PlaybackState.ACTION_REWIND
        val state = PlaybackState.Builder()
            .setActions(actions)
            .setState(
                if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                positionMs,
                if (playing) 1f else 0f,
                SystemClock.elapsedRealtime()
            )
            .build()
        session.setPlaybackState(state)
        if (!session.isActive) session.isActive = true
    }

    private fun releaseMediaSession() {
        mediaSession?.let {
            it.isActive = false
            it.release()
        }
        mediaSession = null
        lastMetadataKey = null
    }

    override fun onDestroy() {
        releaseMediaSession()
        // The Flutter engine (and the party connection in it) goes away with
        // this activity, so there is nothing left for the service to keep alive.
        WatchPartyKeepAliveService.stop(applicationContext)
        super.onDestroy()
    }
}
