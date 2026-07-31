import 'dart:async';

import '../../../core/interfaces/watch_history_repository.dart';
import '../models/playback_request.dart';
import '../models/playback_state.dart';
import '../playback_engine.dart';

class PlaybackHistorySession {
  PlaybackHistorySession({
    required this.repository,
    required this.engine,
    required this.request,
    this.saveInterval = const Duration(seconds: 5),
  });

  final WatchHistoryRepository repository;
  final PlaybackEngine engine;
  PlaybackRequest request;
  final Duration saveInterval;

  Timer? _timer;
  bool _completedSaved = false;
  bool _disposed = false;
  Map<String, dynamic>? _existing;

  Future<PlaybackRequest> prepareRequest() async {
    if (!_tracksHistory) return request;
    final mediaId = request.numericMediaId;
    if (mediaId == null) return request;
    _existing = await repository.getWatchProgress(
      mediaId: mediaId,
      mediaType: request.mediaTypeName,
      seasonNumber: request.season,
      episodeNumber: request.episode,
    );
    final resume = androidResumePosition(
      _existing,
      season: request.season ?? 1,
      episode: request.episode ?? 1,
    );
    final preferredRequest = request.copyWith(
      providerIndex:
          request.providerIndex ??
          _integer(_existing?['preferredProviderIndex']),
      preferredAudioTrack:
          request.preferredAudioTrack ??
          _string(_existing?['preferredAudioTrack']),
      preferredSubtitleTrack:
          request.preferredSubtitleTrack ??
          _string(_existing?['preferredSubtitleTrack']),
      preferredQuality:
          request.preferredQuality ??
          _string(_existing?['preferredResolution']),
    );
    return resume > Duration.zero
        ? preferredRequest.copyWith(startPosition: resume)
        : preferredRequest;
  }

  Future<void> start() async {
    if (!_tracksHistory || _disposed) return;
    await _writeInitialEntryIfNeeded();
    engine.state.addListener(_onPlaybackChanged);
    _timer = Timer.periodic(saveInterval, (_) {
      if (engine.state.value.isPlaying) unawaited(saveProgress());
    });
  }

  void _onPlaybackChanged() {
    final state = engine.state.value;
    if (state.status == PlaybackStatus.completed && !_completedSaved) {
      _completedSaved = true;
      unawaited(saveProgress(markCompleted: true));
    }
  }

  Future<void> _writeInitialEntryIfNeeded() async {
    final existing = _existing;
    final changedEpisode =
        (request.mediaType == PlaybackMediaType.tv ||
            request.mediaType == PlaybackMediaType.anime) &&
        existing != null &&
        (_integer(existing['currentSeason']) != (request.season ?? 1) ||
            _integer(existing['currentEpisode']) != (request.episode ?? 1));
    final progress = _number(existing?['progressPercent']) ?? 0;
    if (existing == null || progress <= 0 || changedEpisode) {
      await _write(
        position: const Duration(seconds: 1),
        duration: const Duration(minutes: 120),
      );
    }
  }

  Future<void> saveProgress({
    bool markCompleted = false,
    String? audioTrack,
    String? subtitleTrack,
    String? resolution,
  }) async {
    if (!_tracksHistory || _disposed) return;
    final state = engine.state.value;
    var position = markCompleted ? state.duration : state.position;
    var duration = state.duration;
    if (duration <= Duration.zero || position <= Duration.zero) return;
    if (duration < position) duration = position + const Duration(minutes: 30);
    await _write(
      position: position,
      duration: duration,
      audioTrack: audioTrack,
      subtitleTrack: subtitleTrack,
      resolution: resolution,
    );
  }

  Future<void> _write({
    required Duration position,
    required Duration duration,
    String? audioTrack,
    String? subtitleTrack,
    String? resolution,
  }) {
    final isEpisode =
        request.mediaType == PlaybackMediaType.tv ||
        request.mediaType == PlaybackMediaType.anime;
    final payload = <String, dynamic>{
      'tmdbId': request.numericMediaId,
      'mediaType': request.mediaTypeName,
      'title': request.title,
      'posterPath': request.posterPath,
      'totalSeasons': request.totalSeasons,
      'totalEpisodes': request.totalEpisodes,
      'lastPositionSeconds': position.inSeconds,
      'totalDurationSeconds': duration.inSeconds,
      'preferredAudioTrack': audioTrack ?? request.preferredAudioTrack,
      'preferredSubtitleTrack': subtitleTrack ?? request.preferredSubtitleTrack,
      'preferredResolution': resolution ?? request.preferredQuality,
      'preferredProviderIndex': request.providerIndex,
    };
    if (isEpisode) {
      payload['currentSeason'] = request.season ?? 1;
      payload['currentEpisode'] = request.episode ?? 1;
    }
    return repository.saveWatchProgress(payload);
  }

  bool get _tracksHistory =>
      !request.isLive &&
      request.mediaType != PlaybackMediaType.liveTv &&
      request.numericMediaId != null;

  Future<void> dispose() async {
    if (_disposed) return;
    await saveProgress();
    _disposed = true;
    _timer?.cancel();
    engine.state.removeListener(_onPlaybackChanged);
  }

  static Duration androidResumePosition(
    Map<String, dynamic>? history, {
    required int season,
    required int episode,
  }) {
    if (history == null ||
        _integer(history['currentSeason']) != season ||
        _integer(history['currentEpisode']) != episode) {
      return Duration.zero;
    }
    final position = _integer(history['lastPositionSeconds']) ?? 0;
    final duration = _integer(history['totalDurationSeconds']) ?? 0;
    if (position <= 0 || duration <= 0 || position >= duration - 30) {
      return Duration.zero;
    }
    final cap = (duration - 45).clamp(0, duration).toInt();
    final safe = (position - 3).clamp(0, cap).toInt();
    return safe > 0 ? Duration(seconds: safe) : Duration.zero;
  }

  static int? _integer(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String? _string(Object? value) {
    final string = value?.toString().trim();
    return string == null || string.isEmpty ? null : string;
  }
}
