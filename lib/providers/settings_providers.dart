import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/episode_check_service.dart';
import '../core/theme.dart';

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
];

String appAccentLabelFromKey(String key) {
  for (final option in appAccentOptions) {
    if (option.key == key) {
      return option.label;
    }
  }
  return appAccentOptions.first.label;
}

Color appAccentColorFromKey(String key) {
  for (final option in appAccentOptions) {
    if (option.key == key) {
      return option.color;
    }
  }
  return appAccentOptions.first.color;
}

// App Accent Color Provider
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

// Subtitle Enabled Provider
final subtitlesEnabledProvider =
    StateNotifierProvider<SubtitlesEnabledNotifier, bool>((ref) {
      return SubtitlesEnabledNotifier();
    });

class SubtitlesEnabledNotifier extends StateNotifier<bool> {
  SubtitlesEnabledNotifier() : super(false) {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('subtitles_enabled') ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('subtitles_enabled', state);
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

// Net22 Audio Language Preference Provider
final net22AudioLanguageProvider =
    StateNotifierProvider<Net22AudioLanguageNotifier, String>((ref) {
      return Net22AudioLanguageNotifier();
    });

class Net22AudioLanguageNotifier extends StateNotifier<String> {
  Net22AudioLanguageNotifier() : super('auto') {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('net22_audio_language') ?? 'auto';
  }

  Future<void> setPreference(String preference) async {
    final normalized = preference.trim().isEmpty ? 'auto' : preference.trim();
    state = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('net22_audio_language', normalized);
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

// Episode Check Frequency Provider
final episodeCheckFrequencyProvider =
    StateNotifierProvider<EpisodeCheckFrequencyNotifier, int>((ref) {
      return EpisodeCheckFrequencyNotifier();
    });

class EpisodeCheckFrequencyNotifier extends StateNotifier<int> {
  EpisodeCheckFrequencyNotifier() : super(24) {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    state = await EpisodeCheckService.getFrequency();
  }

  Future<void> setFrequency(int hours) async {
    state = hours;
    await EpisodeCheckService.setFrequency(hours);
  }

  String get displayName {
    switch (state) {
      case 12:
        return 'Every 12 hours';
      case 24:
        return 'Daily';
      case 48:
        return 'Every 2 days';
      default:
        return 'Every $state hours';
    }
  }
}
