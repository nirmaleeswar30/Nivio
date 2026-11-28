/// Patches plugin C++ sources in the pub cache that MSVC rejects, before a
/// Windows build. Run from packages/nivio_desktop (scripts/run_windows.ps1
/// and the release scripts do this).
///
/// media_kit_video 2.0.1 passes string literals where libmpv's render API
/// takes `void*`. That drops `const`, which MSVC rejects, so explicit casts
/// are added.
/// (window_manager used to need a patch too; 0.7.x has no C++ sources.)
///
/// `--dry-run` reports what would change without writing.
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final rootDir = Directory.current;
  final packageConfigFile = File(
    '${rootDir.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}package_config.json',
  );

  if (!packageConfigFile.existsSync()) {
    stdout.writeln(
      'Notice: .dart_tool/package_config.json not found. Run flutter pub get first.',
    );
    return;
  }

  final packageConfig =
      jsonDecode(packageConfigFile.readAsStringSync()) as Map<String, Object?>;
  final packages = packageConfig['packages'] as List<Object?>;

  final mediaKitVideoRoot = _tryPackageRoot(
    packageConfigFile,
    packages,
    'media_kit_video',
  );

  if (mediaKitVideoRoot != null) {
    _patchMediaKitVideo(
      path:
          '${mediaKitVideoRoot.path}${Platform.pathSeparator}windows${Platform.pathSeparator}video_output.cc',
      dryRun: dryRun,
    );
  }
}

Directory? _tryPackageRoot(
  File packageConfigFile,
  List<Object?> packages,
  String packageName,
) {
  final package = packages
      .cast<Map<String, Object?>>()
      .where((package) => package['name'] == packageName)
      .firstOrNull;

  if (package == null) {
    stdout.writeln('Notice: $packageName was not found in package_config.json.');
    return null;
  }

  return _resolvePackageRoot(packageConfigFile, package['rootUri'] as String);
}

Directory _resolvePackageRoot(File packageConfigFile, String rootUriText) {
  final rootUri = Uri.parse(rootUriText);
  final resolvedUri = rootUri.hasScheme
      ? rootUri
      : packageConfigFile.parent.uri.resolveUri(rootUri);

  if (!resolvedUri.isScheme('file')) {
    throw StateError('Unsupported package URI: $rootUriText');
  }

  return Directory.fromUri(resolvedUri);
}

void _patchMediaKitVideo({required String path, required bool dryRun}) {
  final file = File(path);
  if (!file.existsSync()) {
    stdout.writeln('Source file does not exist: $path');
    return;
  }

  final content = file.readAsStringSync();
  final patchedContent = content
      .replaceAll(
        '{MPV_RENDER_PARAM_API_TYPE, MPV_RENDER_API_TYPE_OPENGL}',
        '{MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(MPV_RENDER_API_TYPE_OPENGL)}',
      )
      .replaceAll(
        '{MPV_RENDER_PARAM_API_TYPE, MPV_RENDER_API_TYPE_SW}',
        '{MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(MPV_RENDER_API_TYPE_SW)}',
      )
      .replaceAll(
        '{MPV_RENDER_PARAM_SW_FORMAT, "rgb0"}',
        '{MPV_RENDER_PARAM_SW_FORMAT, const_cast<char*>("rgb0")}',
      );

  if (patchedContent == content) {
    stdout.writeln('No patch needed for $path');
    return;
  }

  if (dryRun) {
    stdout.writeln('Would patch $path');
    return;
  }

  file.writeAsStringSync(patchedContent);
  stdout.writeln('Patched $path');
}
