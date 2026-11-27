import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/core/mpv_android_setup.dart';
import 'package:nivio/services/ios_video_output.dart';
import 'package:nivio/services/trailer_stream_resolver.dart';
import 'package:nivio/widgets/ios_video_surface.dart';

/// A bare trailer preview (no controls) for the desktop hover card, played in
/// mpv. Full trailers open in the regular player (PlayerScreen with
/// trailerSite/trailerKey).
class TrailerVideoPlayer extends StatefulWidget {
  const TrailerVideoPlayer({
    super.key,
    required this.site,
    required this.videoKey,
    this.autoPlay = true,
    this.muted = false,
    this.loop = false,
    this.fit = BoxFit.contain,
    this.maxHeight = 1080,
    this.onPlaying,
    this.onError,
  });

  /// Where the trailer is hosted, as TMDB names it ("YouTube", "Vimeo", …).
  final String site;

  /// The video's id on that site.
  final String videoKey;

  final bool autoPlay;
  final bool muted;
  final bool loop;
  final BoxFit fit;

  /// Highest resolution to pick when the site offers several.
  final int maxHeight;

  /// The first frame is on screen and playback is moving.
  final VoidCallback? onPlaying;

  /// The trailer can't play.
  final ValueChanged<String>? onError;

  @override
  State<TrailerVideoPlayer> createState() => TrailerVideoPlayerState();
}

class TrailerVideoPlayerState extends State<TrailerVideoPlayer> {
  static const Duration _startTimeout = Duration(seconds: 30);

  late final Player _player = Player(
    configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error),
  );
  late final VideoController _controller = VideoController(
    _player,
    configuration: Platform.isIOS
        ? IosVideoOutput.controllerConfiguration
        : VideoControllerConfiguration(enableHardwareAcceleration: !Platform.isLinux),
  );
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _startTimer;
  bool _disposed = false;
  bool _started = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    _startTimer = Timer(_startTimeout, () => _fail('The trailer took too long to start.'));
    try {
      final stream = await TrailerStreamResolver.resolve(
        widget.site,
        widget.videoKey,
        maxHeight: widget.maxHeight,
      );
      if (_disposed) return;

      _subscriptions
        ..add(_player.stream.position.listen((position) {
          if (!_started && position > Duration.zero) {
            _started = true;
            _startTimer?.cancel();
            widget.onPlaying?.call();
          }
        }))
        ..add(_player.stream.error.listen((message) {
          appDebugLog('🎬 Trailer mpv: $message');
          if (!_started) _fail('Couldn\'t play this trailer.');
        }));

      await IosVideoOutput.instance.prepare(_player);
      if (_disposed) return;
      final native = _player.platform;
      if (native is NativePlayer) {
        // Streams come from TrailerStreamResolver, never from yt-dlp.
        await native.setProperty('ytdl', 'no');
        final caBundle = mpvCaBundlePath;
        if (caBundle != null) {
          await native.setProperty('tls-ca-file', caBundle);
          await native.setProperty('tls-verify', 'yes');
        }
        await native.setProperty('mute', widget.muted ? 'yes' : 'no');
        await native.setProperty('loop-file', widget.loop ? 'inf' : 'no');
        await native.setProperty('sub-visibility', 'no');
        // YouTube refuses URLs fetched with another client's User-Agent.
        final userAgent = stream.userAgent;
        if (userAgent != null) await native.setProperty('user-agent', userAgent);
        final audio = stream.audio;
        if (audio != null) {
          // YouTube serves picture and sound separately above 360p.
          await native.command(['change-list', 'audio-files', 'append', audio.toString()]);
        }
      }
      if (_disposed) return;
      await _player.open(Media(stream.video.toString()), play: widget.autoPlay);
    } on TrailerUnavailableException catch (e) {
      _fail(e.message);
    } catch (e) {
      appDebugLog('🎬 Trailer failed to start: $e');
      _fail('Couldn\'t play this trailer.');
    }
  }

  void _fail(String message) {
    if (_disposed || _failed || _started) return;
    _failed = true;
    _startTimer?.cancel();
    widget.onError?.call(message);
  }

  @override
  void dispose() {
    _disposed = true;
    _startTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> mute() => _setMuted(true);

  Future<void> unMute() => _setMuted(false);

  /// Volume from 0 to 100.
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0, 100).toDouble());

  Future<void> _setMuted(bool muted) async {
    final native = _player.platform;
    if (native is NativePlayer) {
      await native.setProperty('mute', muted ? 'yes' : 'no');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) return IosVideoSurface(player: _player, fit: widget.fit);
    return Video(
      controller: _controller,
      controls: NoVideoControls,
      fit: widget.fit,
      fill: Colors.black,
      wakelock: false,
    );
  }
}
