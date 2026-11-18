# Nivio for iOS (`nivio_ios`)

The iPhone / iPad app. Like `nivio_mobile` (Android) and `nivio_desktop`, it is
a thin app package around `nivio_core` (the root `lib/`).

- **Bundle id:** `com.nirmal.nivio` · **Minimum iOS:** 15.0 · iPhone + iPad
- **Distribution:** unsigned IPA from CI, signed at install time by a sideloading
  tool (AltStore, SideStore, Sideloadly, TrollStore, …).

## Building

### CI (no Mac needed)

`.github/workflows/ios.yml` runs on every push to `ios-support`, on `v*` tags and
on demand (Actions → *iOS build* → *Run workflow*). It uploads
`Nivio-<version>-unsigned.ipa` as the **Nivio-iOS-unsigned** artifact.

The workflow needs the `NIVIO_ENV` repository secret: the full contents of the
app's `.env`. It is bundled as an asset, the same as in the Android and desktop
builds.

### On a Mac

```bash
# once
rustup target add aarch64-apple-ios          # add aarch64-apple-ios-sim x86_64-apple-ios for the simulator
cp ../nivio_mobile/.env .env                 # gitignored

flutter pub get
dart run tool/patch_ios_plugins.dart         # after every pub get / upgrade
bash ../rqbit_ffi/ios/build_xcframework.sh   # add --sim for simulator slices
flutter build ios --release --no-codesign    # or: flutter run -d <iphone>
```

`pod install` (run by Flutter) also builds `rqbit_ffi.xcframework` if it is
missing and fetches the FFmpegKit frameworks (see the `Podfile`).

To make an unsigned IPA by hand:
`mkdir Payload && cp -R build/ios/iphoneos/Runner.app Payload/ && zip -qry Nivio.ipa Payload`.

## Installing

1. Download the artifact from the workflow run and unzip it to get the `.ipa`.
2. Install with **Sideloadly** or **AltStore/SideStore** using any Apple ID.
   Free Apple IDs get 7-day signatures (re-sign weekly); a paid developer
   account gets 1 year.
3. On the iPhone: Settings → General → VPN & Device Management → trust the
   profile. On iOS 16+ also turn on Settings → Privacy & Security →
   **Developer Mode**.

## Architecture decisions

| Decision | Why |
| --- | --- |
| Separate `nivio_ios` package instead of adding `ios/` to `nivio_mobile` | Dependency overrides are per app package. iOS needs the Firebase stubs (below); Android must keep the native SDKs. |
| Firebase via the REST stubs in `packages/stubs` (same as desktop) | The native iOS SDK needs a separately registered iOS app and `GoogleService-Info.plist`. Configured with the Android options it throws an uncatchable Objective-C exception at launch. The stubs use the same project, accounts and Firestore data, and skip the heavy Firestore/gRPC pods. |
| Google sign-in through the loopback OAuth flow in an in-app Safari sheet | The stub's flow (`DESKTOP_GOOGLE_CLIENT_ID`) waits on a `127.0.0.1` server. iOS suspends a backgrounded app, so the page opens in `SFSafariViewController`, which Google allows for OAuth. Nivio stays in the foreground and the sheet closes itself afterwards. |
| `cupertino_http` (NSURLSession) as the HTTP client | Cronet is Android-only. NSURLSession has Safari's TLS/HTTP2 fingerprint, which Cloudflare-fronted sources accept, unlike `dart:io`. |
| CocoaPods only (`enable-swift-package-manager: false`) | `media_kit_libs_ios_video` and `rqbit_ffi` have no Swift package. `permission_handler_apple`'s feature macros can only be set from the Podfile. |
| `rqbit_ffi` as a dynamic framework | A static library would need special strip/`-force_load` settings for `dlsym`. A framework with install name `@rpath/rqbit_ffi.framework/rqbit_ffi` loads with `DynamicLibrary.open` like on the other platforms. |

## Audit: plugins on iOS

Resolved versions match `nivio_mobile/pubspec.lock`. The only differences are
the Firebase stubs and `cupertino_http`.

| Plugin | iOS | What was needed |
| --- | --- | --- |
| media_kit / media_kit_video / media_kit_libs_ios_video | ✅ | OpenGL ES renderer has no background guard: patched (below). VideoToolbox hwdec added to the decoder modes. |
| ffmpeg_kit_flutter_new 4.5.1 (downloads) | ✅ | Its `prepare_command` never runs for Flutter's local pods. The Podfile runs the plugin's `setup_ios.sh`. Its frameworks (`libavcodec`, …) and media_kit's (`Avcodec`, …) are separate dynamic frameworks, so the two FFmpeg builds don't clash. |
| rqbit_ffi (torrents) | ✅ new | podspec, `build_xcframework.sh`, Dart loader. |
| flutter_foreground_task (via rqbit_ffi) | ⚠️ | Registers BGTask id `com.pravera.flutter_foreground_task.refresh` at **every launch**. iOS kills the app if that id is missing from `BGTaskSchedulerPermittedIdentifiers`, so it is listed in Info.plist. The service itself is Android-only. |
| workmanager | ✅ | Not scheduled anywhere (the new-episode check runs at launch), so no BGTask ids are needed. |
| flutter_local_notifications | ✅ | Init had no Darwin settings, so nothing ever showed on iOS: fixed. Progress notifications are skipped on iOS (each update would be a new banner). |
| permission_handler | ✅ | Only `PERMISSION_NOTIFICATIONS=1` is compiled in (Podfile). Storage permissions are Android-only. |
| app_links / url_launcher | ✅ | `nivio://` and `niviodiscord://` URL types; `FlutterDeepLinkingEnabled=false` like Android. |
| flutter_inappwebview, webview_flutter (YouTube) | ✅ | ATS allows arbitrary loads in web content. |
| share_plus | ✅ | iPad needs an anchor rect: `lib/core/share_origin.dart`. |
| device_screen_brightness | ⚠️ | iOS brightness is system-wide: saved before the first gesture, restored when the player closes and while backgrounded (`NivioPlugin.swift`). |
| flutter_volume_controller | ✅ | System volume HUD hidden (the player has its own). |
| flutter_secure_storage (Discord token) | ✅ | Keychain works for sideloaded apps. |
| connectivity_plus, package_info_plus, path_provider, shared_preferences, sqflite, wakelock_plus, file_picker, hive | ✅ | — |
| cronet_http | ❌ Android-only | Replaced by cupertino_http. |
| simple_pip_mode | ❌ Android-only | Calls are already Android-guarded. |
| window_manager, discord_rich_presence, dbus, flutter_inappwebview_linux, rhttp | Desktop-only | Calls are guarded. |
| shorebird_code_push | ✅ | No-op unless the IPA is built with `shorebird release ios`. |

## Audit: native channels (Android → iOS)

| Channel | Android | iOS (`ios/Runner/NivioPlugin.swift`) |
| --- | --- | --- |
| `com.nivio/device` | isTv, hdrInfo, resetWindowBrightness | isTv=false, hdrInfo (SDR), rememberBrightness / resetWindowBrightness |
| `com.nivio/media_session` | MediaSession | MPNowPlayingInfoCenter + MPRemoteCommandCenter: lock screen, Control Center, AirPods, ±N s skip, scrubbing, artwork |
| `com.nivio/watch_party_keepalive` | foreground service | → `com.nivio/background_keepalive` (UIApplication background task) |
| `com.nivio/background_keepalive` | — | new: also held by torrent streaming and downloads (`TorrentForegroundService`) |
| `com.nivio/gesture_exclusion`, `nivio/hdr_surface`, `puntito.simple_pip_mode` | Android-only | not needed (calls are Android-guarded) |

## Problems found and fixed

These would have crashed the app or broken a feature on iOS.

1. **Crash at launch: BGTask id not permitted** (flutter_foreground_task). Fixed in Info.plist.
2. **Crash at launch or no sign-in: Firebase** with Android options on iOS. Fixed with the REST stubs.
3. **Every network request broken:** `nivio_mobile` built a Cronet engine on iOS. `nivio_ios` uses NSURLSession.
4. **Killed when backgrounded during playback:** media_kit draws with OpenGL ES on a worker thread, and iOS kills apps that do GPU work in the background. Two fixes:
   - `tool/patch_ios_plugins.dart` stops rendering once the app resigns active.
   - `lib/services/ios_background_video.dart` switches the video track off (`vid=no`) while backgrounded, so sound keeps playing smoothly.
5. **Torrents unavailable:** `rqbit_ffi` had no iOS build or loader.
6. **Downloads failing on first use:** the FFmpegKit frameworks were never downloaded (no `prepare_command` for local pods).
7. **No notifications at all:** missing Darwin init settings.
8. **Phone left at the player's brightness** after watching.
9. **Share sheet failing on iPad** without an anchor rect.
10. **Deep links / OAuth callbacks** (AniList, MAL, Simkl, Discord) need the URL types.
11. **Plain-http streams, IPTV and the localhost proxy/servers** blocked by ATS.

## Known iOS limitations

- **Picture-in-picture:** not available. iOS PiP needs AVPlayer or an AVSampleBufferDisplayLayer; media_kit renders mpv into a Flutter texture.
- **HDR:** HDR video is tone-mapped to SDR (the Flutter texture is SDR). The HDR settings stay Android/desktop-only.
- **Background work:** there are no foreground services. Downloads, torrents and watch parties get iOS's background-task grace period (seconds to a few minutes) when Nivio leaves the foreground. Audio playback keeps the app alive while it plays (background audio mode).
- **In-app updates:** the update prompt opens the GitHub release page. Reinstall the new IPA with your sideloading tool, which keeps app data when the bundle id matches.
- **Cloudflare:** NSURLSession presents a Safari fingerprint, while some scrapers send Chrome-style `sec-ch-ua` headers (needed with Cronet). If a source works on Android but returns 403 on iOS, check its headers first.
- **Free Apple ID signing** expires after 7 days (a sideloading limit, not an app one).

## Device test checklist

- [ ] Launches; no crash on cold start, and the notifications prompt appears
- [ ] Google sign-in (in-app Safari sheet closes by itself) and guest sign-in; watchlist/history sync with Android
- [ ] Movies/TV/anime sources play (direct, HLS, through the HLS proxy); subtitles, audio tracks, decoder switch
- [ ] Home button / app switch during playback: sound continues, no crash, video comes back on return
- [ ] Lock screen + Control Center controls, AirPods double-tap, artwork
- [ ] Brightness gesture, then close the player: brightness goes back to what it was
- [ ] Volume gesture (no system HUD)
- [ ] Downloads (direct + HLS mux via FFmpegKit); file visible in Files → On My iPhone → Nivio; offline playback
- [ ] Nivio Torrents (rqbit): stream starts, seeks; Local Network prompt
- [ ] Watch party: create/join, share link (iPad: share popover), switching apps briefly keeps the party
- [ ] AniList / MAL / Simkl / Discord sign-in returns to the app
- [ ] IPTV (http playlists), YouTube trailers, iPad layout and rotation
