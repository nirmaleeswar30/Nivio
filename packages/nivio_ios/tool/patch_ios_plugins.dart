// Patches plugin sources in the pub cache for the iOS build. Idempotent; run
// from packages/nivio_ios after `flutter pub get`:
//
//   dart run tool/patch_ios_plugins.dart [--dry-run]
//
// media_kit_video (iOS): the video texture is drawn with OpenGL ES on a
// worker thread whenever mpv has a new frame, with no check for the app's
// state. iOS terminates an app that submits OpenGL ES work while it is in the
// background, so playing on with the app in the background (sound keeps
// going, UIBackgroundModes: audio) gets Nivio killed. The patch stops
// rendering from the moment the app resigns active until it is active again.
// lib/services/ios_background_video.dart additionally switches the video
// track off while backgrounded, so mpv doesn't wait on frames nobody draws.
import 'dart:convert';
import 'dart:io';

const _marker = '// nivio-patch: no-gl-in-background';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final sep = Platform.pathSeparator;
  final configFile = File('${Directory.current.path}$sep.dart_tool${sep}package_config.json');
  if (!configFile.existsSync()) {
    stderr.writeln('package_config.json not found. Run flutter pub get first.');
    exit(1);
  }
  final config = jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
  final packages = (config['packages'] as List).cast<Map<String, Object?>>();

  final mediaKitVideo = _packageRoot(configFile, packages, 'media_kit_video');
  if (mediaKitVideo == null) {
    stderr.writeln('media_kit_video not found in package_config.json.');
    exit(1);
  }
  _patchVideoOutput(
    File('${mediaKitVideo.path}ios${sep}Classes${sep}plugin${sep}common${sep}VideoOutput.swift'),
    dryRun: dryRun,
  );
}

Directory? _packageRoot(File configFile, List<Map<String, Object?>> packages, String name) {
  final package = packages.where((p) => p['name'] == name).firstOrNull;
  if (package == null) return null;
  final rootUri = Uri.parse(package['rootUri'] as String);
  final resolved = rootUri.hasScheme ? rootUri : configFile.parent.uri.resolveUri(rootUri);
  final path = Directory.fromUri(resolved).path;
  return Directory(path.endsWith(Platform.pathSeparator) || path.endsWith('/') ? path : '$path/');
}

void _patchVideoOutput(File file, {required bool dryRun}) {
  if (!file.existsSync()) {
    stderr.writeln('Not found: ${file.path}');
    exit(1);
  }
  var source = file.readAsStringSync();
  if (source.contains(_marker)) {
    stdout.writeln('media_kit_video: already patched (${file.path})');
    return;
  }

  // 1. A process-wide "may render" flag, driven by the app's active state.
  const classOpen = 'public class VideoOutput: NSObject {\n';
  const gate = '''public class VideoOutput: NSObject {
  $_marker
  #if os(iOS)
    private static let renderLock = NSLock()
    private static var appIsActive = true
    private static let activeObservers: [NSObjectProtocol] = {
      let center = NotificationCenter.default
      return [
        center.addObserver(
          forName: UIApplication.willResignActiveNotification, object: nil, queue: nil
        ) { _ in VideoOutput.setAppIsActive(false) },
        center.addObserver(
          forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { _ in VideoOutput.setAppIsActive(true) },
      ]
    }()

    private static func setAppIsActive(_ value: Bool) {
      renderLock.lock()
      appIsActive = value
      renderLock.unlock()
    }

    static var mayRender: Bool {
      _ = activeObservers
      renderLock.lock()
      defer { renderLock.unlock() }
      return appIsActive
    }
  #else
    static var mayRender: Bool { true }
  #endif

''';

  // 2. Skip drawing while the app isn't active.
  const renderCall = '''    if disposed {
      return
    }

    texture.render(size)''';
  const gatedRenderCall = '''    if disposed {
      return
    }

    // nivio-patch: no OpenGL ES work while the app is not active.
    if !VideoOutput.mayRender {
      return
    }

    texture.render(size)''';

  // 3. Register the observers when the first output is created (on the main
  // thread), so the flag is right before any frame is drawn.
  const initCall = '''    super.init()

    worker.enqueue {''';
  const initWithObservers = '''    super.init()

    _ = VideoOutput.mayRender

    worker.enqueue {''';

  for (final (from, to) in [
    (classOpen, gate),
    (renderCall, gatedRenderCall),
    (initCall, initWithObservers),
  ]) {
    if (!source.contains(from)) {
      stderr.writeln('media_kit_video: unexpected VideoOutput.swift layout, could not find:\n$from');
      exit(1);
    }
    source = source.replaceFirst(from, to);
  }

  if (!source.contains('import UIKit')) {
    source = source.replaceFirst(
      '#if canImport(Flutter)\n  import Flutter\n',
      '#if canImport(Flutter)\n  import Flutter\n  import UIKit\n',
    );
  }

  if (dryRun) {
    stdout.writeln('media_kit_video: would patch ${file.path}');
    return;
  }
  file.writeAsStringSync(source);
  stdout.writeln('media_kit_video: patched ${file.path}');
}
