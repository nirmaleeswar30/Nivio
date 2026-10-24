import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:simple_pip_mode/actions/pip_actions_layout.dart';
import 'package:nivio/services/window_fullscreen.dart';
import 'dart:io';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:simple_pip_mode/simple_pip.dart';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:nivio/widgets/video_ambient_background.dart';
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
import 'package:nivio/services/download_service.dart';
import 'package:nivio/widgets/webview_player.dart';
import 'package:nivio/services/hls_proxy_service.dart';
import 'package:nivio/services/aniskip_service.dart';
import 'package:nivio/services/theintrodb_service.dart';
import 'package:nivio/services/skip_times_models.dart';
import 'package:nivio/providers/player_active_provider.dart';
import 'package:nivio/providers/mini_player_provider.dart';
import 'package:nivio/services/torrent/torrent_stream_service.dart';
import 'package:nivio/services/anime_filler_service.dart';
import 'package:nivio/services/discord_rpc_service.dart';
import 'package:nivio/services/anime_tracking_coordinator.dart';
import 'package:nivio/services/simkl_auth_service.dart';
import 'package:nivio/providers/anime_tracking_provider.dart';
import 'package:nivio/models/anime_tracking_models.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/widgets/anime_brand_logos.dart';
import 'dart:math' as math;
import 'package:nivio/services/media_session_service.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final int mediaId;
  final int season;
  final int episode;
  final String? mediaType;
  final int? providerIndex;
  final String? watchPartyCode;
  final WatchPartyRole? watchPartyRole;
  final String? localPath;
  // When set, play a still-downloading item (torrent via rqbit, or the source
  // URL for direct/HLS) so it can be watched while it downloads.
  final String? downloadStreamId;
  final String? directStreamUrl;
  final String? directStreamTitle;
  final bool isLive;
  // Optional Referer for gated direct streams (e.g. live sports CDNs).
  final String? directStreamReferer;

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
    this.downloadStreamId,
    this.directStreamUrl,
    this.directStreamTitle,
    this.isLive = false,
    this.directStreamReferer,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  WatchHistoryService? _cachedHistoryService;
  SearchResult? _cachedMedia;
  StateController<bool>? _cachedPlayerActiveNotifier;
  TorrentStreamService? _cachedTorrentService;
  int? _resolvedMalId;
  int? _lastTrackingSyncedEpisode;

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

  Future<void> _updateSubtitleScalingForPip(bool isPip) async {
    if (_player.platform is NativePlayer) {
      try {
        final np = _player.platform as NativePlayer;
        final fontSize = ref.read(subtitleFontSizeProvider);
        final baseScale = fontSize / 18.0;
        final scale = isPip ? (baseScale * 0.45) : baseScale;
        await np.setProperty('sub-ass-override', 'scale');
        await np.setProperty('sub-scale', '$scale');
      } catch (e) {
        appDebugLog('Failed to update subtitle scale for PiP: $e');
      }
    }
  }

  void _syncPipPlayingState([bool? isPlaying]) {
    if (!Platform.isAndroid) return;
    try {
      final playing = isPlaying ?? _player.state.playing;
      unawaited(SimplePip().setIsPlaying(playing).catchError((_) => false));
    } catch (_) {}
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
  final GlobalKey<CustomPlayerControlsState> _controlsKey = GlobalKey<CustomPlayerControlsState>();
  final GlobalKey _ambientCaptureKey = GlobalKey(debugLabel: 'ambientCapture');
  bool _showNextEpisodeButton = false;
  bool _nextEpisodeDismissed = false;
  Timer? _nextEpisodeTimer;
  int? _nextEpisodeCountdown;
  final Map<int, StreamResult> _prefetchedStreams = {};
  Map<int, Future<StreamResult?>>? _runningFetchers;
  bool _isPrefetching = false;
  bool _isDirectStream = false;
  bool _isManualProviderSwitch = false;
  Future<void>? _prepareProvidersFuture;
  // True when playing a still-downloading item (torrent rqbit stream or a direct
  // source URL) — always a direct/media_kit stream, never a WebView.
  bool _isDownloadStream = false;
  // Binge Mode (torrents only): per-player-session. When on, the next episode
  // auto-advances without the picker, reusing the remembered release group.
  bool _bingeMode = false;
  String? _bingeGroup; // remembered release group, shown on the up-next card
  List<SkipTime> _skipTimes = [];
  bool _isFetchingSkipTimes = false;
  AnimeFillerData _fillerData = const AnimeFillerData();
  bool _isFetchingFillerData = false;
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
  bool _transferredToMiniPlayer = false; // When true, dispose skips player.dispose()
  bool _isDisposing = false; // Track disposal state to prevent ref usage
  bool _videoDetached = false; // When true, Video widget is replaced with black box before mini player handoff
  DateTime _lastDiscordSync = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastDiscordPos = Duration.zero;
  final ValueNotifier<bool> _fullscreenTopBarVisibleNotifier = ValueNotifier(
    false,
  );
  OverlayEntry? _fullscreenTopBarOverlayEntry;

  // Notifier so overlay updates inside BetterPlayer fullscreen
  final ValueNotifier<_NextEpState> _nextEpNotifier = ValueNotifier(
    _NextEpState(show: false, countdown: null),
  );
  OverlayEntry? _nextEpOverlayEntry;
  OverlayEntry? _trackingPromptOverlayEntry;
  bool _trackingPromptDismissed = false;
  
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

  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  ScaffoldMessengerState get _messenger =>
      _messengerKey.currentState ?? ScaffoldMessenger.of(context);

  // —— [STUCK_DEBUG] watchdog for "server loads but playback never leaves 0:00" ——
  Timer? _stuckWatchdog;
  DateTime? _openStartedAt; // when _player.open() returned for the current load
  bool _sawFirstFrame = false; // set once position advances past zero
  bool _stuckReported = false; // one stuck report per load

  /// Called right after a successful direct-stream _player.open(). Arms a timer
  /// that fires if the position is still 0:00 after a grace period, and logs the
  /// full player state so we can tell which anime servers open but never play.
  void _startStuckWatchdog() {
    _stuckWatchdog?.cancel();
    _openStartedAt = DateTime.now();
    _sawFirstFrame = false;
    _stuckReported = false;

    void snapshot(String tag) {
      final s = _player.state;
      final vp = s.videoParams;
      appDebugLog(
        '⏱️ [STUCK_DEBUG] PlayerScreen#$_sid $tag — provider="$_currentProvider" '
        'pos=${s.position} dur=${s.duration} buffer=${s.buffer} '
        'playing=${s.playing} buffering=${s.buffering} completed=${s.completed} '
        'width=${vp.w} height=${vp.h} dw=${vp.dw} dh=${vp.dh} '
        'videoTracks=${s.tracks.video.length} audioTracks=${s.tracks.audio.length} '
        'url=${_streamResult?.url}',
      );
    }

    // Two checks: an early one (server never even started) and a later one.
    _stuckWatchdog = Timer(const Duration(seconds: 8), () {
      if (!mounted || _isDeactivated) return;
      if (_sawFirstFrame) return;
      _stuckReported = true;
      snapshot('STUCK at 0:00 after 8s');

      // If a torrent stream is stuck at 0:00, rqbit may have finished hash-checking/connecting.
      // Re-trigger open() so mpv re-connects to the localhost stream endpoint.
      if (_currentProvider == 'Nivio Torrents' && _streamResult != null) {
        appDebugLog('🔄 [STUCK_DEBUG] Torrent stream stuck at 0:00 — reloading player stream...');
        _player.open(
          Media(_streamResult!.url, httpHeaders: _streamResult!.headers),
          play: true,
        );
      }

      // Re-check once more a few seconds later to distinguish "slow" from "dead".
      Timer(const Duration(seconds: 7), () {
        if (!mounted || _isDeactivated) return;
        if (_sawFirstFrame) {
          appDebugLog('✅ [STUCK_DEBUG] PlayerScreen#$_sid recovered — playback started late for "$_currentProvider"');
        } else {
          snapshot('STILL STUCK at 0:00 after 15s (server likely dead — user must switch)');
          if (_currentProvider == 'Nivio Torrents' && _streamResult != null) {
            _player.open(
              Media(_streamResult!.url, httpHeaders: _streamResult!.headers),
              play: true,
            );
          }
        }
      });
    });
  }

  // —— [CW_DEBUG] diagnostics for the continue-watching replay failure ——
  // Short id so logs from overlapping PlayerScreen instances can be told apart.
  late final String _sid = (identityHashCode(this) & 0xFFFF).toRadixString(16);
  static String _hash(Object? o) =>
      o == null ? 'null' : (identityHashCode(o) & 0xFFFF).toRadixString(16);
  // Set between deactivate() and dispose(). A deactivated State is still
  // `mounted`, so stream callbacks keep running and ref.read() throws.
  bool _isDeactivated = false;
  DateTime? _deactivatedAt;
  final Set<String> _zombieLogged = {};

  /// Returns true (and logs once per source) when a callback fires on a
  /// deactivated-but-not-disposed State.
  bool _isZombieCallback(String source) {
    if (!_isDeactivated) return false;
    if (_zombieLogged.add(source)) {
      final ageMs = _deactivatedAt == null
          ? '?'
          : DateTime.now().difference(_deactivatedAt!).inMilliseconds;
      appDebugLog(
        '🧟 [CW_DEBUG] PlayerScreen#$_sid ZOMBIE: "$source" fired ${ageMs}ms after '
        'deactivate() but dispose() has not run (player=${_hash(_player)}, '
        'transferredToMini=$_transferredToMiniPlayer). Skipping to avoid ref.read on '
        'a deactivated element. Further "$source" hits are silenced.',
      );
    }
    return true;
  }

  @override
  void deactivate() {
    _isDeactivated = true;
    _deactivatedAt = DateTime.now();
    appDebugLog(
      '🧪 [CW_DEBUG] PlayerScreen#$_sid deactivate() — media=${widget.mediaId} '
      'E$_currentEpisode transferredToMini=$_transferredToMiniPlayer '
      'player=${_hash(_player)} subs=${_subscriptions.length} '
      'progressTimerActive=${_progressTimer?.isActive}',
    );
    // A popped route is deactivated, then disposed at the end of the frame.
    // If that frame aborts (the debug semantics assertions), dispose() never
    // runs and a player that was NOT handed to the mini player keeps playing
    // in the background. Silence it here; dispose() still releases it later.
    if (!_transferredToMiniPlayer) {
      _progressTimer?.cancel();
      _nextEpisodeTimer?.cancel();
      try {
        _player.stop();
        appDebugLog('🧪 [CW_DEBUG] PlayerScreen#$_sid deactivate() stopped player=${_hash(_player)} (not handed to mini player)');
      } catch (e) {
        appDebugLog('🧪 [CW_DEBUG] PlayerScreen#$_sid deactivate() stop failed: $e');
      }
    }
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _isDeactivated = false;
    _deactivatedAt = null;
    appDebugLog('🧪 [CW_DEBUG] PlayerScreen#$_sid activate() (re-inserted into tree)');
  }

  bool _isAnimeMedia(SearchResult? media) {
    if (media == null) return false;
    if (media.mediaType == 'anime') return true;
    return false;
  }

  // Automatic fallback walks from _providerStartIndex to the end, then wraps to
  // 0 and stops just before _providerStartIndex. Without the wrap, a saved
  // preferredProviderIndex (a raw index into the *dynamic* anime server list,
  // whose contents shift between sessions) silently skipped every provider
  // before it — e.g. anime replays starting at 4 never tried Animex at 0–3.
  int _providerStartIndex = 0;
  bool _providerWrapped = false;

  bool get _hasNextProvider {
    final next = _currentProviderIndex + 1;
    if (_providerWrapped) return next < _providerStartIndex;
    return next < _maxProviders || _providerStartIndex > 0;
  }

  void _advanceProvider() {
    final next = _currentProviderIndex + 1;
    if (!_providerWrapped && next >= _maxProviders) {
      _providerWrapped = true;
      _currentProviderIndex = 0;
      appDebugLog(
        '🔁 [CW_DEBUG] PlayerScreen#$_sid reached end of $_maxProviders providers — '
        'wrapping to 0 to try the ones before start index $_providerStartIndex',
      );
    } else {
      _currentProviderIndex = next;
    }
  }

  int get _maxProviders {
    final media = ref.read(selectedMediaProvider) ?? _cachedMedia;
    final streamingService = ref.read(streamingServiceProvider);
    return streamingService.totalProvidersFor(isAnime: _isAnimeMedia(media));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSubtitleDelay();
    unawaited(WakelockPlus.enable());
    
    // Pre-cache providers to prevent using ref after widget disposal in dispose() or in microtasks
    _cachedHistoryService = ref.read(watchHistoryServiceProvider);
    _cachedMedia = ref.read(selectedMediaProvider);
    _cachedPlayerActiveNotifier = ref.read(isPlayerActiveProvider.notifier);
    _cachedTorrentService = ref.read(torrentStreamServiceProvider);
    final cachedActiveNotifier = _cachedPlayerActiveNotifier;

    // Signal to the rest of the app that the player is active
    if (cachedActiveNotifier != null) {
      Future.microtask(() {
        cachedActiveNotifier.state = true;
      });
    }

    // Check if the mini player has an active player we can reclaim
    // (user tapped expand on mini player or navigated back to same media)
    final miniPlayerState = ref.read(miniPlayerProvider);
    final miniInfo = miniPlayerState.mediaInfo;
    appDebugLog(
      '🧪 [CW_DEBUG] PlayerScreen#$_sid initState — media=${widget.mediaId} '
      'S${widget.season}E${widget.episode} type=${widget.mediaType} '
      'providerIndex=${widget.providerIndex} | mini: active=${miniPlayerState.isActive} '
      'player=${_hash(miniPlayerState.player)} ctrl=${_hash(miniPlayerState.videoController)} '
      'miniMedia=${miniInfo?.mediaId} S${miniInfo?.season}E${miniInfo?.episode} '
      '| selectedMedia=${ref.read(selectedMediaProvider)?.id}',
    );
    if (miniPlayerState.isActive && miniPlayerState.player != null) {
      appDebugLog(
        '🧪 [CW_DEBUG] PlayerScreen#$_sid RECLAIMING mini player '
        '(same media: ${miniInfo?.mediaId == widget.mediaId && miniInfo?.episode == widget.episode}) '
        '— mini overlay may still have a Video on ctrl=${_hash(miniPlayerState.videoController)}',
      );
      _player = miniPlayerState.player!;
      _videoController = miniPlayerState.videoController!;
      _isDirectStream = true;
      final miniNotifier = ref.read(miniPlayerProvider.notifier);
      Future.microtask(() {
        miniNotifier.reclaim();
      });
    } else {
      _player = Player();
      _videoController = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: !Platform.isLinux,
        ),
      );
      appDebugLog(
        '🧪 [CW_DEBUG] PlayerScreen#$_sid created NEW player=${_hash(_player)} ctrl=${_hash(_videoController)}',
      );
    }

    // Register event listeners via stream subscriptions
    _setupPlayerStreams();

    // Hardware / Bluetooth media buttons and OS media overlay controls.
    MediaSessionService.instance.attach(
      owner: this,
      player: _player,
      metadata: _mediaSessionMetadata(),
      seekStep: Duration(seconds: ref.read(seekDurationProvider)),
    );

    if (Platform.isAndroid) {
      const MethodChannel('com.nivio/gesture_exclusion').invokeMethod('setCanEnterPip', {'value': true});
      try {
        () async {
          const MethodChannel('puntito.simple_pip_mode').setMethodCallHandler((call) async {
            if (call.method == 'onPipEntered') {
              setState(() => _isPipMode = true);
              _updateSubtitleScalingForPip(true);
              _syncPipPlayingState();
            } else if (call.method == 'onPipExited') {
              setState(() => _isPipMode = false);
              _updateSubtitleScalingForPip(false);
              _syncPipPlayingState();
            } else if (call.method == 'onPipAction') {
              final String arg = call.arguments as String;
              final actionStr = arg.toLowerCase();
              if (actionStr == 'play') {
                _player.play();
              } else if (actionStr == 'pause') {
                _player.pause();
              } else if (actionStr == 'next' || actionStr == 'forward') {
                final pos = _player.state.position;
                final dur = _player.state.duration;
                final step = ref.read(seekDurationProvider);
                final newPos = pos + Duration(seconds: step);
                _player.seek(newPos > dur ? dur : newPos);
              } else if (actionStr == 'previous' || actionStr == 'rewind') {
                final pos = _player.state.position;
                final step = ref.read(seekDurationProvider);
                final newPos = pos - Duration(seconds: step);
                _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
              }
            }
          });
          final autoPip = ref.read(pipOnLostVisibilityProvider);
          await SimplePip().setPipActionsLayout(PipActionsLayout.mediaWithSeek10);
          await SimplePip().setAutoPipMode(aspectRatio: const (16, 9), autoEnter: autoPip);
          _syncPipPlayingState();
        }();
      } catch (_) {}
    }
    _currentEpisode = widget.episode;
    _currentProviderIndex = math.max(0, widget.providerIndex ?? 0);
    // If we reclaimed from mini player, the player is already initialized and playing
    if (!miniPlayerState.isActive || miniPlayerState.player == null) {
      _initializePlayer(isRetry: false);
    } else {
      // Player is already playing — just mark as loaded and resume progress tracking
      _isDirectStream = true;
      _startProgressTracking();
      setState(() {
        _isLoading = false;
      });
    }
    _initializeWatchParty();
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_isDisposing) return;
    final pauseOnLost = ref.read(pauseOnLostVisibilityProvider);
    if (pauseOnLost && !_isPipMode) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden) {
        if (_useNativePlayer) {
          _kwikPlayerKey.currentState?.pause();
        } else {
          _player.pause();
        }
      }
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!Platform.isAndroid || !mounted) return;
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view != null) {
      final physicalSize = view.physicalSize;
      final dpr = view.devicePixelRatio;
      final width = physicalSize.width / (dpr > 0 ? dpr : 1);
      final height = physicalSize.height / (dpr > 0 ? dpr : 1);
      final isSmall = width < 500 && height < 400;
      if (isSmall != _isPipMode) {
        setState(() {
          _isPipMode = isSmall;
        });
        _updateSubtitleScalingForPip(isSmall);
        _syncPipPlayingState();
      }
    }
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

    // If already in Plan to Watch, automatically promote to Watching on start
    if (_isAnimeMedia(media)) {
      final watchlistService = ref.read(watchlistServiceProvider);
      final watchItem = watchlistService.getItem(widget.mediaId);
      if (watchItem != null && watchItem.watchStatus == WatchStatus.planning) {
        watchlistService.updateWatchStatus(
          widget.mediaId,
          WatchStatus.watching,
          currentEpisode: _currentEpisode,
        );
        ref.read(watchlistRefreshProvider.notifier).refresh();
        unawaited(
          AnimeTrackingCoordinator.instance.syncWatchStatus(
            anilistId: media.id,
            malId: media.malId ?? _resolvedMalId,
            status: WatchStatus.watching,
            episode: _currentEpisode,
          ),
        );
      }

      unawaited(_checkAndPromptTrackingIfNeeded());
    }
  }

  // ────────────────── Keyboard shortcuts ──────────────────
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // On TV the D-pad is handled by CustomPlayerControls. Keys only get here
    // when focus is outside the controls (e.g. on Skip Intro), so hand them
    // over: arrows there seek / show the controls instead of doing nothing.
    if (AppPlatform.isTv) {
      final controls = _controlsKey.currentState;
      if (controls != null) return controls.handleTvKey(event);
      // No controls yet (loading / error screen): the first arrow press
      // moves onto that screen's buttons, starting with the back arrow.
      final arrow = event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight;
      if (arrow && node.hasPrimaryFocus) {
        node.nextFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_player.state.duration == Duration.zero) {
      return KeyEventResult.ignored;
    }

    // Disable player keybinds when an editable text field (e.g. chat, search) has focus
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus != node) {
      final context = primaryFocus.context;
      if (context != null) {
        final isTextInput = context.widget is EditableText ||
            context.widget is TextField ||
            context.findAncestorWidgetOfExactType<EditableText>() != null ||
            context.findAncestorWidgetOfExactType<TextField>() != null;
        if (isTextInput) {
          return KeyEventResult.ignored;
        }
      }
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
        final step = ref.read(seekDurationProvider);
        _player.seek(
          pos - Duration(seconds: step) < Duration.zero
              ? Duration.zero
              : pos - Duration(seconds: step),
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.keyL:
        final pos = _player.state.position;
        final dur = _player.state.duration;
        final step = ref.read(seekDurationProvider);
        final newPos = pos + Duration(seconds: step);
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
          final anilistService = ref.read(aniListServiceProvider);
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
        
        _resolvedMalId = malId;
        if (malId != null) {
          final times = await AniSkipService.getSkipTimes(malId, episode);
          if (mounted) setState(() { _skipTimes = times; });
        }
      } else if ((media.mediaType == 'tv' || media.mediaType == 'anime')) {
        // Normal show - TheIntroDB (v4 public API)
        final times = await TheIntroDBService.getSkipTimes(media.id, widget.season, episode);
        if (mounted) setState(() { _skipTimes = times; });
      } else if (media.mediaType == 'movie') {
        // Movie - TheIntroDB (v4 public API)
        final times = await TheIntroDBService.getMovieSkipTimes(media.id);
        if (mounted) setState(() { _skipTimes = times; });
      }
    } finally {
      if (mounted) _isFetchingSkipTimes = false;
    }
  }

  Future<void> _fetchFillerData(SearchResult media) async {
    if (_isFetchingFillerData) return;
    if (_fillerData.fillerEpisodes.isNotEmpty || _fillerData.mixedEpisodes.isNotEmpty) return;
    _isFetchingFillerData = true;
    try {
      final fillerService = ref.read(animeFillerServiceProvider);
      final data = await fillerService.getFillerData(
        anilistId: media.id,
        title: media.title ?? media.name ?? '',
        malId: media.malId,
      );
      if (mounted) {
        setState(() {
          _fillerData = data;
        });
      }
    } catch (e) {
      appDebugLog('Error fetching filler data: $e');
    } finally {
      if (mounted) _isFetchingFillerData = false;
    }
  }

  // ├────────────────────────────────────────────────────────────────────────────────────────── Player initialization ──────────────────────────────────────────────────────────────────────────────────────────
  Future<void> _initializePlayer({bool isRetry = true}) async {
    appDebugLog(
      '🧪 [CW_DEBUG] PlayerScreen#$_sid _initializePlayer(isRetry=$isRetry) '
      'providerIdx=$_currentProviderIndex runningFetchers=${_runningFetchers?.keys.toList()} '
      'player=${_hash(_player)} playing=${_player.state.playing} '
      'dur=${_player.state.duration} deactivated=$_isDeactivated',
    );
    // Once the stream is open and playing, later failures (UI/snackbar/etc.)
    // must not be treated as a provider failure — that used to cycle through
    // every provider while the first stream kept playing in the background.
    var mediaOpened = false;
    // Cancel any watchdog from a previous load/retry before starting a new one.
    _stuckWatchdog?.cancel();
    _sawFirstFrame = false;
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
        try {
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
        } catch (e) {
          appDebugLog('PlayerScreen: Could not load media details (offline or error): $e');
        }
      }

      if ((media?.mediaType == 'tv' || media?.mediaType == 'anime')) {
        _fetchSeasonData();
      }
      
      if (media != null && !_isFetchingSkipTimes) {
        _fetchSkipTimes(media, _currentEpisode);
      }

      if (media != null && _isAnimeMedia(media)) {
        _fetchFillerData(media);
      }

      final streamingService = ref.read(streamingServiceProvider);

      final isAnime = (media != null && _isAnimeMedia(media)) || widget.mediaType == 'anime';
      final isTorrentEnabled = streamingService.isTorrentEnabled(isAnime: isAnime);

      if (widget.providerIndex != null) {
        _currentProviderIndex = widget.providerIndex!;
      } else if (isRetry) {
        // Keep current provider index advanced by _advanceProvider
      } else if (_isManualProviderSwitch) {
        _isManualProviderSwitch = false;
        // Keep user-selected provider index from _switchToProvider
      } else if (isTorrentEnabled) {
        // When torrent streaming is enabled, instantly prioritize Nivio Torrents (index 0)
        // for both anime and movies/shows, instead of using a saved direct provider from history.
        _currentProviderIndex = 0;
      } else if (_currentHistory?.preferredProviderIndex != null) {
        _currentProviderIndex = _currentHistory!.preferredProviderIndex!;
      } else {
        _currentProviderIndex = 0;
      }

      appDebugLog(
        '🧪 [CW_DEBUG] PlayerScreen#$_sid history: '
        'S${_currentHistory?.currentSeason}E${_currentHistory?.currentEpisode} '
        'pos=${_currentHistory?.lastPositionSeconds}s/${_currentHistory?.totalDurationSeconds}s '
        'preferredProvider=${_currentHistory?.preferredProviderIndex} '
        'preferredRes=${_currentHistory?.preferredResolution} '
        'preferredAudio=${_currentHistory?.preferredAudioTrack} '
        'isTorrentEnabled=$isTorrentEnabled '
        '→ providerIdx=$_currentProviderIndex',
      );

      String subDubPref = ref.read(languagePreferencesProvider).animePreferredAudio;
      if (_selectedAudioOverride != null && _selectedAudioOverride!.isNotEmpty) {
        subDubPref = _selectedAudioOverride!.toLowerCase().contains('dub') ? 'dub' : 'sub';
      }
      
      if (media != null && _isAnimeMedia(media)) {
        final isTorrent = streamingService.getProviderName(
          _currentProviderIndex,
          isAnime: true,
        ) == 'Nivio Torrents';

        if (isTorrent) {
          // If starting with Nivio Torrents, fire prepareProviders in the background
          // so the torrent picker sheet opens instantly without waiting for Miruro/Animex server queries.
          _prepareProvidersFuture ??= streamingService.prepareProviders(
            media: media,
            season: widget.season,
            episode: _currentEpisode,
            subDubPreference: subDubPref,
          );
        } else {
          // Direct anime provider is being used: ensure prepareProviders has completed
          setState(() => _currentProvider = 'Preparing servers...');
          appDebugLog('⏳ [FLOW] _initializePlayer: calling prepareProviders...');
          _prepareProvidersFuture ??= streamingService.prepareProviders(
            media: media,
            season: widget.season,
            episode: _currentEpisode,
            subDubPreference: subDubPref,
          );
          await _prepareProvidersFuture;
          appDebugLog('✅ [FLOW] _initializePlayer: prepareProviders done, _maxProviders=$_maxProviders');
        }
      }

      if (_maxProviders > 0 && _currentProviderIndex >= _maxProviders) {
        _currentProviderIndex = 0;
        _runningFetchers = null;
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

      // When advancing between episodes (e.g. autoplay or manual next), route
      // parameters like widget.localPath or widget.downloadStreamId only belong
      // to the episode that originally opened the player. Subsequent episodes
      // must resolve their own downloaded file or stream.
      final isInitialEpisode = (_currentEpisode == widget.episode);

      // Always prefer a local downloaded copy if one exists for this media,
      // regardless of how playback was launched. An explicit localPath (e.g.
      // from DownloadsScreen) applies to the initial episode; subsequent episodes
      // query Hive for their own downloadItem.
      final downloadItem = DownloadService.findPlayableDownload(
        mediaId: widget.mediaId,
        season: widget.season,
        episode: _currentEpisode,
      );

      _effectiveLocalPath = (isInitialEpisode && widget.localPath != null && widget.localPath!.isNotEmpty)
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

      // Play-while-downloading: resolve a stream that reuses the bytes already
      // on disk — torrents via rqbit, direct files via the local range server,
      // HLS via a growing local playlist. Never falls back to re-streaming the
      // source; if it can't be resolved we surface an error instead.
      //
      // An explicit downloadStreamId (from the Downloads screen) is honoured
      // as-is for the initial episode. Otherwise, if this media/episode happens to be downloading right
      // now, reuse it automatically — so launching from media detail, continue
      // watching, or a watch-party sync doesn't waste a fresh remote stream.
      // A hard error is only surfaced for the explicit case; for auto-detected
      // in-progress items we fall through to normal providers if not yet ready.
      String? effectiveDownloadStreamId = isInitialEpisode ? widget.downloadStreamId : null;
      bool isExplicitDownload = effectiveDownloadStreamId != null;
      if (effectiveDownloadStreamId == null &&
          _effectiveLocalPath == null &&
          (isInitialEpisode ? widget.directStreamUrl == null : true) &&
          downloadItem == null) {
        final inProgress = DownloadService.findInProgressDownload(
          mediaId: widget.mediaId,
          season: widget.season,
          episode: _currentEpisode,
        );
        if (inProgress != null) {
          effectiveDownloadStreamId = inProgress.id;
          appDebugLog(
            '🧪 [CW_DEBUG] PlayerScreen#$_sid auto-reusing in-progress download '
            'id=${inProgress.id} (status=${inProgress.status}) for '
            'media=${widget.mediaId} S${widget.season}E$_currentEpisode',
          );
        }
      }

      if (effectiveDownloadStreamId != null) {
        final dl = await DownloadService.resolveInProgressStream(
          effectiveDownloadStreamId,
        );
        if (dl != null) {
          _isDownloadStream = true;
          // Register the download's torrent with the streaming service so the
          // live P2P stats overlay (speed/peers/%) shows for watch-while-
          // downloading torrents, not just picker-started ones. Both use the
          // same shared rqbit engine, so stats resolve by torrent id.
          if (dl.isTorrent && dl.torrentId != null) {
            await ref
                .read(torrentStreamServiceProvider)
                .adoptActiveTorrent(dl.torrentId!);
          }
          result = StreamResult(
            url: dl.url,
            quality: 'Downloading',
            // 'Nivio Torrents' reuses the player's torrent-stream handling
            // (no prefetch, tolerant of premature EOF while pieces arrive).
            provider: dl.isTorrent ? 'Nivio Torrents' : 'Local Stream',
            headers: dl.headers,
            isM3U8: dl.isM3u8,
          );
        } else if (isExplicitDownload) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _error =
                "This download isn't ready to stream yet — give it a moment and try again.";
          });
          return;
        } else {
          // Auto-detected but not streamable yet (e.g. HLS segments not
          // registered): fall through to normal remote providers.
          appDebugLog(
            '🧪 [CW_DEBUG] PlayerScreen#$_sid in-progress download not streamable yet — using remote providers',
          );
        }
      }

      if (result != null) {
        // Already resolved above (play-while-downloading).
      } else if (isInitialEpisode && widget.directStreamUrl != null) {
        final lowerUrl = widget.directStreamUrl!.toLowerCase();
        final isHls = lowerUrl.contains('.m3u8') || lowerUrl.contains('.m3u') || widget.isLive;

        result = StreamResult(
          url: widget.directStreamUrl!,
          quality: 'Live',
          provider: widget.directStreamReferer != null ? 'Sports' : 'IPTV',
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': '*/*',
            if (widget.directStreamReferer != null && widget.directStreamReferer!.isNotEmpty)
              'Referer': widget.directStreamReferer!,
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

        if (_runningFetchers == null) {
          // Fresh fallback run: remember where it began so it can wrap around
          // to the providers *before* a saved preferred index (see _advanceProvider).
          _providerStartIndex = _currentProviderIndex;
          _providerWrapped = false;
        }
        if (_runningFetchers == null || !_runningFetchers!.containsKey(_currentProviderIndex)) {
          appDebugLog('🚀 [FLOW] Launching fetchers starting from provider index $_currentProviderIndex (wrapped=$_providerWrapped)');
          _runningFetchers ??= {};

          final isCurrentTorrent = streamingService.getProviderName(
            _currentProviderIndex,
            isAnime: _isAnimeMedia(media),
          ) == 'Nivio Torrents';

          if (isCurrentTorrent) {
            // For Nivio Torrents, launch ONLY the torrent provider.
            // Do NOT precheck or scrape direct sources in parallel while
            // the user is interactively choosing a torrent release.
            appDebugLog('🚀 [FLOW] Launching torrent fetcher for provider index $_currentProviderIndex');
            _runningFetchers![_currentProviderIndex] = streamingService.fetchStreamUrl(
              media: media!,
              season: widget.season,
              episode: _currentEpisode,
              preferredQuality: preferredQuality,
              providerIndex: _currentProviderIndex,
              subDubPreference: subDubPref,
              preferredAudio: targetAudio,
              binge: _bingeMode,
              context: context,
              onStatusUpdate: (msg) {
                if (mounted && _currentProviderIndex == _currentProviderIndex) {
                  setState(() => _loadingMessage = msg);
                }
              },
            );
          } else {
            // Fire all remaining direct providers in parallel to eliminate sequential fallback latency!
            for (int i = _currentProviderIndex; i < _maxProviders; i++) {
              if (_runningFetchers!.containsKey(i)) continue;
              appDebugLog('🚀 [FLOW] Launching fetcher for provider index $i');
              _runningFetchers![i] = streamingService.fetchStreamUrl(
                media: media!,
                season: widget.season,
                episode: _currentEpisode,
                preferredQuality: preferredQuality,
                providerIndex: i,
                subDubPreference: subDubPref,
                preferredAudio: targetAudio,
                binge: _bingeMode,
                context: (i == _currentProviderIndex ? context : null),
                onStatusUpdate: (msg) {
                  if (mounted && _currentProviderIndex == i) {
                    setState(() => _loadingMessage = msg);
                  }
                },
              );
            }
          }
        }

        appDebugLog('⏳ [FLOW] Awaiting _runningFetchers for _currentProviderIndex = $_currentProviderIndex');
        result = await _runningFetchers![_currentProviderIndex];
        appDebugLog('✅ [FLOW] _runningFetchers[$_currentProviderIndex] returned: ${result != null ? result.provider : 'null'}');
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

      if (!mounted) return;
      appDebugLog(
        '🧪 [CW_DEBUG] PlayerScreen#$_sid provider[$_currentProviderIndex/$_maxProviders] '
        'result=${result == null ? 'NULL' : '${result.provider} ${result.quality} m3u8=${result.isM3U8} url=${result.url}'}',
      );
      if (result == null) {
        if (_hasNextProvider) {
          _advanceProvider();
          setState(() => _error = 'Provider unavailable, trying next...');
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          _initializePlayer(isRetry: true);
          return;
        }
        throw Exception('Failed to get stream URL from all providers');
      }

      _streamResult = result;
      _currentProvider = result.provider;
      // A local downloaded file is always played directly (never via WebView).
      _isDirectStream = ((isInitialEpisode && widget.directStreamUrl != null) || _isDownloadStream || (_effectiveLocalPath != null && _effectiveLocalPath!.isNotEmpty))
          ? true
          : ref.read(streamingServiceProvider).isDirectStream(
              _currentProviderIndex,
              isAnime: _isAnimeMedia(media),
            );

      // Pre-verify the stream URL if it's a direct stream to instantly fallback without player errors.
      // Providers can expose several sources (e.g. VidRock's Nova/Luna/Orion servers). Verify each
      // in turn and promote the first reachable one BEFORE giving up on the whole provider — a single
      // dead server should not send us to the next (often embed) provider while good ones remain.
      //
      // Torrent streams ("Nivio Torrents") are exempt: the localhost rqbit URL is
      // never "dead", but its stream endpoint blocks until the first pieces are
      // fetched from peers — a short HTTP probe would time out and wrongly skip
      // the provider. media_kit/mpv buffers the stream natively instead.
      final isTorrentStream = result.provider == 'Nivio Torrents';
      if (_isDirectStream && result.url.startsWith('http') && !isTorrentStream) {
        if (mounted) setState(() => _loadingMessage = 'Verifying stream connection...');

        // Use the SAME headers (incl. browser User-Agent/Origin) that media_kit will use for
        // playback. Sending the raw scraper headers here meant the Dart default User-Agent
        // ("Dart/x (dart:io)") leaked through, which some CDNs (e.g. NetMirror/net27's
        // hakunaymatata CDN) reject with HTTP 428, causing a false "dead stream" fallback.
        final headers = _buildPlaybackHeaders(result.headers);

        // Candidate sources: primary first, then any distinct alternates.
        final candidates = <StreamSource>[
          StreamSource(url: result.url, quality: result.quality, isM3U8: result.isM3U8),
        ];
        final seen = <String>{result.url};
        for (final s in result.sources) {
          if (s.url.startsWith('http') && seen.add(s.url)) candidates.add(s);
        }

        StreamSource? working;
        int? lastStatus;
        
        // Fire all candidate verifications simultaneously to prevent 10-15s sequential timeout delays!
        appDebugLog('⏳ [FLOW] Starting parallel stream verification for ${candidates.length} candidates from ${result.provider}');
        final checkFutures = candidates.map((cand) async {
          try {
            appDebugLog('🔍 [FLOW] Verifying candidate: ${cand.quality} (${cand.url})');
            final request = http.Request('GET', Uri.parse(cand.url));
            request.headers.addAll(headers);
            request.headers['Range'] = 'bytes=0-100'; // range request avoids buffering the whole video
            final client = http.Client();
            
            final streamedResponse = await client.send(request).timeout(const Duration(milliseconds: 2500));
            final status = streamedResponse.statusCode;
            client.close(); // Abort immediately to prevent downloading the video file
            
            if (status < 400) {
              appDebugLog('✅ Stream pre-verification passed (${cand.quality}) with status: $status');
              return {'cand': cand, 'status': status};
            }
            appDebugLog('⚠️ Source "${cand.quality}" returned $status');
            return {'status': status};
          } catch (e) {
            appDebugLog('⚠️ Source "${cand.quality}" error: $e');
            return null;
          }
        }).toList();

        final resultsList = await Future.wait(checkFutures);
        
        // Find the first working one, strictly respecting original order (primary first, then alternates)
        for (int i = 0; i < candidates.length; i++) {
          final res = resultsList[i];
          if (res != null) {
            if (res['status'] != null) lastStatus = res['status'] as int;
            if (res['cand'] != null) {
              working = res['cand'] as StreamSource;
              break;
            }
          }
        }

        if (!mounted) return;
        if (working == null) {
          appDebugLog('❌ All ${candidates.length} source(s) failed for ${result.provider}');
          if (_hasNextProvider) {
            _advanceProvider();
            setState(() => _error = lastStatus != null
                ? 'Stream returned $lastStatus, trying next...'
                : 'Stream unreachable, trying next provider...');
            await Future.delayed(const Duration(milliseconds: 400));
            if (!mounted) return;
            _initializePlayer(isRetry: true);
            return;
          } else {
            throw Exception('Stream link is dead${lastStatus != null ? ' (HTTP $lastStatus)' : ''}');
          }
        }

        // Promote the reachable source as primary if it wasn't already.
        if (working.url != result.url) {
          appDebugLog('🔁 Promoting reachable source "${working.quality}" as primary');
          result = result.copyWith(
            url: working.url,
            quality: working.quality,
            isM3U8: working.isM3U8,
          );
        }
      }
      
      _trackInitialPlay();

      if (media != null) {
        _preloadAvailableAudios(result, media);
      }

      // Embed providers use WebView
      if (!_isDirectStream) {
        _dismissTooltips('loading → WebView player');
        setState(() {
          _isLoading = false;
          _retryCount = 0;
        });
        _updateWatchPartyHostSyncTimer();
        _startProgressTracking();
        _maybeAutoEnterFullscreenOnce();
        appDebugLog('✅ [FLOW] WebView player loaded!');
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
        if (Platform.isAndroid) {
          await np.setProperty('hwdec', 'mediacodec');
        } else {
          await np.setProperty('hwdec', 'auto-safe');
        }
        if (Platform.isLinux) {
          // Never shell out to the host's yt-dlp from mpv's ytdl hook; streams
          // are resolved by Nivio itself.
          await np.setProperty('ytdl', 'no');
        }
        
        final debandEnabled = ref.read(videoDebandingProvider);
        appDebugLog('🔧 Video debanding filter status during player initialization: $debandEnabled');
        await np.setProperty('deband', debandEnabled ? 'yes' : 'no');
        
        await np.setProperty('volume-max', '200'); // Software volume boost
        await np.setProperty('demuxer-max-bytes', '104857600'); // 100MB buffer
        await np.setProperty('demuxer-readahead-secs', '120'); // Buffer 2 mins ahead
        await np.setProperty('sub-delay', '${_subtitleDelayMs / 1000.0}');
        final fontSize = ref.read(subtitleFontSizeProvider);
        final baseScale = fontSize / 18.0;
        final scale = _isPipMode ? (baseScale * 0.45) : baseScale;
        await np.setProperty('sub-ass-override', 'scale');
        await np.setProperty('sub-scale', '$scale');
        
      }

      // Open media
      String targetUrl = result.url;
      if (targetUrl.startsWith('/') && !targetUrl.startsWith('file://')) {
        targetUrl = 'file://$targetUrl';
      }

      // The user may have backed out while providers were resolving. A removed
      // screen still reports mounted == true, so check deactivation as well.
      if (!mounted || _isDeactivated) {
        appDebugLog('🧪 [CW_DEBUG] PlayerScreen#$_sid screen closed during load — NOT opening stream');
        return;
      }
      appDebugLog('✅ [FLOW] Direct player loaded! Starting playback...');
      appDebugLog(
        '🧪 [CW_DEBUG] PlayerScreen#$_sid _player.open → player=${_hash(_player)} '
        'provider=${result.provider} startAt=$startAt url=$targetUrl',
      );
      // Start playback
      await _player.open(
        Media(
          targetUrl,
          httpHeaders: headers,
        ),
        play: true,
      );
      mediaOpened = true;
      appDebugLog(
        '🧪 [CW_DEBUG] PlayerScreen#$_sid _player.open returned — mounted=$mounted '
        'deactivated=$_isDeactivated',
      );
      if (!mounted || _isDeactivated) {
        // Closed while open() was in flight; deactivate()'s stop() ran before
        // the media started, so stop it again.
        appDebugLog('🧪 [CW_DEBUG] PlayerScreen#$_sid screen closed during open — stopping player');
        if (!_transferredToMiniPlayer) await _player.stop();
        return;
      }
      // Watch for servers that open cleanly but never produce a frame.
      _startStuckWatchdog();

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
      if (_bingeMode) {
        _prefetchBingeNext();
      }
      
      if (_resumePosition != null && mounted) {
        final marginHorizontal = (MediaQuery.of(context).size.width - 250) / 2;
        _messenger.showSnackBar(
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

      _dismissTooltips('loading → direct player');
      setState(() {
        _isLoading = false;
        _retryCount = 0;
      });

      _startProgressTracking();
      _updateWatchPartyHostSyncTimer();
      _scheduleWatchPartyBootstrapSyncs();
      appDebugLog('🧪 [CW_DEBUG] PlayerScreen#$_sid _initializePlayer SUCCESS on provider[$_currentProviderIndex] $_currentProvider');
    } catch (e, st) {
      appDebugLog(
        '❌ [CW_DEBUG] PlayerScreen#$_sid _initializePlayer FAILED on provider[$_currentProviderIndex/$_maxProviders] '
        '"$_currentProvider" — mounted=$mounted deactivated=$_isDeactivated '
        'player=${_hash(_player)} playing=${_player.state.playing} dur=${_player.state.duration}\n'
        '   error: $e\n$st',
      );
      if (mediaOpened) {
        appDebugLog(
          '🧪 [CW_DEBUG] PlayerScreen#$_sid stream already playing — treating as non-fatal, NOT switching provider',
        );
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _retryCount = 0;
        });
        _startProgressTracking();
        return;
      }
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });

      if (_hasNextProvider) {
        _advanceProvider();
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

  // Common ISO 639-1/639-2 codes → readable names for track labels.
  static const Map<String, String> _langNames = {
    'en': 'English', 'eng': 'English',
    'ja': 'Japanese', 'jpn': 'Japanese', 'jp': 'Japanese',
    'hi': 'Hindi', 'hin': 'Hindi',
    'ta': 'Tamil', 'tam': 'Tamil',
    'te': 'Telugu', 'tel': 'Telugu',
    'es': 'Spanish', 'spa': 'Spanish',
    'fr': 'French', 'fre': 'French', 'fra': 'French',
    'ko': 'Korean', 'kor': 'Korean',
    'de': 'German', 'ger': 'German', 'deu': 'German',
    'it': 'Italian', 'ita': 'Italian',
    'ar': 'Arabic', 'ara': 'Arabic',
    'pt': 'Portuguese', 'por': 'Portuguese',
    'ru': 'Russian', 'rus': 'Russian',
    'zh': 'Chinese', 'chi': 'Chinese', 'zho': 'Chinese',
    'ml': 'Malayalam', 'mal': 'Malayalam',
    'kn': 'Kannada', 'kan': 'Kannada',
    'bn': 'Bengali', 'ben': 'Bengali',
  };

  /// Maps a language code to a readable name; null when unknown/undetermined.
  String? _friendlyLang(String? code) {
    if (code == null) return null;
    final c = code.trim().toLowerCase();
    if (c.isEmpty ||
        c == 'und' ||
        c == 'unknown' ||
        c == 'unk' ||
        c == 'auto' ||
        c == 'default' ||
        c == 'none') {
      return null;
    }
    return _langNames[c] ?? (c.length <= 3 ? code.trim().toUpperCase() : code.trim());
  }

  /// Builds a track label that includes the language AND the embedded title
  /// (codec/name), e.g. "English · DDP5.1 Atmos". Empty titles/languages are
  /// treated as absent (mkv tracks often have an empty title), and a numbered
  /// fallback keeps otherwise-identical tracks distinguishable.
  String _trackLabel(String? title, String? language, int index, String kind) {
    final lang = _friendlyLang(language);
    var t = (title ?? '').trim();
    final tLower = t.toLowerCase();
    if (tLower == 'sub.vtt' ||
        tLower == 'sub.srt' ||
        tLower == 'subtitle.vtt' ||
        tLower == 'auto' ||
        tLower == 'default') {
      t = '';
    }
    if (lang != null && t.isNotEmpty && lang.toLowerCase() != t.toLowerCase()) {
      return '$lang · $t';
    }
    if (lang != null) return lang;
    if (t.isNotEmpty) return t;
    return index == 0 ? 'Default $kind' : '$kind ${index + 1}';
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

    // Apply Subtitle Track.
    // Selectable embedded subtitle tracks (excluding the synthetic auto/no).
    final selectableSubs =
        subtitleTracks.where((t) => t.id != 'auto' && t.id != 'no').toList();

    if (preferredSubtitle == 'Off') {
      _player.setSubtitleTrack(SubtitleTrack.no());
    } else {
      SubtitleTrack? chosen;

      // 1. Try to honour a specific preferred language (skipped for 'Auto').
      if (preferredSubtitle.isNotEmpty && preferredSubtitle != 'Auto') {
        for (int i = 0; i < selectableSubs.length; i++) {
          final track = selectableSubs[i];
          final title = (track.title ?? '').trim();
          final lang = (track.language ?? '').trim();
          final label = _trackLabel(track.title, track.language, i, 'Subtitle');
          if (title == preferredSubtitle ||
              lang == preferredSubtitle ||
              label == preferredSubtitle ||
              _isLanguageMatch(title, preferredSubtitle) ||
              _isLanguageMatch(lang, preferredSubtitle) ||
              _isLanguageMatch(label, preferredSubtitle)) {
            chosen = track;
            break;
          }
        }
      }

      // 2. Fallback: enable the FIRST embedded subtitle track. This is what
      //    fixes anime torrents/streams whose single sub track has a blank title and
      //    no/undetermined language — previously nothing matched, so subtitles
      //    silently stayed off. Subs-on-by-default matches how the app plays.
      chosen ??= selectableSubs.isNotEmpty ? selectableSubs.first : null;

      if (chosen != null) {
        _player.setSubtitleTrack(chosen);
      } else if (_streamResult != null && _streamResult!.subtitles.isNotEmpty) {
        // 3. No embedded tracks: check if an external subtitle matches preferred,
        //    else pick the first external subtitle.
        final ext = _streamResult!.subtitles;
        final match = ext.firstWhere(
          (s) =>
              preferredSubtitle != 'Auto' &&
              s.lang.isNotEmpty &&
              (s.lang == preferredSubtitle ||
                  _isLanguageMatch(s.lang, preferredSubtitle)),
          orElse: () => ext.first,
        );
        final alreadyLoaded = selectableSubs.any((t) {
          final tTitle = (t.title ?? '').trim().toLowerCase();
          final tLang = (t.language ?? '').trim().toLowerCase();
          final mLang = match.lang.trim().toLowerCase();
          return (mLang.isNotEmpty && (tTitle == mLang || tLang == mLang)) ||
                 (match.url.isNotEmpty && (tTitle.contains(match.url) || match.url.endsWith(tTitle)));
        });
        if (!alreadyLoaded) {
          _player.setSubtitleTrack(SubtitleTrack.uri(match.url, title: match.lang.isNotEmpty ? match.lang : 'Default Subtitle'));
        }
      } else {
        _player.setSubtitleTrack(SubtitleTrack.auto());
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
        if (_isZombieCallback('position stream')) return;
        // First time the stream actually advances past zero: the server works.
        if (!_sawFirstFrame && position > Duration.zero) {
          _sawFirstFrame = true;
          _stuckWatchdog?.cancel();
          final ms = _openStartedAt == null
              ? '?'
              : DateTime.now().difference(_openStartedAt!).inMilliseconds;
          appDebugLog(
            '▶️ [STUCK_DEBUG] PlayerScreen#$_sid first frame for "$_currentProvider" '
            'after ${ms}ms (pos=$position)${_stuckReported ? ' (was flagged stuck — recovered)' : ''}',
          );
        }
        _checkNextEpisode();
        unawaited(_broadcastWatchPartyPlayback(force: false));
        _updateDiscordActivity();
      }),
    );

    // Playing state stream
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (!mounted) return;
        if (_isZombieCallback('playing stream')) return;
        unawaited(_broadcastWatchPartyPlayback(force: true));
        _updateDiscordActivity(isPlaying: playing, force: true);
        _syncPipPlayingState(playing);
        MediaSessionService.instance.updateMetadata(this, _mediaSessionMetadata());
      }),
    );

    // Completed stream
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (!mounted || !completed) return;
        if (_isZombieCallback('completed stream')) return;

        final pos = _player.state.position;
        final dur = _player.state.duration;
        
        // Ignore premature EOF from network dropouts (especially on torrent streams 
        // where mpv times out if pieces aren't downloaded fast enough or before container headers are read).
        final isTorrentStream = _currentProvider == 'Nivio Torrents';
        final isPrematureEof = (dur.inSeconds > 60 && pos.inSeconds < dur.inSeconds - 15) ||
            (dur == Duration.zero && !_sawFirstFrame);

        if (isPrematureEof) {
          appDebugLog('⚠️ Ignoring premature EOF or instant completion (pos=${pos.inSeconds}s, dur=${dur.inSeconds}s, torrent=$isTorrentStream). Retrying stream...');
          
          _resumePosition = pos > Duration.zero ? pos : null;
          
          Future.microtask(() async {
            if (mounted) {
              setState(() {
                _isLoading = true;
              });

              if (isTorrentStream) {
                await Future.delayed(const Duration(milliseconds: 1000));
              }
              
              if (_streamResult != null) {
                await _player.open(
                  Media(
                    _streamResult!.url,
                    httpHeaders: _streamResult!.headers,
                  ),
                  play: true,
                );
                if (pos > Duration.zero) {
                  await _player.seek(pos);
                }
              } else {
                // Fallback if _streamResult is somehow null
                _disposePlayer();
                _initializePlayer(isRetry: true);
              }
              
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            }
          });
          return;
        }

        _markAsCompleted();
        if (_hasNextEpisode()) {
          _showNextEpisodePopup();
        } else {
          _markWatchlistCompletedIfNeeded();
        }
      }),
    );

    // Tracks stream — refresh UI when new tracks are parsed
    _subscriptions.add(
      _player.stream.tracks.listen((_) {
        if (!mounted) return;
        if (_isZombieCallback('tracks stream')) return;
        _applyTrackPreferences();
        setState(() {});
      }),
    );

    // Error stream
    _subscriptions.add(
      _player.stream.error.listen((error) {
        if (!mounted) return;
        appDebugLog(
          '🎬 Player error (screen#$_sid, player=${_hash(_player)}, '
          'deactivated=$_isDeactivated): $error',
        );
      }),
    );

    // Buffering stream
    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        if (!mounted) return;
        if (_isZombieCallback('buffering stream')) return;
        // Only log while we haven't seen playback yet — a server stuck at 0:00
        // usually sits in buffering=true forever, or flips to false with no frame.
        if (!_sawFirstFrame) {
          appDebugLog(
            '⏳ [STUCK_DEBUG] PlayerScreen#$_sid buffering=$buffering for "$_currentProvider" '
            '(pos=${_player.state.position} dur=${_player.state.duration})',
          );
        }
      }),
    );
  }

  /// Title/artwork for the OS media session (headset & media-key controls).
  MediaSessionMetadata _mediaSessionMetadata() {
    final media = ref.read(selectedMediaProvider);
    final title = widget.directStreamTitle ?? media?.title ?? media?.name ?? 'Nivio';

    String? subtitle;
    if (widget.directStreamTitle != null) {
      subtitle = widget.isLive ? 'Live Stream' : null;
    } else if (widget.mediaType == 'tv' ||
        widget.mediaType == 'anime' ||
        (media?.mediaType == 'tv')) {
      subtitle = 'Season ${widget.season} · Episode $_currentEpisode';
    }

    String? artUrl;
    final posterPath = widget.directStreamTitle != null
        ? null
        : (media?.posterPath ?? media?.backdropPath);
    if (posterPath != null && posterPath.isNotEmpty) {
      if (posterPath.startsWith('http')) {
        artUrl = posterPath;
      } else {
        final path = posterPath.startsWith('/') ? posterPath : '/$posterPath';
        artUrl = 'https://image.tmdb.org/t/p/w500$path';
      }
    }

    return MediaSessionMetadata(title: title, subtitle: subtitle, artUrl: artUrl);
  }

  void _updateDiscordActivity({bool? isPlaying, bool force = false}) {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    final playing = isPlaying ?? _player.state.playing;
    final media = ref.read(selectedMediaProvider);
    final title = widget.directStreamTitle ??
        media?.title ??
        media?.name ??
        'Video';

    if (!playing) {
      DiscordRpcService.instance.setPaused(title: title);
      return;
    }

    final pos = _player.state.position;
    final now = DateTime.now();

    // Check if seek occurred (> 10s difference from expected time)
    if (!force) {
      final elapsedSinceLastSync = now.difference(_lastDiscordSync);
      if (elapsedSinceLastSync.inSeconds < 5) return;
      final expectedPos = _lastDiscordPos + elapsedSinceLastSync;
      final diff = (pos - expectedPos).inSeconds.abs();
      // If position is roughly what Discord is already displaying, don't spam IPC
      if (diff < 10) return;
    }

    _lastDiscordSync = now;
    _lastDiscordPos = pos;

    String? details;
    if (widget.directStreamTitle != null) {
      details = widget.isLive ? 'Live Stream' : 'Streaming';
    } else if (widget.mediaType == 'tv' ||
        widget.mediaType == 'anime' ||
        (media?.mediaType == 'tv')) {
      details = 'Season ${widget.season} · Episode $_currentEpisode';
    } else {
      details = 'Movie';
    }

    String? posterUrl;
    final posterPath = media?.posterPath ?? media?.backdropPath;
    if (posterPath != null && posterPath.isNotEmpty) {
      if (posterPath.startsWith('http')) {
        posterUrl = posterPath;
      } else {
        final path = posterPath.startsWith('/') ? posterPath : '/$posterPath';
        posterUrl = 'https://image.tmdb.org/t/p/w500$path';
      }
    }

    final startedAt = now.subtract(pos);

    DiscordRpcService.instance.setWatching(
      title: title,
      details: details,
      posterUrl: posterUrl,
      startedAt: startedAt,
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
      _messenger.showSnackBar(
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
      _messenger.showSnackBar(SnackBar(content: Text(message.trim())));
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
      _messenger.showSnackBar(
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
                                    _messenger.showSnackBar(
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
      if (isInIntro && ref.read(autoSkipIntroOutroProvider)) {
        _skipIntro();
      }
    }

    final edSkip = _skipTimes.where((s) => s.type == 'ed' || s.type == 'mixed-ed').firstOrNull;
    final isInOutro = edSkip != null && position >= edSkip.startTime && position < edSkip.endTime;
    if (isInOutro != _isInOutroSegment) {
      setState(() { _isInOutroSegment = isInOutro; });
      if (isInOutro && ref.read(autoSkipIntroOutroProvider)) {
        _skipOutro();
      }
    }

    // --- Next Episode (trigger 15s before the actual end of the video) ---
    if (!_showNextEpisodeButton && !_nextEpisodeDismissed && _hasNextEpisode() && duration.inSeconds > 60) {
      final remaining = duration.inSeconds - position.inSeconds;
      if (remaining <= 15) {
        _showNextEpisodePopup();
      }
    }

    if (duration.inSeconds > 60 && position >= duration - const Duration(seconds: 10)) {
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
    
    // For P2P streams, prefetch next episode if binge mode is active
    if (_currentProvider == 'Nivio Torrents') {
      if (_bingeMode) {
        _prefetchBingeNext();
      }
      return;
    }
    // Don't prefetch while streaming a still-downloading item.
    if (_isDownloadStream) return;

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
    // Binge mode always counts down (continuous play), even if the global
    // auto-play-next setting is off.
    final autoPlay = ref.read(autoPlayNextEpisodeProvider) || _bingeMode;
    if (!autoPlay) {
      setState(() {
        _showNextEpisodeButton = true;
        _nextEpisodeCountdown = null;
      });
      _nextEpNotifier.value = const _NextEpState(show: true, countdown: null);
      _showOverlayEntry();
      return;
    }
    setState(() {
      _showNextEpisodeButton = true;
      _nextEpisodeCountdown = 15;
    });
    _showOverlayEntry();
    _beginNextEpisodeCountdown(15);
  }

  /// Starts (or restarts) the auto-advance countdown, and — in binge mode —
  /// kicks off the medium prefetch so the next episode is ready by 0s.
  void _beginNextEpisodeCountdown(int start) {
    _nextEpisodeCountdown = start;
    _nextEpNotifier.value = _NextEpState(show: true, countdown: start);
    if (_bingeMode) _prefetchBingeNext();
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

  Future<void> _toggleBingeMode() async {
    final enabling = !_bingeMode;
    setState(() => _bingeMode = enabling);
    if (enabling) {
      // Load the remembered release group so the card can show it.
      final group =
          await _cachedTorrentService?.recallReleaseGroup(widget.mediaId);
      if (mounted) setState(() => _bingeGroup = group);
      _prefetchBingeNext();
    }
    // Rebuild the overlay so it reflects the new binge state immediately.
    if (_showNextEpisodeButton) {
      _removeOverlayEntry();
      _showOverlayEntry();
      // If the card was showing without a countdown, binge starts one now
      // (which also triggers the prefetch); turning binge off stops it.
      if (enabling && _nextEpisodeCountdown == null) {
        _beginNextEpisodeCountdown(15);
      } else if (!enabling) {
        _nextEpisodeTimer?.cancel();
        setState(() => _nextEpisodeCountdown = null);
        _nextEpNotifier.value = const _NextEpState(show: true, countdown: null);
      }
    }
  }

  /// Medium prefetch: while the up-next card counts down, pre-add the next
  /// episode's torrent to rqbit so the switch is near-instant. Torrents only.
  void _prefetchBingeNext() {
    if (!_bingeMode || _currentProvider != 'Nivio Torrents') return;
    if (!_hasNextEpisode()) return;
    final media = ref.read(selectedMediaProvider) ?? _cachedMedia;
    if (media == null) return;
    final nextEp = _currentEpisode + 1;
    final resMatch = RegExp(r'\d{3,4}').firstMatch(_streamResult?.quality ?? '');
    final resolution = resMatch?.group(0) ?? '1080';
    unawaited(
      _cachedTorrentService?.prefetchEpisode(
        media: media,
        episode: nextEp,
        season: widget.season,
        resolution: resolution,
        absoluteEpisode: null,
        preferredGroup: _bingeGroup,
      ) ??
          Future.value(),
    );
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

    if (dur.inSeconds <= 0) {
      appDebugLog('⚠️ Ignoring _markAsCompleted because duration is 0 (playback likely failed or stream ended prematurely)');
      return;
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
    final effectiveMediaType = media?.mediaType ?? widget.mediaType;
    if (effectiveMediaType != 'tv' && effectiveMediaType != 'anime') return false; // Movies return false

    // Check if the next episode exists locally in completed downloads or active downloads
    final nextDownloaded = DownloadService.findPlayableDownload(
      mediaId: widget.mediaId,
      season: widget.season,
      episode: _currentEpisode + 1,
    );
    if (nextDownloaded != null) return true;

    final nextInProgress = DownloadService.findInProgressDownload(
      mediaId: widget.mediaId,
      season: widget.season,
      episode: _currentEpisode + 1,
    );
    if (nextInProgress != null) return true;
    
    if (_prefetchedStreams.containsKey(_currentEpisode + 1)) return true;
    
    if (_currentSeasonData != null) {
      final autoSkipFiller = ref.read(autoSkipFillerProvider);
      if (autoSkipFiller && _isAnimeMedia(media) && _fillerData.fillerEpisodes.isNotEmpty) {
        int next = _currentEpisode + 1;
        while (_fillerData.isFiller(next) && next <= _currentSeasonData!.episodes.length) {
          next++;
        }
        return next <= _currentSeasonData!.episodes.length;
      }
      return _currentEpisode < _currentSeasonData!.episodes.length;
    }
    
    return false;
  }

  /// When a title reaches its end, automatically move it to the Completed
  /// bucket of the watchlist instead of asking whether to remove it. Nothing
  /// is deleted — finished titles simply flow from Watching -> Completed and
  /// stay in the library. Anime completion is also pushed to AniList/MAL.
  Future<void> _markWatchlistCompletedIfNeeded() async {
    final media = ref.read(selectedMediaProvider);
    if (media == null) return;

    final watchlistService = ref.read(watchlistServiceProvider);
    final items = watchlistService.getAllItems();

    final mediaTitle = (media.title ?? media.name ?? '').toLowerCase();
    final match = items.where((w) =>
      w.id == widget.mediaId ||
      w.title.toLowerCase() == mediaTitle
    ).firstOrNull;

    if (match == null) return;
    if (match.watchStatus == WatchStatus.completed) return;

    await watchlistService.updateWatchStatus(
      match.id,
      WatchStatus.completed,
      currentEpisode: match.currentEpisode,
      totalEpisodes: match.totalEpisodes,
    );
    ref.read(watchlistRefreshProvider.notifier).refresh();

    if (match.mediaType == 'anime' || match.anilistId != null || match.malId != null) {
      unawaited(
        AnimeTrackingCoordinator.instance.syncWatchStatus(
          anilistId: match.anilistId ?? (match.mediaType == 'anime' ? match.id : null),
          malId: match.malId,
          status: WatchStatus.completed,
          episode: match.currentEpisode ?? 1,
        ),
      );
    }

    if (mounted) {
      _messenger.showSnackBar(
        SnackBar(content: Text('Marked ${match.title} as completed')),
      );
    }
  }

  void _playNextEpisode() {
    final autoSkipFiller = ref.read(autoSkipFillerProvider);
    final media = ref.read(selectedMediaProvider);
    int nextEpisode = _currentEpisode + 1;

    if (autoSkipFiller && _isAnimeMedia(media) && _fillerData.fillerEpisodes.isNotEmpty) {
      final maxEp = _currentSeasonData?.episodes.length ?? 99999;
      int skippedCount = 0;
      while (_fillerData.isFiller(nextEpisode) && nextEpisode <= maxEp) {
        nextEpisode++;
        skippedCount++;
      }

      if (skippedCount > 0 && mounted) {
        if (nextEpisode > maxEp) {
          _messenger.showSnackBar(
            SnackBar(
              content: const Text('Reached end of season (no more non-filler episodes)'),
              duration: const Duration(seconds: 3),
              backgroundColor: NivioTheme.accentColorOf(context),
            ),
          );
          return;
        }
        _messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Skipped $skippedCount filler episode${skippedCount > 1 ? 's' : ''} -> Playing Episode $nextEpisode',
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: NivioTheme.accentColorOf(context),
          ),
        );
      }
    }

    _playEpisode(nextEpisode);
  }

  void _playEpisode(int episodeNumber) {
    if (_currentEpisode == episodeNumber) return;
    _nextEpisodeTimer?.cancel();
    _removeOverlayEntry();
    
    final media = ref.read(selectedMediaProvider);
    final effectiveMediaType = media?.mediaType ?? widget.mediaType;
    if (effectiveMediaType != 'tv' && effectiveMediaType != 'anime') return;

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
      _runningFetchers = null;
      _nativePosition = Duration.zero;
      _nativeDuration = Duration.zero;
      _skipTimes = [];
      _isInIntroSegment = false;
      _isInOutroSegment = false;
      _isFetchingSkipTimes = false;
      _prepareProvidersFuture = null;
    });
    
    _initializePlayer(isRetry: false);
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
        fillerData: _fillerData,
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
      _messenger.showSnackBar(
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
      _isManualProviderSwitch = true;
      _currentProviderIndex = providerIndex;
      _isLoading = true;
      _error = null;
      _retryCount = 0;
      _streamResult = null;
      _runningFetchers = null;
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
          _messenger.showSnackBar(
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
          _messenger.showSnackBar(
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
        _messenger.showSnackBar(
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
      _messenger.showSnackBar(
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
        _messenger.showSnackBar(
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
      _messenger.showSnackBar(
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
    
    final isTorrent = providerName == 'Nivio Torrents';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isTorrent
              ? BorderSide(
                  color: isCurrent
                      ? Theme.of(context).primaryColor.withOpacity(0.5)
                      : Colors.white.withOpacity(0.18),
                  width: 1.0,
                )
              : BorderSide.none,
        ),
        tileColor: isCurrent 
            ? Theme.of(context).primaryColor.withOpacity(0.15) 
            : (isTorrent ? Colors.white.withOpacity(0.04) : null),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        leading: isTorrent
            ? Icon(
                Icons.cloud_download_rounded,
                color: isCurrent ? Theme.of(context).primaryColor : Colors.greenAccent,
                size: 22,
              )
            : null,
        title: Row(
          children: [
            Text(
              providerName,
              style: TextStyle(
                color: isCurrent ? Theme.of(context).primaryColor : Colors.white,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                fontSize: 16,
              ),
            ),
            if (isTorrent) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.4), width: 0.8),
                ),
                child: const Text(
                  'P2P',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: isTorrent
            ? Text(
                'High quality BitTorrent stream',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              )
            : null,
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

        if (groupName == 'Nivio Torrents') {
          for (final i in indices) {
            widgets.add(_buildSingleProviderTile(i, media));
          }
          continue;
        }

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
      if (_isZombieCallback('progress timer')) return;
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
    
    // Cache providers safely if we are still mounted and active
    if (mounted && !_isDisposing) {
      try {
        _cachedHistoryService ??= ref.read(watchHistoryServiceProvider);
        _cachedMedia ??= ref.read(selectedMediaProvider);
      } catch (_) {}
    }
    
    SearchResult? media = _cachedMedia;
    if (media == null && mounted && !_isDisposing) {
      try {
        media = ref.read(selectedMediaProvider);
      } catch (_) {}
    }
    if (media == null) return;
    
    WatchHistoryService? historyService = _cachedHistoryService;
    if (historyService == null && mounted && !_isDisposing) {
      try {
        historyService = ref.read(watchHistoryServiceProvider);
      } catch (_) {}
    }
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

    // Sync anime watch progress to AniList, MAL, and Watchlist if enabled
    if (_isAnimeMedia(media)) {
      final progressRatio = duration.inSeconds > 0
          ? (position.inSeconds / duration.inSeconds)
          : 0.0;

      if (progressRatio >= 0.80 &&
          _lastTrackingSyncedEpisode != _currentEpisode) {
        _lastTrackingSyncedEpisode = _currentEpisode;
        final isCompleted = _currentSeasonData?.episodes.length != null &&
            _currentEpisode >= _currentSeasonData!.episodes.length &&
            progressRatio >= 0.90;
        final anilistId = media.id;
        final malId = media.malId ?? _resolvedMalId;
        final targetStatus = isCompleted ? WatchStatus.completed : WatchStatus.watching;

        final watchlistService = ref.read(watchlistServiceProvider);
        final watchItem = watchlistService.getItem(widget.mediaId);

        bool autoSyncEnabled = true;
        try {
          autoSyncEnabled = ref.read(animeAutoSyncProgressProvider);
        } catch (_) {}

        if (watchItem != null) {
          watchlistService.updateWatchStatus(
            widget.mediaId,
            targetStatus,
            currentEpisode: _currentEpisode,
            totalEpisodes: _currentSeasonData?.episodes.length,
          );
          ref.read(watchlistRefreshProvider.notifier).refresh();
        } else if (autoSyncEnabled) {
          final newWatchItem = WatchlistItem(
            id: widget.mediaId,
            title: media.title ?? media.name ?? 'Unknown',
            posterPath: media.posterPath ?? media.backdropPath,
            mediaType: media.mediaType,
            addedAt: DateTime.now(),
            voteAverage: media.voteAverage,
            releaseDate: media.releaseDate ?? media.firstAirDate,
            overview: media.overview,
            watchStatus: targetStatus,
            currentEpisode: _currentEpisode,
            totalEpisodes: _currentSeasonData?.episodes.length,
            anilistId: anilistId,
            malId: malId,
          );
          watchlistService.addToWatchlist(newWatchItem, status: targetStatus);
          ref.read(watchlistRefreshProvider.notifier).refresh();
        }

        if (autoSyncEnabled) {
          unawaited(
            AnimeTrackingCoordinator.instance.syncWatchProgress(
              anilistId: anilistId,
              malId: malId,
              episode: _currentEpisode,
              isCompleted: isCompleted,
            ),
          );
          // Parity with AniList/MAL: also record the watched episode on Simkl
          // so its watched-episode count tracks real progress (status alone,
          // synced via the watchlist, would leave Simkl at 0/N).
          if (SimklAuthService.instance.isAuthenticated) {
            unawaited(
              SimklAuthService.instance.markWatched(
                mediaType: 'anime',
                tmdbId: widget.mediaId,
                malId: malId,
                anilistId: anilistId,
                season: widget.season,
                episode: _currentEpisode,
              ),
            );
          }
        }
      }
    }
  }

  void _disposePlayer() {
    _saveProgress(); // Ensure we save one last time on exit
    _progressTimer?.cancel();
    _removeFullscreenTopBarOverlayEntry();
    _removeTrackingPromptOverlay();
    _player.stop();
  }

  @override
  void dispose() {
    final zombieMs = _deactivatedAt == null
        ? 'n/a'
        : '${DateTime.now().difference(_deactivatedAt!).inMilliseconds}ms';
    appDebugLog('🧪 [CW_DEBUG] PlayerScreen#$_sid dispose() — $zombieMs after deactivate(), player=${_hash(_player)}');
    appDebugLog('🔴 [DISPOSE] Step 0: dispose() CALLED — mounted=$mounted, _transferredToMiniPlayer=$_transferredToMiniPlayer, _isDirectStream=$_isDirectStream');
    _isDisposing = true;

    // Keep media buttons working while the mini player owns the player.
    if (_transferredToMiniPlayer) {
      MediaSessionService.instance.releaseOwner(this);
    } else {
      MediaSessionService.instance.detach(this);
    }

    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        appDebugLog('🔴 [DISPOSE] Step 1: setWindowFullScreen(false)...');
        setWindowFullScreen(false);
        appDebugLog('🔴 [DISPOSE] Step 1: ✅ done');
      }
    } catch (e, st) {
      appDebugLog('🔴 [DISPOSE] Step 1: ❌ FAILED — $e\n$st');
    }

    try {
      appDebugLog('🔴 [DISPOSE] Step 2: WakelockPlus.disable()...');
      unawaited(WakelockPlus.disable());
      appDebugLog('🔴 [DISPOSE] Step 2: ✅ done');
    } catch (e, st) {
      appDebugLog('🔴 [DISPOSE] Step 2: ❌ FAILED — $e\n$st');
    }

    // Release the active torrent unless playback continues in the mini-player.
    if (!_transferredToMiniPlayer) {
      try {
        unawaited(_cachedTorrentService?.stopActive() ?? Future.value());
      } catch (_) {}
    }

    if (Platform.isAndroid) {
      try {
        appDebugLog('🔴 [DISPOSE] Step 3: Android PIP cleanup...');
        const MethodChannel('com.nivio/gesture_exclusion').invokeMethod('setCanEnterPip', {'value': false});
        const MethodChannel('com.nivio/gesture_exclusion').setMethodCallHandler(null);
        const MethodChannel('puntito.simple_pip_mode').setMethodCallHandler(null);
        SimplePip().setAutoPipMode(aspectRatio: const (16, 9), autoEnter: false);
        appDebugLog('🔴 [DISPOSE] Step 3: ✅ done');
      } catch (e, st) {
        appDebugLog('🔴 [DISPOSE] Step 3: ❌ FAILED — $e\n$st');
      }
    }

    try {
      appDebugLog('🔴 [DISPOSE] Step 4: cancel timers...');
      _progressTimer?.cancel();
      _stuckWatchdog?.cancel();
      _watchPartyHostSyncTimer?.cancel();
      _watchPartyPlaybackSub?.cancel();
      _watchPartySessionSub?.cancel();
      _watchPartyErrorSub?.cancel();
      _nextEpisodeTimer?.cancel();
      appDebugLog('🔴 [DISPOSE] Step 4: ✅ done');
    } catch (e, st) {
      appDebugLog('🔴 [DISPOSE] Step 4: ❌ FAILED — $e\n$st');
    }

    try {
      appDebugLog('🔴 [DISPOSE] Step 5: _removeOverlayEntry()...');
      _removeOverlayEntry();
      appDebugLog('🔴 [DISPOSE] Step 5: ✅ done');
    } catch (e, st) {
      appDebugLog('🔴 [DISPOSE] Step 5: ❌ FAILED — $e\n$st');
    }

    try {
      appDebugLog('🔴 [DISPOSE] Step 6: _removeFullscreenTopBarOverlayEntry()...');
      _removeFullscreenTopBarOverlayEntry();
      _removeTrackingPromptOverlay();
      appDebugLog('🔴 [DISPOSE] Step 6: ✅ done');
    } catch (e, st) {
      appDebugLog('🔴 [DISPOSE] Step 6: ❌ FAILED — $e\n$st');
    }

    try {
      appDebugLog('🔴 [DISPOSE] Step 7: dispose notifiers...');
      _nextEpNotifier.dispose();
      _fullscreenTopBarVisibleNotifier.dispose();
      appDebugLog('🔴 [DISPOSE] Step 7: ✅ done');
    } catch (e, st) {
      appDebugLog('🔴 [DISPOSE] Step 7: ❌ FAILED — $e\n$st');
    }

    try {
      appDebugLog('🔴 [DISPOSE] Step 8: _saveProgress (duration=${_player.state.duration})...');
      if (_player.state.duration > Duration.zero) {
        _saveProgress();
      }
      appDebugLog('🔴 [DISPOSE] Step 8: ✅ done');
    } catch (e, st) {
      appDebugLog('🔴 [DISPOSE] Step 8: ❌ FAILED — $e\n$st');
    }

    try {
      appDebugLog('🔴 [DISPOSE] Step 9: _player.dispose() — _transferredToMiniPlayer=$_transferredToMiniPlayer...');
      if (!_transferredToMiniPlayer) {
        _player.dispose();
      }
      appDebugLog('🔴 [DISPOSE] Step 9: ✅ done');
    } catch (e, st) {
      appDebugLog('🔴 [DISPOSE] Step 9: ❌ FAILED — $e\n$st');
    }

    try {
      appDebugLog('🔴 [DISPOSE] Step 10: cancel stream subscriptions (${_subscriptions.length})...');
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      _hasAppliedGlobalTracks = false;
      appDebugLog('🔴 [DISPOSE] Step 10: ✅ done');
    } catch (e, st) {
      appDebugLog('🔴 [DISPOSE] Step 10: ❌ FAILED — $e\n$st');
    }

    try {
      appDebugLog('🔴 [DISPOSE] Step 11: _focusNode.dispose()...');
      _focusNode.dispose();
      appDebugLog('🔴 [DISPOSE] Step 11: ✅ done');
    } catch (e, st) {
      appDebugLog('🔴 [DISPOSE] Step 11: ❌ FAILED — $e\n$st');
    }

    try {
      appDebugLog('🔴 [DISPOSE] Step 12: signal player inactive...');
      final cachedNotifier = _cachedPlayerActiveNotifier;
      if (cachedNotifier != null) {
        Future.microtask(() => cachedNotifier.state = false);
      }
      if (!_transferredToMiniPlayer &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        DiscordRpcService.instance.setBrowsing();
      }
      appDebugLog('🔴 [DISPOSE] Step 12: ✅ done');
    } catch (e, st) {
      appDebugLog('🔴 [DISPOSE] Step 12: ❌ FAILED — $e\n$st');
    }

    try {
      appDebugLog('🔴 [DISPOSE] Step 13: SystemChrome orientations + UI mode...');
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      appDebugLog('🔴 [DISPOSE] Step 13: ✅ done');
    } catch (e, st) {
      appDebugLog('🔴 [DISPOSE] Step 13: ❌ FAILED — $e\n$st');
    }

    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}

    appDebugLog('🔴 [DISPOSE] Step 14: super.dispose()...');
    super.dispose();
    appDebugLog('🔴 [DISPOSE] Step 14: ✅ ALL DONE');
  }

  /// Closes any visible tooltip before a big subtree swap (route pop, loading →
  /// playing). A tooltip's overlay child left open while its owner is torn out
  /// is the prime suspect for the '!child.attached' semantics assertion.
  void _dismissTooltips(String where) {
    final hadTooltip = Tooltip.dismissAllToolTips();
    appDebugLog('🧪 [CW_DEBUG] PlayerScreen#$_sid tooltips dismissed at $where — anyVisible=$hadTooltip');
  }

  void _handleBackNavigation() {
    _dismissTooltips('back navigation');
    appDebugLog('🟡 [BACK_NAV] Step 0: _handleBackNavigation() CALLED — mounted=$mounted, _isDirectStream=$_isDirectStream, _isInFullscreen=$_isInFullscreen, _useNativePlayer=$_useNativePlayer');
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    if (isDesktop) {
      try {
        appDebugLog('🟡 [BACK_NAV] Step 1: setWindowFullScreen(false)...');
        setWindowFullScreen(false);
        appDebugLog('🟡 [BACK_NAV] Step 1: ✅ done');
      } catch (e, st) {
        appDebugLog('🟡 [BACK_NAV] Step 1: ❌ FAILED — $e\n$st');
      }
    }
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_isDirectStream && _isInFullscreen) {
      appDebugLog('🟡 [BACK_NAV] Step 2: exit embed fullscreen (not direct stream)...');
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      setState(() {
        _isInFullscreen = false;
      });
      _syncFullscreenTopBarVisibility();
      appDebugLog('🟡 [BACK_NAV] Step 2: ✅ done — returning early');
      return;
    }

    // On desktop, enter mini player mode instead of fully closing.
    // CRITICAL FIX: We must detach the Video widget from the PlayerScreen's
    // tree FIRST, wait one frame for the native texture to be released, and
    // THEN activate the mini player + navigate. Otherwise, two Video widgets
    // share the same VideoController/native texture simultaneously, causing a
    // native DirectX crash on Windows.
    if (isDesktop && !_useNativePlayer && _player.state.duration > Duration.zero) {
      appDebugLog('🟡 [BACK_NAV] Step 3: detaching Video widget before mini player handoff...');
      setState(() {
        _videoDetached = true;
      });

      // Wait one frame so the Video widget is fully removed from the tree
      // and the native rendering surface is released.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          appDebugLog('🟡 [BACK_NAV] Step 3b: activating mini player (post-frame)...');
          final media = ref.read(selectedMediaProvider);
          _transferredToMiniPlayer = true;
          ref.read(miniPlayerProvider.notifier).activate(
            player: _player,
            videoController: _videoController,
            mediaInfo: MiniPlayerMediaInfo(
              mediaId: widget.mediaId,
              season: widget.season,
              episode: _currentEpisode,
              mediaType: widget.mediaType ?? media?.mediaType,
              title: media?.title ?? media?.name ?? 'Playing',
              posterPath: media?.posterPath ?? media?.backdropPath,
              totalSeasons: 1,
              totalEpisodes: _currentSeasonData?.episodes.length,
            ),
          );
          appDebugLog('🟡 [BACK_NAV] Step 3b: ✅ mini player activated');
          appDebugLog(
            '🧪 [CW_DEBUG] PlayerScreen#$_sid handed player=${_hash(_player)} '
            'ctrl=${_hash(_videoController)} to mini player — this screen should dispose next',
          );
        } catch (e, st) {
          appDebugLog('🟡 [BACK_NAV] Step 3b: ❌ FAILED — $e\n$st');
        }

        _navigateAway(isDesktop);
      });
      return;
    }

    if (!isDesktop) {
      appDebugLog('🟡 [BACK_NAV] Step 4: mobile orientation reset...');
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    _navigateAway(isDesktop);
  }

  void _navigateAway(bool isDesktop) {
    try {
      appDebugLog('🟡 [BACK_NAV] Step 5: navigating away — canPop=${context.canPop()}...');
      if (context.canPop()) {
        Navigator.of(context).pop();
        appDebugLog('🟡 [BACK_NAV] Step 5: ✅ popped');
        return;
      }
      appDebugLog('🟡 [BACK_NAV] Step 5: cannot pop, using context.go("/home")...');
      context.go('/home');
      appDebugLog('🟡 [BACK_NAV] Step 5: ✅ navigated to /home');
    } catch (e, st) {
      appDebugLog('🟡 [BACK_NAV] Step 5: ❌ FAILED — $e\n$st');
    }
  }

  void _forceExitPlayer() {
    appDebugLog('🟠 [FORCE_EXIT] CALLED — mounted=$mounted');
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    if (!isDesktop) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    
    try {
      appDebugLog('🟠 [FORCE_EXIT] navigating — canPop=${context.canPop()}...');
      if (context.canPop()) {
        Navigator.of(context).pop();
        appDebugLog('🟠 [FORCE_EXIT] ✅ popped');
        return;
      }
      context.go('/home');
      appDebugLog('🟠 [FORCE_EXIT] ✅ navigated to /home');
    } catch (e, st) {
      appDebugLog('🟠 [FORCE_EXIT] ❌ FAILED — $e\n$st');
    }
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
    final media = ref.read(selectedMediaProvider) ?? _cachedMedia;
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
                                            ...audioTracks.where((track) => track.id != 'auto' && track.id != 'no').toList().asMap().entries.map((entry) {
                                              final track = entry.value;
                                              final isCurrent = activeAudioId == track.id;
                                              final label = _trackLabel(track.title, track.language, entry.key, 'Audio');
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
                                                ...() {
                                                  final rawSelectable = subtitleTracks.where((sub) => sub.id != 'auto' && sub.id != 'no').toList();
                                                  final displayedNativeTracks = <SubtitleTrack>[];
                                                  final seenTrackKeys = <String>{};
                                                  for (final sub in rawSelectable) {
                                                    final key = '${sub.title?.trim()}|${sub.language?.trim()}';
                                                    if (seenTrackKeys.add(key)) {
                                                      displayedNativeTracks.add(sub);
                                                    }
                                                  }

                                                  final externalSubs = <StreamSubtitleTrack>[];
                                                  if (_streamResult != null && _streamResult!.subtitles.isNotEmpty) {
                                                    for (final s in _streamResult!.subtitles) {
                                                      final sLang = s.lang.trim().toLowerCase();
                                                      final alreadyLoaded = displayedNativeTracks.any((t) {
                                                        final tTitle = (t.title ?? '').trim().toLowerCase();
                                                        final tLang = (t.language ?? '').trim().toLowerCase();
                                                        return (sLang.isNotEmpty && (tTitle == sLang || tLang == sLang)) ||
                                                               (s.url.isNotEmpty && (tTitle.contains(s.url) || s.url.endsWith(tTitle)));
                                                      });
                                                      if (!alreadyLoaded) {
                                                        externalSubs.add(s);
                                                      }
                                                    }
                                                  }

                                                  return [
                                                    ...externalSubs.map((sub) {
                                                      final isCurrent = activeSubtitleId == sub.url || 
                                                          (tempSubtitleTrackId == null && (currentSubtitleTrack.title?.toLowerCase() == sub.lang.toLowerCase() || 
                                                          currentSubtitleTrack.id.contains(sub.url)));
                                                      return ListTile(
                                                        contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
                                                        title: Text(sub.lang.isNotEmpty ? sub.lang : 'Default Subtitle', style: TextStyle(color: isCurrent ? Theme.of(context).primaryColor : Colors.white)),
                                                        trailing: isCurrent ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                        onTap: () async {
                                                          tempSubtitleTrackId = sub.url;
                                                          _player.setSubtitleTrack(SubtitleTrack.uri(sub.url, title: sub.lang.isNotEmpty ? sub.lang : 'Default Subtitle'));
                                                          await _updateLocalHistoryPreference(subtitleTrack: sub.lang);
                                                          setDialogState(() {});
                                                        },
                                                      );
                                                    }),
                                                    ...displayedNativeTracks.asMap().entries.map((entry) {
                                                      final sub = entry.value;
                                                      final isCurrent = activeSubtitleId == sub.id ||
                                                          (tempSubtitleTrackId == null && currentSubtitleTrack.id == sub.id) ||
                                                          (rawSelectable.any((raw) => raw.id == activeSubtitleId && raw.title == sub.title && raw.language == sub.language));
                                                      final label = _trackLabel(sub.title, sub.language, entry.key, 'Subtitle');
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
                                                  ];
                                                }(),
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
                                                        final baseScale = entry.value / 18.0;
                                                        final scale = _isPipMode ? (baseScale * 0.45) : baseScale;
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
    // No tooltips anywhere in the player. Every Tooltip builds an OverlayPortal,
    // and OverlayPortal semantics corrupt the accessibility tree when nearby
    // siblings change (snackbar hiding, mini-player handoff) — flutter#189902,
    // fix pending in flutter#190431. In debug that asserted every frame, which
    // blocked disposal of popped player screens. With visibility off, Tooltip
    // returns its child directly and no OverlayPortal is created.
    return TooltipVisibility(
      visible: false,
      child: _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final isPip = _isPipMode ||
        (Platform.isAndroid && screenSize.width < 500 && screenSize.height < 400);

    if (isPip) {
      return ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: _buildDirectStreamLayout(isPortrait, isPipMode: true),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        debugPrint('🔵 [POP_SCOPE] onPopInvokedWithResult — didPop=$didPop, mounted=$mounted');
        if (!didPop) {
          // TV remote Back first hides the on-screen controls, like other
          // TV players (the on-screen back arrow exits straight away).
          if (_controlsKey.currentState?.hideControlsForBack() == true) return;
          _handleBackNavigation();
        }
      },
      child: GestureDetector(
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          // Player-local messenger: snackbars shown here never touch the
          // app-root messenger (which also drives the home Scaffold), and a
          // PlayerScreen that lingers after pop can't poison later snackbars.
          child: ScaffoldMessenger(
            key: _messengerKey,
            child: Scaffold(
              backgroundColor: Colors.black,
              extendBodyBehindAppBar: false,
              appBar: null,
              body: _buildPlayerBody(isPortrait),
            ),
          ),
        ),
      ),
    );
  }

  
  Timer? _webViewControlsTimer;

  // ignore: unused_element
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
                    appDebugLog(
                      '❌ [CW_DEBUG] PlayerScreen#$_sid WebView provider[$_currentProviderIndex/$_maxProviders] '
                      'failed: $errorMessage — native player=${_hash(_player)} '
                      'playing=${_player.state.playing} (if true, audio you hear is NOT from this WebView)',
                    );
                    if (_hasNextProvider) {
                      setState(() {
                        _advanceProvider();
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
                  onEnterFullscreen: () async {
                    _setFullscreenTopBarVisibility(true);
                    await setWindowFullScreen(true);
                  },
                  onExitFullscreen: () async {
                    _setFullscreenTopBarVisibility(false);
                    await setWindowFullScreen(false);
                  },
                  onShowEpisodesRequested: () {
                    _showEpisodesBottomSheet();
                  },
                ),
              ),
            ),
            // Back / exit button (always visible)
            Positioned(
              top: 12,
              left: 12,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: _handleBackNavigation,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back, color: Colors.white, size: 22),
                  ),
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
                      child: SkipIntroButton(
                        onTap: _skipIntro,
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
                      child: _PlayerHoverScale(
                        child: Material(
                          color: Colors.transparent,
                          child: FocusableInkWell(
                          style: DpadFocusStyle.lift,
                          requestFocusOnMount: AppPlatform.isTv,
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
    debugPrint('🟣 [TOPBAR_EXIT] CALLED — _isInFullscreen=$_isInFullscreen, _isDirectStream=$_isDirectStream, mounted=$mounted');
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
    try {
      _fullscreenTopBarOverlayEntry?.remove();
    } catch (e) {
      appDebugLog('🔴 [DISPOSE] _removeFullscreenTopBarOverlayEntry failed: $e');
    }
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

  // ── OverlayEntry management ─────────────────────────────────────
  void _showOverlayEntry() {
    _removeOverlayEntry();
    _nextEpOverlayEntry = OverlayEntry(
      builder: (_) => _NextEpisodeOverlayWidget(
        notifier: _nextEpNotifier,
        episode: _currentEpisode,
        season: widget.season,
        seasonData: _currentSeasonData,
        fillerData: _fillerData,
        autoSkipFiller: ref.read(autoSkipFillerProvider) && _isAnimeMedia(ref.read(selectedMediaProvider)),
        // Binge Mode: only offered while streaming a torrent.
        isTorrent: _currentProvider == 'Nivio Torrents',
        bingeMode: _bingeMode,
        bingeGroup: _bingeGroup,
        onToggleBinge: () => _toggleBingeMode(),
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
    try {
      _nextEpOverlayEntry?.remove();
    } catch (e) {
      appDebugLog('🔴 [DISPOSE] _removeOverlayEntry failed: $e');
    }
    _nextEpOverlayEntry = null;
  }

  void _removeTrackingPromptOverlay() {
    try {
      _trackingPromptOverlayEntry?.remove();
    } catch (e) {
      appDebugLog('🔴 [DISPOSE] _removeTrackingPromptOverlay failed: $e');
    }
    _trackingPromptOverlayEntry = null;
  }

  Future<void> _checkAndPromptTrackingIfNeeded() async {
    if (_trackingPromptDismissed) return;
    if (!mounted) return;

    final media = ref.read(selectedMediaProvider);
    if (!_isAnimeMedia(media) || media == null) return;

    // Check if user set untracked behavior to 'prompt'
    final behavior = ref.read(untrackedAnimeBehaviorProvider);
    if (behavior != UntrackedAnimeBehavior.prompt) return;

    // Check if any tracking account is connected
    if (!AnimeTrackingCoordinator.instance.hasAnyAccountConnected) return;

    // Check if already in user's Nivio watchlist
    final watchlistService = ref.read(watchlistServiceProvider);
    final isAlreadyTracked = watchlistService.isInWatchlist(widget.mediaId);
    if (isAlreadyTracked) return;

    _showTrackingPromptOverlay(media);
  }

  void _showTrackingPromptOverlay(SearchResult media) {
    if (!mounted || _trackingPromptDismissed || _trackingPromptOverlayEntry != null) return;

    _trackingPromptOverlayEntry = OverlayEntry(
      builder: (ctx) => _AnimeTrackingPromptOverlay(
        mediaTitle: media.title ?? media.name ?? 'Anime',
        currentEpisode: _currentEpisode,
        onTrack: () async {
          _removeTrackingPromptOverlay();
          _trackingPromptDismissed = true;

          final watchlistService = ref.read(watchlistServiceProvider);
          final watchItem = WatchlistItem(
            id: widget.mediaId,
            title: media.title ?? media.name ?? 'Unknown',
            posterPath: media.posterPath ?? media.backdropPath,
            mediaType: 'anime',
            addedAt: DateTime.now(),
            voteAverage: media.voteAverage,
            releaseDate: media.releaseDate ?? media.firstAirDate,
            overview: media.overview,
            watchStatus: WatchStatus.watching,
            currentEpisode: _currentEpisode,
            anilistId: media.id,
            malId: media.malId ?? _resolvedMalId,
          );

          await watchlistService.addToWatchlist(watchItem, status: WatchStatus.watching);
          ref.read(watchlistRefreshProvider.notifier).refresh();

          unawaited(
            AnimeTrackingCoordinator.instance.syncWatchStatus(
              anilistId: media.id,
              malId: media.malId ?? _resolvedMalId,
              status: WatchStatus.watching,
              episode: _currentEpisode,
            ),
          );

          if (mounted) {
            _messenger.showSnackBar(
              SnackBar(
                content: Text('Added "${media.title ?? media.name}" to Watching!'),
                backgroundColor: NivioTheme.accentColorOf(context),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
        onDismiss: () {
          _removeTrackingPromptOverlay();
          _trackingPromptDismissed = true;
        },
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_trackingPromptOverlayEntry!);
  }

  // ── Loading state ───────────────────────────────────────────────
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
          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: _PlayerHoverScale(
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                onPressed: _handleBackNavigation,
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

  // ── Error state ─────────────────────────────────────────────────
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
                    _runningFetchers = null;
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

  // ── WebView player (embed fallback) ─────────────────────────────

  // ── BetterPlayer widget ─────────────────────────────────────────
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

    // When _videoDetached is true, the Video widget is removed from the tree
    // to release the native rendering surface before the mini player overlay
    // creates its own Video widget with the same controller. This prevents a
    // native DirectX crash on Windows caused by two Video widgets sharing the
    // same VideoController simultaneously.
    final screenSize = MediaQuery.sizeOf(context);
    final isEffectivePip = isPipMode ||
        (Platform.isAndroid && screenSize.width < 500 && screenSize.height < 400);

    // Ambient mode (Android phones only): a glow fills the letterbox bars.
    // Desktop, TV, PiP, "Fit Screen" and the mini-player handoff keep the
    // plain black bars.
    final ambient = Platform.isAndroid &&
        !AppPlatform.isTv &&
        !isEffectivePip &&
        !_videoDetached &&
        _selectedDisplayFitKey == 'bestFit' &&
        ref.watch(ambientModeProvider);

    Widget videoWidget = _videoDetached
        ? Container(color: Colors.black)
        : Video(
            controller: _videoController,
            controls: NoVideoControls,
            fit: _displayFitOptions[_selectedDisplayFitKey] ?? BoxFit.cover,
            // Transparent so the ambient glow shows through the bars.
            fill: ambient ? Colors.transparent : Colors.black,
            subtitleViewConfiguration: const SubtitleViewConfiguration(
              visible: false,
            ),
          );
    if (ambient) {
      videoWidget = Stack(
        fit: StackFit.expand,
        children: [
          VideoAmbientBackground(
            player: _player,
            captureKey: _ambientCaptureKey,
          ),
          RepaintBoundary(key: _ambientCaptureKey, child: videoWidget),
        ],
      );
    }

    if (isEffectivePip) {
      final baseFontSize = ref.watch(subtitleFontSizeProvider) * 1.1;
      final pipFontSize = (baseFontSize * 0.45).clamp(8.0, 11.5);
      return RepaintBoundary(
        child: Stack(
          children: [
            videoWidget,
            Positioned(
              left: 8,
              right: 8,
              bottom: 4,
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
                          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                          child: Text(
                            line,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: pipFontSize,
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
          ],
        ),
      );
    }

    final media = ref.read(selectedMediaProvider);
    String title = 'Playing';
    String? subtitle;
    
    if (media != null && (media.mediaType == 'tv' || media.mediaType == 'anime')) {
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
        title = fallback;
      } else {
        title = '$fallback - $episodeName';
      }
      subtitle = null;
    } else {
      title = media?.title ?? media?.name ?? 'Playing';
      subtitle = null;
    }

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
            key: AppPlatform.isTv ? _controlsKey : null,
            controller: _player,
            title: title,
            subtitle: subtitle,
            providerName: _currentProvider,
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

// ─────────────────────────────────────────────────────────────────
// Redesigned Episode Picker with thumbnails and search
// ─────────────────────────────────────────────────────────────────
class _EpisodePickerSheet extends ConsumerStatefulWidget {
  final int mediaId;
  final int currentSeason;
  final int currentEpisode;
  final String? mediaType;
  final String? watchPartyCode;
  final WatchPartyRole? watchPartyRole;
  final int providerIndex;
  final AnimeFillerData? fillerData;
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
    this.fillerData,
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

                              return FocusableTap(
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
                                                  if (widget.fillerData != null &&
                                                      widget.fillerData!.isFiller(episode.episodeNumber))
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 5,
                                                            vertical: 2,
                                                          ),
                                                      margin:
                                                          const EdgeInsets.only(
                                                            right: 6,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.amber
                                                            .withValues(alpha: 0.2),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              3,
                                                            ),
                                                        border: Border.all(
                                                          color: Colors.amber,
                                                          width: 0.8,
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        'FILLER',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.amber,
                                                        ),
                                                      ),
                                                    )
                                                  else if (widget.fillerData != null &&
                                                      widget.fillerData!.isMixed(episode.episodeNumber))
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 5,
                                                            vertical: 2,
                                                          ),
                                                      margin:
                                                          const EdgeInsets.only(
                                                            right: 6,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.lightBlue
                                                            .withValues(alpha: 0.2),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              3,
                                                            ),
                                                        border: Border.all(
                                                          color: Colors.lightBlue,
                                                          width: 0.8,
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        'MIXED',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.lightBlue,
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

// ── Helper class for next episode overlay state ──
class _NextEpState {
  final bool show;
  final int? countdown;

  const _NextEpState({required this.show, required this.countdown});
}

// ── Netflix-style loading spinner ──
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

// ── Separate widget for the OverlayEntry (renders above everything) ──
class _NextEpisodeOverlayWidget extends StatelessWidget {
  final ValueNotifier<_NextEpState> notifier;
  final int episode;
  final int season;
  final SeasonData? seasonData;
  final AnimeFillerData? fillerData;
  final bool autoSkipFiller;
  final bool isTorrent;
  final bool bingeMode;
  final String? bingeGroup;
  final VoidCallback onToggleBinge;
  final VoidCallback onPlay;
  final VoidCallback onDismiss;

  const _NextEpisodeOverlayWidget({
    required this.notifier,
    required this.episode,
    required this.season,
    required this.seasonData,
    this.fillerData,
    this.autoSkipFiller = false,
    this.isTorrent = false,
    this.bingeMode = false,
    this.bingeGroup,
    required this.onToggleBinge,
    required this.onPlay,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_NextEpState>(
      valueListenable: notifier,
      builder: (context, state, _) {
        if (!state.show) return const SizedBox.shrink();

        int nextEpNum = episode + 1;
        if (autoSkipFiller && fillerData != null && fillerData!.fillerEpisodes.isNotEmpty) {
          final maxEp = seasonData?.episodes.length ?? 99999;
          while (fillerData!.isFiller(nextEpNum) && nextEpNum <= maxEp) {
            nextEpNum++;
          }
        }

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
                          Row(
                            children: [
                              Text(
                                bingeMode ? 'BINGE · UP NEXT' : 'UP NEXT',
                                style: TextStyle(
                                  color: bingeMode
                                      ? const Color(0xFF4ADE80)
                                      : Colors.grey,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const Spacer(),
                              if (isTorrent)
                                _BingeModeToggleButton(
                                  bingeMode: bingeMode,
                                  onToggle: onToggleBinge,
                                ),
                            ],
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
                            bingeMode
                                ? 'S$season E$nextEpNum · ${(bingeGroup != null && bingeGroup!.isNotEmpty) ? 'Same group ($bingeGroup)' : 'No picker — auto-playing'}'
                                : 'S$season E$nextEpNum${nextEpNum > episode + 1 ? ' (Skipping filler)' : ''}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
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

class _BingeModeToggleButton extends StatefulWidget {
  final bool bingeMode;
  final VoidCallback onToggle;

  const _BingeModeToggleButton({
    required this.bingeMode,
    required this.onToggle,
  });

  @override
  State<_BingeModeToggleButton> createState() => _BingeModeToggleButtonState();
}

class _BingeModeToggleButtonState extends State<_BingeModeToggleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.bingeMode;
    const green = Color(0xFF4ADE80);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _isHovered ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onToggle,
              borderRadius: BorderRadius.circular(20),
              splashColor: active
                  ? green.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.15),
              highlightColor: active
                  ? green.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.08),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: active
                      ? green.withValues(alpha: _isHovered ? 0.28 : 0.20)
                      : Colors.white.withValues(alpha: _isHovered ? 0.14 : 0.07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active
                        ? green
                        : Colors.white.withValues(alpha: _isHovered ? 0.40 : 0.22),
                    width: active ? 1.2 : 1.0,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: green.withValues(alpha: _isHovered ? 0.45 : 0.25),
                            blurRadius: _isHovered ? 12 : 8,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : (_isHovered
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (active) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: green,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: green,
                              blurRadius: 5,
                              spreadRadius: 0.5,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Icon(
                      Icons.all_inclusive_rounded,
                      size: 14,
                      color: active ? green : (_isHovered ? Colors.white : Colors.white70),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      active ? 'Binge ON' : 'Binge Mode',
                      style: TextStyle(
                        color: active ? green : (_isHovered ? Colors.white : Colors.white70),
                        fontSize: 11.5,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

class _PlayerHoverScale extends StatefulWidget {
  final Widget child;
  const _PlayerHoverScale({required this.child});

  @override
  State<_PlayerHoverScale> createState() => _PlayerHoverScaleState();
}

class _PlayerHoverScaleState extends State<_PlayerHoverScale> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _isHovered ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class SkipIntroButton extends StatefulWidget {
  final VoidCallback onTap;
  const SkipIntroButton({super.key, required this.onTap});

  @override
  State<SkipIntroButton> createState() => _SkipIntroButtonState();
}

class _SkipIntroButtonState extends State<SkipIntroButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = NivioTheme.accentColorOf(context);
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: FocusableTap(
        requestFocusOnMount: AppPlatform.isTv,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: _isHovered ? 26 : 22, 
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? accentColor : Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? accentColor.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.3),
                blurRadius: _isHovered ? 16 : 8,
                spreadRadius: _isHovered ? 2 : 0,
                offset: Offset(0, _isHovered ? 4 : 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.skip_next_rounded, 
                color: _isHovered ? Colors.white : Colors.black87, 
                size: 22,
              ),
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  color: _isHovered ? Colors.white : Colors.black87,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: _isHovered ? 1.0 : 0.5,
                ),
                child: const Text('Skip Intro'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimeTrackingPromptOverlay extends StatefulWidget {
  final String mediaTitle;
  final int currentEpisode;
  final VoidCallback onTrack;
  final VoidCallback onDismiss;

  const _AnimeTrackingPromptOverlay({
    required this.mediaTitle,
    required this.currentEpisode,
    required this.onTrack,
    required this.onDismiss,
  });

  @override
  State<_AnimeTrackingPromptOverlay> createState() => _AnimeTrackingPromptOverlayState();
}

class _AnimeTrackingPromptOverlayState extends State<_AnimeTrackingPromptOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _animController.forward();

    // Auto dismiss after 10 seconds if untouched
    _autoDismissTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        _dismissWithAnimation();
      }
    });
  }

  void _dismissWithAnimation() {
    _autoDismissTimer?.cancel();
    _animController.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = NivioTheme.accentColorOf(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 24.0, right: 24.0),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xF2181824),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            AniListLogo(size: 14),
                            SizedBox(width: 4),
                            MalLogo(size: 14),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Track Anime?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Track "${widget.mediaTitle}" (Ep ${widget.currentEpisode}) as Watching?',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () {
                          _autoDismissTimer?.cancel();
                          widget.onTrack();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Track',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: _dismissWithAnimation,
                        icon: Icon(Icons.close_rounded, size: 18, color: Colors.white.withOpacity(0.6)),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        splashRadius: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

