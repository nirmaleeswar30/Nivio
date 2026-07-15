import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image/image.dart' as img;
import 'package:material_color_utilities/material_color_utilities.dart';
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

/// Helper function to extract seed color inside isolate (async to support await quantize)
Future<int> extractSeedColor(Uint8List bytes) async {
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw Exception('Failed to decode image');
  }
  // Resize to 50x50 to make quantization extremely fast (<1ms)
  final resized = img.copyResize(image, width: 50, height: 50);
  final List<int> argbPixels = [];
  for (final pixel in resized) {
    final a = pixel.a.toInt();
    final r = pixel.r.toInt();
    final g = pixel.g.toInt();
    final b = pixel.b.toInt();
    argbPixels.add((a << 24) | (r << 16) | (g << 8) | b);
  }
  final quantizerResult = await QuantizerCelebi().quantize(argbPixels, 128);
  final colorToCount = quantizerResult.colorToCount;
  if (colorToCount.isEmpty) {
    throw Exception('No colors found');
  }
  return colorToCount.keys.reduce((a, b) =>
      colorToCount[a]! > colorToCount[b]! ? a : b);
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
    Uint8List bytes;
    final cacheManager = DefaultCacheManager();
    final fileInfo = await cacheManager.getFileFromCache(imageUrl);
    
    if (fileInfo != null) {
      bytes = await fileInfo.file.readAsBytes();
    } else {
      final file = await cacheManager.getSingleFile(imageUrl);
      bytes = await file.readAsBytes();
    }

    // Spawns background isolate to decode and run Celebi quantization
    final seedColorValue = await compute(extractSeedColor, bytes);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: Color(seedColorValue),
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
