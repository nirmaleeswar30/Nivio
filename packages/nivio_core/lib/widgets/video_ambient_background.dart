import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

/// YouTube-style "ambient mode": fills the letterbox / pillarbox bars around
/// a "Best Fit" video with a soft glow taken from the picture.
///
/// Used by the player on Android phones only. [child] is the [Video] widget,
/// which must have a transparent fill and be wrapped in a [RepaintBoundary]
/// keyed with [captureKey]. The glow is painted behind it, and (with
/// [edgeFade]) thin strips of the same glow are faded in over the video's
/// edges next to the bars, so the
/// picture melts into the glow instead of ending in a hard line. The strips
/// are small offscreen layers (a few percent of the video's width each), so
/// they cost far less than masking the whole video every frame.
///
/// A few times a second it samples a tiny (~48px wide) copy of the current
/// frame, blurs it, picks a base and an accent colour, and crossfades to the
/// result. Sampling renders the video's layer at that tiny size on the GPU
/// and reads back a few pixels. There is deliberately no mpv-screenshot
/// fallback (a full-size frame grab stutters playback): if the capture comes
/// back empty once playback has settled, the bars stay black and it tries
/// again a little later. Empty captures before then (a stream's first frames
/// not drawn yet) are expected and ignored.
class VideoAmbientBackground extends StatefulWidget {
  const VideoAmbientBackground({
    super.key,
    required this.player,
    required this.captureKey,
    required this.child,
    this.blurStrength = 10,
    this.edgeFade = true,
  });

  final Player player;

  /// Glow softness from 0 (no blur) to 10 (the original look: box-blur radius
  /// 2 on the tiny sample). In-between values blend the two nearest radii.
  final int blurStrength;

  /// Fade the video's edges into the glow (ambient style 'fade').
  final bool edgeFade;

  /// Key of the [RepaintBoundary] wrapping the [Video] widget.
  final GlobalKey captureKey;

  /// The video, drawn between the glow and the faded edges.
  final Widget child;

  @override
  State<VideoAmbientBackground> createState() =>
      _VideoAmbientBackgroundState();
}

class _VideoAmbientBackgroundState extends State<VideoAmbientBackground>
    with SingleTickerProviderStateMixin {
  static const int _sampleWidth = 48;
  static const Duration _captureInterval = Duration(milliseconds: 350);
  static const Duration _idleInterval = Duration(milliseconds: 1000);

  /// Captures only count as failures once playback has been steady (playing,
  /// not buffering) this long: before the first frames are drawn, an empty
  /// capture is expected.
  static const Duration _settleTime = Duration(milliseconds: 1500);

  /// After repeated empty captures, wait this long before trying again
  /// (never give up for good: a stalled stream can look like a failure).
  static const Duration _retryBackoff = Duration(seconds: 10);

  /// Mean per-channel difference below which a new sample is ignored.
  static const double _changeThreshold = 2.0;

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  int _failures = 0;
  DateTime? _steadySince;
  DateTime? _backoffUntil;
  StreamSubscription<int?>? _widthSub;

  ui.Image? _previous;
  ui.Image? _current;
  Color _baseFrom = const Color(0xFF000000);
  Color _baseTo = const Color(0xFF000000);
  Color _accentFrom = const Color(0xFF000000);
  Color _accentTo = const Color(0xFF000000);
  Uint8List? _lastSample;

  /// The last sample used, so a blur change can redo the glow right away
  /// (also while paused, when nothing new is captured).
  _Sample? _lastApplied;

  @override
  void didUpdateWidget(covariant VideoAmbientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sample = _lastApplied;
    if (oldWidget.blurStrength != widget.blurStrength && sample != null) {
      unawaited(_apply(sample, force: true));
    }
  }

  @override
  void initState() {
    super.initState();
    // A new video (next episode, source switch) starts capture afresh.
    _widthSub = widget.player.stream.width.listen((_) => _resetCapture());
    // First sample soon after the first frame, even when starting paused.
    _schedule(const Duration(milliseconds: 600));
  }

  void _resetCapture() {
    _failures = 0;
    _steadySince = null;
    _backoffUntil = null;
    _lastSample = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _widthSub?.cancel();
    _timer?.cancel();
    _fade.dispose();
    _previous?.dispose();
    _current?.dispose();
    super.dispose();
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (_disposed) return;
    _timer = Timer(delay, _tick);
  }

  Future<void> _tick() async {
    if (_disposed) return;
    final state = widget.player.state;
    final playing = state.playing;
    final now = DateTime.now();
    if (playing && !state.buffering) {
      _steadySince ??= now;
    } else {
      _steadySince = null;
    }
    final visible = SchedulerBinding.instance.lifecycleState ==
        AppLifecycleState.resumed;
    final backingOff = _backoffUntil != null && now.isBefore(_backoffUntil!);
    // While paused, keep the last glow and only sample if there is none yet.
    if (visible && !backingOff && (playing || _current == null)) {
      await _capture();
    }
    if (_disposed) return;
    _schedule(playing ? _captureInterval : _idleInterval);
  }

  /// Whether there is anything to capture and show: the video size is known
  /// (it isn't while loading) and the fitted video leaves bars on screen.
  bool get _hasBars {
    final vw = widget.player.state.width ?? 0;
    final vh = widget.player.state.height ?? 0;
    final ro = widget.captureKey.currentContext?.findRenderObject();
    if (vw <= 0 || vh <= 0 || ro is! RenderBox || !ro.hasSize) return false;
    final box = ro.size;
    final video = _containRect(box, vw / vh);
    return box.width - video.width > 8 || box.height - video.height > 8;
  }

  Future<void> _capture() async {
    // Not a failure: nothing to sample yet, or no bars to fill.
    if (_busy || !_hasBars) return;
    _busy = true;
    try {
      final sample = await _sampleFromLayer();
      if (_disposed) return;
      if (sample == null) {
        _onCaptureFailed();
        return;
      }
      _failures = 0;
      await _apply(sample);
    } catch (e) {
      if (kDebugMode) debugPrint('VideoAmbientBackground: capture failed: $e');
      _onCaptureFailed();
    } finally {
      _busy = false;
    }
  }

  void _onCaptureFailed() {
    // Before playback has settled, an empty capture is expected.
    final steady = _steadySince != null &&
        DateTime.now().difference(_steadySince!) >= _settleTime;
    if (!steady) return;
    _failures++;
    if (_failures < 3) return;
    // Keep the last glow (or black bars) and try again a little later.
    _failures = 0;
    _backoffUntil = DateTime.now().add(_retryBackoff);
    if (kDebugMode) {
      debugPrint('VideoAmbientBackground: captures empty, retrying later');
    }
  }

  /// Renders the video's layer at a tiny size (GPU side) and reads back the
  /// video rectangle. Returns null if the video texture isn't captured
  /// (everything comes back transparent).
  Future<_Sample?> _sampleFromLayer() async {
    final player = widget.player;
    final vw = player.state.width ?? 0;
    final vh = player.state.height ?? 0;
    if (vw <= 0 || vh <= 0) return null;

    await SchedulerBinding.instance.endOfFrame;
    final ro = widget.captureKey.currentContext?.findRenderObject();
    if (_disposed || ro is! RenderRepaintBoundary || !ro.hasSize) return null;
    if (kDebugMode && ro.debugNeedsPaint) return null;

    final box = ro.size;
    final video = _containRect(box, vw / vh);
    if (video.width < 1 || video.height < 1) return null;

    final ratio = _sampleWidth / video.width;
    final image = await ro.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final iw = image.width;
    final ih = image.height;
    image.dispose();
    if (data == null) return null;

    final left = (video.left * ratio).round().clamp(0, iw - 1);
    final top = (video.top * ratio).round().clamp(0, ih - 1);
    final w = (video.width * ratio).round().clamp(1, iw - left);
    final h = (video.height * ratio).round().clamp(1, ih - top);

    final src = data.buffer.asUint8List();
    final out = Uint8List(w * h * 4);
    var opaque = 0;
    for (var y = 0; y < h; y++) {
      final rowSrc = ((top + y) * iw + left) * 4;
      final rowDst = y * w * 4;
      for (var x = 0; x < w * 4; x += 4) {
        out[rowDst + x] = src[rowSrc + x];
        out[rowDst + x + 1] = src[rowSrc + x + 1];
        out[rowDst + x + 2] = src[rowSrc + x + 2];
        out[rowDst + x + 3] = 255;
        if (src[rowSrc + x + 3] > 8) opaque++;
      }
    }
    // The Video widget's fill is transparent, so an uncaptured texture comes
    // back fully transparent (a dark scene comes back opaque black).
    if (opaque < (w * h) ~/ 4) return null;
    return _Sample(out, w, h);
  }

  Future<void> _apply(_Sample sample, {bool force = false}) async {
    final last = _lastSample;
    if (!force && last != null && last.length == sample.rgba.length) {
      var diff = 0;
      for (var i = 0; i < last.length; i++) {
        diff += (last[i] - sample.rgba[i]).abs();
      }
      if (diff / last.length < _changeThreshold) return;
    }
    _lastSample = sample.rgba;
    _lastApplied = sample;

    final blurred = _blurByStrength(sample.rgba, sample.width, sample.height, widget.blurStrength);
    final colors = _extractColors(blurred);
    final image = await _decode(blurred, sample.width, sample.height);
    if (_disposed) {
      image.dispose();
      return;
    }

    final t = _fade.value;
    setState(() {
      _baseFrom = Color.lerp(_baseFrom, _baseTo, t)!;
      _accentFrom = Color.lerp(_accentFrom, _accentTo, t)!;
      _baseTo = colors.base;
      _accentTo = colors.accent;
      _previous?.dispose();
      _previous = _current;
      _current = image;
    });
    _fade.forward(from: 0);
  }

  /// One glow layer: the full glow behind the video, or the faded strips
  /// over its edges ([edges]).
  Widget _glowLayer({required bool edges}) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _fade,
          builder: (context, _) {
            final player = widget.player;
            final vw = player.state.width ?? 0;
            final vh = player.state.height ?? 0;
            return CustomPaint(
              size: Size.infinite,
              painter: _AmbientPainter(
                previous: _previous,
                current: _current,
                t: Curves.easeInOut.transform(_fade.value),
                base: Color.lerp(_baseFrom, _baseTo, _fade.value)!,
                accent: Color.lerp(_accentFrom, _accentTo, _fade.value)!,
                videoAspect: vw > 0 && vh > 0 ? vw / vh : null,
                edges: edges,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _glowLayer(edges: false),
        widget.child,
        if (widget.edgeFade) _glowLayer(edges: true),
      ],
    );
  }
}


class _Sample {
  const _Sample(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width;
  final int height;
}

/// The video's on-screen rect when fitted with [BoxFit.contain].
Rect _containRect(Size box, double aspect) {
  var w = box.width;
  var h = w / aspect;
  if (h > box.height) {
    h = box.height;
    w = h * aspect;
  }
  return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
}

/// The largest box-blur radius, reached at strength 10 (the original look).
const int _maxBlurRadius = 2;

/// Blurs for a strength from 0 to 10, mapped to a radius from 0 to
/// [_maxBlurRadius]. Radii are whole numbers, so a strength between two of
/// them blends those two blurs, which keeps every slider step distinct.
Uint8List _blurByStrength(Uint8List src, int w, int h, int strength) {
  final radius = strength.clamp(0, 10) / 10 * _maxBlurRadius;
  final lo = radius.floor();
  final hi = radius.ceil();
  Uint8List blurAt(int r) => r == 0 ? src : _boxBlur(src, w, h, r);
  final a = blurAt(lo);
  if (hi == lo) return a;
  final b = blurAt(hi);
  final f = radius - lo;
  final out = Uint8List(src.length);
  for (var i = 0; i < out.length; i++) {
    out[i] = (a[i] + (b[i] - a[i]) * f).round();
  }
  return out;
}

/// Separable box blur ([radius], two passes) on an RGBA buffer, so the
/// upscaled sample reads as a soft glow rather than blocks. The sample is
/// tiny, so this costs next to nothing.
Uint8List _boxBlur(Uint8List src, int w, int h, int radius) {
  var a = Uint8List.fromList(src);
  var b = Uint8List(src.length);
  for (var pass = 0; pass < 2; pass++) {
    for (var horizontal = 0; horizontal < 2; horizontal++) {
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          var r = 0, g = 0, bl = 0, n = 0;
          for (var k = -radius; k <= radius; k++) {
            final sx = horizontal == 0 ? (x + k).clamp(0, w - 1) : x;
            final sy = horizontal == 0 ? y : (y + k).clamp(0, h - 1);
            final i = (sy * w + sx) * 4;
            r += a[i];
            g += a[i + 1];
            bl += a[i + 2];
            n++;
          }
          final o = (y * w + x) * 4;
          b[o] = r ~/ n;
          b[o + 1] = g ~/ n;
          b[o + 2] = bl ~/ n;
          b[o + 3] = 255;
        }
      }
      final tmp = a;
      a = b;
      b = tmp;
    }
  }
  return a;
}

/// Base = average colour (gamma-correct); accent = average of the most
/// saturated tenth of the pixels, so a strong colour in part of the frame
/// still tints the glow.
({Color base, Color accent}) _extractColors(Uint8List rgba) {
  double toLinear(int c) => math.pow(c / 255.0, 2.2).toDouble();
  int toSrgb(double c) =>
      (math.pow(c.clamp(0.0, 1.0), 1 / 2.2) * 255).round();

  final count = rgba.length ~/ 4;
  var lr = 0.0, lg = 0.0, lb = 0.0;
  final saturations = List<double>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    lr += toLinear(r);
    lg += toLinear(g);
    lb += toLinear(b);
    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    saturations[i] = maxC == 0 ? 0 : (maxC - minC) / maxC * (maxC / 255.0);
  }
  final base = Color.fromARGB(
    255,
    toSrgb(lr / count),
    toSrgb(lg / count),
    toSrgb(lb / count),
  );

  final sorted = List<double>.of(saturations)..sort();
  final cutoff = sorted[(count * 0.9).floor().clamp(0, count - 1)];
  var ar = 0.0, ag = 0.0, ab = 0.0, n = 0;
  for (var i = 0; i < count; i++) {
    if (saturations[i] < cutoff) continue;
    ar += toLinear(rgba[i * 4]);
    ag += toLinear(rgba[i * 4 + 1]);
    ab += toLinear(rgba[i * 4 + 2]);
    n++;
  }
  final accent = n == 0
      ? base
      : Color.fromARGB(
          255,
          toSrgb(ar / n),
          toSrgb(ag / n),
          toSrgb(ab / n),
        );
  return (base: base, accent: accent);
}

Future<ui.Image> _decode(Uint8List rgba, int w, int h) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888,
      completer.complete);
  return completer.future;
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.previous,
    required this.current,
    required this.t,
    required this.base,
    required this.accent,
    required this.videoAspect,
    required this.edges,
  });

  final ui.Image? previous;
  final ui.Image? current;
  final double t;
  final Color base;
  final Color accent;
  final double? videoAspect;

  /// Paint only the faded strips over the video's edges (drawn above the
  /// video) instead of the full glow (drawn behind it).
  final bool edges;

  static const double _baseAlpha = 0.5;
  static const double _frameAlpha = 0.5;
  static const double _accentAlpha = 0.22;

  /// Width of each faded edge, as a fraction of the video's width (or
  /// height, for bars above and below).
  static const double _edgeFraction = 0.06;

  /// Glow opacity across a strip, from the video's edge inwards. Eased
  /// rather than linear so the strip's inner end doesn't show as a line.
  static const _edgeColors = [
    Color(0xFFFFFFFF),
    Color(0xBFFFFFFF),
    Color(0x66FFFFFF),
    Color(0x1FFFFFFF),
    Color(0x00FFFFFF),
  ];
  static const _edgeStops = [0.0, 0.25, 0.55, 0.8, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    if (edges) {
      _paintEdges(canvas, size);
    } else {
      _paintGlow(canvas, size);
    }
  }

  /// The glow over the video's edges next to the bars: each strip is the
  /// glow drawn into a small offscreen layer, then faded out towards the
  /// middle of the picture.
  void _paintEdges(Canvas canvas, Size size) {
    final aspect = videoAspect;
    if (current == null || aspect == null) return;
    final video = _containRect(size, aspect);
    final strips = <(Rect, Offset, Offset)>[];
    if (size.width - video.width > 8) {
      final w = video.width * _edgeFraction;
      strips
        ..add((Rect.fromLTWH(video.left, video.top, w, video.height),
            Offset(video.left, 0), Offset(video.left + w, 0)))
        ..add((Rect.fromLTWH(video.right - w, video.top, w, video.height),
            Offset(video.right, 0), Offset(video.right - w, 0)));
    }
    if (size.height - video.height > 8) {
      final h = video.height * _edgeFraction;
      strips
        ..add((Rect.fromLTWH(video.left, video.top, video.width, h),
            Offset(0, video.top), Offset(0, video.top + h)))
        ..add((Rect.fromLTWH(video.left, video.bottom - h, video.width, h),
            Offset(0, video.bottom), Offset(0, video.bottom - h)));
    }
    for (final (rect, from, to) in strips) {
      canvas.saveLayer(rect, Paint());
      canvas.clipRect(rect);
      _paintGlow(canvas, size);
      canvas.drawRect(
        rect,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(from, to, _edgeColors, _edgeStops),
      );
      canvas.restore();
    }
  }

  void _paintGlow(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    canvas.drawRect(full, Paint()..color = const Color(0xFF000000));
    if (current == null) return;

    canvas.drawRect(full, Paint()..color = base.withValues(alpha: _baseAlpha));

    // Crossfade previous -> current at a constant overall frame opacity F:
    // drawing previous at alpha a, then current at alpha b over it gives
    // current*b + previous*a*(1-b), so pick b and a for F*t and F*(1-t).
    const f = _frameAlpha;
    final hasPrevious = previous != null && t < 1;
    final b = hasPrevious ? f * t / (1 - f + f * t) : f * t;
    if (hasPrevious) {
      final a = f * (1 - t) / (1 - b);
      _drawCover(canvas, previous!, size, _imagePaint(a));
    }
    _drawCover(canvas, current!, size, _imagePaint(b));
    canvas.drawRect(
      full,
      Paint()..color = accent.withValues(alpha: _accentAlpha),
    );

    // Brightest next to the video, fading to dark toward the screen edges,
    // so the glow reads as light spilling out of the picture.
    final aspect = videoAspect;
    final video = aspect == null ? full : _containRect(size, aspect);
    canvas.drawRect(
      full,
      Paint()
        ..shader = ui.Gradient.radial(
          video.center,
          size.longestSide * 0.75,
          const [Color(0x1A000000), Color(0x40000000), Color(0xB3000000)],
          const [0.0, 0.55, 1.0],
        ),
    );
  }

  static Paint _imagePaint(double opacity) => Paint()
    ..filterQuality = FilterQuality.medium
    ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));

  /// Draws [image] covering [size] (cropped to keep its aspect ratio).
  void _drawCover(Canvas canvas, ui.Image image, Size size, Paint paint) {
    final src = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, src, size);
    final srcRect = Alignment.center.inscribe(fitted.source, Offset.zero & src);
    canvas.drawImageRect(image, srcRect, Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter old) =>
      old.previous != previous ||
      old.current != current ||
      old.t != t ||
      old.base != base ||
      old.accent != accent ||
      old.videoAspect != videoAspect ||
      old.edges != edges;
}
