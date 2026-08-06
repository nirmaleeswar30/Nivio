import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final rootDir = Directory.current;
  final packageConfigFile = File(
    '${rootDir.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}package_config.json',
  );

  if (!packageConfigFile.existsSync()) {
    throw StateError(
      'Missing .dart_tool/package_config.json. Run flutter pub get first.',
    );
  }

  final packageConfig =
      jsonDecode(packageConfigFile.readAsStringSync()) as Map<String, Object?>;
  final packages = packageConfig['packages'] as List<Object?>;
  final windowManagerRoot = _packageRoot(
    packageConfigFile,
    packages,
    'window_manager',
  );
  final mediaKitVideoRoot = _packageRoot(
    packageConfigFile,
    packages,
    'media_kit_video',
  );

  _patchClassDeclarationQualifiers(
    path:
        '${windowManagerRoot.path}${Platform.pathSeparator}windows${Platform.pathSeparator}window_manager.cpp',
    className: 'WindowManager',
    classMarker: 'class WindowManager',
    dryRun: dryRun,
  );

  _patchClassDeclarationQualifiers(
    path:
        '${windowManagerRoot.path}${Platform.pathSeparator}windows${Platform.pathSeparator}window_manager_plugin.cpp',
    className: 'WindowManagerPlugin',
    classMarker: 'class WindowManagerPlugin',
    extraReplacements: const {
      '\nvoid RegisterWithRegistrar(\n    flutter::PluginRegistrarWindows* registrar) {':
          '\nvoid WindowManagerPlugin::RegisterWithRegistrar(\n    flutter::PluginRegistrarWindows* registrar) {',
    },
    dryRun: dryRun,
  );

  _patchMediaKitVideo(
    path:
        '${mediaKitVideoRoot.path}${Platform.pathSeparator}windows${Platform.pathSeparator}video_output.cc',
    dryRun: dryRun,
  );
}

Directory _packageRoot(
  File packageConfigFile,
  List<Object?> packages,
  String packageName,
) {
  final package = packages
      .cast<Map<String, Object?>>()
      .where((package) => package['name'] == packageName)
      .firstOrNull;

  if (package == null) {
    throw StateError('$packageName was not found in package_config.json.');
  }

  return _resolvePackageRoot(packageConfigFile, package['rootUri'] as String);
}

Directory _resolvePackageRoot(File packageConfigFile, String rootUriText) {
  final rootUri = Uri.parse(rootUriText);
  final resolvedUri = rootUri.hasScheme
      ? rootUri
      : packageConfigFile.parent.uri.resolveUri(rootUri);

  if (!resolvedUri.isScheme('file')) {
    throw StateError('Unsupported window_manager package URI: $rootUriText');
  }

  return Directory.fromUri(resolvedUri);
}

void _patchClassDeclarationQualifiers({
  required String path,
  required String className,
  required String classMarker,
  Map<String, String> extraReplacements = const {},
  required bool dryRun,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      'Expected window_manager source file does not exist: $path',
    );
  }

  final content = file.readAsStringSync();
  var patchedContent = content;
  for (final replacement in extraReplacements.entries) {
    patchedContent = patchedContent.replaceFirst(
      replacement.key,
      replacement.value,
    );
  }

  final classStart = patchedContent.indexOf(classMarker);
  if (classStart < 0) {
    throw StateError("Could not find marker '$classMarker' in $path");
  }

  final classEnd = patchedContent.indexOf('\n};', classStart);
  if (classEnd < 0) {
    throw StateError("Could not find end of '$classMarker' in $path");
  }

  final beforeClass = patchedContent.substring(0, classStart);
  final classBody = patchedContent.substring(classStart, classEnd);
  final afterClass = patchedContent.substring(classEnd);
  final patchedClassBody = classBody.replaceAll('$className::', '');

  patchedContent = beforeClass + patchedClassBody + afterClass;

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

void _patchMediaKitVideo({required String path, required bool dryRun}) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      'Expected media_kit_video source file does not exist: $path',
    );
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
