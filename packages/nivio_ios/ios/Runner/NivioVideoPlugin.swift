import AVFoundation
import AVKit
import Flutter
import UIKit

/// iOS video output for media_kit players, driven from Dart by
/// lib/services/ios_video_output.dart on "com.nivio/ios_video".
///
/// Each player gets one AVSampleBufferDisplayLayer for its whole life. mpv
/// draws into it directly (vo=avfoundation, --wid=<layer>): VideoToolbox frames
/// go to the layer untouched, so iOS shows HDR10 / HLG / Dolby Vision as HDR,
/// the same layer is the picture-in-picture source, and there is no OpenGL
/// (which iOS forbids in the background). mpv adds its subtitle (OSD) layer
/// next to the display layer, so both live in a container layer that moves
/// between whichever "nivio/ios_video" platform view shows the player (the
/// player screen or the mini player).
final class NivioVideoPlugin: NSObject, FlutterPlugin {
  private static var shared: NivioVideoPlugin?

  private let channel: FlutterMethodChannel
  fileprivate var entries: [Int64: NivioVideoEntry] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.nivio/ios_video", binaryMessenger: registrar.messenger())
    let instance = NivioVideoPlugin(channel: channel)
    shared = instance
    channel.setMethodCallHandler { [weak instance] call, result in
      instance?.onMethodCall(call, result: result)
    }
    registrar.register(NivioVideoViewFactory(plugin: instance), withId: "nivio/ios_video")
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(willEnterForeground),
      name: UIApplication.willEnterForegroundNotification, object: nil)
  }

  fileprivate func send(_ method: String, _ args: [String: Any]) {
    channel.invokeMethod(method, arguments: args)
  }

  private func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let handle = (args["handle"] as? NSNumber)?.int64Value ?? 0
    switch call.method {
    case "create":
      let entry = entries[handle] ?? NivioVideoEntry(handle: handle, plugin: self)
      entries[handle] = entry
      // The pointer mpv takes as --wid. The entry keeps the layer alive; the
      // VO retains it too while it runs.
      result(Int64(Int(bitPattern: Unmanaged.passUnretained(entry.displayLayer).toOpaque())))
    case "dispose":
      entries.removeValue(forKey: handle)?.dispose()
      result(nil)
    case "setGravity":
      entries[handle]?.setGravity(args["fit"] as? String ?? "contain")
      result(nil)
    case "setHdr":
      entries[handle]?.setHdr(args["enabled"] as? Bool ?? true)
      result(nil)
    case "setAutoPip":
      entries[handle]?.setAutoPip(args["enabled"] as? Bool ?? false)
      result(nil)
    case "playback":
      entries[handle]?.updatePlayback(
        playing: args["playing"] as? Bool ?? false,
        durationMs: (args["durationMs"] as? NSNumber)?.doubleValue ?? 0)
      result(nil)
    case "startPip":
      result(entries[handle]?.startPip() ?? false)
    case "stopPip":
      entries[handle]?.stopPip()
      result(nil)
    case "pipActive":
      result(entries[handle]?.pipActive ?? false)
    case "pipSupported":
      result(AVPictureInPictureController.isPictureInPictureSupported())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Back in Nivio: the video is shown inline again, as on Android.
  @objc private func willEnterForeground() {
    for entry in entries.values where entry.pipActive {
      entry.stopPip()
    }
  }
}

// MARK: - Per-player layer and PiP

final class NivioVideoEntry: NSObject {
  let handle: Int64
  let container = CALayer()
  let displayLayer = AVSampleBufferDisplayLayer()
  fileprivate weak var host: NivioVideoHostView?
  private weak var plugin: NivioVideoPlugin?

  private var pipController: AVPictureInPictureController?
  private var autoPip = false
  private var playing = false
  private var durationSec: Double = 0
  fileprivate(set) var pipActive = false

  fileprivate init(handle: Int64, plugin: NivioVideoPlugin) {
    self.handle = handle
    self.plugin = plugin
    super.init()
    container.backgroundColor = UIColor.black.cgColor
    container.masksToBounds = true
    displayLayer.backgroundColor = UIColor.black.cgColor
    displayLayer.videoGravity = .resizeAspect
    container.addSublayer(displayLayer)
  }

  fileprivate func attach(to view: NivioVideoHostView) {
    host = view
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    container.removeFromSuperlayer()
    view.layer.addSublayer(container)
    layout(in: view.bounds)
    CATransaction.commit()
    ensurePipController()
  }

  fileprivate func detach(from view: NivioVideoHostView) {
    guard host === view else { return }
    // Leave the layer where it is while PiP shows it; the next view takes it.
    if pipActive { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    container.removeFromSuperlayer()
    CATransaction.commit()
    host = nil
  }

  fileprivate func layout(in bounds: CGRect) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    container.frame = bounds
    displayLayer.frame = container.bounds
    CATransaction.commit()
  }

  func setGravity(_ fit: String) {
    switch fit {
    case "cover", "fitWidth", "fitHeight":
      displayLayer.videoGravity = .resizeAspectFill
    case "fill":
      displayLayer.videoGravity = .resize
    default:
      displayLayer.videoGravity = .resizeAspect
    }
  }

  /// On (HDR Output enabled and an HDR video playing): the layer uses the
  /// screen's extra brightness (EDR). Off: iOS tone-maps HDR to SDR.
  func setHdr(_ enabled: Bool) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if #available(iOS 26.0, *) {
      displayLayer.preferredDynamicRange = enabled ? .high : .standard
    } else if #available(iOS 17.0, *) {
      displayLayer.wantsExtendedDynamicRangeContent = enabled
    }
    CATransaction.commit()
  }

  func setAutoPip(_ enabled: Bool) {
    autoPip = enabled
    pipController?.canStartPictureInPictureAutomaticallyFromInline = enabled
  }

  func updatePlayback(playing: Bool, durationMs: Double) {
    self.playing = playing
    durationSec = durationMs / 1000
    pipController?.invalidatePlaybackState()
  }

  private func ensurePipController() {
    guard pipController == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
    let controller = AVPictureInPictureController(contentSource: source)
    controller.delegate = self
    controller.canStartPictureInPictureAutomaticallyFromInline = autoPip
    pipController = controller
  }

  func startPip() -> Bool {
    ensurePipController()
    guard let controller = pipController, controller.isPictureInPicturePossible else { return false }
    controller.startPictureInPicture()
    return true
  }

  func stopPip() {
    pipController?.stopPictureInPicture()
  }

  fileprivate func dispose() {
    pipController?.stopPictureInPicture()
    pipController = nil
    container.removeFromSuperlayer()
    displayLayer.flushAndRemoveImage()
  }

  private func send(_ method: String, _ args: [String: Any]) {
    var payload = args
    payload["handle"] = handle
    plugin?.send(method, payload)
  }
}

extension NivioVideoEntry: AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
    pipActive = true
    send("pipState", ["active": true])
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
    pipActive = false
    send("pipState", ["active": false])
    // The view the player now belongs to may have changed while in PiP.
    if let host = host, container.superlayer !== host.layer {
      attach(to: host)
    }
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    pipActive = false
    send("pipState", ["active": false, "error": error.localizedDescription])
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }
}

extension NivioVideoEntry: AVPictureInPictureSampleBufferPlaybackDelegate {
  func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
    self.playing = playing
    send("pipCommand", ["command": playing ? "play" : "pause"])
    controller.invalidatePlaybackState()
  }

  func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
    guard durationSec > 0 else {
      // Unknown length (live): no scrubber.
      return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    return CMTimeRange(start: .zero, duration: CMTime(seconds: durationSec, preferredTimescale: 1000))
  }

  func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
    !playing
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    send("pipCommand", ["command": "seekBy", "deltaMs": Int(skipInterval.seconds * 1000)])
    completionHandler()
  }
}

// MARK: - Platform view

final class NivioVideoViewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: NivioVideoPlugin?

  init(plugin: NivioVideoPlugin) {
    self.plugin = plugin
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let params = args as? [String: Any] ?? [:]
    let handle = (params["handle"] as? NSNumber)?.int64Value ?? 0
    let view = NivioVideoHostView(frame: frame)
    if let entry = plugin?.entries[handle] {
      view.entry = entry
      entry.setGravity(params["fit"] as? String ?? "contain")
      entry.attach(to: view)
    }
    return NivioVideoPlatformView(view: view)
  }
}

final class NivioVideoPlatformView: NSObject, FlutterPlatformView {
  private let hostView: NivioVideoHostView

  init(view: NivioVideoHostView) {
    hostView = view
  }

  func view() -> UIView { hostView }

  deinit {
    let hostView = hostView
    DispatchQueue.main.async {
      hostView.entry?.detach(from: hostView)
    }
  }
}

final class NivioVideoHostView: UIView {
  fileprivate var entry: NivioVideoEntry?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
    isUserInteractionEnabled = false
    clipsToBounds = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func layoutSubviews() {
    super.layoutSubviews()
    if let entry = entry, entry.host === self {
      entry.layout(in: bounds)
    }
  }
}
