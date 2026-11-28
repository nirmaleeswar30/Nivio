/// Base exception for all device_screen_brightness errors.
///
/// Every public exception extends this class and carries a stable [code] for
/// programmatic matching, a human-readable [message] aimed at debugging, and
/// an optional [details] map with structured diagnostic data.
///
/// ### Details contract
///
/// When available, [details] should contain:
/// - `platform`  – e.g. `'iOS'`, `'android'`, `'linux'`.
/// - `operation` – the API method that failed, e.g. `'setBrightness'`.
/// - `backend`   – native subsystem involved, e.g. `'IOKit'`, `'sysfs'`.
/// - `nativeCode`    – raw error code from the native layer.
/// - `nativeMessage` – raw error message from the native layer.
/// - `suggestedAction` – a hint for the developer on how to resolve the issue.
abstract class DeviceScreenBrightnessException implements Exception {
  /// Stable, machine-readable error code.
  final String code;

  /// Human-readable description aimed at developers debugging the issue.
  final String message;

  /// Structured diagnostic data for logging and telemetry.
  final Map<String, Object?> details;

  const DeviceScreenBrightnessException(
    this.code,
    this.message, [
    this.details = const {},
  ]);

  @override
  String toString() {
    final buffer = StringBuffer(
      'DeviceScreenBrightnessException($code): $message',
    );
    if (details.isNotEmpty) {
      buffer.write(' | details: $details');
    }
    return buffer.toString();
  }
}

/// Thrown when an operation is not supported on the current platform.
final class UnsupportedOperationException
    extends DeviceScreenBrightnessException {
  const UnsupportedOperationException({
    required String message,
    Map<String, Object?> details = const {},
  }) : super('unsupported_operation', message, details);
}

/// Thrown when the caller supplies a brightness value outside the valid range.
final class InvalidBrightnessValueException
    extends DeviceScreenBrightnessException {
  const InvalidBrightnessValueException({
    required String message,
    Map<String, Object?> details = const {},
  }) : super('invalid_brightness_value', message, details);
}

/// Thrown when the native backend reports an unexpected failure.
///
/// [details] should include `nativeCode` and `nativeMessage` when available.
final class NativeBackendException extends DeviceScreenBrightnessException {
  const NativeBackendException({
    required String message,
    Map<String, Object?> details = const {},
  }) : super('native_backend_failure', message, details);
}

/// Thrown when setting up or maintaining a brightness observation stream fails.
final class BrightnessObservationException
    extends DeviceScreenBrightnessException {
  const BrightnessObservationException({
    required String message,
    Map<String, Object?> details = const {},
  }) : super('brightness_observation_failure', message, details);
}

/// Thrown when the required brightness backend is not available on the system.
///
/// Example: no backlight device on a headless Linux server or VM.
final class BackendNotAvailableException
    extends DeviceScreenBrightnessException {
  const BackendNotAvailableException({
    required String message,
    Map<String, Object?> details = const {},
  }) : super('backend_not_available', message, details);
}

/// Thrown when the application lacks the required permission to control brightness.
final class PermissionDeniedException extends DeviceScreenBrightnessException {
  const PermissionDeniedException({
    required String message,
    Map<String, Object?> details = const {},
  }) : super('permission_denied', message, details);
}

/// Thrown when an operation arrives after the native plugin was detached.
final class PluginDetachedException extends DeviceScreenBrightnessException {
  const PluginDetachedException({
    required String message,
    Map<String, Object?> details = const {},
  }) : super('plugin_detached', message, details);
}
