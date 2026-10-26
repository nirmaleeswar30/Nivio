import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nivio/core/debug_log.dart';

/// mpv settings for each HDR output mode, applied on the HDR surface.
/// Values follow mpv's documented options.
class HdrOutputSettings {
  final Map<String, String> properties;
  const HdrOutputSettings(this.properties);

  /// True HDR: gpu-next tags the Vulkan swapchain with the video's colour
  /// space, so Android switches the panel into HDR (mpvRx's "Linear" mode).
  ///
  /// The hint follows the display's colour space ("target"), not the source's
  /// per-frame values, and per-frame peak detection is off: either one makes
  /// the hinted colour space change every frame, and libplacebo rebuilds the
  /// Vulkan swapchain whenever it changes (seen as ~60 rebuilds a second).
  static const passthrough = HdrOutputSettings({
    'target-colorspace-hint': 'yes',
    'target-colorspace-hint-mode': 'target',
    'target-prim': 'auto',
    'target-trc': 'auto',
    'target-peak': 'auto',
    'hdr-compute-peak': 'no',
    'inverse-tone-mapping': 'no',
    // Undo any SDR tone mapping (see HdrToneMapping) set on the texture path.
    'tone-mapping': 'auto',
    'gamut-mapping-mode': 'auto',
    'glsl-shaders': '',
    'glsl-shader-opts': '',
  });

  /// SDR output with HDR → SDR tone mapping (HdrToneMapping's properties);
  /// the swapchain stays untagged, so the screen stays in SDR.
  HdrOutputSettings.toneMapped(Map<String, String> toneMapping)
      : properties = {
          ...toneMapping,
          'target-colorspace-hint': 'no',
          'target-peak': 'auto',
          'inverse-tone-mapping': 'no',
        };
}

/// Video output driver backend for the native SurfaceView.
enum HdrSurfaceBackend {
  /// Standard Vulkan gpu-next swapchain (true HDR10 & HDR Toys shaders).
  vulkan,

  /// Zero-copy direct MediaCodec output to SurfaceView (hardware pipeline).
  mediacodecEmbed,
}

/// Android-only video surface for HDR output, also used for hdr-toys tone
/// mapping (its shaders need mpv's Vulkan renderer).
///
/// Shows an Android SurfaceView (com.nirmal.nivio.HdrSurfaceView) and points
/// the player's mpv at it with the Vulkan gpu-next renderer or mediacodec_embed,
/// instead of media_kit's Flutter texture (which Flutter composites as SDR).
/// When it goes away, mpv is switched back to media_kit's texture surface.
class HdrVideoSurface extends StatefulWidget {
  final Player player;
  final HdrOutputSettings settings;
  final HdrSurfaceBackend backend;

  /// How the video fills the view (mpv scales it here, not Flutter).
  final BoxFit fit;

  /// Called if mpv can't start its renderer here; the caller should go
  /// back to the normal video widget.
  final VoidCallback? onFailed;

  const HdrVideoSurface({
    super.key,
    required this.player,
    this.settings = HdrOutputSettings.passthrough,
    this.backend = HdrSurfaceBackend.vulkan,
    this.fit = BoxFit.contain,
    this.onFailed,
  });

  @override
  State<HdrVideoSurface> createState() => _HdrVideoSurfaceState();
}

class _HdrVideoSurfaceState extends State<HdrVideoSurface> {
  MethodChannel? _channel;
  int _wid = 0;
  int _width = 0;
  int _height = 0;
  bool _attached = false;

  /// media_kit's own output settings, restored when leaving the HDR surface.
  Map<String, String>? _saved;

  // All mpv property changes run one after another.
  Future<void> _queue = Future.value();
  void _enqueue(Future<void> Function() job) {
    _queue = _queue.then((_) => job()).catchError((Object e) {
      appDebugLog('🌈 HDR surface: $e');
    });
  }

  NativePlayer? get _mpv {
    final p = widget.player.platform;
    return p is NativePlayer ? p : null;
  }

  static const _savedKeys = ['wid', 'android-surface-size', 'vo', 'hwdec', 'gpu-api', 'gpu-context', 'target-colorspace-hint', 'hdr-compute-peak'];

  void _onViewCreated(int id) {
    final channel = MethodChannel('com.nivio/hdr_surface_$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      switch (call.method) {
        case 'created':
        case 'changed':
          _onSurface(args['wid'] as int? ?? 0, args['width'] as int? ?? 0, args['height'] as int? ?? 0);
        case 'destroyed':
          _enqueue(_parkRenderer);
      }
      return null;
    });
    // The surface may already exist.
    channel.invokeMapMethod<String, dynamic>('state').then((state) {
      if (state != null) _onSurface(state['wid'] as int? ?? 0, state['width'] as int? ?? 0, state['height'] as int? ?? 0);
    });
  }

  void _onSurface(int wid, int width, int height) {
    if (wid == 0 || width <= 0 || height <= 0) return;
    _width = width;
    _height = height;
    _enqueue(() async {
      final mpv = _mpv;
      if (mpv == null || !mounted) return;
      if (_attached && wid == _wid) {
        await mpv.setProperty('android-surface-size', '${width}x$height');
        return;
      }
      _saved ??= {for (final k in _savedKeys) k: await mpv.getProperty(k)};
      // vo must be off while wid changes (mpv requirement on Android).
      await mpv.setProperty('vo', 'null');
      await mpv.setProperty('android-surface-size', '${width}x$height');
      await mpv.setProperty('wid', '$wid');

      final isEmbed = widget.backend == HdrSurfaceBackend.mediacodecEmbed;
      if (isEmbed) {
        await mpv.setProperty('gpu-api', 'auto');
        await mpv.setProperty('gpu-context', 'auto');
        // Zero-copy direct hardware decode to SurfaceView
        await mpv.setProperty('hwdec', 'mediacodec');
        for (final e in _fitProperties(widget.fit).entries) {
          await mpv.setProperty(e.key, e.value);
        }
        await mpv.setProperty('vo', 'mediacodec_embed');
        _wid = wid;
        _attached = true;
        appDebugLog('🌈 HDR surface (mediacodec_embed): mpv on SurfaceView ${width}x$height (wid=$wid)');
      } else {
        await mpv.setProperty('gpu-api', 'vulkan');
        await mpv.setProperty('gpu-context', 'androidvk');
        // The Vulkan path can't take MediaCodec's GPU frames directly.
        await mpv.setProperty('hwdec', 'mediacodec-copy');
        for (final e in widget.settings.properties.entries) {
          await mpv.setProperty(e.key, e.value);
        }
        for (final e in _fitProperties(widget.fit).entries) {
          await mpv.setProperty(e.key, e.value);
        }
        await mpv.setProperty('vo', 'gpu-next');
        _wid = wid;
        _attached = true;
        appDebugLog('🌈 HDR surface (gpu-next): mpv on SurfaceView ${width}x$height (wid=$wid)');
      }

      // Check that the selected renderer actually came up.
      await Future.delayed(const Duration(milliseconds: 800));
      final vo = await mpv.getProperty('current-vo');
      appDebugLog('🌈 HDR surface: current-vo=$vo');
      final expectedVo = isEmbed ? 'mediacodec_embed' : 'gpu-next';
      if (vo != expectedVo && mounted) {
        widget.onFailed?.call();
      }
    });
  }

  /// Display fit as mpv options: on the SurfaceView mpv scales the video
  /// itself (on media_kit's texture, Flutter does it with BoxFit).
  static Map<String, String> _fitProperties(BoxFit fit) => switch (fit) {
        BoxFit.cover => const {'keepaspect': 'yes', 'panscan': '1.0'},
        BoxFit.fill => const {'keepaspect': 'no', 'panscan': '0.0'},
        _ => const {'keepaspect': 'yes', 'panscan': '0.0'},
      };

  @override
  void didUpdateWidget(covariant HdrVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend) {
      if (_wid != 0 && _width > 0 && _height > 0) {
        _attached = false;
        _onSurface(_wid, _width, _height);
      }
      return;
    }
    if (!mapEquals(oldWidget.settings.properties, widget.settings.properties)) {
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
      _enqueue(() async {
        final mpv = _mpv;
        if (mpv == null || !_attached) return;
        for (final e in _fitProperties(widget.fit).entries) {
          await mpv.setProperty(e.key, e.value);
        }
      });
    }
  }

  /// Surface gone (e.g. app in background): stop rendering into it.
  Future<void> _parkRenderer() async {
    final mpv = _mpv;
    if (mpv == null || !_attached) return;
    await mpv.setProperty('vo', 'null');
    _attached = false;
    _wid = 0;
  }

  /// Back to media_kit's texture surface and its renderer settings.
  Future<void> _restore() async {
    final mpv = _mpv;
    final saved = _saved;
    if (mpv == null || saved == null) return;
    await mpv.setProperty('vo', 'null');
    for (final key in const ['gpu-api', 'gpu-context', 'hwdec', 'target-colorspace-hint', 'hdr-compute-peak', 'android-surface-size', 'wid']) {
      final value = saved[key];
      if (value != null && value.isNotEmpty) await mpv.setProperty(key, value);
    }
    // Flutter does the scaling on the texture path.
    await mpv.setProperty('keepaspect', 'yes');
    await mpv.setProperty('panscan', '0.0');
    final vo = saved['vo'];
    await mpv.setProperty('vo', (vo == null || vo.isEmpty || vo == 'null') ? 'gpu' : vo);
    appDebugLog('🌈 HDR surface: back to the texture surface');
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _enqueue(_restore);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) return const SizedBox.shrink();
    return ColoredBox(
      color: Colors.black,
      child: PlatformViewLink(
        viewType: 'nivio/hdr_surface',
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          // Touches go to the player controls drawn above it.
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        ),
        onCreatePlatformView: (params) {
          // A SurfaceView needs Hybrid Composition (a real Android view in the
          // hierarchy); texture-based platform views would make it SDR again.
          final controller = PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: 'nivio/hdr_surface',
            layoutDirection: TextDirection.ltr,
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..addOnPlatformViewCreatedListener(_onViewCreated);
          controller.create();
          return controller;
        },
      ),
    );
  }
}
