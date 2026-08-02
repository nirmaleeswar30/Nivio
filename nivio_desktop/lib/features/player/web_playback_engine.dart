import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_linux/webview_all_linux.dart';

import 'models/playback_request.dart';
import 'models/playback_state.dart';
import 'playback_surface.dart';
import 'services/playback_runtime_diagnostics.dart';
import 'services/web_runtime_service.dart';

class WebPlaybackEngine implements PlaybackSurfaceEngine {
  WebPlaybackEngine({
    WebViewController? controller,
    this.onPointerActivity,
    this.onBackRequested,
    this.onServerRequested,
    this.onEpisodesRequested,
  }) : _injectedController = controller {
    PlaybackRuntimeDiagnostics.webEnginesCreated++;
    PlaybackRuntimeDiagnostics.webLog(
      'WebPlaybackEngine#$debugInstanceId created '
      '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
    );
    _resetController();
  }

  static int _nextInstanceId = 0;

  final int debugInstanceId = ++_nextInstanceId;
  final WebViewController? _injectedController;
  VoidCallback? onPointerActivity;
  VoidCallback? onBackRequested;
  VoidCallback? onServerRequested;
  VoidCallback? onEpisodesRequested;
  ValueChanged<int>? onSourceIndexRequested;
  Future<void> Function()? _onEnterFullscreen;
  Future<void> Function()? _onExitFullscreen;
  late WebViewController _controller;
  late Future<void> _configured;
  final ValueNotifier<PlaybackState> _state = ValueNotifier(
    const PlaybackState(),
  );

  PlaybackRequest? _request;
  Uri? _initialUri;
  Uri? _loadedUri;
  int _surfaceGeneration = 0;
  int _loadGeneration = 0;
  bool _disposed = false;
  Stopwatch? _loadClock;
  bool _sawVideo = false;
  bool _sawMetadata = false;
  bool _sawLoadedData = false;
  bool _sawCanPlay = false;
  bool _sawFirstFrame = false;
  bool _expectsFirstFrame = false;
  int _internalHttpErrorCount = 0;
  Timer? _readinessTimeoutTimer;
  String? _lastAppControlEvent;
  DateTime? _lastAppControlEventAt;
  List<Map<String, Object?>> _appControlSources = const [];
  int? _selectedAppControlSourceIndex;
  String? _appControlProviderLabel;
  String? _appControlServerLabel;

  @override
  ValueListenable<PlaybackState> get state => _state;
  bool get debugDisposed => _disposed;
  int get debugSurfaceGeneration => _surfaceGeneration;
  int get debugLoadGeneration => _loadGeneration;
  Uri? get debugLoadedUri => _loadedUri;

  void configureAppControls({
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
    this.onPointerActivity = onPointerActivity;
    this.onBackRequested = onBackRequested;
    this.onServerRequested = onServerRequested;
    this.onEpisodesRequested = onEpisodesRequested;
    this.onSourceIndexRequested = onSourceIndexRequested;
    _appControlSources = List<Map<String, Object?>>.unmodifiable(sourceOptions);
    _selectedAppControlSourceIndex = selectedSourceIndex;
    _appControlProviderLabel = providerLabel;
    _appControlServerLabel = serverLabel;
    PlaybackRuntimeDiagnostics.webLog(
      'WebPlaybackEngine#$debugInstanceId app controls configured '
      'pointer=${onPointerActivity != null} back=${onBackRequested != null} '
      'server=${onServerRequested != null} episodes=${onEpisodesRequested != null} '
      'sourceSelect=${onSourceIndexRequested != null} sources=${sourceOptions.length}',
      clock: _loadClock,
    );
    unawaited(_syncAppControlsConfiguration());
  }

  static WebViewController _createController() {
    return WebRuntimeService.instance.createController();
  }

  @override
  Future<void> load(PlaybackRequest request) async {
    final generation = ++_loadGeneration;
    _request = request;
    _resetReadiness();
    PlaybackRuntimeDiagnostics.webLog(
      'WebPlaybackEngine#$debugInstanceId load invoked disposed=$_disposed '
      'surfaceGeneration=$_surfaceGeneration loadGeneration=$generation '
      'provider=${request.providerIndex ?? 'auto'} '
      'streamResultProvider=${request.streamResult?.provider ?? 'none'} '
      'streamResultIframe=${request.streamResult?.isIframe ?? false} '
      'source=${request.source ?? 'none'} currentLoaded=$_loadedUri',
    );
    final source = request.source?.trim();
    if (source == null || source.isEmpty) {
      _update(
        status: PlaybackStatus.error,
        errorMessage: 'No embedded playback source is available.',
      );
      return;
    }

    final uri = Uri.tryParse(_embedUrl(source));
    if (uri == null || !uri.hasScheme) {
      _update(
        status: PlaybackStatus.error,
        errorMessage: 'Invalid embedded playback source.',
      );
      return;
    }

    _initialUri = uri;
    _loadClock = Stopwatch()..start();
    _scheduleReadinessTimeout(generation);
    if (_loadedUri == null) {
      PlaybackRuntimeDiagnostics.webLog(
        'First embedded load',
        clock: _loadClock,
      );
    } else {
      WebRuntimeService.instance.markReused();
      PlaybackRuntimeDiagnostics.webLog(
        'Provider/server navigation via loadRequest from $_loadedUri to $uri',
        clock: _loadClock,
      );
    }
    await _configured;
    _update(
      status: PlaybackStatus.loading,
      isPlaying: false,
      position: request.startPosition,
      duration: Duration.zero,
      bufferedPosition: Duration.zero,
      clearError: true,
    );

    try {
      PlaybackRuntimeDiagnostics.webLog(
        'Page load started url=$uri',
        clock: _loadClock,
      );
      await _controller.loadRequest(uri, headers: request.httpHeaders);
      if (_disposed || generation != _loadGeneration) return;
      _loadedUri = uri;
    } catch (error) {
      if (_disposed || generation != _loadGeneration) return;
      _update(
        status: PlaybackStatus.error,
        isPlaying: false,
        errorMessage: 'Embedded playback failed: $error',
      );
    }
  }

  @override
  Future<void> retry() async {
    final request = _request;
    if (request != null) await load(request);
  }

  @override
  Future<void> play() async {
    await _runCommand('''
      (function() {
        var video = document.querySelector('video');
        if (!video) return;
        var start = function() {
          try { video.play(); } catch (_) {}
        };
        if (video.readyState >= 3) {
          start();
        } else {
          video.addEventListener('canplay', start, { once: true });
          video.addEventListener('loadeddata', start, { once: true });
        }
      })();
    ''');
  }

  @override
  Future<void> pause() async {
    await _runCommand('''
      (function() {
        var video = document.querySelector('video');
        if (video) video.pause();
      })();
    ''');
  }

  @override
  Future<void> stop() async {
    _readinessTimeoutTimer?.cancel();
    await _stopAllMedia();
    await _cleanupBridge();
    try {
      await _controller.loadHtmlString('<html><body></body></html>');
    } catch (_) {}
    _update(status: PlaybackStatus.stopped, isPlaying: false);
  }

  @override
  Future<void> seek(Duration position) async {
    final seconds = (position.inMilliseconds / 1000).toStringAsFixed(3);
    await _runCommand('''
      (function() {
        var video = document.querySelector('video');
        if (video && isFinite(video.duration)) video.currentTime = $seconds;
      })();
    ''');
  }

  @override
  Future<void> setVolume(double volume) async {
    final normalized = volume.clamp(0.0, 2.0).toDouble();
    final browserVolume = normalized.clamp(0.0, 1.0).toStringAsFixed(3);
    await _runCommand('''
      (function() {
        var video = document.querySelector('video');
        if (video) {
          video.volume = $browserVolume;
          video.muted = ${normalized == 0};
        }
      })();
    ''');
    _update(volume: normalized, isMuted: normalized == 0);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    final normalized = speed.clamp(0.25, 4.0).toDouble();
    await _runCommand('''
      (function() {
        var video = document.querySelector('video');
        if (video) video.playbackRate = ${normalized.toStringAsFixed(3)};
      })();
    ''');
    _update(playbackSpeed: normalized);
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    await _runCommand('''
      (function() {
        var video = document.querySelector('video');
        if (video) video.loop = ${mode == PlaybackRepeatMode.one};
      })();
    ''');
    _update(repeatMode: mode);
  }

  @override
  Future<void> selectAudioTrack(String trackId) async {
    _update(selectedAudioTrackId: trackId);
  }

  @override
  Future<void> selectSubtitleTrack(
    String trackId, {
    String? externalUrl,
  }) async {
    _update(selectedSubtitleTrackId: trackId);
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) async {}

  @override
  Future<void> setSubtitleStyle(SubtitleStyle style) async {}

  @override
  Future<void> setDebanding(bool enabled) async {}

  @override
  Future<PlaybackDiagnostics> diagnostics() async {
    return PlaybackDiagnostics(
      backend: 'Web Adapter',
      decoder: 'browser',
      renderer: 'WebKitGTK',
      hardwareAcceleration: 'web engine',
      resolution: await _webValue('resolution'),
      fps: await _webValue('fps'),
      bitrate: 'unknown',
      cache: 'WebKitGTK cache',
      buffer: await _webValue('buffer'),
      droppedFrames: await _webValue('droppedFrames'),
      audioTrack:
          '${_state.value.selectedAudioTrackId}; ${PlaybackRuntimeDiagnostics.memorySummary()}',
      subtitleTrack:
          '${_state.value.selectedSubtitleTrackId}; ${WebRuntimeService.instance.limitationsSummary()}',
    );
  }

  @override
  Future<String?> takeScreenshot() async => null;

  @override
  Widget buildSurface({
    required BuildContext context,
    required BoxFit fit,
    required PlaybackControlsBuilder controls,
    Future<void> Function()? onEnterFullscreen,
    Future<void> Function()? onExitFullscreen,
  }) {
    _onEnterFullscreen = onEnterFullscreen;
    _onExitFullscreen = onExitFullscreen;
    PlaybackRuntimeDiagnostics.webLog(
      'WebPlaybackEngine#$debugInstanceId buildSurface '
      'generation=$_surfaceGeneration disposed=$_disposed '
      'loadGeneration=$_loadGeneration loaded=$_loadedUri '
      'requestProvider=${_request?.providerIndex ?? 'auto'} '
      'requestStreamResult=${_request?.streamResult?.provider ?? 'none'} '
      'requestIframe=${_request?.streamResult?.isIframe ?? false} '
      'state=${_state.value.status.name} '
      'focus=${FocusManager.instance.primaryFocus?.debugLabel ?? FocusManager.instance.primaryFocus?.context?.widget.runtimeType.toString() ?? 'none'}',
    );
    return ColoredBox(
      color: Colors.black,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => PlaybackRuntimeDiagnostics.webLog(
          'WebView Flutter wrapper pointer down position=${event.position} '
          'buttons=${event.buttons} generation=$_surfaceGeneration',
        ),
        onPointerUp: (event) => PlaybackRuntimeDiagnostics.webLog(
          'WebView Flutter wrapper pointer up position=${event.position} '
          'generation=$_surfaceGeneration',
        ),
        child: WebViewWidget(
          key: ValueKey('web-playback-$_surfaceGeneration'),
          controller: _controller,
        ),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _readinessTimeoutTimer?.cancel();
    PlaybackRuntimeDiagnostics.webLog(
      'WebPlaybackEngine#$debugInstanceId dispose start disposed=$_disposed '
      'surfaceGeneration=$_surfaceGeneration loaded=$_loadedUri',
    );
    try {
      await _stopAllMedia();
      await _cleanupBridge();
      await _controller.loadHtmlString('<html><body></body></html>');
    } catch (_) {}
    _disposed = true;
    WebRuntimeService.instance.markDestroyed();
    if (_controller.platform is LinuxWebViewController) {
      try {
        await (_controller.platform as LinuxWebViewController).dispose();
      } catch (_) {}
    }
    _state.dispose();
    PlaybackRuntimeDiagnostics.webEnginesDisposed++;
    PlaybackRuntimeDiagnostics.webLog(
      'WebPlaybackEngine#$debugInstanceId dispose complete disposed=$_disposed '
      '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
    );
  }

  void _resetController() {
    _controller = _injectedController ?? _createController();
    _configured = _configureController();
    _surfaceGeneration++;
    PlaybackRuntimeDiagnostics.webLog(
      'WebPlaybackEngine#$debugInstanceId WebView controller '
      'reset/recreated surfaceGeneration=$_surfaceGeneration '
      'injected=${_injectedController != null}',
    );
  }

  Future<void> _configureController() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(Colors.black);
    await _controller.enableZoom(false);
    await _controller.setUserAgent(
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    );
    await _controller.addJavaScriptChannel(
      'NivioPlayer',
      onMessageReceived: (message) => _handleBridgeMessage(message.message),
    );
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (progress) {
          if (progress >= 100) {
            PlaybackRuntimeDiagnostics.webLog(
              'Page load progress 100%',
              clock: _loadClock,
            );
          }
        },
        onPageStarted: (url) {
          PlaybackRuntimeDiagnostics.webLog(
            'Page started url=$url',
            clock: _loadClock,
          );
          _resetReadiness();
          _scheduleReadinessTimeout(_loadGeneration);
          _update(status: PlaybackStatus.loading, clearError: true);
          unawaited(_injectAndroidParityBridge(_loadGeneration));
        },
        onPageFinished: (url) {
          PlaybackRuntimeDiagnostics.webLog(
            'Page finished url=$url',
            clock: _loadClock,
          );
          unawaited(_injectAndroidParityBridge(_loadGeneration));
        },
        onNavigationRequest: _handleNavigationRequest,
        onWebResourceError: (error) {
          PlaybackRuntimeDiagnostics.webLog(
            'Web resource error mainFrame=${error.isForMainFrame} '
            'description=${error.description}',
            clock: _loadClock,
          );
          if (error.isForMainFrame != true) return;
          _update(
            status: PlaybackStatus.error,
            isPlaying: false,
            errorMessage: error.description,
          );
        },
        onHttpError: (error) {
          PlaybackRuntimeDiagnostics.webLog(
            'HTTP error status=${error.response?.statusCode ?? 'unknown'} '
            'url=${error.request?.uri ?? error.response?.uri ?? 'unknown'}',
            clock: _loadClock,
          );
          if (!_isFatalHttpError(error)) {
            PlaybackRuntimeDiagnostics.webLog(
              'Ignored non-critical HTTP error status=${error.response?.statusCode ?? 'unknown'} '
              'url=${error.request?.uri ?? error.response?.uri ?? 'unknown'}',
              clock: _loadClock,
            );
            return;
          }
          _update(
            status: PlaybackStatus.error,
            isPlaying: false,
            errorMessage: 'Embedded playback HTTP error.',
          );
        },
        onUrlChange: (change) {},
      ),
    );
    await _controller.setOnJavaScriptAlertDialog((request) async {});
    await _controller.setOnJavaScriptConfirmDialog((request) async => false);
    await _controller.setOnJavaScriptTextInputDialog((request) async => '');
  }

  NavigationDecision _handleNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (uri.scheme == 'nivio' && uri.host == 'player-control') {
      final event = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      _handleAppControlEvent(
        event,
        sourceIndex: int.tryParse(uri.queryParameters['index'] ?? ''),
      );
      return NavigationDecision.prevent;
    }
    if (uri.scheme == 'about' || uri.scheme == 'data') {
      return NavigationDecision.navigate;
    }
    final host = uri.host.toLowerCase();
    final lower = request.url.toLowerCase();
    if (_isBlockedHost(host) || _isBlockedUrl(lower)) {
      PlaybackRuntimeDiagnostics.webLog(
        'Navigation prevented blocked url=${request.url}',
        clock: _loadClock,
      );
      return NavigationDecision.prevent;
    }
    if (request.isMainFrame && !_isAllowedMainFrame(uri)) {
      PlaybackRuntimeDiagnostics.webLog(
        'Main-frame navigation prevented url=${request.url}',
        clock: _loadClock,
      );
      _update(
        status: PlaybackStatus.error,
        isPlaying: false,
        errorMessage: 'Embedded provider redirected away from its player.',
      );
      return NavigationDecision.prevent;
    }
    _detectEpisodeNavigation(lower);
    PlaybackRuntimeDiagnostics.webLog(
      'Navigation allowed mainFrame=${request.isMainFrame} url=${request.url}',
      clock: _loadClock,
    );
    return NavigationDecision.navigate;
  }

  void _resetReadiness() {
    _sawVideo = false;
    _sawMetadata = false;
    _sawLoadedData = false;
    _sawCanPlay = false;
    _sawFirstFrame = false;
    _expectsFirstFrame = false;
    _internalHttpErrorCount = 0;
  }

  void _scheduleReadinessTimeout(int generation) {
    _readinessTimeoutTimer?.cancel();
    _readinessTimeoutTimer = Timer(const Duration(seconds: 18), () {
      if (_disposed || generation != _loadGeneration) return;
      final status = _state.value.status;
      if (status == PlaybackStatus.ready ||
          status == PlaybackStatus.completed ||
          status == PlaybackStatus.error ||
          status == PlaybackStatus.stopped) {
        return;
      }
      if (_hasStartedEmbeddedPlayback) return;
      PlaybackRuntimeDiagnostics.webLog(
        'Embedded provider readiness timeout '
        'status=${status.name} sawVideo=$_sawVideo sawMetadata=$_sawMetadata '
        'sawLoadedData=$_sawLoadedData sawCanPlay=$_sawCanPlay '
        'sawFirstFrame=$_sawFirstFrame',
        clock: _loadClock,
      );
      _update(
        status: PlaybackStatus.error,
        isPlaying: false,
        errorMessage: _sawVideo
            ? 'Embedded provider did not start the video.'
            : 'Embedded provider did not expose a playable video.',
      );
    });
  }

  bool _isFatalHttpError(HttpResponseError error) {
    final status = error.response?.statusCode ?? 0;
    if (status < 400) return false;

    final uri = error.request?.uri ?? error.response?.uri;
    if (uri == null) return true;

    final lower = uri.toString().toLowerCase();
    final initial = _initialUri;
    final isInitialDocument =
        initial != null &&
        uri.host.toLowerCase() == initial.host.toLowerCase() &&
        uri.path == initial.path;
    if (isInitialDocument) return true;

    final isCriticalStreamRequest =
        lower.contains('.m3u8') ||
        lower.contains('.mpd') ||
        lower.contains('.mp4') ||
        lower.contains('.m4v') ||
        lower.contains('playlist') ||
        lower.contains('/api/');
    if (isCriticalStreamRequest) return true;

    if (_isStaticSubresource(lower)) return false;

    final longOpaqueRequest = lower.length > 50 || lower.contains('token=');
    if (!longOpaqueRequest) return false;

    _internalHttpErrorCount += 1;
    return _internalHttpErrorCount >= 4;
  }

  bool _isStaticSubresource(String lower) {
    const extensions = <String>[
      '.css',
      '.js',
      '.png',
      '.jpg',
      '.jpeg',
      '.webp',
      '.gif',
      '.svg',
      '.ico',
      '.woff',
      '.woff2',
      '.ttf',
      '.txt',
    ];
    final path = Uri.tryParse(lower)?.path.toLowerCase() ?? lower;
    return extensions.any(path.endsWith);
  }

  Future<void> _cleanupBridge() async {
    await _runCommand('''
      (function() {
        try {
          if (window.__nivioCleanup) window.__nivioCleanup();
        } catch (_) {}
      })();
    ''');
  }

  Future<void> _stopAllMedia() async {
    await _runCommand('''
      (function() {
        try {
          var media = Array.prototype.slice.call(
            document.querySelectorAll('video,audio')
          );
          for (var i = 0; i < media.length; i++) {
            try {
              media[i].pause();
              media[i].muted = true;
              media[i].removeAttribute('src');
              var sources = media[i].querySelectorAll('source');
              for (var j = 0; j < sources.length; j++) {
                sources[j].removeAttribute('src');
              }
              media[i].load();
            } catch (_) {}
          }
        } catch (_) {}
      })();
    ''');
  }

  void _maybeMarkReady({bool? isPlaying}) {
    if (!_hasStartedEmbeddedPlayback) {
      _update(status: PlaybackStatus.buffering, isPlaying: isPlaying);
      return;
    }
    _readinessTimeoutTimer?.cancel();
    _update(status: PlaybackStatus.ready, isPlaying: isPlaying);
  }

  bool get _hasStartedEmbeddedPlayback {
    if (!_sawVideo || !_sawMetadata || !_sawLoadedData || !_sawCanPlay) {
      return false;
    }
    return !_expectsFirstFrame || _sawFirstFrame;
  }

  String _appControlsConfigJson() {
    return jsonEncode({
      'sources': _appControlSources,
      'selectedSourceIndex': _selectedAppControlSourceIndex,
      'providerLabel': _appControlProviderLabel,
      'serverLabel': _appControlServerLabel,
      'canShowEpisodes': onEpisodesRequested != null,
    });
  }

  Future<void> _syncAppControlsConfiguration() async {
    if (_disposed || _loadedUri == null) return;
    final config = _appControlsConfigJson();
    await _runCommand('''
      (function() {
        window.__nivioAppControlsConfig = $config;
        if (window.__nivioRenderServerDrawer) {
          window.__nivioRenderServerDrawer();
        }
      })();
    ''');
  }

  Future<void> _injectAndroidParityBridge(int generation) async {
    final controlsConfig = _appControlsConfigJson();
    await _runCommand('''
      (function() {
        var nivioLoadId = $generation;
        window.__nivioAppControlsConfig = $controlsConfig;
        if (window.__nivioBridgeInstalled &&
            window.__nivioBridgeLoadId === nivioLoadId) {
          return;
        }
        try {
          if (window.__nivioCleanup) window.__nivioCleanup();
        } catch (_) {}
        window.__nivioBridgeInstalled = true;
        window.__nivioBridgeLoadId = nivioLoadId;
        window.__nivioCleanupCallbacks = [];

        var fakeWindow = {
          close: function(){},
          focus: function(){},
          blur: function(){},
          postMessage: function(){},
          document: document,
          location: { href: '', reload: function(){} }
        };
        window.open = function() { return fakeWindow; };

        try {
          Object.defineProperty(document, 'referrer', {
            get: function(){ return 'https://7reels.cc/'; }
          });
        } catch (_) {}

        var originalPlay = HTMLMediaElement.prototype.play;
        var originalPause = HTMLMediaElement.prototype.pause;
        HTMLMediaElement.prototype.play = function() {
          var self = this;
          if (self._nivioPlayPending) return Promise.resolve();
          self._nivioPlayPending = true;
          var promise = originalPlay.apply(this, arguments);
          if (promise && promise.then) {
            promise.then(function() {
              self._nivioPlayPending = false;
              if (self._nivioWantsPause) {
                self._nivioWantsPause = false;
                originalPause.apply(self);
              }
            }).catch(function() {
              self._nivioPlayPending = false;
              self._nivioWantsPause = false;
            });
          } else {
            self._nivioPlayPending = false;
          }
          return promise || Promise.resolve();
        };
        HTMLMediaElement.prototype.pause = function() {
          if (this._nivioPlayPending) {
            this._nivioWantsPause = true;
            return;
          }
          originalPause.apply(this, arguments);
        };

        document.addEventListener('click', function(event) {
          var target = event.target && event.target.closest
            ? event.target.closest('a')
            : null;
          if (!target || !target.href) return;
          var href = target.href.toLowerCase();
          if (href.indexOf('offertomynewbid') >= 0 ||
              href.indexOf('zrlqm') >= 0) {
            event.preventDefault();
            event.stopPropagation();
            return false;
          }
        }, true);

        function post(event, data) {
          try {
            window.NivioPlayer.postMessage(JSON.stringify(Object.assign({
              event: event,
              loadId: nivioLoadId
            }, data || {})));
          } catch (_) {}
        }
        post('bridge_installed');

        function readyStateName(video) {
          if (!video) return 'none';
          return String(video.readyState || 0) + '/' + String(video.networkState || 0);
        }

        function postNavigationTiming() {
          try {
            var entries = performance.getEntriesByType('navigation');
            var timing = entries && entries.length ? entries[0] : null;
            if (!timing) return;
            post('navigation_timing', {
              dns: Math.max(0, timing.domainLookupEnd - timing.domainLookupStart),
              tcp: Math.max(0, timing.connectEnd - timing.connectStart),
              tls: timing.secureConnectionStart > 0
                ? Math.max(0, timing.connectEnd - timing.secureConnectionStart)
                : 0,
              request: Math.max(0, timing.responseStart - timing.requestStart),
              response: Math.max(0, timing.responseEnd - timing.responseStart),
              domInteractive: Math.max(0, timing.domInteractive),
              domContentLoaded: Math.max(0, timing.domContentLoadedEventEnd),
              loadEvent: Math.max(0, timing.loadEventEnd)
            });
          } catch (_) {}
        }

        function installAppControls() {
          if (!document.body) return;
          var existing = document.getElementById('nivio-app-controls');
          if (existing && existing.parentNode === document.body) return;
          if (existing && existing.parentNode) {
            try { existing.parentNode.removeChild(existing); } catch (_) {}
          }

          var root = document.createElement('div');
          root.id = 'nivio-app-controls';
          root.style.all = 'initial';
          root.style.position = 'fixed';
          root.style.top = '12px';
          root.style.left = '0';
          root.style.right = '0';
          root.style.height = '44px';
          root.style.zIndex = '2147483647';
          root.style.display = 'block';
          root.style.pointerEvents = 'none';
          root.style.opacity = '1';
          root.style.visibility = 'visible';
          root.style.fontFamily = 'system-ui, -apple-system, BlinkMacSystemFont, sans-serif';

          function slot(side) {
            var box = document.createElement('div');
            box.style.all = 'initial';
            box.style.position = 'absolute';
            box.style.top = '0';
            box.style.pointerEvents = 'auto';
            if (side === 'left') {
              box.style.left = '12px';
            } else {
              box.style.right = '12px';
              box.style.display = 'inline-flex';
              box.style.alignItems = 'center';
              box.style.gap = '8px';
              box.style.opacity = '0';
              box.style.visibility = 'hidden';
              box.style.transition = 'opacity 180ms ease, visibility 0ms linear 180ms';
            }
            return box;
          }

          function controlsConfig() {
            return window.__nivioAppControlsConfig || {
              sources: [],
              selectedSourceIndex: null,
              providerLabel: '',
              serverLabel: '',
              canShowEpisodes: false
            };
          }

          var lastActivationKey = '';
          var lastActivationAt = 0;
          function activate(eventName, event, data) {
            var now = Date.now();
            var key = eventName + ':' + (data && data.index != null ? data.index : '');
            if (key === lastActivationKey && now - lastActivationAt < 180) return;
            lastActivationKey = key;
            lastActivationAt = now;
            if (event) {
              event.preventDefault();
              event.stopPropagation();
              if (event.stopImmediatePropagation) event.stopImmediatePropagation();
            }
            post(eventName, data || {});
            try {
              var query = data && data.index != null
                ? '?index=' + encodeURIComponent(String(data.index))
                : '';
              window.location.href = 'nivio://player-control/' +
                encodeURIComponent(eventName) + query;
            } catch (_) {}
          }

          function eventPoint(event) {
            if (typeof event.clientX === 'number' && typeof event.clientY === 'number') {
              return { x: event.clientX, y: event.clientY };
            }
            var touch = event.changedTouches && event.changedTouches.length
              ? event.changedTouches[0]
              : null;
            if (touch) return { x: touch.clientX, y: touch.clientY };
            return null;
          }

          function rectContains(rect, point) {
            return point &&
              point.x >= rect.left &&
              point.x <= rect.right &&
              point.y >= rect.top &&
              point.y <= rect.bottom;
          }

          function button(label, icon, eventName) {
            var btn = document.createElement('button');
            btn.style.all = 'initial';
            btn.type = 'button';
            btn.setAttribute('aria-label', label);
            btn.textContent = icon + (label === 'Back' ? '' : '  ' + label);
            btn.style.boxSizing = 'border-box';
            btn.style.display = 'inline-flex';
            btn.style.alignItems = 'center';
            btn.style.justifyContent = 'center';
            btn.style.minWidth = label === 'Back' ? '46px' : '96px';
            btn.style.height = '42px';
            btn.style.pointerEvents = 'auto';
            btn.style.border = '0';
            btn.style.borderRadius = '8px';
            btn.style.background = 'rgba(0,0,0,0.62)';
            btn.style.color = '#fff';
            btn.style.padding = label === 'Back' ? '0' : '0 12px';
            btn.style.fontSize = label === 'Back' ? '24px' : '14px';
            btn.style.fontWeight = '800';
            btn.style.lineHeight = '1';
            btn.style.cursor = 'pointer';
            btn.style.boxShadow = '0 6px 18px rgba(0,0,0,0.35)';
            btn.addEventListener('pointerdown', function(event) {
              event.preventDefault();
              event.stopPropagation();
            }, true);
            btn.addEventListener('mousedown', function(event) {
              event.preventDefault();
              event.stopPropagation();
            }, true);
            btn.addEventListener('touchstart', function(event) {
              event.preventDefault();
              event.stopPropagation();
            }, true);
            btn.addEventListener('pointerup', function(event) {
              if (eventName) activate(eventName, event);
            }, true);
            btn.addEventListener('mouseup', function(event) {
              if (eventName) activate(eventName, event);
            }, true);
            btn.addEventListener('touchend', function(event) {
              if (eventName) activate(eventName, event);
            }, true);
            btn.addEventListener('click', function(event) {
              event.preventDefault();
              event.stopPropagation();
            }, true);
            btn.addEventListener('keydown', function(event) {
              if (event.key === 'Enter' || event.key === ' ') {
                if (eventName) activate(eventName, event);
              }
            }, true);
            return btn;
          }

          function text(value, fallback) {
            if (value == null) return fallback || '';
            var next = String(value).trim();
            return next.length ? next : (fallback || '');
          }

          var serverButton = null;
          var episodesButton = null;

          function hasAlternateServers() {
            var config = controlsConfig();
            var sources = Array.isArray(config.sources) ? config.sources : [];
            return sources.length > 1;
          }

          function setActionSlotVisible(visible) {
            if (!rightSlot) return;
            var config = controlsConfig();
            var showServer = hasAlternateServers();
            var showEpisodes = config.canShowEpisodes === true;
            if (serverButton) {
              serverButton.style.display = showServer ? 'inline-flex' : 'none';
            }
            if (episodesButton) {
              episodesButton.style.display = showEpisodes ? 'inline-flex' : 'none';
            }
            rightSlot.style.display = showServer || showEpisodes ? 'inline-flex' : 'none';
            if (visible && (showServer || showEpisodes)) {
              rightSlot.style.visibility = 'visible';
              rightSlot.style.opacity = '1';
              rightSlot.style.transition = 'opacity 180ms ease';
            }
          }

          function closeServerDrawer() {
            var drawer = document.getElementById('nivio-server-drawer');
            var shade = document.getElementById('nivio-server-shade');
            if (drawer) drawer.style.display = 'none';
            if (shade) shade.style.display = 'none';
            setActionSlotVisible(true);
          }

          function isServerDrawerVisible() {
            var drawer = document.getElementById('nivio-server-drawer');
            return !!drawer && drawer.style.display !== 'none';
          }

          var lastServerToggleAt = 0;

          function toggleServerDrawer(event) {
            if (event) {
              event.preventDefault();
              event.stopPropagation();
              if (event.stopImmediatePropagation) event.stopImmediatePropagation();
            }
            var now = Date.now();
            if (now - lastServerToggleAt < 280) return;
            lastServerToggleAt = now;
            window.__nivioRenderServerDrawer();
            var drawer = document.getElementById('nivio-server-drawer');
            var shade = document.getElementById('nivio-server-shade');
            if (!drawer || !shade) return;
            var show = drawer.style.display === 'none';
            drawer.style.display = show ? 'block' : 'none';
            shade.style.display = show ? 'block' : 'none';
            setActionSlotVisible(!show);
            if (show) wakeControls();
          }

          window.__nivioRenderServerDrawer = function() {
            var config = controlsConfig();
            var sources = Array.isArray(config.sources) ? config.sources : [];
            var shade = document.getElementById('nivio-server-shade');
            if (!shade) {
              shade = document.createElement('div');
              shade.id = 'nivio-server-shade';
              shade.style.all = 'initial';
              shade.style.position = 'fixed';
              shade.style.inset = '0';
              shade.style.zIndex = '2147483646';
              shade.style.background = 'rgba(0,0,0,0.28)';
              shade.style.display = 'none';
              shade.style.pointerEvents = 'auto';
              shade.addEventListener('pointerup', closeServerDrawer, true);
              document.body.appendChild(shade);
            }

            var drawer = document.getElementById('nivio-server-drawer');
            var wasVisible = drawer && drawer.style.display !== 'none';
            if (!drawer) {
              drawer = document.createElement('div');
              drawer.id = 'nivio-server-drawer';
              drawer.style.all = 'initial';
              drawer.style.boxSizing = 'border-box';
              drawer.style.position = 'fixed';
              drawer.style.top = '0';
              drawer.style.right = '0';
              drawer.style.bottom = '0';
              drawer.style.width = '350px';
              drawer.style.maxWidth = '82vw';
              drawer.style.zIndex = '2147483647';
              drawer.style.background = 'rgba(16,16,16,0.96)';
              drawer.style.borderLeft = '1px solid rgba(255,255,255,0.14)';
              drawer.style.boxShadow = '-18px 0 36px rgba(0,0,0,0.45)';
              drawer.style.display = 'none';
              drawer.style.pointerEvents = 'auto';
              drawer.style.fontFamily = 'system-ui, -apple-system, BlinkMacSystemFont, sans-serif';
              drawer.addEventListener('pointerdown', function(event) {
                event.stopPropagation();
              }, true);
              document.body.appendChild(drawer);
            }

            drawer.innerHTML = '';
            var header = document.createElement('div');
            header.style.all = 'initial';
            header.style.boxSizing = 'border-box';
            header.style.display = 'flex';
            header.style.alignItems = 'center';
            header.style.gap = '12px';
            header.style.padding = '22px 22px 14px';
            header.style.color = '#fff';
            header.style.fontFamily = 'inherit';

            var title = document.createElement('div');
            title.style.all = 'initial';
            title.style.color = '#fff';
            title.style.fontSize = '20px';
            title.style.fontWeight = '800';
            title.style.fontFamily = 'inherit';
            title.style.flex = '1';
            title.textContent = 'Select Server';

            var close = button('Close', '\\u00d7', '');
            close.style.minWidth = '40px';
            close.style.height = '38px';
            close.style.fontSize = '24px';
            close.addEventListener('pointerup', function(event) {
              event.preventDefault();
              event.stopPropagation();
              closeServerDrawer();
            }, true);
            header.appendChild(title);
            header.appendChild(close);
            drawer.appendChild(header);

            var current = document.createElement('div');
            current.style.all = 'initial';
            current.style.display = 'block';
            current.style.margin = '0 22px 16px';
            current.style.padding = '10px 12px';
            current.style.borderRadius = '8px';
            current.style.background = 'rgba(255,255,255,0.08)';
            current.style.color = 'rgba(255,255,255,0.72)';
            current.style.fontSize = '12px';
            current.style.fontWeight = '700';
            current.style.fontFamily = 'inherit';
            current.textContent = text(config.serverLabel, text(config.providerLabel, 'Current server'));
            drawer.appendChild(current);

            var list = document.createElement('div');
            list.style.all = 'initial';
            list.style.boxSizing = 'border-box';
            list.style.display = 'block';
            list.style.padding = '0 14px 22px';
            list.style.overflowY = 'auto';
            list.style.maxHeight = 'calc(100vh - 112px)';
            drawer.appendChild(list);

            if (!sources.length) {
              var empty = document.createElement('div');
              empty.style.all = 'initial';
              empty.style.display = 'block';
              empty.style.padding = '18px 10px';
              empty.style.color = 'rgba(255,255,255,0.58)';
              empty.style.fontSize = '13px';
              empty.style.fontFamily = 'inherit';
              empty.textContent = 'No alternate servers available.';
              list.appendChild(empty);
            }

            sources.forEach(function(source) {
              var selected = source.selected === true ||
                Number(source.index) === Number(config.selectedSourceIndex);
              var tile = document.createElement('button');
              tile.style.all = 'initial';
              tile.type = 'button';
              tile.style.boxSizing = 'border-box';
              tile.style.display = 'block';
              tile.style.width = '100%';
              tile.style.margin = '0 0 10px';
              tile.style.padding = '13px 14px';
              tile.style.borderRadius = '8px';
              tile.style.background = selected
                ? 'rgba(229,9,20,0.20)'
                : 'rgba(255,255,255,0.07)';
              tile.style.border = selected
                ? '1px solid rgba(229,9,20,0.72)'
                : '1px solid rgba(255,255,255,0.08)';
              tile.style.color = selected ? '#fff' : 'rgba(255,255,255,0.86)';
              tile.style.fontFamily = 'inherit';
              tile.style.cursor = 'pointer';
              tile.style.textAlign = 'left';
              tile.style.pointerEvents = 'auto';
              tile.textContent = text(source.label, text(source.server, source.provider));
              tile.addEventListener('pointerup', function(event) {
                activate('app_source', event, { index: Number(source.index) });
                closeServerDrawer();
              }, true);
              tile.addEventListener('mouseup', function(event) {
                activate('app_source', event, { index: Number(source.index) });
                closeServerDrawer();
              }, true);
              list.appendChild(tile);
            });

            drawer.style.display = wasVisible ? 'block' : 'none';
            shade.style.display = wasVisible ? 'block' : 'none';
            setActionSlotVisible(!wasVisible);
          };

          var leftSlot = slot('left');
          var rightSlot = slot('right');
          leftSlot.appendChild(button('Back', '\\u2190', 'app_back'));
          serverButton = button('Server', '\\u25A4', '');
          serverButton.addEventListener('pointerup', toggleServerDrawer, true);
          serverButton.addEventListener('mouseup', toggleServerDrawer, true);
          serverButton.addEventListener('touchend', toggleServerDrawer, true);
          rightSlot.appendChild(serverButton);
          episodesButton = button('Episodes', '\\u2630', 'app_episodes');
          rightSlot.appendChild(episodesButton);
          root.appendChild(leftSlot);
          root.appendChild(rightSlot);
          document.body.appendChild(root);
          window.__nivioRenderServerDrawer();

          var appControlCapture = function(event) {
            var point = eventPoint(event);
            if (!point || root.style.visibility === 'hidden') return;
            if (rectContains(leftSlot.getBoundingClientRect(), point)) {
              activate('app_back', event);
              return;
            }
            if (serverButton &&
                serverButton.style.display !== 'none' &&
                rectContains(serverButton.getBoundingClientRect(), point)) {
              toggleServerDrawer(event);
              return;
            }
            if (episodesButton &&
                episodesButton.style.display !== 'none' &&
                rectContains(episodesButton.getBoundingClientRect(), point)) {
              activate('app_episodes', event);
            }
          };
          document.addEventListener('pointerup', appControlCapture, true);
          document.addEventListener('mouseup', appControlCapture, true);
          document.addEventListener('touchend', appControlCapture, true);

          var controlsHideTimer;
          var controlsVisibilityTimer;
          var lastWakeControlsAt = 0;
          var wakeControls = function() {
            var now = Date.now();
            if (now - lastWakeControlsAt < 120) return;
            lastWakeControlsAt = now;
            clearTimeout(controlsVisibilityTimer);
            setActionSlotVisible(true);
            clearTimeout(controlsHideTimer);
            controlsHideTimer = setTimeout(function() {
              if (isServerDrawerVisible()) return;
              rightSlot.style.opacity = '0';
              rightSlot.style.transition = 'opacity 180ms ease, visibility 0ms linear 180ms';
              controlsVisibilityTimer = setTimeout(function() {
                rightSlot.style.visibility = 'hidden';
              }, 220);
            }, 2500);
          };
          var pointerWake = function() { wakeControls(); };
          document.addEventListener('mousemove', pointerWake, true);
          document.addEventListener('touchstart', pointerWake, true);
          root.addEventListener('mouseenter', wakeControls, true);
          wakeControls();

          function activeEditable() {
            var element = document.activeElement;
            if (!element) return false;
            var tag = (element.tagName || '').toLowerCase();
            return tag === 'input' ||
              tag === 'textarea' ||
              tag === 'select' ||
              element.isContentEditable === true;
          }

          function firstMedia() {
            var videos = document.getElementsByTagName('video');
            if (videos && videos.length) return videos[0];
            var audios = document.getElementsByTagName('audio');
            if (audios && audios.length) return audios[0];
            return null;
          }

          function clamp(value, min, max) {
            return Math.max(min, Math.min(max, value));
          }

          function toggleFullscreen() {
            if (document.fullscreenElement) {
              if (document.exitFullscreen) document.exitFullscreen();
              return;
            }
            var target = firstMedia() || document.documentElement;
            if (target && target.requestFullscreen) target.requestFullscreen();
          }

          function handlePlayerKey(event) {
            if (activeEditable()) return;
            var key = event.key || '';
            if (isServerDrawerVisible()) {
              if (key === 'Escape') {
                event.preventDefault();
                event.stopPropagation();
                closeServerDrawer();
              }
              return;
            }
            var media = firstMedia();
            if (key === 's' || key === 'S') {
              var config = controlsConfig();
              var sources = Array.isArray(config.sources) ? config.sources : [];
              if (sources.length > 1) toggleServerDrawer(event);
              return;
            }
            if (!media && key !== 'f' && key !== 'F') return;
            if (key === ' ' || key === 'k' || key === 'K') {
              event.preventDefault();
              event.stopPropagation();
              if (media.paused) media.play(); else media.pause();
            } else if (key === 'ArrowLeft' || key === 'j' || key === 'J') {
              event.preventDefault();
              event.stopPropagation();
              if (isFinite(media.duration)) {
                media.currentTime = clamp(media.currentTime - 10, 0, media.duration);
              }
            } else if (key === 'ArrowRight' || key === 'l' || key === 'L') {
              event.preventDefault();
              event.stopPropagation();
              if (isFinite(media.duration)) {
                media.currentTime = clamp(media.currentTime + 10, 0, media.duration);
              }
            } else if (key === 'ArrowUp') {
              event.preventDefault();
              event.stopPropagation();
              media.volume = clamp(media.volume + 0.05, 0, 1);
              post('volume', { volume: media.volume });
            } else if (key === 'ArrowDown') {
              event.preventDefault();
              event.stopPropagation();
              media.volume = clamp(media.volume - 0.05, 0, 1);
              post('volume', { volume: media.volume });
            } else if (key === 'f' || key === 'F') {
              event.preventDefault();
              event.stopPropagation();
              toggleFullscreen();
            }
          }

          document.addEventListener('keydown', handlePlayerKey, true);

          window.__nivioCleanupCallbacks.push(function() {
            clearTimeout(controlsHideTimer);
            clearTimeout(controlsVisibilityTimer);
            try {
              document.removeEventListener('mousemove', pointerWake, true);
              document.removeEventListener('touchstart', pointerWake, true);
              document.removeEventListener('pointerup', appControlCapture, true);
              document.removeEventListener('mouseup', appControlCapture, true);
              document.removeEventListener('touchend', appControlCapture, true);
              document.removeEventListener('keydown', handlePlayerKey, true);
            } catch (_) {}
            try { root.remove(); } catch (_) {}
            try {
              var drawer = document.getElementById('nivio-server-drawer');
              if (drawer) drawer.remove();
              var shade = document.getElementById('nivio-server-shade');
              if (shade) shade.remove();
              window.__nivioRenderServerDrawer = null;
            } catch (_) {}
          });
        }

        function hook(video) {
          if (!video || video.__nivioHooked) return;
          video.__nivioHooked = true;
          window.__nivioMediaHooked = true;
          post('video_found', {
            readyState: readyStateName(video),
            tag: video.tagName || 'video',
            frameCallback: !!video.requestVideoFrameCallback
          });
          if (video.requestVideoFrameCallback) {
            video.requestVideoFrameCallback(function() {
              post('first_frame', {
                position: isFinite(video.currentTime) ? video.currentTime : 0,
                width: video.videoWidth || 0,
                height: video.videoHeight || 0
              });
            });
          }
          video.addEventListener('play', function(){ post('play'); });
          video.addEventListener('pause', function(){ post('pause'); });
          video.addEventListener('playing', function(){
            post('playing', {
              position: isFinite(video.currentTime) ? video.currentTime : 0,
              readyState: readyStateName(video)
            });
          });
          video.addEventListener('canplay', function(){
            post('canplay', {
              duration: isFinite(video.duration) ? video.duration : 0,
              readyState: readyStateName(video)
            });
          });
          video.addEventListener('loadedmetadata', function(){
            post('metadata', {
              duration: isFinite(video.duration) ? video.duration : 0,
              readyState: readyStateName(video)
            });
          });
          video.addEventListener('loadeddata', function(){
            post('loadeddata', {
              duration: isFinite(video.duration) ? video.duration : 0,
              readyState: readyStateName(video),
              width: video.videoWidth || 0,
              height: video.videoHeight || 0
            });
          });
          video.addEventListener('waiting', function(){ post('buffering'); });
          video.addEventListener('stalled', function(){ post('buffering'); });
          video.addEventListener('suspend', function(){ post('buffering'); });
          video.addEventListener('seeking', function(){ post('buffering'); });
          video.addEventListener('seeked', function(){ post('ready'); });
          video.addEventListener('ended', function(){ post('ended'); });
          video.addEventListener('error', function(){
            post('error', { message: 'Embedded video error' });
          });
          video.addEventListener('timeupdate', function(){
            post('timeupdate', {
              position: isFinite(video.currentTime) ? video.currentTime : 0,
              duration: isFinite(video.duration) ? video.duration : 0,
              buffered: video.buffered && video.buffered.length
                ? video.buffered.end(video.buffered.length - 1)
                : 0
            });
          });
        }

        function scan() {
          installAppControls();
          var videos = document.getElementsByTagName('video');
          for (var i = 0; i < videos.length; i++) hook(videos[i]);
          var audios = document.getElementsByTagName('audio');
          for (var j = 0; j < audios.length; j++) hook(audios[j]);
          if (document.body && !window.__nivioErrorDetected) {
            var text = document.body.innerText
              ? document.body.innerText.toLowerCase()
              : '';
            if (text.indexOf('404 not found') >= 0 ||
                text.indexOf('video not found') >= 0 ||
                text.indexOf('file was deleted') >= 0 ||
                text.indexOf('page not found') >= 0 ||
                text.indexOf('no stream found') >= 0 ||
                text.indexOf("we couldn't find") >= 0 ||
                text.indexOf('could not find') >= 0 ||
                text.indexOf('no results') >= 0 ||
                text.indexOf('not available') >= 0 ||
                text.indexOf('video is unavailable') >= 0 ||
                text.indexOf('movie not found') >= 0 ||
                text.indexOf('episode not found') >= 0) {
              window.__nivioErrorDetected = true;
              post('error', { message: 'Embedded provider reported no stream.' });
            }
          }
        }

        scan();
        var scanCount = 0;
        var scanInterval = setInterval(function() {
          scanCount++;
          scan();
          if ((window.__nivioMediaHooked || scanCount >= 20) && scanInterval) {
            clearInterval(scanInterval);
            scanInterval = null;
          }
        }, 1000);
        window.__nivioCleanupCallbacks.push(function() {
          if (scanInterval) clearInterval(scanInterval);
        });

        if (document.readyState === 'interactive' || document.readyState === 'complete') {
          post('dom_ready', { readyState: document.readyState });
          postNavigationTiming();
        } else {
          document.addEventListener('DOMContentLoaded', function() {
            post('dom_ready', { readyState: document.readyState });
            postNavigationTiming();
            scan();
          }, { once: true });
        }
        window.addEventListener('load', postNavigationTiming, { once: true });

        var root = document.documentElement || document;
        if (window.MutationObserver && root) {
          var observer = new MutationObserver(function(mutations) {
            for (var i = 0; i < mutations.length; i++) {
              for (var j = 0; j < mutations[i].addedNodes.length; j++) {
                var node = mutations[i].addedNodes[j];
                if (!node) continue;
                if (node.tagName === 'VIDEO' || node.tagName === 'AUDIO') hook(node);
                if (node.querySelectorAll) {
                  var media = node.querySelectorAll('video,audio,source');
                  for (var k = 0; k < media.length; k++) {
                    if (media[k].tagName === 'VIDEO' || media[k].tagName === 'AUDIO') {
                      hook(media[k]);
                    }
                  }
                }
              }
            }
            scan();
          });
          observer.observe(root, { childList: true, subtree: true });
          window.__nivioCleanupCallbacks.push(function() {
            try { observer.disconnect(); } catch (_) {}
          });
        }

        var fullscreenListener = function() {
          post(document.fullscreenElement ? 'fullscreen_enter' : 'fullscreen_exit');
        };
        document.addEventListener('fullscreenchange', fullscreenListener);
        window.__nivioCleanupCallbacks.push(function() {
          try {
            document.removeEventListener('fullscreenchange', fullscreenListener);
          } catch (_) {}
        });

        var lastPointerActivityAt = 0;
        var pointerActivityListener = function() {
          var now = Date.now();
          if (now - lastPointerActivityAt < 250) return;
          lastPointerActivityAt = now;
          post('pointer_activity');
        };
        document.addEventListener('mousemove', pointerActivityListener, true);
        document.addEventListener('touchstart', pointerActivityListener, true);
        window.__nivioCleanupCallbacks.push(function() {
          try {
            document.removeEventListener('mousemove', pointerActivityListener, true);
            document.removeEventListener('touchstart', pointerActivityListener, true);
          } catch (_) {}
        });
        window.__nivioCleanup = function() {
          var callbacks = window.__nivioCleanupCallbacks || [];
          for (var i = 0; i < callbacks.length; i++) {
            try { callbacks[i](); } catch (_) {}
          }
          window.__nivioCleanupCallbacks = [];
          window.__nivioBridgeInstalled = false;
        };
      })();
    ''');
  }

  void _handleBridgeMessage(String raw) {
    try {
      final message = jsonDecode(raw);
      if (message is! Map<String, dynamic>) return;
      if (_integer(message['loadId']) != _loadGeneration) return;
      final event = message['event']?.toString();
      switch (event) {
        case 'bridge_installed':
          PlaybackRuntimeDiagnostics.webLog(
            'First JS injected',
            clock: _loadClock,
          );
        case 'pointer_activity':
          onPointerActivity?.call();
        case 'fullscreen_enter':
          unawaited(_onEnterFullscreen?.call());
        case 'fullscreen_exit':
          unawaited(_onExitFullscreen?.call());
        case 'app_back':
          _handleAppControlEvent(event);
        case 'app_server':
          _handleAppControlEvent(event);
        case 'app_episodes':
          _handleAppControlEvent(event);
        case 'app_source':
          _handleAppControlEvent(
            event,
            sourceIndex: _integer(message['index']),
          );
        case 'dom_ready':
          PlaybackRuntimeDiagnostics.webLog('DOM ready', clock: _loadClock);
        case 'navigation_timing':
          PlaybackRuntimeDiagnostics.webLog(
            'Navigation timing dns=${message['dns'] ?? 'unknown'}ms '
            'tcp=${message['tcp'] ?? 'unknown'}ms '
            'tls=${message['tls'] ?? 'unknown'}ms '
            'request=${message['request'] ?? 'unknown'}ms '
            'response=${message['response'] ?? 'unknown'}ms '
            'domInteractive=${message['domInteractive'] ?? 'unknown'}ms '
            'domContentLoaded=${message['domContentLoaded'] ?? 'unknown'}ms '
            'loadEvent=${message['loadEvent'] ?? 'unknown'}ms',
            clock: _loadClock,
          );
        case 'video_found':
          _sawVideo = true;
          _expectsFirstFrame = message['frameCallback'] == true;
          PlaybackRuntimeDiagnostics.webLog(
            'First <video>/<audio> detected readyState=${message['readyState'] ?? 'unknown'}',
            clock: _loadClock,
          );
          _maybeMarkReady();
        case 'play':
          _maybeMarkReady(isPlaying: true);
        case 'playing':
          PlaybackRuntimeDiagnostics.webLog(
            'Playing readyState=${message['readyState'] ?? 'unknown'}',
            clock: _loadClock,
          );
          _maybeMarkReady(isPlaying: true);
        case 'pause':
          _maybeMarkReady(isPlaying: false);
        case 'buffering':
          _update(status: PlaybackStatus.buffering);
        case 'canplay':
          _sawCanPlay = true;
          PlaybackRuntimeDiagnostics.webLog(
            'canplay readyState=${message['readyState'] ?? 'unknown'}',
            clock: _loadClock,
          );
          _maybeMarkReady();
        case 'loadeddata':
          _sawLoadedData = true;
          PlaybackRuntimeDiagnostics.webLog(
            'loadeddata ${message['width'] ?? 0}x${message['height'] ?? 0}',
            clock: _loadClock,
          );
          _maybeMarkReady();
        case 'metadata':
          _sawMetadata = true;
          PlaybackRuntimeDiagnostics.webLog(
            'loadedmetadata',
            clock: _loadClock,
          );
          _update(duration: _seconds(message['duration']));
          _maybeMarkReady();
        case 'ready':
          _maybeMarkReady();
        case 'volume':
          _update(volume: _number(message['volume']).clamp(0.0, 2.0));
        case 'first_frame':
          _sawFirstFrame = true;
          PlaybackRuntimeDiagnostics.webLog(
            'First rendered frame ${message['width'] ?? 0}x${message['height'] ?? 0}',
            clock: _loadClock,
          );
          _maybeMarkReady();
        case 'ended':
          _update(status: PlaybackStatus.completed, isPlaying: false);
        case 'error':
          _update(
            status: PlaybackStatus.error,
            isPlaying: false,
            errorMessage: message['message']?.toString() ?? 'Embedded error',
          );
        case 'timeupdate':
          final position = _seconds(message['position']);
          final duration = _seconds(message['duration']);
          final buffered = _seconds(message['buffered']);
          final status = _sawVideo && _sawMetadata && _sawLoadedData
              ? PlaybackStatus.ready
              : PlaybackStatus.buffering;
          _update(
            status: status,
            position: position,
            duration: duration,
            bufferedPosition: buffered,
          );
      }
    } catch (error) {
      if (PlaybackRuntimeDiagnostics.enabled) {
        debugPrint('Invalid WebPlayback bridge message: $error');
      }
    }
  }

  void _handleAppControlEvent(String? event, {int? sourceIndex}) {
    if (event == null || event.isEmpty) return;
    final now = DateTime.now();
    final eventKey = sourceIndex == null ? event : '$event:$sourceIndex';
    final lastAt = _lastAppControlEventAt;
    if (_lastAppControlEvent == eventKey &&
        lastAt != null &&
        now.difference(lastAt) < const Duration(milliseconds: 350)) {
      return;
    }
    _lastAppControlEvent = eventKey;
    _lastAppControlEventAt = now;
    PlaybackRuntimeDiagnostics.webLog(
      'Embedded app control event=$event sourceIndex=${sourceIndex ?? 'none'} '
      'source=bridge-or-navigation',
      clock: _loadClock,
    );
    switch (event) {
      case 'app_back':
        onBackRequested?.call();
      case 'app_server':
        onServerRequested?.call();
      case 'app_episodes':
        onEpisodesRequested?.call();
      case 'app_source':
        if (sourceIndex != null) onSourceIndexRequested?.call(sourceIndex);
    }
  }

  Future<void> _runCommand(String script) async {
    if (_disposed) return;
    try {
      await _configured;
      await _controller.runJavaScript(script);
    } catch (error) {
      if (PlaybackRuntimeDiagnostics.enabled) {
        debugPrint('WebPlayback JavaScript failed: $error');
      }
    }
  }

  Future<String> _webValue(String key) async {
    try {
      final result = await _controller.runJavaScriptReturningResult('''
        (function() {
          var video = document.querySelector('video');
          if (!video) return 'unknown';
          if ('$key' === 'resolution') {
            return video.videoWidth && video.videoHeight
              ? video.videoWidth + 'x' + video.videoHeight
              : 'unknown';
          }
          if ('$key' === 'fps') {
            var quality = video.getVideoPlaybackQuality
              ? video.getVideoPlaybackQuality()
              : null;
            return quality && quality.totalVideoFrames && video.currentTime
              ? Math.round(quality.totalVideoFrames / video.currentTime).toString()
              : 'unknown';
          }
          if ('$key' === 'buffer') {
            return video.buffered && video.buffered.length
              ? Math.max(0, video.buffered.end(video.buffered.length - 1) -
                video.currentTime).toFixed(1) + 's'
              : 'unknown';
          }
          if ('$key' === 'droppedFrames') {
            var q = video.getVideoPlaybackQuality
              ? video.getVideoPlaybackQuality()
              : null;
            return q && q.droppedVideoFrames != null
              ? q.droppedVideoFrames.toString()
              : 'unknown';
          }
          return 'unknown';
        })();
      ''');
      return result.toString().replaceAll('"', '');
    } catch (_) {
      return 'unknown';
    }
  }

  void _detectEpisodeNavigation(String lower) {
    final match = RegExp(r'/tv/[^/]+/(\d+)/(\d+)').firstMatch(lower);
    if (match == null) return;
    final season = int.tryParse(match.group(1)!);
    final episode = int.tryParse(match.group(2)!);
    if (season == null || episode == null) return;
  }

  bool _isAllowedMainFrame(Uri uri) {
    final host = uri.host.toLowerCase();
    final initialHost = _initialUri?.host.toLowerCase();
    if (initialHost != null && host == initialHost) return true;
    return host.contains('vidsrc') ||
        host.contains('vidcore') ||
        host.contains('vidup') ||
        host.contains('vidlink') ||
        host.contains('vidplus') ||
        host.contains('videasy') ||
        host.contains('youtube.com') ||
        host.contains('youtu.be') ||
        host.contains('google.com');
  }

  static bool _isBlockedHost(String host) {
    const blockedDomains = [
      'offertomynewbid.com',
      'zrlqm.com',
      'popcash.net',
      'popads.net',
      'clickadu.com',
      'adsterra.com',
    ];
    return blockedDomains.any(host.contains);
  }

  static bool _isBlockedUrl(String url) {
    const adPatterns = [
      'google-analytics',
      'googletagmanager',
      'pagead',
      'doubleclick',
      'popcash',
      'popads',
      'adsterra',
      'offertomynewbid',
      '/ad/',
      '/ads/',
      'banner',
      'tracker',
      'telemetry',
    ];
    return adPatterns.any(url.contains);
  }

  static Duration _seconds(Object? raw) {
    final number = _number(raw);
    if (!number.isFinite || number <= 0) return Duration.zero;
    return Duration(milliseconds: (number * 1000).round());
  }

  static double _number(Object? raw) {
    return raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
  }

  static int? _integer(Object? raw) {
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  static String _embedUrl(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null) return source;
    final host = uri.host.toLowerCase();
    if (host.contains('youtube.com') && uri.path == '/watch') {
      final id = uri.queryParameters['v'];
      if (id != null && id.isNotEmpty) {
        return Uri.https('www.youtube.com', '/embed/$id', {
          'autoplay': '1',
          'playsinline': '1',
        }).toString();
      }
    }
    if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
      return Uri.https('www.youtube.com', '/embed/${uri.pathSegments.first}', {
        'autoplay': '1',
        'playsinline': '1',
      }).toString();
    }
    return source;
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
    String? selectedAudioTrackId,
    String? selectedSubtitleTrackId,
    String? errorMessage,
    bool clearError = false,
  }) {
    if (_disposed) return;
    _state.value = _state.value.copyWith(
      status: status,
      isPlaying: isPlaying,
      position: position,
      duration: duration,
      bufferedPosition: bufferedPosition,
      volume: volume,
      isMuted: isMuted,
      playbackSpeed: playbackSpeed,
      repeatMode: repeatMode,
      selectedAudioTrackId: selectedAudioTrackId,
      selectedSubtitleTrackId: selectedSubtitleTrackId,
      errorMessage: errorMessage,
      clearError: clearError,
    );
  }
}
