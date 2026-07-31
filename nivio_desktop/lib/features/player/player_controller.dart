import 'dart:async';

import '../../core/interfaces/watch_history_repository.dart';
import 'models/playback_request.dart';
import 'models/playback_state.dart';
import 'playback_engine.dart';
import 'services/playback_history_session.dart';
import 'services/playback_runtime_diagnostics.dart';

/// Coordinates UI commands without exposing a concrete playback package.
class DesktopPlayerController {
  DesktopPlayerController({
    required this.engine,
    required this.request,
    this.watchHistoryRepository,
    this.historySaveInterval = const Duration(seconds: 5),
  });

  final PlaybackEngine engine;
  PlaybackRequest request;
  final WatchHistoryRepository? watchHistoryRepository;
  final Duration historySaveInterval;
  PlaybackHistorySession? _historySession;
  double _lastAudibleVolume = 1;
  bool _disposed = false;

  PlaybackState get state => engine.state.value;
  bool get debugDisposed => _disposed;

  void _setRequest(PlaybackRequest nextRequest) {
    PlaybackRuntimeDiagnostics.controllerLog(
      'Request updated provider=${nextRequest.providerIndex ?? 'auto'} '
      'source=${nextRequest.source ?? 'none'} '
      'streamResultProvider=${nextRequest.streamResult?.provider ?? 'none'} '
      'streamResultIframe=${nextRequest.streamResult?.isIframe ?? false}',
    );
    request = nextRequest;
    final session = _historySession;
    if (session != null) session.request = nextRequest;
  }

  Future<void> initialize() async {
    PlaybackRuntimeDiagnostics.controllerLog(
      'initialize start disposed=$_disposed',
    );
    if (_disposed) return;
    var effectiveRequest = request;
    final repository = watchHistoryRepository;
    if (repository != null) {
      final session = PlaybackHistorySession(
        repository: repository,
        engine: engine,
        request: request,
        saveInterval: historySaveInterval,
      );
      _historySession = session;
      effectiveRequest = await session.prepareRequest();
      if (_disposed) return;
      _setRequest(effectiveRequest);
      await engine.load(effectiveRequest);
      if (_disposed) return;
      await _applyPreferredSelections();
      if (_disposed) return;
      await session.start();
      PlaybackRuntimeDiagnostics.controllerLog('initialize complete');
      return;
    }
    if (_disposed) return;
    await engine.load(effectiveRequest);
    if (_disposed) return;
    _setRequest(effectiveRequest);
    await _applyPreferredSelections();
    PlaybackRuntimeDiagnostics.controllerLog('initialize complete');
  }

  Future<void> loadRequest(PlaybackRequest nextRequest) async {
    PlaybackRuntimeDiagnostics.controllerLog(
      'loadRequest provider=${nextRequest.providerIndex ?? 'auto'} '
      'current=${request.providerIndex ?? 'auto'} disposed=$_disposed '
      'source=${nextRequest.source ?? 'none'} '
      'streamResultProvider=${nextRequest.streamResult?.provider ?? 'none'} '
      'streamResultIframe=${nextRequest.streamResult?.isIframe ?? false}',
    );
    if (_disposed) return;
    _setRequest(nextRequest);
    await engine.load(nextRequest);
    if (_disposed) return;
    await _applyPreferredSelections();
  }

  Future<void> _applyPreferredSelections() async {
    final preferredAudio = request.preferredAudioTrack;
    if (preferredAudio != null && preferredAudio.isNotEmpty) {
      await engine.selectAudioTrack(preferredAudio);
    }
    final preferredSubtitle = request.preferredSubtitleTrack;
    if (preferredSubtitle != null && preferredSubtitle.isNotEmpty) {
      await engine.selectSubtitleTrack(
        preferredSubtitle,
        externalUrl: _externalSubtitleUrl(preferredSubtitle),
      );
    }
  }

  Future<void> retry() => engine.retry();

  Future<void> togglePlayPause() {
    return state.isPlaying ? engine.pause() : engine.play();
  }

  Future<void> seekBy(Duration offset) {
    if (request.isLive) return Future<void>.value();

    var target = state.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (state.duration > Duration.zero && target > state.duration) {
      target = state.duration;
    }
    return engine.seek(target);
  }

  Future<void> setVolume(double volume) {
    final normalized = volume.clamp(0.0, 2.0);
    if (normalized > 0) _lastAudibleVolume = normalized;
    return engine.setVolume(normalized);
  }

  Future<void> changeVolume(double delta) => setVolume(state.volume + delta);

  Future<void> setPlaybackSpeed(double speed) => engine.setPlaybackSpeed(speed);

  Future<void> cycleRepeatMode() {
    final next = switch (state.repeatMode) {
      PlaybackRepeatMode.none => PlaybackRepeatMode.one,
      PlaybackRepeatMode.one => PlaybackRepeatMode.all,
      PlaybackRepeatMode.all => PlaybackRepeatMode.none,
    };
    return engine.setRepeatMode(next);
  }

  Future<void> selectAudioTrack(String trackId) async {
    await engine.selectAudioTrack(trackId);
    _setRequest(request.copyWith(preferredAudioTrack: trackId));
    await _historySession?.saveProgress(
      audioTrack: trackId,
      subtitleTrack: request.preferredSubtitleTrack,
      resolution: request.preferredQuality,
    );
  }

  Future<void> selectSubtitleTrack(
    String trackId, {
    String? externalUrl,
  }) async {
    await engine.selectSubtitleTrack(trackId, externalUrl: externalUrl);
    _setRequest(request.copyWith(preferredSubtitleTrack: trackId));
    await _historySession?.saveProgress(
      audioTrack: request.preferredAudioTrack,
      subtitleTrack: trackId,
      resolution: request.preferredQuality,
    );
  }

  Future<void> setSubtitleDelay(Duration delay) =>
      engine.setSubtitleDelay(delay);

  Future<void> setSubtitleStyle(SubtitleStyle style) =>
      engine.setSubtitleStyle(style);

  Future<void> setDebanding(bool enabled) => engine.setDebanding(enabled);

  Future<PlaybackDiagnostics> diagnostics() => engine.diagnostics();

  Future<String?> takeScreenshot() => engine.takeScreenshot();

  Future<void> switchQuality(String quality, String source) async {
    if (request.isLive) return;
    final position = state.position;
    final wasPlaying = state.isPlaying;
    final nextRequest = request.copyWith(
      source: source,
      startPosition: position,
      preferredQuality: quality,
    );
    _setRequest(nextRequest);
    await _historySession?.saveProgress(
      audioTrack: nextRequest.preferredAudioTrack,
      subtitleTrack: nextRequest.preferredSubtitleTrack,
      resolution: quality,
    );
    await engine.load(nextRequest);
    if (position > Duration.zero) await engine.seek(position);
    if (!wasPlaying) await engine.pause();
  }

  Future<void> prepareForSourceSwitch(PlaybackRequest nextRequest) async {
    PlaybackRuntimeDiagnostics.controllerLog(
      'Switch provider prepare current=${request.providerIndex ?? 'auto'} '
      'next=${nextRequest.providerIndex ?? 'auto'} disposed=$_disposed '
      'nextSource=${nextRequest.source ?? 'none'} '
      'nextStreamResult=${nextRequest.streamResult?.provider ?? 'none'} '
      'nextIframe=${nextRequest.streamResult?.isIframe ?? false}',
    );
    _setRequest(nextRequest);
    await _historySession?.saveProgress(
      audioTrack: nextRequest.preferredAudioTrack,
      subtitleTrack: nextRequest.preferredSubtitleTrack,
      resolution: nextRequest.preferredQuality,
    );
  }

  String? _externalSubtitleUrl(String trackId) {
    const customPrefix = 'external:Custom:';
    if (trackId.startsWith(customPrefix)) {
      final url = trackId.substring(customPrefix.length).trim();
      return url.isEmpty ? null : url;
    }

    for (final track in request.streamResult?.subtitles ?? const []) {
      final externalId = 'external:${track.lang}:${track.url}';
      if (trackId == externalId || trackId == track.lang) return track.url;
    }
    return null;
  }

  Future<void> toggleMute() {
    if (state.isMuted || state.volume == 0) {
      return engine.setVolume(_lastAudibleVolume.clamp(0.05, 2.0));
    }
    _lastAudibleVolume = state.volume;
    return engine.setVolume(0);
  }

  Future<void> stop() async {
    PlaybackRuntimeDiagnostics.controllerLog('stop disposed=$_disposed');
    await _historySession?.saveProgress();
    await engine.stop();
  }

  Future<void> detachUi() async {
    PlaybackRuntimeDiagnostics.controllerLog(
      'detachUi start disposed=$_disposed',
    );
    if (_disposed) return;
    _disposed = true;
    await _historySession?.dispose();
    _historySession = null;
    PlaybackRuntimeDiagnostics.controllerLog(
      'detachUi complete disposed=$_disposed enginePreserved=true',
    );
  }

  Future<void> close() async {
    PlaybackRuntimeDiagnostics.controllerLog('close start disposed=$_disposed');
    await detachUi();
    await engine.dispose();
    PlaybackRuntimeDiagnostics.controllerLog(
      'close complete disposed=$_disposed engineDisposed=true',
    );
  }
}
