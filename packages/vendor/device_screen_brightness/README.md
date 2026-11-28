# device_screen_brightness

[![pub.dev](https://img.shields.io/pub/v/device_screen_brightness.svg)](https://pub.dev/packages/device_screen_brightness)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Control and observe screen brightness from Flutter through native platform
channels. Public values use an integer range from **0 to 100**.

## Platform support

| Platform | Backend | Read | Write | Observe |
|---|---|:---:|:---:|:---:|
| Android | Window brightness and `Settings.System` | ✅ | ✅ | ✅ |
| iOS | `UIScreen.main.brightness` | ✅ | ✅ | ✅ |
| macOS | DisplayServices or IOAVService DDC/CI | ✅ | Best effort | ✅ |
| Linux | `/sys/class/backlight` | ✅ | Permission-dependent | ✅ |
| Windows | Physical Monitor API / DXVA2 | ✅ | Best effort | ✅ |

The plugin reports the current device's runtime support through
`getCapabilities()`. Headless systems, virtual machines, unsupported monitors,
and restricted sessions may expose fewer capabilities than the table above.

## Installation

```yaml
dependencies:
  device_screen_brightness: ^2.0.0
```

## Usage

```dart
import 'package:device_screen_brightness/device_screen_brightness.dart';

final current = await DeviceScreenBrightness.getBrightness();
final applied = await DeviceScreenBrightness.setBrightness(75);

await DeviceScreenBrightness.incrementBrightness();
await DeviceScreenBrightness.decrementBrightness();

final subscription = DeviceScreenBrightness.streamBrightness().listen((value) {
  print('Brightness: $value');
});
```

The stream reads one initial value and then receives deduplicated changes from
the native plugin.

## Capabilities

```dart
final capabilities = await DeviceScreenBrightness.getCapabilities();

if (capabilities.canRead) {
  final brightness = await DeviceScreenBrightness.getBrightness();
}

if (capabilities.writeSupport == BrightnessWriteSupport.supported) {
  await DeviceScreenBrightness.setBrightness(60);
}
```

`BrightnessWriteSupport.bestEffort` means that the operating system exposes a
write API but the monitor, connection, sandbox, or system policy may reject the
operation. The plugin verifies writes where possible and throws a typed
exception instead of reporting a false success.

## Android modes and permission

Android supports two distinct modes:

| Mode | Behavior | Permission |
|---|---|---|
| `BrightnessMode.app` | Changes only the foreground Flutter activity | None |
| `BrightnessMode.system` | Changes the global system setting | `WRITE_SETTINGS` |

The package manifest declares `WRITE_SETTINGS`, but Android requires the user
to grant this special access explicitly:

```dart
if (!await DeviceScreenBrightness.hasPermission()) {
  await DeviceScreenBrightness.requestPermission();
}

await DeviceScreenBrightness.setBrightness(
  70,
  mode: BrightnessMode.system,
);
```

On other platforms, `BrightnessMode.app` is treated as system brightness for
compatibility, `hasPermission()` returns `true`, and `requestPermission()` is a
no-op.

## Error handling

All native failures extend `DeviceScreenBrightnessException`:

| Exception | Meaning |
|---|---|
| `InvalidBrightnessValueException` | Value is outside 0–100 |
| `PermissionDeniedException` | Required OS permission is missing |
| `BackendNotAvailableException` | No usable display/backlight backend exists |
| `UnsupportedOperationException` | The selected operation is unsupported |
| `BrightnessObservationException` | Native observation failed |
| `PluginDetachedException` | The Flutter engine detached from the plugin |
| `NativeBackendException` | Other native or hardware failure |

Each exception has a stable `code`, a developer-facing `message`, and a
structured `details` map.

## Platform notes

### macOS

The plugin selects one backend at runtime:

1. DisplayServices for built-in and Apple displays.
2. IOAVService DDC/CI for compatible third-party monitors on Apple Silicon.

DDC/CI may not work through adapters or hubs that block DDC, on Intel Macs, on
some built-in HDMI routes, or in sandboxed Mac App Store applications. macOS
writes are therefore reported as `bestEffort` and verified after execution.

### Linux

The selected `/sys/class/backlight/*/brightness` file must be writable. Many
distributions grant access through udev/logind; others require membership in an
appropriate group such as `video`. The plugin reports a permission error when
the file exists but cannot be written.

### Windows

Brightness control uses the primary logical monitor and the first compatible
physical monitor exposed through DXVA2. Some internal panels, virtual machines,
remote sessions, and monitors that disable DDC/CI do not expose this API.

## Migrating from 0.x

Version 2.0 replaces direct FFI/JNI calls with registered Flutter channels.
One-shot methods are now asynchronous:

```dart
// 0.x
final value = DeviceScreenBrightness.getBrightness();

// 2.0
final value = await DeviceScreenBrightness.getBrightness();
```

The `getBrightnessCompute`, `setBrightnessCompute`,
`incrementBrightnessCompute`, and `decrementBrightnessCompute` methods were
removed. Method Channels are already asynchronous, so use the corresponding
method without the `Compute` suffix.

`hasPermission()` and `requestPermission()` must also be awaited.

## License

[MIT](LICENSE)
