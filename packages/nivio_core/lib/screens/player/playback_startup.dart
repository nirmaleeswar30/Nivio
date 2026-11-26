import 'package:media_kit/media_kit.dart';

enum PlaybackStartupStage {
  building('Building player…'),
  opening('Starting stream…'),
  buffering('Buffering…'),
  started('Buffering…');

  const PlaybackStartupStage(this.message);

  final String message;
}

/// Tracks startup for one source. Once playback begins, buffering and seeks
/// are handled by the player controls.
class PlaybackStartup {
  var _stage = PlaybackStartupStage.building;
  var _openReturned = false;
  Duration? _lastPosition;

  PlaybackStartupStage get stage => _stage;

  bool get waitingForPlayback =>
      stage == PlaybackStartupStage.opening ||
      stage == PlaybackStartupStage.buffering;

  void startOpening() {
    _stage = PlaybackStartupStage.opening;
    _openReturned = false;
    _lastPosition = null;
  }

  void openReturned() => _openReturned = true;

  void update(PlayerState state) {
    if (!waitingForPlayback || !_openReturned) return;

    final hasVideo = state.tracks.video.any((track) => _isMediaTrack(track.id));
    final hasAudio = state.tracks.audio.any((track) => _isMediaTrack(track.id));
    if (!hasVideo && !hasAudio) {
      _lastPosition = null;
      _stage = PlaybackStartupStage.opening;
      return;
    }

    _stage = PlaybackStartupStage.buffering;
    if (state.buffering || state.completed) {
      _lastPosition = null;
      return;
    }

    if (!state.playing) {
      _lastPosition = null;
      // A watch-party host can pause this client before its clock advances.
      // Decoded output is enough to reveal the paused video in that case.
      final outputReady = hasVideo
          ? (state.videoParams.w ?? 0) > 0
          : (state.audioParams.sampleRate ?? 0) > 0;
      if (outputReady) _stage = PlaybackStartupStage.started;
      return;
    }

    // The initial position can come from a resume seek. Wait for the
    // playback clock to advance from an observed position.
    final previousPosition = _lastPosition;
    _lastPosition = state.position > Duration.zero ? state.position : null;
    if (previousPosition != null && state.position > previousPosition) {
      _stage = PlaybackStartupStage.started;
    }
  }

  static bool _isMediaTrack(String id) => id != 'auto' && id != 'no';
}
