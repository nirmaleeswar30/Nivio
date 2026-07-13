import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_pip_mode/actions/pip_actions_layout.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:simple_pip_mode/simple_pip.dart';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/screens/player/widgets/custom_player_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:nivio/core/debug_log.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';

import 'package:nivio/models/season_info.dart';
import 'package:nivio/providers/media_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/providers/language_preferences_provider.dart';
import 'package:nivio/providers/watch_party_provider.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/watch_party/watch_party_models.dart';
import 'package:nivio/services/watch_party/watch_party_service_supabase.dart';
import 'package:nivio/models/watch_history.dart';
import 'package:nivio/services/watch_history_service.dart';

import 'dart:async';
import 'dart:io';
import 'package:nivio/services/download_service.dart';
import 'package:nivio/widgets/webview_player.dart';
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
    
    if (_player.platform is NativePlayer) {
      await (_player.platform as NativePlayer).setProperty('sub-delay', '${_subtitleDelayMs / 1000.0}');
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

  late final Player _player;
  late final VideoController _videoController;
  final List<StreamSubscription> _subscriptions = [];
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
  String? _selectedAudioOverride;
  bool _isInFullscreen = false;
  Duration? _resumePosition;
  WatchHistory? _currentHistory;
  
  bool _useNativePlayer = false;
  String? _nativeUrl;
  Duration _nativePosition = Duration.zero;
  Duration _nativeDuration = Duration.zero;
  bool _isNativePlaying = true;
  bool _isPipMode = false;
  final GlobalKey<_DummyState> _kwikPlayerKey = GlobalKey<_DummyState>();

  // Effective local file to play: either the explicit widget.localPath, or a
  // completed download discovered for this media. When set, playback is offline.
  String? _effectiveLocalPath;
  // ignore: unused_field
  String _localAudioLang = 'English';

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
    if (media.mediaType == 'anime') return true;
    return false;
  }

  int get _maxProviders {
    final media = ref.read(selectedMediaProvider);
    final streamingService = ref.read(streamingServiceProvider);
    return streamingService.totalProvidersFor(isAnime: _isAnimeMedia(media));
  }

  @override
  void initState() {
    super.initState();
    _loadSubtitleDelay();
    
    _player = Player();
    _videoController = VideoController(_player);

    // Register event listeners via stream subscriptions
    _setupPlayerStreams();
    
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
              _player.play();
            } else if (actionStr == 'pause') {
              _player.pause();
            } else if (actionStr == 'next' || actionStr == 'forward') {
              final pos = _player.state.position;
              _player.seek(pos + const Duration(seconds: 10));
            } else if (actionStr == 'previous' || actionStr == 'rewind') {
              final pos = _player.state.position;
              _player.seek(pos - const Duration(seconds: 10));
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
    _initializePlayer(isRetry: false);
    _initializeWatchParty();
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
    } else if ((media.mediaType == 'tv' || media.mediaType == 'anime') && (existing.currentSeason != widget.season || existing.currentEpisode != _currentEpisode)) {
      needsUpdate = true;
    }

    if (needsUpdate) {
      await historyService.updateProgress(
        tmdbId: widget.mediaId,
        mediaType: media.mediaType,
        title: media.title ?? media.name ?? 'Unknown',
        posterPath: media.posterPath ?? media.backdropPath,
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
    if (_player.state.duration == Duration.zero) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        if (_player.state.playing) {
          _player.pause();
        } else {
          _player.play();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.keyJ:
        final pos = _player.state.position;
        _player.seek(
          pos - const Duration(seconds: 10) < Duration.zero
              ? Duration.zero
              : pos - const Duration(seconds: 10),
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.keyL:
        final pos = _player.state.position;
        final dur = _player.state.duration;
        final newPos = pos + const Duration(seconds: 10);
        _player.seek(newPos > dur ? dur : newPos);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        final vol = _player.state.volume;
        _player.setVolume(vol > 0 ? 0 : 100);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        final vol = _player.state.volume;
        _player.setVolume((vol + 10).clamp(0.0, 100.0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        final vol = _player.state.volume;
        _player.setVolume((vol - 10).clamp(0.0, 100.0));
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
      if (_isAnimeMedia(media)) {
        // Anime - AniSkip
        int? malId = media.malId;
        
        // Fallback for older Watchlist/History items that don't have malId
        if (malId == null) {
          final anilistService = AniListService();
          if (media.mediaType == 'anime') {
            // New architecture: media.id is the AniList ID
            final details = await anilistService.getAnimeDetails(media.id);
            malId = details.malId;
          } else if ((media.mediaType == 'tv' || media.mediaType == 'anime')) {
            // Old architecture: media.id is the TMDB ID
            final result = await anilistService.getAniListIdFromTMDB(title: media.title ?? media.name ?? '', year: media.firstAirDate?.split('-').first, tmdbId: media.id);
            malId = result?.idMal;
          }
        }
        
        if (malId != null) {
          final times = await AniSkipService.getSkipTimes(malId, episode);
          if (mounted) setState(() { _skipTimes = times; });
        }
      } else if ((media.mediaType == 'tv' || media.mediaType == 'anime')) {
        // Normal show - TheIntroDB (v3 public API)
        final times = await TheIntroDBService.getSkipTimes(media.id, widget.season, episode);
        if (mounted) setState(() { _skipTimes = times; });
      }
    } finally {
      if (mounted) _isFetchingSkipTimes = false;
    }
  }

  // ├────────────────────────────────────────────────────────────────────────────────────────── Player initialization ──────────────────────────────────────────────────────────────────────────────────────────
  Future<void> _initializePlayer({bool isRetry = true}) async {
    _hasAppliedGlobalTracks = false;
    _autoFullscreenTriggeredForCurrentLoad = false;
    _useNativePlayer = false;
    _nativeUrl = null;
    _nativePosition = Duration.zero;
    _nativeDuration = Duration.zero;
    setState(() {
      _isLoading = true;
      _error = null;
      _loadingMessage = null;
    });

    try {
      await _loadSubtitleDelay();
      final historyService = ref.read(watchHistoryServiceProvider);
      await historyService.init();
      _currentHistory = await historyService.getHistory(widget.mediaId);

      // If the route didn't explicitly specify a provider, use the saved preference
      // Only do this if it's not a retry, so we don't infinitely loop back to a broken provider
      if (!isRetry && widget.providerIndex == null && _currentHistory?.preferredProviderIndex != null) {
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
        if (widget.mediaType == 'anime') {
          final anilistService = ref.read(aniListServiceProvider);
          media = await anilistService.getAnimeDetails(widget.mediaId);
        } else if (widget.mediaType == 'tv') {
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

      if ((media?.mediaType == 'tv' || media?.mediaType == 'anime')) {
        _fetchSeasonData();
      }
      
      if (media != null && !_isFetchingSkipTimes) {
        _fetchSkipTimes(media, _currentEpisode);
      }

      final streamingService = ref.read(streamingServiceProvider);

      String subDubPref = ref.read(languagePreferencesProvider).animePreferredAudio;
      if (_selectedAudioOverride != null && _selectedAudioOverride!.isNotEmpty) {
        subDubPref = _selectedAudioOverride!.toLowerCase().contains('dub') ? 'dub' : 'sub';
      }
      
      if (media != null) {
        setState(() => _currentProvider = 'Preparing servers...');
        await streamingService.prepareProviders(
          media: media,
          season: widget.season,
          episode: _currentEpisode,
          subDubPreference: subDubPref,
        );
        
        if (_maxProviders > 0 && _currentProviderIndex >= _maxProviders) {
          _currentProviderIndex = 0;
        }
      }

      setState(() => _currentProvider = 'Fetching stream...');

      final settingsQuality = ref.read(videoQualityProvider);
      var manualQuality = ref.read(selectedQualityProvider);
      if (manualQuality == null && _currentHistory?.preferredResolution != null && _currentHistory!.preferredResolution!.isNotEmpty) {
        manualQuality = _currentHistory!.preferredResolution;
      }
      final preferredQuality =
          manualQuality ?? (settingsQuality == 'auto' ? null : settingsQuality);
      // using the subDubPref defined above

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
          subtitles: hasSrt ? [StreamSubtitleTrack(lang: subLang, url: srtPath)] : [],
        );
      } else if (_prefetchedStreams.containsKey(_currentEpisode)) {
        // Use the silently prefetched stream to eliminate loading delays!
        result = _prefetchedStreams.remove(_currentEpisode);
      } else if (_selectedAudioOverride != null && _streamResult?.preloadedSources?.containsKey(_selectedAudioOverride) == true) {
        result = _streamResult!.preloadedSources![_selectedAudioOverride]!;
        // Preserve the cache for future switches
        result.preloadedSources = _streamResult!.preloadedSources;
      } else {
        String? targetAudio = _selectedAudioOverride ?? _currentHistory?.preferredAudioTrack ?? ref.read(preferredAudioLanguageProvider);
        if (targetAudio == 'Original') targetAudio = null;

        result = await streamingService.fetchStreamUrl(
          media: media!,
          season: widget.season,
          episode: _currentEpisode,
          preferredQuality: preferredQuality,
          providerIndex: _currentProviderIndex,
          subDubPreference: subDubPref,
          preferredAudio: targetAudio,
          onStatusUpdate: (msg) {
            if (mounted) {
              setState(() => _loadingMessage = msg);
            }
          },
        );
      }

      final res = result;
      if (res != null && res.sources.isNotEmpty && preferredQuality != null) {
        final isDubTarget = res.selectedAudio.toLowerCase() == 'dub' || res.selectedAudio.toLowerCase().contains('english');
        final normalizedTarget = _normalizeQualityLabel(preferredQuality);
        
        StreamSource? bestMatch;
        if (normalizedTarget == 'auto') {
           bestMatch = res.sources.firstWhere(
             (s) => s.isDub == isDubTarget,
             orElse: () => res.sources.first,
           );
        } else {
           bestMatch = res.sources.firstWhere(
             (s) => _normalizeQualityLabel(s.quality) == normalizedTarget && s.isDub == isDubTarget,
             orElse: () => res.sources.firstWhere(
               (s) => _normalizeQualityLabel(s.quality) == normalizedTarget,
               orElse: () => res.sources.first,
             ),
           );
        }
        result = res.copyWith(url: bestMatch.url, quality: bestMatch.quality);
      }

      if (result == null) {
        if (_currentProviderIndex < _maxProviders - 1) {
          _currentProviderIndex++;
          setState(() => _error = 'Provider unavailable, trying next...');
          await Future.delayed(const Duration(milliseconds: 500));
          _initializePlayer(isRetry: true);
          return;
        }
        throw Exception('Failed to get stream URL from all providers');
      }

      _streamResult = result;
      _currentProvider = result.provider;
      // A local downloaded file is always played directly (never via WebView).
      _isDirectStream = (widget.directStreamUrl != null || (_effectiveLocalPath != null && _effectiveLocalPath!.isNotEmpty))
          ? true
          : ref.read(streamingServiceProvider).isDirectStream(
              _currentProviderIndex,
              isAnime: _isAnimeMedia(media),
            );

      // Pre-verify the stream URL if it's a direct stream to instantly fallback without player errors
      if (_isDirectStream && result.url.startsWith('http')) {
        try {
          if (mounted) setState(() => _loadingMessage = 'Verifying stream connection...');
          
          final request = http.Request('GET', Uri.parse(result.url));
          request.headers.addAll(result.headers);
          final client = http.Client();
          final streamedResponse = await client.send(request).timeout(const Duration(seconds: 8));
          final status = streamedResponse.statusCode;
          client.close(); // Abort immediately to prevent downloading the video file

          if (status >= 400) {
            appDebugLog('❌ Stream pre-verification failed with status: $status');
            if (_currentProviderIndex < _maxProviders - 1) {
              _currentProviderIndex++;
              setState(() => _error = 'Stream returned $status, trying next...');
              await Future.delayed(const Duration(milliseconds: 500));
              _initializePlayer(isRetry: true);
              return;
            } else {
              throw Exception('Stream link is dead (HTTP $status)');
            }
          } else {
             appDebugLog('✅ Stream pre-verification passed with status: $status');
          }
        } catch (e) {
          appDebugLog('❌ Stream pre-verification error: $e');
          if (e.toString().contains('dead') || e.toString().contains('Exception')) {
             // Let it throw to the outer catch block
             rethrow;
          }
          if (_currentProviderIndex < _maxProviders - 1) {
            _currentProviderIndex++;
            setState(() => _error = 'Stream verification timeout, trying next...');
            await Future.delayed(const Duration(milliseconds: 500));
            _initializePlayer(isRetry: true);
            return;
          } else {
            throw Exception('Stream verification failed: $e');
          }
        }
      }
      
      _trackInitialPlay();

      if (media != null) {
        _preloadAvailableAudios(result, media);
      }

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

      if (_resumePosition != null) {
        startAt = _resumePosition;
      } else if (history != null &&
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

      final headers = _buildPlaybackHeaders(result.headers);

      // Configure mpv properties before opening
      if (_player.platform is NativePlayer) {
        final np = _player.platform as NativePlayer;
        await np.setProperty('hwdec', 'mediacodec'); // Hardware acceleration
        
        final debandEnabled = ref.read(videoDebandingProvider);
        appDebugLog('🔧 Video debanding filter status during player initialization: $debandEnabled');
        await np.setProperty('deband', debandEnabled ? 'yes' : 'no');
        
        await np.setProperty('volume-max', '200'); // Software volume boost
        await np.setProperty('demuxer-max-bytes', '104857600'); // 100MB buffer
        await np.setProperty('demuxer-readahead-secs', '120'); // Buffer 2 mins ahead
        await np.setProperty('sub-delay', '${_subtitleDelayMs / 1000.0}');
        final fontSize = ref.read(subtitleFontSizeProvider);
        final scale = fontSize / 18.0;
        await np.setProperty('sub-ass-override', 'scale');
        await np.setProperty('sub-scale', '$scale');
        
      }

      // Open media
      String targetUrl = result.url;
      if (targetUrl.startsWith('/') && !targetUrl.startsWith('file://')) {
        targetUrl = 'file://$targetUrl';
      }

      await _player.open(
        Media(
          targetUrl,
          httpHeaders: headers,
        ),
        play: true,
      );

      // Load custom remote subtitle if saved
      try {
        final prefs = await SharedPreferences.getInstance();
        final customSubKey = 'custom_sub_${widget.mediaId}_${widget.season}_$_currentEpisode';
        final customSubJson = prefs.getString(customSubKey);
        if (customSubJson != null) {
          final data = json.decode(customSubJson);
          final url = data['url'] as String;
          final name = data['name'] as String;
          if (url.isNotEmpty) {
            await _player.setSubtitleTrack(SubtitleTrack.uri(url, title: name));
          }
        }
      } catch (e) {
        appDebugLog('Error loading saved custom remote subtitle: $e');
      }

      if (startAt != null && startAt.inSeconds > 0) {
        appDebugLog('🎬 SEEK_DEBUG: startAt is $startAt');
        late StreamSubscription<Duration> seekSub;
        seekSub = _player.stream.position.listen((pos) {
          if (!mounted) {
            appDebugLog('🎬 SEEK_DEBUG: Player screen not mounted, cancelling seek listener');
            seekSub.cancel();
            return;
          }
          if (pos > Duration.zero && _player.state.duration > Duration.zero) {
            seekSub.cancel();
            appDebugLog('🎬 SEEK_DEBUG: Position tick is $pos (> zero) and duration is ${_player.state.duration}. Waiting 300ms for stream stabilization...');
            Future.delayed(const Duration(milliseconds: 300), () async {
              if (mounted) {
                appDebugLog('🎬 SEEK_DEBUG: Executing stabilized seek to $startAt');
                await _player.seek(startAt!);
              }
            });
          }
        });
        _subscriptions.add(seekSub);
      } else {
        appDebugLog('🎬 SEEK_DEBUG: startAt is null or zero');
      }

      final speed = ref.read(playbackSpeedProvider);
      await _player.setRate(speed);
      
      _applyDisplaySettings(refreshUi: false);
      _maybeAutoEnterFullscreenOnce();
      _prefetchNextEpisode();
      
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

      setState(() {
        _isLoading = false;
        _retryCount = 0;
      });

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
        _initializePlayer(isRetry: true);
        return;
      }

      if (_retryCount < _maxRetries &&
          (e.toString().contains('network') ||
              e.toString().contains('timeout'))) {
        await Future.delayed(const Duration(seconds: 2));
        _retryCount++;
        _initializePlayer(isRetry: true);
      }
    }
  }

  // —————————————————————————————————————————————————————————————————————————————————————————— media_kit event streams ——————————————————————————————————————————————————————————————————————————————————————————
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
    final audioTracks = _player.state.tracks.audio;
    final subtitleTracks = _player.state.tracks.subtitle;
    
    if (audioTracks.isEmpty && subtitleTracks.isEmpty) return;
    
    if (_hasAppliedGlobalTracks && 
        audioTracks.length == _lastAudioTrackCount && 
        subtitleTracks.length == _lastSubtitleTrackCount) {
      return;
    }
    
    _lastAudioTrackCount = audioTracks.length;
    _lastSubtitleTrackCount = subtitleTracks.length;

    // Determine Preferences
    String preferredAudio = _currentHistory?.preferredAudioTrack ?? ref.read(preferredAudioLanguageProvider);
    String preferredSubtitle = _currentHistory?.preferredSubtitleTrack ?? ref.read(preferredSubtitleLanguageProvider);

    // Apply Audio Track
    if (preferredAudio != 'Original' && preferredAudio.isNotEmpty) {
      for (final track in audioTracks) {
        final title = track.title ?? '';
        final lang = track.language ?? '';
        if (title == preferredAudio || lang == preferredAudio ||
            _isLanguageMatch(title, preferredAudio) || 
            _isLanguageMatch(lang, preferredAudio)) {
          _player.setAudioTrack(track);
          break;
        }
      }
    }

    // Apply Subtitle Track
    if (preferredSubtitle == 'Off') {
      _player.setSubtitleTrack(SubtitleTrack.no());
    } else if (preferredSubtitle == 'Auto' || preferredSubtitle.isEmpty) {
      _player.setSubtitleTrack(SubtitleTrack.auto());
    } else {
      bool foundNative = false;
      for (final track in subtitleTracks) {
        final title = track.title ?? '';
        final lang = track.language ?? '';
        if (title == preferredSubtitle || lang == preferredSubtitle ||
            _isLanguageMatch(title, preferredSubtitle) ||
            _isLanguageMatch(lang, preferredSubtitle)) {
          _player.setSubtitleTrack(track);
          foundNative = true;
          break;
        }
      }
      if (!foundNative && _streamResult != null && _streamResult!.subtitles.isNotEmpty) {
        for (final sub in _streamResult!.subtitles) {
          if (sub.lang == preferredSubtitle || _isLanguageMatch(sub.lang, preferredSubtitle)) {
            _player.setSubtitleTrack(SubtitleTrack.uri(sub.url, title: sub.lang));
            break;
          }
        }
      }
    }

    // Apply Saved Resolution/Video Track
    if (_currentHistory?.preferredResolution != null && _currentHistory!.preferredResolution!.isNotEmpty) {
      final videoTracks = _player.state.tracks.video;
      for (final track in videoTracks) {
        if ('${track.h}p' == _currentHistory!.preferredResolution) {
          _player.setVideoTrack(track);
          break;
        }
      }
    }

    _hasAppliedGlobalTracks = true;
  }

  Future<void> _updateLocalHistoryPreference({
    String? resolution,
    String? audioTrack,
    String? subtitleTrack,
    int? providerIndex,
  }) async {
    final service = ref.read(watchHistoryServiceProvider);
    await service.saveTrackPreferences(
      widget.mediaId,
      resolution: resolution,
      audioTrack: audioTrack,
      subtitleTrack: subtitleTrack,
      providerIndex: providerIndex,
    );
    _currentHistory = await service.getHistory(widget.mediaId);
  }

  void _setupPlayerStreams() {
    // Position/Progress stream — track preferences, next episode, watch party
    _subscriptions.add(
      _player.stream.position.listen((position) {
        if (!mounted) return;
        // appDebugLog('🎬 POSITION_DEBUG: Current player position = $position');
        _checkNextEpisode();
        unawaited(_broadcastWatchPartyPlayback(force: false));
      }),
    );

    // Playing state stream
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (!mounted) return;
        unawaited(_broadcastWatchPartyPlayback(force: true));
      }),
    );

    // Completed stream
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (!mounted || !completed) return;
        _markAsCompleted();
        if (_hasNextEpisode()) {
          _showNextEpisodePopup();
        } else {
          _promptWatchlistRemovalIfNeeded();
        }
      }),
    );

    // Tracks stream — refresh UI when new tracks are parsed
    _subscriptions.add(
      _player.stream.tracks.listen((_) {
        if (!mounted) return;
        _applyTrackPreferences();
        setState(() {});
      }),
    );

    // Error stream
    _subscriptions.add(
      _player.stream.error.listen((error) {
        if (!mounted) return;
        appDebugLog('🎬 Player error: $error');
      }),
    );

    // Buffering stream
    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        if (!mounted) return;
        // Can be used for UI indicators
      }),
    );
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

    if (!_useNativePlayer && _isDirectStream && (_player.state.duration == Duration.zero)) {
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
    
    if (_isDirectStream) {
      position = _player.state.position;
      isPlaying = _player.state.playing;
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

    if ((_player.state.duration == Duration.zero)) {
      _pendingWatchPartyPlayback = playback;
      return;
    }
    if (_isApplyingWatchPartyState) return;

    _isApplyingWatchPartyState = true;
    try {
      final expectedMs = playback.expectedPositionMs;
      final currentMs = _player.state.position.inMilliseconds;
      final driftMs = (currentMs - expectedMs).abs();

      if (driftMs > _watchPartyDriftThresholdMs) {
        await _player.seek(
          Duration(milliseconds: math.max(0, expectedMs)),
        );
      }

      final localIsPlaying = _player.state.playing;
      if (playback.isPlaying && !localIsPlaying) {
        await _player.play();
      } else if (!playback.isPlaying && localIsPlaying) {
        await _player.pause();
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
    late Duration duration;

    if (_useNativePlayer) {
      position = _nativePosition;
      duration = _nativeDuration;
    } else {
      if ((_player.state.duration == Duration.zero)) return;
      position = _player.state.position;
      duration = _player.state.duration;
    }

    if (duration.inSeconds <= 0) return;
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
      _player.seek(opSkip.endTime);
    }
    setState(() { _isInIntroSegment = false; });
  }

  void _skipOutro() {
    final edSkip = _skipTimes.where((s) => s.type == 'ed' || s.type == 'mixed-ed').firstOrNull;
    if (edSkip == null) return;

    if (_useNativePlayer) {
      _kwikPlayerKey.currentState?.seekTo(edSkip.endTime);
    } else {
      _player.seek(edSkip.endTime);
    }
    setState(() { _isInOutroSegment = false; });
  }

  Future<void> _prefetchNextEpisode() async {
    if (_isPrefetching) return;
    if (!_hasNextEpisode()) return;
    
    final nextEp = _currentEpisode + 1;
    if (_prefetchedStreams.containsKey(nextEp)) return;

    final media = ref.read(selectedMediaProvider);
    if (media == null || (media.mediaType != 'tv' && media.mediaType != 'anime')) return;

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
        preferredAudio: _selectedAudioOverride,
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
      final media = ref.read(selectedMediaProvider);
      if (media?.mediaType == 'anime') {
        final anilistService = ref.read(aniListServiceProvider);
        final seasonData = await anilistService.getAnimeSeasonData(widget.mediaId);
        if (mounted) {
          setState(() {
            _currentSeasonData = seasonData;
          });
        }
        return;
      }

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
      dur = _player.state.duration;
    }
    final historyService = ref.read(watchHistoryServiceProvider);
    await historyService.updateProgress(
      tmdbId: widget.mediaId,
      mediaType: media.mediaType,
      title: media.title ?? media.name ?? 'Unknown',
      posterPath: media.posterPath ?? media.backdropPath,
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
    if (media == null) return false;
    if (media.mediaType != 'tv' && media.mediaType != 'anime') return false; // Movies return false
    
    if (_prefetchedStreams.containsKey(_currentEpisode + 1)) return true;
    
    if (_currentSeasonData != null) {
      return _currentEpisode < _currentSeasonData!.episodes.length;
    }
    

    
    return false;
  }

  Future<void> _promptWatchlistRemovalIfNeeded() async {
    final media = ref.read(selectedMediaProvider);
    if (media == null) return;
    
    final watchlistService = ref.read(watchlistServiceProvider);
    final items = watchlistService.getAllItems();
    
    final mediaTitle = (media.title ?? media.name ?? '').toLowerCase();
    final match = items.where((w) => 
      w.id == widget.mediaId || 
      w.title.toLowerCase() == mediaTitle
    ).firstOrNull;

    if (match != null) {
      final shouldRemove = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: NivioTheme.netflixDarkGrey,
          title: const Text('Finished Watching?', style: TextStyle(color: Colors.white)),
          content: Text(
            'You have reached the end of ${match.title}. Would you like to remove it from your watchlist?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Remove', style: TextStyle(color: NivioTheme.accentColorOf(ctx))),
            ),
          ],
        ),
      );

      if (shouldRemove == true) {
        await watchlistService.removeFromWatchlist(match.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Removed ${match.title} from watchlist')),
          );
        }
      }
    }
  }

  void _playNextEpisode() {
    _playEpisode(_currentEpisode + 1);
  }

  void _playEpisode(int episodeNumber) {
    if (_currentEpisode == episodeNumber) return;
    _nextEpisodeTimer?.cancel();
    _removeOverlayEntry();
    
    final media = ref.read(selectedMediaProvider);
    if (media == null || (media.mediaType != 'tv' && media.mediaType != 'anime')) return;

    _player.stop();
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
      _nativePosition = Duration.zero;
      _nativeDuration = Duration.zero;
      _skipTimes = [];
      _isInIntroSegment = false;
      _isInOutroSegment = false;
      _isFetchingSkipTimes = false;
    });
    
    _initializePlayer();
  }

  void _showEpisodesBottomSheet() {
    final media = ref.read(selectedMediaProvider);
    if (media == null || (media.mediaType != 'tv' && media.mediaType != 'anime')) return;
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
    return ref.read(streamingServiceProvider).getProviderName(
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

  Future<void> _loadSubtitleFromFile(StateSetter setDialogState) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt'],
      );
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final fileName = result.files.single.name;
        final trackName = 'Local: $fileName';
        final newTrack = SubtitleTrack.uri('file://' + filePath, title: trackName);
        await _player.setSubtitleTrack(newTrack);
        
        // Persist local custom subtitle
        try {
          final prefs = await SharedPreferences.getInstance();
          final customSubKey = 'custom_sub_${widget.mediaId}_${widget.season}_$_currentEpisode';
          await prefs.setString(customSubKey, json.encode({
            'type': 'file',
            'name': trackName,
            'url': filePath,
          }));
          await ref.read(watchHistoryServiceProvider).saveTrackPreferences(widget.mediaId, subtitleTrack: trackName);
        } catch (e) {
          debugPrint('Failed to save local custom subtitle: $e');
        }

        if (mounted) {
          setDialogState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Loaded local subtitle: $fileName')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking subtitle file: $e');
    }
  }

  Future<void> _loadSubtitleFromUrl(StateSetter setDialogState) async {
    final textController = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F1F1F),
          title: const Text('Load Subtitle from URL', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: TextField(
            controller: textController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Enter .srt or .vtt link...',
              hintStyle: TextStyle(color: Colors.white30),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.redAccent)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, textController.text.trim()),
              child: const Text('Load', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );

    if (url != null && url.isNotEmpty) {
      Uri? parsedUri = Uri.tryParse(url);
      if (parsedUri == null || !parsedUri.hasAbsolutePath) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid URL entered.')),
          );
        }
        return;
      }
      
      final String name = parsedUri.pathSegments.isNotEmpty 
          ? parsedUri.pathSegments.last 
          : 'Remote Subtitle';

      final trackName = 'URL: $name';
      final newTrack = SubtitleTrack.uri(url, title: trackName);
      await _player.setSubtitleTrack(newTrack);

      // Persist remote custom subtitle
      try {
        final prefs = await SharedPreferences.getInstance();
        final customSubKey = 'custom_sub_${widget.mediaId}_${widget.season}_$_currentEpisode';
        await prefs.setString(customSubKey, json.encode({
          'type': 'network',
          'name': trackName,
          'url': url,
        }));
        await ref.read(watchHistoryServiceProvider).saveTrackPreferences(widget.mediaId, subtitleTrack: trackName);
      } catch (e) {
        debugPrint('Failed to save remote custom subtitle: $e');
      }

      if (mounted) {
        setDialogState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded remote subtitle: $name')),
        );
      }
    }
  }

  // ignore: unused_element
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
        ? _player.state.position
        : _webViewPosition;
    await _saveProgress();

    ref.read(selectedQualityProvider.notifier).state =
        normalizedTarget == 'auto' ? null : normalizedTarget;
    ref.read(watchHistoryServiceProvider).saveTrackPreferences(widget.mediaId, resolution: normalizedTarget);

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
    
    if (_isDirectStream) {
      if (normalizedTarget == 'auto') {
        _player.setVideoTrack(VideoTrack.auto());
        return;
      }
      final videoTracks = _player.state.tracks.video;
      for (final track in videoTracks) {
        final heightLabel = track.h != null && track.h! > 0 ? '${track.h}p' : '';
        if (heightLabel.isNotEmpty && _normalizeQualityLabel(heightLabel) == normalizedTarget) {
          _player.setVideoTrack(track);
          return;
        }
      }
    }

    if (!_isDirectStream && _streamResult != null && _streamResult!.sources.isNotEmpty) {
      final isDubTarget = _streamResult!.selectedAudio.toLowerCase() == 'dub';
      
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
      _resumePosition = currentPosition;
    });

    await _initializePlayer();
  }

  bool _hasAudioSelection() {
    if (_streamResult != null && _streamResult!.availableAudios.isNotEmpty) {
      return true;
    }
    final provider = (_streamResult?.provider ?? '').toLowerCase();
    if (provider.isEmpty) return false;
    return provider.startsWith('aimi-') ||
        provider.contains('animepahe') ||
        provider.contains('allanime') ||
        provider.contains('anizone');
  }












  Future<void> _switchAudioMode(String audioOption) async {
    final availableAudios = _streamResult?.availableAudios ?? [];
    
    // Anime fallback logic
    if (availableAudios.isEmpty) {
      final target = audioOption.toLowerCase() == 'dub' ? 'dub' : 'sub';
      final current = ref.read(languagePreferencesProvider).animePreferredAudio.toLowerCase();
      if (target == current) return;

      final currentPosition = _isDirectStream
          ? _player.state.position
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
        _webViewPosition = currentPosition; 
        _resumePosition = currentPosition;
      });

      await _initializePlayer();
      return;
    }

    // Dynamic languages from scraper logic (NetMirror)
    final currentAudio = _streamResult?.selectedAudio ?? '';
    if (audioOption.toLowerCase() == currentAudio.toLowerCase()) return;

    final currentPosition = _isDirectStream
        ? _player.state.position
        : _webViewPosition;
    await _saveProgress();
    
    _selectedAudioOverride = audioOption;
    ref.read(selectedQualityProvider.notifier).state = null;
    ref.read(watchHistoryServiceProvider).saveTrackPreferences(widget.mediaId, audioTrack: audioOption);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switching to $audioOption...'),
          duration: const Duration(seconds: 2),
          backgroundColor: NivioTheme.accentColorOf(context),
        ),
      );
    }

    final hasPreloaded = _streamResult?.preloadedSources?.containsKey(audioOption) == true;

    _disposePlayer();
    setState(() {
      _isLoading = true;
      _error = null;
      _retryCount = 0;
      if (!hasPreloaded) {
        _streamResult = null;
      }
      _webViewPosition = currentPosition; 
      _resumePosition = currentPosition;
    });

    await _initializePlayer();
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

  Widget _buildSingleProviderTile(int index, SearchResult? media) {
    final isCurrent = index == _currentProviderIndex;
    String providerName = ref.read(streamingServiceProvider).getProviderName(index, isAnime: _isAnimeMedia(media));
    
    if (providerName.startsWith('Animetsu (')) {
      providerName = providerName.substring('Animetsu ('.length);
      if (providerName.endsWith(')')) providerName = providerName.substring(0, providerName.length - 1);
    } else if (providerName.startsWith('Miruro (')) {
      providerName = providerName.substring('Miruro ('.length);
      if (providerName.endsWith(')')) providerName = providerName.substring(0, providerName.length - 1);
    } else if (providerName.startsWith('Animex (')) {
      providerName = providerName.substring('Animex ('.length);
      if (providerName.endsWith(')')) providerName = providerName.substring(0, providerName.length - 1);
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: isCurrent ? Theme.of(context).primaryColor.withOpacity(0.15) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        title: Text(
          providerName,
          style: TextStyle(
            color: isCurrent ? Theme.of(context).primaryColor : Colors.white,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            fontSize: 16,
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
    final bool isAnime = _isAnimeMedia(media);

    if (isAnime) {
      final Map<String, List<int>> groups = {};
      for (int i = 0; i < _maxProviders; i++) {
        final name = ref.read(streamingServiceProvider).getProviderName(i, isAnime: true);
        String groupName = name;
        if (name.startsWith('Animetsu')) groupName = 'Animetsu';
        else if (name.startsWith('Miruro')) groupName = 'Miruro';
        else if (name.startsWith('Animex')) groupName = 'Animex';
        
        groups.putIfAbsent(groupName, () => []).add(i);
      }

      for (final entry in groups.entries) {
        final groupName = entry.key;
        final indices = entry.value;

        if (indices.length == 1) {
          widgets.add(_buildSingleProviderTile(indices.first, media));
        } else {
          bool containsCurrent = indices.contains(_currentProviderIndex);
          widgets.add(
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: containsCurrent,
                iconColor: Theme.of(context).primaryColor,
                collapsedIconColor: Colors.white70,
                title: Text(
                  groupName,
                  style: TextStyle(
                    color: containsCurrent ? Theme.of(context).primaryColor : Colors.white,
                    fontWeight: containsCurrent ? FontWeight.bold : FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                children: indices.map((i) => _buildSingleProviderTile(i, media)).toList(),
              ),
            ),
          );
        }
      }
    } else {
      for (int i = 0; i < _maxProviders; i++) {
        widgets.add(_buildSingleProviderTile(i, media));
      }
    }

    return widgets;
  }

  void _startProgressTracking() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isDirectStream) {
        if (_player.state.duration > Duration.zero && _player.state.playing) {
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
    
    if (_isDirectStream) {
      if (_player.state.duration == Duration.zero) return;
      position = _player.state.position;
      duration = _player.state.duration;
      
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
      posterPath: media.posterPath ?? media.backdropPath,
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
    _player.stop();
  }

  @override
  void dispose() {
    try {
      ScreenBrightness().resetScreenBrightness();
    } catch (e) {
      debugPrint('Error resetting screen brightness: $e');
    }
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
    if (_player.state.duration > Duration.zero) {
      _saveProgress();
    }
    _player.dispose();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
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

  // ignore: unused_element
  Future<void> _switchNativeStreamSource(StreamSource source) async {
    Navigator.of(context).pop(); // Close settings panel
    setState(() {
      _isLoading = true;
      _useNativePlayer = false; // Temporarily hide KwikNativePlayer
    });

    if (source.url.contains('kwik.cx')) {
      final dynamic extraction = null;
      if (extraction != null) {
        final proxy = HlsProxyService.instance;
        await proxy.start();
        final proxiedUrl = proxy.getProxyUrl(extraction.m3u8Url, extraction.userAgent, extraction.cookies, referer: source.url);
        _useNativePlayer = true;
        _nativeUrl = proxiedUrl;
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
      _streamResult = _streamResult!.copyWith(url: source.url);
      setState(() {
        _isLoading = false;
      });
      _startProgressTracking();
    }
  }

  // ignore: unused_element
  void _showSettingsOverlayPanel() {
    String? tempSubtitleTrackId;
    String? tempAudioTrackId;
    String? tempVideoTrackId;

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
                          final videoTracks = _player.state.tracks.video;
                          final currentVideoTrack = _player.state.track.video;
                          final audioTracks = _player.state.tracks.audio;
                          final currentAudioTrack = _player.state.track.audio;
                          final subtitleTracks = _player.state.tracks.subtitle;
                          final currentSubtitleTrack = _player.state.track.subtitle;

                          final activeSubtitleId = tempSubtitleTrackId ?? currentSubtitleTrack.id;
                          final activeAudioId = tempAudioTrackId ?? currentAudioTrack.id;
                          final activeVideoId = tempVideoTrackId ?? currentVideoTrack.id;

                          final streamSources = _streamResult?.sources ?? [];
                          final useScraperQualities = streamSources.length > 1;

                          final scraperCurrentSource = useScraperQualities
                              ? streamSources.firstWhere((s) => s.url == _streamResult?.url, orElse: () => streamSources.first)
                              : null;

                          // Find unique qualities for current audio
                          final allQualitiesForCurrentAudio = useScraperQualities
                              ? streamSources.where((s) => s.isDub == scraperCurrentSource?.isDub).toList()
                              : <StreamSource>[];
                          final seenQualities = <String>{};
                          final scraperQualities = <StreamSource>[];
                          for (final q in allQualitiesForCurrentAudio) {
                            if (seenQualities.add(q.quality)) {
                              scraperQualities.add(q);
                            }
                          }

                          final scraperAudios = useScraperQualities ? [
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
                                        children: _displayFitOrder.map((fitKey) {
                                          final label = _displayFitLabels[fitKey] ?? fitKey;
                                          final isSelected = fitKey == _selectedDisplayFitKey;
                                          return ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                            title: Text(label, style: TextStyle(color: isSelected ? Theme.of(context).primaryColor : Colors.white)),
                                            trailing: isSelected ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                            onTap: () {
                                              _switchDisplayMode(fitKey);
                                              setDialogState(() {});
                                            },
                                          );
                                        }).toList(),
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
                                          // 1. Native HLS/manifest resolution tracks of the currently loaded stream
                                          if (videoTracks.where((t) => t.id != 'auto' && t.id != 'no').isNotEmpty) ...[
                                            ListTile(
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                              title: Text('Auto', style: TextStyle(color: activeVideoId == 'auto' ? Theme.of(context).primaryColor : Colors.white)),
                                              trailing: activeVideoId == 'auto' ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                              onTap: () async {
                                                tempVideoTrackId = 'auto';
                                                _player.setVideoTrack(VideoTrack.auto());
                                                await _updateLocalHistoryPreference(resolution: 'Auto');
                                                setDialogState(() {});
                                              },
                                            ),
                                            ...videoTracks.where((track) => track.id != 'auto' && track.id != 'no').map((track) {
                                              final label = track.title ?? ((track.h != null && track.h! > 0) ? '${track.h}p' : 'Track ${track.id}');
                                              final isCurrent = activeVideoId == track.id;
                                              return ListTile(
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                title: Text(label, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                onTap: () async {
                                                  tempVideoTrackId = track.id;
                                                  _player.setVideoTrack(track);
                                                  await _updateLocalHistoryPreference(resolution: label);
                                                  setDialogState(() {});
                                                },
                                              );
                                            }),
                                          ],
                                          // Divider between native resolution and different server options
                                          if (useScraperQualities && videoTracks.where((t) => t.id != 'auto' && t.id != 'no').isNotEmpty)
                                            const Padding(
                                              padding: EdgeInsets.symmetric(vertical: 8.0),
                                              child: Divider(color: Colors.white24, height: 1),
                                            ),
                                          // 2. Scraper-level sources/servers (if any)
                                          if (useScraperQualities) ...[
                                            ...scraperQualities.map((source) {
                                              final isCurrent = source.url == _streamResult?.url;
                                              String label = source.quality;
                                              if (label.startsWith('auto (') && label.endsWith(')')) {
                                                final serverName = label.substring(6, label.length - 1);
                                                label = 'Server: $serverName';
                                              }
                                              return ListTile(
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                title: Text(label, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                onTap: () {
                                                  _switchQuality(source.quality);
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
                                          if (_hasAudioSelection()) ...[
                                            if ((_streamResult?.availableAudios ?? []).isNotEmpty) ...[
                                              ...(_streamResult!.availableAudios).map((audio) {
                                                final isCurrent = audio.toLowerCase() == (_streamResult!.selectedAudio).toLowerCase();
                                                return ListTile(
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                  title: Text(audio, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                  trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                  onTap: () {
                                                    Navigator.pop(context);
                                                    _switchAudioMode(audio);
                                                  },
                                                );
                                              }),
                                            ] else ...[
                                              ...['sub', 'dub'].map((mode) {
                                                final isCurrent = mode == ref.read(languagePreferencesProvider).animePreferredAudio.toLowerCase();
                                                return ListTile(
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                  title: Text(mode == 'dub' ? 'DUB' : 'SUB', style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                  trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                  onTap: () {
                                                    Navigator.pop(context);
                                                    _switchAudioMode(mode);
                                                  },
                                                );
                                              }),
                                            ],
                                          ] else if (useScraperQualities) ...[
                                            ...scraperAudios.map((audioLabel) {
                                              final isDubTarget = audioLabel == 'Dub';
                                              final isCurrent = scraperCurrentSource?.isDub == isDubTarget;
                                              return ListTile(
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                title: Text(audioLabel, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                onTap: () {
                                                  if (!isCurrent) {
                                                    final targetSources = streamSources.where((s) => s.isDub == isDubTarget).toList();
                                                    if (targetSources.isNotEmpty) {
                                                      final bestMatch = targetSources.firstWhere(
                                                        (s) => s.quality == scraperCurrentSource?.quality,
                                                        orElse: () => targetSources.first,
                                                      );
                                                      _switchQuality(bestMatch.quality);
                                                      setDialogState(() {});
                                                    }
                                                  }
                                                },
                                              );
                                            }),
                                          ] else if (audioTracks.isEmpty) ...[
                                            ListTile(
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                              title: Text(_localAudioLang, style: TextStyle(color: Theme.of(context).primaryColor)),
                                              trailing: Icon(Icons.check, color: Theme.of(context).primaryColor),
                                            ),
                                          ] else ...[
                                            ...audioTracks.where((track) => track.id != 'auto' && track.id != 'no').map((track) {
                                              final isCurrent = activeAudioId == track.id;
                                              final label = track.title ?? track.language ?? 'Audio ${track.id}';
                                              return ListTile(
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                title: Text(label, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                onTap: () async {
                                                  tempAudioTrackId = track.id;
                                                  _player.setAudioTrack(track);
                                                  await _updateLocalHistoryPreference(audioTrack: label);
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
                                        leading: const Icon(Icons.subtitles),
                                        title: const Text('SUBTITLE SETTINGS', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                        children: [
                                          // 1. TRACKS
                                          Theme(
                                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                            child: ExpansionTile(
                                              title: const Text('TRACKS', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                                              children: [
                                                ListTile(
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                  title: Text('Off', style: TextStyle(color: activeSubtitleId == 'no' ? Theme.of(context).primaryColor : Colors.white)),
                                                  trailing: activeSubtitleId == 'no' ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                  onTap: () async {
                                                    tempSubtitleTrackId = 'no';
                                                    _player.setSubtitleTrack(SubtitleTrack.no());
                                                    await _updateLocalHistoryPreference(subtitleTrack: 'Off');
                                                    setDialogState(() {});
                                                  },
                                                ),
                                                ListTile(
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                  leading: const Icon(Icons.folder_open, color: Colors.white70, size: 20),
                                                  title: const Text('Load from Local File (.srt, .vtt)', style: TextStyle(color: Colors.white70)),
                                                  onTap: () => _loadSubtitleFromFile(setDialogState),
                                                ),
                                                ListTile(
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                  leading: const Icon(Icons.link, color: Colors.white70, size: 20),
                                                  title: const Text('Load from URL (Internet)', style: TextStyle(color: Colors.white70)),
                                                  onTap: () => _loadSubtitleFromUrl(setDialogState),
                                                ),
                                                if (_streamResult != null && _streamResult!.subtitles.isNotEmpty) ...[
                                                  ..._streamResult!.subtitles.map((sub) {
                                                    final isCurrent = activeSubtitleId == sub.url || 
                                                        (tempSubtitleTrackId == null && (currentSubtitleTrack.title?.toLowerCase() == sub.lang.toLowerCase() || 
                                                        currentSubtitleTrack.id.contains(sub.url)));
                                                    return ListTile(
                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                      title: Text(sub.lang, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                      trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                      onTap: () async {
                                                        tempSubtitleTrackId = sub.url;
                                                        _player.setSubtitleTrack(SubtitleTrack.uri(sub.url, title: sub.lang));
                                                        await _updateLocalHistoryPreference(subtitleTrack: sub.lang);
                                                        setDialogState(() {});
                                                      },
                                                    );
                                                  }),
                                                ],
                                                ...subtitleTracks.where((sub) => sub.id != 'auto' && sub.id != 'no').map((sub) {
                                                  final isCurrent = activeSubtitleId == sub.id;
                                                  final label = sub.title ?? sub.language ?? 'Subtitle ${sub.id}';
                                                  if (_streamResult != null && _streamResult!.subtitles.any((s) => s.lang == label)) {
                                                    return const SizedBox.shrink();
                                                  }
                                                  return ListTile(
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                    title: Text(label, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                    trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                    onTap: () async {
                                                      tempSubtitleTrackId = sub.id;
                                                      _player.setSubtitleTrack(sub);
                                                      await _updateLocalHistoryPreference(subtitleTrack: label);
                                                      setDialogState(() {});
                                                    },
                                                  );
                                                }),
                                              ],
                                            ),
                                          ),
                                          // 2. SIZE
                                          Theme(
                                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                            child: ExpansionTile(
                                              title: const Text('SIZE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                                              children: [
                                                ...subtitleFontSizeOptions.entries.map((entry) {
                                                  final currentSize = ref.watch(subtitleFontSizeProvider);
                                                  final isCurrent = currentSize == entry.value;
                                                  return ListTile(
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                    title: Text(entry.key, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                    trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                    onTap: () async {
                                                      await ref.read(subtitleFontSizeProvider.notifier).setSize(entry.value);
                                                      if (_player.platform is NativePlayer) {
                                                        final scale = entry.value / 18.0;
                                                        await (_player.platform as NativePlayer).setProperty('sub-scale', '$scale');
                                                      }
                                                      setDialogState(() {});
                                                    },
                                                  );
                                                }),
                                              ],
                                            ),
                                          ),
                                          // 3. BACKGROUND
                                          Theme(
                                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                            child: ExpansionTile(
                                              title: const Text('BACKGROUND', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                                              children: [
                                                ...['Transparent', 'Semi-Transparent', 'Solid'].map((bg) {
                                                  final currentBg = ref.watch(subtitleBackgroundProvider);
                                                  final isCurrent = currentBg == bg;
                                                  return ListTile(
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                    title: Text(bg, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                    trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                    onTap: () async {
                                                      await ref.read(subtitleBackgroundProvider.notifier).setBackground(bg);
                                                      setDialogState(() {});
                                                    },
                                                  );
                                                }),
                                              ],
                                            ),
                                          ),
                                          // 4. TEXT STYLE
                                          Theme(
                                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                            child: ExpansionTile(
                                              title: const Text('TEXT STYLE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                                              children: [
                                                ...['None', 'Subtle Shadow', 'Outline'].map((styleOpt) {
                                                  final currentStyle = ref.watch(subtitleOutlineProvider);
                                                  final isCurrent = currentStyle == styleOpt;
                                                  return ListTile(
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                    title: Text(styleOpt, style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                    trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                    onTap: () async {
                                                      await ref.read(subtitleOutlineProvider.notifier).setOutline(styleOpt);
                                                      setDialogState(() {});
                                                    },
                                                  );
                                                }),
                                              ],
                                            ),
                                          ),
                                          // 5. SYNC
                                          Theme(
                                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                            child: ExpansionTile(
                                              title: const Text('SYNC', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                                              children: [
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      IconButton(
                                                        icon: const Icon(Icons.remove, color: Colors.white),
                                                        onPressed: () {
                                                          _updateSubtitleDelay(-250);
                                                          setDialogState(() {});
                                                        },
                                                      ),
                                                      Text('${_subtitleDelayMs > 0 ? "+" : ""}$_subtitleDelayMs ms', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                                      IconButton(
                                                        icon: const Icon(Icons.add, color: Colors.white),
                                                        onPressed: () {
                                                          _updateSubtitleDelay(250);
                                                          setDialogState(() {});
                                                        },
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
                                    Theme(
                                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                      child: ExpansionTile(
                                        iconColor: Theme.of(context).primaryColor,
                                        collapsedIconColor: Colors.white54,
                                        leading: const Icon(Icons.blur_linear_rounded),
                                        title: const Text('DEBANDING', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                        children: [
                                          SwitchListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                            title: const Text('Enable Debanding', style: TextStyle(color: Colors.white)),
                                            subtitle: const Text('Reduces color banding artifacts (uses more battery)', style: TextStyle(color: Colors.white30, fontSize: 10)),
                                            value: ref.watch(videoDebandingProvider),
                                            onChanged: (value) async {
                                              await ref.read(videoDebandingProvider.notifier).setEnabled(value);
                                              appDebugLog('🔧 Video debanding filter status dynamically changed to: $value');
                                              if (_player.platform is NativePlayer) {
                                                await (_player.platform as NativePlayer).setProperty('deband', value ? 'yes' : 'no');
                                              }
                                              setDialogState(() {});
                                            },
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
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
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
    if (_isLoading) return _buildLoadingState();

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


  void _handlePlayerEvent(String event, double currentTime, double duration) {
    if (!mounted) return;
    
    if (event == 'timeupdate') {
      _webViewPosition = Duration(milliseconds: (currentTime * 1000).toInt());
      _webViewDuration = Duration(milliseconds: (duration * 1000).toInt());
      
      // Also broadcast watch party progress if we are the host
      // Since _broadcastWatchPartyPlayback handles interval throttling, we can call it safely
      _broadcastWatchPartyPlayback(force: false);

      final media = ref.read(selectedMediaProvider);
      if (media != null && (media.mediaType == 'tv' || media.mediaType == 'anime')) {
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
      if (media != null && (media.mediaType == 'tv' || media.mediaType == 'anime') && _hasNextEpisode()) {
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
    String? subtitle = (media?.mediaType == 'tv' || media?.mediaType == 'anime') ? 'S${widget.season} E$_currentEpisode' : null;
    
    if ((media?.mediaType == 'tv' || media?.mediaType == 'anime') && _currentSeasonData != null) {
      try {
        final episode = _currentSeasonData!.episodes.firstWhere((e) => e.episodeNumber == _currentEpisode);
        if (episode.episodeName != null && episode.episodeName!.isNotEmpty && !episode.episodeName!.startsWith('Episode')) {
          subtitle = '$subtitle - ${episode.episodeName}';
        }
      } catch (e) {}
    }
    
    return const SizedBox.shrink();
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

                             if (_buildQualityOptions().length > 1)
                              _buildTopActionMenuButton<String>(
                                menuId: 'fs-quality-menu',
                                icon: Icon(Icons.hd, color: Colors.white),
                                tooltip: 'Quality',
                                itemBuilder: _buildQualityMenuItems,
                                onSelected: _switchQuality,
                              ),
                            IconButton(
                              tooltip: 'Switch Server',
                              icon: const Icon(
                                Icons.sync,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: _showServerOverlayPanel,
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
    final isFullscreen = _isInFullscreen;
    if (isFullscreen) {
      if (_isDirectStream) {
        ;
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
    if (media?.mediaType != 'tv' && media?.mediaType != 'anime') {
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
    if (!_isDirectStream) {
      return const SizedBox.shrink();
    }

    return Container(
      color: const Color(0xCC000000),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: SafeArea(
        top: false,
        child: StreamBuilder<Duration>(
          stream: _player.stream.position,
          initialData: _player.state.position,
          builder: (context, posSnap) {
            final position = posSnap.data ?? Duration.zero;
            final duration = _player.state.duration;
            final durationMs = duration.inMilliseconds;
            final maxMs = durationMs > 0 ? durationMs.toDouble() : 1.0;
            final sliderValue = durationMs > 0
                ? position.inMilliseconds.clamp(0, durationMs).toDouble()
                : 0.0;
            final isMuted = _player.state.volume <= 0.01;

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
                            _player.seek(
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
                          _player.setVolume(isMuted ? 100.0 : 0.0),
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
                        setState(() {
                          _isInFullscreen = !_isInFullscreen;
                        });
                        if (_isInFullscreen) {
                          SystemChrome.setPreferredOrientations([
                            DeviceOrientation.landscapeLeft,
                            DeviceOrientation.landscapeRight,
                          ]);
                          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                        } else {
                          SystemChrome.setPreferredOrientations(DeviceOrientation.values);
                          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                        }
                      },
                      icon: Icon(
                        _isInFullscreen
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
                if ((media?.mediaType == 'tv' || media?.mediaType == 'anime'))
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
                          _loadingMessage ?? 'Loading...',
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
  Future<void> _preloadAvailableAudios(StreamResult currentResult, SearchResult media) async {
    if (currentResult.availableAudios.isEmpty || !_isDirectStream) return;
    
    final streamingService = ref.read(streamingServiceProvider);
    currentResult.preloadedSources ??= {};
    
    final settingsQuality = ref.read(videoQualityProvider);
    final manualQuality = ref.read(selectedQualityProvider);
    final preferredQuality = manualQuality ?? (settingsQuality == 'auto' ? null : settingsQuality);

    for (final audio in currentResult.availableAudios) {
      if (audio.toLowerCase() == currentResult.selectedAudio.toLowerCase()) {
         continue;
      }
      
      if (!mounted || _currentProvider != currentResult.provider) break;
      
      try {
        final preloadedResult = await streamingService.fetchStreamUrl(
          media: media,
          season: widget.season,
          episode: _currentEpisode,
          preferredQuality: preferredQuality,
          providerIndex: _currentProviderIndex,
          subDubPreference: ref.read(languagePreferencesProvider).animePreferredAudio,
          preferredAudio: audio,
          onStatusUpdate: null,
        );
        
        if (preloadedResult != null && preloadedResult.url.isNotEmpty && mounted) {
           currentResult.preloadedSources![audio] = preloadedResult;
           appDebugLog('Preloaded audio: $audio');
        }
      } catch (e) {
        appDebugLog('Failed to preload audio $audio: $e');
      }
    }
  }

  Widget _buildVideoPlayer({bool isPipMode = false}) {
    final bgType = ref.watch(subtitleBackgroundProvider);
    final outlineType = ref.watch(subtitleOutlineProvider);

    Color? backgroundColor;
    if (bgType == 'Semi-Transparent') {
      backgroundColor = const Color(0x88000000);
    } else if (bgType == 'Solid') {
      backgroundColor = Colors.black;
    } else {
      backgroundColor = Colors.transparent;
    }

    List<Shadow>? shadows;
    if (outlineType == 'Outline') {
      shadows = const [
        // Cardinals
        Shadow(offset: Offset(0, -1.5), blurRadius: 1.0, color: Colors.black),
        Shadow(offset: Offset(0, 1.5), blurRadius: 1.0, color: Colors.black),
        Shadow(offset: Offset(-1.5, 0), blurRadius: 1.0, color: Colors.black),
        Shadow(offset: Offset(1.5, 0), blurRadius: 1.0, color: Colors.black),
        // Diagonals
        Shadow(offset: Offset(-1.2, -1.2), blurRadius: 1.0, color: Colors.black),
        Shadow(offset: Offset(1.2, -1.2), blurRadius: 1.0, color: Colors.black),
        Shadow(offset: Offset(1.2, 1.2), blurRadius: 1.0, color: Colors.black),
        Shadow(offset: Offset(-1.2, 1.2), blurRadius: 1.0, color: Colors.black),
      ];
    } else if (outlineType == 'Subtle Shadow') {
      shadows = const [
        Shadow(offset: Offset(2.0, 2.0), blurRadius: 4.0, color: Color(0xD9000000)),
      ];
    } else {
      shadows = null;
    }

    final videoWidget = Video(
      controller: _videoController,
      controls: NoVideoControls,
      fit: _displayFitOptions[_selectedDisplayFitKey] ?? BoxFit.cover,
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        visible: false,
      ),
    );

    if (isPipMode) {
      return RepaintBoundary(child: videoWidget);
    }

    final media = ref.read(selectedMediaProvider);
    String? subtitle;
    if ((media?.mediaType == 'tv' || media?.mediaType == 'anime')) {
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

    return RepaintBoundary(
      child: Stack(
        children: [
          videoWidget,
          Positioned(
            left: 24,
            right: 24,
            bottom: 20,
            child: IgnorePointer(
              child: StreamBuilder<List<String>>(
                stream: _player.stream.subtitle,
                initialData: const [],
                builder: (context, snapshot) {
                  final subtitleLines = snapshot.data ?? const [];
                  if (subtitleLines.isEmpty) return const SizedBox.shrink();

                  final cleanedLines = subtitleLines.map((line) {
                    return line.trim().replaceAll('\r', '').replaceAll('\u0000', '');
                  }).where((line) => line.isNotEmpty).toList();

                  if (cleanedLines.isEmpty) return const SizedBox.shrink();

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: cleanedLines.map((line) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                        child: Text(
                          line,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: ref.watch(subtitleFontSizeProvider) * 1.1,
                            color: Colors.white,
                            backgroundColor: backgroundColor,
                            shadows: shadows,
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),
          CustomPlayerControls(
            controller: _player,
            title: title,
            subtitle: subtitle,
            isLive: widget.isLive,
            onBack: _handleBackNavigation,
            onServerChange: () {
              _showServerOverlayPanel();
            },
            onSettings: () {
              _showSettingsOverlayPanel();
            },
            onEpisodes: ((media?.mediaType == 'tv' || media?.mediaType == 'anime')) ? () {
              _showEpisodesBottomSheet();
            } : null,
            onFitChanged: (fit) {
              final key = fit == BoxFit.cover ? 'fitScreen' : 'bestFit';
              _switchDisplayMode(key);
            },
            onPlayerVisibilityChanged: (visible) {
              setState(() {
                _arePlayerControlsVisible = visible;
              });
              _syncFullscreenTopBarVisibility();
            },
          ),
        ],
      ),
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

class _DummyState extends State<StatefulWidget> {
  @override Widget build(BuildContext context) => const SizedBox.shrink();
  dynamic get player => null;
  void setSubtitleDelay(int a) {}
  Future<void> play() async {}
  Future<void> pause() async {}
  Future<void> seekTo(dynamic a) async {}
  Future<void> seekRelative(Duration a) async {}
  void togglePlayPause() {}
  void handleSkipIntro() {}
}
