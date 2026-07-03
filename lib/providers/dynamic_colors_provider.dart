import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:nivio/core/debug_log.dart';

/// Dynamic color scheme generated from poster/backdrop art
class DynamicColors {
  final Color dominant;
  final Color darkMuted;
  final Color darkVibrant;
  final Color lightVibrant;
  final Color lightMuted;
  final Color onSurface;

  const DynamicColors({
    required this.dominant,
    required this.darkMuted,
    required this.darkVibrant,
    required this.lightVibrant,
    required this.lightMuted,
    required this.onSurface,
  });

  /// Default Netflix-like colors
  static const fallback = DynamicColors(
    dominant: Color(0xFFE50914),
    darkMuted: Color(0xFF141414),
    darkVibrant: Color(0xFF8B0000),
    lightVibrant: Color(0xFFFF4444),
    lightMuted: Color(0xFF2F2F2F),
    onSurface: Colors.white,
  );
}

/// Provider that extracts colors from an image URL
final dynamicColorsProvider = FutureProvider.family<DynamicColors, String?>((
  ref,
  imageUrl,
) async {
  if (imageUrl == null || imageUrl.isEmpty) {
    return DynamicColors.fallback;
  }

  try {
    final colorScheme = await ColorScheme.fromImageProvider(
      provider: CachedNetworkImageProvider(imageUrl),
      brightness: Brightness.dark,
    );

    final dominant = colorScheme.primary;
    final darkMuted = colorScheme.surface;
    final darkVibrant = colorScheme.secondary;
    final lightVibrant = colorScheme.tertiary;
    final lightMuted = colorScheme.surfaceContainerHighest;

    // Ensure text readability
    final onSurface =
        ThemeData.estimateBrightnessForColor(darkMuted) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return DynamicColors(
      dominant: dominant,
      darkMuted: darkMuted,
      darkVibrant: darkVibrant,
      lightVibrant: lightVibrant,
      lightMuted: lightMuted,
      onSurface: onSurface,
    );
  } catch (e) {
    appDebugLog('⚠️ Failed to extract colors: $e');
    return DynamicColors.fallback;
  }
});

