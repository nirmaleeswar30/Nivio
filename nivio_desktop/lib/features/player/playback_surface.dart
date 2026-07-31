import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'playback_engine.dart';

typedef PlaybackControlsBuilder = Widget Function(VideoState state);

/// Optional extension for engines that own their own render surface.
abstract interface class PlaybackSurfaceEngine implements PlaybackEngine {
  Widget buildSurface({
    required BuildContext context,
    required BoxFit fit,
    required PlaybackControlsBuilder controls,
    Future<void> Function()? onEnterFullscreen,
    Future<void> Function()? onExitFullscreen,
  });
}
