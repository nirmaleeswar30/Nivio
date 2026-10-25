import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:path_provider/path_provider.dart';

/// mpv settings that turn HDR (and wide-gamut BT.2020) video into SDR, for
/// whenever it isn't shown as true HDR.
///
/// * standard — mpv/libplacebo's tone mapping, with per-scene peak detection.
/// * hdrToys  — the hdr-toys shaders (github.com/natural-harmonia-gropius/hdr-toys,
///   MIT; the files Nivio uses are bundled under assets/hdr-toys). The profile
///   follows the video, like hdr-toys.conf: PQ (HDR10), HLG, or BT.2020 SDR.
///   mpv's target is set to the source's colour space so mpv itself doesn't
///   convert, and the shaders do the whole conversion down to BT.1886 (SDR).
///   Needs the gpu-next renderer (Android only in Nivio).
class HdrToneMapping {
  HdrToneMapping._();

  /// Every property set here, so switching modes never leaves one behind.
  static const _defaults = {
    'tone-mapping': 'auto',
    'gamut-mapping-mode': 'auto',
    'hdr-compute-peak': 'auto',
    'target-prim': 'auto',
    'target-trc': 'auto',
    'glsl-shaders': '',
    'glsl-shader-opts': '',
  };

  /// Source needs converting: HDR transfer, or BT.2020 primaries.
  static bool needsMapping(String? gamma, String? primaries) =>
      gamma == 'pq' || gamma == 'hlg' || primaries == 'bt.2020';

  /// Properties for [mode] for a video with the given transfer/primaries.
  /// SDR BT.709 video (or anything not covered) gets mpv's defaults back.
  static Future<Map<String, String>> properties({
    required String mode,
    required String? gamma,
    required String? primaries,
  }) async {
    if (!needsMapping(gamma, primaries)) return _defaults;

    if (mode == 'hdrToys' && Platform.isAndroid) {
      final dir = await _shaderDir();
      if (dir != null) {
        String s(String path) => '$dir/$path';
        final List<String> shaders;
        final Map<String, String> extra;
        if (gamma == 'pq') {
          shaders = [
            s('utils/clip_both.glsl'),
            s('transfer-function/pq_inv.glsl'),
            s('tone-mapping/astra.glsl'),
            s('gamut-mapping/bottosson.glsl'),
            s('transfer-function/bt1886.glsl'),
          ];
          extra = {'target-trc': 'pq', 'glsl-shader-opts': 'auto_exposure_limit_positive=1.02'};
        } else if (gamma == 'hlg') {
          shaders = [
            s('utils/clip_both.glsl'),
            s('transfer-function/hlg_inv.glsl'),
            s('tone-mapping/astra.glsl'),
            s('gamut-mapping/bottosson.glsl'),
            s('transfer-function/bt1886.glsl'),
          ];
          extra = {'target-trc': 'hlg'};
        } else {
          // Wide-gamut SDR (BT.2020 primaries, BT.1886 transfer).
          shaders = [
            s('transfer-function/bt1886_inv.glsl'),
            s('gamut-mapping/bottosson.glsl'),
            s('transfer-function/bt1886.glsl'),
          ];
          extra = {'target-trc': 'bt.1886'};
        }
        return {
          ..._defaults,
          'tone-mapping': 'clip',
          'gamut-mapping-mode': 'clip',
          'hdr-compute-peak': 'no',
          'target-prim': 'bt.2020',
          'glsl-shaders': shaders.join(':'), // mpv path list (':' on Android)
          ...extra,
        };
      }
    }

    // Standard: libplacebo picks the curve; peak detection adapts each scene.
    return {
      ..._defaults,
      'hdr-compute-peak': 'yes',
      'gamut-mapping-mode': 'perceptual',
    };
  }

  static Future<String?>? _shaderDirFuture;

  /// Copies the bundled shaders to app storage once (mpv needs real files).
  static Future<String?> _shaderDir() {
    return _shaderDirFuture ??= () async {
      try {
        final base = await getApplicationSupportDirectory();
        final dir = Directory('${base.path}/hdr-toys');
        const files = [
          'utils/clip_both.glsl',
          'transfer-function/pq_inv.glsl',
          'transfer-function/hlg_inv.glsl',
          'transfer-function/bt1886.glsl',
          'transfer-function/bt1886_inv.glsl',
          'tone-mapping/astra.glsl',
          'gamut-mapping/bottosson.glsl',
        ];
        for (final f in files) {
          final data = await rootBundle.loadString('assets/hdr-toys/$f');
          final out = File('${dir.path}/$f');
          await out.parent.create(recursive: true);
          await out.writeAsString(data);
        }
        return dir.path;
      } catch (e) {
        appDebugLog('🌈 hdr-toys shaders unavailable: $e');
        _shaderDirFuture = null;
        return null;
      }
    }();
  }
}
