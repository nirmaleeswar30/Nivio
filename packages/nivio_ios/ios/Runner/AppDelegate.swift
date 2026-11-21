import AVFoundation
import UserNotifications
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Video playback: plays with the ring/silent switch on silent, and keeps
    // sound going in the background (UIBackgroundModes: audio). The session
    // is only activated by mpv when playback starts, so other apps' audio
    // isn't interrupted at launch.
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])

    // flutter_local_notifications: show notifications while Nivio is open.
    UNUserNotificationCenter.current().delegate = self

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NivioPlugin") {
      NivioPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NivioVideoPlugin") {
      NivioVideoPlugin.register(with: registrar)
    }
  }
}
