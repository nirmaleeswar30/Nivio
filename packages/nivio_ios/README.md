# Nivio for iOS (`nivio_ios`)

The iPhone / iPad app. Like `nivio_mobile` (Android) and `nivio_desktop`, it is
a thin app package around `nivio_core` (the root `lib/`).

- **Bundle id:** `com.nirmal.nivio` · **Minimum iOS:** 15.0 · iPhone + iPad
- **Distribution:** unsigned IPA from CI, signed at install time by a sideloading
  tool (AltStore, SideStore, Sideloadly, TrollStore, …).

## Building

### CI (no Mac needed)

Run `.github/workflows/ios.yml` manually from **Actions → iOS build → Run
workflow**. It uploads
`Nivio-<version>-unsigned.ipa` as the **Nivio-iOS-unsigned** artifact.

The workflow needs the `NIVIO_ENV` repository secret: the full contents of the
app's `.env`. It is bundled as an asset, the same as in the Android and desktop
builds.

### Shorebird IPA for sideloading

**Actions → iOS Shorebird release → Run workflow** creates a Shorebird
release baseline. Run it from `main` when ready to release. It uses Nivio's
existing Shorebird app ID and Xcode 26.3 on the macOS 15
runner.

1. Add a Shorebird CI token with access to the Nivio app as the
   `SHOREBIRD_TOKEN` repository secret.
2. The workflow uses the existing `NIVIO_ENV` repository secret, just like
   the regular iOS build. Flutter bundles it as the app's `.env` asset.
3. Use build number `1` for Nivio `2.2.7`. The workflow looks up the exact
   version and build number in Shorebird. For `2.2.7+1`, it picks the Flutter
   revision already used by Android, Windows and Linux. A release version
   that is new to Shorebird uses the CLI's default Flutter. The unsigned
   IPA is uploaded as an Actions artifact. Attach it to a GitHub Release
   separately when ready to distribute it.

Keep the release artifact's IPA, checksum, dependency lockfiles and
`toolchain.txt` together. Sign the same built app when sideloading and
preserve its version and build number. For patches, use the exact
Shorebird release version (for example, `2.2.7+1`), app config,
Xcode and CocoaPods versions from that build. Changes to native code or
bundled assets need a new IPA.

### SideStore and AltStore Classic source

The website serves `https://nivio.nirmaleeswar.dev/altstore.json` from
`landing/api/ios-source.js`. After approval, attach the tested
`Nivio-<version>+<build>-shorebird-unsigned.ipa` to a public GitHub Release.
The website and source pick it up automatically. Check the source against
the built IPA's bundle ID, version, minimum iOS version and permissions
before a release. If you change the minimum iOS version or add permissions,
update the source metadata too.

Users add the Nivio source once and can then find the app in Browse. For a
listing in SideStore's built-in Community Source, follow the
[submission guidelines](https://github.com/SideStore/Community-Source)
after the public IPA and iOS screenshots are available.

### On a Mac

Needs **Xcode 26** or newer: current plugins (e.g. connectivity_plus 7.3) use
iOS 26 SDK APIs.

```bash
# once
rustup target add aarch64-apple-ios          # add aarch64-apple-ios-sim x86_64-apple-ios for the simulator
cp ../nivio_mobile/.env .env                 # gitignored

flutter pub get
dart run tool/patch_ios_plugins.dart         # after every pub get / upgrade
bash ../rqbit_ffi/ios/build_xcframework.sh   # add --sim for simulator slices
flutter build ios --release --no-codesign    # or: flutter run -d <iphone>
```

`pod install` (run by Flutter) also builds whatever is missing (see the
`Podfile`):
- `RqbitEngine.xcframework`;
- `Mpv.xcframework`, from `third_party/media_kit_libs_ios_video/ios/build_mpv_framework.sh`;
- `CurlImpersonate.xcframework`, from `third_party/nivio_curl/ios/build_curl_framework.sh`;
- the FFmpegKit frameworks.

`Mpv` and `CurlImpersonate` are built for devices only (arm64), so the app does
not build for the simulator.

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
| `nivio_curl` (libcurl-impersonate) as the shared HTTP client | Cronet is Android-only, and Google's last prebuilt iOS Cronet is Chromium 108 (2022). [curl-impersonate](https://github.com/lexiforest/curl-impersonate) (MIT) reproduces Chrome's TLS and HTTP/2 fingerprint (target `chrome131_android`), so requests look like they do from Cronet. It sends only the request's own headers, like Cronet. Each request runs in a short-lived isolate and the body is streamed. `cupertino_http` (NSURLSession, Safari fingerprint) is the fallback if the framework can't load. |
| libmpv from [edde746/mpv-build](https://github.com/edde746/mpv-build) (Plezy's, GPL-3.0) | Its `vo=avfoundation` output hands VideoToolbox frames to an `AVSampleBufferDisplayLayer`. iOS then shows HDR10 / HLG / Dolby Vision itself (FFmpeg carries Dolby Vision patches, profile 7 → 8.1 included), and the same layer is the picture-in-picture source. No OpenGL is involved, which iOS forbids in the background. Its static libraries are linked into one `Mpv.framework` that exports only `mpv_*`, so its FFmpeg can't clash with FFmpegKit's. It replaces `media_kit_libs_ios_video` through a `dependency_overrides` package with the same name. |
| media_kit's controller kept, on its software path | The player UI is built around `VideoController`. On iOS it is created with `vo=avfoundation` and `enableHardwareAcceleration: false`, so it never creates an OpenGL context. The picture comes from `IosVideoSurface` (a platform view showing the player's layer), not the texture. |
| CocoaPods only (`enable-swift-package-manager: false`) | `media_kit_libs_ios_video` and `rqbit_ffi` have no Swift package. `permission_handler_apple`'s feature macros can only be set from the Podfile. |
| `rqbit_ffi`'s Rust library as a dynamic framework (`RqbitEngine.framework`) | A static library would need special strip/`-force_load` settings for `dlsym`. A framework loads with `DynamicLibrary.open` like on the other platforms. It isn't named `rqbit_ffi` because the plugin pod already builds a `rqbit_ffi.framework`. |

## Audit: plugins on iOS

Resolved versions match `nivio_mobile/pubspec.lock`. The differences are the
Firebase stubs, `cupertino_http`, `nivio_curl` and the replaced
`media_kit_libs_ios_video`.

| Plugin | iOS | What was needed |
| --- | --- | --- |
| media_kit / media_kit_video | ✅ | libmpv replaced by mpv-build's, video through `vo=avfoundation` (above). VideoToolbox hwdec added to the decoder modes. media_kit's OpenGL renderer is no longer used on iOS. It is still patched (`tool/patch_ios_plugins.dart`) so it can never draw in the background. |
| media_kit_libs_ios_video | 🔁 replaced | `third_party/media_kit_libs_ios_video`: mpv-build's libmpv as `Mpv.framework`. |
| ffmpeg_kit_flutter_new 4.5.1 (downloads) | ✅ | Its `prepare_command` never runs for Flutter's local pods. The Podfile runs the plugin's `setup_ios.sh`. Its dynamic `libav*` frameworks and mpv's FFmpeg (private inside `Mpv.framework`) don't clash. |
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
| cronet_http | ❌ Android-only | Replaced by `nivio_curl` (fallback: cupertino_http). |
| simple_pip_mode | ❌ Android-only | iOS PiP is `AVPictureInPictureController` on the player's display layer (`NivioVideoPlugin.swift`). |
| window_manager, discord_rich_presence, dbus, flutter_inappwebview_linux, rhttp | Desktop-only | Calls are guarded. |
| shorebird_code_push | ✅ | No-op unless the IPA is built with `shorebird release ios`. |

## Audit: native channels (Android → iOS)

| Channel | Android | iOS (`ios/Runner/NivioPlugin.swift`) |
| --- | --- | --- |
| `com.nivio/device` | isTv, hdrInfo, resetWindowBrightness | isTv=false, hdrInfo (HDR modes, EDR headroom), rememberBrightness / resetWindowBrightness |
| `com.nivio/media_session` | MediaSession | MPNowPlayingInfoCenter + MPRemoteCommandCenter: lock screen, Control Center, AirPods, ±N s skip, scrubbing, artwork |
| `com.nivio/watch_party_keepalive` | foreground service | → `com.nivio/background_keepalive` (UIApplication background task) |
| `com.nivio/background_keepalive` | — | new: also held by torrent streaming and downloads (`TorrentForegroundService`) |
| `nivio/hdr_surface` + `puntito.simple_pip_mode` | HDR SurfaceView, PiP | → `com.nivio/ios_video` + platform view `nivio/ios_video` (`NivioVideoPlugin.swift`): per-player display layer, HDR switch, PiP (automatic on leaving the app, play/pause/skip, subtitles composited while in PiP) |
| `com.nivio/gesture_exclusion` | Android-only | not needed (calls are Android-guarded) |

## Problems found and fixed

These would have crashed the app or broken a feature on iOS.

1. **Crash at launch: BGTask id not permitted** (flutter_foreground_task). Fixed in Info.plist.
2. **Crash at launch or no sign-in: Firebase** with Android options on iOS. Fixed with the REST stubs.
3. **Every network request broken:** `nivio_mobile` built a Cronet engine on iOS. `nivio_ios` uses libcurl-impersonate.
4. **Killed when backgrounded during playback:** media_kit draws with OpenGL ES on a worker thread, and iOS kills apps that do GPU work in the background. Fixes:
   - Video now goes through `vo=avfoundation`, which uses no OpenGL.
   - `tool/patch_ios_plugins.dart` also stops media_kit's renderer once the app resigns active.
   - Without PiP, `lib/services/ios_background_video.dart` switches the video track off (`vid=no`) while backgrounded, so only sound plays. iOS stops hardware decoding for background apps anyway.
5. **Torrents unavailable:** `rqbit_ffi` had no iOS build or loader.
6. **Downloads failing on first use:** the FFmpegKit frameworks were never downloaded (no `prepare_command` for local pods).
7. **No notifications at all:** missing Darwin init settings.
8. **Phone left at the player's brightness** after watching.
9. **Share sheet failing on iPad** without an anchor rect.
10. **Deep links / OAuth callbacks** (AniList, MAL, Simkl, Discord) need the URL types.
11. **Plain-http streams, IPTV and the localhost proxy/servers** blocked by ATS.
12. **Localhost servers dead after a long background:** iOS can reclaim a
    suspended app's listening sockets (Apple TN2277). The HLS proxy and the
    local stream server now check themselves on resume and rebind on the same
    port; the torrent engine restarts.

## Known iOS limitations

- **Picture-in-picture** needs iOS 15+. It starts by itself when you leave Nivio while a video plays ("PiP on Lost Visibility", like Android). No PiP button was added.
- **HDR / Dolby Vision** depend on the iPhone: iOS shows whatever its screen supports (`AVPlayer.availableHDRModes`) and tone-maps the rest. Only the "HDR Output" switch is offered; the tone-mapping and surface choices are Android-only. Extended range (EDR) is switched on only while an HDR video plays with HDR Output on (iOS 17+; iOS 15–16 use the system default).
- **Background work:** there are no foreground services. Downloads, torrents and watch parties get iOS's background-task grace period (usually about 30 seconds) when Nivio leaves the foreground. Audio playback keeps the app alive while it plays (background audio mode).
- **In-app updates:** the update prompt opens the GitHub release page. Reinstall the new IPA with your sideloading tool, which keeps app data when the bundle id matches.
- **Network clients:** only `NetworkClientFactory.createClient()` users (Miruro, the HLS proxy, seek thumbnails) go through curl-impersonate, as only they use Cronet on Android. Scrapers built on Dio use `dart:io` on both platforms. Each curl request opens its own connection (no keep-alive).
- **Free Apple ID signing** expires after 7 days (a sideloading limit, not an app one).

## Device test checklist

- [ ] Launches; no crash on cold start, and the notifications prompt appears
- [ ] Google sign-in (in-app Safari sheet closes by itself) and guest sign-in; watchlist/history sync with Android
- [ ] Movies/TV/anime sources play (direct, HLS, through the HLS proxy); subtitles, audio tracks, decoder switch
- [ ] Home button / app switch during playback: PiP window appears (setting on), play/pause/±skip work in it, subtitles show; returning to Nivio puts the video back inline
- [ ] Same with "PiP on Lost Visibility" off: sound continues, no crash, video comes back on return
- [ ] HDR10, HLG and Dolby Vision (profile 5 and 8) files on an HDR iPhone look HDR; HDR Output off tone-maps them (iOS 17+)
- [ ] Mini player shows the video, and back to the full player
- [ ] Miruro (curl-impersonate) loads; check the debug log for `curl:` errors
- [ ] Lock screen + Control Center controls, AirPods double-tap, artwork
- [ ] Brightness gesture, then close the player: brightness goes back to what it was
- [ ] Volume gesture (no system HUD)
- [ ] Downloads (direct + HLS mux via FFmpegKit); file visible in Files → On My iPhone → Nivio; offline playback
- [ ] Nivio Torrents (rqbit): stream starts, seeks; Local Network prompt
- [ ] Watch party: create/join, share link (iPad: share popover), switching apps briefly keeps the party
- [ ] AniList / MAL / Simkl / Discord sign-in returns to the app
- [ ] IPTV (http playlists), YouTube trailers, iPad layout and rotation

## Testing HDR / Dolby Vision

1. IPTV tab → add playlist → M3U link:
   `https://raw.githubusercontent.com/nirmaleeswar30/Nivio/main/packages/nivio_ios/test-media/hdr-test.m3u`
   (Jellyfin's public test clips: SDR control, HDR10, Dolby Vision P5 / P8.1 / P8.4.)
2. Play a clip, open the player settings → **Stats for Nerds**. Expected:
   - VO Driver `avfoundation`, Hardware Dec `videotoolbox`.
   - Source Format names the clip's format (e.g. `Dolby Vision P5`).
   - Display Output `HDR (HDR10)` / `Dolby Vision (iOS)` on an HDR screen with HDR Output on; otherwise `SDR (tone-mapped by iOS)`.
   - Screen shows whether iOS reports the screen as HDR and its peak brightness.
3. Dolby Vision P5 is the telling one: its picture has no SDR/HDR10 fallback, so wrong handling shows purple/green colours. Correct colours mean Dolby Vision is being processed.
4. On an SDR screen (e.g. iPhone SE 2nd gen, whatever panel is fitted) HDR files should play with normal, correctly tone-mapped colours; true HDR brightness needs an HDR iPhone (iPhone X/XS/11 Pro, or iPhone 12 and later except SE models).
