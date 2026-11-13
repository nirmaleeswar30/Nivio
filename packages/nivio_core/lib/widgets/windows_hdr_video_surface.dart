import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/widgets/hdr_video_surface.dart' show HdrOutputSettings;

/// Windows-only video output for true HDR.
///
/// media_kit's video is a Flutter texture, and Flutter composites as 8-bit
/// SDR. Here mpv instead renders with gpu-next on its own Direct3D 11
/// swapchain (tagged HDR10) into a native window behind the app window
/// (packages/nivio_desktop/windows/runner/hdr_video_host.cpp), and the app
/// window turns see-through. This widget paints nothing: it reports where the
/// video goes and switches mpv between that window and media_kit's texture.
///
/// Needs Windows HDR switched on for the screen (see AppPlatform.hdrDisplay).
class WindowsHdrVideoSurface extends StatefulWidget {
  final Player player;
  final HdrOutputSettings settings;

  /// How the video fills the view (mpv scales it here, not Flutter).
  final BoxFit fit;

  /// GPU driving the screen, for mpv's d3d11-adapter.
  final String? adapter;

  /// Called if mpv can't start its renderer here; the caller should go back
  /// to the normal video widget.
  final VoidCallback? onFailed;

  const WindowsHdrVideoSurface({
    super.key,
    required this.player,
    this.settings = HdrOutputSettings.passthrough,
    this.fit = BoxFit.contain,
    this.adapter,
    this.onFailed,
  });

  @override
  State<WindowsHdrVideoSurface> createState() => _WindowsHdrVideoSurfaceState();
}

class _WindowsHdrVideoSurfaceState extends State<WindowsHdrVideoSurface> {
  static const _channel = MethodChannel('com.nivio/hdr_window');

  /// mpv properties changed here, restored when leaving.
  static const _savedKeys = [
    'wid',
    'gpu-api',
    'gpu-context',
    'd3d11-adapter',
    'target-colorspace-hint',
    'target-colorspace-hint-mode',
    'hdr-compute-peak',
    'input-vo-keyboard',
    'input-cursor',
    'cursor-autohide',
    'keepaspect',
    'panscan',
  ];

  Map<String, String>? _saved;
  String _savedVo = 'libmpv';
  bool _attached = false;
  bool _disposed = false;
  Rect? _rect;
  Timer? _voGuard;

  // All mpv / channel calls run one after another.
  Future<void> _queue = Future.value();
  void _enqueue(Future<void> Function() job) {
    _queue = _queue.then((_) => job()).catchError((Object e) {
      appDebugLog('🌈 Windows HDR surface: $e');
    });
  }

  NativePlayer? get _mpv {
    final p = widget.player.platform;
    return p is NativePlayer ? p : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rect = _measure();
      if (rect != null) _enqueue(() => _attach(rect));
    });
  }

  /// The video rect in physical pixels, relative to the window's client area.
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
    final wid = await _channel.invokeMethod<int>('attach', _rectArgs(rect));
    if (wid == null || wid == 0) throw StateError('no HDR video window');
    _attached = true;
    if (_disposed) return;

    final vo = await mpv.getProperty('vo');
    if (vo.isNotEmpty && vo != 'null' && vo != 'gpu-next') _savedVo = vo;
    _saved ??= {for (final k in _savedKeys) k: await mpv.getProperty(k)};

    // vo must be off while wid changes.
    await mpv.setProperty('vo', 'null');
    await mpv.setProperty('wid', '$wid');
    await mpv.setProperty('gpu-api', 'd3d11');
    await mpv.setProperty('gpu-context', 'd3d11');
    final adapter = widget.adapter;
    if (adapter != null && adapter.isNotEmpty) {
      await mpv.setProperty('d3d11-adapter', adapter);
    }
    // The app window gets all input; mpv's window is behind it anyway.
    await mpv.setProperty('input-vo-keyboard', 'no');
    await mpv.setProperty('input-cursor', 'no');
    await mpv.setProperty('cursor-autohide', 'no');
    for (final e in widget.settings.properties.entries) {
      await mpv.setProperty(e.key, e.value);
    }
    for (final e in _fitProperties(widget.fit).entries) {
      await mpv.setProperty(e.key, e.value);
    }
    await mpv.setProperty('vo', 'gpu-next');
    await _recycleVideoTrack(mpv);
    appDebugLog('🌈 Windows HDR surface: mpv gpu-next on wid=$wid ${rect.width.toInt()}x${rect.height.toInt()} (adapter=$adapter)');

    // Wait for mpv to bring up the renderer (not while buffering).
    for (var i = 0, active = 0; i < 150 && !_disposed; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (_disposed) return;
      final current = await mpv.getProperty('current-vo');
      if (current == 'gpu-next') {
        appDebugLog('🌈 Windows HDR surface: gpu-next active after ${(i + 1) * 200}ms');
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
    appDebugLog('🌈 Windows HDR surface: gpu-next did not start; falling back');
    widget.onFailed?.call();
  }

  /// Logs what mpv actually sends to the screen: PQ / BT.2020 is HDR10
  /// output, anything SDR (e.g. srgb / bt.709) means it fell back to SDR.
  Future<void> _logOutput(NativePlayer mpv) async {
    // The target is known once the first frame has been rendered; after the
    // decoder restart that can take a few seconds on a big stream.
    try {
      var gamma = '';
      for (var i = 0; i < 20 && gamma.isEmpty; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (_disposed) return;
        gamma = await mpv.getProperty('video-target-params/gamma');
      }
      final primaries = await mpv.getProperty('video-target-params/primaries');
      final peak = await mpv.getProperty('video-target-params/max-luma');
      final source = await mpv.getProperty('video-params/gamma');
      appDebugLog('🌈 Windows HDR surface: output $gamma / $primaries (peak ${peak.isEmpty ? '?' : '$peak nits'}), source $source');
    } catch (e) {
      appDebugLog('🌈 Windows HDR surface: could not read output params ($e)');
    }
  }

  /// Something resetting mpv's vo (e.g. media_kit re-creating its video
  /// output) would leave the HDR window empty: put gpu-next back.
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
        if (vo.isNotEmpty && vo != 'gpu-next' && vo != 'null') {
          appDebugLog('🌈 Windows HDR surface: vo was reset to $vo, re-asserting gpu-next');
          await mpv.setProperty('vo', 'gpu-next');
        }
      });
    });
  }

  /// Re-opens the video decoder for the new renderer (its hardware frames
  /// belong to the old one's D3D11 device).
  static Future<void> _recycleVideoTrack(NativePlayer mpv) async {
    try {
      final vid = await mpv.getProperty('vid');
      if (vid.isEmpty || vid == 'no') return;
      await mpv.setProperty('vid', 'no');
      await mpv.setProperty('vid', vid);
      await mpv.command(['seek', '0', 'relative+keyframes']);
    } catch (_) {}
  }

  /// Display fit as mpv options: in the HDR window mpv scales the video
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
    // Never leave the HDR tag on media_kit's SDR texture.
    await mpv.setProperty('target-colorspace-hint', 'no');
    await mpv.setProperty('vo', _savedVo);
    await _recycleVideoTrack(mpv);
    appDebugLog('🌈 Windows HDR surface: back to media_kit (vo=$_savedVo)');
  }

  @override
  void didUpdateWidget(covariant WindowsHdrVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final settingsChanged = oldWidget.settings.properties.length != widget.settings.properties.length ||
        oldWidget.settings.properties.entries.any((e) => widget.settings.properties[e.key] != e.value);
    if (settingsChanged) {
      final settings = widget.settings.properties;
      _enqueue(() async {
        final mpv = _mpv;
        if (mpv == null || !_attached) return;
        for (final e in settings.entries) {
          await mpv.setProperty(e.key, e.value);
        }
      });
    }
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
    _enqueue(_restore);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();
    // Transparent: the video shows through from the window behind.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Re-measure after every layout (window resize, fullscreen, UI scale).
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncRect());
        return const SizedBox.expand();
      },
    );
  }
}
