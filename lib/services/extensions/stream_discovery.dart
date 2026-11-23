import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/streaming_service.dart';

import 'extension_repository.dart';
import 'extension_resolver.dart';
import 'stream_selection.dart';
import 'stream_selection_settings.dart';

class StreamDiscovery extends ChangeNotifier {
  StreamDiscovery({
    required this.media,
    required this.season,
    required this.episode,
    required this.streaming,
    required this.repository,
    required this.subDub,
    required this.preferredQuality,
    this.preferredAudio = 'Original',
    this.preferredSubtitle = 'Auto',
    this.previous,
    this.inspectVideoHeights,
    this.selection = const StreamSelectionSettings(),
  });

  final SearchResult media;
  final int season;
  final int episode;
  final StreamingService streaming;
  final ExtensionRepository repository;
  final String subDub;
  final String? preferredQuality;
  final String preferredAudio;
  final String preferredSubtitle;
  final StreamChoice? previous;
  final Future<List<int>> Function(StreamResult)? inspectVideoHeights;
  final StreamSelectionSettings selection;

  final choices = <StreamChoice>[];
  final failures = <String>{};
  final unavailable = <String>{};
  bool searching = true;
  bool _closed = false;
  int _generation = 0;

  bool get isAnime => media.mediaType == 'anime';

  late final policy = StreamSelection(
    selection,
    audio: preferredAudio,
    subtitle: preferredSubtitle,
    animeAudio: subDub,
    isAnime: isAnime,
  );

  List<StreamChoice> get availableChoices =>
      choices.where((choice) => !unavailable.contains(choice.id)).toList();

  List<StreamChoice> orderForPicker(
    List<StreamChoice> visible, {
    int? resolution,
  }) {
    final ordered = visible.indexed.toList();
    ordered.sort((a, b) {
      final byLanguage = policy.compareLanguagePreferences(a.$2, b.$2);
      if (byLanguage != 0) return byLanguage;
      if (resolution != null) {
        final aMatches = a.$2.knownResolutions.contains(resolution);
        final bMatches = b.$2.knownResolutions.contains(resolution);
        if (aMatches != bMatches) return aMatches ? -1 : 1;
      }
      final bySource = policy.compareSources(a.$2, b.$2);
      if (bySource != 0) return bySource;
      return a.$1.compareTo(b.$1);
    });
    return ordered.map((entry) => entry.$2).toList();
  }

  Future<void> waitForResults(Duration timeout) async {
    if (!searching || _closed || timeout <= Duration.zero) return;
    final done = Completer<void>();
    void check() {
      if (!done.isCompleted && !searching) done.complete();
    }

    addListener(check);
    try {
      await done.future.timeout(timeout, onTimeout: () {});
    } finally {
      removeListener(check);
    }
  }

  Future<StreamChoice?> firstReachable(
    StreamSelection policy,
    Duration timeout,
    Future<bool> Function(StreamChoice) probe,
  ) async {
    if (_closed || timeout <= Duration.zero) return null;
    final result = Completer<StreamChoice?>();
    final checked = <String>{};
    var active = 0;

    void pump() {
      if (result.isCompleted) return;
      if (_closed) {
        result.complete(null);
        return;
      }
      for (final choice in availableChoices) {
        if (active >= 5) break;
        if (!choice.isDirect ||
            !policy.eligible(choice) ||
            !policy.confirmedAudio(choice) ||
            !checked.add(choice.id))
          continue;
        active++;
        unawaited(() async {
          var reachable = false;
          try {
            reachable = await probe(choice);
          } catch (_) {
            // Continue racing the other direct sources.
          }
          active--;
          if (result.isCompleted) return;
          if (reachable) {
            result.complete(choice);
          } else {
            markFailed(choice);
          }
        }());
      }
      if (!searching && active == 0) result.complete(null);
    }

    addListener(pump);
    try {
      pump();
      return await result.future.timeout(
        timeout,
        onTimeout: () {
          result.complete(null);
          return null;
        },
      );
    } finally {
      removeListener(pump);
    }
  }

  Future<void> search() async {
    final generation = ++_generation;
    searching = true;
    choices.clear();
    failures.clear();
    unavailable.clear();
    notifyListeners();
    await Future.wait([
      _searchBuiltIn(generation),
      _searchExtensions(generation),
    ]);
    if (_current(generation)) {
      searching = false;
      notifyListeners();
    }
  }

  void stop() {
    _generation++;
    searching = false;
    if (!_closed) notifyListeners();
  }

  void markFailed(StreamChoice choice) {
    if (_closed) return;
    unavailable.add(choice.id);
    notifyListeners();
  }

  bool _current(int generation) => !_closed && generation == _generation;

  void _add(int generation, List<StreamChoice> results) {
    if (!_current(generation)) return;
    choices.addAll(results.where((choice) => choice.isDirect));
    notifyListeners();
  }

  void _failed(int generation, String name) {
    if (!_current(generation)) return;
    failures.add(name);
    notifyListeners();
  }

  Future<void> _searchBuiltIn(int generation) async {
    if (isAnime) {
      try {
        await streaming
            .prepareProviders(
              media: media,
              season: season,
              episode: episode,
              subDubPreference: subDub,
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        // The streaming service retains its default anime servers on failure.
      }
    }
    if (!_current(generation)) return;
    final providers =
        [
              for (
                var i = 0;
                i < streaming.totalProvidersFor(isAnime: isAnime);
                i++
              )
                if (streaming.getProviderName(i, isAnime: isAnime) !=
                        'Nivio Torrents' &&
                    streaming.isDirectStream(i, isAnime: isAnime))
                  i,
            ]
            .map(
              (index) =>
                  (index, streaming.getProviderName(index, isAnime: isAnime)),
            )
            .toList();
    if (selection.mode != StreamSelectionMode.first) {
      providers.sort((a, b) {
        final rank = selection
            .sourceRank(streamSelectionSourceId('builtin:${a.$2}'))
            .compareTo(
              selection.sourceRank(streamSelectionSourceId('builtin:${b.$2}')),
            );
        return rank != 0 ? rank : a.$1.compareTo(b.$1);
      });
    }
    await _concurrently(providers, 5, generation, (provider) async {
      final (index, name) = provider;
      try {
        final result = await streaming
            .fetchStreamUrl(
              media: media,
              season: season,
              episode: episode,
              providerIndex: index,
              preferredQuality: preferredQuality,
              preferredAudio: !isAnime && preferredAudio != 'Original'
                  ? preferredAudio
                  : null,
              subDubPreference: subDub,
            )
            .timeout(const Duration(seconds: 24));
        if (result == null || result.url.isEmpty) return;
        final urls = <String>{result.url};
        final selected = [
          result.copyWith(sources: const []),
          for (final source in result.sources)
            if (source.url.isNotEmpty && urls.add(source.url))
              result.copyWith(
                url: source.url,
                quality: source.quality,
                isM3U8: source.isM3U8,
                sources: const [],
                selectedAudio: isAnime
                    ? (source.isDub ? 'Dub' : 'Sub')
                    : result.selectedAudio,
              ),
        ];
        final results = [
          for (var i = 0; i < selected.length; i++)
            StreamChoice(
              id: 'builtin:$name:$i',
              providerId: 'builtin:$name',
              provider: result.provider,
              origin: 'Built-in source',
              title: result.provider,
              quality: selected[i].quality,
              audio: selected[i].selectedAudio.isEmpty
                  ? null
                  : selected[i].selectedAudio,
              direct: selected[i],
            ),
        ];
        _add(generation, results);
        final inspect = inspectVideoHeights;
        if (inspect != null) {
          final unlabelled = results
              .where(
                (choice) =>
                    choice.direct!.isM3U8 && choice.knownResolutions.isEmpty,
              )
              .toList();
          await _concurrently(unlabelled, 2, generation, (choice) async {
            try {
              final heights = await inspect(choice.direct!);
              if (!_current(generation) || heights.isEmpty) return;
              final position = choices.indexOf(choice);
              if (position < 0) return;
              choices[position] = choice.withVideoHeights(heights);
              notifyListeners();
            } catch (_) {
              // A manifest without readable metadata can still be played.
            }
          });
        }
      } catch (_) {
        _failed(generation, name);
      }
    });
  }

  Future<void> _searchExtensions(int generation) async {
    try {
      final repositories = await repository.list();
      final providers = repositories
          .expand((repo) => repo.providers)
          .where(
            (provider) =>
                provider.enabled &&
                ExtensionResolver.supports(provider.repository.format) &&
                provider.supports(media.mediaType),
          )
          .toList();
      if (providers.isEmpty || !_current(generation)) return;
      if (selection.mode != StreamSelectionMode.first) {
        final ranked = providers.indexed.toList()
          ..sort((a, b) {
            final rank = selection
                .sourceRank(a.$2.id)
                .compareTo(selection.sourceRank(b.$2.id));
            return rank != 0 ? rank : a.$1.compareTo(b.$1);
          });
        providers.setAll(0, ranked.map((entry) => entry.$2));
      }
      final target = await extensionMedia(media, season, episode);
      final resolver = ExtensionResolver(repository);
      await _concurrently(providers, 4, generation, (provider) async {
        try {
          _add(
            generation,
            await resolver
                .resolve(provider, target, media)
                .timeout(const Duration(seconds: 38)),
          );
        } catch (_) {
          _failed(generation, provider.name);
        }
      });
    } catch (_) {
      _failed(generation, 'Extensions');
    }
  }

  Future<void> _concurrently<T>(
    List<T> items,
    int workers,
    int generation,
    Future<void> Function(T) task,
  ) async {
    var next = 0;
    Future<void> work() async {
      while (_current(generation) && next < items.length) {
        await task(items[next++]);
      }
    }

    await Future.wait(List.generate(workers, (_) => work()));
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    super.dispose();
  }
}
