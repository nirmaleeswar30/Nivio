package com.nirmal.nivio

import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.graphics.Rect
import cl.puntito.simple_pip_mode.PipCallbackHelperActivityWrapper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : PipCallbackHelperActivityWrapper() {
    private val CHANNEL = "com.nivio/gesture_exclusion"
    private val MEDIA_SESSION_CHANNEL = "com.nivio/media_session"
    private val WATCH_PARTY_CHANNEL = "com.nivio/watch_party_keepalive"
    private var methodChannel: MethodChannel? = null
    private var mediaSessionChannel: MethodChannel? = null
    private var mediaSession: MediaSession? = null
    private var lastMetadataKey: String? = null
    private var canEnterPip = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
