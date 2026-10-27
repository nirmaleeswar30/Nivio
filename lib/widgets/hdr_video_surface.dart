import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/src/video_controller/android_video_controller/android_video_controller.dart';
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

  /// The active VideoController, used to retrieve the media_kit texture WID
  /// and surface dimensions when restoring back to SDR / tone-mapped playback.
  final VideoController? videoController;

  /// Called if mpv can't start its renderer here; the caller should go
  /// back to the normal video widget.
  final VoidCallback? onFailed;

  const HdrVideoSurface({
    super.key,
    required this.player,
    this.videoController,
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
  Timer? _hijackGuardTimer;
  int? _videoWidth;
  int? _videoHeight;
  StreamSubscription? _videoParamsSub;

  @override
  void initState() {
    super.initState();
    final vp = widget.player.state.videoParams;
    _updateVideoDimensions(vp.dw ?? vp.w, vp.dh ?? vp.h);
    _videoParamsSub = widget.player.stream.videoParams.listen((vp) {
      _updateVideoDimensions(vp.dw ?? vp.w, vp.dh ?? vp.h);
    });
  }

  void _updateVideoDimensions(int? w, int? h) {
    if (w != null && h != null && w > 0 && h > 0 && (w != _videoWidth || h != _videoHeight)) {
      if (mounted) {
        setState(() {
          _videoWidth = w;
          _videoHeight = h;
        });
      }
    }
  }

  Future<({int? wid, int? w, int? h})> _getTextureInfo() async {
    final vc = widget.videoController;
    if (vc == null) return (wid: null, w: null, h: null);
    try {
      final p = vc.notifier.value ??
          await vc.platform.future.timeout(const Duration(milliseconds: 500));
      if (p is AndroidVideoController) {
        var wid = p.wid.value;
        for (int i = 0; i < 10 && (wid == null || wid == 0); i++) {
          await Future.delayed(const Duration(milliseconds: 50));
          wid = p.wid.value;
        }
        final r = p.rect.value;
        final w = (r != null && r.width > 0) ? r.width.toInt() : null;
        final h = (r != null && r.height > 0) ? r.height.toInt() : null;
        return (wid: (wid != null && wid > 0) ? wid : null, w: w, h: h);
      }
    } catch (_) {}
    return (wid: null, w: null, h: null);
  }

  void _startHijackGuard(String expectedVo) {
    _hijackGuardTimer?.cancel();
    _hijackGuardTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      final mpv = _mpv;
      if (!mounted || !_attached || _wid == 0 || mpv == null) {
        _hijackGuardTimer?.cancel();
        return;
      }
      try {
        final currentWid = await mpv.getProperty('wid');
        final currentVo = await mpv.getProperty('vo');
        if (currentWid.isNotEmpty && currentWid != '$_wid') {
          appDebugLog('🛡️ [HDR_SURFACE] Hijack detected: wid was $currentWid, re-asserting $_wid');
          await mpv.setProperty('vo', 'null');
          await mpv.setProperty('wid', '$_wid');
          await mpv.setProperty('vo', expectedVo);
        } else if (currentVo.isNotEmpty && currentVo != 'null' && currentVo != expectedVo) {
          appDebugLog('🛡️ [HDR_SURFACE] Hijack detected: vo was $currentVo, re-asserting $expectedVo');
          await mpv.setProperty('vo', expectedVo);
        }
      } catch (_) {}
    });
  }

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
      _hijackGuardTimer?.cancel();
      _hijackGuardTimer = null;
      if (_attached && wid == _wid) {
        await mpv.setProperty('android-surface-size', '${width}x$height');
        return;
      }
      // Check whether video was already playing before this surface switch
      final currentDwidth = await mpv.getProperty('dwidth');
      final currentDheight = await mpv.getProperty('dheight');
      _updateVideoDimensions(int.tryParse(currentDwidth), int.tryParse(currentDheight));
      final currentPos = double.tryParse(await mpv.getProperty('time-pos')) ?? 0;
      final wasPlayingMidStream = (currentDwidth.isNotEmpty && currentDwidth != '0') || currentPos > 0;

      if (_saved == null) {
        final map = {for (final k in _savedKeys) k: await mpv.getProperty(k)};
        final info = await _getTextureInfo();
        if ((map['wid'] == null || map['wid']!.isEmpty || map['wid'] == '0') && info.wid != null) {
          map['wid'] = '${info.wid}';
        }
        if ((map['android-surface-size'] == null || map['android-surface-size']!.isEmpty) && info.w != null && info.h != null) {
          map['android-surface-size'] = '${info.w}x${info.h}';
        }
        _saved = map;
      }
      // vo must be off while wid changes (mpv requirement on Android).
      await mpv.setProperty('vo', 'null');
      await mpv.setProperty('android-surface-size', '${width}x$height');
      await mpv.setProperty('wid', '$wid');
      await mpv.setProperty('sub-visibility', 'no');
      await mpv.setProperty('secondary-sub-visibility', 'no');

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

      // If switching mid-stream, reload video track so mpv cleanly tears down
      // the old MediaCodec instance and initializes the new one (zero-copy vs copy mode)
      if (wasPlayingMidStream) {
        try {
          final vid = await mpv.getProperty('vid');
          await mpv.setProperty('vid', 'no');
          await mpv.setProperty('vid', vid.isNotEmpty && vid != 'no' ? vid : 'auto');
          await mpv.command(['seek', '0', 'relative+keyframes']);
        } catch (_) {}
      }

      // Wait for mpv to actually configure the VO and decode video frames.
      // Do not fail while the stream is buffering network packets or demuxing.
      int totalPollTicks = 0;
      int activeDecodingTicks = 0;
      final expectedVo = isEmbed ? 'mediacodec_embed' : 'gpu-next';

      while (mounted && _attached && wid == _wid && totalPollTicks < 150) {
        await Future.delayed(const Duration(milliseconds: 200));
        totalPollTicks++;
        if (!mounted || !_attached || wid != _wid) return;

        final currentVo = await mpv.getProperty('current-vo');
        if (currentVo == expectedVo) {
          appDebugLog('🌈 HDR surface: confirmed active VO=$currentVo (in ${totalPollTicks * 200}ms)');
          _startHijackGuard(expectedVo);
          return; // Success!
        }

        final isBuffering = (await mpv.getProperty('paused-for-cache')) == 'yes' ||
                            (await mpv.getProperty('core-idle')) == 'yes';
        final primaries = await mpv.getProperty('video-params/primaries');
        final timePos = double.tryParse(await mpv.getProperty('time-pos')) ?? 0;

        // Only count as active decoding if core is actively playing (not idle/buffering),
        // colorspace/primaries are populated, and playback position has begun advancing.
        if (!isBuffering && primaries.isNotEmpty && timePos > 0.5) {
          activeDecodingTicks++;
          if (activeDecodingTicks > 15) {
            appDebugLog('🌈 HDR surface: video active for >3s but VO=$currentVo (expected $expectedVo) — falling back');
            widget.onFailed?.call();
            return;
          }
        }
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
      _hijackGuardTimer?.cancel();
      _hijackGuardTimer = null;
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
    _hijackGuardTimer?.cancel();
    final mpv = _mpv;
    if (mpv == null || !_attached) return;
    await mpv.setProperty('vo', 'null');
    _attached = false;
    _wid = 0;
  }

  /// Back to media_kit's texture surface and its renderer settings.
  Future<void> _restore() async {
    _hijackGuardTimer?.cancel();
    _hijackGuardTimer = null;
    final mpv = _mpv;
    if (mpv == null) return;

    appDebugLog('🌈 HDR surface: restoring to media_kit texture surface...');
    final saved = _saved;

    // 1. Turn off vo while modifying wid / surface
    await mpv.setProperty('vo', 'null');

    // 2. Query texture info from videoController (or fallback to saved)
    final info = await _getTextureInfo();
    final savedWid = saved?['wid'];
    final targetWid = info.wid != null
        ? '${info.wid}'
        : ((savedWid != null && savedWid.isNotEmpty && savedWid != '0' && savedWid != '$_wid') ? savedWid : null);

    final targetW = info.w ?? _videoWidth ?? 1920;
    final targetH = info.h ?? _videoHeight ?? 1080;
    await mpv.setProperty('android-surface-size', '${targetW}x$targetH');

    // 3. Set wid to media_kit's Flutter texture
    if (targetWid != null && targetWid.isNotEmpty) {
      await mpv.setProperty('wid', targetWid);
      appDebugLog('🌈 HDR surface: restored wid=$targetWid');
    } else {
      appDebugLog('⚠️ [HDR_SURFACE] Could not find texture wid to restore!');
    }

    // 4. Context & API for media_kit Android texture (EGL / OpenGL ES)
    await mpv.setProperty('gpu-api', 'auto');
    final savedGpuContext = saved?['gpu-context'];
    final gpuContext = (savedGpuContext != null && savedGpuContext.isNotEmpty && savedGpuContext != 'androidvk')
        ? savedGpuContext
        : 'android';
    await mpv.setProperty('gpu-context', gpuContext);

    // 5. Disable direct HDR color signaling to the SDR texture surface
    await mpv.setProperty('target-colorspace-hint', 'no');
    await mpv.setProperty('hdr-compute-peak', 'no');

    // 6. Restore decoder setting: use user's saved preference or try HW+ with fallback
    final savedHwdec = saved?['hwdec'];
    final targetHwdec = (savedHwdec != null && savedHwdec.isNotEmpty)
        ? savedHwdec
        : 'mediacodec,mediacodec-copy,no';
    await mpv.setProperty('hwdec', targetHwdec);

    // 7. Flutter does the scaling on the texture path
    await mpv.setProperty('keepaspect', 'yes');
    await mpv.setProperty('panscan', '0.0');
    await mpv.setProperty('sub-visibility', 'no');
    await mpv.setProperty('secondary-sub-visibility', 'no');

    // 8. Re-enable VO with gpu-next
    final savedVo = saved?['vo'];
    final targetVo = (savedVo != null && savedVo.isNotEmpty && savedVo != 'null' && savedVo != 'mediacodec_embed')
        ? savedVo
        : 'gpu-next';
    await mpv.setProperty('vo', targetVo);

    // 9. Recycle video track so MediaCodec cleanly unbinds from the destroyed SurfaceView
    // and binds fresh to the texture in copy mode
    try {
      final vid = await mpv.getProperty('vid');
      await mpv.setProperty('vid', 'no');
      await mpv.setProperty('vid', vid.isNotEmpty && vid != 'no' ? vid : 'auto');
      await mpv.command(['seek', '0', 'relative+keyframes']);
    } catch (_) {}

    _attached = false;
    _wid = 0;
    appDebugLog('🌈 HDR surface: successfully restored to texture surface (vo=$targetVo, wid=$targetWid)');
  }

  @override
  void dispose() {
    _videoParamsSub?.cancel();
    _hijackGuardTimer?.cancel();
    _channel?.setMethodCallHandler(null);
    _enqueue(_restore);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) return const SizedBox.shrink();

    final platformView = PlatformViewLink(
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;
        if (screenW <= 0 || screenH <= 0) {
          return ColoredBox(color: Colors.black, child: platformView);
        }

        int? vwInt = _videoWidth;
        int? vhInt = _videoHeight;
        if (vwInt == null || vhInt == null || vwInt <= 0 || vhInt <= 0) {
          final vp = widget.player.state.videoParams;
          vwInt = vp.dw ?? vp.w;
          vhInt = vp.dh ?? vp.h;
        }
        final vw = (vwInt != null && vwInt > 0) ? vwInt.toDouble() : 1920.0;
        final vh = (vhInt != null && vhInt > 0) ? vhInt.toDouble() : 1080.0;
        final videoAspect = vw / vh;
        final screenAspect = screenW / screenH;

        double targetW;
        double targetH;

        switch (widget.fit) {
          case BoxFit.cover: // "Fit Screen" (Zoom to fill screen, crop top/bottom or sides)
            if (screenAspect > videoAspect) {
              targetW = screenW;
              targetH = screenW / videoAspect;
            } else {
              targetH = screenH;
              targetW = screenH * videoAspect;
            }
            break;

          case BoxFit.fill: // "Fill" (Stretch to exact screen rectangle)
            targetW = screenW;
            targetH = screenH;
            break;

          case BoxFit.none:
            targetW = vw;
            targetH = vh;
            break;

          case BoxFit.contain: // "Best Fit" (Preserve aspect ratio, letterbox with black bars)
          default:
            if (screenAspect > videoAspect) {
              targetH = screenH;
              targetW = screenH * videoAspect;
            } else {
              targetW = screenW;
              targetH = screenW / videoAspect;
            }
            break;
        }

        return ColoredBox(
          color: Colors.black,
          child: ClipRect(
            child: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              alignment: Alignment.center,
              child: SizedBox(
                width: targetW,
                height: targetH,
                child: platformView,
              ),
            ),
          ),
        );
      },
    );
  }
}
