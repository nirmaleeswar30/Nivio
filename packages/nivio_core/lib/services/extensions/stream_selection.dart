import 'dart:async';
import 'dart:isolate';

import 'package:nivio/services/torrent/anitomy.dart';

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
    this.subtitle = 'Auto',
    required this.animeAudio,
    required this.isAnime,
  });

  final StreamSelectionSettings settings;
  final String audio;
  final String subtitle;
  final String animeAudio;
  final bool isAnime;
  late final _wantedAudio = _languageCodes(audio);
  late final _wantedSubtitles = _languageCodes(subtitle);
  late final _preferredFormats = [
    for (final feature in settings.features)
      RegExp(feature.pattern, caseSensitive: false),
  ];

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
    if (!choice.isDirect) return false;
    final text = choice.releaseLabel;
    if (settings.exclusions.any((term) => _blocked[term]!.hasMatch(text)))
      return false;
    if (!fitsFileSizeLimit(choice)) return false;
    return !settings.matchAudio ||
        (_wantedAudio.isNotEmpty && choice.audioTracks.isEmpty) ||
        _audioMatch(choice) > 0;
  }

  bool fitsFileSizeLimit(StreamChoice choice, {bool allowUnknown = false}) {
    final limit = settings.maxFileBytes;
    if (limit == null) return true;
    final size = choice.displaySizeBytes;
    return size == null ? allowUnknown : size <= limit;
  }

  int _audioMatch(StreamChoice choice) {
    if (_wantedAudio.isNotEmpty) {
      if (choice.audioTracks.isNotEmpty) {
        final tracks = choice.audioTracks.map(_languageCodes);
        if (tracks.any((codes) => codes.any(_wantedAudio.contains))) return 2;
        return tracks.any((codes) => codes.isEmpty) ? 1 : 0;
      }
      final tracks = _languageCodes(choice.audio ?? '');
      if (_wantedAudio.any(tracks.contains) ||
          _wantedAudio.any(choice.namedAudioLanguages.contains)) {
        return 2;
      }
      if (tracks.isEmpty) return 1;
      return 0;
    }
    if (isAnime) {
      final preference = animeAudio.toLowerCase();
      final type = choice.audioType?.toLowerCase();
      if (type == 'both' || type == preference) return 2;
      if (type != null) return 0;
      if (preference == 'sub' &&
          (choice.audioTracks.any(
                (track) => _languageCodes(track).contains('ja'),
              ) ||
              _languageCodes(choice.audio ?? '').contains('ja') ||
              choice.namedAudioLanguages.contains('ja'))) {
        return 2;
      }
    }
    final requested = audio.trim().toLowerCase();
    return isAnime || !const {'', 'original', 'auto'}.contains(requested)
        ? 1
        : 2;
  }

  static Set<String> _languageCodes(String label) => {
    for (final value in label.toLowerCase().split(RegExp(r'[^a-z0-9_-]+')))
      if (_languageCode(value) case final String code) code,
  };

  static bool matchesLanguage(String label, String preference) {
    final wanted = preference.trim().toLowerCase();
    if (wanted.isEmpty) return false;
    return label.trim().toLowerCase() == wanted ||
        _languageCodes(label).any(_languageCodes(wanted).contains);
  }

  /// A title's saved track is a fallback when the picker has no explicit
  /// language preference in Playback settings.
  static String pickerAudioPreference(String preferred, {String? savedTrack}) {
    final preference = preferred.trim();
    if (const {'', 'original', 'auto'}.contains(preference.toLowerCase())) {
      final saved = savedTrack?.trim();
      if (saved != null && saved.isNotEmpty) return saved;
    }
    return preference;
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
    'ja': ['jp', 'jpn', 'japanese'],
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

  static final _releaseGroup = RegExp(r'\[([^\[\]]+)\]|\(([^()]+)\)');
  static final _releaseMarker = RegExp(
    r'(?<![a-z0-9])(?:(?:240|360|480|540|576|720|1080|1440|2160)[pi]|4k|uhd|web[ ._-]?dl|web[ ._-]?rip|blu[ ._-]?ray|remux|x26[45]|hevc)(?![a-z0-9])',
    caseSensitive: false,
  );
  static final _labelSeparator = RegExp(r'\s+[-–—]\s+|[|:\n]');
  static final _subtitleMarker = RegExp(
    r'(?<![a-z])(?:subtitles?|subbed|subs?|srt|vtt|esubs?)(?![a-z])',
    caseSensitive: false,
  );
  static final _audioMarker = RegExp(
    r'🎧|🔊|(?<![a-z])(?:dual[ ._-]?audio|multi[ ._-]?audio|multi[ ._-]?dub|audio|dubbed|dub|ddp?|eac3|aac|atmos|dts|truehd)(?![a-z])',
    caseSensitive: false,
  );
  static final _releaseFormats = {
    'Remux': RegExp(r'\bremux\b', caseSensitive: false),
    'BluRay': RegExp(r'\bblu[ .-]?ray\b', caseSensitive: false),
    'WEB-DL': RegExp(r'\bweb[ .-]?dl\b', caseSensitive: false),
    'WEBRip': RegExp(r'\bweb[ .-]?rip\b', caseSensitive: false),
  };

  static bool _isLanguageList(String text) {
    final words = text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty);
    return words.isNotEmpty &&
        words.every((word) => word == 'and' || _languageCode(word) != null);
  }

  /// Reads language hints only from release metadata, away from the film title.
  static Set<String> releaseAudioLanguages(String name) {
    final languages = <String>{};
    for (final match in _releaseGroup.allMatches(name)) {
      final tag = match.group(1) ?? match.group(2)!;
      if (_subtitleMarker.hasMatch(tag)) continue;
      if (_audioMarker.hasMatch(tag) ||
          _releaseMarker.hasMatch(tag) ||
          _isLanguageList(tag)) {
        languages.addAll(_languageCodes(tag.replaceAll(RegExp(r'[-_]'), ' ')));
      }
    }

    final plain = name.replaceAll(_releaseGroup, ' ');
    final marker = _releaseMarker.firstMatch(plain);
    // Provider labels can put audio before the quality, e.g. “Mirror -
    // English, Tamil 1080p”. Only read explicit fields made of language names.
    final leading = plain.substring(0, marker?.start ?? plain.length);
    final fields = leading.split(_labelSeparator);
    final audioFields = fields
        .skip(1)
        .toList()
        .reversed
        .takeWhile(_isLanguageList);
    for (final field in audioFields.toList().reversed) {
      languages.addAll(_languageCodes(field.replaceAll(RegExp(r'[-_]'), ' ')));
    }
    for (final line in [
      if (marker != null) plain.substring(marker.end),
      ...plain.split('\n').skip(1).where(_audioMarker.hasMatch),
    ]) {
      final subtitle = _subtitleMarker.firstMatch(line);
      // A subtitle marker can follow the language it describes.
      if (subtitle != null) continue;
      // Outside brackets, ISO two-letter codes are often ordinary words.
      for (final word in line.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
        if (word.length < 3) continue;
        if (_languageCode(word) case final String code) languages.add(code);
      }
    }
    return languages;
  }

  static String? releaseAudioLabel(String name) {
    final languages = releaseAudioLanguages(name);
    if (languages.isNotEmpty) return languages.map(_languageName).join(' / ');
    final hint = _audioMarker.stringMatch(name)?.toLowerCase();
    if (hint?.startsWith('dual') == true) return 'Dual audio';
    if (hint?.startsWith('multi') == true) return 'Multi audio';
    return null;
  }

  static Iterable<String> releaseFormats(String name) sync* {
    final normalized = name.replaceAll('_', ' ');
    for (final entry in _releaseFormats.entries) {
      if (entry.value.hasMatch(normalized)) yield entry.key;
    }
  }

  static String _languageName(String code) {
    final name = _languages[code]?.firstWhere((alias) => alias.length > 3);
    return name == null ? code : '${name[0].toUpperCase()}${name.substring(1)}';
  }

  bool meetsAutoplayAudioPreference(StreamChoice choice) =>
      !settings.matchAudio || _audioMatch(choice) == 2;

  static bool isUnspecifiedAudioLanguage(String? language) => const {
    '',
    'und',
    'unknown',
    'auto',
    'default',
    'none',
    'unk',
  }.contains(language?.trim().toLowerCase() ?? '');

  static String audioTrackLanguage(String? language, String? title) {
    if (!isUnspecifiedAudioLanguage(language)) return language!.trim();
    return _languageCodes(title ?? '').isEmpty ? 'und' : title!.trim();
  }

  bool hasPreferredSubtitles(StreamChoice choice) {
    return _wantedSubtitles.isNotEmpty &&
        (choice.direct?.subtitles.any(
              (track) =>
                  _languageCodes(track.lang).any(_wantedSubtitles.contains),
            ) ??
            false);
  }

  int compareLanguagePreferences(
    StreamChoice a,
    StreamChoice b, {
    bool matchAudio = true,
  }) {
    if (matchAudio) {
      final byAudio = _audioMatch(b).compareTo(_audioMatch(a));
      if (byAudio != 0) return byAudio;
    }
    final aMatches = hasPreferredSubtitles(a);
    final bMatches = hasPreferredSubtitles(b);
    return aMatches == bMatches ? 0 : (aMatches ? -1 : 1);
  }

  int compareSources(StreamChoice a, StreamChoice b) => settings
      .sourceRank(a.selectionSourceId, isAnime: isAnime)
      .compareTo(settings.sourceRank(b.selectionSourceId, isAnime: isAnime));

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
        ? {for (final choice in choices) choice.id: resolutionRank(choice)}
        : const <String, int>{};
    final features = usePreset
        ? {for (final choice in choices) choice.id: _featureScore(choice)}
        : const <String, int>{};
    indexed.sort((a, b) {
      final x = a.$2;
      final y = b.$2;
      final byLanguage = compareLanguagePreferences(
        x,
        y,
        matchAudio: settings.matchAudio,
      );
      if (byLanguage != 0) return byLanguage;
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
          final bySize = (x.displaySizeBytes ?? 1 << 60).compareTo(
            y.displaySizeBytes ?? 1 << 60,
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

  int resolutionRank(StreamChoice choice, {List<int>? priority}) {
    final resolutions = priority ?? settings.resolutions;
    final heights = choice.knownResolutions;
    final index = resolutions.indexWhere(heights.contains);
    return index >= 0 ? index : resolutions.length + (heights.isEmpty ? 1 : 0);
  }

  int _featureScore(StreamChoice choice) {
    final text = choice.releaseLabel;
    return _preferredFormats.where((pattern) => pattern.hasMatch(text)).length;
  }
}

extension StreamSelectionMetadata on StreamChoice {
  static final _height = RegExp(
    r'(?<!\d)(2160|1440|1080|720|576|540|480|360|240)(?:[pi](?![a-z])|\b)|(?<![a-z0-9])(?:4k|uhd)(?![a-z0-9])',
    caseSensitive: false,
  );

  static int? _readHeight(String text) {
    final match = _height.firstMatch(text.replaceAll('_', ' '));
    return match == null ? null : int.tryParse(match.group(1) ?? '') ?? 2160;
  }

  String get selectionSourceId => streamSelectionSourceId(providerId);
  Set<String> get namedAudioLanguages =>
      StreamSelection.releaseAudioLanguages(title);

  String? get pickerAudioLabel {
    if (audioTracks.isNotEmpty) {
      final labels = <String>{};
      for (final (index, raw) in audioTracks.indexed) {
        final label = raw.trim();
        if (StreamSelection.isUnspecifiedAudioLanguage(label)) {
          labels.add('Track ${index + 1} · Language unknown');
          continue;
        }
        final code = StreamSelection._languageCode(label.toLowerCase());
        labels.add(code == null ? label : StreamSelection._languageName(code));
      }
      return labels.join(' / ');
    }
    final reported = audio?.trim();
    final fromName = StreamSelection.releaseAudioLabel(title);
    if (fromName != null) return fromName;
    return audioType ??
        (reported == null || reported.isEmpty ? null : reported);
  }

  String get releaseLabel =>
      '$provider $quality ${audio ?? ''} $title'.split('\n').join(' ').trim();
  int? get resolution {
    if (videoHeights.length == 1) return videoHeights.single;
    return reportedResolution ??
        torrent?.parsed.resolution ??
        _readHeight(title);
  }

  int? get reportedResolution => _readHeight(quality);

  List<int> get knownResolutions => videoHeights.isNotEmpty
      ? videoHeights
      : [if (resolution case final int height) height];

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
