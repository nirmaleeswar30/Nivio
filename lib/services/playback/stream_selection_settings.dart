import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'built_in_direct_sources.dart';

enum StreamSelectionMode {
  manual('Manual'),
  first('Fastest First'),
  match('Autoplay');

  const StreamSelectionMode(this.label);
  final String label;
}

enum StreamPreset {
  dataSaver('Data Saver', 'Prefer 720p, HEVC, and smaller files.', [
    720,
    1080,
    480,
    1440,
    2160,
  ]),
  balanced('Balanced', 'Prefer 1080p and clean releases.', [
    1080,
    720,
    2160,
    1440,
    480,
  ]),
  maxQuality('Max Quality', 'Prefer 4K, HDR, and remux releases.', [
    2160,
    1440,
    1080,
    720,
    480,
  ]);

  const StreamPreset(this.label, this.description, this.resolutions);
  final String label;
  final String description;
  final List<int> resolutions;
}

enum StreamExclusion {
  cam('CAM'),
  ts('TS'),
  hdcam('HDCAM'),
  threeD('3D');

  const StreamExclusion(this.label);
  final String label;
}

enum StreamFeature {
  webSources('WEB Sources', r'\bweb[ ._-]?(?:dl|rip)\b'),
  webDl('WEB-DL', r'\bweb[ ._-]?dl\b'),
  bluRayQuality(
    'BluRay Quality',
    r'\b(?:blu[ ._-]?ray|b[dr][ ._-]?rip|remux)\b',
  ),
  bluRay('BluRay', r'\bblu[ ._-]?ray\b'),
  remux('Remux', r'\bremux\b'),
  hevc('HEVC / x265', r'\b(?:x265|h[ ._-]?265|hevc|hev1|hvc1)\b'),
  avc('AVC / x264', r'\b(?:x264|h[ ._-]?264|avc1?)\b'),
  hdr('HDR / HDR10 / HDR10+', r'\bhdr(?:10)?\b'),
  dolbyVision('Dolby Vision', r'\b(?:dovi|dv|dolby[ ._-]?vision)\b'),
  dolbyAtmosDts(
    'Dolby Atmos / DTS',
    r'\b(?:atmos|true[ ._-]?hd|dts(?:[ ._:-]?(?:hd|x))?)\b',
  );

  const StreamFeature(this.label, this.pattern);
  final String label;
  final String pattern;
}

// Nuvio Mobile's regex presets, in the order shown in Playback settings.
enum StreamRegexPreset {
  any1080p('Any 1080p+', r'(2160p|4k|1080p)'),
  remux4k('4K / Remux', r'(2160p|4k|remux)'),
  standard1080p('1080p Standard', r'(1080p|full\s*hd)'),
  smaller720p('720p / Smaller', r'(720p|webrip|web-dl)'),
  webSources('WEB Sources', r'(web[-\s]?dl|webrip)'),
  bluRayQuality('BluRay Quality', r'(bluray|b[dr]rip|remux)'),
  hevc('HEVC / x265', r'(hevc|x265|h\.265)'),
  avc('AVC / x264', r'(x264|h\.264|avc)'),
  hdrDolbyVision('HDR / Dolby Vision', r'(hdr|hdr10\+?|dv|dolby\s*vision)'),
  dolbyAtmosDts('Dolby Atmos / DTS', r'(atmos|truehd|dts[-\s]?hd|dtsx?)'),
  english('English', r'(\beng\b|english)'),
  noCamTs('No CAM/TS', r'^(?!.*\b(cam|hdcam|ts|telesync)\b).*$'),
  // Matching is already case-insensitive. [\s\S] replaces Kotlin's dot-all flag.
  noRemuxHdr(
    'No REMUX/HDR',
    r'^(?![\s\S]*\b(hdr|hdr10|dv|dolby|vision|hevc|remux|2160p)\b)[\s\S]+$',
  );

  const StreamRegexPreset(this.label, this.pattern);
  final String label;
  final String pattern;
}

class StreamPresetOptions {
  const StreamPresetOptions({
    this.resolutions,
    this.exclusions,
    this.features,
    this.maxFileGb = 0,
  });

  final List<int>? resolutions;
  final Set<StreamExclusion>? exclusions;
  final Set<StreamFeature>? features;
  final int maxFileGb;

  factory StreamPresetOptions.fromJson(
    Map<String, dynamic> data,
    StreamPreset preset, {
    required bool migrateFormatBoosts,
  }) {
    final resolutions = (data['resolutions'] as List?)
        ?.whereType<int>()
        .toSet();
    Set<T>? readSet<T extends Enum>(List<T> values, String key) {
      final names = data[key];
      return names is List
          ? values.where((value) => names.contains(value.name)).toSet()
          : null;
    }

    final features = readSet(StreamFeature.values, 'features');
    if (migrateFormatBoosts && features != null) {
      // These format boosts used to apply even to a customised preset.
      features.addAll(switch (preset) {
        StreamPreset.dataSaver => const {},
        StreamPreset.balanced => const {
          StreamFeature.webDl,
          StreamFeature.bluRay,
        },
        StreamPreset.maxQuality => const {StreamFeature.remux},
      });
    }
    return StreamPresetOptions(
      resolutions: resolutions == null
          ? null
          : [
              ...resolutions.where(preset.resolutions.contains),
              ...preset.resolutions.where(
                (height) => !resolutions.contains(height),
              ),
            ],
      exclusions: readSet(StreamExclusion.values, 'exclusions'),
      features: features,
      maxFileGb: (data['maxFileGb'] as int? ?? 0).clamp(0, 100),
    );
  }

  Map<String, dynamic> toJson() => {
    'resolutions': resolutions,
    'exclusions': exclusions?.map((value) => value.name).toList(),
    'features': features?.map((value) => value.name).toList(),
    'maxFileGb': maxFileGb,
  };
}

class StreamSelectionSettings {
  const StreamSelectionSettings({
    this.mode = StreamSelectionMode.manual,
    this.preset = StreamPreset.balanced,
    this.sourceOrder = const [],
    this.animeSourceOrder = const [],
    this.presetOptions = const {},
    this.regex = '',
    this.timeoutSeconds = 8,
    this.reuseBingeGroup = true,
    this.matchAudio = true,
    this.groupBySource = true,
  });

  final StreamSelectionMode mode;
  final StreamPreset preset;
  final List<String> sourceOrder;
  final List<String> animeSourceOrder;
  final Map<StreamPreset, StreamPresetOptions> presetOptions;
  final String regex;
  final int timeoutSeconds;
  final bool reuseBingeGroup;
  final bool matchAudio;
  final bool groupBySource;

  List<int> get resolutions =>
      presetOptions[preset]?.resolutions ?? preset.resolutions;
  int get maxFileGb => presetOptions[preset]?.maxFileGb ?? 0;
  int? get maxFileBytes =>
      maxFileGb > 0 ? maxFileGb * 1024 * 1024 * 1024 : null;
  Set<StreamExclusion> get exclusions =>
      presetOptions[preset]?.exclusions ??
      {StreamExclusion.cam, StreamExclusion.ts, StreamExclusion.hdcam};
  Set<StreamFeature> get features =>
      presetOptions[preset]?.features ??
      switch (preset) {
        StreamPreset.dataSaver => {StreamFeature.hevc},
        StreamPreset.balanced => {StreamFeature.webDl, StreamFeature.bluRay},
        StreamPreset.maxQuality => {
          StreamFeature.hdr,
          StreamFeature.dolbyVision,
          StreamFeature.remux,
        },
      };

  StreamSelectionSettings copyWith({
    StreamSelectionMode? mode,
    StreamPreset? preset,
    List<String>? sourceOrder,
    List<String>? animeSourceOrder,
    List<int>? customResolutions,
    Set<StreamExclusion>? customExclusions,
    Set<StreamFeature>? customFeatures,
    int? maxFileGb,
    String? regex,
    int? timeoutSeconds,
    bool? reuseBingeGroup,
    bool? matchAudio,
    bool? groupBySource,
  }) {
    final activePreset = preset ?? this.preset;
    final options = presetOptions[activePreset];
    return StreamSelectionSettings(
      mode: mode ?? this.mode,
      preset: activePreset,
      sourceOrder: sourceOrder ?? this.sourceOrder,
      animeSourceOrder: animeSourceOrder ?? this.animeSourceOrder,
      presetOptions: {
        ...presetOptions,
        if (customResolutions != null ||
            customExclusions != null ||
            customFeatures != null ||
            maxFileGb != null)
          activePreset: StreamPresetOptions(
            resolutions: customResolutions ?? options?.resolutions,
            exclusions: customExclusions ?? options?.exclusions,
            features: customFeatures ?? options?.features,
            maxFileGb: maxFileGb ?? options?.maxFileGb ?? 0,
          ),
      },
      regex: regex ?? this.regex,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      reuseBingeGroup: reuseBingeGroup ?? this.reuseBingeGroup,
      matchAudio: matchAudio ?? this.matchAudio,
      groupBySource: groupBySource ?? this.groupBySource,
    );
  }

  List<String> sourceOrderFor({required bool isAnime}) =>
      isAnime ? animeSourceOrder : sourceOrder;

  List<RegExp> get torrentFormatPreferences => [
    for (final feature in features)
      RegExp(feature.pattern, caseSensitive: false),
  ];

  int sourceRank(String id, {bool isAnime = false}) {
    final order = sourceOrderFor(isAnime: isAnime);
    final index = order.indexOf(id);
    return index < 0 ? order.length : index;
  }

  static const _key = 'stream_selection_preferences';
  static const _version = 2;

  static StreamSelectionSettings read(SharedPreferences prefs) {
    final legacyAnimeSource = prefs.get('preferred_anime_source');
    final legacyAnimeOrder = [
      if (const {
        'Miruro',
        'Animetsu',
        'Animex',
        'AniKoto',
      }.contains(legacyAnimeSource))
        'builtin:$legacyAnimeSource',
    ];
    final defaults = legacyAnimeOrder.isEmpty
        ? const StreamSelectionSettings()
        : StreamSelectionSettings(animeSourceOrder: legacyAnimeOrder);
    final raw = prefs.getString(_key);
    if (raw == null) return defaults;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      T readEnum<T extends Enum>(List<T> values, String key, T fallback) =>
          values.where((value) => value.name == data[key]).firstOrNull ??
          fallback;
      final preset = readEnum(
        StreamPreset.values,
        'preset',
        StreamPreset.balanced,
      );
      final savedOptions =
          data['presetOptions'] as Map<String, dynamic>? ?? const {};
      final savedVersion = data['version'] as int? ?? 1;
      final savedOrder =
          (data['sourceOrder'] as List?)
              ?.whereType<String>()
              .map(BuiltInDirectSources.legacySourceId)
              .nonNulls
              .toSet()
              .toList() ??
          const <String>[];
      return StreamSelectionSettings(
        mode: readEnum(
          StreamSelectionMode.values,
          'mode',
          StreamSelectionMode.manual,
        ),
        preset: preset,
        sourceOrder: savedOrder,
        animeSourceOrder:
            (data['animeSourceOrder'] as List?)
                ?.whereType<String>()
                .where((id) => id.startsWith('builtin:'))
                .toSet()
                .toList() ??
            (savedOrder.isEmpty ? legacyAnimeOrder : savedOrder),
        presetOptions: {
          for (final preset in StreamPreset.values)
            if (savedOptions[preset.name]
                case final Map<String, dynamic> options)
              preset: StreamPresetOptions.fromJson(
                options,
                preset,
                migrateFormatBoosts: savedVersion < _version,
              ),
        },
        regex: data['regex'] as String? ?? '',
        timeoutSeconds: (data['timeoutSeconds'] as int? ?? 8).clamp(1, 30),
        reuseBingeGroup: data['reuseBingeGroup'] as bool? ?? true,
        matchAudio: data['matchAudio'] as bool? ?? true,
        groupBySource: data['groupBySource'] as bool? ?? true,
      );
    } on FormatException {
      return defaults;
    } on TypeError {
      return defaults;
    }
  }

  Future<bool> save(SharedPreferences prefs) => prefs.setString(
    _key,
    jsonEncode({
      'version': _version,
      'mode': mode.name,
      'preset': preset.name,
      'sourceOrder': sourceOrder,
      'animeSourceOrder': animeSourceOrder,
      'presetOptions': {
        for (final entry in presetOptions.entries)
          entry.key.name: entry.value.toJson(),
      },
      'regex': regex,
      'timeoutSeconds': timeoutSeconds,
      'reuseBingeGroup': reuseBingeGroup,
      'matchAudio': matchAudio,
      'groupBySource': groupBySource,
    }),
  );
}

final streamSelectionSettingsProvider =
    AsyncNotifierProvider<
      StreamSelectionSettingsNotifier,
      StreamSelectionSettings
    >(StreamSelectionSettingsNotifier.new);

class StreamSelectionSettingsNotifier
    extends AsyncNotifier<StreamSelectionSettings> {
  @override
  Future<StreamSelectionSettings> build() async =>
      StreamSelectionSettings.read(await SharedPreferences.getInstance());

  Future<void> change(
    StreamSelectionSettings Function(StreamSelectionSettings) update,
  ) async {
    final next = update(state.value ?? await future);
    state = AsyncData(next);
    await next.save(await SharedPreferences.getInstance());
  }
}
