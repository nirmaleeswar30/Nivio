import 'package:better_player_plus/better_player_plus.dart';
import 'package:simple_pip_mode/actions/pip_actions_layout.dart';
import 'package:simple_pip_mode/simple_pip.dart';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/screens/player/widgets/custom_player_controls.dart';
import 'package:nivio/models/search_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nivio/models/season_info.dart';
import 'package:nivio/providers/media_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/providers/language_preferences_provider.dart';
import 'package:nivio/providers/watch_party_provider.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/streaming_service.dart';
import 'package:nivio/services/watch_party/watch_party_models.dart';
import 'package:nivio/services/watch_party/watch_party_service_supabase.dart';
import 'package:nivio/models/watch_history.dart';
import 'package:nivio/services/watch_history_service.dart';

import 'dart:async';
import 'dart:io';
import 'package:nivio/services/download_service.dart';
import 'package:nivio/widgets/webview_player.dart';
import 'package:nivio/widgets/kwik_native_player.dart';
import 'package:nivio/services/scrapers/animepahe/kwik_extractor_service.dart';
import 'package:nivio/services/hls_proxy_service.dart';
import 'package:nivio/services/anilist_service.dart';
import 'package:nivio/services/aniskip_service.dart';
import 'package:nivio/services/theintrodb_service.dart';
import 'package:nivio/services/skip_times_models.dart';
import 'dart:math' as math;

class PlayerScreen extends ConsumerStatefulWidget {
  final int mediaId;
  final int season;
  final int episode;
  final String? mediaType;
  final int? providerIndex;
  final String? watchPartyCode;
  final WatchPartyRole? watchPartyRole;
  final String? localPath;
  final String? directStreamUrl;
  final String? directStreamTitle;
  final bool isLive;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.season,
    required this.episode,
    this.mediaType,
    this.providerIndex,
    this.watchPartyCode,
    this.watchPartyRole,
    this.localPath,
    this.directStreamUrl,
    this.directStreamTitle,
    this.isLive = false,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  WatchHistoryService? _cachedHistoryService;
  SearchResult? _cachedMedia;

  Future<void> _loadSubtitleDelay() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _subtitleDelayMs = prefs.getInt('subtitle_delay_${widget.mediaId}') ?? 0;
    });
  }

  void _updateSubtitleDelay(int change) async {
    setState(() {
      _subtitleDelayMs += change;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('subtitle_delay_${widget.mediaId}', _subtitleDelayMs);
    
    if (_useNativePlayer) {
      _kwikPlayerKey.currentState?.setSubtitleDelay(_subtitleDelayMs);
    } else {
      _betterPlayerController?.setSubtitleDelay(_subtitleDelayMs);
    }
  }

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
  final Map<int, StreamResult> _prefetchedStreams = {};
  bool _isPrefetching = false;
  bool _isDirectStream = false;
  List<SkipTime> _skipTimes = [];
  bool _isFetchingSkipTimes = false;
  bool _isInIntroSegment = false;
  bool _isInOutroSegment = false;
  int _currentEpisode = 0;
  bool _isInFullscreen = false;
  Duration? _resumePosition;
  WatchHistory? _currentHistory;
  
  bool _useNativePlayer = false;
  String? _nativeUrl;
  Map<String, String>? _nativeHeaders;
  Duration? _nativeStartAt;
  Duration _nativePosition = Duration.zero;
  Duration _nativeDuration = Duration.zero;
  bool _isNativePlaying = true;
  bool _isPipMode = false;
  final GlobalKey<KwikNativePlayerState> _kwikPlayerKey = GlobalKey<KwikNativePlayerState>();

  // Effective local file to play: either the explicit widget.localPath, or a
  // completed download discovered for this media. When set, playback is offline.
  String? _effectiveLocalPath;
  String _localAudioLang = 'English';
  
  BoxFit _currentFit = BoxFit.contain;

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
  
  int _subtitleDelayMs = 0;

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

  Duration _webViewPosition = Duration.zero;
  Duration _webViewDuration = Duration.zero;

  static const int _watchPartyDriftThresholdMs = 1200;
  String? _loadingMessage;

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
    _loadSubtitleDelay();
    
    const MethodChannel('com.nivio/gesture_exclusion').invokeMethod('setCanEnterPip', {'value': true});
    try {
      () async {
        const MethodChannel('puntito.simple_pip_mode').setMethodCallHandler((call) async {
          if (call.method == 'onPipEntered') {
            setState(() => _isPipMode = true);
          } else if (call.method == 'onPipExited') {
            setState(() => _isPipMode = false);
          } else if (call.method == 'onPipAction') {
            final String arg = call.arguments as String;
            final actionStr = arg.toLowerCase();
            if (actionStr == 'play') {
              if (_useNativePlayer) {
                _kwikPlayerKey.currentState?.play();
              } else {
                _betterPlayerController?.play();
              }
            } else if (actionStr == 'pause') {
              if (_useNativePlayer) {
                _kwikPlayerKey.currentState?.pause();
              } else {
                _betterPlayerController?.pause();
              }
            } else if (actionStr == 'next' || actionStr == 'forward') {
              if (_useNativePlayer) {
                final pos = _kwikPlayerKey.currentState?.player.state.position ?? Duration.zero;
                _kwikPlayerKey.currentState?.seekTo(pos + const Duration(seconds: 10));
              } else {
                final pos = _betterPlayerController?.videoPlayerController?.value.position ?? Duration.zero;
                _betterPlayerController?.seekTo(pos + const Duration(seconds: 10));
              }
            } else if (actionStr == 'previous' || actionStr == 'rewind') {
              if (_useNativePlayer) {
                final pos = _kwikPlayerKey.currentState?.player.state.position ?? Duration.zero;
                _kwikPlayerKey.currentState?.seekTo(pos - const Duration(seconds: 10));
              } else {
                final pos = _betterPlayerController?.videoPlayerController?.value.position ?? Duration.zero;
                _betterPlayerController?.seekTo(pos - const Duration(seconds: 10));
              }
            }
          }
        });
        await SimplePip().setPipActionsLayout(PipActionsLayout.mediaWithSeek10);
        await SimplePip().setAutoPipMode(aspectRatio: const (16, 9), autoEnter: true);
        await SimplePip().setIsPlaying(true);
      }();
    } catch (_) {}
    _currentEpisode = widget.episode;
    _currentProviderIndex = math.max(0, widget.providerIndex ?? 0);
    _initializeWatchParty();
    _initializePlayer();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _trackInitialPlay() async {
    final media = ref.read(selectedMediaProvider);
    if (media == null) return;
    
    final historyService = ref.read(watchHistoryServiceProvider);
    final existing = await historyService.getHistory(widget.mediaId);
    
    bool needsUpdate = false;
    if (existing == null || existing.progressPercent <= 0) {
      needsUpdate = true;
    } else if (media.mediaType == 'tv' && (existing.currentSeason != widget.season || existing.currentEpisode != _currentEpisode)) {
      needsUpdate = true;
    }

    if (needsUpdate) {
      await historyService.updateProgress(
        tmdbId: widget.mediaId,
        mediaType: media.mediaType,
        title: media.title ?? media.name ?? 'Unknown',
        posterPath: media.backdropPath ?? media.posterPath,
        currentSeason: widget.season,
        currentEpisode: _currentEpisode,
        totalSeasons: 1,
        totalEpisodes: null,
        lastPosition: const Duration(seconds: 1),
        totalDuration: const Duration(minutes: 120),
      );
    }
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

  Future<void> _fetchSkipTimes(SearchResult media, int episode) async {
    if (_isFetchingSkipTimes) return;
    _isFetchingSkipTimes = true;
    _skipTimes.clear();
    
    try {
      if (media.mediaType == 'tv' && _isAnimeMedia(media)) {
        // Anime - AniSkip
        final anilistService = AniListService();
        final result = await anilistService.getAniListIdFromTMDB(title: media.title ?? media.name ?? '', year: media.firstAirDate?.split('-').first, tmdbId: media.id);
        if (result?.idMal != null) {
          final times = await AniSkipService.getSkipTimes(result!.idMal!, episode);
          if (mounted) setState(() { _skipTimes = times; });
        }
      } else if (media.mediaType == 'tv') {
        // Normal show - TheIntroDB (v3 public API)
        final times = await TheIntroDBService.getSkipTimes(media.id, widget.season, episode);
        if (mounted) setState(() { _skipTimes = times; });
      }
    } finally {
      if (mounted) _isFetchingSkipTimes = false;
    }
  }

  // ├────────────────────────────────────────────────────────────────────────────────────────── Player initialization ──────────────────────────────────────────────────────────────────────────────────────────
  Future<void> _initializePlayer() async {
    _autoFullscreenTriggeredForCurrentLoad = false;
    _useNativePlayer = false;
    _nativeUrl = null;
    _nativeHeaders = null;
    _nativeStartAt = null;
    _nativePosition = Duration.zero;
    _nativeDuration = Duration.zero;
    setState(() {
      _isLoading = true;
      _error = null;
      _loadingMessage = null;
    });

    try {
      final historyService = ref.read(watchHistoryServiceProvider);
      await historyService.init();
      _currentHistory = await historyService.getHistory(widget.mediaId);

      // If the route didn't explicitly specify a provider, use the saved preference
      if (widget.providerIndex == null && _currentHistory?.preferredProviderIndex != null) {
        _currentProviderIndex = _currentHistory!.preferredProviderIndex!;
      }

      var media = ref.read(selectedMediaProvider);
      final hasMatchingSelectedMedia =
          media != null &&
          media.id == widget.mediaId &&
          (widget.mediaType == null || media.mediaType == widget.mediaType);

      if (widget.directStreamUrl != null) {
        media = null;
        Future.microtask(() {
          if (mounted) {
            ref.read(selectedMediaProvider.notifier).state = null;
          }
        });
      } else if (!hasMatchingSelectedMedia) {
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

      if (media?.mediaType == 'tv') {
        _fetchSeasonData();
      }
      
      if (media != null && !_isFetchingSkipTimes) {
        _fetchSkipTimes(media, _currentEpisode);
      }

      setState(() => _currentProvider = 'Fetching stream...');

      final streamingService = ref.read(streamingServiceProvider);
      final settingsQuality = ref.read(videoQualityProvider);
      final manualQuality = ref.read(selectedQualityProvider);
      final preferredQuality =
          manualQuality ?? (settingsQuality == 'auto' ? null : settingsQuality);
      final subDubPref = ref.read(languagePreferencesProvider).animePreferredAudio;

      StreamResult? result;

      // Always prefer a local downloaded copy if one exists for this media,
      // regardless of how playback was launched. An explicit localPath (e.g.
      final downloadItem = DownloadService.findPlayableDownload(
        mediaId: widget.mediaId,
        season: widget.season,
        episode: _currentEpisode,
      );

      _effectiveLocalPath = (widget.localPath != null && widget.localPath!.isNotEmpty)
          ? widget.localPath
          : downloadItem?.savePath;

      String getLangName(String? code) {
        if (code == null || code.isEmpty) return 'English';
        final c = code.toLowerCase();
        if (c.contains('eng') || c.startsWith('en')) return 'English';
        if (c.contains('hin') || c.startsWith('hi')) return 'Hindi';
        if (c.contains('tam') || c.startsWith('ta')) return 'Tamil';
        if (c.contains('tel') || c.startsWith('te')) return 'Telugu';
        if (c.contains('spa') || c.startsWith('es')) return 'Spanish';
        if (c.contains('fra') || c.startsWith('fr')) return 'French';
        if (c.contains('jpn') || c.startsWith('ja')) return 'Japanese';
        if (c.contains('kor') || c.startsWith('ko')) return 'Korean';
        if (c.contains('deu') || c.startsWith('de')) return 'German';
        if (c.contains('ita') || c.startsWith('it')) return 'Italian';
        return code;
      }

      if (downloadItem != null) {
        _localAudioLang = getLangName(downloadItem.selectedAudioLanguage);
      }

      if (widget.directStreamUrl != null) {
        final lowerUrl = widget.directStreamUrl!.toLowerCase();
        final isHls = lowerUrl.contains('.m3u8') || lowerUrl.contains('.m3u') || widget.isLive;
        
        result = StreamResult(
          url: widget.directStreamUrl!,
          quality: 'Live',
          provider: 'IPTV',
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': '*/*',
          },
          isM3U8: isHls,
        );
      } else if (_effectiveLocalPath != null && _effectiveLocalPath!.isNotEmpty) {
        final String srtPath = _effectiveLocalPath!.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.srt');
        final bool hasSrt = await File(srtPath).exists();

        String subLang = 'English';
        if (downloadItem != null) {
          subLang = getLangName(downloadItem.selectedSubtitleLanguage);
        }

        result = StreamResult(
          url: _effectiveLocalPath!,
          quality: 'Downloaded',
          provider: 'Local',
          headers: {},
          subtitles: hasSrt ? [SubtitleTrack(lang: subLang, url: srtPath)] : [],
        );
      } else if (_prefetchedStreams.containsKey(_currentEpisode)) {
        // Use the silently prefetched stream to eliminate loading delays!
        result = _prefetchedStreams.remove(_currentEpisode);
      } else {
        result = await streamingService.fetchStreamUrl(
          media: media!,
          season: widget.season,
          episode: _currentEpisode,
          preferredQuality: preferredQuality,
          providerIndex: _currentProviderIndex,
          subDubPreference: subDubPref,
          onStatusUpdate: (msg) {
            if (mounted) {
              setState(() => _loadingMessage = msg);
            }
          },
        );
      }

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
      // A local downloaded file is always played directly (never via WebView).
      _isDirectStream = (widget.directStreamUrl != null || (_effectiveLocalPath != null && _effectiveLocalPath!.isNotEmpty))
          ? true
          : StreamingService.isDirectStream(
              _currentProviderIndex,
              isAnime: _isAnimeMedia(media),
            );
      
      _trackInitialPlay();

      // Embed providers use WebView
      if (!_isDirectStream) {
        setState(() {
          _isLoading = false;
          _retryCount = 0;
        });
        _updateWatchPartyHostSyncTimer();
        _startProgressTracking();
        _maybeAutoEnterFullscreenOnce();
        return;
      }

      // —————————————————————————————————————————————————————————————————————————————————————————— Check watch history for resume ——————————————————————————————————————————————————————————————————————————————————————————
      final history = _currentHistory;
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

      if (_isDirectStream && _isAnimeMedia(media)) {
        _useNativePlayer = true;
        _nativeUrl = result.url;
        _nativeHeaders = _buildPlaybackHeaders(result.headers);
        _nativeStartAt = startAt;
        setState(() {
          _isLoading = false;
          _retryCount = 0;
        });
        _updateWatchPartyHostSyncTimer();
        _startProgressTracking();
        _maybeAutoEnterFullscreenOnce();
        return;
      }

      // —————————————————————————————————————————————————————————————————————————————————————————— Build subtitle sources ——————————————————————————————————————————————————————————————————————————————————————————
      final subtitleSources = result.subtitles.map((sub) {
        return BetterPlayerSubtitlesSource(
          type: _effectiveLocalPath != null && _effectiveLocalPath!.isNotEmpty 
              ? BetterPlayerSubtitlesSourceType.file 
              : BetterPlayerSubtitlesSourceType.network,
          name: sub.lang,
          urls: [sub.url],
        );
      }).toList();

      // —————————————————————————————————————————————————————————————————————————————————————————— Build resolutions map for non-HLS multi-quality ——————————————————————————————————————————————————————————————————————————————————————————
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
      final cacheConfiguration = _buildCacheConfiguration(result);

      // —————————————————————————————————————————————————————————————————————————————————————————— Headers ——————————————————————————————————————————————————————————————————————————————————————————
      final headers = _buildPlaybackHeaders(result.headers);

      // —————————————————————————————————————————————————————————————————————————————————————————— Data source ——————————————————————————————————————————————————————————————————————————————————————————
      final dataSource = BetterPlayerDataSource(
        _effectiveLocalPath != null && _effectiveLocalPath!.isNotEmpty 
            ? BetterPlayerDataSourceType.file 
            : BetterPlayerDataSourceType.network,
        result.url,
        headers: _effectiveLocalPath != null && _effectiveLocalPath!.isNotEmpty ? null : headers,
        videoFormat: _effectiveLocalPath != null && _effectiveLocalPath!.isNotEmpty 
            ? BetterPlayerVideoFormat.other
            : (result.isM3U8
                ? BetterPlayerVideoFormat.hls
                : BetterPlayerVideoFormat.other),
        useAsmsTracks: _effectiveLocalPath != null && _effectiveLocalPath!.isNotEmpty ? false : result.isM3U8,
        useAsmsSubtitles: _effectiveLocalPath != null && _effectiveLocalPath!.isNotEmpty ? false : result.isM3U8,
        useAsmsAudioTracks: _effectiveLocalPath != null && _effectiveLocalPath!.isNotEmpty ? false : result.isM3U8,
        subtitles: subtitleSources.isNotEmpty ? subtitleSources : null,
        resolutions: resolutions,
        cacheConfiguration: _effectiveLocalPath != null && _effectiveLocalPath!.isNotEmpty ? const BetterPlayerCacheConfiguration(useCache: false) : cacheConfiguration,
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 120000, // 2 minutes minimum buffer
          maxBufferMs: 900000, // 15 minutes max buffer
          bufferForPlaybackMs: 250, // Start playing instantly (250ms)
          bufferForPlaybackAfterRebufferMs: 1500, // Resume quickly after buffering (1.5s)
        ),
      );

      _betterPlayerController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true,
          looping: false,
          fullScreenByDefault: false,
          subtitlesConfiguration: BetterPlayerSubtitlesConfiguration(
            fontSize: ref.read(subtitleFontSizeProvider),
          ),
          aspectRatio: MediaQuery.of(context).size.width / MediaQuery.of(context).size.height,
          deviceOrientationsAfterFullScreen: const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
          deviceOrientationsOnFullScreen: const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
          fit: _displayFitOptions[_selectedDisplayFitKey] ?? BoxFit.cover,
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
            playerTheme: BetterPlayerTheme.custom,
            customControlsBuilder: (controller, onPlayerVisibilityChanged, controlsConfiguration) {
              final media = ref.read(selectedMediaProvider);
              String? subtitle;
              if (media?.mediaType == 'tv') {
                String? episodeName;
                if (_currentSeasonData != null) {
                  for (final episode in _currentSeasonData!.episodes) {
                    if (episode.episodeNumber == _currentEpisode) {
                      episodeName = episode.episodeName;
                      break;
                    }
                  }
                }
                final fallback = 'S${widget.season} E$_currentEpisode';
                if (episodeName == null || episodeName.trim().isEmpty || episodeName.startsWith('Episode')) {
                  subtitle = fallback;
                } else {
                  subtitle = '$fallback - $episodeName';
                }
              }
              final title = media?.title ?? media?.name ?? 'Playing';
              
              return CustomPlayerControls(
                controller: controller,
                onPlayerVisibilityChanged: onPlayerVisibilityChanged,
                controlsConfiguration: controlsConfiguration,
                title: title,
                subtitle: subtitle,
                providerName: _streamResult?.provider ?? _currentProvider,
                isLive: widget.isLive,
                onBack: _handleBackNavigation,
                onServerChange: () {
                  _showServerOverlayPanel();
                },
                onSettings: () {
                  _showSettingsOverlayPanel();
                },
                onEpisodes: (media?.mediaType == 'tv') ? () {
                  _showEpisodesBottomSheet();
                } : null,
              );
            },
            overflowMenuCustomItems: [
              if (_isDirectStream)
                BetterPlayerOverflowMenuItem(
                  Icons.aspect_ratio,
                  'Display',
                  _showDisplaySelectionBottomSheet,
                ),
              if (media?.mediaType == 'tv')
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
              child: SingleChildScrollView(
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
             ),
            );
          },
        ),
      );

      // Register event listener BEFORE setting up data source
      _betterPlayerController!.addEventsListener(_onBetterPlayerEvent);
      _applyDisplaySettings(refreshUi: false);

      // Show the player immediately — BetterPlayer handles its own buffering UI
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

  // —————————————————————————————————————————————————————————————————————————————————————————— BetterPlayer event listener ——————————————————————————————————————————————————————————————————————————————————————————
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

    setIfMissing('Accept', '*/*');
    setIfMissing('Accept-Language', 'en-US,en;q=0.9');
    return headers;
  }

  BetterPlayerCacheConfiguration? _buildCacheConfiguration(
    StreamResult result,
  ) {
    // BetterPlayer's experimental cache proxy is known to cause severe hangs and pipeline
    // failures in ExoPlayer when seeking unbuffered HLS segments. We disable it entirely
    // and rely on ExoPlayer's robust native DefaultLoadControl buffering instead.
    return null;
  }

  bool _isLanguageMatch(String trackLang, String preferredLang) {
    if (trackLang.isEmpty || preferredLang.isEmpty) return false;
    final t = trackLang.toLowerCase().trim();
    final p = preferredLang.toLowerCase().trim();
    if (t == p || t.contains(p) || p.contains(t)) return true;
    
    // Map preferred language to ISO codes
    final map = {
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
    };

    final pIsoCodes = map[p] ?? [p];
    final tIsoCodes = map[t] ?? [t];

    if (pIsoCodes.any((code) => t.contains(code) || t == code)) return true;
    if (tIsoCodes.any((code) => p.contains(code) || p == code)) return true;

    for (final iso in pIsoCodes) {
      final regex = RegExp(r'\b' + iso + r'\b', caseSensitive: false);
      if (regex.hasMatch(t)) return true;
    }
    
    return false;
  }

  bool _hasAppliedGlobalTracks = false;
  int _lastAudioTrackCount = 0;
  int _lastSubtitleTrackCount = 0;

  void _applyTrackPreferences() {
    final audioTracks = _betterPlayerController?.betterPlayerAsmsAudioTracks ?? [];
    final subtitleTracks = _betterPlayerController?.betterPlayerSubtitlesSourceList ?? [];
    
    // If tracks haven't been parsed yet from the stream, wait for the next event
    if (audioTracks.isEmpty && subtitleTracks.isEmpty) return;
    
    // Only skip if we already applied preferences AND no new tracks were dynamically parsed by the player
    if (_hasAppliedGlobalTracks && 
        audioTracks.length == _lastAudioTrackCount && 
        subtitleTracks.length == _lastSubtitleTrackCount) {
      return;
    }
    
    _lastAudioTrackCount = audioTracks.length;
    _lastSubtitleTrackCount = subtitleTracks.length;

    // 1. Determine Preferred Audio
    // Priority: Saved History -> Global Settings
    String preferredAudio = _currentHistory?.preferredAudioTrack ?? ref.read(preferredAudioLanguageProvider);
    
    // 2. Determine Preferred Subtitle
    // Priority: Saved History -> Global Settings
    String preferredSubtitle = _currentHistory?.preferredSubtitleTrack ?? ref.read(preferredSubtitleLanguageProvider);

    // Apply Audio Language
    if (preferredAudio != 'Original' && preferredAudio.isNotEmpty) {
      for (final track in audioTracks) {
        if (track.label == preferredAudio || track.language == preferredAudio ||
            _isLanguageMatch(track.label ?? '', preferredAudio) || 
            _isLanguageMatch(track.language ?? '', preferredAudio)) {
          _betterPlayerController?.setAudioTrack(track);
          break;
        }
      }
    }

    // Apply Subtitle Language
    if (preferredSubtitle == 'Off') {
      _betterPlayerController?.setupSubtitleSource(BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none));
    } else if (preferredSubtitle != 'Auto' && preferredSubtitle.isNotEmpty) {
      for (final track in subtitleTracks) {
        if (track.name == preferredSubtitle || _isLanguageMatch(track.name ?? '', preferredSubtitle)) {
          _betterPlayerController?.setupSubtitleSource(track);
          break;
        }
      }
    }
    
    // Apply Saved Resolution Track if it exists
    if (_currentHistory?.preferredResolution != null && _currentHistory!.preferredResolution!.isNotEmpty) {
      final asmsTracks = _betterPlayerController?.betterPlayerAsmsTracks ?? [];
      for (final track in asmsTracks) {
        if ('${track.height}p' == _currentHistory!.preferredResolution) {
          _betterPlayerController?.setTrack(track);
          break;
        }
      }
    }

    _hasAppliedGlobalTracks = true;
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
        
        // Start prefetching next episode stream silently in background
        _prefetchNextEpisode();
        
        // Refresh action menus after ASMS tracks are parsed.
        setState(() {});
        // Show resume snackbar
        if (_resumePosition != null && mounted) {
          final marginHorizontal = (MediaQuery.of(context).size.width - 250) / 2;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(bottom: 32, left: marginHorizontal, right: marginHorizontal),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              content: Text(
                'Resumed from ${_formatDuration(_resumePosition!)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              duration: const Duration(seconds: 3),
              backgroundColor: const Color(0xE6000000),
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
        _applyTrackPreferences();
        unawaited(_broadcastWatchPartyPlayback(force: true));
        break;
      case BetterPlayerEventType.pause:
        unawaited(_broadcastWatchPartyPlayback(force: true));
        break;
      case BetterPlayerEventType.seekTo:
        final seekTarget = event.parameters?['duration'] as Duration?;
        if (seekTarget != null) {
          final buffered = _betterPlayerController?.videoPlayerController?.value.buffered ?? [];
          bool isOutsideBuffer = true;
          for (final range in buffered) {
            if (seekTarget >= range.start && seekTarget <= range.end) {
              isOutsideBuffer = false;
              break;
            }
          }
          if (isOutsideBuffer) {
            debugPrint('🔍 DEBUG: Seeking OUTSIDE buffer to $seekTarget! (Current buffered: $buffered)');
          } else {
            debugPrint('🔍 DEBUG: Seeking INSIDE buffer to $seekTarget.');
          }
        }
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
        _applyTrackPreferences();
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
      if ((!_hasWatchPartyContext && !service.isInSession)) {
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
        (_watchPartyService?.controllerId == null ||
            (_watchPartyService?.controllerId ?? '').trim().isEmpty) &&
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
        !service.canControlPlayback ||
        _isApplyingWatchPartyState) {
      return;
    }

    if (!_useNativePlayer && _isDirectStream && _betterPlayerController?.isVideoInitialized() != true) {
      return;
    }

    final now = DateTime.now();
    if (!force &&
        _lastWatchPartyBroadcastAt != null &&
        now.difference(_lastWatchPartyBroadcastAt!) <
            _watchPartyHostProgressInterval) {
      return;
    }

    Duration position;
    bool isPlaying;
    
    if (_useNativePlayer) {
      position = _nativePosition;
      isPlaying = _isNativePlaying;
    } else if (_isDirectStream) {
      final controller = _betterPlayerController!;
      final vpc = controller.videoPlayerController!;
      position = vpc.value.position;
      isPlaying = controller.isPlaying() == true;
    } else {
      position = _webViewPosition;
      isPlaying = true;
    }

    final mediaType = _resolvedWatchPartyMediaType();

    await service.syncPlayback(
      mediaId: widget.mediaId,
      mediaType: mediaType,
      providerIndex: _currentProviderIndex,
      season: widget.season,
      episode: _currentEpisode,
      positionMs: position.inMilliseconds,
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
    final service = _watchPartyService;
    if (!mounted || service == null) return;
    if (playback.hostId == service.userId) return;

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

    if (_useNativePlayer) {
      if (_isApplyingWatchPartyState) return;
      _isApplyingWatchPartyState = true;
      try {
        final state = _kwikPlayerKey.currentState;
        if (state == null) return;
        
        final expectedMs = playback.expectedPositionMs;
        final currentMs = _nativePosition.inMilliseconds;
        final driftMs = (currentMs - expectedMs).abs();

        if (driftMs > _watchPartyDriftThresholdMs) {
          await state.seekTo(Duration(milliseconds: math.max(0, expectedMs)));
        }

        if (playback.isPlaying && !_isNativePlaying) {
          await state.play();
        } else if (!playback.isPlaying && _isNativePlaying) {
          await state.pause();
        }
      } finally {
        Future.delayed(const Duration(milliseconds: 350), () {
          _isApplyingWatchPartyState = false;
        });
      }
      return;
    }

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
                        final canManageControl =
                            service.isHost &&
                            !participant.isHost &&
                            participant.id != service.userId;
                        final hasControl =
                            session.controllerId == participant.id;
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
                              : (hasControl
                                    ? const Text(
                                        'Can control playback',
                                        style: TextStyle(color: Colors.white70),
                                      )
                                    : null),
                          trailing: canManageControl
                              ? TextButton(
                                  onPressed: () async {
                                    if (hasControl) {
                                      await service.setPlaybackController(null);
                                    } else {
                                      await service.setPlaybackController(
                                        participant.id,
                                      );
                                    }
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          hasControl
                                              ? '${participant.name} no longer has control'
                                              : '${participant.name} can now control playback',
                                        ),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    hasControl ? 'Revoke' : 'Give control',
                                    style: TextStyle(
                                      color: NivioTheme.accentColorOf(context),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
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
    ).whenComplete(() {
      if (mounted && !_isPipMode) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });

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
    _autoFullscreenTriggeredForCurrentLoad = true;

    if (_isDirectStream) {
      // Nothing needed. PlayerScreen handles its own immersive fullscreen mode.
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        if (mounted) {
          setState(() {
            _isInFullscreen = true;
          });
          _syncFullscreenTopBarVisibility();
        }
      });
    }
  }

  void _checkNextEpisode() {
    late Duration position;
    Duration? duration;

    if (_useNativePlayer) {
      position = _nativePosition;
      duration = _nativeDuration;
    } else {
      if (_betterPlayerController?.isVideoInitialized() != true) return;
      final vpc = _betterPlayerController!.videoPlayerController!;
      position = vpc.value.position;
      duration = vpc.value.duration;
    }

    if (duration == null || duration.inSeconds <= 0) return;
    if (_isLoading) return;

    // --- Skip Intro/Outro tracking ---
    final opSkip = _skipTimes.where((s) => s.type == 'op' || s.type == 'mixed-op').firstOrNull;
    final isInIntro = opSkip != null && position >= opSkip.startTime && position < opSkip.endTime;
    if (isInIntro != _isInIntroSegment) {
      setState(() { _isInIntroSegment = isInIntro; });
    }

    final edSkip = _skipTimes.where((s) => s.type == 'ed' || s.type == 'mixed-ed').firstOrNull;
    final isInOutro = edSkip != null && position >= edSkip.startTime && position < edSkip.endTime;
    if (isInOutro != _isInOutroSegment) {
      setState(() { _isInOutroSegment = isInOutro; });
    }

    // --- Next Episode (trigger 15s before the actual end of the video) ---
    if (!_showNextEpisodeButton && !_nextEpisodeDismissed && _hasNextEpisode()) {
      final remaining = duration.inSeconds - position.inSeconds;
      if (remaining <= 15) {
        _showNextEpisodePopup();
      }
    }

    if (position >= duration - const Duration(seconds: 10) && duration.inSeconds > 0) {
      _markAsCompleted();
    }
  }

  void _skipIntro() {
    final opSkip = _skipTimes.where((s) => s.type == 'op' || s.type == 'mixed-op').firstOrNull;
    if (opSkip == null) return;

    if (_useNativePlayer) {
      _kwikPlayerKey.currentState?.seekTo(opSkip.endTime);
    } else {
      _betterPlayerController?.seekTo(opSkip.endTime);
    }
    setState(() { _isInIntroSegment = false; });
  }

  void _skipOutro() {
    final edSkip = _skipTimes.where((s) => s.type == 'ed' || s.type == 'mixed-ed').firstOrNull;
    if (edSkip == null) return;

    if (_useNativePlayer) {
      _kwikPlayerKey.currentState?.seekTo(edSkip.endTime);
    } else {
      _betterPlayerController?.seekTo(edSkip.endTime);
    }
    setState(() { _isInOutroSegment = false; });
  }

  Future<void> _prefetchNextEpisode() async {
    if (_isPrefetching) return;
    if (!_hasNextEpisode()) return;
    
    final nextEp = _currentEpisode + 1;
    if (_prefetchedStreams.containsKey(nextEp)) return;

    final media = ref.read(selectedMediaProvider);
    if (media == null || media.mediaType != 'tv') return;

    _isPrefetching = true;
    try {
      final streamingService = ref.read(streamingServiceProvider);
      final settingsQuality = ref.read(videoQualityProvider);
      final manualQuality = ref.read(selectedQualityProvider);
      final preferredQuality = manualQuality ?? (settingsQuality == 'auto' ? null : settingsQuality);
      final subDubPref = ref.read(languagePreferencesProvider).animePreferredAudio;

      final result = await streamingService.fetchStreamUrl(
        media: media,
        season: widget.season,
        episode: nextEp,
        preferredQuality: preferredQuality,
        providerIndex: _currentProviderIndex,
        subDubPreference: subDubPref,
        onStatusUpdate: null, // Silently fetch
      );
      
      if (result != null && mounted) {
        _prefetchedStreams[nextEp] = result;
      }
    } catch (_) {
      // Ignore prefetch errors silently
    } finally {
      if (mounted) _isPrefetching = false;
    }
  }

  // —————————————————————————————————————————————————————————————————————————————————————————— Season data fetch ——————————————————————————————————————————————————————————————————————————————————————————
  Future<void> _fetchSeasonData() async {
    try {
      final tmdbService = ref.read(tmdbServiceProvider);
      final seasonData = await tmdbService.getSeasonInfo(
        widget.mediaId,
        widget.season,
      );
      if (mounted) {
        setState(() {
          _currentSeasonData = seasonData;
        });
      }
    } catch (_) {}
  }

  // —————————————————————————————————————————————————————————————————————————————————————————— Next episode popup ——————————————————————————————————————————————————————————————————————————————————————————
  void _showNextEpisodePopup() {
    if (!mounted || _showNextEpisodeButton || _nextEpisodeDismissed || _nextEpisodeCountdown != null) return;
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
    
    Duration dur;
    if (_useNativePlayer) {
      dur = _nativeDuration;
    } else {
      final vpc = _betterPlayerController?.videoPlayerController;
      dur = vpc?.value.duration ?? Duration.zero;
    }
    final historyService = ref.read(watchHistoryServiceProvider);
    await historyService.updateProgress(
      tmdbId: widget.mediaId,
      mediaType: media.mediaType,
      title: media.title ?? media.name ?? 'Unknown',
      posterPath: media.backdropPath ?? media.posterPath,
      currentSeason: widget.season,
      currentEpisode: _currentEpisode,
      totalSeasons: 1,
      totalEpisodes: null,
      lastPosition: dur,
      totalDuration: dur,
    );
  }

  // —————————————————————————————————————————————————————————————————————————————————————————— WebView event handler ——————————————————————————————————————————————————————————————————————————————————————————

  bool _hasNextEpisode() {
    final media = ref.read(selectedMediaProvider);
    if (media == null || media.mediaType != 'tv') return false;
    if (_currentSeasonData != null) {
      return _currentEpisode < _currentSeasonData!.episodes.length;
    }
    return true;
  }

  void _playNextEpisode() {
    _playEpisode(_currentEpisode + 1);
  }

  void _playEpisode(int episodeNumber) {
    if (_currentEpisode == episodeNumber) return;
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
    // Pause native player immediately to prevent audio bleed during delay
    if (_useNativePlayer) {
      _kwikPlayerKey.currentState?.pause();
    }

    // Delay to let the fullscreen route fully pop before disposing
    Future.delayed(Duration(milliseconds: wasFullScreen ? 300 : 50), () {
      if (!mounted) return;
      final oldController = _betterPlayerController;
      _progressTimer?.cancel();
      setState(() {
        _currentEpisode = episodeNumber;
        _showNextEpisodeButton = false;
        _nextEpisodeDismissed = false;
        _nextEpisodeCountdown = null;
        _isLoading = true;
        _error = null;
        _retryCount = 0;
        _streamResult = null;
        _betterPlayerController = null;
        _nativePosition = Duration.zero;
        _nativeDuration = Duration.zero;
        _skipTimes = [];
        _isInIntroSegment = false;
        _isInOutroSegment = false;
        _isFetchingSkipTimes = false;
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
        providerIndex: _currentProviderIndex,
        onEpisodeSelected: (episodeNum) {
          _playEpisode(episodeNum);
        },
      ),
    ).whenComplete(() {
      if (mounted && !_isPipMode) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
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

    ref.read(watchHistoryServiceProvider).saveTrackPreferences(widget.mediaId, providerIndex: providerIndex);

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

  void _applyDisplaySettings({bool refreshUi = true}) {
    final controller = _betterPlayerController;
    if (controller == null) return;
    // Apply aspect ratio first, then fit (fit emits refresh event in BetterPlayer).
    final screenAspectRatio = MediaQuery.of(context).size.width / MediaQuery.of(context).size.height;
    controller.setOverriddenAspectRatio(screenAspectRatio);
    controller.setOverriddenFit(
      _displayFitOptions[_selectedDisplayFitKey] ?? BoxFit.cover,
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
    ).whenComplete(() {
      if (mounted && !_isPipMode) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
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

    final currentPosition = _isDirectStream
        ? _betterPlayerController?.videoPlayerController?.value.position
        : _webViewPosition;
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
    
    if (!_isDirectStream && _streamResult != null && _streamResult!.sources.isNotEmpty) {
      final currentAudio = ref.read(languagePreferencesProvider).animePreferredAudio.toLowerCase();
      final isDubTarget = currentAudio == 'dub';
      
      StreamSource? bestMatch;
      if (normalizedTarget == 'auto') {
        bestMatch = _streamResult!.sources.firstWhere(
          (s) => s.isDub == isDubTarget,
          orElse: () => _streamResult!.sources.first,
        );
      } else {
        bestMatch = _streamResult!.sources.firstWhere(
          (s) => _normalizeQualityLabel(s.quality) == normalizedTarget && s.isDub == isDubTarget,
          orElse: () => _streamResult!.sources.firstWhere(
            (s) => _normalizeQualityLabel(s.quality) == normalizedTarget,
            orElse: () => _streamResult!.sources.first,
          ),
        );
      }
      
      setState(() {
        _streamResult = _streamResult!.copyWith(
          url: bestMatch!.url,
          quality: bestMatch.quality,
        );
      });
      return;
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
    if (provider.isEmpty) return false;
    return provider.startsWith('aimi-') ||
        provider.contains('animepahe') ||
        provider.contains('allanime') ||
        provider.contains('anizone');
  }











  List<PopupMenuEntry<String>> _buildAnimeModeMenuItems() {
    final selected = ref.read(languagePreferencesProvider).animePreferredAudio.toLowerCase();
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
    final current = ref.read(languagePreferencesProvider).animePreferredAudio.toLowerCase();
    if (target == current) return;

    final currentPosition = _isDirectStream
        ? _betterPlayerController?.videoPlayerController?.value.position
        : _webViewPosition;
    await _saveProgress();
    
    await ref.read(languagePreferencesProvider.notifier).setAnimePreferredAudio(target);
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
    
    if (!_isDirectStream && _streamResult != null && _streamResult!.sources.isNotEmpty) {
      final isDubTarget = target == 'dub';
      StreamSource? bestMatch = _streamResult!.sources.firstWhere(
        (s) => s.isDub == isDubTarget,
        orElse: () => _streamResult!.sources.first,
      );
      
      setState(() {
        _streamResult = _streamResult!.copyWith(
          url: bestMatch.url,
          quality: bestMatch.quality,
          selectedAudio: target,
        );
      });
      return;
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

  // —————————————————————————————————————————————————————————————————————————————————————————— Formatting & progress ——————————————————————————————————————————————————————————————————————————————————————————
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) return '${twoDigits(h)}:${twoDigits(m)}:${twoDigits(s)}';
    return '${twoDigits(m)}:${twoDigits(s)}';
  }

  Widget _buildSingleProviderTile(int index, SearchResult? media, {bool isSubItem = false}) {
    final isCurrent = index == _currentProviderIndex;
    final providerName = StreamingService.getProviderName(index, isAnime: _isAnimeMedia(media));
    
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isSubItem ? 32.0 : 16.0, vertical: 4.0),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: isCurrent ? Theme.of(context).primaryColor.withOpacity(0.15) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        title: Text(
          providerName,
          style: TextStyle(
            color: isCurrent ? Theme.of(context).primaryColor : (isSubItem ? Colors.white70 : Colors.white),
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            fontSize: isSubItem ? 14 : 16,
          ),
        ),
        trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
        onTap: () {
          Navigator.of(context).pop();
          if (!isCurrent) _switchToProvider(index);
        },
      ),
    );
  }

  List<Widget> _buildProviderListTiles(SearchResult? media) {
    final List<Widget> widgets = [];
    List<int> currentNewTvGroup = [];
    
    void flushNewTvGroup() {
      if (currentNewTvGroup.isEmpty) return;
      final isAnyNewTvCurrent = currentNewTvGroup.contains(_currentProviderIndex);
      widgets.add(
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: isAnyNewTvCurrent,
            iconColor: Theme.of(context).primaryColor,
            collapsedIconColor: Colors.white54,
            title: Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Text(
                'NewTV Premium',
                style: TextStyle(
                  color: isAnyNewTvCurrent ? Theme.of(context).primaryColor : Colors.white,
                  fontWeight: isAnyNewTvCurrent ? FontWeight.bold : FontWeight.normal,
                  fontSize: 16,
                ),
              ),
            ),
            children: currentNewTvGroup.map((index) => _buildSingleProviderTile(index, media, isSubItem: true)).toList(),
          ),
        ),
      );
      currentNewTvGroup = [];
    }

    for (int i = 0; i < _maxProviders; i++) {
      final name = StreamingService.getProviderName(i, isAnime: _isAnimeMedia(media));
      if (name.startsWith('NewTV')) {
        currentNewTvGroup.add(i);
      } else {
        flushNewTvGroup();
        widgets.add(_buildSingleProviderTile(i, media, isSubItem: false));
      }
    }
    flushNewTvGroup();

    return widgets;
  }

  void _startProgressTracking() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_useNativePlayer) {
        _saveProgress();
      } else if (_isDirectStream) {
        if (_betterPlayerController != null &&
            _betterPlayerController!.isVideoInitialized() == true &&
            _betterPlayerController!.isPlaying() == true) {
          _saveProgress();
        }
      } else {
        // For embed players, always save progress periodically.
        // Even if we can't track precise playback time inside cross-origin iframes,
        // this ensures the episode/movie is added to the "Continue Watching" list!
        _saveProgress();
      }
    });
  }

  Future<void> _saveProgress() async {
    Duration position;
    Duration duration;
    
    if (_useNativePlayer) {
      position = _nativePosition;
      duration = _nativeDuration;
    } else if (_isDirectStream) {
      if (_betterPlayerController?.isVideoInitialized() != true) return;
      final vpc = _betterPlayerController!.videoPlayerController!;
      position = vpc.value.position;
      duration = vpc.value.duration ?? Duration.zero;
      
      // Fix for HLS streams: If the player hasn't parsed the full playlist duration yet,
      // it might report a duration smaller than our current seek position.
      // This causes progressPercent > 1.0, prematurely marking the movie as "Completed" 
      // and removing it from Continue Watching. We pad the duration to prevent this.
      if (duration < position) {
        debugPrint('⚠️ WARNING: Player reported duration (${duration.inSeconds}s) is smaller than current position (${position.inSeconds}s)! Padding duration to prevent premature completion.');
        duration = position + const Duration(minutes: 30);
      }
    } else {
      position = _webViewPosition;
      duration = _webViewDuration;
      
      // Fallback for embed players (like cross-origin iframes) where JS can't extract `<video>` duration.
      if (duration == Duration.zero) {
        duration = const Duration(minutes: 90); // Dummy duration so JSON encoding doesn't crash
      }
    }

    // Prevent division by zero crash in JSON encoding when duration is missing
    if (duration.inSeconds <= 0) return;
    
    // Cache providers safely if we are still mounted
    if (mounted) {
      _cachedHistoryService ??= ref.read(watchHistoryServiceProvider);
      _cachedMedia ??= ref.read(selectedMediaProvider);
    }
    
    final media = _cachedMedia ?? (mounted ? ref.read(selectedMediaProvider) : null);
    if (media == null) return;
    
    final historyService = _cachedHistoryService ?? (mounted ? ref.read(watchHistoryServiceProvider) : null);
    if (historyService == null) return;
    
    // Attempt to get total seasons if available
    int totalSeasons = 1;
    
    // Fire and forget progress update
    historyService.updateProgress(
      tmdbId: widget.mediaId,
      mediaType: media.mediaType,
      title: media.title ?? media.name ?? 'Unknown',
      posterPath: media.backdropPath ?? media.posterPath,
      currentSeason: widget.season,
      currentEpisode: _currentEpisode,
      totalSeasons: totalSeasons,
      totalEpisodes: _currentSeasonData?.episodes.length,
      lastPosition: position,
      totalDuration: duration,
    );
  }

  void _disposePlayer() {
    _saveProgress(); // Ensure we save one last time on exit
    _progressTimer?.cancel();
    _removeFullscreenTopBarOverlayEntry();
    if (_betterPlayerController != null) {
      final oldController = _betterPlayerController;
      _betterPlayerController = null;
      oldController!.removeEventsListener(_onBetterPlayerEvent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController.dispose(forceDispose: true);
      });
    }
  }

  @override
  void dispose() {
    const MethodChannel('com.nivio/gesture_exclusion').invokeMethod('setCanEnterPip', {'value': false});
    const MethodChannel('com.nivio/gesture_exclusion').setMethodCallHandler(null);
    const MethodChannel('puntito.simple_pip_mode').setMethodCallHandler(null);
    SimplePip().setAutoPipMode(aspectRatio: const (16, 9), autoEnter: false);
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
    _hasAppliedGlobalTracks = false;
    _focusNode.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _handleBackNavigation() {
    if (!_isDirectStream && _isInFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      setState(() {
        _isInFullscreen = false;
      });
      _syncFullscreenTopBarVisibility();
      return;
    }

    if (context.canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go('/home');
  }

  void _forceExitPlayer() {
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

  // ——————————————————————————————————————————————————————————————————————————————————————————
  void _showServerOverlayPanel() {
    final media = ref.read(selectedMediaProvider);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Server Overlay',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(24.0)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                child: Material(
                  color: const Color(0x99101010),
                  child: SizedBox(
                    width: 350,
                    height: double.infinity,
              child: SafeArea(
                left: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Row(
                        children: [
                          const Icon(Icons.dns, color: Colors.white, size: 28),
                          const SizedBox(width: 16),
                          const Text('Select Server', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: _buildProviderListTiles(media),
                      ),
                    ),
                  ],
                ), // Column
              ), // SafeArea
            ), // SizedBox
            ), // Material
          ), // BackdropFilter
        ), // ClipRRect
      ), // Material
    ); // Align
  },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutExpo),
          ),
          child: child,
        );
      },
    ).whenComplete(() {
      if (mounted && !_isPipMode) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  Future<void> _switchNativeStreamSource(StreamSource source) async {
    final currentPos = _nativePosition;
    Navigator.of(context).pop(); // Close settings panel
    setState(() {
      _isLoading = true;
      _useNativePlayer = false; // Temporarily hide KwikNativePlayer
    });

    if (source.url.contains('kwik.cx')) {
      final extraction = await KwikExtractorService.extract(source.url);
      if (extraction != null) {
        final proxy = HlsProxyService.instance;
        await proxy.start();
        final proxiedUrl = proxy.getProxyUrl(extraction.m3u8Url, extraction.userAgent, extraction.cookies, referer: source.url);
        _useNativePlayer = true;
        _nativeUrl = proxiedUrl;
        _nativeStartAt = currentPos;
        _streamResult = _streamResult!.copyWith(url: source.url);
        setState(() {
          _isLoading = false;
        });
        _startProgressTracking();
      } else {
        setState(() {
          _error = "Failed to extract video stream";
          _isLoading = false;
        });
      }
    } else {
      _useNativePlayer = true;
      _nativeUrl = source.url;
      _nativeStartAt = currentPos;
      _streamResult = _streamResult!.copyWith(url: source.url);
      setState(() {
        _isLoading = false;
      });
      _startProgressTracking();
    }
  }

  void _showSettingsOverlayPanel() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Settings Overlay',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(24.0)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                child: Material(
                  color: const Color(0x99101010),
                  child: SizedBox(
                    width: 350,
                    height: double.infinity,
              child: SafeArea(
                left: false,
                child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        final asmsTracks = _betterPlayerController?.betterPlayerAsmsTracks ?? [];
                        final currentAsmsTrack = _betterPlayerController?.betterPlayerAsmsTrack;
                        final resolutions = _betterPlayerController?.betterPlayerDataSource?.resolutions ?? {};
                        final audioTracks = _betterPlayerController?.betterPlayerAsmsAudioTracks ?? [];
                        final currentAudioTrack = _betterPlayerController?.betterPlayerAsmsAudioTrack;
                        final subtitleSources = _betterPlayerController?.betterPlayerSubtitlesSourceList ?? [];
                        final currentSubtitle = _betterPlayerController?.betterPlayerSubtitlesSource;

                        final streamSources = _streamResult?.sources ?? [];
                        final isNative = _useNativePlayer && streamSources.isNotEmpty;
                        
                        final nativeCurrentSource = isNative ? streamSources.firstWhere((s) => s.url == _streamResult?.url, orElse: () => streamSources.first) : null;
                        
                        // Find unique qualities for current audio
                        final allQualitiesForCurrentAudio = isNative ? streamSources.where((s) => s.isDub == nativeCurrentSource?.isDub).toList() : <StreamSource>[];
                        final seenQualities = <String>{};
                        final nativeQualities = <StreamSource>[];
                        for (final q in allQualitiesForCurrentAudio) {
                          if (seenQualities.add(q.quality)) {
                            nativeQualities.add(q);
                          }
                        }

                        final nativeAudios = isNative ? [
                          if (streamSources.any((s) => !s.isDub)) 'Sub',
                          if (streamSources.any((s) => s.isDub)) 'Dub',
                        ] : <String>[];

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.settings, color: Colors.white, size: 28),
                                  const SizedBox(width: 16),
                                  const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                padding: EdgeInsets.zero,
                                children: [
                                  Theme(
                                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      iconColor: Theme.of(context).primaryColor,
                                      collapsedIconColor: Colors.white54,
                                      leading: const Icon(Icons.aspect_ratio),
                                      title: const Text('DISPLAY FIT', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                      children: [
                                        ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                          title: Text('Contain', style: TextStyle(color: _currentFit == BoxFit.contain ? Theme.of(context).primaryColor : Colors.white)),
                                          trailing: _currentFit == BoxFit.contain ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                          onTap: () {
                                            setDialogState(() => _currentFit = BoxFit.contain);
                                            setState(() => _currentFit = BoxFit.contain);
                                            _betterPlayerController?.setOverriddenFit(BoxFit.contain);
                                          },
                                        ),
                                        ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                          title: Text('Cover', style: TextStyle(color: _currentFit == BoxFit.cover ? Theme.of(context).primaryColor : Colors.white)),
                                          trailing: _currentFit == BoxFit.cover ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                          onTap: () {
                                            setDialogState(() => _currentFit = BoxFit.cover);
                                            setState(() => _currentFit = BoxFit.cover);
                                            _betterPlayerController?.setOverriddenFit(BoxFit.cover);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  Theme(
                                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      iconColor: Theme.of(context).primaryColor,
                                      collapsedIconColor: Colors.white54,
                                      leading: const Icon(Icons.high_quality),
                                      title: const Text('QUALITY', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                      children: [
                                        if (isNative) ...[
                                          ...nativeQualities.map((source) {
                                            final isCurrent = source.url == _streamResult?.url;
                                            return ListTile(
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                              title: Text(source.quality, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                              trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                              onTap: () {
                                                _switchNativeStreamSource(source);
                                              },
                                            );
                                          }),
                                        ] else if (asmsTracks.isEmpty && resolutions.isEmpty)
                                          ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                            title: Text('Default', style: TextStyle(color: Theme.of(context).primaryColor)),
                                            trailing: Icon(Icons.check, color: Theme.of(context).primaryColor),
                                          ),
                                        if (asmsTracks.isNotEmpty) ...[
                                          ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                            title: Text('Auto', style: TextStyle(color: currentAsmsTrack == null ? Theme.of(context).primaryColor : Colors.white)),
                                            trailing: currentAsmsTrack == null ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                            onTap: () {
                                              _betterPlayerController?.setTrack(BetterPlayerAsmsTrack.defaultTrack());
                                              ref.read(watchHistoryServiceProvider).saveTrackPreferences(widget.mediaId, resolution: 'Auto');
                                              setDialogState(() {});
                                            },
                                          ),
                                            ...asmsTracks.where((track) => track.height != null && track.height! > 0).map((track) {
                                              final isCurrent = currentAsmsTrack == track;
                                              String label = '${track.height}p';
                                              return ListTile(
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                title: Text(label, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                onTap: () {
                                                  _betterPlayerController?.setTrack(track);
                                                  ref.read(watchHistoryServiceProvider).saveTrackPreferences(widget.mediaId, resolution: label);
                                                  setDialogState(() {});
                                                },
                                              );
                                            }),
                                          ],
                                          if (resolutions.isNotEmpty) ...[
                                            ...resolutions.entries.map((entry) {
                                              return ListTile(
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                title: Text(entry.key, style: const TextStyle(color: Colors.white)),
                                                onTap: () {
                                                  _betterPlayerController?.setResolution(entry.value);
                                                  setDialogState(() {});
                                                },
                                              );
                                            }),
                                          ],
                                        ],
                                      ),
                                    ),
                                  Theme(
                                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      iconColor: Theme.of(context).primaryColor,
                                      collapsedIconColor: Colors.white54,
                                      leading: const Icon(Icons.audiotrack),
                                      title: const Text('AUDIO', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                      children: [
                                        if (isNative) ...[
                                          ...nativeAudios.map((audioLabel) {
                                            final isDubTarget = audioLabel == 'Dub';
                                            final isCurrent = nativeCurrentSource?.isDub == isDubTarget;
                                            return ListTile(
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                              title: Text(audioLabel, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                              trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                              onTap: () {
                                                if (!isCurrent) {
                                                  final targetSources = streamSources.where((s) => s.isDub == isDubTarget).toList();
                                                  if (targetSources.isNotEmpty) {
                                                    final bestMatch = targetSources.firstWhere(
                                                      (s) => s.quality == nativeCurrentSource?.quality,
                                                      orElse: () => targetSources.first,
                                                    );
                                                    _switchNativeStreamSource(bestMatch);
                                                  }
                                                }
                                              },
                                            );
                                          }),
                                        ] else if (audioTracks.isEmpty)
                                          ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                            title: Text(_localAudioLang, style: TextStyle(color: Theme.of(context).primaryColor)),
                                            trailing: Icon(Icons.check, color: Theme.of(context).primaryColor),
                                          ),
                                        ...audioTracks.map((track) {
                                            final isCurrent = currentAudioTrack == track;
                                            final label = track.label ?? track.language ?? 'Audio ${track.id ?? ""}';
                                            return ListTile(
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                              title: Text(label, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                              trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                              onTap: () {
                                                _betterPlayerController?.setAudioTrack(track);
                                                ref.read(watchHistoryServiceProvider).saveTrackPreferences(widget.mediaId, audioTrack: label);
                                                setDialogState(() {});
                                              },
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  Theme(
                                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      iconColor: Theme.of(context).primaryColor,
                                      collapsedIconColor: Colors.white54,
                                      leading: const Icon(Icons.subtitles),
                                      title: const Text('SUBTITLES', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                        children: [
                                          ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                            title: Text('Off', style: TextStyle(color: currentSubtitle?.name == null || currentSubtitle?.type == BetterPlayerSubtitlesSourceType.none ? Theme.of(context).primaryColor : Colors.white)),
                                            trailing: currentSubtitle?.name == null || currentSubtitle?.type == BetterPlayerSubtitlesSourceType.none ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                            onTap: () {
                                              _betterPlayerController?.setupSubtitleSource(BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none));
                                              ref.read(watchHistoryServiceProvider).saveTrackPreferences(widget.mediaId, subtitleTrack: 'Off');
                                              setDialogState(() {});
                                            },
                                          ),
                                          ...subtitleSources.where((sub) => sub.type != BetterPlayerSubtitlesSourceType.none).map((sub) {
                                            final isCurrent = currentSubtitle == sub;
                                            final label = sub.name ?? 'Subtitle';
                                            return ListTile(
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                              title: Text(label, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                              trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                              onTap: () {
                                                _betterPlayerController?.setupSubtitleSource(sub);
                                                ref.read(watchHistoryServiceProvider).saveTrackPreferences(widget.mediaId, subtitleTrack: label);
                                                setDialogState(() {});
                                              },
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  Theme(
                                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      iconColor: Theme.of(context).primaryColor,
                                      collapsedIconColor: Colors.white54,
                                      leading: const Icon(Icons.format_size),
                                      title: const Text('SUBTITLE SIZE', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                      children: [
                                        ...subtitleFontSizeOptions.entries.map((entry) {
                                          final currentSize = ref.read(subtitleFontSizeProvider);
                                          final isCurrent = currentSize == entry.value;
                                          return ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                            title: Text(entry.key, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                            trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                            onTap: () {
                                              ref.read(subtitleFontSizeProvider.notifier).setSize(entry.value);
                                              _betterPlayerController?.setSubtitlesFontSize(entry.value);
                                              setDialogState(() {});
                                            },
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                  Theme(
                                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      iconColor: Theme.of(context).primaryColor,
                                      collapsedIconColor: Colors.white54,
                                      leading: const Icon(Icons.sync),
                                      title: const Text('SUBTITLE SYNC', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  IconButton(
                                                    onPressed: () {
                                                      _updateSubtitleDelay(-250);
                                                      setDialogState(() {});
                                                    },
                                                    icon: const Icon(Icons.fast_rewind, color: Colors.white70),
                                                    tooltip: '-250ms',
                                                  ),
                                                  IconButton(
                                                    onPressed: () {
                                                      _updateSubtitleDelay(-50);
                                                      setDialogState(() {});
                                                    },
                                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                '${_subtitleDelayMs > 0 ? '+' : ''}$_subtitleDelayMs ms',
                                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                              ),
                                              Row(
                                                children: [
                                                  IconButton(
                                                    onPressed: () {
                                                      _updateSubtitleDelay(50);
                                                      setDialogState(() {});
                                                    },
                                                    icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                                                  ),
                                                  IconButton(
                                                    onPressed: () {
                                                      _updateSubtitleDelay(250);
                                                      setDialogState(() {});
                                                    },
                                                    icon: const Icon(Icons.fast_forward, color: Colors.white70),
                                                    tooltip: '+250ms',
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                                          child: Text('Negative values show subtitles earlier, positive values show them later.',
                                            style: TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                  }
                ),
              ), // SafeArea
            ), // SizedBox
            ), // Material
          ), // BackdropFilter
        ), // ClipRRect
      ), // Material
    ); // Align
  },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutExpo),
          ),
          child: child,
        );
      },
    ).whenComplete(() {
      if (mounted && !_isPipMode) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });
  }

  Widget _buildPlayerBody(bool isPortrait) {
    if (_isLoading) return _buildLoadingState();
    if (_error != null) return _buildErrorState();
    if (_useNativePlayer && _nativeUrl != null) return _buildDirectStreamLayout(isPortrait);
    if (_streamResult != null && !_isDirectStream) return _buildDirectStreamLayout(isPortrait);
    if (_betterPlayerController == null) return _buildLoadingState();

    return _buildDirectStreamLayout(isPortrait);
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    if (_isPipMode) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildDirectStreamLayout(isPortrait, isPipMode: true),
      );
    }

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
            appBar: null,
            body: _buildPlayerBody(isPortrait),
          ),
        ),
      ),
    );
  }

  
  Timer? _webViewControlsTimer;

  void _toggleWebViewControls() {
    setState(() {
      _isInFullscreen = !_isInFullscreen;
    });
    _webViewControlsTimer?.cancel();
    if (_isInFullscreen) {
      _webViewControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _isInFullscreen = false;
          });
        }
      });
    }
  }

  // ─── WebView player (embed fallback) ───────────────────────────────────────
  Widget _buildWebViewPlayer() {
    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: (_) => _toggleWebViewControls(),
              behavior: HitTestBehavior.translucent,
              child: WebViewPlayer(
                key: ValueKey(_streamResult!.url),
                    streamUrl: _streamResult!.url,
                    headers: _streamResult!.headers,
                    title:
                      ref.read(selectedMediaProvider)?.title ??
                      ref.read(selectedMediaProvider)?.name ??
                      'Video',
                  onPlayerEvent: _handlePlayerEvent,
                  onEpisodeChanged: (season, episode) {
                    if (!mounted) return;
                    if (_currentEpisode != episode) {
                      setState(() {
                        _currentEpisode = episode;
                      });
                      _trackInitialPlay();
                    }
                  },
                  onError: (errorMessage) {
                    if (!mounted) return;
                    debugPrint("WebView failed with error: \$errorMessage, trying next provider...");
                    if (_currentProviderIndex < _maxProviders - 1) {
                      setState(() {
                        _currentProviderIndex++;
                        _error = 'Provider unavailable, switching to next...';
                      });
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (mounted) _initializePlayer();
                      });
                    } else {
                      setState(() {
                        _error = 'All providers failed. Video unavailable.';
                      });
                    }
                  },
                  onEnterFullscreen: () {
                    _setFullscreenTopBarVisibility(true);
                  },
                  onExitFullscreen: () {
                    _setFullscreenTopBarVisibility(false);
                  },
                  onShowEpisodesRequested: () {
                    _showEpisodesBottomSheet();
                  },
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IgnorePointer(
                ignoring: !_isInFullscreen,
                child: AnimatedOpacity(
                  opacity: _isInFullscreen ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_buildQualityOptions().length > 1) ...[
                      _buildQualityFloatingButton(),
                      const SizedBox(width: 8),
                    ],
                    if (_isAimiAnimeStream()) ...[
                      _buildAudioFloatingButton(),
                      const SizedBox(width: 8),
                    ],
                    _buildServerFloatingButton(),
                    if (ref.read(selectedMediaProvider)?.mediaType == 'tv') ...[
                      const SizedBox(width: 8),
                      _buildEpisodesFloatingButton(),
                    ],
                  ],
                ),
              ),
            ),
            ),
          ],
        ),
    );
  }

  Widget _buildEpisodesFloatingButton() {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          _setFullscreenTopBarVisibility(false); // Hide if we were in fullscreen
          _showEpisodesBottomSheet();
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.list, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text('Episodes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerFloatingButton() {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          _setFullscreenTopBarVisibility(false);
          _showServerOverlayPanel();
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.dns, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text('Server', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityFloatingButton() {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: PopupMenuButton<String>(
        tooltip: 'Quality',
        onSelected: _switchQuality,
        itemBuilder: (context) => _buildQualityMenuItems(),
        offset: const Offset(0, 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.hd, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text('Quality', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioFloatingButton() {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: PopupMenuButton<String>(
        tooltip: 'Audio',
        onSelected: _switchAnimeMode,
        itemBuilder: (context) => _buildAnimeModeMenuItems(),
        offset: const Offset(0, 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.record_voice_over, color: Colors.white, size: 20),
              SizedBox(width: 6),
              Text('Audio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  void _handlePlayerEvent(String event, double currentTime, double duration) {
    if (!mounted) return;
    
    if (event == 'timeupdate') {
      _webViewPosition = Duration(milliseconds: (currentTime * 1000).toInt());
      _webViewDuration = Duration(milliseconds: (duration * 1000).toInt());
      
      // Also broadcast watch party progress if we are the host
      // Since _broadcastWatchPartyPlayback handles interval throttling, we can call it safely
      _broadcastWatchPartyPlayback(force: false);

      final media = ref.read(selectedMediaProvider);
      if (media != null && media.mediaType == 'tv') {
        if (_hasNextEpisode()) {
          final remaining = duration - currentTime;
          if (duration > 0 && remaining <= 15 && !_showNextEpisodeButton) {
            _showNextEpisodePopup();
          }
        }
      }
    } else if (event == 'ended') {
      _markAsCompleted();
      final media = ref.read(selectedMediaProvider);
      if (media != null && media.mediaType == 'tv' && _hasNextEpisode()) {
         _playNextEpisode();
      }
    }
  }


  Widget _buildDirectStreamLayout(bool isPortrait, {bool isPipMode = false}) {
    return Column(
      children: [
        Expanded(
          child: SizedBox.expand(
            child: Stack(
              children: [
                _useNativePlayer 
                    ? _buildNativePlayer(isPipMode: isPipMode)
                    : (!_isDirectStream && _streamResult != null) 
                        ? _buildWebViewPlayer() 
                        : _buildVideoPlayer(isPipMode: isPipMode),
                // Skip Intro button
                if (_isInIntroSegment && !isPipMode)
                  Positioned(
                    right: 24,
                    bottom: 80,
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _skipIntro,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.skip_next_rounded, color: Colors.black87, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'Skip Intro',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Skip Outro button
                if (_isInOutroSegment && !isPipMode)
                  Positioned(
                    right: 24,
                    bottom: 80,
                    child: AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _skipOutro,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.skip_next_rounded, color: Colors.black87, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'Skip Outro',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNativePlayer({bool isPipMode = false}) {
    final media = ref.read(selectedMediaProvider);
    String? subtitle = media?.mediaType == 'tv' ? 'S${widget.season} E$_currentEpisode' : null;
    
    if (media?.mediaType == 'tv' && _currentSeasonData != null) {
      try {
        final episode = _currentSeasonData!.episodes.firstWhere((e) => e.episodeNumber == _currentEpisode);
        if (episode.episodeName != null && episode.episodeName!.isNotEmpty && !episode.episodeName!.startsWith('Episode')) {
          subtitle = '$subtitle - ${episode.episodeName}';
        }
      } catch (e) {}
    }
    
    final title = media?.title ?? media?.name ?? 'Playing';
    return KwikNativePlayer(
      isPipMode: isPipMode,
      key: _kwikPlayerKey,
      url: _nativeUrl!,
      headers: _nativeHeaders ?? {},
      startAt: _nativeStartAt,
      initialSubtitleDelayMs: _subtitleDelayMs,
      title: title,
      subtitle: subtitle,
      providerName: _currentProvider,
      onProgress: (pos, dur) {
        _nativePosition = pos;
        _nativeDuration = dur;
        _checkNextEpisode();
      },
      onPlayingChanged: (playing) {
        _isNativePlaying = playing;
        if (playing) {
          // Pre-fetch the next episode stream in the background if not done already
          _prefetchNextEpisode();
        }
      },
      onEnded: () {
        _markAsCompleted();
        if (_hasNextEpisode()) {
          _showNextEpisodePopup();
        }
      },
      onBack: _handleBackNavigation,
      onSettings: _showSettingsOverlayPanel,
      onServerChange: _showServerOverlayPanel,
      onEpisodes: (media?.mediaType == 'tv') ? _showEpisodesBottomSheet : null,
    );
  }

  // ignore: unused_element
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
                      icon: const Icon(
                        Icons.chevron_left,
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
                                  if (widget.isLive) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.8),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'LIVE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      widget.directStreamTitle ??
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
                            _buildServerFloatingButton(),
                            const SizedBox(width: 8),
                            if (ref.read(selectedMediaProvider)?.mediaType == 'tv')
                              IconButton(
                                tooltip: 'Episodes',
                                onPressed: () {
                                  _setFullscreenTopBarVisibility(false);
                                  _showEpisodesBottomSheet();
                                },
                                icon: const Icon(
                                  Icons.list,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            if (watchPartySession != null)
                              IconButton(
                                tooltip: 'Watch Party',
                                onPressed: _showWatchPartyDetailsSheet,
                                icon: const Icon(
                                  Icons.group,
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
                             if (_buildQualityOptions().length > 1)
                              _buildTopActionMenuButton<String>(
                                menuId: 'fs-quality-menu',
                                icon: Icon(Icons.hd, color: Colors.white),
                                tooltip: 'Quality',
                                itemBuilder: _buildQualityMenuItems,
                                onSelected: _switchQuality,
                              ),
                            _buildTopActionMenuButton<int>(
                              menuId: 'fs-server-menu',
                              icon: const Icon(
                                Icons.sync,
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
    _setFullscreenTopBarVisibility(shouldShow);
  }

  void _setFullscreenTopBarVisibility(bool shouldShow) {
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
    final isFullscreen = _betterPlayerController?.isFullScreen == true || (!_isDirectStream && _isInFullscreen);
    if (isFullscreen) {
      if (_isDirectStream) {
        _betterPlayerController?.exitFullScreen();
        Future.delayed(const Duration(milliseconds: 220), () {
          if (!mounted) return;
          _forceExitPlayer();
        });
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        setState(() {
          _isInFullscreen = false;
        });
        _syncFullscreenTopBarVisibility();
        _forceExitPlayer();
      }
      return;
    }
    _forceExitPlayer();
  }

  void _showFullscreenTopBarOverlayEntry() {
    // Disabled old overlay to prevent duplication
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
    if (episodeName == null || episodeName.trim().isEmpty || episodeName.startsWith('Episode')) {
      return fallback;
    }
    return '$fallback - $episodeName';
  }

  // ignore: unused_element
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
                if (!widget.isLive) ...[
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
                ],
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
                    if (_buildQualityOptions().length > 1)
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
                SizedBox(width: 56, height: 56, child: _NivioLoadingSpinner()),
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
                      Flexible(
                        child: Text(
                          _loadingMessage ?? (_currentProvider.isNotEmpty
                              ? _currentProvider
                              : _providerSelectorLabel(_currentProviderIndex)),
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
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
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
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

  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ BetterPlayer widget ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
  Widget _buildVideoPlayer({bool isPipMode = false}) {
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
  final int providerIndex;
  final void Function(int) onEpisodeSelected;

  const _EpisodePickerSheet({
    required this.mediaId,
    required this.currentSeason,
    required this.currentEpisode,
    required this.onEpisodeSelected,
    this.mediaType,
    this.watchPartyCode,
    this.watchPartyRole,
    this.providerIndex = 0,
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
                                    widget.onEpisodeSelected(episode.episodeNumber);
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
                                                      'E${episode.episodeNumber} - ${episode.episodeName ?? 'Episode ${episode.episodeNumber}'}',
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
