import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'media_kit_playback_engine.dart';
import 'models/playback_request.dart';
import 'models/playback_state.dart';
import 'playback_engine.dart';
import 'playback_surface.dart';
import 'services/playback_runtime_diagnostics.dart';
import 'web_playback_engine.dart';

class AdaptivePlaybackEngine implements PlaybackSurfaceEngine {
  AdaptivePlaybackEngine({
    this._direct,
    this._web,
    MediaKitPlaybackEngine Function()? directFactory,
    WebPlaybackEngine Function()? webFactory,
  }) : _directFactory = directFactory ?? (() => MediaKitPlaybackEngine()),
       _webFactory = webFactory ?? (() => WebPlaybackEngine()) {
    PlaybackRuntimeDiagnostics.adaptiveEnginesCreated++;
    PlaybackRuntimeDiagnostics.engineLog(
      'AdaptivePlaybackEngine#$debugInstanceId created '
      '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
    );
    final direct = _direct;
    if (direct != null) _state.value = direct.state.value;
  }

  static int _nextInstanceId = 0;

  final int debugInstanceId = ++_nextInstanceId;
  MediaKitPlaybackEngine? _direct;
  WebPlaybackEngine? _web;
  final MediaKitPlaybackEngine Function() _directFactory;
  final WebPlaybackEngine Function() _webFactory;
  final ValueNotifier<PlaybackState> _state = ValueNotifier(
    const PlaybackState(),
  );

  PlaybackEngine? _active;
  VoidCallback? _activeListener;
  VoidCallback? _webPointerActivityCallback;
  VoidCallback? _webBackRequestedCallback;
  VoidCallback? _webServerRequestedCallback;
  VoidCallback? _webEpisodesRequestedCallback;
  ValueChanged<int>? _webSourceIndexRequestedCallback;
  List<Map<String, Object?>> _webSourceOptions = const [];
  int? _webSelectedSourceIndex;
  String? _webProviderLabel;
  String? _webServerLabel;
  bool _disposed = false;

  @override
  ValueListenable<PlaybackState> get state => _state;
  bool get debugDisposed => _disposed;
  String get debugActiveBackend => _active.runtimeType.toString();
  String get debugSessionIdentity =>
      'adaptive#$debugInstanceId active=${_active.runtimeType} '
      'web=${_web?.debugInstanceId ?? '-'} '
      'media=${_direct?.debugInstanceId ?? '-'}';

  void configureWebAppControls({
    VoidCallback? onPointerActivity,
    VoidCallback? onBackRequested,
    VoidCallback? onServerRequested,
    VoidCallback? onEpisodesRequested,
    ValueChanged<int>? onSourceIndexRequested,
    List<Map<String, Object?>> sourceOptions = const [],
    int? selectedSourceIndex,
    String? providerLabel,
    String? serverLabel,
  }) {
    _webPointerActivityCallback = onPointerActivity;
    _webBackRequestedCallback = onBackRequested;
    _webServerRequestedCallback = onServerRequested;
    _webEpisodesRequestedCallback = onEpisodesRequested;
    _webSourceIndexRequestedCallback = onSourceIndexRequested;
    _webSourceOptions = List<Map<String, Object?>>.unmodifiable(sourceOptions);
    _webSelectedSourceIndex = selectedSourceIndex;
    _webProviderLabel = providerLabel;
    _webServerLabel = serverLabel;
    PlaybackRuntimeDiagnostics.engineLog(
      'AdaptivePlaybackEngine#$debugInstanceId web app controls configured '
      'pointer=${onPointerActivity != null} back=${onBackRequested != null} '
      'server=${onServerRequested != null} episodes=${onEpisodesRequested != null} '
      'sourceSelect=${onSourceIndexRequested != null} sources=${sourceOptions.length}',
    );
    _configureWebEngineCallbacks(_web);
  }

  @override
  Future<void> load(PlaybackRequest request) async {
    final transitionClock = Stopwatch()..start();
    final useWeb = _shouldUseWeb(request);
    PlaybackRuntimeDiagnostics.engineLog(
      'Current backend=${_active.runtimeType} target=${useWeb ? 'WebPlaybackEngine' : 'MediaKitPlaybackEngine'} '
      'disposed=$_disposed provider=${request.providerIndex ?? 'auto'} '
      'streamResultProvider=${request.streamResult?.provider ?? 'none'} '
      'streamResultIframe=${request.streamResult?.isIframe ?? false} '
      'source=${request.source ?? 'none'}',
      clock: transitionClock,
    );
    PlaybackRuntimeDiagnostics.lifecycleLog(
      'Backend transition requested target=${useWeb ? 'web' : 'media_kit'}',
      clock: transitionClock,
    );
    final next = useWeb ? _webEngine : _directEngine;
    final previous = _active;
    if (previous != null && !identical(previous, next)) {
      if (useWeb && previous is MediaKitPlaybackEngine) {
        _unbind();
        await previous.dispose();
        if (identical(_direct, previous)) _direct = null;
        PlaybackRuntimeDiagnostics.lifecycleLog(
          'Direct backend fully disposed before WebView load',
          clock: transitionClock,
        );
        PlaybackRuntimeDiagnostics.snapshot(
          'before WebView load',
          clock: transitionClock,
        );
      } else {
        await previous.stop();
        PlaybackRuntimeDiagnostics.lifecycleLog(
          'Previous backend stopped',
          clock: transitionClock,
        );
      }
    }
    _bind(next);
    await next.load(request);
    PlaybackRuntimeDiagnostics.lifecycleLog(
      'Backend load dispatched target=${useWeb ? 'web' : 'media_kit'}',
      clock: transitionClock,
    );
  }

  @override
  Future<void> retry() => _active?.retry() ?? Future.value();

  @override
  Future<void> play() => _active?.play() ?? Future.value();

  @override
  Future<void> pause() => _active?.pause() ?? Future.value();

  @override
  Future<void> stop() => _active?.stop() ?? Future.value();

  @override
  Future<void> seek(Duration position) =>
      _active?.seek(position) ?? Future.value();

  @override
  Future<void> setVolume(double volume) {
    return _active?.setVolume(volume) ?? Future.value();
  }

  @override
  Future<void> setPlaybackSpeed(double speed) {
    return _active?.setPlaybackSpeed(speed) ?? Future.value();
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) {
    return _active?.setRepeatMode(mode) ?? Future.value();
  }

  @override
  Future<void> selectAudioTrack(String trackId) {
    return _active?.selectAudioTrack(trackId) ?? Future.value();
  }

  @override
  Future<void> selectSubtitleTrack(String trackId, {String? externalUrl}) {
    return _active?.selectSubtitleTrack(trackId, externalUrl: externalUrl) ??
        Future.value();
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) {
    return _active?.setSubtitleDelay(delay) ?? Future.value();
  }

  @override
  Future<void> setSubtitleStyle(SubtitleStyle style) {
    return _active?.setSubtitleStyle(style) ?? Future.value();
  }

  @override
  Future<void> setDebanding(bool enabled) {
    return _active?.setDebanding(enabled) ?? Future.value();
  }

  @override
  Future<PlaybackDiagnostics> diagnostics() {
    return _active?.diagnostics() ??
        Future.value(const PlaybackDiagnostics(backend: 'adaptive'));
  }

  @override
  Future<String?> takeScreenshot() {
    return _active?.takeScreenshot() ?? Future.value();
  }

  @override
  Widget buildSurface({
    required BuildContext context,
    required BoxFit fit,
    required PlaybackControlsBuilder controls,
    Future<void> Function()? onEnterFullscreen,
    Future<void> Function()? onExitFullscreen,
  }) {
    final active = _active;
    PlaybackRuntimeDiagnostics.engineLog(
      'AdaptivePlaybackEngine#$debugInstanceId buildSurface '
      'active=${active.runtimeType} disposed=$_disposed '
      'state=${_state.value.status.name}',
    );
    if (active is WebPlaybackEngine) {
      return active.buildSurface(
        context: context,
        fit: fit,
        controls: controls,
        onEnterFullscreen: onEnterFullscreen,
        onExitFullscreen: onExitFullscreen,
      );
    }
    if (active is MediaKitPlaybackEngine) {
      return Video(
        controller: active.videoController,
        fit: fit,
        fill: Colors.black,
        controls: controls,
        onEnterFullscreen: onEnterFullscreen ?? defaultEnterNativeFullscreen,
        onExitFullscreen: onExitFullscreen ?? defaultExitNativeFullscreen,
      );
    }
    return const ColoredBox(color: Colors.black);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    PlaybackRuntimeDiagnostics.engineLog(
      'Adaptive#$debugInstanceId dispose start active=${_active.runtimeType} '
      'disposed=$_disposed',
    );
    _disposed = true;
    _unbind();
    _state.dispose();
    await _web?.dispose();
    await _direct?.dispose();
    PlaybackRuntimeDiagnostics.adaptiveEnginesDisposed++;
    PlaybackRuntimeDiagnostics.engineLog(
      'Adaptive#$debugInstanceId dispose complete '
      '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
    );
  }

  MediaKitPlaybackEngine get _directEngine => _direct ??= _directFactory();

  WebPlaybackEngine get _webEngine {
    final existing = _web;
    if (existing != null) return existing;
    final created = _webFactory();
    _web = created;
    _configureWebEngineCallbacks(created);
    return created;
  }

  void _configureWebEngineCallbacks(WebPlaybackEngine? engine) {
    if (engine == null) return;
    engine.configureAppControls(
      onPointerActivity: _webPointerActivityCallback,
      onBackRequested: _webBackRequestedCallback,
      onServerRequested: _webServerRequestedCallback,
      onEpisodesRequested: _webEpisodesRequestedCallback,
      onSourceIndexRequested: _webSourceIndexRequestedCallback,
      sourceOptions: _webSourceOptions,
      selectedSourceIndex: _webSelectedSourceIndex,
      providerLabel: _webProviderLabel,
      serverLabel: _webServerLabel,
    );
  }

  void _bind(PlaybackEngine engine) {
    if (identical(_active, engine)) return;
    PlaybackRuntimeDiagnostics.engineLog(
      'Binding backend from ${_active.runtimeType} to ${engine.runtimeType}',
    );
    _unbind();
    _active = engine;
    _state.value = engine.state.value;
    void listener() => _state.value = engine.state.value;
    _activeListener = listener;
    engine.state.addListener(listener);
  }

  void _unbind() {
    final active = _active;
    final listener = _activeListener;
    if (active != null && listener != null) {
      active.state.removeListener(listener);
    }
    _activeListener = null;
  }

  static bool _shouldUseWeb(PlaybackRequest request) {
    if (request.streamResult?.isIframe == true) return true;
    final source = request.source?.toLowerCase() ?? '';
    return source.contains('youtube.com/watch') ||
        source.contains('youtube.com/embed') ||
        source.contains('youtu.be/') ||
        source.contains('vidup.') ||
        source.contains('vidlink.') ||
        source.contains('vidcore.') ||
        source.contains('vidplus.');
  }
}
