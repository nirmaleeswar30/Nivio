import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
