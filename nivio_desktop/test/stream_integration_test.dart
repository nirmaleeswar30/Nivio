import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivio_desktop/app/app.dart';
import 'package:nivio_desktop/core/interfaces/home_repository.dart';
import 'package:nivio_desktop/core/interfaces/watch_history_repository.dart';
import 'package:nivio_desktop/core/repositories/empty_watch_history_repository.dart';
import 'package:nivio_desktop/features/player/models/playback_request.dart';
import 'package:nivio_desktop/features/player/models/playback_state.dart';
import 'package:nivio_desktop/features/player/playback_engine.dart';
import 'package:nivio_desktop/features/player/playback_request_factory.dart';
import 'package:nivio_desktop/features/player/player_screen.dart';
import 'package:nivio_desktop/features/player/resolving_player_screen.dart';
import 'package:nivio_desktop/features/player/services/anime_stream_providers.dart';
import 'package:nivio_desktop/features/player/services/desktop_streaming_service.dart';
import 'package:nivio_desktop/features/player/services/provider_registry.dart';
import 'package:nivio_desktop/features/player/services/stream_resolver.dart';
import 'package:nivio_desktop/features/search/models/search_media_item.dart';
import 'package:nivio_desktop/features/library/models/library_models.dart';
import 'package:nivio_desktop/shared/models/iptv_channel.dart';
import 'package:nivio_desktop/shared/models/stream_result.dart';

final ThemeData _testTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  splashFactory: InkRipple.splashFactory,
);

class FakeHealthChecker implements StreamHealthChecker {
  FakeHealthChecker(this.check, {this.contentKind = StreamContentKind.hls});

  final bool Function(String source) check;
  final StreamContentKind contentKind;
  final List<String> checkedSources = [];
  final List<bool> hlsChecks = [];

  @override
  Future<StreamValidationResult> validate(
    String source,
    Map<String, String> headers, {
    bool isHls = false,
  }) async {
    checkedSources.add(source);
    hlsChecks.add(isHls);
    final ok = check(source);
    return StreamValidationResult(
      playable: ok,
      kind: ok ? contentKind : StreamContentKind.html,
      statusCode: ok ? 200 : 200,
      contentType: ok ? 'application/vnd.apple.mpegurl' : 'text/html',
      finalUrl: source,
      failureReason: ok ? null : 'HTML page returned instead of media',
    );
  }
}

class FakeAnimeProvider implements AnimeStreamProvider {
  FakeAnimeProvider({required this.name, required this.result});

  @override
  final String name;
  final StreamResult? result;
  int resolveCount = 0;
  int availableServersCount = 0;

  @override
  Future<List<String>> availableServers(PlaybackRequest request) async {
    availableServersCount++;
    return [name.toLowerCase()];
  }

  @override
  Future<StreamResult?> resolve(
    PlaybackRequest request, {
    required String server,
  }) async {
    resolveCount++;
    return result;
  }
}

class FakeRegisteredProvider implements RegisteredStreamProvider {
  FakeRegisteredProvider({
    required this.metadata,
    required this.capabilities,
    required this.source,
    required this.result,
  });

  @override
  final StreamProviderMetadata metadata;

  @override
  final StreamProviderCapabilities capabilities;

  final PlaybackSourceOption source;
  final StreamResult? result;
  int resolveCount = 0;

  @override
  Future<List<PlaybackSourceOption>> enumerateServers(
    PlaybackRequest request,
  ) async {
    return [source];
  }

  @override
  Map<String, String> requestHeaders(PlaybackRequest request) => const {};

  @override
  Future<StreamResolution?> resolve(
    PlaybackRequest request, {
    required PlaybackSourceOption source,
  }) async {
    resolveCount++;
    if (result == null) return null;
    return StreamResolution(
      result: result!,
      diagnostics: StreamProviderDiagnostics(
        providerId: metadata.id,
        providerName: metadata.displayName,
        server: source.server,
        capabilities: capabilities,
      ),
    );
  }

  @override
  bool supports(PlaybackRequest request) => true;
}

class FakeStreamResolver implements StreamResolver {
  PlaybackRequest? request;
  final List<PlaybackRequest> requests = [];
  int resolveCount = 0;

  @override
  Future<List<PlaybackSourceOption>> availableSources(
    PlaybackRequest request,
  ) async {
    return const [
      PlaybackSourceOption(
        index: 0,
        provider: 'Test',
        server: 'Primary',
        group: 'Test',
      ),
      PlaybackSourceOption(
        index: 1,
        provider: 'Test',
        server: 'Backup',
        group: 'Test',
      ),
    ];
  }

  @override
  Future<StreamResult> resolve(
    PlaybackRequest request, {
    StreamResolutionStatus? onStatus,
  }) async {
    this.request = request;
    requests.add(request);
    resolveCount++;
    onStatus?.call('Resolved for test');
    final url = request.providerIndex == null
        ? 'https://example.com/resolved.mp4'
        : 'https://example.com/resolved-${request.providerIndex}.mp4';
    return StreamResult(
      url: url,
      quality: 'auto',
      provider: 'Test',
      providerIndex: request.providerIndex,
    );
  }
}

class DeferredStreamResolver implements StreamResolver {
  final List<PlaybackRequest> requests = [];
  final List<Completer<StreamResult>> completions = [];

  @override
  Future<List<PlaybackSourceOption>> availableSources(
    PlaybackRequest request,
  ) async {
    return [
      PlaybackSourceOption(
        index: request.providerIndex ?? 0,
        provider: 'Deferred',
        server: 'Server',
        group: 'Deferred',
      ),
    ];
  }

  @override
  Future<StreamResult> resolve(
    PlaybackRequest request, {
    StreamResolutionStatus? onStatus,
  }) {
    requests.add(request);
    onStatus?.call('Deferred resolve');
    final completer = Completer<StreamResult>();
    completions.add(completer);
    return completer.future;
  }
}

class FakePlaybackEngine implements PlaybackEngine {
  final ValueNotifier<PlaybackState> notifier = ValueNotifier(
    const PlaybackState(status: PlaybackStatus.ready),
  );
  PlaybackRequest? loadedRequest;
  final List<PlaybackRequest> loadedRequests = [];
  int stopCount = 0;
  int disposeCount = 0;

  @override
  ValueListenable<PlaybackState> get state => notifier;

  @override
  Future<void> load(PlaybackRequest request) async {
    loadedRequest = request;
    loadedRequests.add(request);
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

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
  Future<void> stop() async {
    stopCount++;
  }
}

class PreferenceWatchHistoryRepository implements WatchHistoryRepository {
  PreferenceWatchHistoryRepository(this.progress);

  final Map<String, dynamic> progress;
  final List<Map<String, dynamic>> saved = [];

  @override
  Future<void> clearWatchHistory() async {}

  @override
  Future<Map<String, dynamic>?> getWatchProgress({
    required int mediaId,
    required String mediaType,
    int? seasonNumber,
    int? episodeNumber,
  }) async => progress;

  @override
  Future<List<Map<String, dynamic>>> getWatchHistory() async => [progress];

  @override
  Future<void> removeWatchProgress({
    required int mediaId,
    required String mediaType,
  }) async {}

  @override
  Future<void> saveWatchProgress(Map<String, dynamic> progress) async {
    saved.add(progress);
  }
}

class PlaybackHomeRepository implements HomeRepository {
  static const featured = SearchMediaItem(
    id: 'movie:550',
    title: 'Playback Hero',
    year: 1999,
    rating: 8.4,
    language: SearchLanguageFilter.english,
    mediaType: SearchMediaTypeFilter.movie,
    provider: 'N/A',
    genres: [],
    posterLabel: 'Playback Hero',
    overview: 'Test playback routing.',
    runtimeLabel: '2h',
  );

  @override
  Future<List<SearchMediaItem>> getFeaturedContent() async => [featured];

  @override
  Future<List<SearchMediaItem>> getHindiPicks() async => [];

  @override
  Future<List<SearchMediaItem>> getKoreanDramas() async => [];

  @override
  Future<List<SearchMediaItem>> getMalayalamPicks() async => [];

  @override
  Future<List<SearchMediaItem>> getPopularAnime() async => [];

  @override
  Future<List<SearchMediaItem>> getPopularMovies() async => [];

  @override
  Future<List<SearchMediaItem>> getPopularTv() async => [];

  @override
  Future<List<SearchMediaItem>> getRecommendationsForHistory(
    List<Map<String, dynamic>> history,
  ) async => [];

  @override
  Future<List<SearchMediaItem>> getTamilPicks() async => [];

  @override
  Future<List<SearchMediaItem>> getTeluguPicks() async => [];

  @override
  Future<List<SearchMediaItem>> getTopRatedMovies() async => [];

  @override
  Future<List<SearchMediaItem>> getTrendingAnime() async => [];

  @override
  Future<List<SearchMediaItem>> getTrendingMovies() async => [];

  @override
  Future<List<SearchMediaItem>> getTrendingTv() async => [];
}

void main() {
  group('PlaybackRequestFactory', () {
    test(
      'maps existing Continue Watching episode context without resuming',
      () {
        final request = PlaybackRequestFactory.fromHistory({
          'tmdbId': 42,
          'mediaType': 'tv',
          'title': 'Series',
          'currentSeason': 3,
          'currentEpisode': 7,
          'lastPositionSeconds': 900,
        });

        expect(request.mediaId, 'tv:42');
        expect(request.season, 3);
        expect(request.episode, 7);
        expect(request.startPosition, Duration.zero);
      },
    );

    test('maps saved playback preferences from Continue Watching history', () {
      final request = PlaybackRequestFactory.fromHistory({
        'tmdbId': 42,
        'mediaType': 'anime',
        'title': 'Anime',
        'currentSeason': 1,
        'currentEpisode': 4,
        'preferredProviderIndex': 12000,
        'preferredAudioTrack': 'audio-jpn',
        'preferredSubtitleTrack': 'sub-eng',
        'preferredResolution': '1080p',
      });

      expect(request.providerIndex, 12000);
      expect(request.preferredAudioTrack, 'audio-jpn');
      expect(request.preferredSubtitleTrack, 'sub-eng');
      expect(request.preferredQuality, '1080p');
    });

    test('maps completed downloads to their local media path', () {
      final item = LibraryDownloadItem(
        id: 'download-1',
        mediaId: 55,
        title: 'Series|||Episode 2',
        mediaType: 'tv',
        season: 1,
        episode: 2,
        savePath: '/tmp/episode-2.mp4',
        status: LibraryDownloadStatus.completed,
        createdAt: DateTime(2026),
      );

      final request = PlaybackRequestFactory.fromDownload(item);

      expect(request.source, '/tmp/episode-2.mp4');
      expect(request.mediaId, 'tv:55');
      expect(request.episode, 2);
    });

    test('maps IPTV channels as live direct sources', () {
      final request = PlaybackRequestFactory.fromIptv(
        IptvChannel(name: 'News', url: 'https://example.com/news.m3u8'),
      );

      expect(request.mediaType, PlaybackMediaType.liveTv);
      expect(request.isLive, isTrue);
      expect(request.source, 'https://example.com/news.m3u8');
    });
  });

  group('DesktopStreamingService', () {
    test(
      'ProviderRegistry preserves Android TMDB provider capabilities',
      () async {
        final registry = ProviderRegistry.androidParity(animeProviders: []);
        const request = PlaybackRequest(
          mediaId: 'movie:550',
          title: 'Movie',
          mediaType: PlaybackMediaType.movie,
        );

        final sources = await registry.sourcesFor(request);

        expect(sources.map((source) => source.provider), [
          'Nivio',
          'CastleTV',
          'MovieBox',
          'StreamFlix',
          'VidUp (FAST)',
          'VidLink',
          'VidCore (ACTIVE)',
        ]);
        expect(sources.first.directMedia, isTrue);
        expect(
          sources.skip(4),
          everyElement(
            isA<PlaybackSourceOption>().having(
              (source) => source.iframeOnly,
              'iframeOnly',
              isTrue,
            ),
          ),
        );
      },
    );

    test('download resolver skips iframe-only providers', () async {
      final direct = FakeRegisteredProvider(
        metadata: const StreamProviderMetadata(
          id: 'direct',
          displayName: 'Direct',
          priority: 0,
          kind: StreamProviderKind.direct,
          supportedMediaTypes: {PlaybackMediaType.movie},
        ),
        capabilities: const StreamProviderCapabilities(
          directMedia: true,
          iframe: false,
          hls: true,
          download: true,
        ),
        source: const PlaybackSourceOption(
          index: 0,
          provider: 'Direct',
          server: 'Primary',
          providerId: 'direct',
          directMedia: true,
          iframeOnly: false,
        ),
        result: StreamResult(
          url: 'https://example.com/direct.m3u8',
          quality: 'auto',
          provider: 'Direct',
          isM3U8: true,
        ),
      );
      final iframe = FakeRegisteredProvider(
        metadata: const StreamProviderMetadata(
          id: 'iframe',
          displayName: 'Iframe',
          priority: 10,
          kind: StreamProviderKind.iframe,
          supportedMediaTypes: {PlaybackMediaType.movie},
        ),
        capabilities: const StreamProviderCapabilities(
          directMedia: false,
          iframe: true,
          download: false,
        ),
        source: const PlaybackSourceOption(
          index: 1,
          provider: 'Iframe',
          server: 'Iframe',
          providerId: 'iframe',
          directMedia: false,
          iframeOnly: true,
        ),
        result: StreamResult(
          url: 'https://example.com/embed',
          quality: 'auto',
          provider: 'Iframe',
          isDirect: false,
          isIframe: true,
        ),
      );
      final service = DesktopStreamingService(
        providerRegistry: ProviderRegistry([direct, iframe]),
        healthChecker: FakeHealthChecker((url) => url.contains('direct')),
      );
      const request = PlaybackRequest(
        mediaId: 'movie:550',
        title: 'Movie',
        mediaType: PlaybackMediaType.movie,
      );

      final result = await service.resolveDownloadable(request);

      expect(result.provider, 'Direct');
      expect(result.isIframe, isFalse);
      expect(direct.resolveCount, 1);
      expect(iframe.resolveCount, 0);
    });

    test('download resolver respects selected downloadable server', () async {
      final first = FakeRegisteredProvider(
        metadata: const StreamProviderMetadata(
          id: 'first',
          displayName: 'First',
          priority: 0,
          kind: StreamProviderKind.direct,
          supportedMediaTypes: {PlaybackMediaType.movie},
        ),
        capabilities: const StreamProviderCapabilities(
          directMedia: true,
          iframe: false,
          hls: true,
          download: true,
        ),
        source: const PlaybackSourceOption(
          index: 0,
          provider: 'First',
          server: 'Primary',
          providerId: 'first',
        ),
        result: StreamResult(
          url: 'https://example.com/first.m3u8',
          quality: 'auto',
          provider: 'First',
          isM3U8: true,
        ),
      );
      final second = FakeRegisteredProvider(
        metadata: const StreamProviderMetadata(
          id: 'second',
          displayName: 'Second',
          priority: 10,
          kind: StreamProviderKind.direct,
          supportedMediaTypes: {PlaybackMediaType.movie},
        ),
        capabilities: const StreamProviderCapabilities(
          directMedia: true,
          iframe: false,
          hls: true,
          download: true,
        ),
        source: const PlaybackSourceOption(
          index: 1,
          provider: 'Second',
          server: 'Backup',
          providerId: 'second',
        ),
        result: StreamResult(
          url: 'https://example.com/second.m3u8',
          quality: 'auto',
          provider: 'Second',
          isM3U8: true,
        ),
      );
      final service = DesktopStreamingService(
        providerRegistry: ProviderRegistry([first, second]),
        healthChecker: FakeHealthChecker((_) => true),
      );
      const request = PlaybackRequest(
        mediaId: 'movie:550',
        title: 'Movie',
        mediaType: PlaybackMediaType.movie,
        providerIndex: 1,
      );

      final result = await service.resolveDownloadable(request);

      expect(result.provider, 'Second');
      expect(first.resolveCount, 0);
      expect(second.resolveCount, 1);
    });

    test('opens and classifies a direct HLS/IPTV source', () async {
      final health = FakeHealthChecker((_) => true);
      final service = DesktopStreamingService(healthChecker: health);
      const request = PlaybackRequest(
        mediaId: 'live:test',
        title: 'Live channel',
        mediaType: PlaybackMediaType.liveTv,
        source: 'https://example.com/live/channel.m3u8',
        isLive: true,
      );

      final result = await service.resolve(request);

      expect(result.provider, 'IPTV');
      expect(result.isM3U8, isTrue);
      expect(health.checkedSources, [request.source]);
    });

    test('falls through anime providers and rejects invalid sources', () async {
      final first = FakeAnimeProvider(
        name: 'First',
        result: StreamResult(
          url: 'https://example.com/broken.m3u8',
          quality: 'auto',
          provider: 'First',
        ),
      );
      final second = FakeAnimeProvider(
        name: 'Second',
        result: StreamResult(
          url: 'https://example.com/good.m3u8',
          quality: 'auto',
          provider: 'Second',
        ),
      );
      final health = FakeHealthChecker((url) => url.contains('good'));
      final service = DesktopStreamingService(
        animeProviders: [first, second],
        healthChecker: health,
      );
      const request = PlaybackRequest(
        mediaId: 'anime:21',
        title: 'Anime',
        mediaType: PlaybackMediaType.anime,
        season: 1,
        episode: 2,
      );

      final result = await service.resolve(request);

      expect(first.resolveCount, 1);
      expect(second.resolveCount, 1);
      expect(result.provider, 'Second');
      expect(health.hlsChecks, [isTrue, isTrue]);
    });

    test('reuses the source enumeration produced by resolution', () async {
      final provider = FakeAnimeProvider(
        name: 'Iframe',
        result: StreamResult(
          url: 'https://example.com/embed',
          quality: 'auto',
          provider: 'Iframe',
          isIframe: true,
        ),
      );
      final service = DesktopStreamingService(
        animeProviders: [provider],
        healthChecker: FakeHealthChecker((_) => true),
      );
      const request = PlaybackRequest(
        mediaId: 'anime:21',
        title: 'Anime',
        mediaType: PlaybackMediaType.anime,
        season: 1,
        episode: 1,
      );

      await service.resolve(request);
      final sources = await service.availableSources(request);

      expect(sources, hasLength(1));
      expect(provider.availableServersCount, 1);
    });

    test(
      'fallback from a selected provider does not wrap to earlier providers',
      () async {
        final first = FakeAnimeProvider(
          name: 'First',
          result: StreamResult(
            url: 'https://example.com/first.m3u8',
            quality: 'auto',
            provider: 'First',
          ),
        );
        final second = FakeAnimeProvider(
          name: 'Second',
          result: StreamResult(
            url: 'https://example.com/second-broken.m3u8',
            quality: 'auto',
            provider: 'Second',
          ),
        );
        final third = FakeAnimeProvider(
          name: 'Third',
          result: StreamResult(
            url: 'https://example.com/third-good.m3u8',
            quality: 'auto',
            provider: 'Third',
          ),
        );
        final service = DesktopStreamingService(
          animeProviders: [first, second, third],
          healthChecker: FakeHealthChecker((url) => url.contains('third-good')),
        );
        const request = PlaybackRequest(
          mediaId: 'anime:21',
          title: 'Anime',
          mediaType: PlaybackMediaType.anime,
          season: 1,
          episode: 1,
          providerIndex: 11000,
        );

        final result = await service.resolve(request);

        expect(first.resolveCount, 0);
        expect(second.resolveCount, 1);
        expect(third.resolveCount, 1);
        expect(result.provider, 'Third');
      },
    );

    test(
      'invalid saved provider index resets to first provider fallback',
      () async {
        final first = FakeAnimeProvider(
          name: 'First',
          result: StreamResult(
            url: 'https://example.com/first-good.m3u8',
            quality: 'auto',
            provider: 'First',
          ),
        );
        final service = DesktopStreamingService(
          animeProviders: [first],
          healthChecker: FakeHealthChecker((url) => url.contains('first-good')),
        );
        const request = PlaybackRequest(
          mediaId: 'anime:21',
          title: 'Anime',
          mediaType: PlaybackMediaType.anime,
          season: 1,
          episode: 1,
          providerIndex: 999999,
        );

        final result = await service.resolve(request);

        expect(first.resolveCount, 1);
        expect(result.provider, 'First');
      },
    );

    test(
      'rejects anime provider HTML responses before player launch',
      () async {
        final provider = FakeAnimeProvider(
          name: 'HtmlProvider',
          result: StreamResult(
            url: 'https://example.com/embed-page',
            quality: 'auto',
            provider: 'HtmlProvider',
          ),
        );
        final service = DesktopStreamingService(
          animeProviders: [provider],
          healthChecker: FakeHealthChecker(
            (_) => false,
            contentKind: StreamContentKind.html,
          ),
        );
        const request = PlaybackRequest(
          mediaId: 'anime:21',
          title: 'Anime',
          mediaType: PlaybackMediaType.anime,
          episode: 1,
        );

        await expectLater(
          service.resolve(request),
          throwsA(
            isA<StreamResolutionException>().having(
              (error) => error.message,
              'message',
              contains('HTML page returned instead of media'),
            ),
          ),
        );
      },
    );

    test('reports unavailable direct streams without freezing', () async {
      final service = DesktopStreamingService(
        healthChecker: FakeHealthChecker((_) => false),
      );
      const request = PlaybackRequest(
        mediaId: 'live:missing',
        title: 'Missing channel',
        mediaType: PlaybackMediaType.liveTv,
        source: 'https://example.com/missing.m3u8',
        isLive: true,
      );

      await expectLater(
        service.resolve(request),
        throwsA(
          isA<StreamResolutionException>().having(
            (error) => error.message,
            'message',
            contains('unavailable'),
          ),
        ),
      );
    });

    testWidgets('re-resolves playback when provider selection changes', (
      tester,
    ) async {
      final resolver = FakeStreamResolver();
      final engine = FakePlaybackEngine();
      const initial = PlaybackRequest(
        mediaId: 'anime:21',
        title: 'Anime',
        mediaType: PlaybackMediaType.anime,
        season: 1,
        episode: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme,
          home: ResolvingPlayerScreen(
            request: initial,
            resolver: resolver,
            engineFactory: () => engine,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(resolver.requests.map((request) => request.providerIndex), [null]);
      expect(engine.loadedRequest?.source, 'https://example.com/resolved.mp4');

      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme,
          home: ResolvingPlayerScreen(
            request: initial.copyWith(
              providerIndex: 12000,
              clearSource: true,
              clearStreamResult: true,
            ),
            resolver: resolver,
            engineFactory: () => engine,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(resolver.requests.map((request) => request.providerIndex), [
        null,
        12000,
      ]);
      expect(
        engine.loadedRequest?.source,
        'https://example.com/resolved-12000.mp4',
      );
      expect(engine.loadedRequests, hasLength(2));
      expect(engine.disposeCount, 0);
    });

    testWidgets(
      'iframe provider switch removes PlayerScreen while preserving session engine',
      (tester) async {
        final resolver = DeferredStreamResolver();
        final engine = FakePlaybackEngine();
        const initial = PlaybackRequest(
          mediaId: 'movie:550',
          title: 'Movie',
          mediaType: PlaybackMediaType.movie,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: _testTheme,
            home: ResolvingPlayerScreen(
              request: initial,
              resolver: resolver,
              engineFactory: () => engine,
              onClose: () {},
            ),
          ),
        );
        await tester.pump();

        resolver.completions.single.complete(
          StreamResult(
            url: 'https://example.com/embed-a',
            quality: 'auto',
            provider: 'Deferred',
            isDirect: false,
            isIframe: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PlayerScreen), findsOneWidget);
        expect(engine.loadedRequests, hasLength(1));

        await tester.pumpWidget(
          MaterialApp(
            theme: _testTheme,
            home: ResolvingPlayerScreen(
              request: initial.copyWith(
                providerIndex: 1,
                clearSource: true,
                clearStreamResult: true,
              ),
              resolver: resolver,
              engineFactory: () => engine,
              onClose: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(PlayerScreen), findsNothing);
        expect(engine.loadedRequests, hasLength(1));
        expect(engine.stopCount, 1);
        expect(engine.disposeCount, 0);

        resolver.completions.last.complete(
          StreamResult(
            url: 'https://example.com/embed-b',
            quality: 'auto',
            provider: 'Deferred',
            providerIndex: 1,
            isDirect: false,
            isIframe: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PlayerScreen), findsOneWidget);
        expect(engine.loadedRequests, hasLength(2));
        expect(engine.loadedRequest?.source, 'https://example.com/embed-b');
        expect(engine.disposeCount, 0);
      },
    );

    testWidgets(
      'ignores stale resolver completions and keeps the player engine alive',
      (tester) async {
        final resolver = DeferredStreamResolver();
        final engine = FakePlaybackEngine();
        const initial = PlaybackRequest(
          mediaId: 'anime:21',
          title: 'Anime',
          mediaType: PlaybackMediaType.anime,
          season: 1,
          episode: 1,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: _testTheme,
            home: ResolvingPlayerScreen(
              request: initial,
              resolver: resolver,
              engineFactory: () => engine,
              onClose: () {},
            ),
          ),
        );
        await tester.pump();

        expect(resolver.requests.map((request) => request.providerIndex), [
          null,
        ]);

        await tester.pumpWidget(
          MaterialApp(
            theme: _testTheme,
            home: ResolvingPlayerScreen(
              request: initial.copyWith(
                providerIndex: 12000,
                clearSource: true,
                clearStreamResult: true,
              ),
              resolver: resolver,
              engineFactory: () => engine,
              onClose: () {},
            ),
          ),
        );
        await tester.pump();

        resolver.completions.first.complete(
          StreamResult(
            url: 'https://example.com/stale.mp4',
            quality: 'auto',
            provider: 'Deferred',
          ),
        );
        await tester.pump();

        expect(engine.loadedRequests, isEmpty);

        resolver.completions.last.complete(
          StreamResult(
            url: 'https://example.com/current.mp4',
            quality: 'auto',
            provider: 'Deferred',
            providerIndex: 12000,
          ),
        );
        await tester.pumpAndSettle();

        expect(engine.loadedRequest?.source, 'https://example.com/current.mp4');
        expect(engine.loadedRequest?.providerIndex, 12000);
        expect(engine.disposeCount, 0);
      },
    );

    testWidgets('restores provider preference before stream resolution', (
      tester,
    ) async {
      final resolver = FakeStreamResolver();
      final engine = FakePlaybackEngine();
      final history = PreferenceWatchHistoryRepository({
        'currentSeason': 1,
        'currentEpisode': 1,
        'lastPositionSeconds': 0,
        'totalDurationSeconds': 1200,
        'preferredProviderIndex': 1,
        'preferredAudioTrack': 'audio-jpn',
        'preferredSubtitleTrack': 'sub-eng',
        'preferredResolution': '720p',
      });
      const initial = PlaybackRequest(
        mediaId: 'anime:21',
        title: 'Anime',
        mediaType: PlaybackMediaType.anime,
        season: 1,
        episode: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme,
          home: ResolvingPlayerScreen(
            request: initial,
            resolver: resolver,
            engineFactory: () => engine,
            watchHistoryRepository: history,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(resolver.request?.providerIndex, 1);
      expect(resolver.request?.preferredQuality, '720p');
      expect(resolver.request?.preferredAudioTrack, 'audio-jpn');
      expect(resolver.request?.preferredSubtitleTrack, 'sub-eng');
      expect(
        engine.loadedRequest?.source,
        'https://example.com/resolved-1.mp4',
      );
    });

    testWidgets(
      'server switching preserves controller-owned playback preferences',
      (tester) async {
        final resolver = FakeStreamResolver();
        final engine = FakePlaybackEngine();
        final history = PreferenceWatchHistoryRepository({
          'currentSeason': 1,
          'currentEpisode': 1,
          'lastPositionSeconds': 0,
          'totalDurationSeconds': 1200,
          'preferredAudioTrack': 'audio-eng',
          'preferredSubtitleTrack': 'sub-eng',
          'preferredResolution': '720p',
        });
        PlaybackRequest? switchedRequest;
        const initial = PlaybackRequest(
          mediaId: 'anime:21',
          title: 'Anime',
          mediaType: PlaybackMediaType.anime,
          season: 1,
          episode: 1,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: _testTheme,
            home: ResolvingPlayerScreen(
              request: initial,
              resolver: resolver,
              engineFactory: () => engine,
              watchHistoryRepository: history,
              onClose: () {},
              onNextEpisode: (request) => switchedRequest = request,
            ),
          ),
        );
        await tester.pumpAndSettle();

        engine.notifier.value = const PlaybackState(
          status: PlaybackStatus.error,
          errorMessage: 'Playback failed',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Switch Server'));
        await tester.pumpAndSettle();

        expect(switchedRequest?.providerIndex, 1);
        expect(switchedRequest?.source, isNull);
        expect(switchedRequest?.streamResult, isNull);
        expect(switchedRequest?.preferredQuality, '720p');
        expect(switchedRequest?.preferredAudioTrack, 'audio-eng');
        expect(switchedRequest?.preferredSubtitleTrack, 'sub-eng');
      },
    );
  });

  testWidgets('Home hero Play routes through resolver into the player', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final resolver = FakeStreamResolver();
    late FakePlaybackEngine engine;

    await tester.pumpWidget(
      NivioDesktopApp(
        requireAuthentication: false,
        homeRepository: PlaybackHomeRepository(),
        watchHistoryRepository: EmptyWatchHistoryRepository(),
        streamResolver: resolver,
        playbackEngineFactory: () {
          engine = FakePlaybackEngine();
          return engine;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('hero_watch_now_button')));
    await tester.pumpAndSettle();

    expect(resolver.request?.mediaId, 'movie:550');
    expect(resolver.request?.source, isNull);
    expect(engine.loadedRequest?.source, 'https://example.com/resolved.mp4');
    expect(
      find.byKey(const ValueKey('playback-surface-placeholder')),
      findsOneWidget,
    );
    expect(find.text('Nivio Desktop'), findsNothing);
  });
}
