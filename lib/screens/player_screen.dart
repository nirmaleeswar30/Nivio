import 'package:better_player_plus/better_player_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/season_info.dart';
import 'package:nivio/providers/media_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/providers/watch_party_provider.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/streaming_service.dart';
import 'package:nivio/services/watch_party/watch_party_models.dart';
import 'package:nivio/services/watch_party/watch_party_service_supabase.dart';
import 'package:nivio/widgets/webview_player.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'dart:async';
import 'dart:math' as math;

class PlayerScreen extends ConsumerStatefulWidget {
  final int mediaId;
  final int season;
  final int episode;
  final String? mediaType;
  final int? providerIndex;
  final String? watchPartyCode;
  final WatchPartyRole? watchPartyRole;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.season,
    required this.episode,
    this.mediaType,
    this.providerIndex,
    this.watchPartyCode,
    this.watchPartyRole,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const int _hlsCacheMaxSizeBytes = 512 * 1024 * 1024; // 512 MB
  static const int _hlsCacheMaxFileSizeBytes = 256 * 1024 * 1024; // 256 MB
  static const int _hlsPreCacheBytes = 8 * 1024 * 1024; // 8 MB
  static const List<String> _displayFitOrder = [
    'bestFit',
    'fitScreen',
    'fill',
    'none',
  ];
  static const Map<String, BoxFit> _displayFitOptions = {
    'bestFit': BoxFit.contain,
    'fitScreen': BoxFit.cover,
    'fill': BoxFit.fill,
    'none': BoxFit.none,
  };
  static const Map<String, String> _displayFitLabels = {
    'bestFit': 'Best Fit',
    'fitScreen': 'Fit Screen',
    'fill': 'Fill',
    'none': 'None',
  };

  BetterPlayerController? _betterPlayerController;
  StreamResult? _streamResult;
  bool _isLoading = true;
  String? _error;
  Timer? _progressTimer;
  String _currentProvider = '';
  int _retryCount = 0;
  int _currentProviderIndex = 0;
  static const int _maxRetries = 3;
  final FocusNode _focusNode = FocusNode();
  bool _showNextEpisodeButton = false;
  bool _nextEpisodeDismissed = false;
  Timer? _nextEpisodeTimer;
  int? _nextEpisodeCountdown;
  bool _isDirectStream = false;
  Duration? _resumePosition;
  int _currentEpisode = 0;
  bool _isInFullscreen = false;
  bool _arePlayerControlsVisible = true;
  bool _autoFullscreenTriggeredForCurrentLoad = false;
  String? _openTopActionMenuId;
  String _selectedDisplayFitKey = 'bestFit';
  final ValueNotifier<bool> _fullscreenTopBarVisibleNotifier = ValueNotifier(
    false,
  );
  OverlayEntry? _fullscreenTopBarOverlayEntry;

  // Notifier so overlay updates inside BetterPlayer fullscreen
  final ValueNotifier<_NextEpState> _nextEpNotifier = ValueNotifier(
    _NextEpState(show: false, countdown: null),
  );
  OverlayEntry? _nextEpOverlayEntry;

  SeasonData? _currentSeasonData;
  WatchPartyServiceSupabase? _watchPartyService;
  WatchPartySession? _watchPartySession;
  StreamSubscription<WatchPartyPlaybackState>? _watchPartyPlaybackSub;
  StreamSubscription<WatchPartySession?>? _watchPartySessionSub;
  StreamSubscription<String>? _watchPartyErrorSub;
  Timer? _watchPartyHostSyncTimer;
  WatchPartyPlaybackState? _pendingWatchPartyPlayback;
  bool _isApplyingWatchPartyState = false;
  DateTime? _lastWatchPartyBroadcastAt;
  bool _isPartyRouteSyncInFlight = false;

  static const Duration _watchPartyHostProgressInterval = Duration(
    milliseconds: 1800,
  );
  static const Duration _watchPartyHostPeriodicSyncInterval = Duration(
    seconds: 3,
  );
  static const int _watchPartyDriftThresholdMs = 1200;

  bool _isAnimeMedia(SearchResult? media) {
    if (media == null) return false;
    final language = (media.originalLanguage ?? '').toLowerCase();
    return media.mediaType == 'tv' && language == 'ja';
  }

  int get _maxProviders {
    final media = ref.read(selectedMediaProvider);
    return StreamingService.totalProvidersFor(isAnime: _isAnimeMedia(media));
  }

  @override
  void initState() {
    super.initState();
    _currentEpisode = widget.episode;
    _currentProviderIndex = math.max(0, widget.providerIndex ?? 0);
    _initializeWatchParty();
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

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Keyboard shortcuts ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
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

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Player initialization ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
  Future<void> _initializePlayer() async {
    _autoFullscreenTriggeredForCurrentLoad = false;
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
          } catch (_) {
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
      final net22AudioPref = ref.read(net22AudioLanguageProvider);

      final result = await streamingService.fetchStreamUrl(
        media: media,
        season: widget.season,
        episode: _currentEpisode,
        preferredQuality: preferredQuality,
        preferredNet22Audio: net22AudioPref,
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
      _isDirectStream = StreamingService.isDirectStream(
        _currentProviderIndex,
        isAnime: _isAnimeMedia(media),
      );

      // Embed providers use WebView
      if (!_isDirectStream) {
        setState(() {
          _isLoading = false;
          _retryCount = 0;
        });
        _updateWatchPartyHostSyncTimer();
        return;
      }

      // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Check watch history for resume ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
      final historyService = ref.read(watchHistoryServiceProvider);
      await historyService.init();
      final history = await historyService.getHistory(widget.mediaId);
      Duration? startAt;

      if (history != null &&
          history.currentSeason == widget.season &&
          history.currentEpisode == _currentEpisode &&
          history.lastPositionSeconds > 0 &&
          history.totalDurationSeconds > 0 &&
          history.lastPositionSeconds < history.totalDurationSeconds - 30) {
        final cappedResumeUpperBound = math.max(
          0,
          history.totalDurationSeconds - 45,
        );
        final safeResumeSeconds = math.min(
          math.max(0, history.lastPositionSeconds - 3),
          cappedResumeUpperBound,
        );
        if (safeResumeSeconds > 0) {
          startAt = Duration(seconds: safeResumeSeconds);
        }
        _resumePosition = startAt;
      }

      // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Build subtitle sources ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
      final subtitleSources = result.subtitles.map((sub) {
        return BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.network,
          name: sub.lang,
          urls: [sub.url],
        );
      }).toList();

      // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Build resolutions map for non-HLS multi-quality ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
      Map<String, String>? resolutions;
      if (result.sources.length > 1) {
        resolutions = {};
        for (final source in result.sources) {
          final label = _normalizeQualityLabel(source.quality);
          if (label.isEmpty) continue;
          resolutions[label] = source.url;
        }
        if (resolutions.length < 2) {
          resolutions = null;
        }
      }
      final hasResolutionMap = resolutions != null && resolutions.isNotEmpty;
      final cacheConfiguration = _buildCacheConfiguration(result);

      // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Headers ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
      final headers = _buildPlaybackHeaders(result.headers);

      // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Data source ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        result.url,
        headers: headers,
        videoFormat: result.isM3U8
            ? BetterPlayerVideoFormat.hls
            : BetterPlayerVideoFormat.other,
        useAsmsTracks: result.isM3U8 && !hasResolutionMap,
        useAsmsSubtitles: result.isM3U8 && !hasResolutionMap,
        useAsmsAudioTracks: result.isM3U8,
        subtitles: subtitleSources.isNotEmpty ? subtitleSources : null,
        resolutions: resolutions,
        cacheConfiguration: cacheConfiguration,
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 120000,
          maxBufferMs: 300000,
          bufferForPlaybackMs: 2500,
          bufferForPlaybackAfterRebufferMs: 10000,
        ),
      );

      // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Controller config ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
      _betterPlayerController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true,
          looping: false,
          fullScreenByDefault: false,
          fit: _displayFitOptions[_selectedDisplayFitKey] ?? BoxFit.contain,
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
            progressBarPlayedColor: NivioTheme.accentColorOf(context),
            progressBarHandleColor: NivioTheme.accentColorOf(context),
            progressBarBufferedColor: NivioTheme.netflixLightGrey,
            progressBarBackgroundColor: NivioTheme.netflixGrey,
            controlBarColor: const Color(0xFF111111),
            enableControlsBackdrop: true,
            controlsBackdropColor: const Color(0xE6000000),
            controlsBackdropTopHeight: 120,
            controlsBackdropBottomHeight: 260,
            loadingColor: NivioTheme.accentColorOf(context),
            overflowModalColor: const Color(0xFF1F1F1F),
            overflowModalTextColor: Colors.white,
            overflowMenuIconsColor: Colors.white70,
            playerTheme: BetterPlayerTheme.material,
            overflowMenuCustomItems: [
              if (_isDirectStream)
                BetterPlayerOverflowMenuItem(
                  Icons.aspect_ratio,
                  'Display',
                  _showDisplaySelectionBottomSheet,
                ),
              if (media.mediaType == 'tv')
                BetterPlayerOverflowMenuItem(
                  Icons.list,
                  'Episodes',
                  _showEpisodesBottomSheet,
                ),
            ],
          ),
          placeholder: Container(
            color: Colors.black,
            child: Center(
              child: CircularProgressIndicator(
                color: NivioTheme.accentColorOf(context),
              ),
            ),
          ),
          errorBuilder: (context, errorMessage) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: NivioTheme.accentColorOf(context),
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
                    icon: Icon(Icons.refresh),
                    label: Text('Retry ($_retryCount/$_maxRetries)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NivioTheme.accentColorOf(context),
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
      _applyDisplaySettings(refreshUi: false);

      // Show the player immediately ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â BetterPlayer handles its own buffering UI
      setState(() {
        _isLoading = false;
        _retryCount = 0;
      });

      await _betterPlayerController!.setupDataSource(dataSource);

      // Start progress tracking timer
      _startProgressTracking();
      _updateWatchPartyHostSyncTimer();
      _scheduleWatchPartyBootstrapSyncs();
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

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ BetterPlayer event listener ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
  Map<String, String> _buildPlaybackHeaders(Map<String, String> incoming) {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      ...incoming,
    };
    bool hasHeader(String name) =>
        headers.keys.any((k) => k.toLowerCase() == name.toLowerCase());
    void setIfMissing(String name, String value) {
      if (!hasHeader(name)) headers[name] = value;
    }

    String? referer;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'referer') {
        referer = entry.value;
        break;
      }
    }

    final hasOrigin = headers.keys.any((k) => k.toLowerCase() == 'origin');
    if (!hasOrigin && referer != null && referer.isNotEmpty) {
      final refUri = Uri.tryParse(referer);
      if (refUri != null &&
          refUri.scheme.isNotEmpty &&
          refUri.host.isNotEmpty) {
        headers['Origin'] = '${refUri.scheme}://${refUri.host}';
      }
    }

    final provider = (_streamResult?.provider ?? '').toLowerCase();
    if (provider.contains('animepahe')) {
      setIfMissing('Referer', 'https://animepahe.ru/');
      setIfMissing('Origin', 'https://animepahe.ru');
    }

    setIfMissing('Accept', '*/*');
    setIfMissing('Accept-Language', 'en-US,en;q=0.9');
    return headers;
  }

  BetterPlayerCacheConfiguration? _buildCacheConfiguration(
    StreamResult result,
  ) {
    // Cache HLS segment playback for better seek/replay performance.
    if (!_isDirectStream || !result.isM3U8) return null;

    return const BetterPlayerCacheConfiguration(
      useCache: true,
      maxCacheSize: _hlsCacheMaxSizeBytes,
      maxCacheFileSize: _hlsCacheMaxFileSizeBytes,
      preCacheSize: _hlsPreCacheBytes,
    );
  }

  void _onBetterPlayerEvent(BetterPlayerEvent event) {
    if (!mounted) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        // Set playback speed after initialization
        final speed = ref.read(playbackSpeedProvider);
        _betterPlayerController?.setSpeed(speed);
        _applyDisplaySettings(refreshUi: false);
        _maybeAutoEnterFullscreenOnce();
        // Refresh action menus after ASMS tracks are parsed.
        setState(() {});
        // Show resume snackbar
        if (_resumePosition != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Resumed from ${_formatDuration(_resumePosition!)}',
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: NivioTheme.accentColorOf(context),
            ),
          );
          _resumePosition = null;
        }
        if (_pendingWatchPartyPlayback != null) {
          final pending = _pendingWatchPartyPlayback!;
          _pendingWatchPartyPlayback = null;
          unawaited(_applyWatchPartyPlayback(pending));
        }
        unawaited(_broadcastWatchPartyPlayback(force: true));
        break;
      case BetterPlayerEventType.play:
        unawaited(_broadcastWatchPartyPlayback(force: true));
        break;
      case BetterPlayerEventType.pause:
        unawaited(_broadcastWatchPartyPlayback(force: true));
        break;
      case BetterPlayerEventType.seekTo:
        // Post-seek nudge disabled: rely on native/player handling.
        unawaited(_broadcastWatchPartyPlayback(force: true));
        break;
      case BetterPlayerEventType.bufferingStart:
        break;
      case BetterPlayerEventType.bufferingEnd:
        break;
      case BetterPlayerEventType.openFullscreen:
        setState(() {
          _isInFullscreen = true;
          _arePlayerControlsVisible = true;
        });
        _syncFullscreenTopBarVisibility();
        break;
      case BetterPlayerEventType.hideFullscreen:
        setState(() {
          _isInFullscreen = false;
        });
        _syncFullscreenTopBarVisibility();
        break;
      case BetterPlayerEventType.controlsVisible:
        setState(() => _arePlayerControlsVisible = true);
        _syncFullscreenTopBarVisibility();
        break;
      case BetterPlayerEventType.controlsHiddenEnd:
        setState(() => _arePlayerControlsVisible = false);
        _syncFullscreenTopBarVisibility();
        break;
      case BetterPlayerEventType.progress:
        _checkNextEpisode();
        unawaited(_broadcastWatchPartyPlayback(force: false));
        break;
      case BetterPlayerEventType.exception:
        // Post-seek nudge disabled: no forced retryDataSource/re-seek.
        break;
      case BetterPlayerEventType.finished:
        _markAsCompleted();
        if (_hasNextEpisode()) _showNextEpisodePopup();
        break;
      default:
        break;
    }
  }

  bool get _hasWatchPartyContext {
    return _resolvedWatchPartyCode != null && _resolvedWatchPartyRole != null;
  }

  bool get _hasActiveWatchPartySession {
    final service = _watchPartyService ?? ref.read(watchPartyServiceProvider);
    return service?.isInSession == true;
  }

  String? get _resolvedWatchPartyCode {
    final fromRoute = (widget.watchPartyCode ?? '').trim();
    if (fromRoute.isNotEmpty) return fromRoute.toUpperCase();

    final service = _watchPartyService ?? ref.read(watchPartyServiceProvider);
    final fromService = (service?.sessionCode ?? '').trim();
    if (service?.isInSession == true && fromService.isNotEmpty) {
      return fromService.toUpperCase();
    }
    return null;
  }

  WatchPartyRole? get _resolvedWatchPartyRole {
    final fromRoute = widget.watchPartyRole;
    if (fromRoute != null) return fromRoute;

    final service = _watchPartyService ?? ref.read(watchPartyServiceProvider);
    if (service?.isInSession != true) return null;
    return service!.isHost ? WatchPartyRole.host : WatchPartyRole.participant;
  }

  void _initializeWatchParty() {
    if (!_hasWatchPartyContext && !_hasActiveWatchPartySession) return;
    unawaited(_initializeWatchPartyInternal());
  }

  Future<void> _initializeWatchPartyInternal() async {
    final service = ref.read(watchPartyServiceProvider);
    if (service == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Watch Party unavailable. Configure SUPABASE_URL and SUPABASE_ANON_KEY.',
          ),
        ),
      );
      return;
    }

    _watchPartyService = service;
    _watchPartyPlaybackSub ??= service.playbackStream.listen((playback) {
      if ((!_hasWatchPartyContext && !service.isInSession) || service.isHost) {
        return;
      }
      unawaited(_applyWatchPartyPlayback(playback));
    });
    _watchPartySessionSub ??= service.sessionStream.listen((session) {
      if (!mounted) return;
      setState(() {
        _watchPartySession = session;
      });
      _updateWatchPartyHostSyncTimer();
    });
    _watchPartyErrorSub ??= service.errorStream.listen((message) {
      if (!mounted || message.trim().isEmpty) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message.trim())));
    });

    final targetCode = _resolvedWatchPartyCode;
    final targetRole = _resolvedWatchPartyRole;
    if (targetCode == null || targetRole == null) return;

    final existingCode = service.currentSession?.sessionCode.toUpperCase();

    bool ok = true;
    if (existingCode != targetCode) {
      if (targetRole == WatchPartyRole.host) {
        final created = await service.createSession(preferredCode: targetCode);
        ok = created != null;
      } else {
        ok = await service.joinSession(targetCode);
      }
    }
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to connect to watch party')),
      );
      return;
    }

    setState(() {
      _watchPartySession = service.currentSession;
    });
    _updateWatchPartyHostSyncTimer();
    _scheduleWatchPartyBootstrapSyncs();

    if (!service.isHost) {
      unawaited(service.requestStateSync(reason: 'player_opened'));
    }
  }

  void _scheduleWatchPartyBootstrapSyncs() {
    if (_watchPartyService?.isInSession != true ||
        _watchPartyService?.isHost != true) {
      return;
    }

    unawaited(_broadcastWatchPartyPlayback(force: true));
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      unawaited(_broadcastWatchPartyPlayback(force: true));
    });
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      unawaited(_broadcastWatchPartyPlayback(force: true));
    });
  }

  void _updateWatchPartyHostSyncTimer() {
    final shouldSync =
        _watchPartyService?.isInSession == true &&
        _watchPartyService?.isHost == true &&
        _isDirectStream;
    if (!shouldSync) {
      _watchPartyHostSyncTimer?.cancel();
      _watchPartyHostSyncTimer = null;
      return;
    }
    if (_watchPartyHostSyncTimer != null) return;
    _watchPartyHostSyncTimer = Timer.periodic(
      _watchPartyHostPeriodicSyncInterval,
      (_) => unawaited(_broadcastWatchPartyPlayback(force: true)),
    );
  }

  Future<void> _broadcastWatchPartyPlayback({required bool force}) async {
    final service = _watchPartyService;
    if (service == null ||
        !service.isHost ||
        _isApplyingWatchPartyState ||
        !_isDirectStream ||
        _betterPlayerController?.isVideoInitialized() != true) {
      return;
    }

    final now = DateTime.now();
    if (!force &&
        _lastWatchPartyBroadcastAt != null &&
        now.difference(_lastWatchPartyBroadcastAt!) <
            _watchPartyHostProgressInterval) {
      return;
    }

    final controller = _betterPlayerController!;
    final vpc = controller.videoPlayerController!;
    final mediaType = _resolvedWatchPartyMediaType();

    await service.syncPlayback(
      mediaId: widget.mediaId,
      mediaType: mediaType,
      providerIndex: _currentProviderIndex,
      season: widget.season,
      episode: _currentEpisode,
      positionMs: vpc.value.position.inMilliseconds,
      isPlaying: controller.isPlaying() == true,
    );
    _lastWatchPartyBroadcastAt = now;
  }

  Future<void> _broadcastWatchPartyPlaybackFromWebView({
    required int positionMs,
    required bool isPlaying,
    required bool force,
  }) async {
    final service = _watchPartyService;
    if (service == null || !service.isHost || _isApplyingWatchPartyState) {
      return;
    }

    final now = DateTime.now();
    if (!force &&
        _lastWatchPartyBroadcastAt != null &&
        now.difference(_lastWatchPartyBroadcastAt!) <
            _watchPartyHostProgressInterval) {
      return;
    }

    await service.syncPlayback(
      mediaId: widget.mediaId,
      mediaType: _resolvedWatchPartyMediaType(),
      providerIndex: _currentProviderIndex,
      season: widget.season,
      episode: _currentEpisode,
      positionMs: math.max(0, positionMs),
      isPlaying: isPlaying,
    );
    _lastWatchPartyBroadcastAt = now;
  }

  String _resolvedWatchPartyMediaType() {
    final fromWidget = (widget.mediaType ?? '').trim();
    if (fromWidget.isNotEmpty) return fromWidget;
    final fromSelected = (ref.read(selectedMediaProvider)?.mediaType ?? '')
        .trim();
    if (fromSelected.isNotEmpty) return fromSelected;
    return 'movie';
  }

  Future<void> _applyWatchPartyPlayback(
    WatchPartyPlaybackState playback,
  ) async {
    if (!mounted || _watchPartyService?.isHost == true) return;

    if (playback.mediaId != widget.mediaId) {
      _syncRouteToWatchPartyPlayback(playback);
      return;
    }

    if (playback.season != widget.season ||
        playback.episode != _currentEpisode) {
      _syncRouteToWatchPartyPlayback(playback);
      return;
    }

    if (!_isDirectStream) return;

    if (_betterPlayerController?.isVideoInitialized() != true) {
      _pendingWatchPartyPlayback = playback;
      return;
    }
    if (_isApplyingWatchPartyState) return;

    _isApplyingWatchPartyState = true;
    try {
      final controller = _betterPlayerController!;
      final vpc = controller.videoPlayerController!;
      final expectedMs = playback.expectedPositionMs;
      final currentMs = vpc.value.position.inMilliseconds;
      final driftMs = (currentMs - expectedMs).abs();

      if (driftMs > _watchPartyDriftThresholdMs) {
        await controller.seekTo(
          Duration(milliseconds: math.max(0, expectedMs)),
        );
      }

      final localIsPlaying = controller.isPlaying() == true;
      if (playback.isPlaying && !localIsPlaying) {
        await controller.play();
      } else if (!playback.isPlaying && localIsPlaying) {
        await controller.pause();
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 350), () {
        _isApplyingWatchPartyState = false;
      });
    }
  }

  void _syncRouteToWatchPartyPlayback(WatchPartyPlaybackState playback) {
    if (_isPartyRouteSyncInFlight || !mounted) return;
    _isPartyRouteSyncInFlight = true;

    final playbackType = playback.mediaType.trim().isNotEmpty
        ? playback.mediaType.trim()
        : (widget.mediaType ?? 'movie');

    final query = <String, String>{
      'season': '${playback.season}',
      'episode': '${playback.episode}',
      if (playbackType.isNotEmpty) 'type': playbackType,
      if (playback.providerIndex != null)
        'provider': '${math.max(0, playback.providerIndex!)}',
      if (_resolvedWatchPartyCode != null)
        'partyCode': _resolvedWatchPartyCode!,
      if (_resolvedWatchPartyRole != null)
        'partyRole': _resolvedWatchPartyRole!.queryValue,
    };

    context.pushReplacement(
      Uri(
        path: '/player/${playback.mediaId}',
        queryParameters: query,
      ).toString(),
    );
  }

  Future<void> _showWatchPartyDetailsSheet() async {
    final service = _watchPartyService;
    final session = _watchPartySession;
    if (service == null || session == null || !mounted) return;

    final shouldLeave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.8;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ColoredBox(
              color: const Color(0xFF141414),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Watch Party ${session.sessionCode}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '${session.participantCount} participants',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: session.participants.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        if (index == session.participants.length) {
                          return ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            tileColor: Colors.red.withValues(alpha: 0.12),
                            leading: const Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                            ),
                            title: Text(
                              service.isHost
                                  ? 'End Watch Party'
                                  : 'Leave Watch Party',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () => Navigator.pop(sheetContext, true),
                          );
                        }

                        final participant = session.participants[index];
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          tileColor: Colors.white.withValues(alpha: 0.05),
                          leading: _buildWatchPartyAvatar(participant),
                          title: Text(
                            participant.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: participant.isHost
                              ? const Text(
                                  'Host',
                                  style: TextStyle(color: Colors.white70),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (shouldLeave != true || !mounted) return;
    if (service.isHost) {
      await service.endSession();
    } else {
      await service.leaveSession();
    }
    if (!mounted) return;
    setState(() {
      _watchPartySession = null;
    });
    _watchPartyHostSyncTimer?.cancel();
    _watchPartyHostSyncTimer = null;
  }

  Widget _buildWatchPartyAvatar(WatchPartyParticipant participant) {
    final initials = _participantInitials(participant.name);
    final photoUrl = (participant.photoUrl ?? '').trim();
    if (photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.white12,
        backgroundImage: NetworkImage(photoUrl),
      );
    }

    return CircleAvatar(
      radius: 18,
      backgroundColor: participant.isHost
          ? NivioTheme.accentColorOf(context).withValues(alpha: 0.35)
          : Colors.white12,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _participantInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  void _maybeAutoEnterFullscreenOnce() {
    if (_autoFullscreenTriggeredForCurrentLoad) return;
    if (!_isDirectStream || _betterPlayerController == null) return;
    if (_betterPlayerController!.isFullScreen) return;

    _autoFullscreenTriggeredForCurrentLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _betterPlayerController == null) return;
      if (_betterPlayerController!.isFullScreen) return;
      _betterPlayerController!.enterFullScreen();
    });
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

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Season data fetch ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
  Future<void> _fetchSeasonData() async {
    try {
      final tmdbService = ref.read(tmdbServiceProvider);
      _currentSeasonData = await tmdbService.getSeasonInfo(
        widget.mediaId,
        widget.season,
      );
    } catch (_) {}
  }

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Next episode popup ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
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

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ WebView event handler ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
  void _handlePlayerEvent(String event, double currentTime, double duration) {
    final media = ref.read(selectedMediaProvider);
    if (media == null) return;
    switch (event) {
      case 'time':
        _saveWebViewProgress(currentTime, duration);
        unawaited(
          _broadcastWatchPartyPlaybackFromWebView(
            positionMs: (currentTime * 1000).round(),
            isPlaying: true,
            force: false,
          ),
        );
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
        unawaited(
          _broadcastWatchPartyPlaybackFromWebView(
            positionMs: ((duration > 0 ? duration : currentTime) * 1000)
                .round(),
            isPlaying: false,
            force: true,
          ),
        );
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
        watchPartyCode: widget.watchPartyCode,
        watchPartyRole: widget.watchPartyRole,
      ),
    );
  }

  Future<void> _switchToProvider(int providerIndex) async {
    if (providerIndex == _currentProviderIndex) return;

    await _saveProgress();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Switching to ${_providerSelectorLabel(providerIndex)}...',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: NivioTheme.accentColorOf(context),
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
  }

  String _providerSelectorLabel(int index) {
    final media = ref.read(selectedMediaProvider);
    return StreamingService.getProviderName(
      index,
      isAnime: _isAnimeMedia(media),
    );
  }

  String _normalizeQualityLabel(String value) {
    final v = value.toLowerCase().trim();
    if (v.isEmpty) return '';
    if (v == 'default' || v == 'auto') return 'auto';

    final pMatch = RegExp(r'(\d{3,4})p').firstMatch(v);
    if (pMatch != null) return '${pMatch.group(1)}p';

    final rawNumber = RegExp(r'\b(\d{3,4})\b').firstMatch(v);
    if (rawNumber != null) return '${rawNumber.group(1)}p';

    return value;
  }

  int _qualityScore(String quality) {
    final normalized = _normalizeQualityLabel(quality);
    if (normalized == 'auto') return -1;
    final match = RegExp(r'(\d{3,4})p').firstMatch(normalized);
    if (match != null) return int.tryParse(match.group(1)!) ?? 0;
    return 0;
  }

  List<String> _buildQualityOptions() {
    final stream = _streamResult;
    if (stream == null) return const [];

    final options = <String>{};
    for (final quality in stream.availableQualities) {
      final normalized = _normalizeQualityLabel(quality);
      if (normalized.isNotEmpty) options.add(normalized);
    }
    for (final source in stream.sources) {
      final normalized = _normalizeQualityLabel(source.quality);
      if (normalized.isNotEmpty) options.add(normalized);
    }
    if (options.isEmpty) {
      final fallback = _normalizeQualityLabel(stream.quality);
      if (fallback.isNotEmpty) options.add(fallback);
    }

    options.add('auto');

    final ordered = options.toList()
      ..sort((a, b) => _qualityScore(b).compareTo(_qualityScore(a)));
    return ordered;
  }

  List<PopupMenuEntry<String>> _buildQualityMenuItems() {
    final selectedRaw =
        ref.read(selectedQualityProvider) ?? _streamResult?.quality ?? 'auto';
    final selected = _normalizeQualityLabel(selectedRaw);

    return _buildQualityOptions().map((quality) {
      final isSelected = quality == selected;
      return PopupMenuItem<String>(
        value: quality,
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected
                  ? NivioTheme.accentColorOf(context)
                  : Colors.white70,
              size: 18,
            ),
            const SizedBox(width: 12),
            Text(
              quality.toUpperCase(),
              style: TextStyle(
                color: isSelected
                    ? NivioTheme.accentColorOf(context)
                    : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  double _resolvedVideoAspectRatio() {
    final ratio =
        _betterPlayerController?.videoPlayerController?.value.aspectRatio;
    if (ratio != null && ratio > 0 && ratio.isFinite && !ratio.isNaN) {
      return ratio;
    }
    return 16 / 9;
  }

  void _applyDisplaySettings({bool refreshUi = true}) {
    final controller = _betterPlayerController;
    if (controller == null) return;
    // Apply aspect ratio first, then fit (fit emits refresh event in BetterPlayer).
    controller.setOverriddenAspectRatio(_resolvedVideoAspectRatio());
    controller.setOverriddenFit(
      _displayFitOptions[_selectedDisplayFitKey] ?? BoxFit.contain,
    );
    if (refreshUi && mounted) {
      setState(() {});
    }
  }

  List<PopupMenuEntry<String>> _buildDisplayMenuItems() {
    return _displayFitOrder.map((fitKey) {
      final isSelected = fitKey == _selectedDisplayFitKey;
      final label = _displayFitLabels[fitKey] ?? fitKey;
      return PopupMenuItem<String>(
        value: fitKey,
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected
                  ? NivioTheme.accentColorOf(context)
                  : Colors.white70,
              size: 18,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? NivioTheme.accentColorOf(context)
                    : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  void _showDisplaySelectionBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: ColoredBox(
            color: const Color(0xFF1F1F1F),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 6, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Display',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                ..._displayFitOrder.map((fitKey) {
                  final selected = fitKey == _selectedDisplayFitKey;
                  final label = _displayFitLabels[fitKey] ?? fitKey;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tileColor: selected
                          ? NivioTheme.accentColorOf(
                              context,
                            ).withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.05),
                      leading: Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        color: selected
                            ? NivioTheme.accentColorOf(context)
                            : Colors.white70,
                      ),
                      title: Text(
                        label,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _switchDisplayMode(fitKey);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _switchDisplayMode(String value) {
    if (!_displayFitOptions.containsKey(value)) return;
    if (value == _selectedDisplayFitKey) return;
    _selectedDisplayFitKey = value;
    _applyDisplaySettings();
  }

  Future<void> _switchQuality(String quality) async {
    final normalizedTarget = _normalizeQualityLabel(quality);
    final currentRaw =
        ref.read(selectedQualityProvider) ?? _streamResult?.quality ?? 'auto';
    final normalizedCurrent = _normalizeQualityLabel(currentRaw);
    if (normalizedTarget == normalizedCurrent) return;

    final currentPosition =
        _betterPlayerController?.videoPlayerController?.value.position;
    await _saveProgress();

    ref.read(selectedQualityProvider.notifier).state =
        normalizedTarget == 'auto' ? null : normalizedTarget;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Switching quality to ${normalizedTarget.toUpperCase()}',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: NivioTheme.accentColorOf(context),
        ),
      );
    }

    _disposePlayer();

    setState(() {
      _isLoading = true;
      _error = null;
      _retryCount = 0;
      _streamResult = null;
    });

    await _initializePlayer();

    if (!mounted ||
        currentPosition == null ||
        _betterPlayerController?.isVideoInitialized() != true) {
      return;
    }
    await _betterPlayerController!.seekTo(currentPosition);
    await _betterPlayerController!.play();
  }

  bool _isAimiAnimeStream() {
    final provider = (_streamResult?.provider ?? '').toLowerCase();
    if (!_isDirectStream || provider.isEmpty) return false;
    return provider.startsWith('aimi-') ||
        provider.contains('animepahe') ||
        provider.contains('allanime') ||
        provider.contains('anizone');
  }

  bool _isNet22DirectStream() {
    final provider = (_streamResult?.provider ?? '').toLowerCase();
    if (!_isDirectStream || provider.isEmpty) return false;
    return provider.contains('net22');
  }

  static const Map<String, String> _net22AudioAliasToCode = {
    'english': 'eng',
    'eng': 'eng',
    'en': 'eng',
    'hindi': 'hin',
    'hin': 'hin',
    'hi': 'hin',
    'tamil': 'tam',
    'tam': 'tam',
    'ta': 'tam',
    'telugu': 'tel',
    'tel': 'tel',
    'te': 'tel',
    'malayalam': 'mal',
    'mal': 'mal',
    'ml': 'mal',
    'kannada': 'kan',
    'kan': 'kan',
    'kn': 'kan',
    'japanese': 'jpn',
    'jpn': 'jpn',
    'ja': 'jpn',
    'korean': 'kor',
    'kor': 'kor',
    'ko': 'kor',
    'chinese': 'chi',
    'chi': 'chi',
    'zho': 'chi',
    'zh': 'chi',
    'spanish': 'spa',
    'spa': 'spa',
    'es': 'spa',
    'french': 'fre',
    'fre': 'fre',
    'fra': 'fre',
    'fr': 'fre',
    'german': 'ger',
    'ger': 'ger',
    'deu': 'ger',
    'de': 'ger',
    'italian': 'ita',
    'ita': 'ita',
    'it': 'ita',
    'portuguese': 'por',
    'por': 'por',
    'pt': 'por',
    'arabic': 'ara',
    'ara': 'ara',
    'ar': 'ara',
    'russian': 'rus',
    'rus': 'rus',
    'ru': 'rus',
    'bengali': 'ben',
    'ben': 'ben',
    'bn': 'ben',
    'marathi': 'mar',
    'mar': 'mar',
    'mr': 'mar',
    'urdu': 'urd',
    'urd': 'urd',
    'ur': 'urd',
  };

  static const Map<String, String> _net22AudioCodeToName = {
    'eng': 'English',
    'hin': 'Hindi',
    'tam': 'Tamil',
    'tel': 'Telugu',
    'mal': 'Malayalam',
    'kan': 'Kannada',
    'jpn': 'Japanese',
    'kor': 'Korean',
    'chi': 'Chinese',
    'spa': 'Spanish',
    'fre': 'French',
    'ger': 'German',
    'ita': 'Italian',
    'por': 'Portuguese',
    'ara': 'Arabic',
    'rus': 'Russian',
    'ben': 'Bengali',
    'mar': 'Marathi',
    'urd': 'Urdu',
  };

  String _normalizeNet22AudioToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _canonicalNet22AudioValue(String value) {
    final token = _normalizeNet22AudioToken(value.trim());
    if (token.isEmpty) return '';
    final alias = _net22AudioAliasToCode[token];
    if (alias != null && alias.isNotEmpty) return alias;
    return token;
  }

  String _titleCaseNet22Audio(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[_-]+'), ' ');
    if (cleaned.isEmpty) return '';
    return cleaned
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) {
          final lower = part.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  String _net22AudioDisplayLabel(
    String canonical, {
    String? rawValue,
    BetterPlayerAsmsAudioTrack? track,
  }) {
    final code = canonical.trim().toLowerCase();
    if (code.isEmpty) return 'Unknown';

    final knownName = _net22AudioCodeToName[code];
    if (knownName != null) {
      return '$knownName ($code)';
    }

    final raw = (rawValue ?? '').trim();
    if (raw.isNotEmpty) {
      final rawPretty = _titleCaseNet22Audio(raw);
      if (rawPretty.isNotEmpty &&
          _normalizeNet22AudioToken(rawPretty) !=
              _normalizeNet22AudioToken(code)) {
        return '$rawPretty ($code)';
      }
      if (rawPretty.isNotEmpty) return rawPretty;
    }

    final trackLanguage = (track?.language ?? '').trim();
    if (trackLanguage.isNotEmpty) {
      final pretty = _titleCaseNet22Audio(trackLanguage);
      if (pretty.isNotEmpty &&
          _normalizeNet22AudioToken(pretty) !=
              _normalizeNet22AudioToken(code)) {
        return '$pretty ($code)';
      }
      if (pretty.isNotEmpty) return pretty;
    }

    final trackLabel = (track?.label ?? '').trim();
    if (trackLabel.isNotEmpty) {
      final pretty = _titleCaseNet22Audio(trackLabel);
      if (pretty.isNotEmpty &&
          _normalizeNet22AudioToken(pretty) !=
              _normalizeNet22AudioToken(code)) {
        return '$pretty ($code)';
      }
      if (pretty.isNotEmpty) return pretty;
    }

    return code.toUpperCase();
  }

  Map<String, String> _buildNet22AudioOptions() {
    final options = <String, String>{};
    final tracks = _net22AsmsAudioTrackMap();

    void addOption(String raw, {BetterPlayerAsmsAudioTrack? track}) {
      final value = raw.trim();
      if (value.isEmpty) return;
      final canonical = _canonicalNet22AudioValue(value);
      if (canonical.isEmpty) return;
      options.putIfAbsent(
        canonical,
        () => _net22AudioDisplayLabel(
          canonical,
          rawValue: value,
          track: track ?? tracks[canonical],
        ),
      );
    }

    for (final audio in _streamResult?.availableAudios ?? const <String>[]) {
      addOption(audio);
    }

    final asmsTracks =
        _betterPlayerController?.betterPlayerAsmsAudioTracks ??
        const <BetterPlayerAsmsAudioTrack>[];
    for (final track in asmsTracks) {
      addOption(track.label ?? '', track: track);
      addOption(track.language ?? '', track: track);
    }

    for (final entry in tracks.entries) {
      options.putIfAbsent(
        entry.key,
        () => _net22AudioDisplayLabel(entry.key, track: entry.value),
      );
    }

    return options;
  }

  Map<String, BetterPlayerAsmsAudioTrack> _net22AsmsAudioTrackMap() {
    final tracks = _betterPlayerController?.betterPlayerAsmsAudioTracks;
    if (tracks == null || tracks.isEmpty) return const {};

    final out = <String, BetterPlayerAsmsAudioTrack>{};
    for (final track in tracks) {
      final label = (track.label ?? '').trim();
      final language = (track.language ?? '').trim();
      if (label.isNotEmpty) {
        final canonicalLabel = _canonicalNet22AudioValue(label);
        if (canonicalLabel.isNotEmpty) {
          out.putIfAbsent(canonicalLabel, () => track);
        }
      }
      if (language.isNotEmpty) {
        final canonicalLanguage = _canonicalNet22AudioValue(language);
        if (canonicalLanguage.isNotEmpty) {
          out.putIfAbsent(canonicalLanguage, () => track);
        }
      }
    }
    return out;
  }

  List<PopupMenuEntry<String>> _buildNet22AudioMenuItems() {
    final options = _buildNet22AudioOptions();
    if (options.isEmpty) {
      return const [
        PopupMenuItem<String>(
          enabled: false,
          value: '',
          child: Text('No audio options found'),
        ),
      ];
    }

    final selectedPref = ref.read(net22AudioLanguageProvider).trim();
    final selectedCurrent = (_streamResult?.selectedAudio ?? '').trim();
    final selectedAsmsTrack =
        _betterPlayerController?.betterPlayerAsmsAudioTrack;
    final selectedAsms =
        (selectedAsmsTrack?.label ?? selectedAsmsTrack?.language ?? '').trim();
    final selectedPrefCanonical = _canonicalNet22AudioValue(selectedPref);
    final selectedCurrentCanonical = _canonicalNet22AudioValue(selectedCurrent);
    final selectedAsmsCanonical = _canonicalNet22AudioValue(selectedAsms);
    final selected = selectedPref.isNotEmpty && selectedPref != 'auto'
        ? selectedPrefCanonical
        : (selectedAsmsCanonical.isNotEmpty
              ? selectedAsmsCanonical
              : selectedCurrentCanonical);

    return options.entries.map((entry) {
      final value = entry.key.trim();
      final isSelected = value.toLowerCase() == selected.toLowerCase();
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected
                  ? NivioTheme.accentColorOf(context)
                  : Colors.white70,
              size: 18,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                entry.value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected
                      ? NivioTheme.accentColorOf(context)
                      : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Future<void> _switchNet22Audio(String audio) async {
    final target = _canonicalNet22AudioValue(audio.trim());
    if (target.isEmpty) return;

    final displayMap = _buildNet22AudioOptions();
    final targetLabel = displayMap[target] ?? target.toUpperCase();

    final asmsTrackMap = _net22AsmsAudioTrackMap();
    final asmsTrack = asmsTrackMap[target];

    if (asmsTrack != null && _betterPlayerController != null) {
      _betterPlayerController!.setAudioTrack(asmsTrack);
      await ref.read(net22AudioLanguageProvider.notifier).setPreference(target);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audio changed to $targetLabel'),
            duration: const Duration(seconds: 2),
            backgroundColor: NivioTheme.accentColorOf(context),
          ),
        );
      }
      setState(() {});
      return;
    }

    final currentPref = ref.read(net22AudioLanguageProvider).trim();
    final currentResult = (_streamResult?.selectedAudio ?? '').trim();
    final currentAsmsTrack =
        _betterPlayerController?.betterPlayerAsmsAudioTrack;
    final currentAsms =
        (currentAsmsTrack?.label ?? currentAsmsTrack?.language ?? '').trim();
    final currentPrefCanonical = _canonicalNet22AudioValue(currentPref);
    final currentResultCanonical = _canonicalNet22AudioValue(currentResult);
    final currentAsmsCanonical = _canonicalNet22AudioValue(currentAsms);
    if (target == currentPrefCanonical ||
        target == currentResultCanonical ||
        target == currentAsmsCanonical) {
      return;
    }

    final currentPosition =
        _betterPlayerController?.videoPlayerController?.value.position;
    await _saveProgress();
    await ref.read(net22AudioLanguageProvider.notifier).setPreference(target);
    ref.read(selectedQualityProvider.notifier).state = null;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switching audio to $targetLabel'),
          duration: const Duration(seconds: 2),
          backgroundColor: NivioTheme.accentColorOf(context),
        ),
      );
    }

    _disposePlayer();
    setState(() {
      _isLoading = true;
      _error = null;
      _retryCount = 0;
      _streamResult = null;
    });

    await _initializePlayer();

    if (!mounted ||
        currentPosition == null ||
        _betterPlayerController?.isVideoInitialized() != true) {
      return;
    }
    await _betterPlayerController!.seekTo(currentPosition);
    await _betterPlayerController!.play();
  }

  List<PopupMenuEntry<String>> _buildAnimeModeMenuItems() {
    final selected = ref.read(animeSubDubProvider).toLowerCase();
    final modes = const ['sub', 'dub'];

    return modes.map((mode) {
      final isSelected = mode == selected;
      return PopupMenuItem<String>(
        value: mode,
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected
                  ? NivioTheme.accentColorOf(context)
                  : Colors.white70,
              size: 18,
            ),
            const SizedBox(width: 12),
            Text(
              mode == 'dub' ? 'DUB' : 'SUB',
              style: TextStyle(
                color: isSelected
                    ? NivioTheme.accentColorOf(context)
                    : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Future<void> _switchAnimeMode(String mode) async {
    final target = mode.toLowerCase() == 'dub' ? 'dub' : 'sub';
    final current = ref.read(animeSubDubProvider).toLowerCase();
    if (target == current) return;

    final currentPosition =
        _betterPlayerController?.videoPlayerController?.value.position;
    await _saveProgress();
    await ref.read(animeSubDubProvider.notifier).setPreference(target);
    ref.read(selectedQualityProvider.notifier).state = null;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switching to ${target.toUpperCase()}'),
          duration: const Duration(seconds: 2),
          backgroundColor: NivioTheme.accentColorOf(context),
        ),
      );
    }

    _disposePlayer();
    setState(() {
      _isLoading = true;
      _error = null;
      _retryCount = 0;
      _streamResult = null;
    });

    await _initializePlayer();

    if (!mounted ||
        currentPosition == null ||
        _betterPlayerController?.isVideoInitialized() != true) {
      return;
    }
    await _betterPlayerController!.seekTo(currentPosition);
    await _betterPlayerController!.play();
  }

  List<PopupMenuEntry<int>> _buildProviderMenuItems() {
    return List.generate(_maxProviders, (index) {
      final isSelected = index == _currentProviderIndex;
      return PopupMenuItem(
        value: index,
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected
                  ? NivioTheme.accentColorOf(context)
                  : Colors.white70,
              size: 18,
            ),
            const SizedBox(width: 12),
            Text(
              _providerSelectorLabel(index),
              style: TextStyle(
                color: isSelected
                    ? NivioTheme.accentColorOf(context)
                    : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (index == 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
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
  }

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ WebView progress helpers ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
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

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Formatting & progress ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
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
    _removeFullscreenTopBarOverlayEntry();
    if (_betterPlayerController != null) {
      _betterPlayerController!.removeEventsListener(_onBetterPlayerEvent);
      _betterPlayerController!.dispose(forceDispose: true);
      _betterPlayerController = null;
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _watchPartyHostSyncTimer?.cancel();
    _watchPartyPlaybackSub?.cancel();
    _watchPartySessionSub?.cancel();
    _watchPartyErrorSub?.cancel();
    _nextEpisodeTimer?.cancel();
    _removeOverlayEntry();
    _removeFullscreenTopBarOverlayEntry();
    _nextEpNotifier.dispose();
    _fullscreenTopBarVisibleNotifier.dispose();
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

  void _handleBackNavigation() {
    if (context.canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go('/home');
  }

  Future<void> _toggleTopActionMenu<T>({
    required BuildContext anchorContext,
    required String menuId,
    required List<PopupMenuEntry<T>> Function() itemBuilder,
    required ValueChanged<T> onSelected,
  }) async {
    if (!mounted) return;
    if (_openTopActionMenuId == menuId) {
      await Navigator.of(context, rootNavigator: true).maybePop();
      if (mounted) {
        setState(() => _openTopActionMenuId = null);
      }
      return;
    }
    if (_openTopActionMenuId != null) {
      return;
    }

    final button = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    if (button == null || overlay == null) return;

    final buttonTopLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final buttonBottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    const verticalGap = 4.0;
    final menuTop = buttonBottomRight.dy + verticalGap;
    final position = RelativeRect.fromLTRB(
      buttonTopLeft.dx,
      menuTop,
      overlay.size.width - buttonBottomRight.dx,
      overlay.size.height - menuTop,
    );

    setState(() => _openTopActionMenuId = menuId);
    final selected = await showMenu<T>(
      context: context,
      position: position,
      color: const Color(0xFF1F1F1F),
      items: itemBuilder(),
      useRootNavigator: true,
    );
    if (!mounted) return;
    setState(() => _openTopActionMenuId = null);
    if (selected != null) {
      onSelected(selected);
    }
  }

  Widget _buildTopActionMenuButton<T>({
    required String menuId,
    required Widget icon,
    required String tooltip,
    required List<PopupMenuEntry<T>> Function() itemBuilder,
    required ValueChanged<T> onSelected,
  }) {
    return Builder(
      builder: (buttonContext) {
        final isOtherMenuOpen =
            _openTopActionMenuId != null && _openTopActionMenuId != menuId;
        return IconButton(
          tooltip: tooltip,
          onPressed: isOtherMenuOpen
              ? null
              : () => _toggleTopActionMenu<T>(
                  anchorContext: buttonContext,
                  menuId: menuId,
                  itemBuilder: itemBuilder,
                  onSelected: onSelected,
                ),
          icon: icon,
        );
      },
    );
  }

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Build ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
  @override
  Widget build(BuildContext context) {
    final media = ref.watch(selectedMediaProvider);
    final shouldShowAppBar = _streamResult != null && !_isInFullscreen;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackNavigation();
        }
      },
      child: GestureDetector(
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: Scaffold(
            backgroundColor: Colors.black,
            extendBodyBehindAppBar: false,
            appBar: shouldShowAppBar
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(kToolbarHeight),
                    child: AppBar(
                      backgroundColor: Colors.black.withValues(alpha: 0.7),
                      elevation: 0,
                      leading: IconButton(
                        icon: const PhosphorIcon(
                          PhosphorIconsRegular.caretLeft,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: _handleBackNavigation,
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            media?.title ?? media?.name ?? 'Playing',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                if (media?.mediaType == 'tv')
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: NivioTheme.accentColorOf(context),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      'S${widget.season} E$_currentEpisode',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                if (_watchPartySession != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      '${_watchPartySession!.sessionCode} • ${_watchPartySession!.participantCount}',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    _streamResult!.provider.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        if (_watchPartySession != null)
                          IconButton(
                            tooltip: 'Watch Party',
                            onPressed: _showWatchPartyDetailsSheet,
                            icon: const PhosphorIcon(
                              PhosphorIconsRegular.users,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        if (_isAimiAnimeStream())
                          _buildTopActionMenuButton<String>(
                            menuId: 'top-subdub-menu',
                            icon: Icon(
                              Icons.record_voice_over,
                              color: Colors.white,
                            ),
                            tooltip: 'Sub/Dub',
                            itemBuilder: _buildAnimeModeMenuItems,
                            onSelected: _switchAnimeMode,
                          ),
                        if (_isNet22DirectStream())
                          _buildTopActionMenuButton<String>(
                            menuId: 'top-audio-menu',
                            icon: Icon(
                              Icons.record_voice_over,
                              color: Colors.white,
                            ),
                            tooltip: 'Audio Language',
                            itemBuilder: _buildNet22AudioMenuItems,
                            onSelected: _switchNet22Audio,
                          ),
                        if (_isDirectStream &&
                            _buildQualityOptions().length > 1)
                          _buildTopActionMenuButton<String>(
                            menuId: 'top-quality-menu',
                            icon: Icon(Icons.hd, color: Colors.white),
                            tooltip: 'Quality',
                            itemBuilder: _buildQualityMenuItems,
                            onSelected: _switchQuality,
                          ),
                        // Switch Server
                        _buildTopActionMenuButton<int>(
                          menuId: 'top-server-menu',
                          icon: const PhosphorIcon(
                            PhosphorIconsRegular.arrowsClockwise,
                            color: Colors.white,
                            size: 21,
                          ),
                          tooltip: 'Switch Server',
                          itemBuilder: _buildProviderMenuItems,
                          onSelected: _switchToProvider,
                        ),
                      ],
                    ),
                  )
                : null,
            body: _buildPlayerBody(isPortrait),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerBody(bool isPortrait) {
    if (_isLoading) return _buildLoadingState();
    if (_error != null) return _buildErrorState();
    if (_streamResult != null && !_isDirectStream) return _buildWebViewPlayer();
    if (_betterPlayerController == null) return _buildLoadingState();

    return _buildDirectStreamLayout(isPortrait);
  }

  Widget _buildDirectStreamLayout(bool isPortrait) {
    final safeAspectRatio = _resolvedVideoAspectRatio();

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final maxHeight = constraints.maxHeight;
              final fittedWidth = math.min(
                maxWidth,
                maxHeight * safeAspectRatio,
              );
              final fittedHeight = fittedWidth / safeAspectRatio;

              return Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: fittedWidth,
                  height: fittedHeight,
                  child: _buildVideoPlayer(),
                ),
              );
            },
          ),
        ),
        if (isPortrait) _buildPortraitBottomControls(),
      ],
    );
  }

  Widget _buildFullscreenFloatingTopBar() {
    final appTheme = Theme.of(context);
    final watchPartySession = _watchPartySession;
    final titleStyle =
        appTheme.textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ) ??
        TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        );
    final subtitleStyle =
        appTheme.textTheme.bodySmall?.copyWith(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ) ??
        TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        );

    return ValueListenableBuilder<bool>(
      valueListenable: _fullscreenTopBarVisibleNotifier,
      builder: (context, showInPlayer, _) {
        return IgnorePointer(
          ignoring: !showInPlayer,
          child: AnimatedOpacity(
            opacity: showInPlayer ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 6, right: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: () {
                        _exitPlayerFromTopBar();
                      },
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: const PhosphorIcon(
                        PhosphorIconsRegular.caretLeft,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  ref.read(selectedMediaProvider)?.title ??
                                      ref.read(selectedMediaProvider)?.name ??
                                      'Playing',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                              ),
                              if (watchPartySession != null) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Transform.translate(
                                    offset: const Offset(0, 8),
                                    child: Text(
                                      '${watchPartySession.sessionCode} • ${watchPartySession.participantCount}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: titleStyle.copyWith(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _buildFullscreenSubtitle(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: subtitleStyle,
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (watchPartySession != null)
                              IconButton(
                                tooltip: 'Watch Party',
                                onPressed: _showWatchPartyDetailsSheet,
                                icon: const PhosphorIcon(
                                  PhosphorIconsRegular.users,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            if (_isAimiAnimeStream())
                              _buildTopActionMenuButton<String>(
                                menuId: 'fs-subdub-menu',
                                icon: Icon(
                                  Icons.record_voice_over,
                                  color: Colors.white,
                                ),
                                tooltip: 'Sub/Dub',
                                itemBuilder: _buildAnimeModeMenuItems,
                                onSelected: _switchAnimeMode,
                              ),
                            if (_isNet22DirectStream())
                              _buildTopActionMenuButton<String>(
                                menuId: 'fs-audio-menu',
                                icon: Icon(
                                  Icons.record_voice_over,
                                  color: Colors.white,
                                ),
                                tooltip: 'Audio Language',
                                itemBuilder: _buildNet22AudioMenuItems,
                                onSelected: _switchNet22Audio,
                              ),
                            if (_isDirectStream &&
                                _buildQualityOptions().length > 1)
                              _buildTopActionMenuButton<String>(
                                menuId: 'fs-quality-menu',
                                icon: Icon(Icons.hd, color: Colors.white),
                                tooltip: 'Quality',
                                itemBuilder: _buildQualityMenuItems,
                                onSelected: _switchQuality,
                              ),
                            _buildTopActionMenuButton<int>(
                              menuId: 'fs-server-menu',
                              icon: const PhosphorIcon(
                                PhosphorIconsRegular.arrowsClockwise,
                                color: Colors.white,
                                size: 20,
                              ),
                              tooltip: 'Switch Server',
                              itemBuilder: _buildProviderMenuItems,
                              onSelected: _switchToProvider,
                            ),
                          ],
                        ),
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

  void _syncFullscreenTopBarVisibility() {
    final shouldShow = _isInFullscreen && _arePlayerControlsVisible;
    if (_fullscreenTopBarVisibleNotifier.value != shouldShow) {
      _fullscreenTopBarVisibleNotifier.value = shouldShow;
    }
    if (shouldShow) {
      _showFullscreenTopBarOverlayEntry();
    } else {
      _removeFullscreenTopBarOverlayEntry();
    }
  }

  void _exitPlayerFromTopBar() {
    final isFullscreen = _betterPlayerController?.isFullScreen == true;
    if (isFullscreen) {
      _betterPlayerController?.exitFullScreen();
      Future.delayed(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        _handleBackNavigation();
      });
      return;
    }
    _handleBackNavigation();
  }

  void _showFullscreenTopBarOverlayEntry() {
    if (!mounted || _fullscreenTopBarOverlayEntry != null) return;
    _fullscreenTopBarOverlayEntry = OverlayEntry(
      builder: (_) => Positioned.fill(child: _buildFullscreenFloatingTopBar()),
    );
    Overlay.of(
      context,
      rootOverlay: true,
    ).insert(_fullscreenTopBarOverlayEntry!);
  }

  void _removeFullscreenTopBarOverlayEntry() {
    _fullscreenTopBarOverlayEntry?.remove();
    _fullscreenTopBarOverlayEntry = null;
  }

  String _buildFullscreenSubtitle() {
    final media = ref.read(selectedMediaProvider);
    if (media?.mediaType != 'tv') {
      return _streamResult?.provider.toUpperCase() ?? '';
    }

    String? episodeName;
    final seasonData = _currentSeasonData;
    if (seasonData != null) {
      for (final episode in seasonData.episodes) {
        if (episode.episodeNumber == _currentEpisode) {
          episodeName = episode.episodeName;
          break;
        }
      }
    }

    final fallback = 'S${widget.season} E$_currentEpisode';
    if (episodeName == null || episodeName.trim().isEmpty) {
      return fallback;
    }
    return episodeName;
  }

  Widget _buildPortraitBottomControls() {
    final controller = _betterPlayerController;
    final videoController = controller?.videoPlayerController;
    if (controller == null || videoController == null) {
      return const SizedBox.shrink();
    }

    return Container(
      color: const Color(0xCC000000),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder(
          valueListenable: videoController,
          builder: (context, value, _) {
            final position = value.position;
            final duration = value.duration ?? Duration.zero;
            final durationMs = duration.inMilliseconds;
            final maxMs = durationMs > 0 ? durationMs.toDouble() : 1.0;
            final sliderValue = durationMs > 0
                ? position.inMilliseconds.clamp(0, durationMs).toDouble()
                : 0.0;
            final isMuted = value.volume <= 0.01;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      _formatDuration(position),
                      style: TextStyle(fontSize: 11, color: Colors.white),
                    ),
                    const Spacer(),
                    Text(
                      _formatDuration(duration),
                      style: TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ],
                ),
                Slider(
                  value: sliderValue,
                  min: 0,
                  max: maxMs,
                  activeColor: NivioTheme.accentColorOf(context),
                  inactiveColor: Colors.white30,
                  onChanged: durationMs > 0 ? (_) {} : null,
                  onChangeEnd: durationMs > 0
                      ? (newValue) {
                          controller.seekTo(
                            Duration(milliseconds: newValue.round()),
                          );
                        }
                      : null,
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () =>
                          controller.setVolume(isMuted ? 1.0 : 0.0),
                      icon: Icon(
                        isMuted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    if (ref.read(selectedMediaProvider)?.mediaType == 'tv')
                      IconButton(
                        onPressed: _showEpisodesBottomSheet,
                        icon: Icon(Icons.list, color: Colors.white),
                      ),
                    if (_isDirectStream)
                      PopupMenuButton<String>(
                        icon: Icon(Icons.aspect_ratio, color: Colors.white),
                        tooltip: 'Display',
                        color: const Color(0xFF1F1F1F),
                        onSelected: _switchDisplayMode,
                        itemBuilder: (context) => _buildDisplayMenuItems(),
                      ),
                    IconButton(
                      onPressed: () {
                        if (controller.isFullScreen) {
                          controller.exitFullScreen();
                        } else {
                          controller.enterFullScreen();
                        }
                      },
                      icon: Icon(
                        controller.isFullScreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ OverlayEntry management ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
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

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Loading state ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
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
                  imageUrl:
                      posterPath.startsWith('http://') ||
                          posterPath.startsWith('https://')
                      ? posterPath
                      : posterPath.startsWith('/')
                      ? '$tmdbImageBaseUrl/$backdropSize$posterPath'
                      : posterPath,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              ),
            ),
          // Content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Netflix-style loading ring
                SizedBox(width: 56, height: 56, child: _NamizoLoadingSpinner()),
                const SizedBox(height: 24),
                if (title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      title,
                      style: TextStyle(
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
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                const SizedBox(height: 16),
                // Provider pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
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
                          color: NivioTheme.accentColorOf(
                            context,
                          ).withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _currentProvider.isNotEmpty
                            ? _currentProvider
                            : _providerSelectorLabel(_currentProviderIndex),
                        style: TextStyle(
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
                      color: Colors.orange.withValues(alpha: 0.8),
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

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Error state ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
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
              color: NivioTheme.accentColorOf(context).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline,
              color: NivioTheme.accentColorOf(context),
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
            style: TextStyle(fontSize: 14, color: Colors.white70, height: 1.5),
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
                  icon: Icon(Icons.swap_horiz, size: 20),
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
                icon: Icon(Icons.refresh, size: 20),
                label: const Text('RETRY'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NivioTheme.accentColorOf(context),
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
                onPressed: _handleBackNavigation,
                icon: Icon(Icons.arrow_back, size: 20),
                label: const Text('GO BACK'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white54, width: 1.5),
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

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ WebView player (embed fallback) ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
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

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ BetterPlayer widget ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
  Widget _buildVideoPlayer() {
    return RepaintBoundary(
      child: BetterPlayer(controller: _betterPlayerController!),
    );
  }
}

// ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
// Redesigned Episode Picker with thumbnails and search
// ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
class _EpisodePickerSheet extends ConsumerStatefulWidget {
  final int mediaId;
  final int currentSeason;
  final int currentEpisode;
  final String? mediaType;
  final String? watchPartyCode;
  final WatchPartyRole? watchPartyRole;

  const _EpisodePickerSheet({
    required this.mediaId,
    required this.currentSeason,
    required this.currentEpisode,
    this.mediaType,
    this.watchPartyCode,
    this.watchPartyRole,
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
          decoration: BoxDecoration(
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
                              style: TextStyle(
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
                          icon: Icon(Icons.close, color: Colors.white70),
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
                      style: TextStyle(color: Colors.white, fontSize: 14),
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
                                  ? (episode.stillPath!.startsWith('http://') ||
                                            episode.stillPath!.startsWith(
                                              'https://',
                                            )
                                        ? episode.stillPath!
                                        : episode.stillPath!.startsWith('/')
                                        ? '$tmdbImageBaseUrl/$backdropSize${episode.stillPath}'
                                        : episode.stillPath!)
                                  : '';

                              return GestureDetector(
                                onTap: () {
                                  Navigator.pop(context);
                                  if (!isCurrent) {
                                    final query = <String, String>{
                                      'season': '${widget.currentSeason}',
                                      'episode': '${episode.episodeNumber}',
                                      if ((widget.mediaType ?? '').isNotEmpty)
                                        'type': widget.mediaType!,
                                      if ((widget.watchPartyCode ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        'partyCode': widget.watchPartyCode!
                                            .trim()
                                            .toUpperCase(),
                                      if (widget.watchPartyRole != null)
                                        'partyRole':
                                            widget.watchPartyRole!.queryValue,
                                    };
                                    this.context.pushReplacement(
                                      Uri(
                                        path: '/player/${widget.mediaId}',
                                        queryParameters: query,
                                      ).toString(),
                                    );
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? NivioTheme.accentColorOf(
                                            context,
                                          ).withValues(alpha: 0.15)
                                        : const Color(0xFF1E1E1E),
                                    borderRadius: BorderRadius.circular(10),
                                    border: isCurrent
                                        ? Border.all(
                                            color: NivioTheme.accentColorOf(
                                              context,
                                            ),
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
                                                      placeholder:
                                                          (context, url) =>
                                                              Container(
                                                                color: Colors
                                                                    .grey[900],
                                                              ),
                                                      errorWidget:
                                                          (
                                                            context,
                                                            url,
                                                            error,
                                                          ) => Container(
                                                            color: Colors
                                                                .grey[900],
                                                            child: Icon(
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
                                                                  .withValues(
                                                                    alpha: 0.6,
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
                                                  child: Icon(
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
                                                      'E${episode.episodeNumber} Ãƒâ€šÃ‚Â· ${episode.episodeName ?? 'Episode ${episode.episodeNumber}'}',
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
            loading: () => Center(
              child: CircularProgressIndicator(
                color: NivioTheme.accentColorOf(context),
              ),
            ),
            error: (error, stack) => Center(
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

// ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Helper class for next episode overlay state ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
class _NextEpState {
  final bool show;
  final int? countdown;

  const _NextEpState({required this.show, required this.countdown});
}

// ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Netflix-style loading spinner ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
class _NamizoLoadingSpinner extends StatefulWidget {
  @override
  State<_NamizoLoadingSpinner> createState() => _NamizoLoadingSpinnerState();
}

class _NamizoLoadingSpinnerState extends State<_NamizoLoadingSpinner>
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
          painter: _SpinnerPainter(
            _controller.value,
            NivioTheme.accentColorOf(context),
          ),
          size: const Size(56, 56),
        );
      },
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final double progress;
  final Color accentColor;

  _SpinnerPainter(this.progress, this.accentColor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    // Track circle
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
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
        colors: [accentColor.withValues(alpha: 0), accentColor],
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
      ..color = accentColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(dotX, dotY), 3, dotPaint);
    canvas.drawCircle(Offset(dotX, dotY), 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Separate widget for the OverlayEntry (renders above everything) ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
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
                      color: Colors.black.withValues(alpha: 0.8),
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
                      Builder(
                        builder: (_) {
                          final stillPath = nextEpisode?.stillPath;
                          if (stillPath == null) {
                            return const SizedBox.shrink();
                          }
                          final imageUrl =
                              stillPath.startsWith('http://') ||
                                  stillPath.startsWith('https://')
                              ? stillPath
                              : stillPath.startsWith('/')
                              ? '$tmdbImageBaseUrl/$backdropSize$stillPath'
                              : stillPath;

                          return ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              width: 280,
                              height: 120,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => Container(
                                height: 60,
                                color: Colors.grey[900],
                              ),
                            ),
                          );
                        },
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
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'S$season E$nextEpNum',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: onPlay,
                                  icon: Icon(Icons.play_arrow, size: 18),
                                  label: Text(
                                    state.countdown != null
                                        ? 'Play in ${state.countdown}s'
                                        : 'Play Now',
                                    style: TextStyle(
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
                                icon: Icon(
                                  Icons.close,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.1,
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
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  NivioTheme.accentColorOf(context),
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
