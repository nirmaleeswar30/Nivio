import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/playback/stream_discovery.dart';
import 'package:nivio/services/playback/stream_selection_settings.dart';
import 'package:nivio/services/streaming_service.dart';

/// Two sources whose answers the test releases by hand.
class _ControlledSources implements StreamingService {
  final answers = {
    'Slow': Completer<StreamResult?>(),
    'Fast': Completer<StreamResult?>(),
  };

  static const _names = ['Slow', 'Fast'];

  @override
  int totalProvidersFor({required bool isAnime}) => _names.length;

  @override
  String getProviderName(int index, {required bool isAnime}) => _names[index];

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
  }) => answers[_names[providerIndex]]!.future;

  void answer(String name, String quality) => answers[name]!.complete(
    StreamResult(url: 'https://example.com/$name', quality: quality, provider: name),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StreamDiscovery _discovery(_ControlledSources sources) => StreamDiscovery(
  media: const SearchResult(id: 1, mediaType: 'movie'),
  season: 1,
  episode: 1,
  streaming: sources,
  subDub: 'sub',
  preferredQuality: null,
  selection: const StreamSelectionSettings(
    mode: StreamSelectionMode.match,
    sourceOrder: ['builtin:Slow', 'builtin:Fast'],
  ),
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('starts as soon as the top source has the preferred resolution', () async {
    final sources = _ControlledSources();
    final discovery = _discovery(sources);
    addTearDown(discovery.dispose);
    unawaited(discovery.search());
    await _settle();
    expect(discovery.autoplaySettled(), isFalse);

    sources.answer('Slow', '1080p');
    final clock = Stopwatch()..start();
    await discovery.waitForResults(
      const Duration(seconds: 5),
      settled: discovery.autoplaySettled,
    );
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    // Fast never answered, so the full wait would have run to the timeout.
    expect(discovery.searching, isTrue);
    sources.answers['Fast']!.complete(null);
  });

  test('waits for a higher-priority source still searching', () async {
    final sources = _ControlledSources();
    final discovery = _discovery(sources);
    addTearDown(discovery.dispose);
    unawaited(discovery.search());
    await _settle();

    sources.answer('Fast', '1080p');
    await _settle();
    expect(discovery.autoplaySettled(), isFalse);

    sources.answers['Slow']!.complete(null);
    await _settle();
    expect(discovery.autoplaySettled(), isTrue);
  });

  test('keeps waiting when no result has the preferred resolution', () async {
    final sources = _ControlledSources();
    final discovery = _discovery(sources);
    addTearDown(discovery.dispose);
    unawaited(discovery.search());
    await _settle();

    sources.answer('Slow', '720p');
    await _settle();
    expect(discovery.autoplaySettled(), isFalse);
    sources.answers['Fast']!.complete(null);
  });
}
