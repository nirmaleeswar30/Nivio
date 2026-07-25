# Shorebird OTA Setup

This project is configured for Shorebird Code Push on Android and desktop
Linux.

## What's already wired

- `shorebird_code_push` dependency is added.
- `shorebird.yaml` exists and is included in `pubspec.yaml` assets.
- `auto_update: true` is set, so Shorebird checks for updates automatically on launch.
- App startup runs a background OTA check.
- Settings screen includes **Check OTA Update** for manual checks.

## Release and patch workflow

Run all commands from the project root.

1. Create your first Shorebird release:
   ```powershell
   shorebird release android
   ```
2. Install that release build on a device.
3. After code changes, publish an OTA patch:
   ```powershell
   shorebird patch android
   ```
4. Open the app and use **Settings -> Check OTA Update**.
5. Restart the app when prompted so the patch is applied.

## Important notes

- Shorebird patches are only delivered to apps installed from a Shorebird release.
- `flutter run` builds will show OTA as unavailable.

## Linux desktop

Run desktop commands from `nivio_desktop/`.

1. Create a Linux desktop release:
   ```bash
   shorebird release linux
   ```
2. Publish the full Linux artifact from `build/linux/` to GitHub Releases.
3. After Dart-only fixes, publish a patch:
   ```bash
   shorebird patch linux
   ```

Nivio Desktop also checks GitHub Releases for full binary updates at startup in
release builds and from **Settings -> Check for Updates**.
