import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:nivio/core/constants.dart';

final _imageBase = Uri.parse(tmdbImageBaseUrl);
final _imageSize = RegExp(r'^(original|[wh]\d+)$');
const _logoWidths = [45, 92, 154, 185, 300, 500];

enum ArtworkKind {
  poster(2 / 3, [92, 154, 185, 342, 500, 780]),
  backdrop(16 / 9, [300, 780, 1280]),
  still(16 / 9, [92, 185, 300]),
  logo(3, _logoWidths),
  badge(1, _logoWidths),
  profile(2 / 3, [45, 185]);

  const ArtworkKind(this.aspectRatio, this.widths);

  final double aspectRatio;
  final List<int> widths;

  String variantFor(double pixels) {
    final width = widths.firstWhere(
      (width) => width >= pixels,
      orElse: () => widths.last,
    );
    return 'w$width';
  }
}

/// Requests a smaller TMDB variant, including for URLs already stored in caches.
/// Artwork from other providers keeps its original URL.
String? tmdbArtworkUrl(String? path, String size) {
  if (path == null || path.isEmpty) return null;
  final uri = Uri.tryParse(path);
  if (uri == null) return null;
  if (!uri.hasScheme && !uri.hasAuthority) {
    final variant = uri.path.toLowerCase().endsWith('.svg') ? 'original' : size;
    return '$tmdbImageBaseUrl/$variant/${path.startsWith('/') ? path.substring(1) : path}';
  }

  final segments = uri.pathSegments;
  if ((uri.host != _imageBase.host && uri.host != 'image.tmdb.org') ||
      segments.length != 4 ||
      segments[0] != 't' ||
      segments[1] != 'p' ||
      !_imageSize.hasMatch(segments[2]) ||
      segments.last.toLowerCase().endsWith('.svg')) {
    return path;
  }

  return uri.replace(pathSegments: ['t', 'p', size, segments.last]).toString();
}

/// Selects a TMDB variant for the fitted box and also bounds decoded images
/// from providers whose URLs cannot be resized.
ImageProvider artworkImageProvider(
  String path, {
  double? width,
  double? height,
  double pixelRatio = 1,
  ArtworkKind kind = ArtworkKind.poster,
  BoxFit fit = BoxFit.cover,
  int? maxDecodeWidth,
}) {
  final ratio = kind.aspectRatio;
  final w = width != null && width.isFinite && width > 0 ? width : null;
  final h = height != null && height.isFinite && height > 0 ? height : null;
  final double targetWidth;
  if (w != null && h != null) {
    targetWidth = switch (fit) {
      BoxFit.contain || BoxFit.scaleDown => math.min(w, h * ratio),
      BoxFit.cover => math.max(w, h * ratio),
      BoxFit.fitHeight => h * ratio,
      _ => w,
    };
  } else {
    targetWidth = w ?? (h == null ? 160 : h * ratio);
  }

  final widthCap = maxDecodeWidth ?? 1280;
  final pixelsWide = math.min(targetWidth * pixelRatio, widthCap.toDouble());
  final pixelsHigh = kind == ArtworkKind.logo && h != null
      ? h * pixelRatio
      : pixelsWide / ratio;
  // Bucket nearby sizes so resizing the desktop window reuses decoded entries.
  final widthLimit = math.min(_decodeBucket(pixelsWide), widthCap);
  final heightLimit = _decodeBucket(pixelsHigh);
  final url = tmdbArtworkUrl(path, kind.variantFor(pixelsWide)) ?? path;
  return ResizeImage(
    CachedNetworkImageProvider(url),
    width: widthLimit,
    height: heightLimit,
    policy: ResizeImagePolicy.fit,
  );
}

int _decodeBucket(double pixels) {
  final step = pixels > 500 ? 128 : 16;
  return ((pixels / step).ceil() * step).clamp(16, 1280);
}

/// A small, separate cache entry for palette extraction.
ImageProvider artworkPaletteProvider(String path) => ResizeImage(
  CachedNetworkImageProvider(tmdbArtworkUrl(path, 'w185') ?? path),
  width: 128,
  height: 128,
  policy: ResizeImagePolicy.fit,
);
