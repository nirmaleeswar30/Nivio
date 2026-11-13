import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/core/debug_log.dart';

/// Linux-only video output for true HDR (Wayland).
///
/// media_kit's video is a Flutter texture, and Flutter composites as 8-bit
/// SDR. mpv can't embed its own window on Wayland, so the runner renders it
/// instead (packages/nivio_desktop/linux/runner/hdr_video_host.cc): mpv's
/// render context moves from media_kit's texture to a 10-bit EGL surface,
/// a Wayland subsurface below the app window tagged as HDR10 (PQ, BT.2020),
/// and the app window turns see-through. This widget paints nothing: it
/// reports where the video goes and moves mpv between that surface and
/// media_kit's texture.
///
/// Needs the compositor's HDR mode on for the screen (see
/// AppPlatform.hdrDisplay).
class LinuxHdrVideoSurface extends StatefulWidget {
  final Player player;

  /// media_kit's controller, whose video output is released while this is
  /// shown and created again afterwards.
  final VideoController videoController;

  /// How the video fills the view (mpv scales it here, not Flutter).
  final BoxFit fit;

  /// Peak brightness of the screen in nits, which mpv tone-maps to.
  final double? peak;

  /// Called if the HDR surface can't start or is lost; the caller should go
  /// back to the normal video widget.
  final VoidCallback? onFailed;

  const LinuxHdrVideoSurface({
    super.key,
    required this.player,
    required this.videoController,
    this.fit = BoxFit.contain,
    this.peak,
    this.onFailed,
  });

  @override
  State<LinuxHdrVideoSurface> createState() => _LinuxHdrVideoSurfaceState();
}

class _LinuxHdrVideoSurfaceState extends State<LinuxHdrVideoSurface> {
  static const _channel = MethodChannel('com.nivio/hdr_window');
  static const _mediaKitChannel = MethodChannel('com.alexmercerind/media_kit_video');

  /// Peak used when the compositor doesn't report one.
  static const _defaultPeak = 1000.0;

  /// mpv properties changed here, restored when leaving.
  static const _savedKeys = [
    'target-trc',
    'target-prim',
    'target-peak',
    'tone-mapping',
    'hdr-compute-peak',
    'inverse-tone-mapping',
    'glsl-shaders',
    'keepaspect',
    'panscan',
  ];

  Map<String, String>? _saved;
  String _savedVid = 'auto';
  int? _handle;
  bool _mediaKitReleased = false;
  bool _attached = false;
  bool _disposed = false;
  bool _failed = false;
  Rect? _rect;
  Timer? _voGuard;
  StreamSubscription<void>? _surfaceLost;

  // All mpv / channel calls run one after another.
  Future<void> _queue = Future.value();
  void _enqueue(Future<void> Function() job) {
    _queue = _queue.then((_) => job()).catchError((Object e) {
      appDebugLog('🌈 Linux HDR surface: $e');
    });
  }

  NativePlayer? get _mpv {
    final p = widget.player.platform;
    return p is NativePlayer ? p : null;
  }

  @override
  void initState() {
    super.initState();
    _surfaceLost = AppPlatform.hdrSurfaceLost.listen((_) => _onSurfaceLost());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rect = _measure();
      if (rect != null) _enqueue(() => _attach(rect));
    });
  }

  void _onSurfaceLost() {
    if (_disposed || !_attached) return;
    appDebugLog('🌈 Linux HDR surface: app window was hidden; falling back');
    _fail();
  }

  void _fail() {
    if (_failed || _disposed) return;
    _failed = true;
    widget.onFailed?.call();
  }

  /// The video rect in physical pixels, relative to the Flutter view.
  Rect? _measure() {
    if (!mounted) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    final dpr = View.of(context).devicePixelRatio;
    final topLeft = box.localToGlobal(Offset.zero);
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
    return Rect.fromLTRB(
      (topLeft.dx * dpr).roundToDouble(),
      (topLeft.dy * dpr).roundToDouble(),
      (bottomRight.dx * dpr).roundToDouble(),
      (bottomRight.dy * dpr).roundToDouble(),
    );
  }

  static Map<String, int> _rectArgs(Rect r) => {
        'x': r.left.toInt(),
        'y': r.top.toInt(),
        'width': r.width.toInt(),
        'height': r.height.toInt(),
      };

  void _syncRect() {
    if (_disposed) return;
    final rect = _measure();
    if (rect == null || rect == _rect) return;
    _rect = rect;
    if (_attached) {
      _enqueue(() => _channel.invokeMethod('setRect', _rectArgs(rect)));
    }
  }

  Future<void> _attach(Rect rect) async {
    final mpv = _mpv;
    if (mpv == null || _disposed) return;
    _rect = rect;
    final handle = _handle = await widget.player.handle;
    final vid = await mpv.getProperty('vid');
    if (vid.isNotEmpty && vid != 'no') _savedVid = vid;
    _saved ??= {for (final k in _savedKeys) k: await mpv.getProperty(k)};

    // mpv has a single render context: media_kit's texture output gives its
    // up, and the runner creates one on the HDR surface. vo must be off
    // while it changes hands.
    await mpv.setProperty('vo', 'null');
    await _mediaKitChannel.invokeMethod('VideoOutputManager.Dispose', {'handle': '$handle'});
    _mediaKitReleased = true;
    if (_disposed) return;
    final peak = (widget.peak ?? 0) > 0 ? widget.peak! : _defaultPeak;
    try {
      await _channel.invokeMethod('attach', {
        ..._rectArgs(rect),
        'handle': handle,
        'peak': peak,
      });
    } on PlatformException catch (e) {
      appDebugLog('🌈 Linux HDR surface: could not start (${e.message}); falling back');
      _fail();
      return;
    }
    _attached = true;
    if (_disposed) return;

    // mpv writes HDR10 itself: PQ / BT.2020, tone-mapped to the screen's peak
    // (the libmpv renderer can't tag a surface, the runner did that).
    await mpv.setProperty('target-trc', 'pq');
    await mpv.setProperty('target-prim', 'bt.2020');
    await mpv.setProperty('target-peak', '${peak.round()}');
    await mpv.setProperty('tone-mapping', 'auto');
    await mpv.setProperty('hdr-compute-peak', 'auto');
    await mpv.setProperty('inverse-tone-mapping', 'no');
    await mpv.setProperty('glsl-shaders', '');
    for (final e in _fitProperties(widget.fit).entries) {
      await mpv.setProperty(e.key, e.value);
    }
    await mpv.setProperty('vo', 'libmpv');
    await _recycleVideoTrack(mpv, _savedVid);
    appDebugLog('🌈 Linux HDR surface: mpv on the HDR10 surface ${rect.width.toInt()}x${rect.height.toInt()} (peak $peak nits)');

    // Wait for frames on the surface (not while buffering).
    for (var i = 0, active = 0; i < 150 && !_disposed; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (_disposed) return;
      final status = await _channel.invokeMapMethod<String, dynamic>('status');
      if (((status?['frames'] as int?) ?? 0) > 1 && await mpv.getProperty('current-vo') == 'libmpv') {
        appDebugLog('🌈 Linux HDR surface: rendering after ${(i + 1) * 200}ms');
        _startVoGuard();
        unawaited(_logOutput(mpv));
        return;
      }
      final idle = (await mpv.getProperty('paused-for-cache')) == 'yes' ||
          (await mpv.getProperty('core-idle')) == 'yes';
      final pos = double.tryParse(await mpv.getProperty('time-pos')) ?? 0;
      if (!idle && pos > 0.5 && ++active > 15) break;
    }
    if (_disposed) return;
    appDebugLog('🌈 Linux HDR surface: no frames rendered; falling back');
    _fail();
  }

  /// Logs the decoder in use and the source's colour space (the libmpv
  /// renderer doesn't report video-target-params).
  Future<void> _logOutput(NativePlayer mpv) async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (_disposed) return;
      final source = await mpv.getProperty('video-params/gamma');
      final primaries = await mpv.getProperty('video-params/primaries');
      final hwdec = await mpv.getProperty('hwdec-current');
      appDebugLog('🌈 Linux HDR surface: source $source / $primaries → PQ / BT.2020, hwdec $hwdec');
    } catch (e) {
      appDebugLog('🌈 Linux HDR surface: could not read video params ($e)');
    }
  }

  /// Something resetting mpv's vo would leave the HDR surface empty: put it
  /// back.
  void _startVoGuard() {
    _voGuard?.cancel();
    _voGuard = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || !_attached) {
        _voGuard?.cancel();
        return;
      }
      _enqueue(() async {
        final mpv = _mpv;
        if (mpv == null || _disposed) return;
        final vo = await mpv.getProperty('vo');
        if (vo.isNotEmpty && vo != 'libmpv' && vo != 'null') {
          appDebugLog('🌈 Linux HDR surface: vo was reset to $vo, re-asserting libmpv');
          await mpv.setProperty('vo', 'libmpv');
        }
      });
    });
  }

  /// Re-opens the video decoder for the new renderer, and selects the video
  /// track again if mpv dropped it while it had no video output.
  static Future<void> _recycleVideoTrack(NativePlayer mpv, String vid) async {
    try {
      await mpv.setProperty('vid', 'no');
      await mpv.setProperty('vid', vid);
      await mpv.command(['seek', '0', 'relative+keyframes']);
    } catch (_) {}
  }

  /// Display fit as mpv options: on the HDR surface mpv scales the video
  /// itself (on media_kit's texture, Flutter does it with BoxFit).
  static Map<String, String> _fitProperties(BoxFit fit) => switch (fit) {
        BoxFit.cover => const {'keepaspect': 'yes', 'panscan': '1.0'},
        BoxFit.fill => const {'keepaspect': 'no', 'panscan': '0.0'},
        _ => const {'keepaspect': 'yes', 'panscan': '0.0'},
      };

  /// Back to media_kit's texture output.
  Future<void> _restore() async {
    _voGuard?.cancel();
    final mpv = _mpv;
    if (mpv != null) {
      await mpv.setProperty('vo', 'null');
    }
    if (_attached) {
      _attached = false;
      await _channel.invokeMethod('detach');
    }
    if (mpv == null) return;
    final saved = _saved ?? const <String, String>{};
    for (final e in saved.entries) {
      try {
        await mpv.setProperty(e.key, e.value);
      } catch (_) {}
    }
    if (_mediaKitReleased) {
      _mediaKitReleased = false;
      // Same configuration as PlayerScreen's VideoController. media_kit
      // answers with a new texture ID, which its Video widget picks up.
      final configuration = widget.videoController.platform.isCompleted
          ? (await widget.videoController.platform.future).configuration
          : const VideoControllerConfiguration(enableHardwareAcceleration: false);
      await _mediaKitChannel.invokeMethod('VideoOutputManager.Create', {
        'handle': '$_handle',
        'configuration': {
          'width': configuration.width.toString(),
          'height': configuration.height.toString(),
          'enableHardwareAcceleration': configuration.enableHardwareAcceleration,
        },
      });
    }
    await mpv.setProperty('vo', 'libmpv');
    await _recycleVideoTrack(mpv, _savedVid);
    appDebugLog('🌈 Linux HDR surface: back to media_kit');
  }

  @override
  void didUpdateWidget(covariant LinuxHdrVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fit != widget.fit) {
      final fit = widget.fit;
      _enqueue(() async {
        final mpv = _mpv;
        if (mpv == null || !_attached) return;
        for (final e in _fitProperties(fit).entries) {
          await mpv.setProperty(e.key, e.value);
        }
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _voGuard?.cancel();
    _surfaceLost?.cancel();
    _enqueue(_restore);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isLinux) return const SizedBox.shrink();
    // Transparent: the video shows through from the surface below.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Re-measure after every layout (window resize, fullscreen, UI scale).
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncRect());
        return const SizedBox.expand();
      },
    );
  }
}
