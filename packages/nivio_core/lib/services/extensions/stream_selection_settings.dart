import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StreamSelectionMode {
  manual('Manual'),
  first('Fastest First'),
  match('Match Preferences');

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
  hevc('HEVC / x265'),
  hdr('HDR10'),
  dolbyVision('Dolby Vision');

  const StreamFeature(this.label);
  final String label;
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
    StreamPreset preset,
  ) {
    final resolutions = (data['resolutions'] as List?)
        ?.whereType<int>()
        .toSet();
    Set<T>? readSet<T extends Enum>(List<T> values, String key) {
      final names = data[key];
      return names is List
          ? values.where((value) => names.contains(value.name)).toSet()
          : null;
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
      features: readSet(StreamFeature.values, 'features'),
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
    this.presetOptions = const {},
    this.regex = '',
    this.timeoutSeconds = 8,
    this.reuseBingeGroup = true,
    this.matchAudio = true,
  });

  final StreamSelectionMode mode;
  final StreamPreset preset;
  final List<String> sourceOrder;
  final Map<StreamPreset, StreamPresetOptions> presetOptions;
  final String regex;
  final int timeoutSeconds;
  final bool reuseBingeGroup;
  final bool matchAudio;

  List<int> get resolutions =>
      presetOptions[preset]?.resolutions ?? preset.resolutions;
  int get maxFileGb => presetOptions[preset]?.maxFileGb ?? 0;
  Set<StreamExclusion> get exclusions =>
      presetOptions[preset]?.exclusions ??
      {StreamExclusion.cam, StreamExclusion.ts, StreamExclusion.hdcam};
  Set<StreamFeature> get features =>
      presetOptions[preset]?.features ??
      switch (preset) {
        StreamPreset.dataSaver => {StreamFeature.hevc},
        StreamPreset.balanced => {},
        StreamPreset.maxQuality => {
          StreamFeature.hdr,
          StreamFeature.dolbyVision,
        },
      };

  StreamSelectionSettings copyWith({
    StreamSelectionMode? mode,
    StreamPreset? preset,
    List<String>? sourceOrder,
    List<int>? customResolutions,
    Set<StreamExclusion>? customExclusions,
    Set<StreamFeature>? customFeatures,
    int? maxFileGb,
    String? regex,
    int? timeoutSeconds,
    bool? reuseBingeGroup,
    bool? matchAudio,
  }) {
    final activePreset = preset ?? this.preset;
    final options = presetOptions[activePreset];
    return StreamSelectionSettings(
      mode: mode ?? this.mode,
      preset: activePreset,
      sourceOrder: sourceOrder ?? this.sourceOrder,
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
    );
  }

  int sourceRank(String id) {
    final index = sourceOrder.indexOf(id);
    return index < 0 ? sourceOrder.length : index;
  }

  static const _key = 'stream_selection_preferences';

  static StreamSelectionSettings read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return const StreamSelectionSettings();
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
      return StreamSelectionSettings(
        mode: readEnum(
          StreamSelectionMode.values,
          'mode',
          StreamSelectionMode.manual,
        ),
        preset: preset,
        sourceOrder:
            (data['sourceOrder'] as List?)
                ?.whereType<String>()
                .toSet()
                .toList() ??
            const [],
        presetOptions: {
          for (final preset in StreamPreset.values)
            if (savedOptions[preset.name]
                case final Map<String, dynamic> options)
              preset: StreamPresetOptions.fromJson(options, preset),
        },
        regex: data['regex'] as String? ?? '',
        timeoutSeconds: (data['timeoutSeconds'] as int? ?? 8).clamp(1, 30),
        reuseBingeGroup: data['reuseBingeGroup'] as bool? ?? true,
        matchAudio: data['matchAudio'] as bool? ?? true,
      );
    } on FormatException {
      return const StreamSelectionSettings();
    } on TypeError {
      return const StreamSelectionSettings();
    }
  }

  Future<bool> save(SharedPreferences prefs) => prefs.setString(
    _key,
    jsonEncode({
      'mode': mode.name,
      'preset': preset.name,
      'sourceOrder': sourceOrder,
      'presetOptions': {
        for (final entry in presetOptions.entries)
          entry.key.name: entry.value.toJson(),
      },
      'regex': regex,
      'timeoutSeconds': timeoutSeconds,
      'reuseBingeGroup': reuseBingeGroup,
      'matchAudio': matchAudio,
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
    final next = update(state.valueOrNull ?? await future);
    state = AsyncData(next);
    await next.save(await SharedPreferences.getInstance());
  }
}
