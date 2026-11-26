import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/models/stream_size.dart';
import 'package:nivio/screens/onboarding_screen.dart';
import 'package:nivio/screens/stream_selection_screen.dart';
import 'package:nivio/services/playback/stream_choice.dart';
import 'package:nivio/services/playback/stream_discovery.dart';
import 'package:nivio/services/playback/stream_selection.dart';
import 'package:nivio/services/playback/stream_selection_settings.dart';
import 'package:nivio/services/m3u8_parser.dart';
import 'package:nivio/services/mp4_metadata.dart';
import 'package:nivio/services/streaming_service.dart';
import 'package:nivio/widgets/mobile_stream_picker.dart' show MobileStreamCard;
import 'package:nivio/widgets/stream_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

StreamChoice _choice(
  String id,
  String title,
  String quality, {
  String provider = 'builtin:Nivio',
  String? audio,
  String? group,
  int? bytes,
  List<StreamSubtitleTrack> subtitles = const [],
}) => StreamChoice(
  id: id,
  providerId: provider,
  provider: 'Example provider',
  title: title,
  quality: quality,
  audio: audio,
  bingeGroupHint: group,
  byteSize: bytes,
  direct: StreamResult(
    url: 'https://example.com/$id',
    quality: quality,
    provider: provider,
    subtitles: subtitles,
  ),
);

class _UnusedStreamingService implements StreamingService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Mp4StreamingService extends _UnusedStreamingService {
  @override
  int totalProvidersFor({required bool isAnime}) => 1;

  @override
  String getProviderName(int index, {required bool isAnime}) => 'Example';

  @override
  Future<StreamResult?> fetchStreamUrl({
    required SearchResult media,
    int season = 1,
    int episode = 1,
    int? absoluteEpisode,
    String? preferredQuality,
    int providerIndex = 0,
    bool autoSkipIntro = true,
    String subDubPreference = 'sub',
    String? preferredAudio,
    void Function(String)? onStatusUpdate,
    BuildContext? context,
    bool binge = false,
  }) async => StreamResult(
    url: 'https://example.com/movie.mp4',
    provider: 'Example',
    quality: '1080p',
    selectedAudio: 'English',
  );
}

void main() {
  test(
    'size badges use explicit bytes or an unambiguous release-name size',
    () {
      const gib = 1024 * 1024 * 1024;
      expect(
        StreamSize.format(StreamSize.fromTitle('Movie REMUX\n43.09 GB')!),
        '43.09 GB',
      );
      expect(StreamSize.fromTitle('Film 1080p 2.5 GiB'), (2.5 * gib).round());
      expect(StreamSize.fromTitle('Film.2.5GB_WEB-DL'), (2.5 * gib).round());
      expect(StreamSize.fromTitle('Film (2 GB / 4 GB)'), isNull);
      expect(StreamSize.fromTitle('Film 1080p 16 GBps'), isNull);
      expect(
        _choice(
          'sized',
          'Movie 43.09 GB',
          '1080p',
          bytes: gib,
        ).displaySizeBytes,
        gib,
      );
    },
  );

  test(
    'anime source priority migrates and saves separately from movies',
    () async {
      SharedPreferences.setMockInitialValues({
        'stream_selection_preferences': jsonEncode({
          'version': 2,
          'sourceOrder': [
            'builtin:CastleTV',
            'builtin:Miruro',
            'builtin:Animex',
            'https://example.com/manifest.json#retired',
          ],
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final original = StreamSelectionSettings.read(prefs);
      expect(original.sourceRank('builtin:Miruro', isAnime: true), 1);
      expect(original.sourceOrder, hasLength(3));
      await original
          .copyWith(animeSourceOrder: ['builtin:Animex', 'builtin:Miruro'])
          .save(prefs);
      final settings = StreamSelectionSettings.read(prefs);
      expect(settings.sourceRank('builtin:CastleTV'), 0);
      expect(settings.sourceRank('builtin:Miruro', isAnime: true), 1);
      expect(settings.sourceRank('builtin:Animex', isAnime: true), 0);
    },
  );

  test('the legacy anime source is used until a priority is saved', () async {
    SharedPreferences.setMockInitialValues({
      'preferred_anime_source': 'Animex',
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = StreamSelectionSettings.read(prefs);
    expect(settings.animeSourceOrder, ['builtin:Animex']);

    await settings
        .copyWith(animeSourceOrder: ['builtin:Miruro', 'builtin:Animex'])
        .save(prefs);
    expect(StreamSelectionSettings.read(prefs).animeSourceOrder, [
      'builtin:Miruro',
      'builtin:Animex',
    ]);
  });

  test('anime picker ranks Japanese audio alongside Sub', () async {
    final discovery = StreamDiscovery(
      media: const SearchResult(id: 1, mediaType: 'anime'),
      season: 1,
      episode: 2,
      streaming: _UnusedStreamingService(),
      subDub: 'sub',
      preferredQuality: '1080p',
      selection: const StreamSelectionSettings(
        mode: StreamSelectionMode.match,
        animeSourceOrder: ['builtin:Miruro', 'builtin:AniKoto'],
      ),
    );
    addTearDown(discovery.dispose);
    final aniKoto = _choice(
      'anikoto-720',
      'MegaPlay SUB 720p',
      '720p',
      provider: 'builtin:AniKoto',
    );
    final miruroSub = _choice(
      'miruro-sub-unknown',
      'Miruro (kickassanime)',
      'Cat',
      provider: 'builtin:Miruro (kickassanime)',
      audio: 'Sub',
    );
    final miruroJapanese = _choice(
      'miruro-japanese-1080',
      'Miruro (kickassanime)',
      'Vid',
      provider: 'builtin:Miruro (kickassanime)',
      audio: 'japanese',
    ).withMetadata(videoHeights: [1080, 720, 360]);
    final choices = [aniKoto, miruroSub, miruroJapanese];
    final expected = [miruroJapanese, aniKoto, miruroSub];

    expect(discovery.orderForPicker(choices, resolution: 1080), expected);
    expect(await discovery.policy.ranked(choices), expected);
  });

  testWidgets('the picker only inspects audio when the user taps the button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tracks = Completer<List<String>>();
    String? inspectedUrl;
    final discovery = StreamDiscovery(
      media: const SearchResult(id: 1, mediaType: 'movie'),
      season: 1,
      episode: 1,
      streaming: _Mp4StreamingService(),
      subDub: 'sub',
      preferredQuality: null,
      inspectAudioTracks: (stream, _) {
        inspectedUrl = stream.url;
        return tracks.future;
      },
    );
    final search = discovery.search();
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
    await search;
    expect(inspectedUrl, isNull);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Checking audio…'), findsNothing);

    await tester.tap(find.text('Check audio tracks'));
    await tester.pump();
    expect(inspectedUrl, 'https://example.com/movie.mp4');
    expect(find.text('Checking audio…'), findsOneWidget);
    expect(find.byType(DirectStreamPickerSheet), findsOneWidget);
    tracks.complete(['hin', 'und']);
    await tester.pumpAndSettle();
    expect(find.text('Hindi / Track 2 · Language unknown'), findsOneWidget);
    expect(find.text('Check audio tracks'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    discovery.dispose();
  });

  test('release-name audio hints stay separate from titles and subtitles', () {
    expect(
      StreamSelection.releaseAudioLanguages(
        'English Vinglish 2026 1080p WEB-DL [HIN + Tamil] [English Subs]',
      ),
      {'hi', 'ta'},
    );
    expect(
      StreamSelection.releaseAudioLabel(
        'Example.2160p.BluRay.REMUX.Hindi.English.x265',
      ),
      'Hindi / English',
    );
    expect(
      StreamSelection.releaseAudioLabel('Example 1080p BluRay [English DTS]'),
      'English',
    );
    expect(
      StreamSelection.releaseAudioLabel('Example 1080p BluRay [DTS]'),
      isNull,
    );
    expect(
      StreamSelection.releaseAudioLabel('English Vinglish 1080p WEBRip'),
      isNull,
    );
    expect(
      StreamSelection.releaseAudioLabel('The English Patient 1080p WEB-DL'),
      isNull,
    );
    expect(
      StreamSelection.releaseAudioLabel('Mirror - English subtitles 1080p'),
      isNull,
    );
    expect(
      StreamSelection.releaseAudioLabel('Mirror - English | Tamil'),
      'English / Tamil',
    );
    expect(
      StreamSelection.releaseAudioLabel('Example 1080p WEBRip [Dual Audio]'),
      'Dual audio',
    );
    expect(StreamSelection.releaseFormats('Example_2160p_BluRay_Remux'), [
      'Remux',
      'BluRay',
    ]);
  });

  test(
    'CastleTV audio labels before the resolution count for picker ranking',
    () {
      final builtIn = _choice(
        'castle720',
        'CastleTV',
        '720p',
        provider: 'builtin:CastleTV',
        audio: 'English',
      );
      final extension = _choice(
        'castle1080',
        'Castle TV - English, Hindi, Tamil, Telugu 1080p',
        '1080p',
        provider: 'repo#CastleTvProvider',
      );
      final discovery = StreamDiscovery(
        media: const SearchResult(id: 1368337, mediaType: 'movie'),
        season: 1,
        episode: 1,
        streaming: _UnusedStreamingService(),
        subDub: 'sub',
        preferredQuality: '1080p',
        preferredAudio: StreamSelection.pickerAudioPreference(
          'Original',
          savedTrack: 'English · DTS-HD Master Audio',
        ),
        selection: const StreamSelectionSettings(
          sourceOrder: ['builtin:CastleTV', 'repo#CastleTvProvider'],
        ),
      );
      addTearDown(discovery.dispose);
      expect(discovery.orderForPicker([builtIn, extension], resolution: 1080), [
        extension,
        builtIn,
      ]);
      expect(extension.pickerAudioLabel, 'English / Hindi / Tamil / Telugu');
    },
  );

  test(
    'autoplay gives name and track language matches equal priority',
    () async {
      final nameMatch = _choice(
        'named',
        'Example 1080p WEB-DL [Hindi]',
        '1080p',
        audio: 'English',
      );
      final verifiedHindi = _choice(
        'verified',
        'Example',
        '720p',
      ).withMetadata(audioTracks: ['hin']);
      final contradicted = _choice(
        'other',
        'Example 1080p WEBRip [Hindi]',
        '1080p',
      ).withMetadata(audioTracks: ['eng']);
      final policy = StreamSelection(
        const StreamSelectionSettings(mode: StreamSelectionMode.match),
        audio: 'Hindi',
        animeAudio: 'sub',
        isAnime: false,
      );
      expect(await policy.ranked([nameMatch, contradicted, verifiedHindi]), [
        nameMatch,
        verifiedHindi,
      ]);
      expect(nameMatch.pickerAudioLabel, 'Hindi');
      expect(contradicted.pickerAudioLabel, 'English');
      expect(policy.meetsAutoplayAudioPreference(nameMatch), isTrue);
      expect(_choice('4k', 'Example.4K.REMUX', 'Unknown').knownResolutions, [
        2160,
      ]);
    },
  );

  test(
    'verified multilingual tracks override the provider audio label',
    () async {
      final reportedEnglish = _choice(
        'english',
        'Film',
        '1080p',
        audio: 'English',
      );
      final withHindi = reportedEnglish.withMetadata(
        audioTracks: ['eng', 'hin'],
      );
      final advertisedHindi = _choice('adv', 'Film', '1080p', audio: 'Hindi');
      final confirmedEnglish = _choice(
        'verified',
        'Film',
        '1080p',
        audio: 'Hindi',
      ).withMetadata(audioTracks: ['eng']);
      final policy = StreamSelection(
        const StreamSelectionSettings(mode: StreamSelectionMode.match),
        audio: 'Hindi',
        animeAudio: 'sub',
        isAnime: false,
      );

      expect(reportedEnglish.pickerAudioLabel, 'English');
      expect(withHindi.pickerAudioLabel, 'English / Hindi');
      expect(policy.meetsAutoplayAudioPreference(withHindi), isTrue);
      expect(policy.eligible(reportedEnglish), isTrue);
      expect(policy.eligible(confirmedEnglish), isFalse);
      expect(
        await policy.ranked([advertisedHindi, withHindi, confirmedEnglish]),
        [advertisedHindi, withHindi],
      );
    },
  );

  test('HLS uses the rendition language and falls back to its name', () {
    expect(
      M3u8Parser.audioLanguages('''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,NAME="English, stereo",GROUP-ID="audio",LANGUAGE="en"
#EXT-X-MEDIA:TYPE=AUDIO,NAME="Hindi",GROUP-ID="audio",LANGUAGE="und"
#EXT-X-MEDIA:TYPE=SUBTITLES,NAME="Tamil",GROUP-ID="subs",LANGUAGE="ta"
'''),
      ['en', 'Hindi'],
    );
  });

  test(
    'MP4 reads audio and video metadata even when sample tables are large',
    () {
      List<int> box(String type, List<int> payload, {int? size}) {
        final length = ByteData(4)..setUint32(0, size ?? payload.length + 8);
        return [...length.buffer.asUint8List(), ...type.codeUnits, ...payload];
      }

      List<int> track(String handler, String language, {int version = 0}) {
        final offset = version == 0 ? 20 : 32;
        final value = language.codeUnits.fold(
          0,
          (bits, code) => bits * 32 + code - 96,
        );
        final header = ByteData(offset + 2)
          ..setUint8(0, version)
          ..setUint16(offset, value);
        return box(
          'trak',
          box('mdia', [
            ...box('mdhd', header.buffer.asUint8List()),
            ...box('hdlr', [...List.filled(8, 0), ...handler.codeUnits]),
          ]),
        );
      }

      final prefix = Uint8List.fromList([
        ...box('ftyp', 'isom'.codeUnits),
        ...box('mdat', [], size: 1000000),
      ]);
      expect(Mp4Metadata.moviePosition(prefix), (
        offset: 1000012,
        complete: false,
      ));
      final dimensions = ByteData(28)
        ..setUint16(24, 1920)
        ..setUint16(26, 1080);
      final description = box('stsd', [
        ...[0, 0, 0, 0, 0, 0, 0, 1],
        ...box('avc1', dimensions.buffer.asUint8List()),
      ]);
      final video = box(
        'trak',
        box('mdia', [
          ...box('hdlr', [...List.filled(8, 0), ...'vide'.codeUnits]),
          ...box('minf', box('stbl', description)),
          ...box('free', [], size: 4096),
          ...List.filled(4096 - 8, 0),
        ]),
      );
      final movie = Uint8List.fromList(
        box('moov', [
          ...video,
          ...track('soun', 'eng'),
          ...track('soun', 'hin', version: 1),
        ]),
      );
      expect(Mp4Metadata.moviePosition(movie), (offset: 0, complete: true));
      expect(Mp4Metadata.audioLanguages(movie, 0), ['eng', 'hin']);
      expect(Mp4Metadata.videoHeights(movie, 0), [1080]);
      expect(
        Mp4Metadata.videoHeights(Uint8List.sublistView(movie, 0, 128), 0),
        [1080],
      );
      expect(
        Mp4Metadata.videoHeights(Uint8List.sublistView(movie, 0, 20), 0),
        isEmpty,
      );
      expect(
        Mp4Metadata.audioLanguages(Uint8List.sublistView(movie, 0, 20), 0),
        isEmpty,
      );
    },
  );

  test(
    'direct picker ranks preferred audio and subtitles ahead of resolution',
    () {
      final wrongAudio = _choice('other', 'Film', '1080p', audio: 'French');
      final unknown = _choice('unknown', 'Film', '1080p');
      final audio = _choice('audio', 'Film', '1080p', audio: 'English');
      final both = _choice(
        'both',
        'Film',
        '720p',
        audio: 'en-US',
        subtitles: [
          StreamSubtitleTrack(
            url: 'https://example.com/es.vtt',
            lang: 'es-419',
          ),
        ],
      );
      final discovery = StreamDiscovery(
        media: const SearchResult(id: 1, mediaType: 'movie'),
        season: 1,
        episode: 1,
        streaming: _UnusedStreamingService(),
        subDub: 'sub',
        preferredQuality: '1080p',
        preferredAudio: 'English',
        preferredSubtitle: 'Spanish',
      );
      addTearDown(discovery.dispose);
      expect(
        discovery.orderForPicker([
          wrongAudio,
          unknown,
          audio,
          both,
        ], resolution: 1080),
        [both, audio, unknown, wrongAudio],
      );
      expect(discovery.policy.hasPreferredSubtitles(both), isTrue);
      expect(discovery.policy.hasPreferredSubtitles(audio), isFalse);
      expect(StreamSelection.matchesLanguage('French', 'English'), isFalse);
      expect(StreamSelection.matchesLanguage('English (CC)', 'en-US'), isTrue);
    },
  );

  testWidgets(
    'the direct picker ranks 1080p Tamil from the title ahead of verified 720p Tamil',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const settings = StreamSelectionSettings(
        preset: StreamPreset.balanced,
        sourceOrder: ['builtin:CastleTV', 'repo#4khdhub'],
      );
      final castle = _choice(
        'castle',
        'CastleTV',
        '720p',
        provider: 'builtin:CastleTV',
        audio: 'Tamil',
      );
      final hub = _choice(
        'hub',
        'The Odyssey 1080p BluRay REMUX [Hindi-Tamil-Telugu DDP 5.1 + English DTS]',
        '1080p',
        provider: 'repo#4khdhub',
      );
      final english = castle.withMetadata(audioTracks: ['eng']);
      final named720 = _choice(
        'named720',
        'The Odyssey 720p WEBRip [Tamil]',
        '720p',
      );
      final discovery = StreamDiscovery(
        media: const SearchResult(id: 1368337, mediaType: 'movie'),
        season: 1,
        episode: 1,
        streaming: _UnusedStreamingService(),
        subDub: 'sub',
        preferredQuality: '1080p',
        preferredAudio: StreamSelection.pickerAudioPreference(
          'Tamil',
          savedTrack: 'English · DDP5.1',
        ),
        selection: settings,
      );
      addTearDown(discovery.dispose);

      expect(hub.pickerAudioLabel, 'Hindi / Tamil / Telugu / English');
      expect(
        discovery.orderForPicker([
          castle,
          hub,
          named720,
          english,
        ], resolution: 1080),
        [hub, castle, named720, english],
      );
      expect(discovery.orderForPicker([castle, hub], resolution: 720), [
        castle,
        hub,
      ]);
      expect(
        StreamSelection.pickerAudioPreference(
          'Original',
          savedTrack: 'English',
        ),
        'English',
      );

      discovery.choices.addAll([castle, hub]);
      discovery.stop();
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
      final cards = tester.widgetList<MobileStreamCard>(
        find.byType(MobileStreamCard),
      );
      expect(cards.map((card) => card.title), [hub.title, castle.title]);
      expect(cards.first.preferred, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'Max Quality falls back across resolutions while keeping the audio and size limits',
    () async {
      final selection = StreamSelection(
        const StreamSelectionSettings(
          mode: StreamSelectionMode.match,
          preset: StreamPreset.maxQuality,
          presetOptions: {
            StreamPreset.maxQuality: StreamPresetOptions(maxFileGb: 5),
          },
        ),
        audio: 'English',
        animeAudio: 'sub',
        isAnime: false,
      );
      final acceptable = _choice(
        'sd',
        'Film WEB-DL',
        '720p',
        audio: 'en-US',
        bytes: 3000000000,
      );
      final choices = [
        _choice(
          'too-large',
          'Film BluRay',
          '4K',
          audio: 'English',
          bytes: 5 * 1073741824 + 1,
        ),
        _choice(
          'wrong-audio',
          'Film BluRay',
          '4K',
          audio: 'French',
          bytes: 2000000000,
        ).withMetadata(audioTracks: ['fra']),
        _choice(
          'cam',
          'Film HDCAM',
          '1080p',
          audio: 'English',
          bytes: 2000000000,
        ),
        _choice('unknown-size', 'Film WEBRip', '1080p', audio: 'English'),
        acceptable,
      ];
      expect(await selection.ranked(choices), [acceptable]);
    },
  );

  test('the direct picker reorders providers as better resolutions arrive', () {
    final movieBox = _choice('moviebox', 'Movie', '480p', provider: 'moviebox');
    final vidRock = _choice('vidrock', 'Movie', 'Nova', provider: 'vidrock');
    final nivio = _choice('nivio', 'Movie', '1080p');
    final discovery = StreamDiscovery(
      media: const SearchResult(id: 1, mediaType: 'movie'),
      season: 1,
      episode: 1,
      streaming: _UnusedStreamingService(),
      subDub: 'sub',
      preferredQuality: '1080p',
      selection: const StreamSelectionSettings(
        sourceOrder: ['moviebox', 'vidrock', 'builtin:Nivio'],
      ),
    )..choices.addAll([movieBox, vidRock]);
    addTearDown(discovery.dispose);
    List<StreamChoice> ranked() =>
        discovery.orderForPicker(discovery.choices, resolution: 1080);

    expect(ranked(), [movieBox, vidRock]);
    final inspected = vidRock.withMetadata(videoHeights: [720]);
    discovery.choices[1] = inspected;
    expect(ranked(), [inspected, movieBox]);
    discovery.choices.add(nivio);
    expect(ranked(), [nivio, inspected, movieBox]);
  });

  test(
    'preset, source order, and binge group produce distinct ranks',
    () async {
      const settings = StreamSelectionSettings(
        mode: StreamSelectionMode.match,
        sourceOrder: ['repo#abc', 'builtin:Nivio'],
      );
      final selection = StreamSelection(
        settings,
        audio: 'Original',
        animeAudio: 'sub',
        isAnime: false,
      );
      final extension = _choice(
        'extension',
        'S01E02 WEB-DL',
        '1080p',
        provider: 'repo#abc',
      );
      final builtIn = _choice(
        'builtin',
        'S01E02 WEB-DL',
        '1080p',
        group: 'release',
      );
      final lower = _choice(
        'lower',
        'S01E02 WEB-DL',
        '720p',
        provider: 'repo#abc',
      );
      final previous = _choice(
        'prev',
        'S01E01 WEB-DL',
        '1080p',
        group: 'release',
      );
      expect(await selection.ranked([lower, builtIn, extension]), [
        extension,
        builtIn,
        lower,
      ]);
      expect(
        await selection.ranked([
          lower,
          builtIn,
          extension,
        ], bingeGroup: previous.bingeGroup),
        [builtIn, extension, lower],
      );
    },
  );

  test('regex override matches release labels and respects blocks', () async {
    const settings = StreamSelectionSettings(
      mode: StreamSelectionMode.match,
      regex: r'720p.*WEB-DL',
    );
    final selection = StreamSelection(
      settings,
      audio: 'Original',
      animeAudio: 'sub',
      isAnime: false,
    );
    final match = _choice('match', 'Film WEB-DL MPEG-TS', '720p');
    final candidates = [
      _choice('other', 'Film WEB-DL', '1080p'),
      match,
      _choice('blocked', 'Film WEB-DL CAM', '720p'),
    ];
    expect(await selection.ranked(candidates), [match]);
    expect(await selection.ranked([candidates.first]), isEmpty);
    expect(validateStreamRegex('['), isNotNull);
  });

  test('each preferred format promotes a matching release', () async {
    const samples = {
      StreamFeature.webSources: 'Film WEBRip',
      StreamFeature.webDl: 'Film WEB-DL',
      StreamFeature.bluRayQuality: 'Film BDRip',
      StreamFeature.bluRay: 'Film BluRay',
      StreamFeature.remux: 'Film Remux',
      StreamFeature.hevc: 'Film H.265',
      StreamFeature.avc: 'Film H.264',
      StreamFeature.hdr: 'Film HDR10+',
      StreamFeature.dolbyVision: 'Film Dolby Vision',
      StreamFeature.dolbyAtmosDts: 'Film DTS:X',
    };
    final untagged = _choice('untagged', 'Film', '1080p');
    for (final feature in StreamFeature.values) {
      final tagged = _choice(feature.name, samples[feature]!, '1080p');
      final selection = StreamSelection(
        const StreamSelectionSettings(
          mode: StreamSelectionMode.match,
          preset: StreamPreset.dataSaver,
        ).copyWith(customFeatures: {feature}),
        audio: 'Original',
        animeAudio: 'sub',
        isAnime: false,
      );
      expect(await selection.ranked([untagged, tagged]), [tagged, untagged]);
    }
  });

  test('former built-in boosts migrate and can be turned off', () async {
    SharedPreferences.setMockInitialValues({
      'stream_selection_preferences': jsonEncode({
        'mode': 'match',
        'presetOptions': {
          'balanced': {
            'features': ['avc'],
          },
          'maxQuality': {
            'features': ['hdr'],
          },
        },
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final saved = StreamSelectionSettings.read(prefs);
    expect(saved.features, {
      StreamFeature.avc,
      StreamFeature.webDl,
      StreamFeature.bluRay,
    });
    expect(saved.copyWith(preset: StreamPreset.maxQuality).features, {
      StreamFeature.hdr,
      StreamFeature.remux,
    });

    await saved.copyWith(customFeatures: {}).save(prefs);
    final restored = StreamSelectionSettings.read(prefs);
    expect(restored.features, isEmpty);
    final selection = StreamSelection(
      restored,
      audio: 'Original',
      animeAudio: 'sub',
      isAnime: false,
    );
    final choices = [
      _choice('plain', 'Film', '1080p'),
      _choice('web', 'Film WEB-DL', '1080p'),
    ];
    expect(await selection.ranked(choices), choices);
  });

  testWidgets('resolution priority keeps actions visible on a short phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 390);
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: StreamPickerSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final customise = find.text('Customise');
    await tester.ensureVisible(customise);
    await tester.pumpAndSettle();
    await tester.tap(customise);
    await tester.pumpAndSettle();
    final priority = find.text('Resolution priority');
    await tester.ensureVisible(priority);
    await tester.pumpAndSettle();
    await tester.tap(priority);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Save').hitTestable();
    expect(save, findsOneWidget);
    final moveDown = find.descendant(
      of: find.widgetWithText(ListTile, '1080p'),
      matching: find.byTooltip('Move down'),
    );
    await tester.tap(moveDown);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('720p')).dy,
      lessThan(tester.getTopLeft(find.text('1080p')).dy),
    );
    await tester.drag(find.byType(ReorderableListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(find.text('480p').hitTestable(), findsOneWidget);
    expect(save, findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(StreamSelectionSettings.read(prefs).resolutions.take(2), [
      720,
      1080,
    ]);
  });

  test(
    'all regex presets compile and No REMUX/HDR keeps clean releases',
    () async {
      for (final preset in StreamRegexPreset.values) {
        expect(
          validateStreamRegex(preset.pattern),
          isNull,
          reason: preset.label,
        );
      }
      final selection = StreamSelection(
        StreamSelectionSettings(
          mode: StreamSelectionMode.match,
          regex: StreamRegexPreset.noRemuxHdr.pattern,
        ),
        audio: 'Original',
        animeAudio: 'sub',
        isAnime: false,
      );
      final clean = _choice('clean', 'Film WEBRip x264', '1080p');
      expect(
        await selection.ranked([
          _choice('remux', 'Film REMUX', '1080p'),
          _choice('hdr', 'Film hdr10+', '1080p'),
          clean,
        ]),
        [clean],
      );
    },
  );

  testWidgets(
    'playback settings expose and save formats and all regex presets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: StreamPickerSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> tapVisible(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tapVisible(find.text('Customise'));
      const defaultFeatures = {
        StreamPreset.balanced: {StreamFeature.webDl, StreamFeature.bluRay},
        StreamPreset.maxQuality: {
          StreamFeature.hdr,
          StreamFeature.dolbyVision,
          StreamFeature.remux,
        },
        StreamPreset.dataSaver: {StreamFeature.hevc},
      };
      for (final preset in defaultFeatures.keys) {
        await tapVisible(find.text(preset.label));
        for (final feature in StreamFeature.values) {
          final chip = find.widgetWithText(FilterChip, feature.label);
          expect(
            tester.widget<FilterChip>(chip).selected,
            defaultFeatures[preset]!.contains(feature),
          );
        }
      }
      await tapVisible(
        find.widgetWithText(FilterChip, StreamFeature.avc.label),
      );

      await tapVisible(find.text('Advanced'));
      await tapVisible(find.text('Custom Regex Override'));
      await tapVisible(find.byTooltip('Choose a regex preset'));
      expect(
        find.byType(CheckedPopupMenuItem<StreamRegexPreset>),
        findsNWidgets(13),
      );
      await tapVisible(
        find.widgetWithText(
          CheckedPopupMenuItem<StreamRegexPreset>,
          StreamRegexPreset.noRemuxHdr.label,
        ),
      );
      await tapVisible(find.text('Save'));

      final prefs = await SharedPreferences.getInstance();
      final saved = StreamSelectionSettings.read(prefs);
      expect(saved.features, contains(StreamFeature.avc));
      expect(saved.regex, StreamRegexPreset.noRemuxHdr.pattern);
    },
  );

  test(
    'fastest mode returns a lower-ranked stream when its probe completes first',
    () async {
      const settings = StreamSelectionSettings(
        mode: StreamSelectionMode.first,
        sourceOrder: ['builtin:Nivio', 'repo#abc'],
      );
      final first = _choice('slower', 'Movie', '1080p');
      final second = _choice('fast', 'Movie', '1080p', provider: 'repo#abc');
      final slower = Completer<bool>();
      final discovery = StreamDiscovery(
        media: const SearchResult(id: 1, mediaType: 'movie'),
        season: 1,
        episode: 1,
        streaming: _UnusedStreamingService(),
        subDub: 'sub',
        preferredQuality: null,
        selection: settings,
      )..choices.addAll([second, first]);
      expect(discovery.orderForPicker([second, first]), [first, second]);
      final picked = await discovery.firstReachable(
        StreamSelection(
          settings,
          audio: 'Original',
          animeAudio: 'sub',
          isAnime: false,
        ),
        const Duration(seconds: 1),
        (choice) => choice == first ? slower.future : Future.value(true),
      );
      expect(picked, second);
      slower.complete(false);
      discovery.dispose();
    },
  );

  test(
    'obsolete picker preferences are ignored and playback settings persist',
    () async {
      SharedPreferences.setMockInitialValues({
        'stream_picker_default_filter': 'direct',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final initial = await container.read(
        streamSelectionSettingsProvider.future,
      );
      expect(initial.mode, StreamSelectionMode.manual);
      await container
          .read(streamSelectionSettingsProvider.notifier)
          .change(
            (value) => value.copyWith(
              mode: StreamSelectionMode.match,
              customResolutions: [720, 1080, 1440, 2160, 480],
            ),
          );
      final prefs = await SharedPreferences.getInstance();
      final saved = StreamSelectionSettings.read(prefs);
      expect(saved.mode, StreamSelectionMode.match);
      expect(saved.resolutions.first, 720);
      final switched = saved.copyWith(
        preset: StreamPreset.maxQuality,
        maxFileGb: 5,
      );
      await switched.save(prefs);
      final restored = StreamSelectionSettings.read(prefs);
      expect(restored.maxFileGb, 5);
      expect(restored.resolutions.first, 2160);
      expect(
        restored.copyWith(preset: StreamPreset.balanced).resolutions.first,
        720,
      );
    },
  );

  testWidgets('onboarding swipes and skips to the destination', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const OnboardingScreen(
            userId: 'test-user',
            destination: '/party?code=TEST',
          ),
        ),
        GoRoute(
          path: '/party',
          builder: (_, state) => Scaffold(
            body: Text('Party ${state.uri.queryParameters['code']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Setup starts at playback; sources are no longer a step.
    expect(find.text('Choose your sources'), findsNothing);
    expect(find.text('Source priority'), findsNothing);
    expect(find.text('Set your playback preferences'), findsOneWidget);
    expect(find.text('Fastest Load'), findsNothing);
    final fastestFirst = find.text('Fastest First');
    await tester.ensureVisible(fastestFirst);
    await tester.pumpAndSettle();
    expect(fastestFirst.hitTestable(), findsOneWidget);
    await tester.tap(fastestFirst.hitTestable());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(StreamSelectionSettings.read(prefs).mode, StreamSelectionMode.first);
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Connect your accounts'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const PageStorageKey(0)), findsOneWidget);
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    expect(find.text('Connect your accounts'), findsOneWidget);
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    expect(find.text('Watch together'), findsOneWidget);
    expect(find.text('Start or join from Watch Party'), findsOneWidget);
    await tester.tap(find.text('Skip setup'));
    await tester.pumpAndSettle();
    expect(find.text('Party TEST'), findsOneWidget);
    expect(await hasCompletedOnboarding('test-user'), isTrue);
    expect(await hasCompletedOnboarding('different-user'), isFalse);
    expect(onboardingDestination('https://example.com/'), '/home');
  });
}
