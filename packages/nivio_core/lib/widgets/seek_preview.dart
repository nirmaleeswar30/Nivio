import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/network_client_factory.dart';

/// One cue of a WebVTT thumbnails track: a time range and the sprite-sheet
/// tile (`sprite.webp#xywh=x,y,w,h`) that previews it.
class SeekPreviewCue {
  final Duration start;
  final Duration end;
  final String imageUrl;
  final Rect? region; // null = the whole image

  const SeekPreviewCue(this.start, this.end, this.imageUrl, this.region);
}

/// Seek-bar thumbnail previews from a server's WebVTT sprite map (the kind
/// web players such as JW Player / Vidstack use).
///
/// Loads the VTT once, then fetches and decodes sprite sheets on demand, with
/// the stream's headers (the preview CDNs check the same Referer). Requests go
/// through the app's network client (Cronet on Android), like stream segments.
class SeekPreviewLoader {
  final String vttUrl;
  final Map<String, String> headers;

  SeekPreviewLoader({required this.vttUrl, Map<String, String> headers = const {}})
      : headers = {
          'Accept': '*/*',
          'Sec-Fetch-Site': 'cross-site',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Dest': 'empty',
          ...headers,
        };

  final http.Client _client = NetworkClientFactory.createClient();
  List<SeekPreviewCue> _cues = const [];
  bool _disposed = false;

  /// Decoded sprite sheets, most recently used last. Sheets are ~1-2k px
  /// wide, so only a few are kept.
  final LinkedHashMap<String, ui.Image> _images = LinkedHashMap();
  final Map<String, Future<ui.Image?>> _pending = {};
  static const _maxImages = 4;

  /// Becomes true once the track has loaded and has cues.
  final ValueNotifier<bool> ready = ValueNotifier(false);

  Future<void> load() async {
    try {
      final res = await _client.get(Uri.parse(vttUrl), headers: headers).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        appDebugLog('🖼️ Seek previews: VTT returned ${res.statusCode} ($vttUrl)');
        return;
      }
      final cues = parse(utf8.decode(res.bodyBytes, allowMalformed: true), Uri.parse(vttUrl));
      if (_disposed || cues.isEmpty) return;
      _cues = cues;
      ready.value = true;
      appDebugLog('🖼️ Seek previews: ${cues.length} cues from $vttUrl');
      // Warm the first sheet so the first drag shows a tile straight away.
      unawaited(image(cues.first.imageUrl));
    } catch (e) {
      appDebugLog('🖼️ Seek previews unavailable: $e');
    }
  }

  static final _timing = RegExp(r'((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})\s*-->\s*((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})');

  /// Parses a WebVTT thumbnails track; image paths resolve against [base].
  /// Returns no cues for anything else (e.g. a real subtitle file).
  static List<SeekPreviewCue> parse(String vtt, Uri base) {
    final text = vtt.replaceFirst('﻿', '');
    if (!text.trimLeft().startsWith('WEBVTT')) return const [];
    final lines = const LineSplitter().convert(text);
    final cues = <SeekPreviewCue>[];
    for (var i = 0; i < lines.length; i++) {
      final m = _timing.firstMatch(lines[i]);
      if (m == null) continue;
      // The cue's payload is the line right after the timing line.
      if (i + 1 >= lines.length || lines[i + 1].trim().isEmpty) continue;
      final target = lines[i + 1].trim();
      final hash = target.indexOf('#');
      final path = hash >= 0 ? target.substring(0, hash) : target;
      // Only image cues: a subtitle track has plain text here.
      if (!RegExp(r'\.(jpe?g|png|webp|gif|bmp)(\?|$)', caseSensitive: false).hasMatch(path) && !path.startsWith('http')) {
        continue;
      }
      Rect? region;
      final xywh = RegExp(r'xywh=(\d+),(\d+),(\d+),(\d+)').firstMatch(target);
      if (xywh != null) {
        final v = [for (var k = 1; k <= 4; k++) double.parse(xywh.group(k)!)];
        region = Rect.fromLTWH(v[0], v[1], v[2], v[3]);
      }
      cues.add(SeekPreviewCue(_time(m.group(1)!), _time(m.group(2)!), base.resolve(path).toString(), region));
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  static Duration _time(String s) {
    final parts = s.replaceAll(',', '.').split(':');
    final seconds = double.parse(parts.last);
    final minutes = int.parse(parts[parts.length - 2]);
    final hours = parts.length > 2 ? int.parse(parts[0]) : 0;
    return Duration(milliseconds: ((hours * 3600 + minutes * 60 + seconds) * 1000).round());
  }

  /// The cue covering [position] (binary search), or the nearest one.
  SeekPreviewCue? cueAt(Duration position) {
    if (_cues.isEmpty) return null;
    var lo = 0, hi = _cues.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_cues[mid].start <= position) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return _cues[lo];
  }

  /// A decoded sprite sheet if it's already loaded (no waiting).
  ui.Image? cachedImage(String url) {
    final img = _images.remove(url);
    if (img != null) _images[url] = img; // mark as recently used
    return img;
  }

  /// Fetches and decodes a sprite sheet (deduplicated, cached).
  Future<ui.Image?> image(String url) {
    final cached = cachedImage(url);
    if (cached != null) return Future.value(cached);
    return _pending[url] ??= () async {
      try {
        final res = await _client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200 || _disposed) return null;
        final codec = await ui.instantiateImageCodec(res.bodyBytes);
        final frame = await codec.getNextFrame();
        if (_disposed) {
          frame.image.dispose();
          return null;
        }
        _images[url] = frame.image;
        while (_images.length > _maxImages) {
          final oldest = _images.keys.first;
          _images.remove(oldest)?.dispose();
        }
        return frame.image;
      } catch (e) {
        appDebugLog('🖼️ Seek preview sprite failed: $e');
        return null;
      } finally {
        _pending.remove(url);
      }
    }();
  }

  void dispose() {
    _disposed = true;
    ready.dispose();
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
    _client.close();
  }
}

/// The preview tile for [position], with the time underneath. Shows the
/// previous tile while a new sprite sheet is still loading.
class SeekPreviewThumbnail extends StatefulWidget {
  final SeekPreviewLoader loader;
  final Duration position;
  final String label;
  final Size size;

  const SeekPreviewThumbnail({
    super.key,
    required this.loader,
    required this.position,
    required this.label,
    required this.size,
  });

  @override
  State<SeekPreviewThumbnail> createState() => _SeekPreviewThumbnailState();
}

class _SeekPreviewThumbnailState extends State<SeekPreviewThumbnail> {
  ui.Image? _image;
  Rect? _region;

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(covariant SeekPreviewThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) _update();
  }

  void _update() {
    final cue = widget.loader.cueAt(widget.position);
    if (cue == null) return;
    final cached = widget.loader.cachedImage(cue.imageUrl);
    if (cached != null) {
      _image = cached;
      _region = cue.region;
      return;
    }
    widget.loader.image(cue.imageUrl).then((img) {
      if (!mounted || img == null) return;
      // Still the tile we want? (the finger may have moved on)
      final now = widget.loader.cueAt(widget.position);
      if (now?.imageUrl != cue.imageUrl) return;
      setState(() {
        _image = img;
        _region = now!.region;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: widget.size.width,
          height: widget.size.height,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
          ),
          clipBehavior: Clip.antiAlias,
          child: _image == null
              ? const Center(
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : CustomPaint(painter: _TilePainter(_image!, _region)),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xE6151515), borderRadius: BorderRadius.circular(6)),
          child: Text(
            widget.label,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _TilePainter extends CustomPainter {
  final ui.Image image;
  final Rect? region;

  _TilePainter(this.image, this.region);

  @override
  void paint(Canvas canvas, Size size) {
    final src = region ?? Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    // Cover the box, keeping the tile's aspect ratio.
    final scale = (size.width / src.width) > (size.height / src.height)
        ? size.width / src.width
        : size.height / src.height;
    final w = src.width * scale, h = src.height * scale;
    final dst = Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
    canvas.drawImageRect(image, src, dst, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(covariant _TilePainter old) => old.image != image || old.region != region;
}
