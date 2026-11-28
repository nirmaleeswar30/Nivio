# Vendored plugins

Patched copies of pub.dev plugins, used by `packages/nivio_mobile` through
`dependency_overrides`. The only changes are in each plugin's
`android/build.gradle`, and each change is marked with a `Nivio:` comment.

| Plugin | Upstream version | Change |
|---|---|---|
| `device_screen_brightness` | 2.0.0 | Doesn't apply the Kotlin Gradle Plugin (KGP) or pin AGP 8.11 in `buildscript` |
| `flutter_volume_controller` | 2.0.2 | Conditional `apply plugin: 'kotlin-android'` removed |
| `workmanager_android` | 0.10.9 | Conditional `apply plugin: 'kotlin-android'` removed |

## Why

The app builds with AGP 9's built-in Kotlin (`android.builtInKotlin=true`).
Flutter's Gradle plugin scans each plugin's build file as text. Any
`apply plugin: 'kotlin-android'` line counts, even one inside an `if` that
never runs, and Flutter prints "Your app uses the following plugins that
apply Kotlin Gradle Plugin". It says future versions will fail such builds.
When built-in Kotlin is off, Flutter applies KGP to plugins itself, so
dropping the line is safe either way.

## When to remove

Delete a copy, and its override in `packages/nivio_mobile/pubspec.yaml`,
once a release of that plugin no longer applies KGP in its
`android/build.gradle`.
