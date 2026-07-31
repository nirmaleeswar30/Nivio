import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivio_desktop/features/history/desktop_watch_history_repository.dart';
import 'package:nivio_desktop/features/history/watch_history_storage.dart';
import 'package:nivio_desktop/features/player/models/playback_request.dart';
import 'package:nivio_desktop/features/player/models/playback_state.dart';
import 'package:nivio_desktop/features/player/playback_engine.dart';
import 'package:nivio_desktop/features/player/player_controller.dart';

class MemoryWatchHistoryStorage extends ChangeNotifier
    implements WatchHistoryStorage {
  final Map<String, String> records = {};

  @override
  Listenable get changes => this;

  @override
  Iterable<String> get values => records.values;

  @override
  String? read(String key) => records[key];

  @override
  Future<void> write(String key, String value) async {
    records[key] = value;
    notifyListeners();
  }

  @override
  Future<void> delete(String key) async {
    records.remove(key);
    notifyListeners();
  }

  @override
  Future<void> clear() async {
    records.clear();
    notifyListeners();
  }
}

class HistoryFakePlaybackEngine implements PlaybackEngine {
  final ValueNotifier<PlaybackState> notifier = ValueNotifier(
    const PlaybackState(),
  );
  PlaybackRequest? loadedRequest;

  @override
  ValueListenable<PlaybackState> get state => notifier;

  @override
  Future<void> load(PlaybackRequest request) async => loadedRequest = request;

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> retry() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> selectAudioTrack(String trackId) async {}

  @override
  Future<void> selectSubtitleTrack(
    String trackId, {
    String? externalUrl,
  }) async {}

  @override
  Future<void> setSubtitleDelay(Duration delay) async {}

  @override
  Future<void> setSubtitleStyle(SubtitleStyle style) async {}

  @override
  Future<void> setDebanding(bool enabled) async {}

  @override
  Future<PlaybackDiagnostics> diagnostics() async =>
      const PlaybackDiagnostics(backend: 'fake');

  @override
  Future<String?> takeScreenshot() async => null;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

Map<String, dynamic> progress({
  int mediaId = 42,
  String mediaType = 'movie',
  int season = 1,
  int episode = 1,
  int totalSeasons = 1,
  int? totalEpisodes,
  required int position,
  required int duration,
}) => <String, dynamic>{
  'tmdbId': mediaId,
  'mediaType': mediaType,
  'title': 'History Test',
  'posterPath': '/poster.jpg',
  'currentSeason': season,
  'currentEpisode': episode,
  'totalSeasons': totalSeasons,
  'totalEpisodes': totalEpisodes,
  'lastPositionSeconds': position,
  'totalDurationSeconds': duration,
};

void main() {
  late MemoryWatchHistoryStorage storage;
  late DesktopWatchHistoryRepository repository;

  setUp(() {
    storage = MemoryWatchHistoryStorage();
    repository = DesktopWatchHistoryRepository.withStorage(storage);
  });

  tearDown(() {
    repository.dispose();
    storage.dispose();
  });

  test('uses Android movie completion threshold of 95 percent', () async {
    await repository.saveWatchProgress(progress(position: 949, duration: 1000));
    var saved = await repository.getWatchProgress(
      mediaId: 42,
      mediaType: 'movie',
    );
    expect(saved?['isCompleted'], isFalse);

    await repository.saveWatchProgress(progress(position: 950, duration: 1000));
    saved = await repository.getWatchProgress(mediaId: 42, mediaType: 'movie');
    expect(saved?['isCompleted'], isTrue);
  });

  test(
    'tracks TV episode completion separately from series completion',
    () async {
      await repository.saveWatchProgress(
        progress(
          mediaType: 'tv',
          episode: 2,
          totalEpisodes: 3,
          position: 950,
          duration: 1000,
        ),
      );
      var saved = await repository.getWatchProgress(
        mediaId: 42,
        mediaType: 'tv',
      );
      expect(saved?['isCompleted'], isFalse);
      expect((saved?['episodes'] as Map)['s1e2']['isCompleted'], isTrue);

      await repository.saveWatchProgress(
        progress(
          mediaType: 'tv',
          episode: 3,
          totalEpisodes: 3,
          position: 950,
          duration: 1000,
        ),
      );
      saved = await repository.getWatchProgress(mediaId: 42, mediaType: 'tv');
      expect(saved?['isCompleted'], isTrue);
    },
  );

  test('preserves Android anime persistence behavior', () async {
    await repository.saveWatchProgress(
      progress(
        mediaType: 'anime',
        episode: 2,
        totalEpisodes: 12,
        position: 950,
        duration: 1000,
      ),
    );

    final saved = await repository.getWatchProgress(
      mediaId: 42,
      mediaType: 'anime',
    );
    expect(saved?['isCompleted'], isTrue);
    expect(saved?['episodes'], isEmpty);
  });

  test(
    'clear watch history removes saved progress and notifies listeners',
    () async {
      var notifications = 0;
      void listener() => notifications++;
      repository.addListener(listener);
      addTearDown(() => repository.removeListener(listener));

      await repository.saveWatchProgress(
        progress(position: 120, duration: 1000),
      );
      expect(await repository.getWatchHistory(), isNotEmpty);

      await repository.clearWatchHistory();

      expect(await repository.getWatchHistory(), isEmpty);
      expect(notifications, greaterThanOrEqualTo(2));
    },
  );

  test('remove watch progress deletes the saved record', () async {
    await repository.saveWatchProgress(progress(position: 120, duration: 1000));
    expect(
      await repository.getWatchProgress(mediaId: 42, mediaType: 'movie'),
      isNotNull,
    );

    await repository.removeWatchProgress(mediaId: 42, mediaType: 'movie');

    expect(
      await repository.getWatchProgress(mediaId: 42, mediaType: 'movie'),
      isNull,
    );
  });

  test('resumes three seconds early for the matching episode', () async {
    await repository.saveWatchProgress(
      progress(
        mediaType: 'tv',
        season: 2,
        episode: 4,
        totalEpisodes: 8,
        position: 600,
        duration: 3600,
      ),
    );
    final engine = HistoryFakePlaybackEngine();
    final controller = DesktopPlayerController(
      engine: engine,
      watchHistoryRepository: repository,
      historySaveInterval: const Duration(hours: 1),
      request: const PlaybackRequest(
        mediaId: 'tv:42',
        title: 'History Test',
        mediaType: PlaybackMediaType.tv,
        source: 'https://example.com/episode.m3u8',
        season: 2,
        episode: 4,
        totalEpisodes: 8,
      ),
    );

    await controller.initialize();

    expect(engine.loadedRequest?.startPosition, const Duration(seconds: 597));
    await controller.close();
  });

  test(
    'does not resume the wrong episode or within the final 30 seconds',
    () async {
      await repository.saveWatchProgress(
        progress(
          mediaType: 'tv',
          season: 1,
          episode: 1,
          totalEpisodes: 2,
          position: 3580,
          duration: 3600,
        ),
      );
      final engine = HistoryFakePlaybackEngine();
      final controller = DesktopPlayerController(
        engine: engine,
        watchHistoryRepository: repository,
        historySaveInterval: const Duration(hours: 1),
        request: const PlaybackRequest(
          mediaId: 'tv:42',
          title: 'History Test',
          mediaType: PlaybackMediaType.tv,
          source: 'https://example.com/episode.m3u8',
          season: 1,
          episode: 2,
          totalEpisodes: 2,
        ),
      );

      await controller.initialize();

      expect(engine.loadedRequest?.startPosition, Duration.zero);
      await controller.close();
    },
  );

  test(
    'completed playback writes duration and leaves Continue Watching',
    () async {
      final engine = HistoryFakePlaybackEngine();
      final controller = DesktopPlayerController(
        engine: engine,
        watchHistoryRepository: repository,
        historySaveInterval: const Duration(hours: 1),
        request: const PlaybackRequest(
          mediaId: 'movie:42',
          title: 'History Test',
          mediaType: PlaybackMediaType.movie,
          source: 'https://example.com/movie.mp4',
        ),
      );
      await controller.initialize();
      engine.notifier.value = const PlaybackState(
        status: PlaybackStatus.completed,
        position: Duration(seconds: 1000),
        duration: Duration(seconds: 1000),
      );
      await Future<void>.delayed(Duration.zero);

      final all = await repository.getWatchHistory();
      expect(all.single['isCompleted'], isTrue);
      expect(all.where((item) => item['isCompleted'] != true), isEmpty);
      await controller.close();
    },
  );
}
