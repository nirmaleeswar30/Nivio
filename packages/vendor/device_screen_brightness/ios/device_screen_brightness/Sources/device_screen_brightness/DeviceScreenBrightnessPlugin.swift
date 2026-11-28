import Flutter
import UIKit

/// iOS channel implementation backed by `UIScreen.main.brightness`.
public final class DeviceScreenBrightnessPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "dev.arcas.device_screen_brightness/methods"
  private static let eventChannelName = "dev.arcas.device_screen_brightness/events"

  private var eventSink: FlutterEventSink?
  private var brightnessObserver: NSObjectProtocol?
  private var lastValue: Int?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = DeviceScreenBrightnessPlugin()
    let methods = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    let events = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methods)
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getBrightness":
      result(valueResult(readBrightness()))
    case "setBrightness":
      guard let value = arguments(call)["value"] as? Int, (0...100).contains(value) else {
        result(error("invalid_brightness_value", "Brightness must be between 0 and 100.", call.method))
        return
      }
      UIScreen.main.brightness = CGFloat(value) / 100.0
      let applied = readBrightness()
      guard abs(applied - value) <= 5 else {
        result(error("native_backend_failure", "UIScreen did not apply the requested brightness.", call.method))
        return
      }
      emitIfChanged()
      result(valueResult(applied))
    case "adjustBrightness":
      let direction = arguments(call)["direction"] as? String
      let current = readBrightness()
      let next: Int
      if direction == "increase" {
        next = min(100, current + 5)
      } else if direction == "decrease" {
        next = max(0, current - 5)
      } else {
        result(error("invalid_brightness_value", "Invalid adjustment direction.", call.method))
        return
      }
      UIScreen.main.brightness = CGFloat(next) / 100.0
      let applied = readBrightness()
      guard abs(applied - next) <= 5 else {
        result(error("native_backend_failure", "UIScreen did not apply the requested brightness.", call.method))
        return
      }
      emitIfChanged()
      result(valueResult(applied))
    case "hasPermission":
      result(true)
    case "requestPermission":
      result(nil)
    case "getCapabilities":
      #if targetEnvironment(simulator)
      let canWrite = false
      let writeSupport = "unsupported"
      #else
      let canWrite = true
      let writeSupport = "supported"
      #endif
      result([
        "canRead": true,
        "canWrite": canWrite,
        "canObserve": true,
        "writeSupport": writeSupport,
        "supportedModes": ["system"],
        "requiresWriteSettingsPermission": false,
        "backend": "ios-ui-screen",
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    lastValue = nil
    brightnessObserver = NotificationCenter.default.addObserver(
      forName: UIScreen.brightnessDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.emitIfChanged()
    }
    emitIfChanged()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer = brightnessObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    brightnessObserver = nil
    eventSink = nil
    lastValue = nil
    return nil
  }

  deinit {
    if let observer = brightnessObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private func readBrightness() -> Int {
    Int((UIScreen.main.brightness * 100.0).rounded()).clamped(to: 0...100)
  }

  private func emitIfChanged() {
    let value = readBrightness()
    guard value != lastValue else { return }
    lastValue = value
    eventSink?(["value": value, "mode": "system"])
  }

  private func arguments(_ call: FlutterMethodCall) -> [String: Any] {
    call.arguments as? [String: Any] ?? [:]
  }

  private func valueResult(_ value: Int) -> [String: Any] {
    ["value": value]
  }

  private func error(_ code: String, _ message: String, _ operation: String) -> FlutterError {
    FlutterError(
      code: code,
      message: message,
      details: ["platform": "ios", "operation": operation]
    )
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
