import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// iOS side of Nivio's own platform channels, the counterpart of
/// MainActivity.kt on Android:
///
///  * `com.nivio/device`: TV / HDR queries and handing the screen brightness
///    back after the player's brightness gesture (on iOS the brightness is
///    system-wide, so it must be restored when the player closes or the app
///    leaves the foreground).
///  * `com.nivio/media_session`: lock screen / Control Center / AirPods
///    controls through MPNowPlayingInfoCenter and MPRemoteCommandCenter.
///    Driven by MediaSessionService in Dart.
///  * `com.nivio/background_keepalive`: iOS has no foreground services. While
///    something holds a key here (watch party, torrent streaming, downloads),
///    going to the background asks iOS for extra time to finish work.
final class NivioPlugin: NSObject, FlutterPlugin {
  private static var shared: NivioPlugin?

  private let mediaSessionChannel: FlutterMethodChannel

  // Brightness
  private var systemBrightness: CGFloat?
  private var appBrightness: CGFloat?

  // Media session
  private var remoteCommandsInstalled = false
  private var seekStep: Double = 10
  private var artworkUrl: String?
  private var artwork: MPMediaItemArtwork?
  private var artworkTask: URLSessionDataTask?
  private var nowPlaying: [String: Any] = [:]

  // Background keep-alive
  private var keepAliveHolders = Set<String>()
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NivioPlugin(messenger: registrar.messenger())
    shared = instance
  }

  private init(messenger: FlutterBinaryMessenger) {
    mediaSessionChannel = FlutterMethodChannel(name: "com.nivio/media_session", binaryMessenger: messenger)
    super.init()

    let device = FlutterMethodChannel(name: "com.nivio/device", binaryMessenger: messenger)
    device.setMethodCallHandler { [weak self] call, result in
      self?.handleDevice(call, result: result)
    }

    mediaSessionChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleMediaSession(call, result: result)
    }

    let keepAlive = FlutterMethodChannel(name: "com.nivio/background_keepalive", binaryMessenger: messenger)
    keepAlive.setMethodCallHandler { [weak self] call, result in
      self?.handleKeepAlive(call, result: result)
    }

    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(didEnterBackground),
                       name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.addObserver(self, selector: #selector(willEnterForeground),
                       name: UIApplication.willEnterForegroundNotification, object: nil)
  }

  // MARK: - Device

  private func handleDevice(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isTv":
      result(false)
    case "hdrInfo":
      // The iOS player renders through an SDR Flutter texture, so HDR output
      // isn't offered; report the screen's EDR capability for diagnostics.
      var info: [String: Any] = ["isHdr": false, "types": [String]()]
      if #available(iOS 16.0, *) {
        info["edrHeadroom"] = Double(UIScreen.main.potentialEDRHeadroom)
      }
      result(info)
    case "rememberBrightness":
      if systemBrightness == nil {
        systemBrightness = UIScreen.main.brightness
      }
      result(nil)
    case "resetWindowBrightness":
      if let saved = systemBrightness {
        UIScreen.main.brightness = saved
      }
      systemBrightness = nil
      appBrightness = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Media session

  private func handleMediaSession(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "update":
      let args = call.arguments as? [String: Any] ?? [:]
      updateNowPlaying(args)
      result(nil)
    case "clear":
      clearNowPlaying()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func send(_ command: String, positionMs: Int? = nil) {
    var args: [String: Any] = ["command": command]
    if let positionMs = positionMs { args["positionMs"] = positionMs }
    mediaSessionChannel.invokeMethod("onCommand", arguments: args)
  }

  private func installRemoteCommands() {
    if remoteCommandsInstalled { return }
    remoteCommandsInstalled = true
    let commands = MPRemoteCommandCenter.shared()

    commands.playCommand.addTarget { [weak self] _ in
      self?.send("play"); return .success
    }
    commands.pauseCommand.addTarget { [weak self] _ in
      self?.send("pause"); return .success
    }
    commands.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.send("toggle"); return .success
    }
    commands.stopCommand.addTarget { [weak self] _ in
      self?.send("stop"); return .success
    }
    // Skip ±N seconds rather than next/previous track: there is no playlist
    // and iOS shows either skip or track buttons, not both.
    commands.skipForwardCommand.addTarget { [weak self] _ in
      self?.send("fastForward"); return .success
    }
    commands.skipBackwardCommand.addTarget { [weak self] _ in
      self?.send("rewind"); return .success
    }
    commands.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      self?.send("seek", positionMs: Int(event.positionTime * 1000))
      return .success
    }
    commands.nextTrackCommand.isEnabled = false
    commands.previousTrackCommand.isEnabled = false
    applyCommandState(enabled: true)
  }

  private func applyCommandState(enabled: Bool) {
    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.isEnabled = enabled
    commands.pauseCommand.isEnabled = enabled
    commands.togglePlayPauseCommand.isEnabled = enabled
    commands.stopCommand.isEnabled = enabled
    commands.skipForwardCommand.isEnabled = enabled
    commands.skipBackwardCommand.isEnabled = enabled
    commands.changePlaybackPositionCommand.isEnabled = enabled
    commands.skipForwardCommand.preferredIntervals = [NSNumber(value: seekStep)]
    commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: seekStep)]
  }

  private func updateNowPlaying(_ args: [String: Any]) {
    if let stepMs = (args["seekStepMs"] as? NSNumber)?.doubleValue, stepMs > 0 {
      seekStep = stepMs / 1000
    }
    installRemoteCommands()
    applyCommandState(enabled: true)

    let title = args["title"] as? String ?? ""
    let subtitle = args["subtitle"] as? String ?? ""
    let artUrl = args["artUrl"] as? String ?? ""
    let durationMs = (args["durationMs"] as? NSNumber)?.doubleValue ?? 0
    let positionMs = (args["positionMs"] as? NSNumber)?.doubleValue ?? 0
    let playing = args["playing"] as? Bool ?? false

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyArtist: subtitle,
      MPMediaItemPropertyPlaybackDuration: durationMs / 1000,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: positionMs / 1000,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
    ]
    if artUrl != artworkUrl {
      loadArtwork(artUrl)
    }
    if let artwork = artwork {
      info[MPMediaItemPropertyArtwork] = artwork
    }
    // iOS derives playing/paused from the playback rate (playbackState is
    // macOS-only).
    nowPlaying = info
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func loadArtwork(_ url: String) {
    artworkTask?.cancel()
    artworkTask = nil
    artworkUrl = url
    artwork = nil
    guard !url.isEmpty, let parsed = URL(string: url) else { return }
    let task = URLSession.shared.dataTask(with: parsed) { [weak self] data, _, _ in
      guard let data = data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async {
        guard let self = self, self.artworkUrl == url else { return }
        let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        self.artwork = art
        if !self.nowPlaying.isEmpty {
          self.nowPlaying[MPMediaItemPropertyArtwork] = art
          MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlaying
        }
      }
    }
    artworkTask = task
    task.resume()
  }

  private func clearNowPlaying() {
    artworkTask?.cancel()
    artworkTask = nil
    artworkUrl = nil
    artwork = nil
    nowPlaying = [:]
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    if remoteCommandsInstalled {
      applyCommandState(enabled: false)
    }
  }

  // MARK: - Background keep-alive

  private func handleKeepAlive(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let key = args["key"] as? String ?? "default"
    switch call.method {
    case "hold":
      keepAliveHolders.insert(key)
      if UIApplication.shared.applicationState == .background {
        beginBackgroundTask()
      }
      result(true)
    case "release":
      keepAliveHolders.remove(key)
      if keepAliveHolders.isEmpty {
        endBackgroundTask()
      }
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func beginBackgroundTask() {
    guard backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "NivioKeepAlive") { [weak self] in
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  // MARK: - App lifecycle

  @objc private func didEnterBackground() {
    // Don't leave the home screen at the player's brightness.
    if let saved = systemBrightness {
      appBrightness = UIScreen.main.brightness
      UIScreen.main.brightness = saved
    }
    if !keepAliveHolders.isEmpty {
      beginBackgroundTask()
    }
  }

  @objc private func willEnterForeground() {
    if systemBrightness != nil, let app = appBrightness {
      UIScreen.main.brightness = app
    }
    appBrightness = nil
    endBackgroundTask()
  }
}
