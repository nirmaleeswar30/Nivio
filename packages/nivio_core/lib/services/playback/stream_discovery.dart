import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/services/streaming_service.dart';

import 'built_in_direct_sources.dart';
import 'stream_choice.dart';
import 'stream_selection.dart';
import 'stream_selection_settings.dart';

class StreamDiscovery extends ChangeNotifier {
  static const _maxProgressiveQualityProbes = 6;

  StreamDiscovery({
    required this.media,
    required this.season,
    required this.episode,
    required this.streaming,
    required this.subDub,
    required this.preferredQuality,
    this.preferredAudio = 'Original',
    this.preferredSubtitle = 'Auto',
    this.previous,
    this.inspectVideoHeights,
    this.inspectAudioTracks,
    this.selection = const StreamSelectionSettings(),
  });

  final SearchResult media;
  final int season;
  final int episode;
  final StreamingService streaming;
  final String subDub;
  final String? preferredQuality;
  final String preferredAudio;
  final String preferredSubtitle;
  final StreamChoice? previous;
  final Future<List<int>> Function(StreamResult)? inspectVideoHeights;
  final Future<List<String>> Function(StreamResult, Future<void>)?
  inspectAudioTracks;
  final StreamSelectionSettings selection;

  final choices = <StreamChoice>[];
  final failures = <String>{};
  final unavailable = <String>{};
  final _rateLimited = <String>{};
  // Sources still searching, and results whose resolution is being probed.
  final _pendingSources = <String>{};
  final _inspecting = <String>{};
  final _metadataLanes = List<Future<void>>.filled(3, Future<void>.value());
  var _nextMetadataLane = 0;
  final _checkedAudio = <String>{};
  final _failedAudioChecks = <String>{};
  String? _checkingAudio;
  Completer<void>? _audioCancellation;
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

  String? get fileSizeEmptyMessage =>
      choices.isNotEmpty &&
          choices.every(
            (choice) => !policy.fitsFileSizeLimit(choice, allowUnknown: true),
          )
      ? 'No direct streams within your maximum file size.'
      : null;

  bool checkingAudio(StreamChoice choice) => _checkingAudio == choice.id;
  bool get audioCheckInProgress => _audioCancellation != null;
  bool audioCheckFailed(StreamChoice choice) =>
      _failedAudioChecks.contains(choice.id);

  bool canCheckAudio(StreamChoice choice) {
    final uri = Uri.tryParse(choice.direct.url);
    return inspectAudioTracks != null &&
        uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        !unavailable.contains(choice.id) &&
        !_checkedAudio.contains(choice.id);
  }

  Future<void> checkAudioTracks(StreamChoice choice) async {
    final inspect = inspectAudioTracks;
    if (_closed ||
        inspect == null ||
        audioCheckInProgress ||
        !canCheckAudio(choice) ||
        !choices.contains(choice)) {
      return;
    }
    final generation = _generation;
    final cancellation = _audioCancellation = Completer<void>();
    _checkingAudio = choice.id;
    _failedAudioChecks.remove(choice.id);
    notifyListeners();
    try {
      final tracks = await inspect(choice.direct, cancellation.future);
      if (!_current(generation) || cancellation.isCompleted) return;
      final position = choices.indexWhere(
        (current) => current.id == choice.id && current.direct == choice.direct,
      );
      if (position < 0) return;
      if (tracks.isEmpty) {
        _failedAudioChecks.add(choice.id);
      } else {
        choices[position] = choices[position].withMetadata(audioTracks: tracks);
        _checkedAudio.add(choice.id);
      }
    } catch (_) {
      if (_current(generation) && !cancellation.isCompleted) {
        _failedAudioChecks.add(choice.id);
      }
    } finally {
      _checkingAudio = null;
      cancelAudioCheck();
      _audioCancellation = null;
      if (!_closed) notifyListeners();
    }
  }

  void cancelAudioCheck() {
    final cancellation = _audioCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  List<StreamChoice> orderForPicker(
    List<StreamChoice> visible, {
    int? resolution,
  }) {
    final ordered = visible
        .where((choice) => policy.fitsFileSizeLimit(choice, allowUnknown: true))
        .indexed
        .toList();
    final priority = [
      if (resolution != null) resolution,
      ...selection.resolutions.where((height) => height != resolution),
    ];
    final qualityRanks = resolution == null
        ? null
        : {
            for (final (_, choice) in ordered)
              choice: policy.resolutionRank(choice, priority: priority),
          };
    ordered.sort((a, b) {
      final byLanguage = policy.compareLanguagePreferences(a.$2, b.$2);
      if (byLanguage != 0) return byLanguage;
      if (qualityRanks != null) {
        final byQuality = qualityRanks[a.$2]!.compareTo(qualityRanks[b.$2]!);
        if (byQuality != 0) return byQuality;
      }
      final bySource = policy.compareSources(a.$2, b.$2);
      if (bySource != 0) return bySource;
      return a.$1.compareTo(b.$1);
    });
    return ordered.map((entry) => entry.$2).toList();
  }

  /// Waits until every source has answered, [timeout] passes, or [settled]
  /// says the result can't change.
  Future<void> waitForResults(
    Duration timeout, {
    bool Function()? settled,
  }) async {
    if (!searching || _closed || timeout <= Duration.zero) return;
    if (settled?.call() == true) return;
    final done = Completer<void>();
    void check() {
      if (done.isCompleted) return;
      if (!searching || settled?.call() == true) done.complete();
    }

    addListener(check);
    try {
      await done.future.timeout(timeout, onTimeout: () {});
    } finally {
      removeListener(check);
    }
  }

  /// True once Autoplay's pick can no longer change: a result already meets
  /// every preference above source priority (see
  /// [StreamSelection.settlesAutoplay]), no higher-priority source is still
  /// searching, and no higher-priority result is still being probed.
  bool autoplaySettled({String? bingeGroup}) {
    if (_closed) return false;
    int rank(String sourceId) =>
        selection.sourceRank(sourceId, isAnime: isAnime);
    int? best;
    for (final choice in availableChoices) {
      if (_inspecting.contains(choice.id) ||
          !policy.settlesAutoplay(choice, bingeGroup: bingeGroup)) {
        continue;
      }
      final value = rank(choice.selectionSourceId);
      if (best == null || value < best) best = value;
    }
    final top = best;
    if (top == null) return false;
    if (_pendingSources.any((source) => rank(source) < top)) return false;
    return !availableChoices.any(
      (choice) =>
          _inspecting.contains(choice.id) &&
          rank(choice.selectionSourceId) < top,
    );
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
        if (!policy.eligible(choice) ||
            !policy.meetsAutoplayAudioPreference(choice) ||
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
    if (_closed) return;
    cancelAudioCheck();
    final generation = ++_generation;
    searching = true;
    choices.clear();
    failures.clear();
    unavailable.clear();
    _rateLimited.clear();
    _pendingSources.clear();
    _inspecting.clear();
    _checkedAudio.clear();
    _failedAudioChecks.clear();
    notifyListeners();
    var progressiveProbes = 0;
    void addResults(List<StreamChoice> results) {
      if (!_current(generation)) return;
      choices.addAll(results);
      final inspect = inspectVideoHeights;
      if (inspect != null) {
        for (final choice in results) {
          if (choice.knownResolutions.isNotEmpty) continue;
          final stream = choice.direct;
          if (!stream.isM3U8) {
            final path = Uri.tryParse(stream.url)?.path.toLowerCase();
            if (path?.endsWith('.mp4') != true ||
                progressiveProbes >= _maxProgressiveQualityProbes) {
              continue;
            }
            progressiveProbes++;
          }
          final lane = _nextMetadataLane++ % _metadataLanes.length;
          _inspecting.add(choice.id);
          _metadataLanes[lane] = _metadataLanes[lane].then((_) async {
            if (!_current(generation)) return;
            try {
              final heights = await inspect(stream);
              if (!_current(generation) || heights.isEmpty) return;
              final position = choices.indexWhere(
                (current) =>
                    current.id == choice.id && current.direct == choice.direct,
              );
              if (position < 0) return;
              choices[position] = choices[position].withMetadata(
                videoHeights: heights,
              );
              notifyListeners();
            } catch (_) {
              // The stream remains selectable with its original quality label.
            } finally {
              if (_current(generation) && _inspecting.remove(choice.id)) {
                notifyListeners();
              }
            }
          });
        }
      }
      notifyListeners();
    }

    await _searchBuiltIn(generation, addResults);
    if (!_current(generation)) return;
    await Future.wait(_metadataLanes);
    if (_current(generation)) {
      searching = false;
      notifyListeners();
    }
  }

  void stop() {
    cancelAudioCheck();
    _generation++;
    searching = false;
    if (!_closed) notifyListeners();
  }

  void markFailed(StreamChoice choice, {bool rateLimited = false}) {
    if (_closed) return;
    final added = unavailable.add(choice.id);
    final limited = rateLimited && _rateLimited.add(choice.id);
    if (added || limited) notifyListeners();
  }

  String? failureMessage(StreamChoice choice) {
    if (_rateLimited.contains(choice.id)) {
      return 'Server is rate limiting this stream (HTTP 429). Try another stream or refresh later.';
    }
    return unavailable.contains(choice.id)
        ? 'Couldn’t open this stream. Choose another result.'
        : null;
  }

  bool _current(int generation) => !_closed && generation == _generation;

  void _failed(int generation, String name) {
    if (!_current(generation)) return;
    failures.add(name);
    notifyListeners();
  }

  Future<void> _searchBuiltIn(
    int generation,
    void Function(List<StreamChoice>) addResults,
  ) async {
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
    final providers = [
      for (var i = 0; i < streaming.totalProvidersFor(isAnime: isAnime); i++)
        if (streaming.getProviderName(i, isAnime: isAnime) case final name
            when name != 'Nivio Torrents')
          (i, name),
    ];
    _pendingSources.addAll([
      for (final (_, name) in providers)
        streamSelectionSourceId('builtin:$name'),
    ]);
    if (selection.mode != StreamSelectionMode.first) {
      providers.sort((a, b) {
        final rank = selection
            .sourceRank(
              streamSelectionSourceId('builtin:${a.$2}'),
              isAnime: isAnime,
            )
            .compareTo(
              selection.sourceRank(
                streamSelectionSourceId('builtin:${b.$2}'),
                isAnime: isAnime,
              ),
            );
        return rank != 0 ? rank : a.$1.compareTo(b.$1);
      });
    }
    await _concurrently(providers, 5, generation, (provider) async {
      final (index, name) = provider;
      try {
        await _searchSource(generation, index, name, addResults);
      } finally {
        if (_current(generation)) {
          _pendingSources.remove(streamSelectionSourceId('builtin:$name'));
          notifyListeners();
        }
      }
    });
  }

  Future<void> _searchSource(
    int generation,
    int index,
    String name,
    void Function(List<StreamChoice>) addResults,
  ) async {
    try {
      if (!isAnime && BuiltInDirectSources.names.contains(name)) {
        addResults(
          await BuiltInDirectSources.resolve(
            name,
            media,
            tmdb: streaming.tmdbService,
            season: season,
            episode: episode,
          ),
        );
        return;
      }
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
            title: result.provider,
            quality: selected[i].quality,
            audio: selected[i].selectedAudio.isEmpty
                ? null
                : selected[i].selectedAudio,
            direct: selected[i],
          ),
      ];
      addResults(results);
    } catch (_) {
      _failed(generation, name);
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
    cancelAudioCheck();
    _closed = true;
    _generation++;
    super.dispose();
  }
}
