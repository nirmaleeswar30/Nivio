/// Determines whether brightness operations affect the current app window
/// or the global system setting.
///
/// **Only meaningful on Android.** On all other platforms this parameter is
/// ignored and the system brightness is always used.
///
/// | Mode     | Android behaviour | Permission needed |
/// |----------|-------------------|-------------------|
/// | [app]    | Sets `WindowManager.LayoutParams.screenBrightness` on the current Activity. Only affects this app; resets when the Activity is destroyed. | None |
/// | [system] | Writes `Settings.System.SCREEN_BRIGHTNESS`. Affects the entire device and persists after the app is closed. | `WRITE_SETTINGS` |
enum BrightnessMode {
  /// Adjusts brightness only for the current app window (Android).
  ///
  /// No special permission is required. The value is not persisted — when
  /// the Activity is destroyed the brightness reverts to the system default.
  app,

  /// Adjusts the global system brightness (Android).
  ///
  /// Requires the `WRITE_SETTINGS` special permission. Use
  /// [DeviceScreenBrightness.hasPermission] and
  /// [DeviceScreenBrightness.requestPermission] before calling.
  system,
}
