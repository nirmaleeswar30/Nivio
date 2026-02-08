import 'package:better_player_plus/better_player_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/season_info.dart';
import 'package:nivio/providers/media_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/streaming_service.dart';
import 'package:nivio/widgets/webview_player.dart';
import 'dart:async';
import 'dart:math' as math;

class PlayerScreen extends ConsumerStatefulWidget {
  final int mediaId;
  final int season;
  final int episode;
  final String? mediaType;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.season,
    required this.episode,
    this.mediaType,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  BetterPlayerController? _betterPlayerController;
  StreamResult? _streamResult;
  bool _isLoading = true;
  String? _error;
  Timer? _progressTimer;
  String _currentProvider = '';
  int _retryCount = 0;
  int _currentProviderIndex = 0;
  static const int _maxRetries = 3;
  final int _maxProviders = StreamingService.totalProviders;
  final FocusNode _focusNode = FocusNode();
  bool _showNextEpisodeButton = false;
  bool _nextEpisodeDismissed = false;
  Timer? _nextEpisodeTimer;
  int? _nextEpisodeCountdown;
  bool _isDirectStream = false;
  Duration? _resumePosition;
  int _currentEpisode = 0;
  bool _isSwappingEpisode = false;

  // Notifier so overlay updates inside BetterPlayer fullscreen
  final ValueNotifier<_NextEpState> _nextEpNotifier = ValueNotifier(
    _NextEpState(show: false, countdown: null),
  );
  OverlayEntry? _nextEpOverlayEntry;

  SeasonData? _currentSeasonData;

  @override
  void initState() {
    super.initState();
    _currentEpisode = widget.episode;
    _initializePlayer();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  // ── Keyboard shortcuts ──────────────────────────────────────────
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_betterPlayerController?.isVideoInitialized() != true) {
      return KeyEventResult.ignored;
    }
    final vpc = _betterPlayerController!.videoPlayerController!;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        if (_betterPlayerController?.isPlaying() == true) {
          _betterPlayerController?.pause();
        } else {
          _betterPlayerController?.play();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.keyJ:
        final pos = vpc.value.position;
        _betterPlayerController?.seekTo(
          pos - const Duration(seconds: 10) < Duration.zero
              ? Duration.zero
              : pos - const Duration(seconds: 10),
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.keyL:
        final pos = vpc.value.position;
        final dur = vpc.value.duration;
        if (dur != null) {
          final newPos = pos + const Duration(seconds: 10);
          _betterPlayerController?.seekTo(newPos > dur ? dur : newPos);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        final vol = vpc.value.volume;
        _betterPlayerController?.setVolume(vol > 0 ? 0 : 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        final vol = vpc.value.volume;
        _betterPlayerController?.setVolume((vol + 0.1).clamp(0.0, 1.0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        final vol = vpc.value.volume;
        _betterPlayerController?.setVolume((vol - 0.1).clamp(0.0, 1.0));
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // ── Player initialization ───────────────────────────────────────
  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      var media = ref.read(selectedMediaProvider);
      final hasMatchingSelectedMedia =
          media != null &&
          media.id == widget.mediaId &&
          (widget.mediaType == null || media.mediaType == widget.mediaType);

      if (!hasMatchingSelectedMedia) {
        setState(() => _currentProvider = 'Loading media details...');
        final tmdbService = ref.read(tmdbServiceProvider);
        if (widget.mediaType == 'tv') {
          media = await tmdbService.getTVShowDetails(widget.mediaId);
        } else if (widget.mediaType == 'movie') {
          media = await tmdbService.getMovieDetails(widget.mediaId);
        } else {
          try {
            media = await tmdbService.getTVShowDetails(widget.mediaId);
          } catch (e) {
            media = await tmdbService.getMovieDetails(widget.mediaId);
          }
        }
        ref.read(selectedMediaProvider.notifier).state = media;
      }

      if (media.mediaType == 'tv') {
        _fetchSeasonData();
      }

      setState(() => _currentProvider = 'Fetching stream...');

      final streamingService = ref.read(streamingServiceProvider);
      final settingsQuality = ref.read(videoQualityProvider);
      final manualQuality = ref.read(selectedQualityProvider);
      final preferredQuality =
          manualQuality ?? (settingsQuality == 'auto' ? null : settingsQuality);
      final subDubPref = ref.read(animeSubDubProvider);

      final result = await streamingService.fetchStreamUrl(
        media: media,
        season: widget.season,
        episode: _currentEpisode,
        preferredQuality: preferredQuality,
        providerIndex: _currentProviderIndex,
        subDubPreference: subDubPref,
      );

      if (result == null) {
        if (_currentProviderIndex < _maxProviders - 1) {
          _currentProviderIndex++;
          setState(() => _error = 'Provider unavailable, trying next...');
          await Future.delayed(const Duration(milliseconds: 500));
          _initializePlayer();
          return;
        }
        throw Exception('Failed to get stream URL from all providers');
      }

      _streamResult = result;
      _currentProvider = result.provider;
      _isDirectStream = result.isM3U8;

      // Embed providers use WebView
      if (!_isDirectStream) {
        setState(() {
          _isLoading = false;
          _retryCount = 0;
        });
        return;
      }

      // ── Check watch history for resume ──
      final historyService = ref.read(watchHistoryServiceProvider);
      await historyService.init();
      final history = await historyService.getHistory(widget.mediaId);
      Duration? startAt;

      if (history != null &&
          history.currentSeason == widget.season &&
          history.currentEpisode == _currentEpisode &&
          history.lastPositionSeconds > 0 &&
          history.lastPositionSeconds < history.totalDurationSeconds - 30) {
        startAt = Duration(seconds: history.lastPositionSeconds);
        _resumePosition = startAt;
      }

      // ── Build subtitle sources from Consumet ──
      final subtitleSources = result.subtitles.map((sub) {
        return BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.network,
          name: sub.lang,
          urls: [sub.url],
        );
      }).toList();

      // ── Build resolutions map for non-HLS multi-quality ──
      Map<String, String>? resolutions;
      if (!result.isM3U8 && result.sources.length > 1) {
        resolutions = {};
        for (var source in result.sources) {
          resolutions[source.quality] = source.url;
        }
      }

      // ── Headers ──
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        ...result.headers,
      };

      // ── Data source ──
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        result.url,
        headers: headers,
        videoFormat: result.isM3U8
            ? BetterPlayerVideoFormat.hls
            : BetterPlayerVideoFormat.other,
        useAsmsTracks: result.isM3U8,
        useAsmsSubtitles: result.isM3U8,
        useAsmsAudioTracks: result.isM3U8,
        subtitles: subtitleSources.isNotEmpty ? subtitleSources : null,
        resolutions: resolutions,
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 30000,
          maxBufferMs: 120000,
          bufferForPlaybackMs: 2500,
          bufferForPlaybackAfterRebufferMs: 5000,
        ),
      );

      // ── Controller config ──
      _betterPlayerController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true,
          looping: false,
          fullScreenByDefault: false,
          fit: BoxFit.contain,
          autoDispose: false,
          handleLifecycle: true,
          startAt: startAt,
          controlsConfiguration: BetterPlayerControlsConfiguration(
            enablePlayPause: true,
            enableMute: true,
            enableFullscreen: true,
            enableProgressBar: true,
            enablePlaybackSpeed: true,
            enableSubtitles: true,
            enableQualities: true,
            enableAudioTracks: true,
            enableSkips: true,
            forwardSkipTimeInMilliseconds: 10000,
            backwardSkipTimeInMilliseconds: 10000,
            progressBarPlayedColor: NivioTheme.netflixRed,
            progressBarHandleColor: NivioTheme.netflixRed,
            progressBarBufferedColor: NivioTheme.netflixLightGrey,
            progressBarBackgroundColor: NivioTheme.netflixGrey,
            controlBarColor: Colors.black54,
            loadingColor: NivioTheme.netflixRed,
            overflowModalColor: const Color(0xFF1F1F1F),
            overflowModalTextColor: Colors.white,
            overflowMenuIconsColor: Colors.white70,
            playerTheme: BetterPlayerTheme.material,
            overflowMenuCustomItems: [
              if (media!.mediaType == 'tv')
                BetterPlayerOverflowMenuItem(
                  Icons.list,
                  'Episodes',
                  _showEpisodesBottomSheet,
                ),
            ],
          ),
          placeholder: Container(
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(color: NivioTheme.netflixRed),
            ),
          ),
          errorBuilder: (context, errorMessage) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: NivioTheme.netflixRed,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Playback Error',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMessage ?? 'Unknown error',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (_retryCount < _maxRetries) {
                        _retryCount++;
                        _disposePlayer();
                        _initializePlayer();
                      }
                    },
                    icon: const Icon(Icons.refresh),
                    label: Text('Retry ($_retryCount/$_maxRetries)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NivioTheme.netflixRed,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      // Register event listener BEFORE setting up data source
      _betterPlayerController!.addEventsListener(_onBetterPlayerEvent);

      // Show the player immediately — BetterPlayer handles its own buffering UI
      setState(() {
        _isLoading = false;
        _retryCount = 0;
      });

      await _betterPlayerController!.setupDataSource(dataSource);

      // Start progress tracking timer
      _startProgressTracking();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });

      if (_currentProviderIndex < _maxProviders - 1) {
        _currentProviderIndex++;
        setState(() => _error = 'Switching to next provider...');
        await Future.delayed(const Duration(milliseconds: 500));
        _initializePlayer();
        return;
      }

      if (_retryCount < _maxRetries &&
          (e.toString().contains('network') ||
              e.toString().contains('timeout'))) {
        await Future.delayed(const Duration(seconds: 2));
        _retryCount++;
        _currentProviderIndex = 0;
        _initializePlayer();
      }
    }
  }

  // ── BetterPlayer event listener ─────────────────────────────────
  void _onBetterPlayerEvent(BetterPlayerEvent event) {
    if (!mounted) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        // Set playback speed after initialization
        final speed = ref.read(playbackSpeedProvider);
        _betterPlayerController?.setSpeed(speed);
        // Enter fullscreen with a delay so BetterPlayer is fully ready
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _betterPlayerController?.isFullScreen == false) {
            _betterPlayerController?.enterFullScreen();
          }
        });
        // Show resume snackbar
        if (_resumePosition != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Resumed from ${_formatDuration(_resumePosition!)}',
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: NivioTheme.netflixRed,
            ),
          );
          _resumePosition = null;
        }
        break;
      case BetterPlayerEventType.progress:
        _checkNextEpisode();
        break;
      case BetterPlayerEventType.finished:
        _markAsCompleted();
        if (_hasNextEpisode()) _showNextEpisodePopup();
        break;
      default:
        break;
    }
  }

  void _checkNextEpisode() {
    if (_betterPlayerController?.isVideoInitialized() != true) return;
    final vpc = _betterPlayerController!.videoPlayerController!;

    final position = vpc.value.position;
    final duration = vpc.value.duration;
    if (duration != null && duration.inSeconds > 0) {
      final progress = position.inSeconds / duration.inSeconds;
      if (progress >= 0.90 &&
          !_showNextEpisodeButton &&
          !_nextEpisodeDismissed &&
          _hasNextEpisode()) {
        _showNextEpisodePopup();
      }
    }

    if (duration != null &&
        position >= duration - const Duration(seconds: 10) &&
        duration.inSeconds > 0) {
      _markAsCompleted();
    }
  }

  // ── Season data fetch ───────────────────────────────────────────
  Future<void> _fetchSeasonData() async {
    try {
      final tmdbService = ref.read(tmdbServiceProvider);
      _currentSeasonData = await tmdbService.getSeasonInfo(
        widget.mediaId,
        widget.season,
      );
    } catch (_) {}
  }

  // ── Next episode popup ──────────────────────────────────────────
  void _showNextEpisodePopup() {
    if (_showNextEpisodeButton) return;
    setState(() {
      _showNextEpisodeButton = true;
      _nextEpisodeCountdown = 15;
    });
    _nextEpNotifier.value = _NextEpState(show: true, countdown: 15);
    _showOverlayEntry();
    _nextEpisodeTimer?.cancel();
    _nextEpisodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _nextEpisodeCountdown = (_nextEpisodeCountdown ?? 1) - 1);
      _nextEpNotifier.value = _NextEpState(
        show: true,
        countdown: _nextEpisodeCountdown,
      );
      if ((_nextEpisodeCountdown ?? 0) <= 0) {
        timer.cancel();
        _playNextEpisode();
      }
    });
  }

  Future<void> _markAsCompleted() async {
    final media = ref.read(selectedMediaProvider);
    if (media == null) return;
    final vpc = _betterPlayerController?.videoPlayerController;
    final dur = vpc?.value.duration ?? Duration.zero;
    final historyService = ref.read(watchHistoryServiceProvider);
    await historyService.updateProgress(
      tmdbId: widget.mediaId,
      mediaType: media.mediaType,
      title: media.title ?? media.name ?? 'Unknown',
      posterPath: media.posterPath,
      currentSeason: widget.season,
      currentEpisode: _currentEpisode,
      totalSeasons: 1,
      totalEpisodes: null,
      lastPosition: dur,
      totalDuration: dur,
    );
  }

  // ── WebView event handler ───────────────────────────────────────
  void _handlePlayerEvent(String event, double currentTime, double duration) {
    final media = ref.read(selectedMediaProvider);
    if (media == null) return;
    switch (event) {
      case 'time':
        _saveWebViewProgress(currentTime, duration);
        final progress = duration > 0 ? currentTime / duration : 0.0;
        if (progress >= 0.90 &&
            !_showNextEpisodeButton &&
            !_nextEpisodeDismissed &&
            _hasNextEpisode()) {
          _showNextEpisodePopup();
        }
        break;
      case 'complete':
        _markWebViewAsCompleted(duration);
        if (_hasNextEpisode()) _showNextEpisodePopup();
        break;
    }
  }

  bool _hasNextEpisode() {
    final media = ref.read(selectedMediaProvider);
    if (media == null || media.mediaType != 'tv') return false;
    if (_currentSeasonData != null) {
      return _currentEpisode < _currentSeasonData!.episodes.length;
    }
    return true;
  }

  void _playNextEpisode() {
    _nextEpisodeTimer?.cancel();
    _removeOverlayEntry();
    final media = ref.read(selectedMediaProvider);
    if (media == null || media.mediaType != 'tv') return;

    // Exit fullscreen first so BetterPlayer's route is popped
    // before we dispose the controller
    final wasFullScreen = _betterPlayerController?.isFullScreen == true;
    if (wasFullScreen) {
      _betterPlayerController?.exitFullScreen();
    }

    // Delay to let the fullscreen route fully pop before disposing
    Future.delayed(Duration(milliseconds: wasFullScreen ? 300 : 50), () {
      if (!mounted) return;
      final oldController = _betterPlayerController;
      _progressTimer?.cancel();
      setState(() {
        _currentEpisode = _currentEpisode + 1;
        _isSwappingEpisode = true;
        _showNextEpisodeButton = false;
        _nextEpisodeDismissed = false;
        _nextEpisodeCountdown = null;
        _isLoading = true;
        _error = null;
        _retryCount = 0;
        _currentProviderIndex = 0;
        _streamResult = null;
        _betterPlayerController = null;
      });
      // Dispose after the widget tree has rebuilt without the controller
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (oldController != null) {
          oldController.removeEventsListener(_onBetterPlayerEvent);
          oldController.dispose(forceDispose: true);
        }
        if (mounted) _initializePlayer();
      });
    });
  }

  void _showEpisodesBottomSheet() {
    final media = ref.read(selectedMediaProvider);
    if (media == null || media.mediaType != 'tv') return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _EpisodePickerSheet(
        mediaId: widget.mediaId,
        currentSeason: widget.season,
        currentEpisode: _currentEpisode,
        mediaType: media.mediaType,
      ),
    );
  }

  // ── WebView progress helpers ────────────────────────────────────
  Future<void> _saveWebViewProgress(double currentTime, double duration) async {
    final media = ref.read(selectedMediaProvider);
    if (media == null) return;
    final historyService = ref.read(watchHistoryServiceProvider);
    await historyService.updateProgress(
      tmdbId: widget.mediaId,
      mediaType: media.mediaType,
      title: media.title ?? media.name ?? 'Unknown',
      posterPath: media.posterPath,
      currentSeason: widget.season,
      currentEpisode: _currentEpisode,
      totalSeasons: 1,
      totalEpisodes: null,
      lastPosition: Duration(seconds: currentTime.toInt()),
      totalDuration: Duration(seconds: duration.toInt()),
    );
  }

  Future<void> _markWebViewAsCompleted(double duration) async {
    final media = ref.read(selectedMediaProvider);
    if (media == null) return;
    final historyService = ref.read(watchHistoryServiceProvider);
    await historyService.updateProgress(
      tmdbId: widget.mediaId,
      mediaType: media.mediaType,
      title: media.title ?? media.name ?? 'Unknown',
      posterPath: media.posterPath,
      currentSeason: widget.season,
      currentEpisode: _currentEpisode,
      totalSeasons: 1,
      totalEpisodes: null,
      lastPosition: Duration(seconds: duration.toInt()),
      totalDuration: Duration(seconds: duration.toInt()),
    );
  }

  // ── Formatting & progress ───────────────────────────────────────
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) return '${twoDigits(h)}:${twoDigits(m)}:${twoDigits(s)}';
    return '${twoDigits(m)}:${twoDigits(s)}';
  }

  void _startProgressTracking() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_betterPlayerController != null &&
          _betterPlayerController!.isVideoInitialized() == true &&
          _betterPlayerController!.isPlaying() == true) {
        _saveProgress();
      }
    });
  }

  Future<void> _saveProgress() async {
    if (_betterPlayerController?.isVideoInitialized() != true) return;
    final vpc = _betterPlayerController!.videoPlayerController!;

    final media = ref.read(selectedMediaProvider);
    if (media == null) return;
    final historyService = ref.read(watchHistoryServiceProvider);
    await historyService.updateProgress(
      tmdbId: widget.mediaId,
      mediaType: media.mediaType,
      title: media.title ?? media.name ?? 'Unknown',
      posterPath: media.posterPath,
      currentSeason: widget.season,
      currentEpisode: _currentEpisode,
      totalSeasons: 1,
      totalEpisodes: null,
      lastPosition: vpc.value.position,
      totalDuration: vpc.value.duration ?? Duration.zero,
    );
  }

  void _disposePlayer() {
    _progressTimer?.cancel();
    if (_betterPlayerController != null) {
      _betterPlayerController!.removeEventsListener(_onBetterPlayerEvent);
      _betterPlayerController!.dispose(forceDispose: true);
      _betterPlayerController = null;
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _nextEpisodeTimer?.cancel();
    _removeOverlayEntry();
    _nextEpNotifier.dispose();
    // Save progress before disposing
    if (_betterPlayerController?.isVideoInitialized() == true) {
      _saveProgress();
    }
    if (_betterPlayerController != null) {
      _betterPlayerController!.removeEventsListener(_onBetterPlayerEvent);
      _betterPlayerController!.dispose(forceDispose: true);
      _betterPlayerController = null;
    }
    _focusNode.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  // ── Build ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final media = ref.watch(selectedMediaProvider);
    final shouldShowAppBar = _streamResult != null;

    return GestureDetector(
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: shouldShowAppBar
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(kToolbarHeight),
                  child: AppBar(
                    backgroundColor: Colors.black.withOpacity(0.7),
                    elevation: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          media?.title ?? media?.name ?? 'Playing',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Row(
                          children: [
                            if (media?.mediaType == 'tv')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: NivioTheme.netflixRed,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'S${widget.season} E$_currentEpisode',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                _streamResult!.provider.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    actions: [
                      if (media?.mediaType == 'tv')
                        IconButton(
                          icon: const Icon(Icons.list, color: Colors.white),
                          tooltip: 'Episodes',
                          onPressed: _showEpisodesBottomSheet,
                        ),
                      // Switch Server
                      PopupMenuButton<int>(
                        icon: const Icon(Icons.swap_horiz, color: Colors.white),
                        tooltip: 'Switch Server',
                        color: const Color(0xFF1F1F1F),
                        onSelected: (providerIndex) async {
                          if (providerIndex == _currentProviderIndex) return;

                          // Save current position before switching
                          await _saveProgress();

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Switching to ${StreamingService.getProviderName(providerIndex)}...',
                                ),
                                duration: const Duration(seconds: 2),
                                backgroundColor: NivioTheme.netflixRed,
                              ),
                            );
                          }

                          _disposePlayer();

                          setState(() {
                            _currentProviderIndex = providerIndex;
                            _isLoading = true;
                            _error = null;
                            _retryCount = 0;
                            _streamResult = null;
                          });

                          await _initializePlayer();
                        },
                        itemBuilder: (context) {
                          return List.generate(_maxProviders, (index) {
                            final isSelected = index == _currentProviderIndex;
                            return PopupMenuItem(
                              value: index,
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    color: isSelected
                                        ? NivioTheme.netflixRed
                                        : Colors.white70,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    StreamingService.getProviderName(index),
                                    style: TextStyle(
                                      color: isSelected
                                          ? NivioTheme.netflixRed
                                          : Colors.white,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  if (index == 0)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'HD',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          });
                        },
                      ),
                    ],
                  ),
                )
              : null,
          body: Stack(
            children: [
              Center(
                child: _isLoading
                    ? _buildLoadingState()
                    : _error != null
                    ? _buildErrorState()
                    : _streamResult != null && !_isDirectStream
                    ? _buildWebViewPlayer()
                    : _betterPlayerController != null
                    ? _buildVideoPlayer()
                    : _buildLoadingState(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── OverlayEntry management ─────────────────────────────────────
  void _showOverlayEntry() {
    _removeOverlayEntry();
    _nextEpOverlayEntry = OverlayEntry(
      builder: (_) => _NextEpisodeOverlayWidget(
        notifier: _nextEpNotifier,
        episode: _currentEpisode,
        season: widget.season,
        seasonData: _currentSeasonData,
        onPlay: () {
          _nextEpisodeTimer?.cancel();
          _playNextEpisode();
        },
        onDismiss: () {
          _nextEpisodeTimer?.cancel();
          _showNextEpisodeButton = false;
          _nextEpisodeDismissed = true;
          _nextEpNotifier.value = _NextEpState(show: false, countdown: null);
          _removeOverlayEntry();
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_nextEpOverlayEntry!);
  }

  void _removeOverlayEntry() {
    _nextEpOverlayEntry?.remove();
    _nextEpOverlayEntry = null;
  }

  // ── Loading state ───────────────────────────────────────────────
  Widget _buildLoadingState() {
    final media = ref.read(selectedMediaProvider);
    final posterPath = media?.posterPath;
    final title = media?.title ?? media?.name ?? '';

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Background poster with blur effect
          if (posterPath != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.15,
                child: CachedNetworkImage(
                  imageUrl: 'https://image.tmdb.org/t/p/w500$posterPath',
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          // Content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Netflix-style loading ring
                SizedBox(width: 56, height: 56, child: _NivioLoadingSpinner()),
                const SizedBox(height: 24),
                if (title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 8),
                if (media?.mediaType == 'tv')
                  Text(
                    'S${widget.season} E$_currentEpisode',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                const SizedBox(height: 16),
                // Provider pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: NivioTheme.netflixRed.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _currentProvider.isNotEmpty
                            ? _currentProvider
                            : StreamingService.getProviderName(
                                _currentProviderIndex,
                              ),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_retryCount > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Retry $_retryCount/$_maxRetries',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.withOpacity(0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Error state ─────────────────────────────────────────────────
  Widget _buildErrorState() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: NivioTheme.netflixRed.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline,
              color: NivioTheme.netflixRed,
              size: 64,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Failed to Load Stream',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              if (_currentProviderIndex < _maxProviders - 1)
                ElevatedButton.icon(
                  onPressed: () {
                    _disposePlayer();
                    setState(() {
                      _error = null;
                      _isLoading = true;
                      _currentProviderIndex++;
                      _retryCount = 0;
                      _streamResult = null;
                    });
                    _initializePlayer();
                  },
                  icon: const Icon(Icons.swap_horiz, size: 20),
                  label: const Text('SWITCH SERVER'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: () {
                  _disposePlayer();
                  setState(() {
                    _retryCount = 0;
                    _currentProviderIndex = 0;
                    _streamResult = null;
                  });
                  _initializePlayer();
                },
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('RETRY'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NivioTheme.netflixRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, size: 20),
                label: const Text('GO BACK'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54, width: 1.5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── WebView player (embed fallback) ─────────────────────────────
  Widget _buildWebViewPlayer() {
    return RepaintBoundary(
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: WebViewPlayer(
            key: ValueKey(_streamResult!.url),
            streamUrl: _streamResult!.url,
            title:
                ref.read(selectedMediaProvider)?.title ??
                ref.read(selectedMediaProvider)?.name ??
                'Video',
            onPlayerEvent: _handlePlayerEvent,
          ),
        ),
      ),
    );
  }

  // ── BetterPlayer widget ─────────────────────────────────────────
  Widget _buildVideoPlayer() {
    return RepaintBoundary(
      child: BetterPlayer(controller: _betterPlayerController!),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Redesigned Episode Picker with thumbnails and search
// ─────────────────────────────────────────────────────────────────
class _EpisodePickerSheet extends ConsumerStatefulWidget {
  final int mediaId;
  final int currentSeason;
  final int currentEpisode;
  final String? mediaType;

  const _EpisodePickerSheet({
    required this.mediaId,
    required this.currentSeason,
    required this.currentEpisode,
    this.mediaType,
  });

  @override
  ConsumerState<_EpisodePickerSheet> createState() =>
      _EpisodePickerSheetState();
}

class _EpisodePickerSheetState extends ConsumerState<_EpisodePickerSheet> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EpisodeData> _filterEpisodes(List<EpisodeData> episodes) {
    if (_searchQuery.isEmpty) return episodes;
    final query = _searchQuery.toLowerCase();
    return episodes.where((ep) {
      final name = ep.episodeName?.toLowerCase() ?? '';
      final num = ep.episodeNumber.toString();
      final overview = ep.overview?.toLowerCase() ?? '';
      return name.contains(query) ||
          num.contains(query) ||
          overview.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final seasonDataAsync = ref.watch(
          seasonDataProvider((
            showId: widget.mediaId,
            seasonNumber: widget.currentSeason,
          )),
        );

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF141414),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: seasonDataAsync.when(
            data: (seasonData) {
              final filtered = _filterEpisodes(seasonData.episodes);
              return Column(
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Season ${widget.currentSeason}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${seasonData.episodes.length} Episodes',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Search
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search episodes...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        prefixIcon: Icon(
                          Icons.search,
                          color: Colors.grey[500],
                          size: 20,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear,
                                  color: Colors.grey[500],
                                  size: 18,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Episode list
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  color: Colors.grey[600],
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No episodes match "$_searchQuery"',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final episode = filtered[index];
                              final isCurrent =
                                  episode.episodeNumber ==
                                  widget.currentEpisode;
                              final stillUrl = episode.stillPath != null
                                  ? 'https://image.tmdb.org/t/p/w300${episode.stillPath}'
                                  : '';

                              return GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);
                                  if (!isCurrent) {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                        builder: (context) => PlayerScreen(
                                          mediaId: widget.mediaId,
                                          season: widget.currentSeason,
                                          episode: episode.episodeNumber,
                                          mediaType: widget.mediaType,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? NivioTheme.netflixRed.withOpacity(
                                            0.15,
                                          )
                                        : const Color(0xFF1E1E1E),
                                    borderRadius: BorderRadius.circular(10),
                                    border: isCurrent
                                        ? Border.all(
                                            color: NivioTheme.netflixRed,
                                            width: 1.5,
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      // Thumbnail
                                      ClipRRect(
                                        borderRadius:
                                            const BorderRadius.horizontal(
                                              left: Radius.circular(10),
                                            ),
                                        child: SizedBox(
                                          width: 140,
                                          height: 80,
                                          child: stillUrl.isNotEmpty
                                              ? Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    CachedNetworkImage(
                                                      imageUrl: stillUrl,
                                                      fit: BoxFit.cover,
                                                      placeholder: (_, __) =>
                                                          Container(
                                                            color: Colors
                                                                .grey[900],
                                                          ),
                                                      errorWidget:
                                                          (
                                                            _,
                                                            __,
                                                            ___,
                                                          ) => Container(
                                                            color: Colors
                                                                .grey[900],
                                                            child: const Icon(
                                                              Icons.movie,
                                                              color: Colors
                                                                  .white24,
                                                              size: 28,
                                                            ),
                                                          ),
                                                    ),
                                                    Center(
                                                      child: Container(
                                                        width: 36,
                                                        height: 36,
                                                        decoration:
                                                            BoxDecoration(
                                                              color: Colors
                                                                  .black
                                                                  .withOpacity(
                                                                    0.6,
                                                                  ),
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                        child: Icon(
                                                          isCurrent
                                                              ? Icons.equalizer
                                                              : Icons
                                                                    .play_arrow,
                                                          color: isCurrent
                                                              ? NivioTheme
                                                                    .netflixRed
                                                              : Colors.white,
                                                          size: 20,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : Container(
                                                  color: Colors.grey[900],
                                                  child: const Icon(
                                                    Icons.movie,
                                                    color: Colors.white24,
                                                    size: 28,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      // Info
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  if (isCurrent)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      margin:
                                                          const EdgeInsets.only(
                                                            right: 6,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: NivioTheme
                                                            .netflixRed,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              3,
                                                            ),
                                                      ),
                                                      child: const Text(
                                                        'NOW',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  Expanded(
                                                    child: Text(
                                                      'E${episode.episodeNumber} · ${episode.episodeName ?? 'Episode ${episode.episodeNumber}'}',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: isCurrent
                                                            ? NivioTheme
                                                                  .netflixRed
                                                            : Colors.white,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              if (episode.runtime != null)
                                                Text(
                                                  '${episode.runtime} min',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[500],
                                                  ),
                                                ),
                                              if (episode.overview != null &&
                                                  episode.overview!.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 4,
                                                      ),
                                                  child: Text(
                                                    episode.overview!,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[500],
                                                      height: 1.3,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: NivioTheme.netflixRed),
            ),
            error: (error, stack) => const Center(
              child: Text(
                'Error loading episodes',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Helper class for next episode overlay state ──
class _NextEpState {
  final bool show;
  final int? countdown;

  const _NextEpState({required this.show, required this.countdown});
}

// ── Netflix-style loading spinner ──
class _NivioLoadingSpinner extends StatefulWidget {
  @override
  State<_NivioLoadingSpinner> createState() => _NivioLoadingSpinnerState();
}

class _NivioLoadingSpinnerState extends State<_NivioLoadingSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _SpinnerPainter(_controller.value),
          size: const Size(56, 56),
        );
      },
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final double progress;

  _SpinnerPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    // Track circle
    final trackPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, trackPaint);

    // Spinning arc
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [NivioTheme.netflixRed.withOpacity(0), NivioTheme.netflixRed],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      progress * math.pi * 2,
      math.pi * 1.5,
      false,
      arcPaint,
    );

    // Glowing dot at the leading edge
    final dotAngle = progress * math.pi * 2 + math.pi * 1.5;
    final dotX = center.dx + radius * math.cos(dotAngle);
    final dotY = center.dy + radius * math.sin(dotAngle);
    final dotPaint = Paint()
      ..color = NivioTheme.netflixRed
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(dotX, dotY), 3, dotPaint);
    canvas.drawCircle(Offset(dotX, dotY), 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ── Separate widget for the OverlayEntry (renders above everything) ──
class _NextEpisodeOverlayWidget extends StatelessWidget {
  final ValueNotifier<_NextEpState> notifier;
  final int episode;
  final int season;
  final SeasonData? seasonData;
  final VoidCallback onPlay;
  final VoidCallback onDismiss;

  const _NextEpisodeOverlayWidget({
    required this.notifier,
    required this.episode,
    required this.season,
    required this.seasonData,
    required this.onPlay,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_NextEpState>(
      valueListenable: notifier,
      builder: (context, state, _) {
        if (!state.show) return const SizedBox.shrink();

        final nextEpNum = episode + 1;
        EpisodeData? nextEpisode;
        if (seasonData != null) {
          nextEpisode = seasonData!.episodes
              .where((e) => e.episodeNumber == nextEpNum)
              .firstOrNull;
        }

        return Positioned(
          right: 16,
          bottom: 80,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 280,
                decoration: BoxDecoration(
                  color: const Color(0xFF181818),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24, width: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.8),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (nextEpisode?.stillPath != null)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: CachedNetworkImage(
                          imageUrl:
                              'https://image.tmdb.org/t/p/w300${nextEpisode!.stillPath}',
                          width: 280,
                          height: 120,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(height: 60, color: Colors.grey[900]),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UP NEXT',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            nextEpisode?.episodeName ?? 'Episode $nextEpNum',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'S$season E$nextEpNum',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: onPlay,
                                  icon: const Icon(Icons.play_arrow, size: 18),
                                  label: Text(
                                    state.countdown != null
                                        ? 'Play in ${state.countdown}s'
                                        : 'Play Now',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: onDismiss,
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(
                                    0.1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (state.countdown != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(
                                value: (state.countdown ?? 0) / 15,
                                backgroundColor: Colors.white12,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  NivioTheme.netflixRed,
                                ),
                                minHeight: 3,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
