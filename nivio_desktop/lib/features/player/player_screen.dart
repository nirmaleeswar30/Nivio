import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../shared/theme/index.dart';
import '../../core/interfaces/watch_history_repository.dart';
import '../../core/network/image/tmdb_image_builder.dart';
import '../../shared/models/watch_party_models.dart';
import '../../shared/models/skip_times_models.dart';
import '../../shared/models/stream_result.dart' as stream_models;
import 'adaptive_playback_engine.dart';
import 'media_kit_playback_engine.dart';
import 'models/playback_request.dart';
import 'models/playback_state.dart';
import 'playback_engine.dart';
import 'playback_surface.dart';
import 'player_controller.dart';
import 'web_playback_engine.dart';
import '../party/services/watch_party_service_supabase.dart';
import '../party/services/watch_party_session_manager.dart';
import 'services/m3u8_parser.dart';
import 'services/playback_runtime_diagnostics.dart';
import 'services/skip_times_service.dart';
import 'services/stream_resolver.dart';

part 'player_gesture_layer.dart';
part 'player_drawer.dart';
part 'player_overlay_widgets.dart';
part 'player_settings_overlay.dart';
part 'watch_party_status_overlay.dart';

part 'android_player_controls.dart';
part 'embedded_web_controls.dart';

typedef PlaybackSurfaceBuilder =
    Widget Function(BuildContext context, PlaybackEngine engine);

/// Foundation player surface. Stream resolution and application routing are
/// intentionally introduced in Phase 22.2.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.request,
    this.engine,
    this.surfaceBuilder,
    this.onClose,
    this.onMinimize,
    this.onNextEpisode,
    this.onSourceSwitch,
    this.sourceOptions = const [],
    this.watchHistoryRepository,
  });

  final PlaybackRequest request;
  final PlaybackEngine? engine;
  final PlaybackSurfaceBuilder? surfaceBuilder;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final ValueChanged<PlaybackRequest>? onNextEpisode;
  final ValueChanged<PlaybackRequest>? onSourceSwitch;
  final List<PlaybackSourceOption> sourceOptions;
  final WatchHistoryRepository? watchHistoryRepository;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static int _nextInstanceId = 0;
  static const _autoplayKey = 'autoplay_next_episode';
  static const _videoDebandingKey = 'video_debanding';
  static const _subtitleFontSizeKey = 'subtitle_font_size';
  static const _subtitleBackgroundKey = 'subtitle_background';
  static const _subtitleOutlineKey = 'subtitle_outline';
  static const _subtitleDelayPrefix = 'subtitle_delay_';
  static const _defaultSubtitleFontSize = 18.0;

  final int _instanceId = ++_nextInstanceId;
  final FocusNode _videoControlsFocusNode = FocusNode(
    debugLabel: 'Nivio video controls',
  );
  Future<void> Function()? _toggleNativeFullscreen;
  late final bool _ownsEngine = widget.engine == null;
  late final PlaybackEngine _engine =
      widget.engine ??
      AdaptivePlaybackEngine(
        webFactory: () => WebPlaybackEngine(
          onPointerActivity: _showControlsFromPlaybackSurface,
          onBackRequested: _close,
          onServerRequested: _openWebServerDrawer,
          onEpisodesRequested: _initialEpisodeSelectorCallback,
        ),
      );
  late final DesktopPlayerController _controller = DesktopPlayerController(
    engine: _engine,
    request: widget.request,
    watchHistoryRepository: widget.watchHistoryRepository,
  );
  late final DesktopSkipTimesService _skipTimesService =
      DesktopSkipTimesService();
  final List<_QualityOption> _qualityOptions = [];
  List<SkipTime> _fetchedSkipTimes = const [];
  String? _skipTimesRequestKey;
  bool _qualityDiscoveryComplete = false;
  bool _autoplayNextEpisode = true;
  bool _nextEpisodeStarted = false;
  bool _preferredQualityApplied = false;
  Duration _subtitleDelay = Duration.zero;
  bool _controlsVisible = true;
  bool _closeInFlight = false;
  bool _debandingEnabled = false;
  bool _sourceSwitchInFlight = false;
  bool _watchPartyPanelExpanded = false;
  String? _sourceSwitchMessage;
  bool _isNativeFullscreenActive = false;
  String _subtitleBackground = 'Transparent';
  String _subtitleOutline = 'Outline';
  bool _subtitleBackgroundEnabled = false;
  bool _subtitleOutlineEnabled = false;
  double _subtitleScale = 1;
  BoxFit _displayFit = BoxFit.contain;
  _PlayerDrawer _drawer = _PlayerDrawer.none;
  _WebOverlayDrawer _webDrawer = _WebOverlayDrawer.none;
  int _webOverlayGeneration = 0;
  Timer? _hideControlsTimer;
  Timer? _volumeOverlayTimer;
  Timer? _embeddedProviderFallbackTimer;
  Timer? _watchPartyHostSyncTimer;
  int? _handledEmbeddedErrorProviderIndex;
  double? _volumeOverlayValue;
  WatchPartyServiceSupabase? _watchPartyService;
  WatchPartySession? _watchPartySession;
  WatchPartyPlaybackState? _pendingWatchPartyPlayback;
  StreamSubscription<WatchPartyPlaybackState>? _watchPartyPlaybackSub;
  StreamSubscription<WatchPartySession?>? _watchPartySessionSub;
  StreamSubscription<WatchPartyChatMessage>? _watchPartyChatSub;
  StreamSubscription<WatchPartyReaction>? _watchPartyReactionSub;
  StreamSubscription<String>? _watchPartyErrorSub;
  DateTime? _lastWatchPartyBroadcastAt;
  String? _lastEmbeddedLayoutSnapshotKey;
  bool _isApplyingWatchPartyState = false;
  bool _isPartyRouteSyncInFlight = false;
  String? _watchPartyStatusMessage;
  Rect? _embeddedTopBarRect;
  Rect? _embeddedSurfaceRect;
  final List<WatchPartyChatMessage> _watchPartyMessages = [];
  final List<WatchPartyReaction> _watchPartyReactions = [];

  static const Duration _watchPartyProgressInterval = Duration(
    milliseconds: 1800,
  );
  static const Duration _watchPartyPeriodicSyncInterval = Duration(seconds: 3);
  static const int _watchPartyDriftThresholdMs = 1200;

  @override
  void initState() {
    super.initState();
    _configureEmbeddedWebAppControls();
    PlaybackRuntimeDiagnostics.playerScreensCreated++;
    PlaybackRuntimeDiagnostics.uiLog(
      'PlayerScreen#$_instanceId init mounted=$mounted '
      'ownsEngine=$_ownsEngine request=${widget.request.mediaId} '
      'type=${widget.request.mediaTypeName} '
      '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
    );
    _qualityOptions.addAll(_qualityOptionsFromResult(widget.request));
    unawaited(_loadSavedPlayerPreferences());
    unawaited(_initializeController());
    unawaited(_loadExternalSkipTimes(widget.request));
    unawaited(_discoverHlsQualities());
    unawaited(_initializeWatchParty());
    unawaited(_setPlaybackWakelock(enabled: true));
    _engine.state.addListener(_onPlaybackChanged);
    _scheduleControlsHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestPlayerKeyboardFocus();
    });
  }

  void _configureEmbeddedWebAppControls() {
    final onEpisodes = _episodeSelectorCallback;
    final sourceOptions = widget.sourceOptions
        .map(
          (option) => <String, Object?>{
            'index': option.index,
            'provider': option.provider,
            'server': option.server,
            'group': option.group,
            'label': option.label,
            'selected': option.index == _controller.request.providerIndex,
          },
        )
        .toList(growable: false);
    final engine = _engine;
    if (engine is AdaptivePlaybackEngine) {
      engine.configureWebAppControls(
        onPointerActivity: _showControlsFromPlaybackSurface,
        onBackRequested: _close,
        onServerRequested: _openWebServerDrawer,
        onEpisodesRequested: onEpisodes,
        onSourceIndexRequested: _selectEmbeddedWebSourceByIndex,
        sourceOptions: sourceOptions,
        selectedSourceIndex: _controller.request.providerIndex,
        providerLabel: _providerLabel,
        serverLabel: _serverLabel ?? widget.request.streamResult?.providerGroup,
      );
    } else if (engine is WebPlaybackEngine) {
      engine.configureAppControls(
        onPointerActivity: _showControlsFromPlaybackSurface,
        onBackRequested: _close,
        onServerRequested: _openWebServerDrawer,
        onEpisodesRequested: onEpisodes,
        onSourceIndexRequested: _selectEmbeddedWebSourceByIndex,
        sourceOptions: sourceOptions,
        selectedSourceIndex: _controller.request.providerIndex,
        providerLabel: _providerLabel,
        serverLabel: _serverLabel ?? widget.request.streamResult?.providerGroup,
      );
    }
  }

  Future<void> _loadSavedPlayerPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final subtitleFontSize =
        prefs.getDouble(_subtitleFontSizeKey) ?? _defaultSubtitleFontSize;
    final subtitleBackground =
        prefs.getString(_subtitleBackgroundKey) ?? 'Transparent';
    final subtitleOutline = prefs.getString(_subtitleOutlineKey) ?? 'Outline';
    final subtitleDelayMs = prefs.getInt(_subtitleDelayPreferenceKey) ?? 0;

    final nextScale = _subtitleScaleFromFontSize(subtitleFontSize);
    final nextBackground = subtitleBackground != 'Transparent';
    final nextOutline = subtitleOutline != 'None';
    final nextDebanding = prefs.getBool(_videoDebandingKey) ?? false;
    final nextAutoplay = prefs.getBool(_autoplayKey) ?? true;
    final nextDelay = Duration(milliseconds: subtitleDelayMs);

    if (!mounted) return;
    setState(() {
      _subtitleScale = nextScale;
      _subtitleBackground = subtitleBackground;
      _subtitleOutline = subtitleOutline;
      _subtitleBackgroundEnabled = nextBackground;
      _subtitleOutlineEnabled = nextOutline;
      _subtitleDelay = nextDelay;
      _debandingEnabled = nextDebanding;
      _autoplayNextEpisode = nextAutoplay;
    });

    unawaited(_controller.setSubtitleDelay(nextDelay));
    unawaited(
      _controller.setSubtitleStyle(
        SubtitleStyle(
          scale: nextScale,
          background: nextBackground,
          outline: nextOutline,
        ),
      ),
    );
    unawaited(_controller.setDebanding(nextDebanding));
  }

  Future<void> _saveSubtitleDelay() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _subtitleDelayPreferenceKey,
      _subtitleDelay.inMilliseconds,
    );
  }

  Future<void> _saveSubtitleStyle({
    double? scale,
    String? background,
    String? outline,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (scale != null) {
      await prefs.setDouble(
        _subtitleFontSizeKey,
        _subtitleFontSizeFromScale(scale),
      );
    }
    if (background != null) {
      await prefs.setString(_subtitleBackgroundKey, background);
    }
    if (outline != null) {
      await prefs.setString(_subtitleOutlineKey, outline);
    }
  }

  Future<void> _saveDebanding(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_videoDebandingKey, enabled);
  }

  Future<void> _saveAutoplay(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoplayKey, enabled);
  }

  String get _subtitleDelayPreferenceKey {
    final id =
        widget.request.numericMediaId?.toString() ?? widget.request.mediaId;
    final season = widget.request.season ?? 0;
    final episode = widget.request.episode ?? 0;
    return '$_subtitleDelayPrefix'
        '${widget.request.mediaTypeName}_${_preferencePart(id)}_s${season}_e$episode';
  }

  String _preferencePart(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }

  double _subtitleScaleFromFontSize(double fontSize) {
    if (fontSize <= 14) return 0.75;
    if (fontSize <= 18) return 1.0;
    if (fontSize <= 24) return 1.25;
    return 1.5;
  }

  double _subtitleFontSizeFromScale(double scale) {
    if (scale <= 0.875) return 14.0;
    if (scale <= 1.125) return 18.0;
    if (scale <= 1.375) return 24.0;
    return 30.0;
  }

  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configureEmbeddedWebAppControls();
    final wasEmbeddedWeb = _requestUsesEmbeddedWebPlayback(oldWidget.request);
    final isEmbeddedWeb = _requestUsesEmbeddedWebPlayback(widget.request);
    PlaybackRuntimeDiagnostics.uiLog(
      'PlayerScreen didUpdateWidget mounted=$mounted '
      'sameRequest=${_samePlaybackRequest(oldWidget.request, widget.request)} '
      'oldProvider=${oldWidget.request.providerIndex ?? 'auto'} '
      'newProvider=${widget.request.providerIndex ?? 'auto'} '
      'wasEmbeddedWeb=$wasEmbeddedWeb isEmbeddedWeb=$isEmbeddedWeb '
      'iframeControls=androidContract',
    );
    if (_samePlaybackRequest(oldWidget.request, widget.request)) return;

    if (isEmbeddedWeb) {
      _destroySharedOverlayForWebTransition(
        reason: wasEmbeddedWeb
            ? 'WebView -> WebView request transition'
            : 'MediaKit -> WebView request transition',
      );
    } else if (wasEmbeddedWeb && !isEmbeddedWeb) {
      _destroySharedOverlayForWebTransition(
        reason: 'WebView -> MediaKit request transition',
      );
    }

    _sourceSwitchInFlight = false;
    _isPartyRouteSyncInFlight = false;
    _handledEmbeddedErrorProviderIndex = null;
    _embeddedProviderFallbackTimer?.cancel();
    _nextEpisodeStarted = false;
    _preferredQualityApplied = false;
    _qualityDiscoveryComplete = false;
    _qualityOptions
      ..clear()
      ..addAll(_qualityOptionsFromResult(widget.request));
    _fetchedSkipTimes = const [];

    unawaited(_loadSavedPlayerPreferences());
    unawaited(_loadUpdatedRequest(widget.request));
    unawaited(_loadExternalSkipTimes(widget.request));
    unawaited(_discoverHlsQualities());
  }

  bool _samePlaybackRequest(PlaybackRequest a, PlaybackRequest b) {
    return a.mediaId == b.mediaId &&
        a.mediaType == b.mediaType &&
        a.season == b.season &&
        a.episode == b.episode &&
        a.totalSeasons == b.totalSeasons &&
        a.totalEpisodes == b.totalEpisodes &&
        a.providerIndex == b.providerIndex &&
        a.preferredQuality == b.preferredQuality &&
        a.preferredAudioTrack == b.preferredAudioTrack &&
        a.preferredSubtitleTrack == b.preferredSubtitleTrack &&
        a.source == b.source &&
        a.streamResult?.url == b.streamResult?.url;
  }

  Future<void> _initializeController() async {
    await _controller.initialize();
    if (!mounted || _controller.debugDisposed) return;
    unawaited(_applyCurrentPlaybackPreferences());
    _applyPreferredQuality();
    if (_pendingWatchPartyPlayback != null) {
      final pending = _pendingWatchPartyPlayback!;
      _pendingWatchPartyPlayback = null;
      unawaited(_applyWatchPartyPlayback(pending));
    }
    unawaited(_broadcastWatchPartyPlayback(force: true));
  }

  Future<void> _loadUpdatedRequest(PlaybackRequest request) async {
    await _controller.loadRequest(request);
    if (!mounted || !_samePlaybackRequest(widget.request, request)) return;
    unawaited(_applyCurrentPlaybackPreferences());
    _applyPreferredQuality();
    unawaited(_broadcastWatchPartyPlayback(force: true));
  }

  Future<void> _applyCurrentPlaybackPreferences() async {
    await _controller.setSubtitleDelay(_subtitleDelay);
    await _controller.setSubtitleStyle(
      SubtitleStyle(
        scale: _subtitleScale,
        background: _subtitleBackgroundEnabled,
        outline: _subtitleOutlineEnabled,
      ),
    );
    await _controller.setDebanding(_debandingEnabled);
  }

  List<SkipTime> get _effectiveSkipTimes {
    final providerSkipTimes =
        widget.request.streamResult?.skipTimes ?? const [];
    return providerSkipTimes.isNotEmpty ? providerSkipTimes : _fetchedSkipTimes;
  }

  Future<void> _loadExternalSkipTimes(PlaybackRequest request) async {
    final providerSkipTimes = request.streamResult?.skipTimes ?? const [];
    if (providerSkipTimes.isNotEmpty) {
      _skipTimesRequestKey = null;
      if (mounted && _fetchedSkipTimes.isNotEmpty) {
        setState(() => _fetchedSkipTimes = const []);
      }
      return;
    }

    final episode = request.episode;
    final canFetch =
        !request.isLive &&
        episode != null &&
        episode > 0 &&
        (request.mediaType == PlaybackMediaType.anime ||
            request.mediaType == PlaybackMediaType.tv);
    if (!canFetch) {
      _skipTimesRequestKey = null;
      if (mounted && _fetchedSkipTimes.isNotEmpty) {
        setState(() => _fetchedSkipTimes = const []);
      }
      return;
    }

    final key = [
      request.mediaTypeName,
      request.mediaId,
      request.season ?? 0,
      episode,
    ].join(':');
    _skipTimesRequestKey = key;
    final skipTimes = await _skipTimesService.getSkipTimes(request);
    if (!mounted || _skipTimesRequestKey != key) return;
    setState(() => _fetchedSkipTimes = skipTimes);
  }

  Future<void> _initializeWatchParty() async {
    if (!_hasWatchPartyContext) return;

    final service = await WatchPartySessionManager.instance.ensureService();
    if (!mounted || service == null) {
      _showWatchPartyStatus('Watch Party unavailable.');
      return;
    }

    _watchPartyService = service;
    _watchPartyPlaybackSub ??= service.playbackStream.listen((playback) {
      unawaited(_applyWatchPartyPlayback(playback));
    });
    _watchPartySessionSub ??= service.sessionStream.listen((session) {
      if (!mounted) return;
      setState(() => _watchPartySession = session);
      _updateWatchPartyHostSyncTimer();
    });
    _watchPartyChatSub ??= service.chatStream.listen((message) {
      if (!mounted) return;
      setState(() {
        _watchPartyMessages.add(message);
        if (_watchPartyMessages.length > 8) _watchPartyMessages.removeAt(0);
      });
    });
    _watchPartyReactionSub ??= service.reactionStream.listen((reaction) {
      if (!mounted) return;
      setState(() {
        _watchPartyReactions.add(reaction);
        if (_watchPartyReactions.length > 8) {
          _watchPartyReactions.removeAt(0);
        }
      });
    });
    _watchPartyErrorSub ??= service.errorStream.listen((message) {
      if (!mounted || message.trim().isEmpty) return;
      _showWatchPartyStatus(message.trim());
    });

    final role = _resolvedWatchPartyRole;
    final code = _resolvedWatchPartyCode;
    if (role == null || code.isEmpty) return;

    final existingCode = service.currentSession?.sessionCode.toUpperCase();
    var ok = true;
    if (existingCode != code) {
      if (role == WatchPartyRole.host) {
        ok = await service.createSession(preferredCode: code) != null;
      } else {
        ok = await service.joinSession(code);
      }
    }

    if (!mounted) return;
    if (!ok) {
      _showWatchPartyStatus('Unable to connect to watch party.');
      return;
    }

    setState(() => _watchPartySession = service.currentSession);
    _updateWatchPartyHostSyncTimer();
    if (service.isHost) {
      _scheduleWatchPartyBootstrapSyncs();
    } else {
      unawaited(service.requestStateSync(reason: 'player_opened'));
    }
  }

  bool get _hasWatchPartyContext {
    return _resolvedWatchPartyCode.isNotEmpty &&
        _resolvedWatchPartyRole != null;
  }

  bool get _hasActiveWatchPartySession =>
      _watchPartyService?.isInSession == true;

  String get _resolvedWatchPartyCode {
    final fromRequest = (widget.request.watchPartyCode ?? '').trim();
    if (fromRequest.isNotEmpty) return fromRequest.toUpperCase();

    final service =
        _watchPartyService ?? WatchPartySessionManager.instance.currentService;
    final fromService = (service?.sessionCode ?? '').trim();
    if (service?.isInSession == true && fromService.isNotEmpty) {
      return fromService.toUpperCase();
    }
    return '';
  }

  WatchPartyRole? get _resolvedWatchPartyRole {
    final fromRequest = WatchPartyRoleX.fromQuery(
      widget.request.watchPartyRole,
    );
    if (fromRequest != null) return fromRequest;

    final service =
        _watchPartyService ?? WatchPartySessionManager.instance.currentService;
    if (service?.isInSession != true) return null;
    return service!.isHost ? WatchPartyRole.host : WatchPartyRole.participant;
  }

  bool get _canControlPartyPlayback {
    final service = _watchPartyService;
    if (!_hasActiveWatchPartySession || service == null) return true;
    return service.canControlPlayback;
  }

  String get _partyConnectionLabel {
    final service = _watchPartyService;
    if (!_hasWatchPartyContext) return '';
    if (service == null) return 'Connecting';
    if (!service.isInSession) return 'Disconnected';
    return 'Connected';
  }

  String get _partyControllerLabel {
    final service = _watchPartyService;
    final session = _watchPartySession;
    if (service == null || session == null) return 'Unknown';
    if (session.controllerId == null || session.controllerId!.isEmpty) {
      return 'Host';
    }
    for (final participant in session.participants) {
      if (participant.id == session.controllerId) return participant.name;
    }
    return 'Delegated';
  }

  void _showWatchPartyStatus(String message) {
    if (!mounted) return;
    setState(() => _watchPartyStatusMessage = message);
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _watchPartyStatusMessage != message) return;
      setState(() => _watchPartyStatusMessage = null);
    });
  }

  bool _ensurePartyCanControl() {
    if (_canControlPartyPlayback) return true;
    _showWatchPartyStatus(
      'Only the host or delegated controller can control playback.',
    );
    return false;
  }

  Future<void> _sendWatchPartyChat(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _watchPartyService?.sendChatMessage(trimmed);
  }

  Future<void> _sendWatchPartyReaction(String emoji) async {
    await _watchPartyService?.sendReaction(emoji);
  }

  Future<void> _leaveOrEndWatchParty() async {
    final service = _watchPartyService;
    if (service == null) return;
    if (service.isHost) {
      await service.endSession();
      _showWatchPartyStatus('Watch party ended');
    } else {
      await service.leaveSession();
      _showWatchPartyStatus('Left watch party');
    }
    if (!mounted) return;
    setState(() {
      _watchPartySession = null;
      _watchPartyPanelExpanded = false;
    });
    _watchPartyHostSyncTimer?.cancel();
    _watchPartyHostSyncTimer = null;
  }

  void _toggleWatchPartyPanel() {
    if (!_hasWatchPartyContext) return;
    setState(() {
      _controlsVisible = true;
      _watchPartyPanelExpanded = !_watchPartyPanelExpanded;
    });
    if (!_watchPartyPanelExpanded) {
      _scheduleControlsHide();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _setWatchPartyPanelExpanded(bool expanded) {
    if (_watchPartyPanelExpanded == expanded) return;
    setState(() => _watchPartyPanelExpanded = expanded);
    if (!expanded) _scheduleControlsHide();
  }

  void _scheduleWatchPartyBootstrapSyncs() {
    if (_watchPartyService?.isInSession != true ||
        _watchPartyService?.canControlPlayback != true) {
      return;
    }
    unawaited(_broadcastWatchPartyPlayback(force: true));
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) unawaited(_broadcastWatchPartyPlayback(force: true));
    });
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) unawaited(_broadcastWatchPartyPlayback(force: true));
    });
  }

  void _updateWatchPartyHostSyncTimer() {
    final service = _watchPartyService;
    final shouldSync =
        service?.isInSession == true && service?.canControlPlayback == true;
    if (!shouldSync) {
      _watchPartyHostSyncTimer?.cancel();
      _watchPartyHostSyncTimer = null;
      return;
    }
    if (_watchPartyHostSyncTimer != null) return;
    _watchPartyHostSyncTimer = Timer.periodic(
      _watchPartyPeriodicSyncInterval,
      (_) => unawaited(_broadcastWatchPartyPlayback(force: true)),
    );
  }

  Future<void> _broadcastWatchPartyPlayback({required bool force}) async {
    final service = _watchPartyService;
    if (service == null ||
        !service.canControlPlayback ||
        _isApplyingWatchPartyState ||
        !service.isInSession) {
      return;
    }

    final state = _engine.state.value;
    if (state.status == PlaybackStatus.idle ||
        state.status == PlaybackStatus.loading ||
        state.status == PlaybackStatus.error) {
      return;
    }

    final now = DateTime.now();
    if (!force &&
        _lastWatchPartyBroadcastAt != null &&
        now.difference(_lastWatchPartyBroadcastAt!) <
            _watchPartyProgressInterval) {
      return;
    }

    final mediaId = _watchPartyMediaId;
    if (mediaId == null) return;

    await service.syncPlayback(
      mediaId: mediaId,
      mediaType: _watchPartyMediaType,
      providerIndex: _controller.request.providerIndex,
      season: _controller.request.season ?? 1,
      episode: _controller.request.episode ?? 1,
      positionMs: state.position.inMilliseconds,
      isPlaying: state.isPlaying,
    );
    _lastWatchPartyBroadcastAt = now;
  }

  int? get _watchPartyMediaId {
    final numeric = _controller.request.numericMediaId;
    if (numeric != null && numeric > 0) return numeric;
    return widget.request.numericMediaId;
  }

  String get _watchPartyMediaType {
    final type = _controller.request.mediaTypeName.trim();
    if (type.isNotEmpty && type != 'unknown') return type;
    return widget.request.mediaTypeName;
  }

  Future<void> _applyWatchPartyPlayback(
    WatchPartyPlaybackState playback,
  ) async {
    final service = _watchPartyService;
    if (!mounted || service == null || playback.hostId == service.userId) {
      return;
    }

    final localMediaId = _watchPartyMediaId;
    final localSeason = _controller.request.season ?? 1;
    final localEpisode = _controller.request.episode ?? 1;
    final localProvider = _controller.request.providerIndex;
    final mediaChanged =
        localMediaId != playback.mediaId ||
        _watchPartyMediaType != playback.mediaType;
    final episodeChanged =
        localSeason != playback.season || localEpisode != playback.episode;
    final providerChanged =
        playback.providerIndex != null &&
        localProvider != playback.providerIndex;

    if (mediaChanged || episodeChanged || providerChanged) {
      _syncRouteToWatchPartyPlayback(playback);
      return;
    }

    final currentState = _engine.state.value;
    if (currentState.duration == Duration.zero &&
        currentState.status == PlaybackStatus.loading) {
      _pendingWatchPartyPlayback = playback;
      return;
    }
    if (_isApplyingWatchPartyState) return;

    _isApplyingWatchPartyState = true;
    try {
      final expectedMs = playback.expectedPositionMs;
      final currentMs = currentState.position.inMilliseconds;
      final driftMs = (currentMs - expectedMs).abs();
      if (driftMs > _watchPartyDriftThresholdMs) {
        await _engine.seek(Duration(milliseconds: math.max(0, expectedMs)));
      }

      final localIsPlaying = _engine.state.value.isPlaying;
      if (playback.isPlaying && !localIsPlaying) {
        await _engine.play();
      } else if (!playback.isPlaying && localIsPlaying) {
        await _engine.pause();
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 350), () {
        _isApplyingWatchPartyState = false;
      });
    }
  }

  void _syncRouteToWatchPartyPlayback(WatchPartyPlaybackState playback) {
    if (_isPartyRouteSyncInFlight || !mounted) return;

    final callback = widget.onSourceSwitch ?? widget.onNextEpisode;
    if (callback == null) {
      _showWatchPartyStatus('Unable to follow watch party playback.');
      return;
    }
    _isPartyRouteSyncInFlight = true;
    unawaited(_controller.stop());
    callback(
      _controller.request.copyWith(
        mediaId: '${playback.mediaType}:${playback.mediaId}',
        title: playback.mediaId == _watchPartyMediaId
            ? _controller.request.title
            : 'Media ${playback.mediaId}',
        mediaType: _playbackMediaTypeFromName(playback.mediaType),
        season: playback.season,
        episode: playback.episode,
        providerIndex: playback.providerIndex,
        watchPartyCode: _resolvedWatchPartyCode,
        watchPartyRole: _resolvedWatchPartyRole?.queryValue,
        startPosition: Duration(milliseconds: playback.expectedPositionMs),
        clearSource: true,
        clearStreamResult: true,
        clearPreferredQuality: true,
      ),
    );
  }

  PlaybackMediaType _playbackMediaTypeFromName(String type) {
    return switch (type.trim().toLowerCase()) {
      'movie' => PlaybackMediaType.movie,
      'tv' => PlaybackMediaType.tv,
      'anime' => PlaybackMediaType.anime,
      'live' || 'livetv' || 'live_tv' => PlaybackMediaType.liveTv,
      _ => PlaybackMediaType.unknown,
    };
  }

  @override
  void dispose() {
    PlaybackRuntimeDiagnostics.uiLog(
      'PlayerScreen#$_instanceId dispose start mounted=$mounted '
      'ownsEngine=$_ownsEngine '
      'controllerDisposed=${_controller.debugDisposed} '
      'engineDisposed=${_engineDisposedLabel()}',
    );
    _engine.state.removeListener(_onPlaybackChanged);
    _hideControlsTimer?.cancel();
    _volumeOverlayTimer?.cancel();
    _embeddedProviderFallbackTimer?.cancel();
    _watchPartyHostSyncTimer?.cancel();
    unawaited(_watchPartyPlaybackSub?.cancel());
    unawaited(_watchPartySessionSub?.cancel());
    unawaited(_watchPartyChatSub?.cancel());
    unawaited(_watchPartyReactionSub?.cancel());
    unawaited(_watchPartyErrorSub?.cancel());
    unawaited(_setPlaybackWakelock(enabled: false));
    _videoControlsFocusNode.dispose();
    if (_ownsEngine) {
      unawaited(_controller.close());
    } else {
      unawaited(_controller.detachUi());
    }
    PlaybackRuntimeDiagnostics.playerScreensDisposed++;
    super.dispose();
    PlaybackRuntimeDiagnostics.uiLog(
      'PlayerScreen#$_instanceId dispose complete '
      '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
    );
  }

  Future<void> _setPlaybackWakelock({required bool enabled}) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (error) {
      PlaybackRuntimeDiagnostics.lifecycleLog(
        'Wakelock ${enabled ? 'enable' : 'disable'} failed: $error',
      );
    }
  }

  void _minimizeToMiniPlayer() {
    widget.onMinimize?.call();
  }

  void _onPlaybackChanged() {
    final state = _engine.state.value;
    unawaited(_broadcastWatchPartyPlayback(force: false));
    if (_pendingWatchPartyPlayback != null &&
        state.status != PlaybackStatus.loading &&
        state.status != PlaybackStatus.idle &&
        state.status != PlaybackStatus.error) {
      final pending = _pendingWatchPartyPlayback!;
      _pendingWatchPartyPlayback = null;
      unawaited(_applyWatchPartyPlayback(pending));
    }
    if (state.status == PlaybackStatus.completed && _autoplayNextEpisode) {
      _startNextEpisode();
      return;
    }
    if (!_autoplayNextEpisode ||
        _nextEpisodeStarted ||
        !_hasNextEpisode ||
        widget.request.isLive ||
        state.duration <= Duration.zero) {
      return;
    }
    final remaining = state.duration - state.position;
    if (remaining <= Duration.zero || remaining > const Duration(seconds: 1)) {
      return;
    }
    _startNextEpisode();
  }

  void _close() {
    if (_closeInFlight) return;
    _closeInFlight = true;
    unawaited(_closeAfterStoppingPlayback());
  }

  Future<void> _closeAfterStoppingPlayback() async {
    await _controller.stop();
    if (!mounted) return;
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      await Navigator.of(context).maybePop();
    }
  }

  void _selectEmbeddedWebSourceByIndex(int index) {
    PlaybackRuntimeDiagnostics.overlayLog(
      'WebView DOM server source requested index=$index '
      'sourceCount=${widget.sourceOptions.length}',
    );
    for (final option in widget.sourceOptions) {
      if (option.index == index) {
        unawaited(_switchSource(option));
        return;
      }
    }
  }

  void _toggleControls() {
    if (_drawer != _PlayerDrawer.none) {
      setState(() => _drawer = _PlayerDrawer.none);
      _scheduleControlsHide();
      return;
    }
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (!_controlsVisible) _watchPartyPanelExpanded = false;
    });
    if (_controlsVisible) {
      _scheduleControlsHide();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleControlsHide();
  }

  void _requestPlayerKeyboardFocus() {
    if (!_videoControlsFocusNode.canRequestFocus) return;
    _videoControlsFocusNode.requestFocus();
  }

  void _showControlsFromPlaybackSurface() {
    if (!mounted) return;
    _showControls();
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _drawer != _PlayerDrawer.none) return;
      if (_engine.state.value.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _openDrawer(_PlayerDrawer drawer) {
    PlaybackRuntimeDiagnostics.uiLog(
      '${drawer == _PlayerDrawer.server ? 'Server' : 'Settings'} button pressed',
    );
    _logInteractionSnapshot('before drawer open request=$drawer');
    setState(() {
      _controlsVisible = true;
      _drawer = _drawer == drawer ? _PlayerDrawer.none : drawer;
    });
    PlaybackRuntimeDiagnostics.uiLog(
      'Drawer opening requested=$drawer actual=$_drawer mounted=$mounted',
    );
    _logInteractionSnapshot('after drawer open request=$drawer');
    _hideControlsTimer?.cancel();
    if (_drawer == _PlayerDrawer.none) _requestPlayerKeyboardFocus();
  }

  void _openWebServerDrawer() {
    PlaybackRuntimeDiagnostics.uiLog(
      'WebView Server button pressed owner=PlayerScreen#$_instanceId '
      'mounted=$mounted contextMounted=${context.mounted} '
      'requestProvider=${widget.request.providerIndex ?? 'auto'} '
      'controllerProvider=${_controller.request.providerIndex ?? 'auto'} '
      'playback=${_engine.state.value.status.name}',
    );
    _logInteractionSnapshot('before web drawer open');
    setState(() {
      _controlsVisible = true;
      _drawer = _PlayerDrawer.none;
      _webDrawer = _WebOverlayDrawer.none;
      _webOverlayGeneration++;
    });
    PlaybackRuntimeDiagnostics.overlayLog(
      'WebView-specific server drawer delegated to DOM overlay actual=$_webDrawer '
      'generation=$_webOverlayGeneration sharedDrawer=$_drawer',
    );
    _logInteractionSnapshot('after web drawer open');
    _hideControlsTimer?.cancel();
    _requestPlayerKeyboardFocus();
  }

  void _toggleEmbeddedWebServerDrawer() {
    PlaybackRuntimeDiagnostics.uiLog(
      'Flutter embedded WebView server button pressed '
      'owner=PlayerScreen#$_instanceId current=$_webDrawer',
    );
    setState(() {
      _controlsVisible = true;
      _drawer = _PlayerDrawer.none;
      _webDrawer = _webDrawer == _WebOverlayDrawer.server
          ? _WebOverlayDrawer.none
          : _WebOverlayDrawer.server;
      _webOverlayGeneration++;
    });
    _hideControlsTimer?.cancel();
    if (_webDrawer == _WebOverlayDrawer.none) _requestPlayerKeyboardFocus();
  }

  bool _isTextInputFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    var editing = false;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is EditableText) {
        editing = true;
        return false;
      }
      return true;
    });
    return editing || context.widget is EditableText;
  }

  KeyEventResult _handlePlayerKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isTextInputFocused()) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (_drawer != _PlayerDrawer.none || _webDrawer != _WebOverlayDrawer.none) {
      if (key == LogicalKeyboardKey.escape) {
        setState(() {
          _drawer = _PlayerDrawer.none;
          _webDrawer = _WebOverlayDrawer.none;
          _webOverlayGeneration++;
        });
        _requestPlayerKeyboardFocus();
        _showControls();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.mediaPlay) {
      if (!_ensurePartyCanControl()) return KeyEventResult.handled;
      unawaited(_engine.play());
    } else if (key == LogicalKeyboardKey.mediaPause) {
      if (!_ensurePartyCanControl()) return KeyEventResult.handled;
      unawaited(_engine.pause());
    } else if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyK) {
      if (!_ensurePartyCanControl()) return KeyEventResult.handled;
      unawaited(_controller.togglePlayPause());
    } else if (key == LogicalKeyboardKey.keyJ ||
        key == LogicalKeyboardKey.arrowLeft) {
      if (!_ensurePartyCanControl()) return KeyEventResult.handled;
      unawaited(_controller.seekBy(const Duration(seconds: -10)));
    } else if (key == LogicalKeyboardKey.keyL ||
        key == LogicalKeyboardKey.arrowRight) {
      if (!_ensurePartyCanControl()) return KeyEventResult.handled;
      unawaited(_controller.seekBy(const Duration(seconds: 10)));
    } else if (key == LogicalKeyboardKey.keyM) {
      unawaited(_controller.toggleMute());
    } else if (key == LogicalKeyboardKey.period) {
      unawaited(
        _controller.setPlaybackSpeed(
          (_engine.state.value.playbackSpeed + 0.25).clamp(0.25, 2.0),
        ),
      );
    } else if (key == LogicalKeyboardKey.comma) {
      unawaited(
        _controller.setPlaybackSpeed(
          (_engine.state.value.playbackSpeed - 0.25).clamp(0.25, 2.0),
        ),
      );
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _changeVolume(0.05);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _changeVolume(-0.05);
    } else if (key == LogicalKeyboardKey.keyF) {
      final toggleFullscreen = _toggleNativeFullscreen;
      if (toggleFullscreen != null) unawaited(toggleFullscreen());
    } else if (key == LogicalKeyboardKey.keyS) {
      if (widget.sourceOptions.length > 1) {
        if (_usesEmbeddedWebPlayback) {
          _toggleEmbeddedWebServerDrawer();
        } else {
          _openDrawer(_PlayerDrawer.server);
        }
      }
    } else if (key == LogicalKeyboardKey.keyC && _hasWatchPartyContext) {
      _toggleWatchPartyPanel();
    } else if (key == LogicalKeyboardKey.escape) {
      if (_watchPartyPanelExpanded) {
        _setWatchPartyPanelExpanded(false);
      } else if (_isNativeFullscreenActive) {
        final toggleFullscreen = _toggleNativeFullscreen;
        if (toggleFullscreen != null) {
          unawaited(toggleFullscreen());
        }
      } else {
        _close();
      }
    } else {
      return KeyEventResult.ignored;
    }
    _showControls();
    return KeyEventResult.handled;
  }

  void _destroySharedOverlayForWebTransition({required String reason}) {
    PlaybackRuntimeDiagnostics.overlayLog(
      'Experiment destroying shared overlay before WebView contract '
      'reason=$reason sharedDrawer=$_drawer webDrawer=$_webDrawer '
      'generation=$_webOverlayGeneration',
    );
    _drawer = _PlayerDrawer.none;
    _webDrawer = _WebOverlayDrawer.none;
    _webOverlayGeneration++;
    _lastEmbeddedLayoutSnapshotKey = null;
    PlaybackRuntimeDiagnostics.overlayLog(
      'Experiment created fresh WebView overlay generation=$_webOverlayGeneration',
    );
  }

  String _focusOwnerLabel() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return 'none';
    final label = focus.debugLabel;
    final widgetType = focus.context?.widget.runtimeType.toString();
    return label == null || label.isEmpty
        ? widgetType ?? focus.runtimeType.toString()
        : '$label/$widgetType';
  }

  String _engineDisposedLabel() {
    final engine = _engine;
    if (engine is AdaptivePlaybackEngine) {
      return '${engine.debugSessionIdentity} disposed=${engine.debugDisposed}';
    }
    if (engine is WebPlaybackEngine) {
      return 'web#${engine.debugInstanceId} disposed=${engine.debugDisposed} '
          'generation=${engine.debugSurfaceGeneration}';
    }
    if (engine is MediaKitPlaybackEngine) {
      return 'mediaKit#${engine.debugInstanceId} disposed=${engine.debugDisposed}';
    }
    return 'unknownBackend=${engine.runtimeType}';
  }

  void _logInteractionSnapshot(String label, {PlaybackState? playback}) {
    final state = playback ?? _engine.state.value;
    final isWeb = _usesEmbeddedWebPlayback;
    PlaybackRuntimeDiagnostics.uiLog(
      '$label PlayerScreen#$_instanceId mounted=$mounted drawer=$_drawer '
      'webDrawer=$_webDrawer webOverlayGeneration=$_webOverlayGeneration '
      'controlsVisible=$_controlsVisible sourceSwitchInFlight=$_sourceSwitchInFlight '
      'playback=${state.status.name} focusOwner=${_focusOwnerLabel()} '
      'controllerDisposed=${_controller.debugDisposed} ${_engineDisposedLabel()}',
    );
    PlaybackRuntimeDiagnostics.overlayLog(
      '$label IgnorePointer active=${!_controlsVisible && !isWeb} '
      'AbsorbPointer active=false ModalBarrier present=false '
      'drawerMounted=${_drawer != _PlayerDrawer.none} '
      'webDrawerMounted=${_webDrawer != _WebOverlayDrawer.none} '
      'serverButtonOnPressed=true settingsButtonOnPressed=${!isWeb} '
      'embeddedTopBarRect=$_embeddedTopBarRect '
      'embeddedWebViewInputExclusionRect=$_embeddedSurfaceRect',
    );
    PlaybackRuntimeDiagnostics.webLog(
      '$label WebView owns playback=$isWeb '
      'webViewRecreated=${PlaybackRuntimeDiagnostics.webViewsCreated} created/'
      '${PlaybackRuntimeDiagnostics.webViewsDestroyed} destroyed '
      'reused=${PlaybackRuntimeDiagnostics.webViewReuseCount}',
    );
  }

  void _changeDisplayFit(BoxFit fit) {
    setState(() => _displayFit = fit);
  }

  void _changeVolume(double delta) {
    final next = (_engine.state.value.volume + delta).clamp(0.0, 2.0);
    unawaited(_controller.setVolume(next));
    setState(() => _volumeOverlayValue = next);
    _volumeOverlayTimer?.cancel();
    _volumeOverlayTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _volumeOverlayValue = null);
    });
  }

  bool get _hasNextEpisode {
    if (widget.request.mediaType != PlaybackMediaType.tv &&
        widget.request.mediaType != PlaybackMediaType.anime) {
      return false;
    }
    final episode = widget.request.episode ?? 1;
    final totalEpisodes = widget.request.totalEpisodes;
    if (totalEpisodes == null) return true;
    if (episode < totalEpisodes) return true;
    return (widget.request.season ?? 1) < widget.request.totalSeasons;
  }

  VoidCallback? get _initialEpisodeSelectorCallback {
    final total = _episodeSelectorTotal(widget.request);
    return total == null ? null : _showEpisodeSelector;
  }

  VoidCallback? get _episodeSelectorCallback {
    final total = _episodeSelectorTotal(_controller.request);
    return total == null ? null : _showEpisodeSelector;
  }

  int? _episodeSelectorTotal(PlaybackRequest request) {
    final total = request.totalEpisodes ?? widget.request.totalEpisodes;
    if (total != null && total > 0) return total;
    if (request.mediaType != PlaybackMediaType.tv &&
        request.mediaType != PlaybackMediaType.anime) {
      return null;
    }
    return null;
  }

  bool get _usesEmbeddedWebPlayback {
    final result =
        _controller.request.streamResult ?? widget.request.streamResult;
    if (result?.isIframe == true) return true;
    final source = _controller.request.source?.toLowerCase() ?? '';
    return source.contains('youtube.com/watch') ||
        source.contains('youtube.com/embed') ||
        source.contains('youtu.be/') ||
        source.contains('vidup.') ||
        source.contains('vidlink.') ||
        source.contains('vidcore.') ||
        source.contains('vidplus.');
  }

  bool _requestUsesEmbeddedWebPlayback(PlaybackRequest request) {
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

  PlaybackRequest? _nextEpisodeRequest() {
    if (!_hasNextEpisode) return null;
    final currentRequest = _controller.request;
    final season = currentRequest.season ?? 1;
    final episode = currentRequest.episode ?? 1;
    final totalEpisodes = currentRequest.totalEpisodes;
    final nextSeason = totalEpisodes != null && episode >= totalEpisodes
        ? season + 1
        : season;
    final nextEpisode = totalEpisodes != null && episode >= totalEpisodes
        ? 1
        : episode + 1;
    return currentRequest.copyWith(
      source: '',
      season: nextSeason,
      episode: nextEpisode,
      startPosition: Duration.zero,
      streamResult: null,
      clearSource: true,
      clearStreamResult: true,
    );
  }

  void _startNextEpisode() {
    if (!_ensurePartyCanControl()) return;
    if (_nextEpisodeStarted || _sourceSwitchInFlight) return;
    final next = _nextEpisodeRequest();
    final onNextEpisode = widget.onNextEpisode;
    if (next == null || onNextEpisode == null) return;
    _nextEpisodeStarted = true;
    _sourceSwitchInFlight = true;
    unawaited(_controller.stop());
    onNextEpisode(next);
  }

  Future<void> _switchSource(PlaybackSourceOption option) async {
    PlaybackRuntimeDiagnostics.uiLog(
      'Drawer source option selected index=${option.index} '
      'provider=${option.provider} server=${option.server} '
      'group=${option.group ?? 'none'} iframeOnly=${option.iframeOnly} '
      'owner=PlayerScreen#$_instanceId mounted=$mounted drawer=$_drawer '
      'webGeneration=$_webOverlayGeneration '
      'requestProvider=${widget.request.providerIndex ?? 'auto'} '
      'controllerProvider=${_controller.request.providerIndex ?? 'auto'}',
    );
    _logInteractionSnapshot('before _switchSource');
    if (!_ensurePartyCanControl()) return;
    if (_sourceSwitchInFlight) return;
    final callback = widget.onSourceSwitch ?? widget.onNextEpisode;
    if (callback == null) {
      PlaybackRuntimeDiagnostics.uiLog(
        'Source switch aborted: no callback owner=PlayerScreen#$_instanceId '
        'option=${option.index}',
      );
      return;
    }
    setState(() {
      _sourceSwitchInFlight = true;
      _sourceSwitchMessage = _switchingMessageForSource(option);
      _drawer = _PlayerDrawer.none;
      _webDrawer = _WebOverlayDrawer.none;
      _webOverlayGeneration++;
    });
    PlaybackRuntimeDiagnostics.controllerLog(
      'Switch provider started current=${_controller.request.providerIndex ?? 'auto'} '
      'next=${option.index} owner=PlayerScreen#$_instanceId',
    );
    PlaybackRuntimeDiagnostics.lifecycleLog(
      'Provider switch before stop PlayerScreen#$_instanceId '
      '${_engineDisposedLabel()} '
      '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
    );
    try {
      final nextRequest = _controller.request.copyWith(
        providerIndex: option.index,
        clearSource: true,
        clearStreamResult: true,
        startPosition: _engine.state.value.position,
      );
      PlaybackRuntimeDiagnostics.controllerLog(
        'Switch provider next request prepared owner=PlayerScreen#$_instanceId '
        'next=${option.index} source=${nextRequest.source ?? 'none'} '
        'streamResult=${nextRequest.streamResult?.provider ?? 'none'} '
        'positionMs=${nextRequest.startPosition.inMilliseconds}',
      );
      await _controller.prepareForSourceSwitch(nextRequest);
      await _controller.stop();
      if (!mounted) return;
      PlaybackRuntimeDiagnostics.uiLog(
        'Source switch callback dispatch mounted=$mounted next=${option.index} '
        'callback=${callback == widget.onSourceSwitch ? 'onSourceSwitch' : 'onNextEpisode'} '
        'owner=PlayerScreen#$_instanceId '
        '${PlaybackRuntimeDiagnostics.lifecycleSummary()}',
      );
      callback(nextRequest);
    } finally {
      if (mounted) {
        setState(() {
          _sourceSwitchInFlight = false;
          _sourceSwitchMessage = null;
        });
      }
      _logInteractionSnapshot('after _switchSource finally');
    }
  }

  String _switchingMessageForSource(PlaybackSourceOption option) {
    final label = option.label.trim().isNotEmpty
        ? option.label.trim()
        : option.server.trim().isNotEmpty
        ? option.server.trim()
        : option.provider.trim();
    return label.isEmpty ? 'Switching server...' : 'Switching to $label...';
  }

  Future<void> _switchQuality(_QualityOption option) async {
    if (!_ensurePartyCanControl()) return;
    await _controller.switchQuality(option.quality, option.url);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _switchStreamAudio(String audio) async {
    if (!_ensurePartyCanControl()) return;
    if (_sourceSwitchInFlight) return;
    final normalized = audio.trim();
    if (normalized.isEmpty) return;
    final current =
        (_controller.request.preferredAudioTrack ??
                widget.request.streamResult?.selectedAudio ??
                '')
            .trim();
    if (normalized.toLowerCase() == current.toLowerCase()) return;
    final callback = widget.onSourceSwitch ?? widget.onNextEpisode;
    if (callback == null) return;
    setState(() {
      _sourceSwitchInFlight = true;
      _sourceSwitchMessage = 'Switching audio...';
      _drawer = _PlayerDrawer.none;
    });
    try {
      final nextRequest = _controller.request.copyWith(
        preferredAudioTrack: normalized,
        clearPreferredQuality: true,
        clearSource: true,
        clearStreamResult: true,
        startPosition: _engine.state.value.position,
      );
      await _controller.prepareForSourceSwitch(nextRequest);
      await _controller.stop();
      if (!mounted) return;
      callback(nextRequest);
    } finally {
      if (mounted) {
        setState(() {
          _sourceSwitchInFlight = false;
          _sourceSwitchMessage = null;
        });
      }
    }
  }

  void _playEpisode(int episode) {
    if (!_ensurePartyCanControl()) return;
    if (_sourceSwitchInFlight) return;
    final callback = widget.onSourceSwitch ?? widget.onNextEpisode;
    final currentRequest = _controller.request;
    if (callback == null || episode == currentRequest.episode) return;
    setState(() {
      _sourceSwitchInFlight = true;
      _sourceSwitchMessage = 'Loading episode $episode...';
      _drawer = _PlayerDrawer.none;
      _webDrawer = _WebOverlayDrawer.none;
      _webOverlayGeneration++;
    });
    unawaited(_controller.stop());
    callback(
      currentRequest.copyWith(
        episode: episode,
        clearSource: true,
        clearStreamResult: true,
        startPosition: Duration.zero,
      ),
    );
  }

  Future<void> _showEpisodeSelector() async {
    final request = _controller.request;
    final total = _episodeSelectorTotal(request);
    if (total == null || total <= 0) return;
    final selected = await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => _EpisodePickerDialog(
        totalEpisodes: total,
        currentEpisode: request.episode ?? 1,
        season: request.season ?? 1,
      ),
    );
    if (selected != null) _playEpisode(selected);
  }

  Future<void> _loadCustomSubtitle() async {
    await _loadCustomSubtitleFromUrl();
  }

  Future<void> _loadCustomSubtitleFromFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa'],
        lockParentWindow: true,
      );
      final path = file?.path?.trim();
      if (path == null || path.isEmpty) return;

      await _selectCustomSubtitle(
        uri: Uri.file(path).toString(),
        label: file!.name.isEmpty ? path.split('/').last : file.name,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load subtitle file: $error')),
      );
    }
  }

  Future<void> _loadCustomSubtitleFromUrl() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load Subtitle URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Subtitle URL',
            hintText: 'Paste subtitle URL',
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Load'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;

    final uri = Uri.tryParse(value);
    final validUrl =
        uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.path.trim().isNotEmpty;
    if (!validUrl) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid subtitle URL.')),
      );
      return;
    }

    await _selectCustomSubtitle(
      uri: value,
      label: uri.pathSegments.isEmpty
          ? 'Remote Subtitle'
          : uri.pathSegments.last,
    );
  }

  Future<void> _selectCustomSubtitle({
    required String uri,
    required String label,
  }) async {
    final trackId = 'external:Custom:$uri';
    unawaited(_controller.selectSubtitleTrack(trackId, externalUrl: uri));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Loaded subtitle: $label')));
    }
  }

  void _changeSubtitleDelay(Duration delta) {
    setState(() => _subtitleDelay += delta);
    unawaited(_controller.setSubtitleDelay(_subtitleDelay));
    unawaited(_saveSubtitleDelay());
  }

  void _applySubtitleStyle({
    double? scale,
    String? background,
    String? outline,
  }) {
    final nextScale = scale ?? _subtitleScale;
    final nextBackgroundLabel = background ?? _subtitleBackground;
    final nextOutlineLabel = outline ?? _subtitleOutline;
    final nextBackground = nextBackgroundLabel != 'Transparent';
    final nextOutline = nextOutlineLabel != 'None';
    setState(() {
      _subtitleScale = nextScale;
      _subtitleBackground = nextBackgroundLabel;
      _subtitleOutline = nextOutlineLabel;
      _subtitleBackgroundEnabled = nextBackground;
      _subtitleOutlineEnabled = nextOutline;
    });
    unawaited(
      _controller.setSubtitleStyle(
        SubtitleStyle(
          scale: nextScale,
          background: nextBackground,
          outline: nextOutline,
        ),
      ),
    );
    unawaited(
      _saveSubtitleStyle(
        scale: scale,
        background: background,
        outline: outline,
      ),
    );
  }

  void _setDebanding(bool enabled) {
    setState(() => _debandingEnabled = enabled);
    unawaited(_controller.setDebanding(enabled));
    unawaited(_saveDebanding(enabled));
  }

  Future<void> _showDiagnosticsPanel() async {
    final diagnostics = await _controller.diagnostics();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Playback Diagnostics'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DiagnosticsRow(label: 'Provider', value: _providerLabel),
                _DiagnosticsRow(
                  label: 'Server',
                  value: _serverLabel ?? 'unknown',
                ),
                _DiagnosticsRow(label: 'Stream type', value: _streamTypeLabel),
                for (final row in diagnostics.toRows().entries)
                  _DiagnosticsRow(label: row.key, value: row.value),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _takeScreenshot() async {
    try {
      final path = await _controller.takeScreenshot();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null ? 'Screenshot unavailable' : 'Screenshot saved: $path',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Screenshot failed: $error')));
    }
  }

  String get _providerLabel =>
      widget.request.streamResult?.provider ??
      widget.request.streamResult?.providerGroup ??
      'Unknown';

  String? get _serverLabel => widget.request.streamResult?.serverName;

  String get _streamTypeLabel {
    final result = widget.request.streamResult;
    if (result?.isIframe == true) return 'iframe';
    if (result?.isM3U8 == true) return 'HLS';
    final source = result?.url ?? widget.request.source ?? '';
    if (source.toLowerCase().contains('.m3u8')) return 'HLS';
    if (source.startsWith('file:') || source.startsWith('/')) return 'local';
    if (source.isEmpty) return 'unknown';
    return 'direct';
  }

  List<_QualityOption> _qualityOptionsFromResult(PlaybackRequest request) {
    final result = request.streamResult;
    final options = <_QualityOption>[
      _QualityOption(
        quality: 'auto',
        url: result?.url ?? request.source ?? '',
        label: 'Auto',
      ),
    ];
    for (final source
        in result?.sources ?? const <stream_models.StreamSource>[]) {
      if (source.url.trim().isEmpty) continue;
      final quality = source.quality.trim().isEmpty ? 'auto' : source.quality;
      if (options.any((option) => option.url == source.url)) continue;
      options.add(
        _QualityOption(quality: quality, url: source.url, label: quality),
      );
    }
    return options;
  }

  Future<void> _discoverHlsQualities() async {
    final result = widget.request.streamResult;
    final source = result?.url ?? widget.request.source;
    if (source == null ||
        source.trim().isEmpty ||
        !(result?.isM3U8 ?? source.toLowerCase().contains('.m3u8'))) {
      if (mounted) setState(() => _qualityDiscoveryComplete = true);
      _applyPreferredQuality();
      return;
    }
    final parsed = await M3u8Parser.parseVideoResolutions(
      source,
      widget.request.httpHeaders,
    );
    if (!mounted) return;
    setState(() {
      for (final item in parsed) {
        if (_qualityOptions.any((option) => option.url == item.url)) continue;
        _qualityOptions.add(
          _QualityOption(
            quality: item.quality,
            url: item.url,
            label: item.quality,
          ),
        );
      }
      _qualityDiscoveryComplete = true;
    });
    _applyPreferredQuality();
  }

  void _applyPreferredQuality() {
    if (_preferredQualityApplied) return;
    final preferred = _controller.request.preferredQuality;
    if (preferred == null || preferred.isEmpty || preferred == 'auto') return;
    for (final option in _qualityOptions) {
      if (option.quality == preferred) {
        _preferredQualityApplied = true;
        unawaited(_controller.switchQuality(option.quality, option.url));
        return;
      }
    }
  }

  Widget _buildVideoControls(VideoState videoState) {
    _toggleNativeFullscreen = videoState.toggleFullscreen;
    return _isNativeFullscreenActive
        ? ValueListenableBuilder<PlaybackState>(
            valueListenable: _engine.state,
            builder: (context, playback, _) {
              return MouseRegion(
                onHover: (_) {
                  _requestPlayerKeyboardFocus();
                  _showControls();
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    _requestPlayerKeyboardFocus();
                    _toggleControls();
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_controlsVisible &&
                          playback.status != PlaybackStatus.error)
                        const ColoredBox(color: Color(0x66000000)),
                      if (playback.status != PlaybackStatus.error)
                        _AndroidPlayerControls(
                          visible: _controlsVisible,
                          playback: playback,
                          request: widget.request,
                          providerLabel: _providerLabel,
                          serverLabel: _serverLabel,
                          canSwitchServer: widget.sourceOptions.length > 1,
                          watchPartyMemberCount: _hasWatchPartyContext
                              ? _watchPartySession?.participantCount ?? 0
                              : null,
                          onWatchParty: _hasWatchPartyContext
                              ? _toggleWatchPartyPanel
                              : null,
                          onClose: () => unawaited(videoState.exitFullscreen()),
                          onPlayPause: () {
                            if (!_ensurePartyCanControl()) return;
                            unawaited(_controller.togglePlayPause());
                            _showControls();
                          },
                          onSeek: (position) {
                            if (!_ensurePartyCanControl()) return;
                            unawaited(_engine.seek(position));
                            _showControls();
                          },
                          onSettings: () => _openDrawer(_PlayerDrawer.settings),
                          onServer: () => _openDrawer(_PlayerDrawer.server),
                          onEpisodes: _episodeSelectorCallback,
                        ),
                      if (_sourceSwitchInFlight)
                        _PlayerSwitchingOverlay(
                          message:
                              _sourceSwitchMessage ?? 'Switching server...',
                        ),
                      _SkipOverlay(
                        playback: playback,
                        skipTimes: _effectiveSkipTimes,
                        onSkip: (target) {
                          if (!_ensurePartyCanControl()) return;
                          unawaited(_engine.seek(target));
                        },
                      ),
                      if (_hasNextEpisode && playback.duration > Duration.zero)
                        _NextEpisodeOverlay(
                          playback: playback,
                          autoplay: _autoplayNextEpisode,
                          onNext: _startNextEpisode,
                        ),
                      if (_hasWatchPartyContext)
                        _WatchPartyStatusOverlay(
                          visible:
                              _controlsVisible ||
                              _watchPartyPanelExpanded ||
                              _watchPartyStatusMessage != null,
                          expanded: _watchPartyPanelExpanded,
                          onExpandedChanged: _setWatchPartyPanelExpanded,
                          session: _watchPartySession,
                          isHost: _watchPartyService?.isHost == true,
                          canControl: _canControlPartyPlayback,
                          connectionLabel: _partyConnectionLabel,
                          controllerLabel: _partyControllerLabel,
                          statusMessage: _watchPartyStatusMessage,
                          messages: _watchPartyMessages,
                          reactions: _watchPartyReactions,
                          onSendMessage: _sendWatchPartyChat,
                          onSendReaction: _sendWatchPartyReaction,
                          onLeaveOrEnd: _leaveOrEndWatchParty,
                        ),
                      if (_volumeOverlayValue != null)
                        _VolumeOverlay(value: _volumeOverlayValue!),
                      if (_drawer != _PlayerDrawer.none)
                        _buildRightDrawer(playback),
                    ],
                  ),
                ),
              );
            },
          )
        : const SizedBox.expand();
  }

  Widget _buildSurface(BuildContext context) {
    final surfaceBuilder = widget.surfaceBuilder;
    PlaybackRuntimeDiagnostics.uiLog(
      'PlayerScreen#$_instanceId buildSurface request '
      'surfaceBuilder=${surfaceBuilder != null} '
      'usesEmbeddedWeb=$_usesEmbeddedWebPlayback '
      'requestProvider=${widget.request.providerIndex ?? 'auto'} '
      'controllerProvider=${_controller.request.providerIndex ?? 'auto'} '
      '${_engineDisposedLabel()}',
    );
    if (surfaceBuilder != null) return surfaceBuilder(context, _engine);

    final engine = _engine;
    if (engine is PlaybackSurfaceEngine) {
      return engine.buildSurface(
        context: context,
        fit: _displayFit,
        controls: _buildVideoControls,
        onEnterFullscreen: _handleEnterNativeFullscreen,
        onExitFullscreen: _handleExitNativeFullscreen,
      );
    }
    if (engine is MediaKitPlaybackEngine) {
      return Video(
        controller: engine.videoController,
        fit: _displayFit,
        fill: Colors.black,
        controls: _buildVideoControls,
        onEnterFullscreen: _handleEnterNativeFullscreen,
        onExitFullscreen: _handleExitNativeFullscreen,
      );
    }

    return const ColoredBox(
      key: ValueKey('playback-surface-placeholder'),
      color: Colors.black,
    );
  }

  Future<void> _handleEnterNativeFullscreen() async {
    if (mounted && !_isNativeFullscreenActive) {
      setState(() => _isNativeFullscreenActive = true);
    }
    await defaultEnterNativeFullscreen();
  }

  Future<void> _handleExitNativeFullscreen() async {
    if (mounted && _isNativeFullscreenActive) {
      setState(() {
        _isNativeFullscreenActive = false;
        _drawer = _PlayerDrawer.none;
      });
    }
    await defaultExitNativeFullscreen();
  }

  Widget _buildRightDrawer(PlaybackState playback, {bool inline = false}) {
    PlaybackRuntimeDiagnostics.overlayLog(
      'Drawer widget build drawer=$_drawer inline=$inline mounted=$mounted '
      'playback=${playback.status.name}',
    );
    return _RightPlayerDrawer(
      drawer: _drawer,
      playback: playback,
      qualities: _qualityOptions,
      selectedQuality:
          _controller.request.preferredQuality ??
          widget.request.streamResult?.quality ??
          'auto',
      qualityDiscoveryComplete: _qualityDiscoveryComplete,
      sourceOptions: widget.sourceOptions,
      selectedSourceIndex: _controller.request.providerIndex,
      providerLabel: _providerLabel,
      serverLabel: _serverLabel ?? widget.request.streamResult?.providerGroup,
      streamAudioOptions:
          widget.request.streamResult?.availableAudios ?? const [],
      selectedStreamAudio:
          _controller.request.preferredAudioTrack ??
          widget.request.streamResult?.selectedAudio ??
          '',
      externalSubtitles: widget.request.streamResult?.subtitles ?? const [],
      displayFit: _displayFit,
      debandingEnabled: _debandingEnabled,
      subtitleDelay: _subtitleDelay,
      subtitleScale: _subtitleScale,
      subtitleBackground: _subtitleBackground,
      subtitleOutline: _subtitleOutline,
      onClose: () => setState(() => _drawer = _PlayerDrawer.none),
      onSourceSelected: (option) {
        PlaybackRuntimeDiagnostics.overlayLog(
          'Drawer source tile tap received index=${option.index} '
          'server=${option.server}',
        );
        setState(() => _drawer = _PlayerDrawer.none);
        unawaited(_switchSource(option));
      },
      onQualitySelected: (option) => unawaited(_switchQuality(option)),
      onStreamAudioSelected: (audio) => unawaited(_switchStreamAudio(audio)),
      onAudioSelected: (trackId) =>
          unawaited(_controller.selectAudioTrack(trackId)),
      onSubtitleSelected: (trackId, externalUrl) => unawaited(
        _controller.selectSubtitleTrack(trackId, externalUrl: externalUrl),
      ),
      onLoadLocalSubtitle: _loadCustomSubtitleFromFile,
      onLoadRemoteSubtitle: _loadCustomSubtitle,
      onSubtitleDelayChanged: _changeSubtitleDelay,
      onSubtitleScaleChanged: (value) => _applySubtitleStyle(scale: value),
      onSubtitleBackgroundChanged: (value) =>
          _applySubtitleStyle(background: value),
      onSubtitleOutlineChanged: (value) => _applySubtitleStyle(outline: value),
      onDisplayFitChanged: _changeDisplayFit,
      onDebandingChanged: _setDebanding,
      onVolumeChanged: (value) => unawaited(_controller.setVolume(value)),
      onDiagnosticsPressed: () => unawaited(_showDiagnosticsPanel()),
      onScreenshotPressed: () => unawaited(_takeScreenshot()),
      onSpeedSelected: (speed) =>
          unawaited(_controller.setPlaybackSpeed(speed)),
      onRepeatPressed: () => unawaited(_controller.cycleRepeatMode()),
      autoplayNextEpisode: _autoplayNextEpisode,
      onAutoplayChanged: _hasNextEpisode
          ? (value) {
              setState(() => _autoplayNextEpisode = value);
              unawaited(_saveAutoplay(value));
            }
          : null,
      inline: inline,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _videoControlsFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handlePlayerKey(event),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _requestPlayerKeyboardFocus();
            PlaybackRuntimeDiagnostics.uiLog(
              'Flutter root pointer down position=${event.position} '
              'buttons=${event.buttons}',
            );
            _logFlutterHitTest('root pointer down', event);
            _logInteractionSnapshot('root pointer down');
          },
          onPointerUp: (event) => PlaybackRuntimeDiagnostics.uiLog(
            'Flutter root pointer up position=${event.position}',
          ),
          child: ValueListenableBuilder<PlaybackState>(
            valueListenable: _engine.state,
            builder: (context, playback, _) {
              final usesEmbeddedWeb = _usesEmbeddedWebPlayback;
              PlaybackRuntimeDiagnostics.uiLog(
                'PlayerScreen#$_instanceId ValueListenable rebuild '
                'mounted=$mounted contextMounted=${context.mounted} '
                'playback=${playback.status.name} usesEmbeddedWeb=$usesEmbeddedWeb '
                'requestProvider=${widget.request.providerIndex ?? 'auto'} '
                'controllerProvider=${_controller.request.providerIndex ?? 'auto'} '
                'streamResultProvider=${widget.request.streamResult?.provider ?? 'none'} '
                'streamResultIframe=${widget.request.streamResult?.isIframe ?? false} '
                'sourceOptions=${widget.sourceOptions.length} '
                'sourceSwitchInFlight=$_sourceSwitchInFlight '
                'buttonShouldExist=${usesEmbeddedWeb && playback.status != PlaybackStatus.loading} '
                '${_engineDisposedLabel()}',
              );
              _maybeRecoverEmbeddedProviderError(playback);
              if (usesEmbeddedWeb) {
                return _buildEmbeddedWebLayout(playback);
              }

              if (playback.status == PlaybackStatus.error) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildSurface(context),
                    _PlayerErrorOverlay(
                      message: playback.errorMessage ?? 'Playback failed.',
                      canSwitchServer: widget.sourceOptions.length > 1,
                      onSwitchServer: _switchToNextSource,
                      onRetry: () => unawaited(_controller.retry()),
                      onClose: _close,
                    ),
                    _AndroidPlayerControls(
                      visible: true,
                      playback: playback,
                      request: widget.request,
                      providerLabel: _providerLabel,
                      serverLabel: _serverLabel,
                      canSwitchServer: widget.sourceOptions.length > 1,
                      onClose: _close,
                      onMiniPlayer: widget.onMinimize == null
                          ? null
                          : _minimizeToMiniPlayer,
                      onPlayPause: () =>
                          unawaited(_controller.togglePlayPause()),
                      onSeek: (position) => unawaited(_engine.seek(position)),
                      onSettings: () => _openDrawer(_PlayerDrawer.settings),
                      onServer: () => _openDrawer(_PlayerDrawer.server),
                      onEpisodes: _episodeSelectorCallback,
                    ),
                    if (_sourceSwitchInFlight)
                      _PlayerSwitchingOverlay(
                        message: _sourceSwitchMessage ?? 'Switching server...',
                      ),
                    if (_drawer != _PlayerDrawer.none)
                      _buildRightDrawer(playback),
                  ],
                );
              }

              return MouseRegion(
                onHover: (_) {
                  _requestPlayerKeyboardFocus();
                  _showControls();
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildSurface(context),
                    _PlayerGestureLayer(
                      playback: playback,
                      onTap: _toggleControls,
                      onSeekBy: (offset) {
                        if (!_ensurePartyCanControl()) return;
                        unawaited(_controller.seekBy(offset));
                        _showControls();
                      },
                      onVolumeChanged: (value) {
                        unawaited(_controller.setVolume(value));
                        _showControls();
                      },
                    ),
                    if (_controlsVisible &&
                        playback.status != PlaybackStatus.error)
                      const ColoredBox(color: Color(0x66000000)),
                    if (playback.status == PlaybackStatus.loading)
                      _PlayerLoadingOverlay(
                        title: widget.request.title,
                        posterPath: widget.request.posterPath,
                        subtitle: _requestSubtitle,
                        message:
                            widget.request.streamResult?.provider ??
                            'Finding a playable source...',
                      ),
                    if (playback.status != PlaybackStatus.error)
                      _AndroidPlayerControls(
                        visible: _controlsVisible,
                        playback: playback,
                        request: widget.request,
                        providerLabel: _providerLabel,
                        serverLabel: _serverLabel,
                        canSwitchServer: widget.sourceOptions.length > 1,
                        watchPartyMemberCount: _hasWatchPartyContext
                            ? _watchPartySession?.participantCount ?? 0
                            : null,
                        onWatchParty: _hasWatchPartyContext
                            ? _toggleWatchPartyPanel
                            : null,
                        onClose: _close,
                        onMiniPlayer: widget.onMinimize == null
                            ? null
                            : _minimizeToMiniPlayer,
                        onPlayPause: () {
                          if (!_ensurePartyCanControl()) return;
                          unawaited(_controller.togglePlayPause());
                          _showControls();
                        },
                        onSeek: (position) {
                          if (!_ensurePartyCanControl()) return;
                          unawaited(_engine.seek(position));
                          _showControls();
                        },
                        onSettings: () => _openDrawer(_PlayerDrawer.settings),
                        onServer: () => _openDrawer(_PlayerDrawer.server),
                        onEpisodes: _episodeSelectorCallback,
                      ),
                    if (playback.status == PlaybackStatus.buffering)
                      const _PlayerBufferingOverlay(),
                    if (_sourceSwitchInFlight)
                      _PlayerSwitchingOverlay(
                        message: _sourceSwitchMessage ?? 'Switching server...',
                      ),
                    _SkipOverlay(
                      playback: playback,
                      skipTimes: _effectiveSkipTimes,
                      onSkip: (target) {
                        if (!_ensurePartyCanControl()) return;
                        unawaited(_engine.seek(target));
                      },
                    ),
                    if (_hasNextEpisode && playback.duration > Duration.zero)
                      _NextEpisodeOverlay(
                        playback: playback,
                        autoplay: _autoplayNextEpisode,
                        onNext: _startNextEpisode,
                      ),
                    if (_hasWatchPartyContext)
                      _WatchPartyStatusOverlay(
                        visible:
                            _controlsVisible ||
                            _watchPartyPanelExpanded ||
                            _watchPartyStatusMessage != null,
                        expanded: _watchPartyPanelExpanded,
                        onExpandedChanged: _setWatchPartyPanelExpanded,
                        session: _watchPartySession,
                        isHost: _watchPartyService?.isHost == true,
                        canControl: _canControlPartyPlayback,
                        connectionLabel: _partyConnectionLabel,
                        controllerLabel: _partyControllerLabel,
                        statusMessage: _watchPartyStatusMessage,
                        messages: _watchPartyMessages,
                        reactions: _watchPartyReactions,
                        onSendMessage: _sendWatchPartyChat,
                        onSendReaction: _sendWatchPartyReaction,
                        onLeaveOrEnd: _leaveOrEndWatchParty,
                      ),
                    if (_volumeOverlayValue != null)
                      _VolumeOverlay(value: _volumeOverlayValue!),
                    if (_drawer != _PlayerDrawer.none)
                      _buildRightDrawer(playback),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmbeddedWebLayout(PlaybackState playback) {
    final shouldInsertServerButton = playback.status != PlaybackStatus.loading;
    final shouldShowServerButton = shouldInsertServerButton;
    final showEmbeddedEscapeBar =
        playback.status != PlaybackStatus.ready &&
        playback.status != PlaybackStatus.completed;
    PlaybackRuntimeDiagnostics.overlayLog(
      'Embedded WebView layout rebuild owner=PlayerScreen#$_instanceId '
      'mounted=$mounted contextMounted=${context.mounted} '
      'playback=${playback.status.name} '
      'requestProvider=${widget.request.providerIndex ?? 'auto'} '
      'controllerProvider=${_controller.request.providerIndex ?? 'auto'} '
      'streamResultProvider=${widget.request.streamResult?.provider ?? 'none'} '
      'sourceOptions=${widget.sourceOptions.length} '
      'insertServerButton=$shouldInsertServerButton '
      'showServerButton=$shouldShowServerButton '
      'overlayGeneration=$_webOverlayGeneration '
      '${_engineDisposedLabel()}',
    );
    final snapshotKey =
        '${playback.status.name}|$_drawer|$_webDrawer|'
        '$_webOverlayGeneration|${widget.request.providerIndex}|'
        '${PlaybackRuntimeDiagnostics.webViewsCreated}|'
        '${PlaybackRuntimeDiagnostics.webViewsDestroyed}';
    if (_lastEmbeddedLayoutSnapshotKey != snapshotKey) {
      _lastEmbeddedLayoutSnapshotKey = snapshotKey;
      _logInteractionSnapshot('embedded layout build', playback: playback);
    }
    return MouseRegion(
      onEnter: (_) => _showControls(),
      onHover: (_) => _showControls(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerHover: (_) => _showControls(),
        onPointerDown: (_) => _showControls(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            PlaybackRuntimeDiagnostics.overlayLog(
              'Embedded WebView stack layout constraints=${constraints.biggest} '
              'serverOverlayVisible=$shouldShowServerButton '
              'owner=PlayerScreen#$_instanceId generation=$_webOverlayGeneration',
            );
            return Column(
              children: [
                if (showEmbeddedEscapeBar)
                  _EmbeddedWebTopBar(
                    playback: playback,
                    title: widget.request.title,
                    providerLabel: _providerLabel,
                    serverLabel:
                        _serverLabel ??
                        widget.request.streamResult?.providerGroup,
                    canSwitchServer: widget.sourceOptions.length > 1,
                    onBack: _close,
                    onServer: _toggleEmbeddedWebServerDrawer,
                    onMiniPlayer: widget.onMinimize == null
                        ? null
                        : _minimizeToMiniPlayer,
                    onRetry: playback.status == PlaybackStatus.error
                        ? () => unawaited(_controller.retry())
                        : null,
                  ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _InteractionGeometryProbe(
                              label: 'embedded WebView surface',
                              onGeometryChanged: _recordEmbeddedSurfaceGeometry,
                              child: _buildSurface(context),
                            ),
                            if (playback.status == PlaybackStatus.loading)
                              const _EmbeddedWebStatusBanner(
                                message: 'Loading embedded player...',
                              ),
                            if (playback.status == PlaybackStatus.buffering)
                              const _EmbeddedWebStatusBanner(
                                message: 'Buffering...',
                              ),
                            if (playback.status == PlaybackStatus.error)
                              _PlayerErrorOverlay(
                                message:
                                    playback.errorMessage ??
                                    'Embedded playback failed.',
                                canSwitchServer:
                                    widget.sourceOptions.length > 1,
                                onSwitchServer: _switchToNextSource,
                                onRetry: () => unawaited(_controller.retry()),
                                onClose: _close,
                              ),
                            if (_sourceSwitchInFlight)
                              _PlayerSwitchingOverlay(
                                message:
                                    _sourceSwitchMessage ??
                                    'Switching server...',
                              ),
                          ],
                        ),
                      ),
                      if (_webDrawer == _WebOverlayDrawer.server)
                        _buildWebServerDrawer(
                          playback,
                          width: 350,
                          onClose: () => setState(() {
                            _webDrawer = _WebOverlayDrawer.none;
                            _webOverlayGeneration++;
                          }),
                          onSourceSelected: (option) {
                            setState(() {
                              _webDrawer = _WebOverlayDrawer.none;
                              _webOverlayGeneration++;
                            });
                            unawaited(_switchSource(option));
                          },
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String? get _requestSubtitle {
    if (widget.request.mediaType == PlaybackMediaType.movie ||
        widget.request.isLive) {
      return null;
    }
    return 'S${widget.request.season ?? 1} E${widget.request.episode ?? 1}';
  }

  void _switchToNextSource() {
    if (widget.sourceOptions.isEmpty) return;
    final current = _controller.request.providerIndex ?? 0;
    final next = widget.sourceOptions.firstWhere(
      (option) => option.index > current,
      orElse: () => widget.sourceOptions.first,
    );
    unawaited(_switchSource(next));
  }

  void _logFlutterHitTest(String label, PointerEvent event) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
    final path = result.path
        .take(12)
        .map((entry) => entry.target.runtimeType.toString())
        .join(' > ');
    PlaybackRuntimeDiagnostics.uiLog(
      '$label hitTest position=${event.position} path=$path',
    );
  }

  void _recordEmbeddedSurfaceGeometry(Rect rect) {
    if (_embeddedSurfaceRect == rect) return;
    _embeddedSurfaceRect = rect;
    PlaybackRuntimeDiagnostics.overlayLog(
      'Embedded WebView native input exclusion rect=$rect',
    );
  }

  PlaybackSourceOption? _nextSourceAfterCurrent() {
    if (widget.sourceOptions.isEmpty) return null;
    final current = _controller.request.providerIndex ?? 0;
    for (final option in widget.sourceOptions) {
      if (option.index > current) return option;
    }
    return null;
  }

  void _maybeRecoverEmbeddedProviderError(PlaybackState playback) {
    if (!_usesEmbeddedWebPlayback) return;
    if (playback.status != PlaybackStatus.error) return;
    if (_sourceSwitchInFlight) return;
    final current = _controller.request.providerIndex ?? 0;
    if (_handledEmbeddedErrorProviderIndex == current) return;
    final next = _nextSourceAfterCurrent();
    if (next == null) return;

    _handledEmbeddedErrorProviderIndex = current;
    PlaybackRuntimeDiagnostics.overlayLog(
      'Embedded provider error fallback scheduled owner=PlayerScreen#$_instanceId '
      'current=$current next=${next.index} playback=${playback.status.name} '
      'mounted=$mounted sourceSwitchInFlight=$_sourceSwitchInFlight '
      'webGeneration=$_webOverlayGeneration',
    );
    _embeddedProviderFallbackTimer?.cancel();
    _embeddedProviderFallbackTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _sourceSwitchInFlight) {
        PlaybackRuntimeDiagnostics.overlayLog(
          'Embedded provider error fallback suppressed owner=PlayerScreen#$_instanceId '
          'current=$current next=${next.index} mounted=$mounted '
          'sourceSwitchInFlight=$_sourceSwitchInFlight '
          'webGeneration=$_webOverlayGeneration',
        );
        return;
      }
      PlaybackRuntimeDiagnostics.overlayLog(
        'Embedded provider error fallback firing owner=PlayerScreen#$_instanceId '
        'current=$current next=${next.index} mounted=$mounted '
        'sourceSwitchInFlight=$_sourceSwitchInFlight '
        'webGeneration=$_webOverlayGeneration',
      );
      unawaited(_switchSource(next));
    });
  }

  Widget _buildWebServerDrawer(
    PlaybackState playback, {
    double width = 360,
    VoidCallback? onClose,
    ValueChanged<PlaybackSourceOption>? onSourceSelected,
  }) {
    final selectedSourceIndex = _controller.request.providerIndex;
    final hasSelectedSource = widget.sourceOptions.any(
      (option) => option.index == selectedSourceIndex,
    );
    final sourceSummary = widget.sourceOptions
        .map((option) => '${option.index}:${option.provider}/${option.server}')
        .join(', ');
    PlaybackRuntimeDiagnostics.overlayLog(
      'WebView-specific server drawer build generation=$_webOverlayGeneration '
      'playback=${playback.status.name} sharedDrawer=$_drawer width=$width '
      'sourceCount=${widget.sourceOptions.length} '
      'selectedSourceIndex=$selectedSourceIndex '
      'selectedSourceValid=$hasSelectedSource '
      'providerLabel=$_providerLabel serverLabel=${_serverLabel ?? widget.request.streamResult?.providerGroup} '
      'sources=[$sourceSummary]',
    );
    return _RenderDiagnosticsProbe(
      label: 'web drawer root generation=$_webOverlayGeneration',
      child: _EmbeddedWebServerDrawer(
        generation: _webOverlayGeneration,
        width: width,
        sourceOptions: widget.sourceOptions,
        selectedSourceIndex: selectedSourceIndex,
        providerLabel: _providerLabel,
        serverLabel: _serverLabel ?? widget.request.streamResult?.providerGroup,
        onClose: onClose ?? () => Navigator.of(context).maybePop(),
        onSourceSelected: (option) {
          PlaybackRuntimeDiagnostics.overlayLog(
            'WebView-specific server tile tap generation=$_webOverlayGeneration '
            'index=${option.index} server=${option.server}',
          );
          if (onSourceSelected != null) {
            onSourceSelected(option);
          } else {
            unawaited(_switchSource(option));
          }
        },
      ),
    );
  }
}

enum _PlayerDrawer { none, settings, server }

enum _WebOverlayDrawer { none, server }

class _InteractionGeometryProbe extends SingleChildRenderObjectWidget {
  const _InteractionGeometryProbe({
    required this.label,
    required this.onGeometryChanged,
    required super.child,
  });

  final String label;
  final ValueChanged<Rect> onGeometryChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _InteractionGeometryRenderBox(
      label: label,
      onGeometryChanged: onGeometryChanged,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _InteractionGeometryRenderBox renderObject,
  ) {
    renderObject
      ..label = label
      ..onGeometryChanged = onGeometryChanged;
  }
}

class _InteractionGeometryRenderBox extends RenderProxyBox {
  _InteractionGeometryRenderBox({
    required this._label,
    required this._onGeometryChanged,
  });

  String _label;
  ValueChanged<Rect> _onGeometryChanged;
  Rect? _lastRect;

  set label(String value) {
    if (_label == value) return;
    _label = value;
    _lastRect = null;
  }

  set onGeometryChanged(ValueChanged<Rect> value) {
    _onGeometryChanged = value;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!attached) return;
    final transform = getTransformTo(null);
    final topLeft = MatrixUtils.transformPoint(transform, Offset.zero);
    final bottomRight = MatrixUtils.transformPoint(
      transform,
      Offset(size.width, size.height),
    );
    final rect = Rect.fromLTRB(
      math.min(topLeft.dx, bottomRight.dx),
      math.min(topLeft.dy, bottomRight.dy),
      math.max(topLeft.dx, bottomRight.dx),
      math.max(topLeft.dy, bottomRight.dy),
    );
    if (_lastRect == rect) return;
    _lastRect = rect;
    PlaybackRuntimeDiagnostics.overlayLog('$_label geometry rect=$rect');
    _onGeometryChanged(rect);
  }
}

class _RenderDiagnosticsProbe extends SingleChildRenderObjectWidget {
  const _RenderDiagnosticsProbe({required this.label, required super.child});

  final String label;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderDiagnosticsRenderBox(label);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderDiagnosticsRenderBox renderObject,
  ) {
    renderObject.label = label;
  }
}

class _RenderDiagnosticsRenderBox extends RenderProxyBox {
  _RenderDiagnosticsRenderBox(this._label);

  String _label;
  String? _lastLayoutSnapshot;
  String? _lastPaintSnapshot;

  set label(String value) {
    if (_label == value) return;
    _label = value;
    _lastLayoutSnapshot = null;
    _lastPaintSnapshot = null;
  }

  @override
  void performLayout() {
    super.performLayout();
    final snapshot = 'constraints=$constraints size=$size';
    if (_lastLayoutSnapshot == snapshot) return;
    _lastLayoutSnapshot = snapshot;
    PlaybackRuntimeDiagnostics.overlayLog('$_label layout $snapshot');
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final snapshot = 'offset=$offset size=$size';
    if (_lastPaintSnapshot == snapshot) return;
    _lastPaintSnapshot = snapshot;
    PlaybackRuntimeDiagnostics.overlayLog('$_label paint $snapshot');
  }
}

class _QualityOption {
  const _QualityOption({
    required this.quality,
    required this.url,
    required this.label,
  });

  final String quality;
  final String url;
  final String label;
}
