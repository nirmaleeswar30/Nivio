import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Loads the two glass fragment programs once for the whole app.
///
/// Call [ensureLoaded] before `runApp`. Until it completes, or when the
/// renderer cannot run a shader as an image filter (the Skia backend),
/// glass falls back to colour controls, blur, tint, rim and shadow with no
/// lens — the same step down the Kotlin version takes on Android 12, where
/// RenderEffect exists but RuntimeShader does not.
///
/// The shaders are declared in packages/nivio_core/pubspec.yaml, so the app
/// packages (nivio_mobile, nivio_ios, nivio_desktop) see them under
/// `packages/nivio/`; a build from the repo root sees them unprefixed.
abstract final class GlassShaders {
  static ui.FragmentProgram? _lens;
  static ui.FragmentProgram? _highlight;
  static Future<void>? _loading;

  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<ui.FragmentProgram?> _program(String name) async {
    Object? error;
    for (final path in ['packages/nivio/shaders/$name', 'shaders/$name']) {
      try {
        return await ui.FragmentProgram.fromAsset(path);
      } catch (e) {
        error = e;
      }
    }
    debugPrint('liquid glass: $name unavailable ($error)');
    return null;
  }

  static Future<void> _load() async {
    _lens = await _program('glass_lens.frag');
    _highlight = await _program('glass_highlight.frag');
  }

  /// Whether the refraction lens can run on this renderer.
  static bool get lensSupported =>
      _lens != null && ui.ImageFilter.isShaderFilterSupported;

  static ui.FragmentShader? createLens() =>
      lensSupported ? _lens!.fragmentShader() : null;

  static ui.FragmentShader? createHighlight() => _highlight?.fragmentShader();
}
