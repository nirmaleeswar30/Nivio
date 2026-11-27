/// Cross-platform screen brightness control implemented with Flutter channels.
library;

import 'src/brightness_mode.dart';
import 'src/device_screen_brightness_platform.dart';
import 'src/exceptions/device_screen_brightness_exception.dart';
import 'src/models/brightness_capabilities.dart';

export 'src/brightness_mode.dart';
export 'src/exceptions/device_screen_brightness_exception.dart';
export 'src/models/brightness_capabilities.dart';

/// Public asynchronous facade for reading, changing, and observing brightness.
abstract final class DeviceScreenBrightness {
  /// Reads the current brightness on the normalized 0–100 scale.
  static Future<int> getBrightness({
    BrightnessMode mode = BrightnessMode.system,
  }) => DeviceScreenBrightnessPlatform.instance.getBrightness(mode: mode);

  /// Requests [value] and returns the value actually applied.
  static Future<int> setBrightness(
    int value, {
    BrightnessMode mode = BrightnessMode.system,
  }) {
    _validateBrightness(value);
    return DeviceScreenBrightnessPlatform.instance.setBrightness(
      value,
      mode: mode,
    );
  }

  /// Increases brightness by one native platform step.
  static Future<int> incrementBrightness({
    BrightnessMode mode = BrightnessMode.system,
  }) => DeviceScreenBrightnessPlatform.instance.adjustBrightness(
    mode: mode,
    direction: BrightnessAdjustment.increase,
  );

  /// Decreases brightness by one native platform step.
  static Future<int> decrementBrightness({
    BrightnessMode mode = BrightnessMode.system,
  }) => DeviceScreenBrightnessPlatform.instance.adjustBrightness(
    mode: mode,
    direction: BrightnessAdjustment.decrease,
  );

  /// Emits the current brightness immediately and subsequent native changes.
  static Stream<int> streamBrightness({
    BrightnessMode mode = BrightnessMode.system,
  }) => DeviceScreenBrightnessPlatform.instance.streamBrightness(mode: mode);

  /// Whether Android may write global system brightness.
  ///
  /// Returns `true` on platforms where this special permission does not apply.
  static Future<bool> hasPermission() =>
      DeviceScreenBrightnessPlatform.instance.hasPermission();

  /// Opens Android settings so the user can grant `WRITE_SETTINGS`.
  ///
  /// This completes without side effects on other platforms.
  static Future<void> requestPermission() =>
      DeviceScreenBrightnessPlatform.instance.requestPermission();

  /// Returns the feature set reported by the active display backend.
  static Future<BrightnessCapabilities> getCapabilities() =>
      DeviceScreenBrightnessPlatform.instance.getCapabilities();

  static void _validateBrightness(int value) {
    if (value < 0 || value > 100) {
      throw InvalidBrightnessValueException(
        message: 'Brightness must be between 0 and 100, got $value.',
        details: <String, Object?>{'value': value},
      );
    }
  }
}
