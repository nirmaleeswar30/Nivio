import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global signal indicating the video player screen is currently active.
/// When true, background tasks (banner slider, color extraction, etc.)
/// should pause to prioritize resources for smooth video playback.
///
/// NOTE: This intentionally does NOT affect the next-episode prefetcher
/// inside the player itself — only home screen background work.
final isPlayerActiveProvider = StateProvider<bool>((ref) => false);
