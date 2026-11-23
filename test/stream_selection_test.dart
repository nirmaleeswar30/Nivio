import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/screens/extensions_screen.dart';
import 'package:nivio/screens/onboarding_screen.dart';
import 'package:nivio/screens/stream_selection_screen.dart';
import 'package:nivio/services/extensions/extension_repository.dart';
import 'package:nivio/services/extensions/extension_resolver.dart';
import 'package:nivio/services/extensions/stream_discovery.dart';
import 'package:nivio/services/extensions/stream_selection.dart';
import 'package:nivio/services/extensions/stream_selection_settings.dart';
import 'package:nivio/services/streaming_service.dart';
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
  origin: 'Example repo',
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

void main() {
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
        repository: ExtensionRepository(),
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
        ),
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
      StreamFeature.bluRayQuality: 'Film BDRip',
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
      for (final feature in StreamFeature.values) {
        expect(find.widgetWithText(FilterChip, feature.label), findsOneWidget);
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
        repository: ExtensionRepository(),
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
    expect(find.text('Choose your sources'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Set your playback preferences'), findsOneWidget);
    final fastestLoad = find.text('Fastest Load');
    await tester.ensureVisible(fastestLoad);
    await tester.pumpAndSettle();
    expect(fastestLoad.hitTestable(), findsOneWidget);
    await tester.tap(fastestLoad.hitTestable());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(StreamSelectionSettings.read(prefs).mode, StreamSelectionMode.first);
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Choose your sources'), findsOneWidget);
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    expect(find.byKey(const PageStorageKey(1)), findsOneWidget);
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

  testWidgets('Extensions shows repository directories and pastes the URL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    const url = 'https://example.com/manifest.json';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': '  $url\n'};
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ExtensionsScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nuvio plugins'), findsOneWidget);
    expect(find.text('Cloudstream repos'), findsOneWidget);
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, url);
    expect(
      field.controller!.selection,
      TextSelection.collapsed(offset: url.length),
    );
    expect(find.text('No repositories installed'), findsOneWidget);
  });

  testWidgets('enabling providers keeps the repository expanded', (
    tester,
  ) async {
    final repo = ExtensionRepo(
      url: Uri.https('example.com', '/manifest.json'),
      name: 'Test repository',
      format: ExtensionFormat.javascript,
      entries: [
        {'id': 'first', 'name': 'First source'},
        {'id': 'second', 'name': 'Second source'},
      ],
      enabledIds: {},
    );
    SharedPreferences.setMockInitialValues({
      'stream_extension_repositories': jsonEncode([repo.toJson()]),
    });
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ExtensionsScreen())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test repository'));
    await tester.pumpAndSettle();

    final first = find.widgetWithText(SwitchListTile, 'First source');
    final second = find.widgetWithText(SwitchListTile, 'Second source');
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(first).value, isTrue);
    expect(second, findsOneWidget);

    await tester.ensureVisible(second);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(second).value, isTrue);
    expect(
      (await ExtensionRepository().list()).single.enabledIds,
      hasLength(2),
    );
  });
}
