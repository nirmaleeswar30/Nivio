import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'brightness_mode.dart';
import 'device_screen_brightness_platform.dart';
import 'exceptions/device_screen_brightness_exception.dart';
import 'models/brightness_capabilities.dart';

/// Platform implementation backed by Flutter method and event channels.
class MethodChannelDeviceScreenBrightness
    extends DeviceScreenBrightnessPlatform {
  MethodChannelDeviceScreenBrightness({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel(_methodChannelName),
       _eventChannel = eventChannel ?? const EventChannel(_eventChannelName);

  static const String _methodChannelName =
      'dev.arcas.device_screen_brightness/methods';
  static const String _eventChannelName =
      'dev.arcas.device_screen_brightness/events';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<_BrightnessEvent>? _sharedEvents;

  @override
  Future<int> getBrightness({required BrightnessMode mode}) =>
      _invokeValue('getBrightness', <String, Object?>{'mode': mode.name});

  @override
  Future<int> setBrightness(int value, {required BrightnessMode mode}) =>
      _invokeValue('setBrightness', <String, Object?>{
        'mode': mode.name,
        'value': value,
      });

  @override
  Future<int> adjustBrightness({
    required BrightnessMode mode,
    required BrightnessAdjustment direction,
  }) => _invokeValue('adjustBrightness', <String, Object?>{
    'mode': mode.name,
    'direction': direction.name,
  });

  @override
  Stream<int> streamBrightness({required BrightnessMode mode}) {
    final actualMode = !Platform.isAndroid && mode == BrightnessMode.app
        ? BrightnessMode.system
        : mode;
    final events = _sharedEvents ??= _createSharedEventStream();
    final changes = events
        .where((event) => event.mode == actualMode)
        .map((event) => event.value);
    return _withInitialValue(mode, changes).distinct();
  }

  Stream<int> _withInitialValue(
    BrightnessMode mode,
    Stream<int> changes,
  ) async* {
    yield await getBrightness(mode: mode);
    yield* changes;
  }

  @override
  Future<bool> hasPermission() async {
    try {
      return await _methodChannel.invokeMethod<bool>('hasPermission') ?? false;
    } on PlatformException catch (error) {
      throw _translatePlatformException(error);
    }
  }

  @override
  Future<void> requestPermission() async {
    try {
      await _methodChannel.invokeMethod<void>('requestPermission');
    } on PlatformException catch (error) {
      throw _translatePlatformException(error);
    }
  }

  @override
  Future<BrightnessCapabilities> getCapabilities() async {
    try {
      final payload = await _methodChannel.invokeMethod<Object?>(
        'getCapabilities',
      );
      return BrightnessCapabilities.fromPlatform(_asMap(payload));
    } on PlatformException catch (error) {
      throw _translatePlatformException(error);
    }
  }

  Future<int> _invokeValue(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final payload = await _methodChannel.invokeMethod<Object?>(
        method,
        arguments,
      );
      final value = _asMap(payload)['value'];
      if (value is int && value >= 0 && value <= 100) return value;
      throw FormatException('Expected brightness in [0, 100], got $value.');
    } on PlatformException catch (error) {
      throw _translatePlatformException(error);
    }
  }

  Stream<_BrightnessEvent> _createSharedEventStream() {
    late StreamController<_BrightnessEvent> controller;
    StreamSubscription<Object?>? nativeSubscription;

    controller = StreamController<_BrightnessEvent>.broadcast(
      onListen: () {
        nativeSubscription = _eventChannel.receiveBroadcastStream().listen(
          (event) {
            try {
              controller.add(_BrightnessEvent.fromPlatform(_asMap(event)));
            } on Object catch (error, stackTrace) {
              controller.addError(error, stackTrace);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            controller.addError(
              error is PlatformException
                  ? _translatePlatformException(error)
                  : error,
              stackTrace,
            );
          },
        );
      },
      onCancel: () async {
        await nativeSubscription?.cancel();
        nativeSubscription = null;
      },
    );
    return controller.stream;
  }

  static Map<Object?, Object?> _asMap(Object? payload) {
    if (payload is Map<Object?, Object?>) return payload;
    throw FormatException('Expected a platform map, received $payload.');
  }

  static DeviceScreenBrightnessException _translatePlatformException(
    PlatformException error,
  ) {
    final rawDetails = error.details;
    final details = rawDetails is Map
        ? rawDetails.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, Object?>{'nativeDetails': rawDetails};
    final message = error.message ?? 'The native brightness operation failed.';

    return switch (error.code) {
      'unsupported_operation' => UnsupportedOperationException(
        message: message,
        details: details,
      ),
      'invalid_brightness_value' => InvalidBrightnessValueException(
        message: message,
        details: details,
      ),
      'permission_denied' => PermissionDeniedException(
        message: message,
        details: details,
      ),
      'backend_not_available' => BackendNotAvailableException(
        message: message,
        details: details,
      ),
      'brightness_observation_failure' => BrightnessObservationException(
        message: message,
        details: details,
      ),
      'plugin_detached' => PluginDetachedException(
        message: message,
        details: details,
      ),
      _ => NativeBackendException(message: message, details: details),
    };
  }
}

final class _BrightnessEvent {
  const _BrightnessEvent(this.value, this.mode);

  final int value;
  final BrightnessMode mode;

  factory _BrightnessEvent.fromPlatform(Map<Object?, Object?> map) {
    final value = map['value'];
    final modeName = map['mode']?.toString();
    if (value is! int || value < 0 || value > 100) {
      throw FormatException('Invalid brightness event value: $value.');
    }
    final matches = BrightnessMode.values.where(
      (mode) => mode.name == modeName,
    );
    if (matches.isEmpty) {
      throw FormatException('Invalid brightness event mode: $modeName.');
    }
    return _BrightnessEvent(value, matches.single);
  }
}
