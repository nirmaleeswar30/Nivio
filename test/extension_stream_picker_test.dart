import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/playback/stream_choice.dart';
import 'package:nivio/services/playback/stream_discovery.dart';
import 'package:nivio/services/playback/stream_selection_settings.dart';
import 'package:nivio/services/m3u8_parser.dart';
import 'package:nivio/services/streaming_service.dart';
import 'package:nivio/services/tmdb_service.dart';
import 'package:nivio/services/torrent/anime_query_builder.dart';
import 'package:nivio/services/torrent/media_ranking.dart';
import 'package:nivio/services/torrent/media_torrent_models.dart';
import 'package:nivio/services/torrent/torrent_models.dart';
import 'package:nivio/services/torrent/torrent_stream_service.dart';
import 'package:nivio/widgets/stream_picker_sheet.dart';
import 'package:nivio/widgets/torrent_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _direct = StreamChoice.fromScraper('Test provider', {
  'url': 'https://example.com/movie.m3u8',
  'title': 'Direct link',
  'quality': '1080p',
  'headers': {'Referer': 'https://example.com', 'Range': 'bytes=0-20'},
  'subtitles': [
    {'file': 'https://example.com/en.vtt', 'lang': 'English'},
  ],
}, 0)!;

final _torrent = TorrentResult(
  title: 'Torrent release',
  link: 'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
  source: 'torrentio',
  sizeBytes: 3 * 1024 * 1024 * 1024,
  seeders: 17,
  leechers: 0,
  fileIndex: 2,
);

final _vidRock = StreamChoice(
  id: 'builtin:VidRock:0',
  providerId: 'builtin:VidRock',
  provider: 'VidRock',
  title: 'VidRock',
  quality: 'Nova',
  direct: StreamResult(
    url: 'https://example.com/master.m3u8',
    provider: 'VidRock',
    quality: 'Nova',
    isM3U8: true,
  ),
);

class _UnusedStreamingService implements StreamingService {
  @override
  int totalProvidersFor({required bool isAnime}) => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PickerTmdb implements TmdbService {
  @override
  Future<String?> getImdbId({
    required int tmdbId,
    required bool isMovie,
  }) async => 'tt1234567';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PickerTorrents extends TorrentStreamService {
  _PickerTorrents([List<TorrentResult>? results])
    : results = results ?? [_torrent],
      super(tmdbService: _PickerTmdb(), queryBuilder: _PickerAnimeQuery());

  final List<TorrentResult> results;

  @override
  Future<List<TorrentResult>> searchMediaTorrents({
    required MediaTorrentQuery query,
    void Function(String status)? onStatus,
    bool rank = true,
  }) async => results;

  @override
  Future<List<TorrentResult>> searchTorrents({
    required AnimeQuery query,
    void Function(String status)? onStatus,
  }) async => results;
}

class _PickerAnimeQuery extends AnimeQueryBuilder {
  @override
  Future<AnimeQuery> build(
    SearchResult media,
    int episode, {
    required int season,
    String resolution = '1080',
    List<String> exclusions = const [],
    int? absoluteEpisode,
  }) async => AnimeQuery(
    titles: [media.title!],
    episode: episode,
    season: season,
    resolution: resolution,
  );
}

TorrentResult _release(
  String label,
  int seeders, {
  int size = 0,
  String? type,
}) => TorrentResult(
  title: 'Example release $label',
  link: 'https://example.com/${Uri.encodeComponent('$label $seeders')}.torrent',
  seeders: seeders,
  leechers: 0,
  sizeBytes: size,
  source: 'torrentio',
  type: type,
);

StreamDiscovery _readyDiscovery() =>
    StreamDiscovery(
        media: const SearchResult(
          id: 10,
          mediaType: 'movie',
          title: 'Example movie',
        ),
        season: 1,
        episode: 1,
        streaming: _UnusedStreamingService(),
        subDub: 'sub',
        preferredQuality: null,
      )
      ..choices.add(_direct)
      ..stop();

void main() {
  test(
    'HLS resolution labels read variants from masters with alternate audio',
    () {
      expect(
        M3u8Parser.videoHeights('''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="en",NAME="English",URI="audio.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,AUDIO="en"
720.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080,AUDIO="en"
1080.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720,AUDIO="en"
720-other.m3u8
'''),
        [1080, 720],
      );
      expect(M3u8Parser.videoHeights('#EXTM3U\n#EXTINF:6\npart.ts'), isEmpty);
    },
  );

  test('a built-in scraper preserves the selected stream metadata', () {
    expect(_direct.direct.headers, {'Referer': 'https://example.com'});
    expect(_direct.direct.subtitles.single.lang, 'English');
    expect(_direct.direct.isM3U8, isTrue);
  });

  testWidgets('the direct picker filters built-in results', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final discovery = _readyDiscovery()
      ..choices.addAll([
        _vidRock.withMetadata(videoHeights: [1080, 720]),
        StreamChoice(
          id: 'builtin:VidRock:1',
          providerId: 'builtin:VidRock',
          title: 'VidRock alternate',
          provider: 'VidRock',
          quality: 'Luna',
          direct: _vidRock.direct,
        ),
      ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectStreamPickerSheet(
            discovery: discovery,
            isFullScreen: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Direct link'), findsOneWidget);
    expect(find.text('Torrent release'), findsNothing);
    expect(find.text('Auto Select Stream'), findsOneWidget);
    expect(find.byTooltip('Stream filters'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    final resolution = find.byType(DropdownButton<int>);
    expect(tester.widget<DropdownButton<int>>(resolution).value, 1080);
    expect(find.byTooltip('Stream settings'), findsOneWidget);
    expect(find.text('1080p / 720p'), findsOneWidget);
    expect(find.text('Nova'), findsOneWidget);
    final results = find
        .descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is ListView && widget.scrollDirection == Axis.vertical,
          ),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Auto · resolution unknown'),
      100,
      scrollable: results,
    );
    expect(find.text('Auto · resolution unknown'), findsOneWidget);

    tester.state<ScrollableState>(results).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(resolution);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2160p').last);
    await tester.pumpAndSettle();
    expect(find.text('Direct link'), findsNothing);
    expect(find.text('VidRock alternate'), findsOneWidget);
    await tester.tap(resolution);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any').last);
    discovery.markFailed(_direct);
    await tester.pumpAndSettle();
    expect(find.textContaining('Couldn’t open this stream'), findsOneWidget);
    discovery.markFailed(_direct, rateLimited: true);
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 429'), findsOneWidget);
    expect(find.textContaining('Couldn’t open this stream'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    discovery.dispose();
  });

  testWidgets('the picker route returns the stream selected from its card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final discovery = _readyDiscovery();
    StreamPickerOutcome? picked;
    var pickerReturned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await DirectStreamPickerSheet.show(context, discovery);
                pickerReturned = true;
              },
              child: const Text('Choose a source'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose a source'));
    await tester.pumpAndSettle();
    expect(find.text('Example movie'), findsOneWidget);
    expect(find.byType(DirectStreamPickerSheet), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(pickerReturned, isFalse);
    await tester.pumpAndSettle();
    expect(pickerReturned, isTrue);
    expect(picked, isNull);
    await tester.tap(find.text('Choose a source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Direct link'));
    await tester.pumpAndSettle();
    expect(picked?.choice, _direct);
    expect(picked?.result, _direct.direct);
    expect(picked?.preferredResolution, 1080);
    expect(find.byType(DirectStreamPickerSheet), findsNothing);
    discovery.dispose();
  });

  for (final duringPlayback in [false, true]) {
    testWidgets(
      duringPlayback
          ? 'the in-player torrent chooser waits for a tap and can be dismissed'
          : 'the original torrent picker returns the selected torrent',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'torrent_auto_select': duringPlayback,
        });
        (TorrentResult, dynamic, {bool automatic})? picked;
        var pickerReturned = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    picked = await TorrentPickerSheet.show(
                      context,
                      media: const SearchResult(
                        id: 10,
                        mediaType: 'movie',
                        title: 'Example movie',
                      ),
                      initialEpisode: 1,
                      initialSeason: 1,
                      initialResolution: '1080',
                      torrentStreamService: _PickerTorrents(),
                      autoSelect: duringPlayback ? false : null,
                    );
                    pickerReturned = true;
                  },
                  child: const Text('Open torrent picker'),
                ),
              ),
            ),
          ),
        );
        final open = find.text('Open torrent picker');
        final picker = find.byType(TorrentPickerSheet);
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(picker, findsOneWidget);

        if (duringPlayback) {
          await tester.pump(const Duration(seconds: 6));
          expect(picker, findsOneWidget);
          await tester.binding.handlePopRoute();
          await tester.pump();
          expect(pickerReturned, isFalse);
          await tester.pumpAndSettle();
          expect(pickerReturned, isTrue);
          expect(picked, isNull);
          await tester.tap(open);
          await tester.pumpAndSettle();
        }

        await tester.tap(find.text('Torrent release'));
        await tester.pumpAndSettle();
        expect(picked?.$1, _torrent);
        expect(picked?.automatic, isFalse);
      },
    );
  }

  test('torrent format boosts preserve resolution and seeder priority', () {
    final web = _release('1080p WEB-DL', 80);
    final remux = _release('1080p Remux', 70);
    final lowSeeds = _release('1080p Remux', 1);
    final offResolution = _release('2160p Remux', 100);
    final query = MediaTorrentQuery(title: 'Example movie', isMovie: true);

    expect(MediaRanking.rank([web, remux], query), [web, remux]);
    expect(
      MediaRanking.rank(
        [web, offResolution, lowSeeds, remux],
        query,
        preferredFormats: [
          RegExp(StreamFeature.remux.pattern, caseSensitive: false),
        ],
      ),
      [remux, web, lowSeeds, offResolution],
    );
  });

  for (final mode in [StreamSelectionMode.manual, StreamSelectionMode.match]) {
    testWidgets('${mode.label} uses boosted torrent results', (tester) async {
      final autoSelect = mode == StreamSelectionMode.match;
      SharedPreferences.setMockInitialValues({
        'torrent_auto_select': !autoSelect,
      });
      final media = autoSelect
          ? const SearchResult(
              id: 10,
              mediaType: 'movie',
              title: 'Example movie',
            )
          : const SearchResult(id: 10, mediaType: 'tv', name: 'Example show');
      final web = _release('1080p WEB-DL', 80);
      final remux = _release('1080p Remux', 70);
      final settings = StreamSelectionSettings(
        mode: mode,
      ).copyWith(customFeatures: {StreamFeature.remux});
      (TorrentResult, dynamic, {bool automatic})? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  picked = await TorrentPickerSheet.show(
                    context,
                    media: media,
                    initialEpisode: 1,
                    initialSeason: 1,
                    initialResolution: '1080',
                    torrentStreamService: _PickerTorrents([web, remux]),
                    preferredFormats: settings.torrentFormatPreferences,
                    autoSelect: autoSelect,
                  );
                },
                child: const Text('Open torrent picker'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open torrent picker'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text(remux.title)).dy,
        lessThan(tester.getTopLeft(find.text(web.title)).dy),
      );

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      if (!autoSelect) {
        expect(picked, isNull);
        expect(find.text('Auto Select Torrent'), findsOneWidget);
        await tester.tap(find.text(web.title));
        await tester.pumpAndSettle();
      }
      expect(picked?.$1, autoSelect ? remux : web);
      expect(picked?.automatic, autoSelect);
    });
  }

  for (final type in ['movie', 'tv', 'anime']) {
    testWidgets('the $type torrent picker honors the file size limit', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      const gib = 1024 * 1024 * 1024;
      final settings = const StreamSelectionSettings().copyWith(maxFileGb: 2);
      final media = SearchResult(
        id: 10,
        mediaType: type,
        title: 'Example title',
      );
      final oversized = _release('4K oversized', 100, size: 3 * gib);
      final unknown = _release('1080p unknown size', 90);
      final exact = _release('1080p at the limit', 80, size: 2 * gib);
      final pack = _release(
        '1080p season pack',
        70,
        size: 8 * gib,
        type: 'batch',
      );
      final search = _PickerTorrents([
        oversized,
        unknown,
        if (type == 'anime') pack else exact,
      ]);
      (TorrentResult, dynamic, {bool automatic})? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  picked = await TorrentPickerSheet.show(
                    context,
                    media: media,
                    initialEpisode: 1,
                    initialSeason: 1,
                    initialResolution: '1080',
                    torrentStreamService: search,
                    autoSelect: type != 'tv',
                    maxFileBytes: settings.maxFileBytes,
                  );
                },
                child: const Text('Open torrent picker'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open torrent picker'));
      await tester.pumpAndSettle();
      expect(find.text(oversized.title), findsNothing);
      expect(find.text(unknown.title), findsOneWidget);

      if (type == 'tv') {
        await tester.tap(find.text('Auto Select Torrent'));
      } else {
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
      }
      if (type == 'anime') {
        expect(picked, isNull);
        expect(find.textContaining('Auto Select Torrent'), findsNothing);
        await tester.tap(find.text(pack.title));
      }
      await tester.pumpAndSettle();
      expect(picked?.$1, type == 'anime' ? pack : exact);
      expect(picked?.automatic, type != 'anime');
    });
  }
}
