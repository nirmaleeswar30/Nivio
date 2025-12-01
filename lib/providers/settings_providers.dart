import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/episode_check_service.dart';

// Playback Speed Provider
final playbackSpeedProvider = StateNotifierProvider<PlaybackSpeedNotifier, double>((ref) {
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
final videoQualityProvider = StateNotifierProvider<VideoQualityNotifier, String>((ref) {
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
final subtitlesEnabledProvider = StateNotifierProvider<SubtitlesEnabledNotifier, bool>((ref) {
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
final animationsEnabledProvider = StateNotifierProvider<AnimationsEnabledNotifier, bool>((ref) {
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
final animeSubDubProvider = StateNotifierProvider<AnimeSubDubNotifier, String>((ref) {
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

// Episode Check Enabled Provider
final episodeCheckEnabledProvider = StateNotifierProvider<EpisodeCheckEnabledNotifier, bool>((ref) {
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
final episodeCheckFrequencyProvider = StateNotifierProvider<EpisodeCheckFrequencyNotifier, int>((ref) {
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
