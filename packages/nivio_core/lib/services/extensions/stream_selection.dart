import 'dart:async';
import 'dart:isolate';

import 'package:nivio/services/torrent/anitomy.dart';

import 'extension_repository.dart';
import 'extension_resolver.dart';
import 'stream_selection_settings.dart';

String? validateStreamRegex(String pattern) {
  if (pattern.length > 512) return 'Use at most 512 characters.';
  try {
    RegExp(pattern, caseSensitive: false);
  } on FormatException {
    return 'Enter a valid regular expression.';
  }
  return null;
}

Future<Set<int>?> _regexMatches(String pattern, List<String> labels) async {
  if (validateStreamRegex(pattern) != null) return null;
  final port = ReceivePort();
  final result = port.first;
  Isolate? worker;
  try {
    // A backtracking pattern can take arbitrarily long. Run it where it can
    // be stopped without blocking playback or the picker.
    final input = (port.sendPort, pattern, labels);
    worker = await Isolate.spawn(_evaluateRegex, input);
    return await result.timeout(const Duration(milliseconds: 350)) as Set<int>?;
  } on TimeoutException {
    return null;
  } finally {
    worker?.kill(priority: Isolate.immediate);
    port.close();
  }
}

void _evaluateRegex((SendPort, String, List<String>) input) {
  final (port, pattern, labels) = input;
  final regex = RegExp(pattern, caseSensitive: false);
  port.send({
    for (var i = 0; i < labels.length; i++)
      if (regex.hasMatch(labels[i])) i,
  });
}

class StreamSelection {
  StreamSelection(
    this.settings, {
    required this.audio,
    required this.animeAudio,
    required this.isAnime,
  });

  final StreamSelectionSettings settings;
  final String audio;
  final String animeAudio;
  final bool isAnime;

  static final _blocked = {
    StreamExclusion.cam: RegExp(
      r'(?:^|[\s.\[(_-])cam(?:$|[\s.\])_-])',
      caseSensitive: false,
    ),
    StreamExclusion.ts: RegExp(
      r'(?<!mpeg[ ._-])(?<!mpeg)(?:^|[\s.\[(_-])(?:hdts|telesync|ts)(?:$|[\s.\])_-])',
      caseSensitive: false,
    ),
    StreamExclusion.hdcam: RegExp(r'\bhd[ ._-]?cam\b', caseSensitive: false),
    StreamExclusion.threeD: RegExp(
      r'\b(?:3d|half[ ._-]?sbs|hsbs)\b',
      caseSensitive: false,
    ),
  };

  bool eligible(StreamChoice choice) {
    if (choice.isWebPlayer) return false;
    final text = choice.releaseLabel;
    if (settings.exclusions.any((term) => _blocked[term]!.hasMatch(text)))
      return false;
    final size = choice.torrent?.isBatch == true ? null : choice.byteSize;
    if (settings.maxFileGb > 0 &&
        (size == null || size > settings.maxFileGb * 1073741824))
      return false;
    return !settings.matchAudio || _audioMatch(choice) > 0;
  }

  bool prefers(StreamChoice choice) => switch (settings.preferredType) {
    StreamFilter.all => true,
    StreamFilter.direct => choice.isDirect,
    StreamFilter.torrents => choice.isTorrent,
  };

  int _audioMatch(StreamChoice choice) {
    if (isAnime) {
      final type = choice.audioType?.toLowerCase();
      if (type == 'both' || type == animeAudio.toLowerCase()) return 2;
      if (type != null) return 0;
    }
    final wanted = audio.toLowerCase().trim();
    if (wanted.isEmpty || wanted == 'original' || wanted == 'auto')
      return isAnime ? 1 : 2;
    final wantedCode = _languageCode(wanted);
    final reported = (choice.audio ?? '').toLowerCase();
    final tracks = [
      for (final value in reported.split(RegExp(r'[,/;+|\s]+')))
        if (_languageCode(value) case final String language) language,
    ];
    if (wantedCode == null || tracks.isEmpty) return 1;
    return tracks.contains(wantedCode) ? 2 : 0;
  }

  static String? _languageCode(String label) {
    final base = label.split(RegExp('[-_]')).first;
    for (final entry in _languages.entries) {
      if (entry.key == base || entry.value.contains(base)) return entry.key;
    }
    return null;
  }

  static const _languages = {
    'en': ['eng', 'english'],
    'ja': ['jpn', 'japanese'],
    'hi': ['hin', 'hindi'],
    'es': ['spa', 'spanish'],
    'fr': ['fre', 'fra', 'french'],
    'de': ['deu', 'ger', 'german'],
    'it': ['ita', 'italian'],
    'pt': ['por', 'portuguese'],
    'ru': ['rus', 'russian'],
    'ko': ['kor', 'korean'],
    'zh': ['chi', 'zho', 'chinese', 'mandarin', 'cantonese'],
    'ar': ['ara', 'arabic'],
    'ta': ['tam', 'tamil'],
    'te': ['tel', 'telugu'],
    'ml': ['mal', 'malayalam'],
    'bn': ['ben', 'bengali'],
    'kn': ['kan', 'kannada'],
    'tr': ['tur', 'turkish'],
    'th': ['tha', 'thai'],
    'id': ['ind', 'indonesian'],
    'pl': ['pol', 'polish'],
    'nl': ['dut', 'nld', 'dutch'],
    'sv': ['swe', 'swedish'],
    'vi': ['vie', 'vietnamese'],
  };

  bool confirmedAudio(StreamChoice choice) =>
      !settings.matchAudio || _audioMatch(choice) == 2;

  int compareSources(StreamChoice a, StreamChoice b) => settings
      .sourceRank(a.selectionSourceId)
      .compareTo(settings.sourceRank(b.selectionSourceId));

  Future<List<StreamChoice>> ranked(
    Iterable<StreamChoice> input, {
    String? bingeGroup,
  }) async {
    var choices = input.where(eligible).toList();
    final usePreset =
        settings.mode == StreamSelectionMode.match && settings.regex.isEmpty;
    if (settings.mode == StreamSelectionMode.match &&
        settings.regex.isNotEmpty) {
      final matches = await _regexMatches(settings.regex, [
        for (final choice in choices) choice.releaseLabel,
      ]);
      if (matches == null) return [];
      choices = [for (final i in matches) choices[i]];
    }
    final indexed = choices.indexed.toList();
    final qualities = usePreset
        ? {for (final choice in choices) choice.id: _qualityRank(choice)}
        : const <String, int>{};
    final features = usePreset
        ? {for (final choice in choices) choice.id: _featureScore(choice)}
        : const <String, int>{};
    indexed.sort((a, b) {
      final x = a.$2;
      final y = b.$2;
      if (settings.matchAudio) {
        final byAudio = _audioMatch(y).compareTo(_audioMatch(x));
        if (byAudio != 0) return byAudio;
      }
      final byType = (prefers(y) ? 1 : 0).compareTo(prefers(x) ? 1 : 0);
      if (byType != 0) return byType;
      if (bingeGroup != null) {
        final byBinge = (y.bingeGroup == bingeGroup ? 1 : 0).compareTo(
          x.bingeGroup == bingeGroup ? 1 : 0,
        );
        if (byBinge != 0) return byBinge;
      }
      if (usePreset) {
        final byQuality = qualities[x.id]!.compareTo(qualities[y.id]!);
        if (byQuality != 0) return byQuality;
        final byFeatures = features[y.id]!.compareTo(features[x.id]!);
        if (byFeatures != 0) return byFeatures;
        if (settings.preset == StreamPreset.dataSaver) {
          final bySize = (x.byteSize ?? 1 << 60).compareTo(
            y.byteSize ?? 1 << 60,
          );
          if (bySize != 0) return bySize;
        }
      }
      if (settings.mode == StreamSelectionMode.match) {
        final bySource = compareSources(x, y);
        if (bySource != 0) return bySource;
      }
      return a.$1.compareTo(b.$1);
    });
    return indexed.map((entry) => entry.$2).toList();
  }

  int _qualityRank(StreamChoice choice) {
    final height = choice.resolution;
    final index = settings.resolutions.indexOf(height ?? 0);
    return index >= 0
        ? index
        : settings.resolutions.length + (height == null ? 1 : 0);
  }

  int _featureScore(StreamChoice choice) {
    final text = choice.releaseLabel.toLowerCase();
    var score = 0;
    if (settings.features.contains(StreamFeature.hevc) &&
        RegExp(r'\b(?:x265|h[ .]?265|hevc)\b').hasMatch(text))
      score++;
    if (settings.features.contains(StreamFeature.hdr) &&
        RegExp(r'\bhdr(?:10(?:\+)?)?\b').hasMatch(text))
      score++;
    if (settings.features.contains(StreamFeature.dolbyVision) &&
        RegExp(r'\b(?:dovi|dv|dolby[ ._-]?vision)\b').hasMatch(text))
      score++;
    if (settings.preset == StreamPreset.balanced &&
        RegExp(r'\b(?:web[ ._-]?dl|blu[ ._-]?ray)\b').hasMatch(text))
      score++;
    if (settings.preset == StreamPreset.maxQuality &&
        RegExp(r'\bremux\b').hasMatch(text))
      score++;
    return score;
  }
}

extension StreamSelectionMetadata on StreamChoice {
  static final _height = RegExp(
    r'(?<!\d)(2160|1440|1080|720|576|540|480|360|240)(?:[pi](?![a-z])|\b)',
    caseSensitive: false,
  );

  String get selectionSourceId => streamSelectionSourceId(providerId);
  String get releaseLabel =>
      '$provider $quality ${audio ?? ''} $title'.split('\n').join(' ').trim();
  int? get resolution {
    final qualityLabel = quality.toLowerCase().trim();
    if (qualityLabel == '4k' || qualityLabel == 'uhd') return 2160;
    return int.tryParse(_height.firstMatch(qualityLabel)?.group(1) ?? '') ??
        torrent?.parsed.resolution ??
        int.tryParse(_height.firstMatch(title)?.group(1) ?? '');
  }

  String get bingeGroup {
    final hint = bingeGroupHint;
    if (hint != null && hint.isNotEmpty) {
      return '$providerId|${isTorrent ? 'torrent' : 'direct'}|$hint';
    }
    final parsed = torrent?.parsed ?? Anitomy.parse(title);
    final label = title
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'\bs\d{1,3}[ ._-]*e\d{1,4}\b|\b(?:episode|ep)[ ._-]*\d+\b|\b\d{1,3}x\d{1,4}\b',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'(?:^|\s)-\s*\d{1,4}(?:v\d+)?(?=\s|\[|$)'), ' ')
        .replaceAll(RegExp(r'\[[a-f0-9]{8}\]|\s+'), ' ')
        .trim();
    return [
      providerId,
      isTorrent ? 'torrent' : 'direct',
      resolution ?? quality,
      (audioType ?? audio ?? '').toLowerCase(),
      parsed.releaseGroup ?? label,
      parsed.videoCodec ?? '',
      parsed.source ?? '',
    ].join('|');
  }
}

String streamSelectionSourceId(String providerId) {
  if (!providerId.startsWith('builtin:')) return providerId;
  return providerId.split(' (').first;
}
