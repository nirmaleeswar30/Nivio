import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/screens/onboarding_screen.dart';
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
  ),
);

class _UnusedStreamingService implements StreamingService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
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
        torrentsEnabled: false,
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
    'saved picker tab migrates and new selection settings persist',
    () async {
      SharedPreferences.setMockInitialValues({
        'stream_picker_default_filter': 'direct',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final initial = await container.read(
        streamSelectionSettingsProvider.future,
      );
      expect(initial.preferredType, StreamFilter.direct);
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
      final saved = StreamSelectionSettings.read(prefs, StreamFilter.all);
      expect(saved.mode, StreamSelectionMode.match);
      expect(saved.preferredType, StreamFilter.direct);
      expect(saved.resolutions.first, 720);
      final switched = saved.copyWith(
        preset: StreamPreset.maxQuality,
        maxFileGb: 5,
      );
      await switched.save(prefs);
      final restored = StreamSelectionSettings.read(prefs, StreamFilter.all);
      expect(restored.maxFileGb, 5);
      expect(restored.resolutions.first, 2160);
      expect(
        restored.copyWith(preset: StreamPreset.balanced).resolutions.first,
        720,
      );
    },
  );

  testWidgets('onboarding skips steps and preserves the original destination', (
    tester,
  ) async {
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
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    expect(find.text('Set your playback preferences'), findsOneWidget);
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    expect(find.text('Connect your accounts'), findsOneWidget);
    await tester.tap(find.text('Skip this step'));
    await tester.pumpAndSettle();
    expect(find.text('Watch together'), findsOneWidget);
    await tester.tap(find.text('Skip setup'));
    await tester.pumpAndSettle();
    expect(find.text('Party TEST'), findsOneWidget);
    expect(await hasCompletedOnboarding('test-user'), isTrue);
    expect(await hasCompletedOnboarding('different-user'), isFalse);
    expect(onboardingDestination('https://example.com/'), '/home');
  });
}
