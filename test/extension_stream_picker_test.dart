import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/services/extensions/extension_repository.dart';
import 'package:nivio/services/extensions/extension_resolver.dart';
import 'package:nivio/services/extensions/nuvio_script_runtime.dart';
import 'package:nivio/services/extensions/stream_discovery.dart';
import 'package:nivio/services/streaming_service.dart';
import 'package:nivio/services/tmdb_service.dart';
import 'package:nivio/services/torrent/media_torrent_models.dart';
import 'package:nivio/services/torrent/torrent_models.dart';
import 'package:nivio/services/torrent/torrent_stream_service.dart';
import 'package:nivio/widgets/playback_picker.dart';
import 'package:nivio/widgets/stream_picker_sheet.dart';
import 'package:nivio/widgets/torrent_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _repo = ExtensionRepo(
  url: Uri.https('example.com', '/manifest.json'),
  name: 'Test repository',
  format: ExtensionFormat.javascript,
  entries: const [
    {'id': 'demo', 'name': 'Test provider', 'filename': 'demo.js'},
  ],
  enabledIds: {},
);

final _direct = StreamChoice.fromExtension(_repo.providers.single, {
  'url': 'https://example.com/movie.m3u8',
  'title': 'Direct link',
  'quality': '1080p',
  'headers': {'Referer': 'https://example.com', 'Range': 'bytes=0-20'},
  'subtitles': [
    {'file': 'https://example.com/en.vtt', 'lang': 'English'},
  ],
}, 0)!;

final _torrent = StreamChoice.fromExtension(_repo.providers.single, {
  'infoHash': '0123456789012345678901234567890123456789',
  'title': 'Torrent release',
  'size': '3 GB',
  'seeders': 17,
  'fileIdx': 2,
}, 1)!;

class _UnusedStreamingService implements StreamingService {
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
  _PickerTorrents() : super(tmdbService: _PickerTmdb());

  @override
  Future<List<TorrentResult>> searchMediaTorrents({
    required MediaTorrentQuery query,
    void Function(String status)? onStatus,
    bool rank = true,
  }) async => [_torrent.torrent!];
}

StreamDiscovery _readyDiscovery({required bool torrentsEnabled}) =>
    StreamDiscovery(
        media: const SearchResult(
          id: 10,
          mediaType: 'movie',
          title: 'Example movie',
        ),
        season: 1,
        episode: 1,
        streaming: _UnusedStreamingService(),
        repository: ExtensionRepository(),
        torrentsEnabled: torrentsEnabled,
        subDub: 'sub',
        preferredQuality: null,
      )
      ..choices.addAll([_direct, if (torrentsEnabled) _torrent])
      ..stop();

void main() {
  test('classifies each result and preserves the selected stream metadata', () {
    expect(_direct.isTorrent, isFalse);
    expect(_direct.direct!.headers, {'Referer': 'https://example.com'});
    expect(_direct.direct!.subtitles.single.lang, 'English');
    expect(_direct.direct!.isM3U8, isTrue);
    expect(_torrent.isTorrent, isTrue);
    expect(_torrent.torrent!.fileIndex, 2);
    expect(_torrent.byteSize, 3 * 1024 * 1024 * 1024);
    expect(_torrent.torrent!.link, startsWith('magnet:?xt=urn:btih:'));
  });

  testWidgets(
    'the Direct default filters the sheet and All shows both results',
    (tester) async {
      final discovery = _readyDiscovery(torrentsEnabled: true);
      final filters = <StreamFilter>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreamPickerSheet(
              discovery: discovery,
              initialFilter: StreamFilter.direct,
              onFilter: filters.add,
            ),
          ),
        ),
      );
      expect(find.text('Direct link'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Torrent release'), findsNothing);
      await tester.tap(find.text('All 2'));
      await tester.pump();
      expect(find.text('Torrent release'), findsOneWidget);
      expect(filters, [StreamFilter.all]);
      discovery.markFailed(_direct);
      await tester.pump();
      expect(find.textContaining('Couldn’t open this stream'), findsOneWidget);
      expect(find.byTooltip('Buffer & play'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      discovery.dispose();
    },
  );

  testWidgets(
    'a saved Torrent default falls back to Direct while torrents are disabled',
    (tester) async {
      final discovery = _readyDiscovery(torrentsEnabled: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreamPickerSheet(
              discovery: discovery,
              initialFilter: StreamFilter.torrents,
              onFilter: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Direct link'), findsOneWidget);
      expect(
        find
            .widgetWithText(PlaybackPickerTab, 'Torrents 0')
            .evaluate()
            .single
            .widget,
        isA<PlaybackPickerTab>().having(
          (segment) => segment.onTap,
          'onTap',
          isNull,
        ),
      );
      await tester.pumpWidget(const SizedBox());
      discovery.dispose();
    },
  );

  testWidgets('the picker route returns the stream selected from its card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final discovery = _readyDiscovery(torrentsEnabled: false);
    StreamPickerOutcome? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await StreamPickerSheet.show(
                  context,
                  discovery,
                  StreamFilter.direct,
                  (_) {},
                );
              },
              child: const Text('Choose a source'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose a source'));
    await tester.pumpAndSettle();
    expect(find.text('Choose stream'), findsOneWidget);
    expect(find.byType(PlaybackPickerFrame), findsOneWidget);
    expect(find.byType(PlaybackPickerRow), findsOneWidget);
    await tester.tap(find.text('Direct link'));
    await tester.pumpAndSettle();
    expect(picked?.choice, _direct);
    expect(picked?.result, _direct.direct);
    expect(find.text('Choose stream'), findsNothing);
    discovery.dispose();
  });

  testWidgets('the original torrent picker uses the shared frame and row', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'torrent_auto_select': false});
    (TorrentResult, dynamic, {bool automatic})? picked;
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
    expect(find.byType(PlaybackPickerFrame), findsOneWidget);
    expect(find.byType(PlaybackPickerRow), findsOneWidget);
    await tester.tap(find.text('Torrent release'));
    await tester.pumpAndSettle();
    expect(picked?.$1, _torrent.torrent);
    expect(picked?.automatic, isFalse);
  });

  test(
    'QuickJS runs a CommonJS provider with episode arguments and host modules',
    () async {
      final streams = await runNuvioScript(
        r'''
      const cheerio = require('cheerio-without-node-native');
      const crypto = require('crypto-js');
      module.exports.getStreams = async (id, type, season, episode) => {
        const $ = cheerio.load('<section><a href="https://example.com/episode.mp4">Watch</a></section>');
        return [{url: $('section').find('a').attr('href'),
          title: `${id}:${type}:${season}:${episode}:${crypto.MD5('hello')}`}];
      };
    ''',
        ['42', 'tv', 1, 2],
        const {},
      );
      expect(streams.single['url'], 'https://example.com/episode.mp4');
      expect(
        streams.single['title'],
        '42:tv:1:2:5d41402abc4b2a76b9719d911017c592',
      );
    },
    skip: Platform.environment['FLUTTER_QJS_NEXT_LIBRARY'] == null
        ? 'Set FLUTTER_QJS_NEXT_LIBRARY to the built QuickJS library to run the native fixture.'
        : false,
  );
}
