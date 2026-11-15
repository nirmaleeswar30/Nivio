import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Nivio's notification identity on Windows.
///
/// flutter_local_notifications only works on Windows once it's given these:
/// without them its Windows side was never set up and every notification
/// was dropped. The app ID and the GUID (which names the toast activation
/// handler) must never change, or Windows treats it as a different app.
const String nivioWindowsAppId = 'Nivio.Nivio';
const String _windowsActivatorGuid = '8e1667cc-a577-44c4-84f1-170ef462a084';

WindowsInitializationSettings nivioWindowsInitSettings() =>
    WindowsInitializationSettings(
      appName: 'Nivio',
      appUserModelId: nivioWindowsAppId,
      guid: _windowsActivatorGuid,
      iconPath: _iconPath(),
    );

/// The app icon for toasts, from the bundled assets. The desktop app pulls
/// Nivio's code in as a package, so its assets can sit under packages/nivio.
String? _iconPath() {
  if (!Platform.isWindows) return null;
  final assets =
      '${File(Platform.resolvedExecutable).parent.path}\\data\\flutter_assets';
  for (final relative in const [
    r'\assets\images\nivio.png',
    r'\packages\nivio\assets\images\nivio.png',
  ]) {
    final path = '$assets$relative';
    if (File(path).existsSync()) return path;
  }
  return null;
}
