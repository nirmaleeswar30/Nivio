import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

import '../../shared/models/stream_result.dart' show StreamSegment;
import 'models/playback_request.dart';
import 'models/playback_state.dart';
import 'playback_engine.dart';
import 'services/playback_runtime_diagnostics.dart';

class MediaKitPlaybackEngine implements PlaybackEngine {
  MediaKitPlaybackEngine({Player? player})
    : _player = player ?? _createPlayer() {
    PlaybackRuntimeDiagnostics.mediaKitEnginesCreated++;
    _mpvLog(
      'MediaKitPlaybackEngine#$debugInstanceId created '
      '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
    );
    videoController = VideoController(_player);
    PlaybackRuntimeDiagnostics.videoControllersCreated++;
    _mpvLog(
      'NativeVideoController Created active=${PlaybackRuntimeDiagnostics.textureCount}',
    );
    _mpvLog(
      'VideoOutput Created active=${PlaybackRuntimeDiagnostics.textureCount}',
    );
    _listenToPlayer();
  }

  static int _nextInstanceId = 0;

  final int debugInstanceId = ++_nextInstanceId;
  final Player _player;
  late final VideoController videoController;
  final ValueNotifier<PlaybackState> _state = ValueNotifier(
    const PlaybackState(),
  );
  final List<StreamSubscription<Object?>> _subscriptions = [];
  PlaybackRequest? _request;
  bool _disposed = false;
  Stopwatch? _loadClock;
  bool _firstFrameLogged = false;
  String? _pendingAudioTrackId;
  String? _pendingSubtitleTrackId;
  String? _pendingSubtitleExternalUrl;
  Duration _subtitleDelay = Duration.zero;
  SubtitleStyle _subtitleStyle = const SubtitleStyle();
  bool _debandingEnabled = false;
  bool _applyingPendingTracks = false;
  DateTime? _lastPositionNotificationAt;
  DateTime? _lastBufferNotificationAt;
  Duration _lastPublishedPosition = Duration.zero;
  Duration _lastPublishedBuffer = Duration.zero;
  int? _activeSegmentIndex;
  Duration _activeSegmentStart = Duration.zero;
  bool _usingSegmentPlaylist = false;
  Duration _segmentPlaylistBaseStart = Duration.zero;

  static const Duration _positionNotificationInterval = Duration(
    milliseconds: 500,
  );
  static const Duration _bufferNotificationInterval = Duration(seconds: 1);

  @override
  ValueListenable<PlaybackState> get state => _state;
  bool get debugDisposed => _disposed;

  static Player _createPlayer() {
    MediaKit.ensureInitialized();
    PlaybackRuntimeDiagnostics.mediaPlayersCreated++;
    PlaybackRuntimeDiagnostics.mpvLog(
      'Player Created active=${PlaybackRuntimeDiagnostics.mediaPlayersAlive}',
    );
    PlaybackRuntimeDiagnostics.snapshot('after media_kit player create');
    return Player(
      configuration: PlayerConfiguration(
        logLevel: PlaybackRuntimeDiagnostics.enabled
            ? MPVLogLevel.v
            : MPVLogLevel.error,
        bufferSize: 64 * 1024 * 1024,
        protocolWhitelist: const [
          'udp',
          'rtp',
          'tcp',
          'tls',
          'data',
          'file',
          'http',
          'https',
          'crypto',
          'httpproxy',
        ],
      ),
    );
  }

  void _listenToPlayer() {
    _subscriptions.addAll([
      _player.stream.playing.listen((playing) {
        _mpvLog('Lifecycle: ${playing ? 'Playing' : 'Paused'}');
        _update(
          isPlaying: playing,
          status: _statusAfterPlayingChanged(playing),
        );
      }),
      _player.stream.position.listen((position) {
        final effectivePosition = _effectivePosition(position);
        if (!_shouldPublishPosition(effectivePosition)) return;
        if (effectivePosition.inSeconds > 0 &&
            effectivePosition.inSeconds % 10 == 0) {
          _mpvLog('Position: ${effectivePosition.inSeconds}s');
        }
        _update(position: effectivePosition);
      }),
      _player.stream.duration.listen((duration) {
        final effectiveDuration = _effectiveDuration(duration);
        _mpvLog(
          'Duration: ${duration.inMilliseconds}ms'
          '${effectiveDuration == duration ? '' : ' -> ${effectiveDuration.inMilliseconds}ms'}',
        );
        _update(duration: effectiveDuration);
      }),
      _player.stream.buffer.listen((buffer) {
        final effectiveBuffer = _effectivePosition(buffer);
        if (!_shouldPublishBuffer(effectiveBuffer)) return;
        _mpvLog(
          'Buffer: ${buffer.inMilliseconds}ms'
          '${effectiveBuffer == buffer ? '' : ' -> ${effectiveBuffer.inMilliseconds}ms'}',
        );
        _update(bufferedPosition: effectiveBuffer);
      }),
      _player.stream.volume.listen((volume) {
        final normalized = (volume / 100).clamp(0.0, 2.0);
        _update(volume: normalized, isMuted: normalized == 0);
      }),
      _player.stream.tracks.listen((tracks) {
        _mpvLog(
          'Tracks: video=${tracks.video.length} audio=${tracks.audio.length} '
          'subtitle=${tracks.subtitle.length}',
        );
        _update(
          audioTracks: tracks.audio.map(_audioOption).toList(),
          subtitleTracks: tracks.subtitle.map(_subtitleOption).toList(),
        );
        unawaited(_applyPendingTrackSelections());
      }),
      _player.stream.track.listen((track) {
        _mpvLog(
          'Selected tracks: video=${track.video.id} audio=${track.audio.id} '
          'subtitle=${track.subtitle.id}',
        );
        _update(
          selectedAudioTrackId: track.audio.id,
          selectedSubtitleTrackId: track.subtitle.id,
        );
      }),
      _player.stream.buffering.listen((buffering) {
        _mpvLog('Lifecycle: ${buffering ? 'Buffering' : 'Ready'}');
        final currentStatus = _state.value.status;
        if (currentStatus == PlaybackStatus.error ||
            currentStatus == PlaybackStatus.completed ||
            currentStatus == PlaybackStatus.stopped) {
          return;
        }
        _update(
          status: buffering
              ? PlaybackStatus.buffering
              : currentStatus == PlaybackStatus.buffering
              ? PlaybackStatus.ready
              : currentStatus,
        );
      }),
      _player.stream.completed.listen((completed) {
        if (completed) {
          if (_shouldIgnoreCompletedEvent()) {
            _mpvLog('Lifecycle: Ignored premature ended event');
            return;
          }
          _mpvLog('Lifecycle: Ended');
          _update(status: PlaybackStatus.completed, isPlaying: false);
        }
      }),
      _player.stream.error.listen((message) {
        _mpvLog('Lifecycle: Error $message');
        if (_isRecoverableSubtitleError(message)) {
          _mpvLog('Subtitle load failed without stopping playback: $message');
          _pendingSubtitleTrackId = null;
          _pendingSubtitleExternalUrl = null;
          unawaited(_disableFailedSubtitle());
          _update(selectedSubtitleTrackId: 'no', clearError: true);
          return;
        }
        _update(
          status: PlaybackStatus.error,
          isPlaying: false,
          errorMessage: message,
        );
      }),
      _player.stream.videoParams.listen((params) {
        _mpvLog('Video params: $params');
      }),
      _player.stream.log.listen((event) {
        final text = event.text.trim();
        if (text.isEmpty) return;
        _trackSegmentFromLog(text);
        final lower = text.toLowerCase();
        if (!_firstFrameLogged &&
            lower.contains('first video frame after restart shown')) {
          _firstFrameLogged = true;
          PlaybackRuntimeDiagnostics.mpvLog(
            'First rendered frame',
            clock: _loadClock,
          );
        }
        if (lower.contains('http') ||
            lower.contains('hls') ||
            lower.contains('m3u8') ||
            lower.contains('.ts') ||
            lower.contains('.m4s') ||
            lower.contains('error') ||
            lower.contains('failed') ||
            lower.contains('cache') ||
            lower.contains('decoder') ||
            lower.contains('demux') ||
            lower.contains('video')) {
          _mpvLog('[${event.level}/${event.prefix}] $text');
        }
      }),
    ]);
  }

  PlaybackStatus _statusAfterPlayingChanged(bool playing) {
    return switch (_state.value.status) {
      PlaybackStatus.loading =>
        playing ? PlaybackStatus.ready : PlaybackStatus.loading,
      PlaybackStatus.buffering => PlaybackStatus.buffering,
      PlaybackStatus.error => PlaybackStatus.error,
      PlaybackStatus.completed => PlaybackStatus.completed,
      PlaybackStatus.stopped => PlaybackStatus.stopped,
      _ => PlaybackStatus.ready,
    };
  }

  Duration _effectiveDuration(Duration duration) {
    final override = _request?.streamResult?.duration;
    if (override == null || override <= Duration.zero) return duration;
    if (duration <= Duration.zero) return override;
    if (duration + const Duration(seconds: 30) < override) return override;
    return duration;
  }

  Duration _effectivePosition(Duration position) {
    final segments = _request?.streamResult?.segments ?? const [];
    if (_usingSegmentPlaylist) {
      final mapped = _segmentPlaylistBaseStart + position;
      final duration = _request?.streamResult?.duration;
      if (duration != null && mapped > duration) return duration;
      return mapped;
    }
    final index = _activeSegmentIndex;
    if (segments.isEmpty || index == null || index >= segments.length) {
      return position;
    }
    final segment = segments[index];
    final mapped = segment.start + position;
    final duration = _request?.streamResult?.duration;
    if (duration != null && mapped > duration) return duration;
    return mapped;
  }

  void _trackSegmentFromLog(String text) {
    final marker = 'Playing: ';
    final markerIndex = text.indexOf(marker);
    if (markerIndex < 0) return;
    final url = text.substring(markerIndex + marker.length).trim();
    if (url.isEmpty) return;
    final segments = _request?.streamResult?.segments ?? const [];
    if (segments.isEmpty) return;
    final normalized = _normalizedSegmentUrl(url);
    for (var i = 0; i < segments.length; i += 1) {
      if (_normalizedSegmentUrl(segments[i].url) != normalized) continue;
      if (_usingSegmentPlaylist) {
        if (_activeSegmentIndex != i) {
          _activeSegmentIndex = i;
          _activeSegmentStart = segments[i].start;
          _mpvLog(
            'Castle playlist segment index=$i start=${_activeSegmentStart.inMilliseconds}ms',
          );
        }
        return;
      }
      if (_activeSegmentIndex != i) {
        _activeSegmentIndex = i;
        _activeSegmentStart = segments[i].start;
        _mpvLog(
          'Castle segment mapped index=$i start=${_activeSegmentStart.inMilliseconds}ms',
        );
      }
      return;
    }
  }

  bool _shouldIgnoreCompletedEvent() {
    final override = _request?.streamResult?.duration;
    if (override == null || override <= Duration.zero) return false;
    final position = _state.value.position;
    return position + const Duration(seconds: 30) < override;
  }

  @override
  Future<void> load(PlaybackRequest request) async {
    _request = request;
    _loadClock = Stopwatch()..start();
    _firstFrameLogged = false;
    _lastPositionNotificationAt = null;
    _lastBufferNotificationAt = null;
    _lastPublishedPosition = Duration.zero;
    _lastPublishedBuffer = Duration.zero;
    _activeSegmentIndex = null;
    _activeSegmentStart = Duration.zero;
    _usingSegmentPlaylist = false;
    _segmentPlaylistBaseStart = Duration.zero;
    if (!request.hasPlayableSource) {
      _update(
        status: PlaybackStatus.error,
        errorMessage: 'No playable source is available.',
      );
      return;
    }

    _update(
      status: PlaybackStatus.loading,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
      bufferedPosition: Duration.zero,
      clearError: true,
    );

    try {
      PlaybackRuntimeDiagnostics.mpvLog(
        'Lifecycle: Loading ${request.source}',
        clock: _loadClock,
      );
      await _configureNativeDefaults(request);
      await _player.open(
        Media(
          request.source!,
          httpHeaders: request.httpHeaders,
          start: request.startPosition > Duration.zero
              ? request.startPosition
              : null,
        ),
        play: true,
      );
      PlaybackRuntimeDiagnostics.mpvLog('open() completed', clock: _loadClock);
      await _applyNativePlaybackOptions();
      await _applyPendingTrackSelections();
      unawaited(_dumpNativeState('after-open'));
    } catch (error) {
      _mpvLog('open() failed: $error');
      _update(
        status: PlaybackStatus.error,
        isPlaying: false,
        errorMessage: 'Playback failed: $error',
      );
    }
  }

  @override
  Future<void> retry() async {
    final request = _request;
    if (request != null) await load(request);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    _update(status: PlaybackStatus.stopped, isPlaying: false);
  }

  @override
  Future<void> seek(Duration position) async {
    if (_request?.streamResult?.segments.isNotEmpty == true) {
      final request = _request;
      if (request?.source?.trim().isNotEmpty == true) {
        await _openSegmentedSeek(request!, position);
        return;
      }
    }
    await _player.seek(position);
  }

  Future<void> _openSegmentedSeek(
    PlaybackRequest request,
    Duration position,
  ) async {
    final segments = request.streamResult?.segments ?? const [];
    if (segments.isEmpty) return;

    final clamped = _clampToStreamDuration(position);
    final index = _segmentIndexFor(segments, clamped);
    final segment = segments[index];
    final localOffset = _clampToSegmentOffset(clamped - segment.start, segment);
    final wasPlaying = _player.state.playing;
    final medias = segments
        .skip(index)
        .map((segment) => Media(segment.url, httpHeaders: request.httpHeaders))
        .toList(growable: false);

    _activeSegmentIndex = index;
    _activeSegmentStart = segment.start;
    _usingSegmentPlaylist = true;
    _segmentPlaylistBaseStart = segment.start;
    _lastPublishedPosition = clamped;
    _lastPublishedBuffer = clamped;
    _mpvLog(
      'Castle segmented seek target=${clamped.inMilliseconds}ms '
      'segment=$index local=${localOffset.inMilliseconds}ms',
    );
    _update(
      status: PlaybackStatus.buffering,
      position: clamped,
      bufferedPosition: clamped,
    );
    await _player.open(Playlist(medias), play: wasPlaying);
    if (localOffset > Duration.zero) {
      try {
        await _player.seek(localOffset);
      } catch (error) {
        _mpvLog('Castle segment local seek failed: $error');
      }
    }
    await _applyPendingTrackSelections();
    if (!wasPlaying) await _player.pause();
  }

  Duration _clampToStreamDuration(Duration position) {
    final duration = _request?.streamResult?.duration;
    if (position < Duration.zero) return Duration.zero;
    if (duration == null || duration <= Duration.zero) return position;
    final max = duration - const Duration(milliseconds: 500);
    if (max <= Duration.zero) return Duration.zero;
    return position > max ? max : position;
  }

  static Duration _clampToSegmentOffset(
    Duration offset,
    StreamSegment segment,
  ) {
    if (offset <= Duration.zero) return Duration.zero;
    final max = segment.duration - const Duration(milliseconds: 200);
    if (max <= Duration.zero) return Duration.zero;
    return offset > max ? max : offset;
  }

  static int _segmentIndexFor(List<StreamSegment> segments, Duration position) {
    for (var i = 0; i < segments.length; i += 1) {
      final segment = segments[i];
      if (position >= segment.start && position < segment.end) return i;
    }
    return segments.length - 1;
  }

  @override
  Future<void> setVolume(double volume) {
    return _player.setVolume(volume.clamp(0.0, 2.0) * 100);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    final normalized = speed.clamp(0.25, 4.0).toDouble();
    await _player.setRate(normalized);
    _update(playbackSpeed: normalized);
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    final playlistMode = switch (mode) {
      PlaybackRepeatMode.none => PlaylistMode.none,
      PlaybackRepeatMode.one => PlaylistMode.single,
      PlaybackRepeatMode.all => PlaylistMode.loop,
    };
    await _player.setPlaylistMode(playlistMode);
    _update(repeatMode: mode);
  }

  @override
  Future<void> selectAudioTrack(String trackId) async {
    _pendingAudioTrackId = trackId;
    final track = _findAudioTrack(trackId);
    final position = _player.state.position;
    final wasPlaying = _player.state.playing;
    await _player.setAudioTrack(track);
    if (position > Duration.zero) await _player.seek(position);
    if (wasPlaying) await _player.play();
    _update(selectedAudioTrackId: track.id);
  }

  @override
  Future<void> selectSubtitleTrack(
    String trackId, {
    String? externalUrl,
  }) async {
    _pendingSubtitleTrackId = trackId;
    _pendingSubtitleExternalUrl = externalUrl;
    final SubtitleTrack track;
    if (externalUrl != null && externalUrl.trim().isNotEmpty) {
      track = SubtitleTrack.uri(externalUrl, title: trackId, language: trackId);
    } else {
      track = _findSubtitleTrack(trackId);
    }
    final position = _player.state.position;
    final wasPlaying = _player.state.playing;
    final selected = await _setSubtitleTrackSafely(track);
    if (!selected) return;
    if (position > Duration.zero) await _player.seek(position);
    if (wasPlaying) await _player.play();
    _update(
      selectedSubtitleTrackId:
          externalUrl != null && externalUrl.trim().isNotEmpty
          ? trackId
          : track.id,
    );
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    _subtitleDelay = delay;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty(
        'sub-delay',
        (delay.inMilliseconds / 1000).toString(),
      );
    }
  }

  @override
  Future<void> setSubtitleStyle(SubtitleStyle style) async {
    _subtitleStyle = style;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty('sub-scale', style.scale.toStringAsFixed(2));
    await platform.setProperty(
      'sub-back-color',
      style.background ? '#00000099' : '#00000000',
    );
    await platform.setProperty('sub-border-size', style.outline ? '3' : '1');
    await platform.setProperty(
      'sub-shadow-offset',
      style.outline ? '1.5' : '0',
    );
  }

  @override
  Future<void> setDebanding(bool enabled) async {
    _debandingEnabled = enabled;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('deband', enabled ? 'yes' : 'no');
    }
  }

  @override
  Future<PlaybackDiagnostics> diagnostics() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) {
      return const PlaybackDiagnostics(backend: 'media_kit');
    }

    final width = await _nativeProperty(platform, 'width');
    final height = await _nativeProperty(platform, 'height');
    final fps = await _nativeProperty(platform, 'estimated-vf-fps');
    final videoBitrate = await _nativeProperty(platform, 'video-bitrate');
    final audioBitrate = await _nativeProperty(platform, 'audio-bitrate');
    final cacheUsed = await _nativeProperty(platform, 'cache-used');
    final demuxerCache = await _nativeProperty(
      platform,
      'demuxer-cache-duration',
    );
    final dropped = await _nativeProperty(platform, 'frame-drop-count');
    final decoder = await _nativeProperty(platform, 'video-codec');
    final hwdec = await _nativeProperty(platform, 'hwdec-current');
    final vo = await _nativeProperty(platform, 'current-vo');
    final audio = await _nativeProperty(platform, 'aid');
    final subtitle = await _nativeProperty(platform, 'sid');

    return PlaybackDiagnostics(
      backend: 'media_kit/libmpv',
      decoder: _clean(decoder),
      renderer: _clean(vo),
      hardwareAcceleration: _clean(hwdec),
      resolution: width.isEmpty || height.isEmpty
          ? 'unknown'
          : '${width}x$height',
      fps: _clean(fps),
      bitrate: _bitrate(videoBitrate, audioBitrate),
      cache: cacheUsed.isEmpty ? 'unknown' : '$cacheUsed bytes',
      buffer: demuxerCache.isEmpty ? 'unknown' : '${demuxerCache}s',
      droppedFrames: _clean(dropped),
      audioTrack: _clean(audio),
      subtitleTrack: _clean(subtitle),
    );
  }

  @override
  Future<String?> takeScreenshot() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return null;
    final directory = await getApplicationDocumentsDirectory();
    final screenshots = Directory('${directory.path}/screenshots');
    if (!screenshots.existsSync()) {
      screenshots.createSync(recursive: true);
    }
    final path =
        '${screenshots.path}/nivio-${DateTime.now().millisecondsSinceEpoch}.png';
    await platform.command(['screenshot-to-file', path, 'video']);
    return File(path).existsSync() ? path : null;
  }

  Future<void> _configureNativeDefaults(PlaybackRequest request) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    await _setNativeProperty(platform, 'hwdec', 'auto-safe');
    await _setNativeProperty(platform, 'hwdec-codecs', 'all');
    await _setNativeProperty(platform, 'vd-lavc-dr', 'yes');
    await _setNativeProperty(platform, 'video-sync', 'audio');
    await _setNativeProperty(platform, 'interpolation', 'no');
    await _setNativeProperty(platform, 'volume-max', '200');
    await _setNativeProperty(platform, 'cache', 'yes');
    await _setNativeProperty(platform, 'demuxer-readahead-secs', '12');
    await _applyNativePlaybackOptions();
    await _configureHttpOptions(platform, request);
    unawaited(_dumpNativeState('before-open'));
  }

  Future<void> _setNativeProperty(
    NativePlayer platform,
    String name,
    String value,
  ) async {
    try {
      await platform.setProperty(name, value);
    } catch (error) {
      _mpvLog('Ignoring unsupported native option $name=$value: $error');
    }
  }

  Future<void> _applyNativePlaybackOptions() async {
    await setSubtitleDelay(_subtitleDelay);
    await setSubtitleStyle(_subtitleStyle);
    await setDebanding(_debandingEnabled);
  }

  Future<void> _applyPendingTrackSelections() async {
    if (_applyingPendingTracks) return;
    _applyingPendingTracks = true;
    try {
      final audio = _pendingAudioTrackId;
      if (audio != null && audio.isNotEmpty) {
        final current = _player.state.track.audio.id;
        final next = _findAudioTrack(audio);
        if (next.id != current) {
          await _player.setAudioTrack(next);
          _update(selectedAudioTrackId: next.id);
        }
      }

      final subtitle = _pendingSubtitleTrackId;
      if (subtitle != null && subtitle.isNotEmpty) {
        final current = _player.state.track.subtitle.id;
        final externalUrl = _pendingSubtitleExternalUrl;
        final alreadySelected =
            _state.value.selectedSubtitleTrackId == subtitle;
        final next = externalUrl != null && externalUrl.trim().isNotEmpty
            ? SubtitleTrack.uri(
                externalUrl,
                title: subtitle,
                language: subtitle,
              )
            : _findSubtitleTrack(subtitle);
        final shouldSelect =
            externalUrl != null && externalUrl.trim().isNotEmpty
            ? !alreadySelected
            : next.id != current;
        if (shouldSelect) {
          final selected = await _setSubtitleTrackSafely(next);
          if (!selected) return;
          _update(
            selectedSubtitleTrackId:
                externalUrl != null && externalUrl.trim().isNotEmpty
                ? subtitle
                : next.id,
          );
        }
      }
    } finally {
      _applyingPendingTracks = false;
    }
  }

  Future<bool> _setSubtitleTrackSafely(SubtitleTrack track) async {
    try {
      await _player.setSubtitleTrack(track);
      return true;
    } catch (error) {
      _mpvLog('Subtitle selection failed: $error');
      _pendingSubtitleTrackId = null;
      _pendingSubtitleExternalUrl = null;
      await _disableFailedSubtitle();
      _update(selectedSubtitleTrackId: 'no', clearError: true);
      return false;
    }
  }

  Future<void> _disableFailedSubtitle() async {
    try {
      await _player.setSubtitleTrack(SubtitleTrack.no());
    } catch (_) {}
  }

  bool _isRecoverableSubtitleError(String message) {
    final lower = message.toLowerCase();
    final mentionsSubtitle =
        lower.contains('external file') ||
        lower.contains('subtitle') ||
        lower.contains('.srt') ||
        lower.contains('.vtt') ||
        lower.contains('.ass') ||
        lower.contains('.ssa');
    final failedOpen =
        lower.contains('can not open') ||
        lower.contains('cannot open') ||
        lower.contains('failed to open') ||
        lower.contains('error loading');
    return mentionsSubtitle && failedOpen;
  }

  AudioTrack _findAudioTrack(String trackId) {
    final normalized = _normalizeTrackLookup(trackId);
    if (normalized == 'no') return AudioTrack.no();
    if (normalized == 'auto' || normalized.isEmpty) return AudioTrack.auto();

    for (final track in _player.state.tracks.audio) {
      if (_matchesTrack(track.id, track.title, track.language, normalized)) {
        return track;
      }
    }
    return AudioTrack.auto();
  }

  SubtitleTrack _findSubtitleTrack(String trackId) {
    final normalized = _normalizeTrackLookup(trackId);
    if (normalized == 'no' || normalized == 'off') return SubtitleTrack.no();
    if (normalized == 'auto' || normalized.isEmpty) return SubtitleTrack.auto();

    for (final track in _player.state.tracks.subtitle) {
      if (_matchesTrack(track.id, track.title, track.language, normalized)) {
        return track;
      }
    }
    return SubtitleTrack.auto();
  }

  bool _matchesTrack(
    String id,
    String? title,
    String? language,
    String normalized,
  ) {
    final label = _trackLabel(id, title, language, fallbackPrefix: '');
    return _normalizeTrackLookup(id) == normalized ||
        _normalizeTrackLookup(title) == normalized ||
        _normalizeTrackLookup(language) == normalized ||
        _normalizeTrackLookup(label).contains(normalized) ||
        _isLanguageMatch(title, normalized) ||
        _isLanguageMatch(language, normalized) ||
        _isLanguageMatch(label, normalized);
  }

  String _normalizeTrackLookup(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  bool _isLanguageMatch(String? trackValue, String preferredValue) {
    final track = _normalizeTrackLookup(trackValue);
    final preferred = _normalizeTrackLookup(preferredValue);
    if (track.isEmpty || preferred.isEmpty) return false;
    if (track == preferred ||
        track.contains(preferred) ||
        preferred.contains(track)) {
      return true;
    }

    const aliases = <String, List<String>>{
      'english': ['en', 'eng'],
      'japanese': ['ja', 'jpn'],
      'hindi': ['hi', 'hin'],
      'tamil': ['ta', 'tam'],
      'telugu': ['te', 'tel'],
      'spanish': ['es', 'spa'],
      'french': ['fr', 'fre', 'fra'],
      'korean': ['ko', 'kor'],
      'german': ['de', 'ger', 'deu'],
      'italian': ['it', 'ita'],
      'arabic': ['ar', 'ara'],
      'malayalam': ['ml', 'mal'],
      'portuguese': ['pt', 'por'],
      'chinese': ['zh', 'chi', 'zho'],
    };

    final preferredCodes = aliases[preferred] ?? [preferred];
    final trackCodes = aliases[track] ?? [track];
    if (preferredCodes.any((code) => track == code || track.contains(code))) {
      return true;
    }
    if (trackCodes.any(
      (code) => preferred == code || preferred.contains(code),
    )) {
      return true;
    }

    return preferredCodes.any((code) {
      final escaped = RegExp.escape(code);
      return RegExp(
        '(^|[^a-z])$escaped([^a-z]|\$)',
        caseSensitive: false,
      ).hasMatch(track);
    });
  }

  Future<void> _configureHttpOptions(
    NativePlayer platform,
    PlaybackRequest request,
  ) async {
    await platform.setProperty('http-header-fields', '');
    await platform.setProperty('referrer', '');
    await platform.setProperty('user-agent', '');

    final headers = request.httpHeaders;
    if (headers.isEmpty) {
      _mpvLog('HTTP headers: none');
      return;
    }
    final userAgent = headers[_headerKey(headers, 'User-Agent')];
    final referer =
        headers[_headerKey(headers, 'Referer')] ??
        headers[_headerKey(headers, 'Referrer')];
    if (userAgent != null && userAgent.isNotEmpty) {
      await platform.setProperty('user-agent', userAgent);
    }
    if (referer != null && referer.isNotEmpty) {
      await platform.setProperty('referrer', referer);
    }
    final headerFields = headers.entries
        .where((entry) {
          final key = entry.key.toLowerCase();
          return key != 'user-agent' && key != 'referer' && key != 'referrer';
        })
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(',');
    if (headerFields.isNotEmpty) {
      await platform.setProperty('http-header-fields', headerFields);
    }
    _mpvLog(
      'HTTP headers: user-agent=${userAgent ?? 'none'} '
      'referer=${referer ?? 'none'} fields=${headerFields.isEmpty ? 'none' : headerFields}',
    );
  }

  Future<void> _dumpNativeState(String label) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final properties = {
      'path': await _nativeProperty(platform, 'path'),
      'stream-open-filename': await _nativeProperty(
        platform,
        'stream-open-filename',
      ),
      'demuxer-cache-state': await _nativeProperty(
        platform,
        'demuxer-cache-state',
      ),
      'video-codec': await _nativeProperty(platform, 'video-codec'),
      'hwdec-current': await _nativeProperty(platform, 'hwdec-current'),
      'current-vo': await _nativeProperty(platform, 'current-vo'),
      'width': await _nativeProperty(platform, 'width'),
      'height': await _nativeProperty(platform, 'height'),
    };
    _mpvLog('State[$label]: $properties');
  }

  Future<String> _nativeProperty(NativePlayer platform, String name) async {
    try {
      return (await platform.getProperty(name)).trim();
    } catch (_) {
      return '';
    }
  }

  static String _clean(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == 'no' || trimmed == '0') return 'unknown';
    return trimmed;
  }

  static String _bitrate(String video, String audio) {
    final parts = <String>[
      if (video.trim().isNotEmpty) 'video ${video.trim()}',
      if (audio.trim().isNotEmpty) 'audio ${audio.trim()}',
    ];
    return parts.isEmpty ? 'unknown' : parts.join(', ');
  }

  static String _headerKey(Map<String, String> headers, String key) {
    return headers.keys.firstWhere(
      (candidate) => candidate.toLowerCase() == key.toLowerCase(),
      orElse: () => key,
    );
  }

  static String _normalizedSegmentUrl(String url) {
    final parsed = Uri.tryParse(url.trim());
    if (parsed == null) return url.trim();
    return '${parsed.host}${parsed.path}';
  }

  static void _mpvLog(String message) {
    PlaybackRuntimeDiagnostics.mpvLog(_redactSensitive(message));
  }

  static String _redactSensitive(String message) {
    return message
        .replaceAll(
          RegExp(r'Cookie: [^"\]]+', caseSensitive: false),
          'Cookie: <redacted>',
        )
        .replaceAll(
          RegExp(r'CloudFront-Policy=[^;,"\]]+'),
          'CloudFront-Policy=<redacted>',
        )
        .replaceAll(
          RegExp(r'CloudFront-Signature=[^;,"\]]+'),
          'CloudFront-Signature=<redacted>',
        )
        .replaceAll(
          RegExp(r'CloudFront-Key-Pair-Id=[^;,"\]]+'),
          'CloudFront-Key-Pair-Id=<redacted>',
        );
  }

  bool _shouldPublishPosition(Duration position) {
    final now = DateTime.now();
    if (position <= Duration.zero) {
      if (position == _lastPublishedPosition) return false;
      _lastPositionNotificationAt = now;
      _lastPublishedPosition = position;
      return true;
    }
    final lastAt = _lastPositionNotificationAt;
    final movedBackwards = position < _lastPublishedPosition;
    final movedEnough =
        (position - _lastPublishedPosition).abs() >=
        _positionNotificationInterval;
    final waitedEnough =
        lastAt == null ||
        now.difference(lastAt) >= _positionNotificationInterval;
    if (!movedBackwards && !movedEnough && !waitedEnough) return false;
    _lastPositionNotificationAt = now;
    _lastPublishedPosition = position;
    return true;
  }

  bool _shouldPublishBuffer(Duration buffer) {
    if (buffer == _lastPublishedBuffer) return false;
    final now = DateTime.now();
    final lastAt = _lastBufferNotificationAt;
    final changedEnough =
        (buffer - _lastPublishedBuffer).abs() >= _bufferNotificationInterval;
    final waitedEnough =
        lastAt == null || now.difference(lastAt) >= _bufferNotificationInterval;
    if (!changedEnough && !waitedEnough) return false;
    _lastBufferNotificationAt = now;
    _lastPublishedBuffer = buffer;
    return true;
  }

  void _update({
    PlaybackStatus? status,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    double? volume,
    bool? isMuted,
    double? playbackSpeed,
    PlaybackRepeatMode? repeatMode,
    List<PlaybackTrackOption>? audioTracks,
    List<PlaybackTrackOption>? subtitleTracks,
    String? selectedAudioTrackId,
    String? selectedSubtitleTrackId,
    String? errorMessage,
    bool clearError = false,
  }) {
    if (_disposed) return;
    final next = _state.value.copyWith(
      status: status,
      isPlaying: isPlaying,
      position: position,
      duration: duration,
      bufferedPosition: bufferedPosition,
      volume: volume,
      isMuted: isMuted,
      playbackSpeed: playbackSpeed,
      repeatMode: repeatMode,
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      selectedAudioTrackId: selectedAudioTrackId,
      selectedSubtitleTrackId: selectedSubtitleTrackId,
      errorMessage: errorMessage,
      clearError: clearError,
    );
    if (_sameState(_state.value, next)) return;
    _state.value = next;
  }

  bool _sameState(PlaybackState a, PlaybackState b) {
    return a.status == b.status &&
        a.isPlaying == b.isPlaying &&
        a.position == b.position &&
        a.duration == b.duration &&
        a.bufferedPosition == b.bufferedPosition &&
        a.volume == b.volume &&
        a.isMuted == b.isMuted &&
        a.playbackSpeed == b.playbackSpeed &&
        a.repeatMode == b.repeatMode &&
        identical(a.audioTracks, b.audioTracks) &&
        identical(a.subtitleTracks, b.subtitleTracks) &&
        a.selectedAudioTrackId == b.selectedAudioTrackId &&
        a.selectedSubtitleTrackId == b.selectedSubtitleTrackId &&
        a.errorMessage == b.errorMessage;
  }

  PlaybackTrackOption _audioOption(AudioTrack track) {
    return PlaybackTrackOption(
      id: track.id,
      label: _trackLabel(
        track.id,
        track.title,
        track.language,
        fallbackPrefix: 'Audio',
      ),
      language: track.language,
    );
  }

  PlaybackTrackOption _subtitleOption(SubtitleTrack track) {
    return PlaybackTrackOption(
      id: track.id,
      label: _trackLabel(
        track.id,
        track.title,
        track.language,
        fallbackPrefix: 'Subtitle',
      ),
      language: track.language,
    );
  }

  String _trackLabel(
    String id,
    String? title,
    String? language, {
    required String fallbackPrefix,
  }) {
    if (id == 'auto') return 'Auto';
    if (id == 'no') return 'Off';
    final parts = <String>[
      if (title != null && title.trim().isNotEmpty) title.trim(),
      if (language != null && language.trim().isNotEmpty) language.trim(),
    ];
    return parts.isEmpty ? '$fallbackPrefix $id' : parts.join(' · ');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final disposeClock = Stopwatch()..start();
    PlaybackRuntimeDiagnostics.mpvLog(
      'MediaKitPlaybackEngine#$debugInstanceId disposing',
      clock: disposeClock,
    );
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    PlaybackRuntimeDiagnostics.mediaPlayersDisposed++;
    PlaybackRuntimeDiagnostics.videoControllersDisposed++;
    _mpvLog(
      'Texture Released active=${PlaybackRuntimeDiagnostics.textureCount}',
    );
    _mpvLog(
      'NativeVideoController Destroyed active=${PlaybackRuntimeDiagnostics.textureCount}',
    );
    _mpvLog(
      'VideoOutput Destroyed active=${PlaybackRuntimeDiagnostics.textureCount}',
    );
    _mpvLog(
      'Player Disposed active=${PlaybackRuntimeDiagnostics.mediaPlayersAlive}',
    );
    PlaybackRuntimeDiagnostics.mediaKitEnginesDisposed++;
    PlaybackRuntimeDiagnostics.mpvLog(
      'MediaKitPlaybackEngine#$debugInstanceId shutdown complete '
      '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
      clock: disposeClock,
    );
    PlaybackRuntimeDiagnostics.snapshot('after media_kit player dispose');
    _state.dispose();
  }
}
