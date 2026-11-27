import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'brightness_mode.dart';
import 'device_screen_brightness_method_channel.dart';
import 'models/brightness_capabilities.dart';

/// Contract implemented by the platform-channel transport.
abstract class DeviceScreenBrightnessPlatform extends PlatformInterface {
  DeviceScreenBrightnessPlatform() : super(token: _token);

  static final Object _token = Object();
  static DeviceScreenBrightnessPlatform _instance =
      MethodChannelDeviceScreenBrightness();

  static DeviceScreenBrightnessPlatform get instance => _instance;

  static set instance(DeviceScreenBrightnessPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<int> getBrightness({required BrightnessMode mode});

  Future<int> setBrightness(int value, {required BrightnessMode mode});

  Future<int> adjustBrightness({
    required BrightnessMode mode,
    required BrightnessAdjustment direction,
  });

  Stream<int> streamBrightness({required BrightnessMode mode});

  Future<bool> hasPermission();

  Future<void> requestPermission();

  Future<BrightnessCapabilities> getCapabilities();
}

/// Direction passed to the native `adjustBrightness` method.
enum BrightnessAdjustment { increase, decrease }
