## 2.0.0

* **Breaking:** replace FFI, FFIgen, JNIgen, and Dart-side backend selection
  with registered Flutter Method and Event Channels on all five platforms.
* Make all one-shot brightness and permission APIs asynchronous.
* Remove the obsolete `*Compute` API variants.
* Add `BrightnessCapabilities` and `BrightnessWriteSupport` for runtime feature
  discovery and honest best-effort reporting on hardware-dependent backends.
* Add native brightness observation with a reliable initial stream value and
  deduplicated subsequent events.
* Android: use a Kotlin `FlutterPlugin` with `ActivityAware`, removing activity
  reflection and direct JNI access.
* iOS and macOS: add Swift Package Manager support alongside CocoaPods.
* macOS: retain DisplayServices and IOAVService DDC/CI, serialize native work,
  and verify writes before reporting success.
* Linux: migrate the sysfs backend into a registered GTK plugin.
* Windows: migrate DXVA2 into a registered C++ plugin and correctly enumerate,
  verify, and release physical monitors.
* Add channel contract tests, hardware-aware integration tests, and five-host
  build coverage.

## 0.3.1

* Add `example/linux` scaffolding and update `.metadata`.

## 0.3.0

* **macOS: DDC/CI support for third-party external monitors** via the private
  `IOAVService` API (Apple Silicon Macs, USB-C / Thunderbolt / DisplayPort
  Alt-Mode connections).  Based on the open-source
  [m1ddc](https://github.com/waydabber/m1ddc) project (MIT).
* macOS backend now auto-selects at runtime:
  1. `DisplayServices` for Apple native displays (built-in, Studio Display, Pro Display XDR).
  2. `IOAVService` DDC/CI for third-party external monitors — falls back to
     `BackendNotAvailableException` when neither backend is reachable.
* `macos/device_screen_brightness.podspec`: added `IOKit` to `s.frameworks`.
* README macOS section updated to document both backends and their limitations.

## 0.2.1

* README translated fully to English; macOS and Linux platform notes expanded.
* `spec_device_screen_brightness.md` excluded from version control via `.gitignore`.
* `windows/CMakeLists.txt` corrected to `LANGUAGES C` (was `CXX`).
* CI: added `test`, `build-macos` jobs; `dry-run` now depends on `analyze`.

## 0.2.0

* **`BrightnessMode` enum** — all brightness methods now accept an optional `mode` parameter (`BrightnessMode.app` or `BrightnessMode.system`).
  * `BrightnessMode.app` (Android): adjusts the current Activity window brightness — **no permission required**.
  * `BrightnessMode.system` (Android, default): writes `Settings.System.SCREEN_BRIGHTNESS` — requires `WRITE_SETTINGS`.
  * On iOS, macOS, Linux and Windows the parameter is ignored.
* Added `hasPermission()` and `requestPermission()` — Android `WRITE_SETTINGS` helpers (no-op on other platforms).
* Updated example app with a `SegmentedButton` to toggle between app and system mode.

## 0.1.0

* Unified C API: `device_screen_brightness_get`, `_set`, `_increment`, `_decrement`.
* Backend pattern: `DeviceScreenBrightnessBackend` abstract class with `FfiBackend` and `AndroidBackend`.
* All brightness values normalized to **int 0–100**.
* `abstract final class DeviceScreenBrightness` public facade.
* `streamBrightness()` with 250 ms polling.
* `*Compute` variants via `Flutter.compute`.
* 6 typed exceptions: `UnsupportedOperationException`, `InvalidBrightnessValueException`, `NativeBackendException`, `BrightnessObservationException`, `BackendNotAvailableException`, `PermissionDeniedException`.
* iOS: UIScreen.mainScreen.brightness (UIKit).
* macOS: IOKit (IODisplayGetFloatParameter).
* Linux: sysfs backlight (no external dependencies).
* Windows: Physical Monitor API (dxva2).
* Android: Settings.System via JNIgen.
* CI: analyze, dry-run, build-linux, build-windows.
* CD: OIDC Trusted Publisher via `dart-lang/setup-dart`.
