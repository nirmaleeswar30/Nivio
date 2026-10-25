import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/episode_check_service.dart';
import '../core/theme.dart';

// SharedPreferences loaded once before runApp, so settings that are read
// synchronously (e.g. the torrent toggles consulted when the player builds its
// provider list) start from the saved value instead of a hard-coded default
// that is only corrected after an async load.
SharedPreferences? _startupPrefs;

Future<void> preloadSettingsPrefs() async {
  _startupPrefs = await SharedPreferences.getInstance();
}

class AppAccentOption {
  const AppAccentOption({
    required this.key,
    required this.label,
    required this.color,
  });

  final String key;
  final String label;
  final Color color;
}

const List<AppAccentOption> appAccentOptions = [
  AppAccentOption(key: 'red', label: 'Red', color: NivioTheme.netflixRed),
  AppAccentOption(key: 'blue', label: 'Blue', color: Color(0xFF3B82F6)),
  AppAccentOption(key: 'green', label: 'Green', color: Color(0xFF22C55E)),
  AppAccentOption(key: 'orange', label: 'Orange', color: Color(0xFFF97316)),
  AppAccentOption(key: 'pink', label: 'Pink', color: Color(0xFFEC4899)),
  AppAccentOption(key: 'purple', label: 'Purple', color: Color(0xFFA855F7)),
  AppAccentOption(key: 'teal', label: 'Teal', color: Color(0xFF14B8A6)),
  AppAccentOption(key: 'yellow', label: 'Yellow', color: Color(0xFFEAB308)),
  AppAccentOption(key: 'cyan', label: 'Cyan', color: Color(0xFF06B6D4)),
];

String appAccentLabelFromKey(String key) {
  for (final option in appAccentOptions) {
    if (option.key == key) {
      return option.label;
    }
  }
  if (key.startsWith('#')) {
    return 'Custom ($key)';
  }
  return appAccentOptions.first.label;
}

Color appAccentColorFromKey(String key) {
  for (final option in appAccentOptions) {
    if (option.key == key) {
      return option.color;
    }
  }
  if (key.startsWith('#')) {
    try {
      final hexString = key.substring(1);
      if (hexString.length == 6) {
        return Color(int.parse(hexString, radix: 16) | 0xFF000000);
      }
    } catch (_) {}
  }
  return appAccentOptions.first.color;
}

// App Theme Provider (full color schemes: System, Blackout, Monokai, Catppuccin, Dracula, Amber, Lavender)
final appThemeProvider =
    StateNotifierProvider<AppThemeNotifier, String>((ref) {
  return AppThemeNotifier();
});

class AppThemeNotifier extends StateNotifier<String> {
  AppThemeNotifier() : super('system') {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('app_theme');
    if (savedTheme != null) {
      state = _normalizeTheme(savedTheme);
      return;
    }
    // Migrate legacy accent color if present
    final oldAccent = prefs.getString('app_accent_color');
    if (oldAccent != null) {
      state = _mapOldAccentToTheme(oldAccent);
      await prefs.setString('app_theme', state);
      return;
    }
    state = 'system';
  }

  Future<void> setTheme(String key) async {
    final normalized = _normalizeTheme(key);
    state = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme', normalized);
  }

  String _normalizeTheme(String key) {
    for (final theme in NivioTheme.availableThemes) {
      if (theme.key == key) return key;
    }
    return 'system';
  }

  String _mapOldAccentToTheme(String oldAccent) {
    switch (oldAccent.toLowerCase()) {
      case 'purple':
        return 'dracula';
      case 'green':
        return 'monokai';
      case 'yellow':
      case 'orange':
        return 'amber';
      case 'pink':
      case 'teal':
      case 'blue':
        return 'catppuccin';
      default:
        return 'system';
    }
  }
}

// UI Scale Provider (Zoom level slider)
final uiScaleProvider =
    StateNotifierProvider<UiScaleNotifier, double>((ref) {
  return UiScaleNotifier();
});

class UiScaleNotifier extends StateNotifier<double> {
  static const double defaultScale = 1.0;
  static const double minScale = 0.75;
  static const double maxScale = 1.35;

  UiScaleNotifier() : super(defaultScale) {
    _loadScale();
  }

  Future<void> _loadScale() async {
    final prefs = await SharedPreferences.getInstance();
    final savedScale = prefs.getDouble('ui_scale') ?? defaultScale;
    state = savedScale.clamp(minScale, maxScale);
  }

  void setPreviewScale(double scale) {
    final clamped = scale.clamp(minScale, maxScale);
    final rounded = (clamped * 100).round() / 100;
    state = rounded;
  }

  Future<void> setScale(double scale) async {
    final clamped = scale.clamp(minScale, maxScale);
    final rounded = (clamped * 100).round() / 100;
    state = rounded;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ui_scale', rounded);
  }

  Future<void> resetToDefault() async {
    state = defaultScale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ui_scale', defaultScale);
  }
}

// UI Scale Confirmation State & Provider
class UiScaleConfirmationData {
  final bool isVisible;
  final int secondsRemaining;
  final double previousScale;
  final double proposedScale;

  const UiScaleConfirmationData({
    this.isVisible = false,
    this.secondsRemaining = 5,
    this.previousScale = 1.0,
    this.proposedScale = 1.0,
  });

  UiScaleConfirmationData copyWith({
    bool? isVisible,
    int? secondsRemaining,
    double? previousScale,
    double? proposedScale,
  }) {
    return UiScaleConfirmationData(
      isVisible: isVisible ?? this.isVisible,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      previousScale: previousScale ?? this.previousScale,
      proposedScale: proposedScale ?? this.proposedScale,
    );
  }
}

final uiScaleConfirmationProvider =
    StateNotifierProvider<UiScaleConfirmationNotifier, UiScaleConfirmationData>((ref) {
  return UiScaleConfirmationNotifier(ref);
});

class UiScaleConfirmationNotifier extends StateNotifier<UiScaleConfirmationData> {
  final Ref _ref;
  Timer? _timer;

  UiScaleConfirmationNotifier(this._ref) : super(const UiScaleConfirmationData());

  void requestScaleChange(double proposedScale) {
    final currentScale = _ref.read(uiScaleProvider);
    final clampedProposed = proposedScale.clamp(
      UiScaleNotifier.minScale,
      UiScaleNotifier.maxScale,
    );
    final roundedProposed = (clampedProposed * 100).round() / 100;

    // If already at proposed scale and not currently confirming, no-op
    if (!state.isVisible && (currentScale - roundedProposed).abs() < 0.001) {
      return;
    }

    final prev = state.isVisible ? state.previousScale : currentScale;

    // If proposed is same as the original previous scale, just revert directly
    if ((prev - roundedProposed).abs() < 0.001) {
      revert();
      return;
    }

    // Apply preview scale immediately so app visually zooms
    _ref.read(uiScaleProvider.notifier).setPreviewScale(roundedProposed);

    // Cancel any running timer
    _timer?.cancel();

    // Start 5-second countdown
    state = UiScaleConfirmationData(
      isVisible: true,
      secondsRemaining: 5,
      previousScale: prev,
      proposedScale: roundedProposed,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.secondsRemaining > 1) {
        state = state.copyWith(secondsRemaining: state.secondsRemaining - 1);
      } else {
        // 5 seconds elapsed! Automatically revert!
        _timer?.cancel();
        revert();
      }
    });
  }

  void confirm() {
    _timer?.cancel();
    if (state.isVisible) {
      _ref.read(uiScaleProvider.notifier).setScale(state.proposedScale);
    }
    state = const UiScaleConfirmationData(isVisible: false);
  }

  void revert() {
    _timer?.cancel();
    if (state.isVisible) {
      _ref.read(uiScaleProvider.notifier).setScale(state.previousScale);
    }
    state = const UiScaleConfirmationData(isVisible: false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// App Accent Color Provider (legacy compatibility)
final appAccentColorProvider =
    StateNotifierProvider<AppAccentColorNotifier, String>((ref) {
      return AppAccentColorNotifier();
    });

class AppAccentColorNotifier extends StateNotifier<String> {
  AppAccentColorNotifier() : super(appAccentOptions.first.key) {
    _loadAccentColor();
  }

  Future<void> _loadAccentColor() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey =
        prefs.getString('app_accent_color') ?? appAccentOptions.first.key;
    state = _normalize(savedKey);
  }

  Future<void> setAccentColor(String key) async {
    final normalized = _normalize(key);
    state = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_accent_color', normalized);
  }

  String _normalize(String key) {
    for (final option in appAccentOptions) {
      if (option.key == key) {
        return key;
      }
    }
    if (key.startsWith('#')) return key;
    return appAccentOptions.first.key;
  }
}

// Playback Speed Provider
final playbackSpeedProvider =
    StateNotifierProvider<PlaybackSpeedNotifier, double>((ref) {
      return PlaybackSpeedNotifier();
    });

class PlaybackSpeedNotifier extends StateNotifier<double> {
  PlaybackSpeedNotifier() : super(1.0) {
    _loadSpeed();
  }

  Future<void> _loadSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getDouble('playback_speed') ?? 1.0;
  }

  Future<void> setSpeed(double speed) async {
    state = speed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('playback_speed', speed);
  }
}

// Video Quality Provider
final videoQualityProvider =
    StateNotifierProvider<VideoQualityNotifier, String>((ref) {
      return VideoQualityNotifier();
    });

class VideoQualityNotifier extends StateNotifier<String> {
  VideoQualityNotifier() : super('auto') {
    _loadQuality();
  }

  Future<void> _loadQuality() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('video_quality') ?? 'auto';
  }

  Future<void> setQuality(String quality) async {
    state = quality;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('video_quality', quality);
  }

  String get displayName {
    switch (state) {
      case 'auto':
        return 'Auto (Best Available)';
      case '2160p':
        return '4K (2160p)';
      case '1080p':
        return 'Full HD (1080p)';
      case '720p':
        return 'HD (720p)';
      case '480p':
        return 'SD (480p)';
      default:
        return 'Auto';
    }
  }
}

// Preferred Subtitle Language Provider
final preferredSubtitleLanguageProvider =
    StateNotifierProvider<PreferredSubtitleLanguageNotifier, String>((ref) {
      return PreferredSubtitleLanguageNotifier();
    });

class PreferredSubtitleLanguageNotifier extends StateNotifier<String> {
  PreferredSubtitleLanguageNotifier() : super('Auto') {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('preferred_subtitle_language') ?? 'Auto';
  }

  Future<void> setLanguage(String language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_subtitle_language', language);
  }
}

// Subtitle Font Size Provider
const Map<String, double> subtitleFontSizeOptions = {
  'Small': 14.0,
  'Medium': 18.0,
  'Large': 24.0,
  'Extra Large': 30.0,
};

const double kDefaultSubtitleFontSize = 18.0;

String subtitleFontSizeLabel(double size) {
  for (final entry in subtitleFontSizeOptions.entries) {
    if (entry.value == size) return entry.key;
  }
  return 'Custom';
}

final subtitleFontSizeProvider =
    StateNotifierProvider<SubtitleFontSizeNotifier, double>((ref) {
      return SubtitleFontSizeNotifier();
    });

class SubtitleFontSizeNotifier extends StateNotifier<double> {
  SubtitleFontSizeNotifier() : super(kDefaultSubtitleFontSize) {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getDouble('subtitle_font_size') ?? kDefaultSubtitleFontSize;
  }

  Future<void> setSize(double size) async {
    state = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('subtitle_font_size', size);
  }
}

// Preferred Audio Language Provider
final preferredAudioLanguageProvider =
    StateNotifierProvider<PreferredAudioLanguageNotifier, String>((ref) {
      return PreferredAudioLanguageNotifier();
    });

class PreferredAudioLanguageNotifier extends StateNotifier<String> {
  PreferredAudioLanguageNotifier() : super('Original') {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('preferred_audio_language') ?? 'Original';
  }

  Future<void> setLanguage(String language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_audio_language', language);
  }
}

// Preferred Download Subtitle Language Provider
final preferredDownloadSubtitleLanguageProvider =
    StateNotifierProvider<PreferredDownloadSubtitleLanguageNotifier, String>((ref) {
      return PreferredDownloadSubtitleLanguageNotifier();
    });

class PreferredDownloadSubtitleLanguageNotifier extends StateNotifier<String> {
  PreferredDownloadSubtitleLanguageNotifier() : super('English') {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('preferred_download_subtitle_language') ?? 'English';
  }

  Future<void> setLanguage(String language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_download_subtitle_language', language);
  }
}

// Preferred Download Audio Language Provider
final preferredDownloadAudioLanguageProvider =
    StateNotifierProvider<PreferredDownloadAudioLanguageNotifier, String>((ref) {
      return PreferredDownloadAudioLanguageNotifier();
    });

class PreferredDownloadAudioLanguageNotifier extends StateNotifier<String> {
  PreferredDownloadAudioLanguageNotifier() : super('English') {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('preferred_download_audio_language') ?? 'English';
  }

  Future<void> setLanguage(String language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_download_audio_language', language);
  }
}

// Animations Enabled Provider
final animationsEnabledProvider =
    StateNotifierProvider<AnimationsEnabledNotifier, bool>((ref) {
      return AnimationsEnabledNotifier();
    });

class AnimationsEnabledNotifier extends StateNotifier<bool> {
  AnimationsEnabledNotifier() : super(true) {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('animations_enabled') ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('animations_enabled', state);
  }
}

// Anime Sub/Dub Preference Provider
final animeSubDubProvider = StateNotifierProvider<AnimeSubDubNotifier, String>((
  ref,
) {
  return AnimeSubDubNotifier();
});

class AnimeSubDubNotifier extends StateNotifier<String> {
  AnimeSubDubNotifier() : super('sub') {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('anime_subdub') ?? 'sub';
  }

  Future<void> setPreference(String preference) async {
    if (preference != 'sub' && preference != 'dub') return;
    state = preference;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('anime_subdub', preference);
  }

  String get displayName {
    return state == 'sub' ? 'Subtitled (Sub)' : 'Dubbed (Dub)';
  }
}


// Anime Source Preference Provider
final preferredAnimeSourceProvider = StateNotifierProvider<PreferredAnimeSourceNotifier, String>((ref) {
  return PreferredAnimeSourceNotifier();
});

class PreferredAnimeSourceNotifier extends StateNotifier<String> {
  PreferredAnimeSourceNotifier() : super('Miruro') {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('preferred_anime_source') ?? 'Miruro';
  }

  Future<void> setPreference(String preference) async {
    state = preference;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_anime_source', preference);
  }
}

// Enable Torrents Provider
final enableTorrentsProvider =
    StateNotifierProvider<EnableTorrentsNotifier, bool>((ref) {
  return EnableTorrentsNotifier();
});

class EnableTorrentsNotifier extends StateNotifier<bool> {
  EnableTorrentsNotifier() : super(_startupPrefs?.getBool('enable_torrents') ?? true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('enable_torrents') ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_torrents', state);
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enable_torrents', enabled);
  }
}
// Episode Check Enabled Provider
final episodeCheckEnabledProvider =
    StateNotifierProvider<EpisodeCheckEnabledNotifier, bool>((ref) {
      return EpisodeCheckEnabledNotifier();
    });

class EpisodeCheckEnabledNotifier extends StateNotifier<bool> {
  EpisodeCheckEnabledNotifier() : super(true) {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    state = await EpisodeCheckService.isEnabled();
  }

  Future<void> toggle() async {
    state = !state;
    await EpisodeCheckService.setEnabled(state);
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await EpisodeCheckService.setEnabled(enabled);
  }
}


// Download Concurrency Provider
final downloadConcurrencyProvider =
    StateNotifierProvider<DownloadConcurrencyNotifier, int>((ref) {
  return DownloadConcurrencyNotifier();
});

class DownloadConcurrencyNotifier extends StateNotifier<int> {
  DownloadConcurrencyNotifier() : super(6) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt('download_concurrency') ?? 6;
  }

  Future<void> setPreference(int value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('download_concurrency', value);
  }
}

// Video Debanding Provider
final videoDebandingProvider =
    StateNotifierProvider<VideoDebandingNotifier, bool>((ref) {
      return VideoDebandingNotifier();
    });

class VideoDebandingNotifier extends StateNotifier<bool> {
  VideoDebandingNotifier() : super(false) {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('video_debanding') ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('video_debanding', state);
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('video_debanding', enabled);
  }
}

// Subtitle Background Provider
final subtitleBackgroundProvider =
    StateNotifierProvider<SubtitleBackgroundNotifier, String>((ref) {
      return SubtitleBackgroundNotifier();
    });

class SubtitleBackgroundNotifier extends StateNotifier<String> {
  SubtitleBackgroundNotifier() : super('Transparent') {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('subtitle_background') ?? 'Transparent';
  }

  Future<void> setBackground(String bg) async {
    state = bg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('subtitle_background', bg);
  }
}

// Subtitle Outline Provider
final subtitleOutlineProvider =
    StateNotifierProvider<SubtitleOutlineNotifier, String>((ref) {
      return SubtitleOutlineNotifier();
    });

class SubtitleOutlineNotifier extends StateNotifier<String> {
  SubtitleOutlineNotifier() : super('Outline') {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('subtitle_outline') ?? 'Outline';
  }

  Future<void> setOutline(String outline) async {
    state = outline;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('subtitle_outline', outline);
  }
}

// Torrent Quality Provider
final torrentQualityProvider =
    StateNotifierProvider<TorrentQualityNotifier, String>((ref) {
  return TorrentQualityNotifier();
});

class TorrentQualityNotifier extends StateNotifier<String> {
  TorrentQualityNotifier() : super('1080') {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('nivio_torrent_resolution') ?? '1080';
  }

  Future<void> setPreference(String value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nivio_torrent_resolution', value);
  }
}

// Torrent Auto Select Provider
final torrentAutoSelectProvider =
    StateNotifierProvider<TorrentAutoSelectNotifier, bool>((ref) {
  return TorrentAutoSelectNotifier();
});

class TorrentAutoSelectNotifier extends StateNotifier<bool> {
  TorrentAutoSelectNotifier() : super(true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('torrent_auto_select') ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('torrent_auto_select', value);
  }
}

// Torrent Persist Files Provider
final torrentPersistFilesProvider =
    StateNotifierProvider<TorrentPersistFilesNotifier, bool>((ref) {
  return TorrentPersistFilesNotifier();
});

class TorrentPersistFilesNotifier extends StateNotifier<bool> {
  TorrentPersistFilesNotifier() : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('torrent_persist_files') ?? false;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('torrent_persist_files', value);
  }
}

// Torrent Source Toggles (Nyaa for anime; Torrentio for movies/shows)
final torrentNyaaEnabledProvider =
    StateNotifierProvider<TorrentNyaaEnabledNotifier, bool>((ref) {
  return TorrentNyaaEnabledNotifier();
});

class TorrentNyaaEnabledNotifier extends StateNotifier<bool> {
  TorrentNyaaEnabledNotifier() : super(_startupPrefs?.getBool('torrent_source_nyaa') ?? true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('torrent_source_nyaa') ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('torrent_source_nyaa', value);
  }
}

final torrentTorrentioEnabledProvider =
    StateNotifierProvider<TorrentTorrentioEnabledNotifier, bool>((ref) {
  return TorrentTorrentioEnabledNotifier();
});

class TorrentTorrentioEnabledNotifier extends StateNotifier<bool> {
  TorrentTorrentioEnabledNotifier() : super(_startupPrefs?.getBool('torrent_source_torrentio') ?? true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('torrent_source_torrentio') ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('torrent_source_torrentio', value);
  }
}

final torrentPirateBayEnabledProvider =
    StateNotifierProvider<TorrentPirateBayEnabledNotifier, bool>((ref) {
  return TorrentPirateBayEnabledNotifier();
});

class TorrentPirateBayEnabledNotifier extends StateNotifier<bool> {
  TorrentPirateBayEnabledNotifier() : super(_startupPrefs?.getBool('torrent_source_piratebay') ?? true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('torrent_source_piratebay') ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('torrent_source_piratebay', value);
  }
}

// Auto Play Next Episode Provider
final autoPlayNextEpisodeProvider =
    StateNotifierProvider<AutoPlayNextEpisodeNotifier, bool>((ref) {
  return AutoPlayNextEpisodeNotifier();
});

class AutoPlayNextEpisodeNotifier extends StateNotifier<bool> {
  AutoPlayNextEpisodeNotifier() : super(true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('auto_play_next_episode') ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_play_next_episode', value);
  }
}

// PiP on Lost Visibility Provider (defaults to true)
final pipOnLostVisibilityProvider =
    StateNotifierProvider<PipOnLostVisibilityNotifier, bool>((ref) {
  return PipOnLostVisibilityNotifier(ref);
});

class PipOnLostVisibilityNotifier extends StateNotifier<bool> {
  final Ref _ref;
  PipOnLostVisibilityNotifier(this._ref) : super(true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('pip_on_lost_visibility') ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pip_on_lost_visibility', value);
    if (value) {
      _ref.read(pauseOnLostVisibilityProvider.notifier).setEnabled(false);
    }
  }
}

// Pause on Lost Visibility Provider (defaults to false)
final pauseOnLostVisibilityProvider =
    StateNotifierProvider<PauseOnLostVisibilityNotifier, bool>((ref) {
  return PauseOnLostVisibilityNotifier(ref);
});

class PauseOnLostVisibilityNotifier extends StateNotifier<bool> {
  final Ref _ref;
  PauseOnLostVisibilityNotifier(this._ref) : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('pause_on_lost_visibility') ?? false;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pause_on_lost_visibility', value);
    if (value) {
      _ref.read(pipOnLostVisibilityProvider.notifier).setEnabled(false);
    }
  }
}

// Ambient Mode Provider (Android phones only; defaults to on). Fills the
// letterbox/pillarbox bars in the player with a soft glow from the video.
final ambientModeProvider =
    StateNotifierProvider<AmbientModeNotifier, bool>((ref) {
  return AmbientModeNotifier();
});

class AmbientModeNotifier extends StateNotifier<bool> {
  AmbientModeNotifier() : super(true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('ambient_mode_enabled') ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ambient_mode_enabled', value);
  }
}

// HDR Output Provider (Android): HDR video on an HDR screen plays as true HDR
// (SurfaceView + mpv's Vulkan renderer). Off, or on SDR screens, HDR video is
// tone-mapped to SDR instead (see toneMappingProvider). Defaults to on.
final hdrOutputProvider = StateNotifierProvider<HdrOutputNotifier, bool>((ref) {
  return HdrOutputNotifier();
});

class HdrOutputNotifier extends StateNotifier<bool> {
  HdrOutputNotifier() : super(_startupPrefs?.getBool('hdr_output_enabled') ?? true) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('hdr_output_enabled') ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hdr_output_enabled', value);
  }
}

// Tone Mapping Provider: how HDR (and wide-gamut BT.2020) video is converted
// to SDR when it isn't shown as true HDR.
//  'standard' — mpv/libplacebo's own tone mapping with per-scene peak detection.
//  'hdrToys'  — the hdr-toys shader pipelines (Astra tone mapping, Bottosson
//               gamut mapping), picked from the video: PQ, HLG or BT.2020.
//               Android only (needs mpv's gpu-next renderer).
const toneMappingModes = ['standard', 'hdrToys'];

final toneMappingProvider = StateNotifierProvider<ToneMappingNotifier, String>((ref) {
  return ToneMappingNotifier();
});

class ToneMappingNotifier extends StateNotifier<String> {
  ToneMappingNotifier() : super(_valid(_startupPrefs?.getString('tone_mapping_mode'))) {
    _loadPreference();
  }

  static String _valid(String? mode) => toneMappingModes.contains(mode) ? mode! : 'standard';

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = _valid(prefs.getString('tone_mapping_mode'));
  }

  Future<void> setMode(String mode) async {
    state = _valid(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tone_mapping_mode', state);
  }
}

// Video Decoder Provider: 'auto', 'hwplus' (direct hardware), 'hw' (hardware
// with copy-back) or 'sw' (CPU). Mapped to mpv's hwdec per platform by the player.
const videoDecoderModes = ['auto', 'hwplus', 'hw', 'sw'];

final videoDecoderProvider =
    StateNotifierProvider<VideoDecoderNotifier, String>((ref) {
  return VideoDecoderNotifier();
});

class VideoDecoderNotifier extends StateNotifier<String> {
  VideoDecoderNotifier() : super(_validMode(_startupPrefs?.getString('video_decoder_mode'))) {
    _loadPreference();
  }

  static String _validMode(String? mode) =>
      videoDecoderModes.contains(mode) ? mode! : 'auto';

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = _validMode(prefs.getString('video_decoder_mode'));
  }

  Future<void> setMode(String mode) async {
    state = _validMode(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('video_decoder_mode', state);
  }
}

// Seek Duration Provider (defaults to 10 seconds)
final seekDurationProvider =
    StateNotifierProvider<SeekDurationNotifier, int>((ref) {
  return SeekDurationNotifier();
});

class SeekDurationNotifier extends StateNotifier<int> {
  SeekDurationNotifier() : super(10) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt('player_seek_duration') ?? 10;
  }

  Future<void> setDuration(int value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('player_seek_duration', value);
  }
}

// Auto Skip Intro / Outro Provider (defaults to false)
final autoSkipIntroOutroProvider =
    StateNotifierProvider<AutoSkipIntroOutroNotifier, bool>((ref) {
  return AutoSkipIntroOutroNotifier();
});

class AutoSkipIntroOutroNotifier extends StateNotifier<bool> {
  AutoSkipIntroOutroNotifier() : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('auto_skip_intro_outro') ?? false;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_skip_intro_outro', value);
  }
}

// Auto Skip Filler Provider (defaults to false)
final autoSkipFillerProvider =
    StateNotifierProvider<AutoSkipFillerNotifier, bool>((ref) {
  return AutoSkipFillerNotifier();
});

class AutoSkipFillerNotifier extends StateNotifier<bool> {
  AutoSkipFillerNotifier() : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('auto_skip_filler') ?? false;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_skip_filler', value);
  }
}

// Use DNS over HTTPS Provider (defaults to false)
final useDnsOverHttpsProvider =
    StateNotifierProvider<UseDnsOverHttpsNotifier, bool>((ref) {
  return UseDnsOverHttpsNotifier();
});

class UseDnsOverHttpsNotifier extends StateNotifier<bool> {
  UseDnsOverHttpsNotifier() : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('use_dns_over_https') ?? false;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_dns_over_https', value);
  }
}

// DNS over HTTPS URL Provider (defaults to https://cloudflare-dns.com/dns-query)
final dnsOverHttpsUrlProvider =
    StateNotifierProvider<DnsOverHttpsUrlNotifier, String>((ref) {
  return DnsOverHttpsUrlNotifier();
});

class DnsOverHttpsUrlNotifier extends StateNotifier<String> {
  static const String defaultDohUrl = 'https://cloudflare-dns.com/dns-query';

  DnsOverHttpsUrlNotifier() : super(defaultDohUrl) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('dns_over_https_url') ?? defaultDohUrl;
  }

  Future<void> setUrl(String url) async {
    final trimmed = url.trim();
    final finalUrl = trimmed.isEmpty ? defaultDohUrl : trimmed;
    state = finalUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dns_over_https_url', finalUrl);
  }

  Future<void> resetToDefault() async {
    state = defaultDohUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dns_over_https_url', defaultDohUrl);
  }
}

// Discord Rich Presence Provider (desktop only, defaults to false)
final discordRpcEnabledProvider =
    StateNotifierProvider<DiscordRpcEnabledNotifier, bool>((ref) {
  return DiscordRpcEnabledNotifier();
});

class DiscordRpcEnabledNotifier extends StateNotifier<bool> {
  DiscordRpcEnabledNotifier() : super(false) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('discord_rpc_enabled') ?? false;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('discord_rpc_enabled', value);
  }
}


