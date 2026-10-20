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

  final inAppWebviewLinuxRoot = _tryPackageRoot(
    packageConfigFile,
    packages,
    'flutter_inappwebview_linux',
  );

  if (inAppWebviewLinuxRoot != null) {
    _patchInAppWebviewLinux(
      path:
          '${inAppWebviewLinuxRoot.path}${Platform.pathSeparator}linux${Platform.pathSeparator}in_app_webview${Platform.pathSeparator}in_app_webview_settings.cc',
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

void _patchInAppWebviewLinux({required String path, required bool dryRun}) {
  final file = File(path);
  if (!file.existsSync()) {
    stdout.writeln('Source file does not exist: $path');
    return;
  }

  final content = file.readAsStringSync();
  if (content.contains('WPE_SETTING_DISABLE_ANIMATIONS WPE_SETTING_REDUCED_MOTION') ||
      content.contains('#ifndef WPE_SETTING_DISABLE_ANIMATIONS')) {
    stdout.writeln('No patch needed for $path');
    return;
  }

  const target = '#ifdef HAVE_WPE_PLATFORM\n#include <wpe/wpe-platform.h>\n#endif';
  const replacement = '''#ifdef HAVE_WPE_PLATFORM
#include <wpe/wpe-platform.h>
#ifndef WPE_SETTING_DISABLE_ANIMATIONS
#if defined(WPE_SETTING_REDUCED_MOTION)
#define WPE_SETTING_DISABLE_ANIMATIONS WPE_SETTING_REDUCED_MOTION
#else
#define WPE_SETTING_DISABLE_ANIMATIONS "/wpe-platform/reduced-motion"
#endif
#endif
#endif''';

  if (!content.contains(target)) {
    stdout.writeln('Could not find target block in $path');
    return;
  }

  final patchedContent = content.replaceFirst(target, replacement);

  if (dryRun) {
    stdout.writeln('Would patch $path');
    return;
  }

  file.writeAsStringSync(patchedContent);
  stdout.writeln('Patched $path');
}
