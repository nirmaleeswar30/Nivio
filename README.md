<div align="center">
  <img src="assets/images/appicon.png" alt="Nivio Logo" width="330" />

  **A beautiful, all-in-one streaming application for Movies, TV Shows, Anime, and Live IPTV, featuring real-time Watch Parties and offline downloads.**

  [![Flutter](https://img.shields.io/badge/Built_with-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
  [![Rust](https://img.shields.io/badge/P2P_Engine-Rust-DEA584?style=for-the-badge&logo=rust&logoColor=white)](https://www.rust-lang.org/)
  [![MPV](https://img.shields.io/badge/Playback-MPV%20%2F%20libmpv-8C1D40?style=for-the-badge)](https://mpv.io/)
  [![Supabase](https://img.shields.io/badge/Realtime-Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com/)

  [![Firebase](https://img.shields.io/badge/Powered_by-Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com/)
  [![TMDB](https://img.shields.io/badge/Metadata-TMDB-01B4E4?style=for-the-badge&logo=themoviedatabase&logoColor=white)](https://www.themoviedb.org/)
  [![AniList](https://img.shields.io/badge/Anime-AniList-02A9FF?style=for-the-badge&logo=anilist&logoColor=white)](https://anilist.co/)
  [![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20Android%20TV%20%7C%20Windows%20%7C%20Linux-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com)
  [![HDR](https://img.shields.io/badge/Android-True%20HDR%20%7C%20Dolby%20Vision-000000?style=for-the-badge&logo=dolby&logoColor=white)](#hdr)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

</div>

---

<div align="center">

[Features](#features) • [HDR & Dolby Vision](#hdr) • [Screenshots](#screenshots) • [Docs](https://nivio.nirmaleeswar.dev/docs/) • [Roadmap](#roadmap) • [Installation](#installation) • [Build from Source](#build-from-source) • [Contributing](#contributing)

</div>

<br>

> [!WARNING]
> Nivio is only available on the platforms listed in this README. It is not on the Play Store or any other site claiming to offer official releases. If we ever publish to additional platforms, it will be announced here. Please avoid unofficial or modified builds for your safety.

<p align="center">
  <a href="https://github.com/nirmaleeswar30/Nivio/releases/latest">
    <img src="assets/images/badge-github.png" alt="Get it on GitHub" height="48" />
  </a>
  &nbsp;&nbsp;
  <a href="https://apps.obtainium.imranr.dev/redirect?r=obtainium://app/%7B%22id%22%3A%22com.nirmal.nivio%22%2C%22url%22%3A%22https%3A%2F%2Fgithub.com%2Fnirmaleeswar30%2FNivio%22%2C%22author%22%3A%22nirmaleeswar30%22%2C%22name%22%3A%22Nivio%22%7D">
    <img src="assets/images/badge-obtainium.png" alt="Get it on Obtainium" height="48" />
  </a>
</p>

---

## ⚠️ Disclaimer - DMCA

> [!IMPORTANT]
> **Nivio does not host any media content.**  
> This application acts strictly as an aggregator, scraping metadata and streaming links from publicly available third-party sources on the internet. The developers of Nivio are not affiliated with these sources. You are solely responsible for complying with your local laws, platform terms of service, and digital content rights policies when using this application.

---

<a id="screenshots"></a>

## 📸 Screenshots


<div align="center">

  <h3>📱 Mobile Edition</h3>

  <table border="0">
    <tr>
      <td align="center"><img src="assets/images/home-screen.jpg" alt="Home Screen" width="200" /><br><b>Home Screen</b></td>
      <td align="center"><img src="assets/images/media-screen.jpg" alt="Media Details" width="200" /><br><b>Media Details</b></td>
      <td align="center"><img src="assets/images/provider-screen.jpg" alt="Provider Screen" width="200" /><br><b>Select Provider</b></td>
      <td align="center"><img src="assets/images/watch-party.jpg" alt="Watch Party" width="200" /><br><b>Watch Party</b></td>
    </tr>
    <tr>
      <td align="center"><img src="assets/images/live-tv-screen.jpg" alt="Live TV" width="200" /><br><b>Live TV</b></td>
      <td align="center"><img src="assets/images/sports-tv-screen.jpg" alt="Sports TV" width="200" /><br><b>Sports TV</b></td>
      <td align="center"><img src="assets/images/library-screen.jpg" alt="Library" width="200" /><br><b>Your Library</b></td>
      <td align="center"><img src="assets/images/settings-screen.jpg" alt="Settings" width="200" /><br><b>Settings</b></td>
    </tr>
  </table>
  <br>
  <table border="0">
    <tr>
      <td align="center"><img src="assets/images/player-direct.jpg" alt="Video Player" width="600" /><br><b>Cinema Player</b></td>
    </tr>
  </table>

  <br><br>

  <h3>🖥️ Desktop Edition</h3>

  <table border="0">
    <tr>
      <td align="center"><img src="assets/images/homescreen-desktop.png" alt="Desktop Home Dashboard" width="410" /><br><b>Home Dashboard</b></td>
      <td align="center"><img src="assets/images/provider-screen.png" alt="Desktop Provider Selection" width="410" /><br><b>Stream Providers</b></td>
    </tr>
    <tr>
      <td align="center"><img src="assets/images/media-detail-screen-desktop.png" alt="Desktop Media Details" width="410" /><br><b>Media Details &amp; Cast</b></td>
      <td align="center"><img src="assets/images/settings-screen-desktop.png" alt="Desktop Settings" width="410" /><br><b>Settings &amp; Preferences</b></td>
    </tr>
    <tr>
      <td align="center"><img src="assets/images/player-direct.jpg" alt="Cinema Player Engine" width="410" /><br><b>Cinema Player Engine</b></td>
      <td align="center"><img src="assets/images/player-torrent.jpg" alt="BitTorrent Streaming Engine" width="410" /><br><b>BitTorrent Streaming Engine</b></td>
    </tr>
  </table>

</div>

---

## ✨ Highlights

* **🎉 Real-Time Watch Parties** — Stream together with friends in perfect sync, with shared playback controls.
* **🧲 Instant Torrent Streaming** — Watch magnet links directly on the fly without waiting for downloads, powered by an embedded Rust engine.
* **🎌 Dedicated Anime Hub** — Fast multi-source scraping, one-tap skip intro, filler episode tagging, and AniList sync.
* **⚽ Live Sports & IPTV** — Live sports match streams, schedules, and global TV channels.
* **🌈 True HDR & Dolby Vision on Android** — Real HDR10 / HLG output and hardware Dolby Vision on supported phones, plus HDR → SDR tone mapping everywhere else. [More below](#hdr).
* **📺 Android TV & Google TV** — A full TV layout driven by the remote's D-pad, from browsing to the player.
* **⚡ Native MPV Playback** — Hardware-accelerated decoding (HW+ / HW / SW), 200% software volume boost, and Picture-in-Picture.
* **✨ Ambient Mode** — A soft glow fills the black bars around the video, with adjustable blur and edges that fade into it.
* **🧠 Smart Recommendations** — Private, local recommendations shaped around what you actually watch.

---

<a id="hdr"></a>

## 🌈 True HDR & Dolby Vision (Android)

As far as we know, **Nivio is the only Flutter app that plays real HDR and hardware Dolby Vision.** Flutter draws everything (video included) as SDR, so HDR video normally comes out flat and washed out. Nivio gets around it by giving the video its own Android surface and rendering it with a custom-built mpv:

* **True HDR10 & HLG** — On an HDR screen, the panel switches into HDR mode for HDR videos, rendered by mpv's Vulkan `gpu-next` renderer and tagged with the video's real colour space.
* **Hardware Dolby Vision** — Our own [mpvlibAndroid build](https://github.com/nirmaleeswar30/mpvlibAndroid/releases/tag/v1.1.4-dv) patches FFmpeg to decode on the phone's Dolby Vision decoder and send it straight to the screen, so the display's own Dolby Vision engine kicks in (profiles 5 and 8 on supported phones). Nivio can also convert between Dolby Vision and HDR10 on the fly.
* **Tone mapping for SDR screens** — No HDR screen, or HDR output turned off? HDR and BT.2020 video is tone-mapped to SDR instead: either mpv's own per-scene tone mapping or the [hdr-toys](https://github.com/natural-harmonia-gropius/hdr-toys) shader pipeline (PQ, HLG and BT.2020 profiles, picked from the video), the same approach as [mpvRx](https://github.com/Riteshp2001/mpvRx).
* **You stay in control** — An HDR tile in the player shows exactly what's happening ("True HDR", "True DV", "Tone mapped") and lets you switch HDR output, the tone-mapping mode and the surface backend, also available under Settings → Playback.

> [!NOTE]
> Dolby Vision needs a phone with a Dolby Vision decoder (most recent Snapdragon flagships). Blu-ray remuxes use Dolby Vision profile 7, which phones don't decode; those play their HDR10 layer. HDR & Dolby Vision on Windows and Linux are on the [roadmap](#roadmap).

---

## 💖 Support Nivio

Nivio is free and open source. If it makes your day a little better, consider supporting development — it keeps the project alive and actively maintained.

<div align="center">
  <a href="https://github.com/sponsors/nirmaleeswar30">
    <img src="https://img.shields.io/badge/GITHUB%20SPONSORS-%E2%99%A5-ea4aaa?style=for-the-badge&logo=github&color=ea4aaa&labelColor=30363d" alt="GitHub Sponsors" />
  </a>

  <br><br>
  <b>— or scan to pay via UPI —</b>
  <br><br>

  <img src="assets/images/upi.jpeg" alt="Slice UPI QR" width="280" />
</div>

---

<a id="features"></a>

## 🚀 Features

* **Two-Way Scrobbling & Tracking** (Simkl, AniList, MyAnimeList)
* **Cloud Sync & Watch History** (Google Sign-In / Firebase)
* **Offline Downloads**
* **Curated Release Shelves** (Theatrical, OTT Premiere & Weekly Anime)
* **Custom Subtitles & Persistence** (Local .srt/.vtt or remote URLs)
* **Native Desktop, Mobile & TV Apps** (Windows, Linux, Android, Android TV / Google TV)
* **True HDR, Dolby Vision & Tone Mapping** (Android, [details](#hdr))
* **Live TV & IPTV** (M3U playlists and Xtream Codes, including Xtream movies & series)
* **Seek-Bar Thumbnail Previews** (for sources that provide sprite sheets)
* **Discord Rich Presence** (desktop and Android)
* **Background Episode Alerts**
* **Over-the-Air App Updates** (Shorebird CodePush) and one-click desktop updates

### 📺 Android TV

Nivio runs on Android TV and Google TV with a layout made for the big screen: a side navigation rail, poster grids and wide detail pages, all driven by the remote's D-pad with clear focus highlights. The player is remote-friendly too: arrows to seek, OK to show the controls, Back to step out. Install the same APK as on phones (sideload it, or use a downloader app); Nivio detects the TV and switches layout on its own.

---

## 🛠️ Tech Stack

*   **Architecture**: Modular Monorepo (`nivio_core`, `nivio_desktop`, `nivio_mobile`, `rqbit_ffi`)
*   **UI & Framework**: Flutter (Dart `^3.10.0`)
*   **Native P2P Engine**: Rust (`rqbit_ffi` / C-FFI bindings)
*   **Media Playback**: `media_kit` (high-performance playback engine utilizing `libmpv` / MPV for hardware-accelerated rendering and extensive format decoding). On Android, a custom [mpvlibAndroid](https://github.com/nirmaleeswar30/mpvlibAndroid) build (mpv 0.41, libplacebo, Vulkan, Dolby Vision MediaCodec) powers HDR and Dolby Vision.
*   **State Management**: Riverpod (`flutter_riverpod ^2.6.1`)
*   **Networking**: Dio & Google Cronet HTTP engine
*   **Routing & Navigation**: GoRouter (`go_router ^17.3.0`)
*   **Backend & Authentication**: Firebase (Firebase Auth, Cloud Firestore)
*   **Realtime Sockets**: Supabase (WebSockets for synchronized Watch Parties)
*   **Local Storage**: Hive & SharedPreferences
*   **Social & Presence**: Discord Rich Presence (RPC)
*   **Metadata & Tracking APIs**: TMDB, AniList (GraphQL), Simkl, MyAnimeList
*   **Background Tasks**: WorkManager & Local Notifications
*   **Over-the-Air Updates**: Shorebird CodePush

---

<a id="installation"></a>

## ⚙️ Installation & Setup

### 1. Prerequisites
*   Flutter SDK (`^3.10.0`)
*   A free [Firebase](https://firebase.google.com/) Project
*   A free [TMDB](https://www.themoviedb.org/) API Key
*   *(Optional)* A free [Supabase](https://supabase.com/) Project for Watch Parties

### 2. Clone & Install
```bash
git clone https://github.com/yourusername/nivio.git
cd nivio
flutter pub get
```

### 3. Firebase Setup (Required)
You must connect the app to your own Firebase project for Auth and Database syncing.
1. Create a Firebase project.
2. Enable **Authentication** (Google & Anonymous).
3. Enable **Cloud Firestore**.
4. Use the FlutterFire CLI to configure your app:
   ```bash
   flutterfire configure
   ```
   *(This will generate the required `lib/firebase_options.dart` and native config files).*

### 4. TMDB API Key (Required)
Open `lib/core/constants.dart` and replace the `tmdbApiKey` variable with your own v3 API key:
```dart
const String tmdbApiKey = 'YOUR_TMDB_API_KEY_HERE';
```

### 5. Environment Variables Setup (Optional)
If you want to use the Watch Party feature, custom deep link sharing, or GitHub sponsors, create a `.env` file in the root of the project:
```env
# Supabase Configuration for Watch Parties
SUPABASE_URL=your_supabase_project_url
SUPABASE_ANON_KEY=your_supabase_anon_key

# Deep Link Configuration (URL where redirect.html is hosted)
SHARE_REDIRECT_URL=https://yourusername.github.io/Nivio/redirect.html

# Sponsor Configuration
GITHUB_SPONSOR_URL=https://github.com/sponsors/yourusername
```
*(If you skip this step, the app will still compile and run, but these features will either be disabled or use fallback placeholders).*

### 6. Run the App
```bash
flutter run
```

---

<a id="build-from-source"></a>

## 📦 Building for Release

### 📱 Android (Universal & Architecture Split APKs)

Use the automated builder scripts to compile either a Shorebird OTA release or a standard Flutter release, then bundle Universal (`universal.apk`) and architecture-specific split APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`):

**Using PowerShell (Windows):**
```powershell
# Interactive prompt (Shorebird Release vs Normal Release vs Skip Build):
.\build_universal_apk.ps1

# Or specify build type via parameters:
.\build_universal_apk.ps1 -BuildType shorebird
.\build_universal_apk.ps1 -BuildType normal
.\build_universal_apk.ps1 -SkipBuild
```

**Using Bash (Linux / macOS / WSL):**
```bash
./build_universal_apk.sh
# Or with flags: ./build_universal_apk.sh --shorebird | --normal | --skip-build
```

### 🖥️ Windows Desktop (installer)

> [!IMPORTANT]
> The Windows app **must** be built from `packages/nivio_desktop`, **not** the repo root. The desktop package swaps `google_sign_in` / `firebase_*` for local stubs (browser‑OAuth loopback login that works on Windows); the root build uses the real `google_sign_in`, which has no Windows implementation and fails at runtime with `UnimplementedError`.

#### One-Step Release & Installer Packaging
The packaging scripts automatically read the application version from the root `pubspec.yaml`, compile the desktop release, and produce the Inno Setup installer.

**Using PowerShell (recommended on Windows):**
```powershell
# Interactive prompt (choose between Normal Release or Shorebird OTA Release):
.\scripts\package_windows_installer.ps1

# Or specify build type directly via parameters:
.\scripts\package_windows_installer.ps1 -BuildType normal
.\scripts\package_windows_installer.ps1 -BuildType shorebird

# Or package existing build without recompiling:
.\scripts\package_windows_installer.ps1 -SkipBuild
```

**Using Bash (Git Bash / WSL):**
```bash
./scripts/build_windows_installer.sh
```

The resulting setup wizard executable is saved to:
`packages/nivio_desktop/dist/windows/Nivio-Setup-<version>.exe`

#### 🌐 Windows WebView2 & Permissions Architecture
Trailer players and hover card preview players on Windows utilize Microsoft Edge WebView2 via `flutter_inappwebview`:
* **User Data Isolation:** Nivio configures `WebViewEnvironment` with `userDataFolder` pointing to `%LOCALAPPDATA%\Nivio\webview2_data`.
* **Standard User Compatibility:** Because Edge WebView2 defaults to writing next to the executable, apps installed in `C:\Program Files` would otherwise trigger permission errors (*"We couldn't create the data directory"* / `E_ACCESSDENIED`). Isolating data in `%LOCALAPPDATA%` guarantees full read/write functionality for standard user accounts without requiring administrative elevation.
* **Prerequisites:** Windows 10 and 11 come with Edge WebView2 pre-installed. If running on minimal or LTSC Windows editions, ensure the [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) is installed.

---

<a id="roadmap"></a>

## 🗺️ Roadmap

- [x] True HDR10 / HLG output on Android
- [x] Hardware Dolby Vision on Android (profiles 5 & 8)
- [x] HDR → SDR tone mapping (Standard & hdr-toys) on Android
- [x] Android TV & Google TV support
- [ ] **HDR on Windows** — render mpv (Direct3D 11, `gpu-next`) into its own native window under Flutter's controls, with a newer libmpv. True HDR10 / HLG on HDR monitors, better tone mapping and correct Dolby Vision colours on SDR screens.
- [ ] **HDR on Linux** — the same native-window approach on Wayland compositors with HDR support (KDE Plasma 6, recent GNOME).
- [ ] **Dolby Vision profile 7** — convert Blu-ray profile 7 to 8.1 on the fly (as Kodi does) so phones can play it in Dolby Vision.

Have an idea? [Open a feature request](https://github.com/nirmaleeswar30/Nivio/issues/new/choose).

---

<a id="contributing"></a>

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! 
1. Fork the project.
2. Create your feature branch (`git checkout -b feature/AmazingFeature`).
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

Please make sure you run `flutter analyze` before opening a PR to ensure code quality!

---

## ❤️ Acknowledgements

* **[Hayase](https://github.com/hayase-app)** — Inspiration for the P2P torrent streaming experience.

---

## ⭐ Star History

<a href="https://star-history.com/#nirmaleeswar30/Nivio&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=nirmaleeswar30/Nivio&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=nirmaleeswar30/Nivio&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=nirmaleeswar30/Nivio&type=Date" />
 </picture>
</a>

---

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.
