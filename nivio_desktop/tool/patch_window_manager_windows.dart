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
  final windowManagerPackage = packages
      .cast<Map<String, Object?>>()
      .where((package) => package['name'] == 'window_manager')
      .firstOrNull;

  if (windowManagerPackage == null) {
    throw StateError('window_manager was not found in package_config.json.');
  }

  final packageRoot = _resolvePackageRoot(
    packageConfigFile,
    windowManagerPackage['rootUri'] as String,
  );

  _patchClassDeclarationQualifiers(
    path:
        '${packageRoot.path}${Platform.pathSeparator}windows${Platform.pathSeparator}window_manager.cpp',
    className: 'WindowManager',
    firstDefinitionMarker: 'WindowManager::WindowManager()',
    dryRun: dryRun,
  );

  _patchClassDeclarationQualifiers(
    path:
        '${packageRoot.path}${Platform.pathSeparator}windows${Platform.pathSeparator}window_manager_plugin.cpp',
    className: 'WindowManagerPlugin',
    firstDefinitionMarker: 'WindowManagerPlugin::WindowManagerPlugin',
    dryRun: dryRun,
  );
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
  required String firstDefinitionMarker,
  required bool dryRun,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      'Expected window_manager source file does not exist: $path',
    );
  }

  final content = file.readAsStringSync();
  final markerIndex = content.indexOf(firstDefinitionMarker);
  if (markerIndex < 0) {
    throw StateError("Could not find marker '$firstDefinitionMarker' in $path");
  }

  final declarationSection = content.substring(0, markerIndex);
  final definitionSection = content.substring(markerIndex);
  final patchedDeclarationSection = declarationSection.replaceAll(
    '$className::',
    '',
  );

  if (patchedDeclarationSection == declarationSection) {
    stdout.writeln('No patch needed for $path');
    return;
  }

  if (dryRun) {
    stdout.writeln('Would patch $path');
    return;
  }

  file.writeAsStringSync(patchedDeclarationSection + definitionSection);
  stdout.writeln('Patched $path');
}
