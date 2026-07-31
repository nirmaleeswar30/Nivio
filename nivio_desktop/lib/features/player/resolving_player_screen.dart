import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/theme/index.dart';
import '../../core/interfaces/watch_history_repository.dart';
import 'adaptive_playback_engine.dart';
import 'models/playback_request.dart';
import 'player_screen.dart';
import 'playback_engine.dart';
import 'services/desktop_streaming_service.dart';
import 'services/mini_player_service.dart';
import 'services/playback_runtime_diagnostics.dart';
import 'services/stream_resolver.dart';

class ResolvingPlayerScreen extends StatefulWidget {
  const ResolvingPlayerScreen({
    super.key,
    required this.request,
    required this.onClose,
    this.resolver,
    this.engineFactory,
    this.watchHistoryRepository,
    this.onNextEpisode,
    this.onMinimize,
  });

  final PlaybackRequest request;
  final VoidCallback onClose;
  final StreamResolver? resolver;
  final PlaybackEngineFactory? engineFactory;
  final WatchHistoryRepository? watchHistoryRepository;
  final ValueChanged<PlaybackRequest>? onNextEpisode;
  final VoidCallback? onMinimize;

  @override
  State<ResolvingPlayerScreen> createState() => _ResolvingPlayerScreenState();
}

class _ResolvingPlayerScreenState extends State<ResolvingPlayerScreen> {
  late final StreamResolver _resolver =
      widget.resolver ?? DesktopStreamingService();
  PlaybackRequest? _resolvedRequest;
  PlaybackEngine? _engine;
  List<PlaybackSourceOption> _sourceOptions = const [];
  String _status = 'Finding a playable source...';
  String? _error;
  bool _canRetry = true;
  bool _isResolving = false;
  int _attempt = 0;
  int _playerGeneration = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ResolvingPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_samePlaybackTarget(oldWidget.request, widget.request)) return;
    _resolve();
  }

  Future<void> _resolve() async {
    final miniSession = MiniPlayerService.instance.reclaimIfMatches(
      widget.request,
    );
    if (miniSession != null) {
      setState(() {
        _engine = miniSession.engine;
        _sourceOptions = miniSession.sourceOptions;
        _resolvedRequest = miniSession.request;
        _isResolving = false;
        _error = null;
        _canRetry = true;
        _status = 'Resuming player...';
        _playerGeneration++;
      });
      return;
    }

    final attempt = ++_attempt;
    final hadResolvedPlayer = _resolvedRequest != null;
    final existingEngine = _engine;
    final resolveClock = Stopwatch()..start();
    if (hadResolvedPlayer) {
      PlaybackRuntimeDiagnostics.lifecycleLog(
        'Provider switch UI contract teardown start '
        'generation=${_playerGeneration + 1} '
        'engine=${_sessionEngineLabel(existingEngine)} '
        '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
        clock: resolveClock,
      );
      if (existingEngine != null) unawaited(existingEngine.stop());
    }
    PlaybackRuntimeDiagnostics.streamLog(
      'Resolution started ${_requestLabel(widget.request)} attempt=$attempt',
      clock: resolveClock,
    );
    setState(() {
      _resolvedRequest = null;
      _playerGeneration++;
      _error = null;
      _canRetry = true;
      _isResolving = true;
      _status = _initialResolvingStatus(widget.request);
    });

    try {
      final effectiveRequest = await _requestWithHistoryPreferences(
        widget.request,
      );
      if (!mounted || attempt != _attempt) return;
      PlaybackRuntimeDiagnostics.streamLog(
        'History preferences restored',
        clock: resolveClock,
      );
      final result = await _resolver
          .resolve(
            effectiveRequest,
            onStatus: (status) {
              if (!mounted || attempt != _attempt) return;
              setState(() => _status = status);
            },
          )
          .timeout(const Duration(seconds: 90));
      PlaybackRuntimeDiagnostics.streamLog(
        'Stream resolved provider=${result.provider} '
        'urlType=${result.isIframe
            ? 'iframe'
            : result.isM3U8
            ? 'hls'
            : 'direct'}',
        clock: resolveClock,
      );
      final options = await _resolver
          .availableSources(effectiveRequest)
          .timeout(const Duration(seconds: 20), onTimeout: () => const []);
      if (!mounted || attempt != _attempt) return;
      PlaybackRuntimeDiagnostics.streamLog(
        'Source enumeration completed count=${options.length} '
        'sources=[${_sourceSummary(options)}]',
        clock: resolveClock,
      );
      setState(() {
        _sourceOptions = options;
        _isResolving = false;
        _resolvedRequest = effectiveRequest.copyWith(
          source: result.url,
          httpHeaders: result.headers,
          streamResult: result,
          preferredQuality: _resolvedQualityPreference(
            result.quality,
            effectiveRequest.preferredQuality,
          ),
          providerIndex: result.providerIndex ?? effectiveRequest.providerIndex,
          preferredAudioTrack: result.selectedAudio.isEmpty
              ? null
              : result.selectedAudio,
        );
      });
      PlaybackRuntimeDiagnostics.streamLog(
        'Resolved request committed generation=$_playerGeneration '
        'engine=${_sessionEngineLabel(_engine)} '
        '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
        clock: resolveClock,
      );
    } on StreamResolutionException catch (error) {
      if (!mounted || attempt != _attempt) return;
      PlaybackRuntimeDiagnostics.streamLog(
        'Resolution failed: ${error.message}',
        clock: resolveClock,
      );
      setState(() {
        _isResolving = false;
        _error = error.message;
        _canRetry = error.canRetry;
      });
    } on TimeoutException {
      if (!mounted || attempt != _attempt) return;
      PlaybackRuntimeDiagnostics.streamLog(
        'Resolution timed out',
        clock: resolveClock,
      );
      setState(() {
        _isResolving = false;
        _error = 'Stream resolution timed out.';
      });
    } catch (error) {
      if (!mounted || attempt != _attempt) return;
      PlaybackRuntimeDiagnostics.streamLog(
        'Resolution failed: $error',
        clock: resolveClock,
      );
      setState(() {
        _isResolving = false;
        _error = 'Playback source resolution failed: $error';
      });
    }
  }

  static String _requestLabel(PlaybackRequest request) {
    return 'media=${request.mediaId} type=${request.mediaTypeName} '
        'season=${request.season ?? '-'} episode=${request.episode ?? '-'} '
        'provider=${request.providerIndex ?? 'auto'} '
        'quality=${request.preferredQuality ?? 'auto'}';
  }

  static String _sourceSummary(List<PlaybackSourceOption> options) {
    return options
        .map((option) => '${option.index}:${option.provider}/${option.server}')
        .join(', ');
  }

  String _initialResolvingStatus(PlaybackRequest request) {
    final providerIndex = request.providerIndex;
    if (providerIndex == null) return 'Finding a playable source...';
    for (final option in _sourceOptions) {
      if (option.index != providerIndex) continue;
      final label = option.label.trim().isNotEmpty
          ? option.label.trim()
          : option.server.trim().isNotEmpty
          ? option.server.trim()
          : option.provider.trim();
      if (label.isNotEmpty) return 'Switching to $label...';
    }
    return 'Switching server...';
  }

  Future<PlaybackRequest> _requestWithHistoryPreferences(
    PlaybackRequest request,
  ) async {
    final defaultedRequest = widget.resolver == null
        ? await _requestWithDefaultPreferences(request)
        : request;
    final repository = widget.watchHistoryRepository;
    final mediaId = defaultedRequest.numericMediaId;
    if (repository == null ||
        mediaId == null ||
        defaultedRequest.hasPlayableSource) {
      return defaultedRequest;
    }

    final progress = await repository.getWatchProgress(
      mediaId: mediaId,
      mediaType: defaultedRequest.mediaTypeName,
      seasonNumber: defaultedRequest.season,
      episodeNumber: defaultedRequest.episode,
    );
    if (progress == null) return defaultedRequest;

    return defaultedRequest.copyWith(
      providerIndex:
          request.providerIndex ??
          _integer(progress['preferredProviderIndex']) ??
          defaultedRequest.providerIndex,
      preferredAudioTrack:
          request.preferredAudioTrack ??
          _string(progress['preferredAudioTrack']) ??
          defaultedRequest.preferredAudioTrack,
      preferredSubtitleTrack:
          request.preferredSubtitleTrack ??
          _string(progress['preferredSubtitleTrack']) ??
          defaultedRequest.preferredSubtitleTrack,
      preferredQuality:
          request.preferredQuality ??
          _string(progress['preferredResolution']) ??
          defaultedRequest.preferredQuality,
    );
  }

  Future<PlaybackRequest> _requestWithDefaultPreferences(
    PlaybackRequest request,
  ) async {
    if (request.hasPlayableSource) return request;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(milliseconds: 250),
      );
      final quality = _normalizedPreference(prefs.getString('video_quality'));
      final subtitle = _normalizedPreference(
        prefs.getString('preferred_subtitle_language'),
      );
      var audio = _normalizedPreference(
        prefs.getString('preferred_audio_language'),
      );
      if (request.mediaType == PlaybackMediaType.anime) {
        audio ??= prefs.getString('animePreferredAudio') == 'dub'
            ? 'dub'
            : 'sub';
      }

      return request.copyWith(
        preferredQuality: request.preferredQuality ?? quality,
        preferredAudioTrack: request.preferredAudioTrack ?? audio,
        preferredSubtitleTrack: request.preferredSubtitleTrack ?? subtitle,
      );
    } catch (_) {
      return request;
    }
  }

  static String? _normalizedPreference(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'auto') {
      return null;
    }
    return text;
  }

  static String? _resolvedQualityPreference(String result, String? existing) {
    final quality = result.trim();
    if (quality.isEmpty || quality.toLowerCase() == 'auto') return existing;
    return quality;
  }

  static int? _integer(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static bool _samePlaybackTarget(
    PlaybackRequest previous,
    PlaybackRequest next,
  ) {
    return previous.mediaId == next.mediaId &&
        previous.mediaType == next.mediaType &&
        previous.season == next.season &&
        previous.episode == next.episode &&
        previous.totalSeasons == next.totalSeasons &&
        previous.totalEpisodes == next.totalEpisodes &&
        previous.providerIndex == next.providerIndex &&
        previous.preferredQuality == next.preferredQuality &&
        previous.preferredAudioTrack == next.preferredAudioTrack &&
        previous.preferredSubtitleTrack == next.preferredSubtitleTrack &&
        previous.source == next.source &&
        previous.streamResult?.url == next.streamResult?.url;
  }

  PlaybackEngine _playerEngine() {
    return _engine ??= widget.engineFactory?.call() ?? AdaptivePlaybackEngine();
  }

  void _minimizeToMiniPlayer() {
    final resolved = _resolvedRequest;
    final engine = _engine;
    if (resolved == null || engine == null) {
      widget.onMinimize?.call();
      return;
    }
    MiniPlayerService.instance.activate(
      MiniPlayerSession(
        request: resolved,
        engine: engine,
        sourceOptions: _sourceOptions,
        watchHistoryRepository: widget.watchHistoryRepository,
      ),
    );
    _engine = null;
    widget.onMinimize?.call();
  }

  static String _sessionEngineLabel(PlaybackEngine? engine) {
    if (engine == null) return 'none';
    if (engine is AdaptivePlaybackEngine) return engine.debugSessionIdentity;
    return engine.runtimeType.toString();
  }

  @override
  void dispose() {
    _attempt++;
    final engine = _engine;
    if (engine != null) {
      PlaybackRuntimeDiagnostics.lifecycleLog(
        'Playback session teardown engine=${_sessionEngineLabel(engine)} '
        '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
      );
      unawaited(engine.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolvedRequest;
    if (resolved != null) {
      PlaybackRuntimeDiagnostics.streamLog(
        'PlayerScreen build handoff generation=$_playerGeneration '
        'provider=${resolved.providerIndex ?? 'auto'} '
        'streamResultProvider=${resolved.streamResult?.provider ?? 'none'} '
        'streamResultIframe=${resolved.streamResult?.isIframe ?? false} '
        'source=${resolved.source ?? 'none'} '
        'isResolving=$_isResolving error=${_error ?? 'none'} '
        'sourceOptions=${_sourceOptions.length} '
        'sources=[${_sourceSummary(_sourceOptions)}]',
      );
      final player = PlayerScreen(
        key: ValueKey('player-ui-$_playerGeneration'),
        request: resolved,
        engine: _playerEngine(),
        watchHistoryRepository: widget.watchHistoryRepository,
        onClose: widget.onClose,
        onMinimize: _minimizeToMiniPlayer,
        onNextEpisode: widget.onNextEpisode,
        onSourceSwitch: widget.onNextEpisode,
        sourceOptions: _sourceOptions,
      );
      return player;
    }

    PlaybackRuntimeDiagnostics.streamLog(
      'ResolvingPlayerScreen build loading generation=$_playerGeneration '
      'isResolving=$_isResolving resolved=false status=$_status '
      'error=${_error ?? 'none'} canRetry=$_canRetry '
      'requestProvider=${widget.request.providerIndex ?? 'auto'} '
      'requestHasSource=${widget.request.hasPlayableSource} '
      'sourceOptions=${_sourceOptions.length}',
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: _error == null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            _isResolving ? _status : 'Preparing player...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.primary,
                            size: 52,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Text(
                            'Stream unavailable',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Wrap(
                            spacing: AppSpacing.sm,
                            children: [
                              OutlinedButton(
                                onPressed: widget.onClose,
                                child: const Text('Back'),
                              ),
                              if (_canRetry)
                                FilledButton(
                                  onPressed: _resolve,
                                  child: const Text('Retry'),
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.lg,
            left: AppSpacing.lg,
            child: IconButton.filledTonal(
              tooltip: 'Back',
              onPressed: widget.onClose,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
        ],
      ),
    );
  }
}
