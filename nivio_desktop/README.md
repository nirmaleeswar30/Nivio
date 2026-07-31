<div align="center">
  <img src="assets/images/app-icon.png" alt="Nivio Desktop Logo" width="150" />

  **A Linux desktop streaming application for Movies, TV Shows, Anime, and Live IPTV, with watch history, desktop playback, built-in providers, and cross-distro packages.**

  [![Flutter](https://img.shields.io/badge/Built_with-Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
  [![Linux](https://img.shields.io/badge/Desktop-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://www.linux.org/)
  [![MPV](https://img.shields.io/badge/Playback-libmpv-691F74?style=for-the-badge)](https://mpv.io/)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

</div>

---

## Screenshots

<div align="center">
  <table border="0">
    <tr>
      <td align="center"><img src="assets/screenshots/desktop-home.png" alt="Desktop Home" /><br><b>Home</b></td>
      <td align="center"><img src="assets/screenshots/desktop-home3.png" alt="Desktop Hover Preview" /><br><b>Hover Preview</b></td>
      <td align="center"><img src="assets/screenshots/desktop-home-mini.png" alt="Desktop Continue Watching and Mini Player" /><br><b>Continue Watching</b></td>
    </tr>
  </table>
  <table border="0">
    <tr>
      <td align="center"><img src="assets/screenshots/desktop-details.png" alt="Desktop Details" /><br><b>Details</b></td>
      <td align="center"><img src="assets/screenshots/desktop-player1.png" alt="Desktop Player Controls" /><br><b>Player</b></td>
      <td align="center"><img src="assets/screenshots/desktop-live-tv.png" alt="Desktop Live TV" /><br><b>Live TV</b></td>
    </tr>
  </table>
  <table border="0">
    <tr>
      <td align="center"><img src="assets/screenshots/desktop-library.png" alt="Desktop Library" /><br><b>Library</b></td>
      <td align="center"><img src="assets/screenshots/desktop-watchtogether.png" alt="Desktop Watch Party" /><br><b>Watch Party</b></td>
    </tr>
  </table>
</div>

---

## Features

* **Desktop-first Linux UI**: Sidebar navigation, wide-screen layouts, hover states, keyboard-aware controls, and Linux window integration.
* **Unified Discovery**: Browse movies, TV shows, anime, providers, and details from a desktop-focused interface.
* **Hover Preview Cards**: Inspect media quickly from poster grids with preview artwork, metadata, and instant actions.
* **Continue Watching**: Resume movies and episodes from saved playback progress.
* **Mini Player**: Keep playback visible while browsing other desktop sections.
* **High-performance Playback**: Uses `media_kit` with `libmpv` for native Linux video playback.
* **Skip Intro / Outro Support**: Uses skip-time metadata where available to jump over intros and ending segments.
* **Provider Fallbacks**: Resolves streams through multiple providers and falls back when a source fails.
* **Custom Subtitles**: Load subtitle files or remote subtitle URLs and keep playback preferences.
* **Embedded Web Fallback**: Uses WebKitGTK when a provider requires embedded playback.
* **Live IPTV**: Supports custom M3U/M3U8 playlists, favorites, source filters, and built-in live TV providers.
* **Watch History & Library**: Continue watching, local history, watchlist, and desktop persistence.
* **Watch Parties**: Supabase-backed session support for synced watch rooms.
* **Profile & Cloud Sync**: Sync watch activity and account data when cloud sync is configured.
* **Desktop Settings**: Playback, subtitle appearance, downloads, content feed, app updates, and account controls.
* **Linux Packaging**: AppImage, `.deb`, Arch package, and prepared Flatpak manifest.

---

## Downloads

Linux desktop builds are available from:

https://github.com/NithishSaravananRss/Nivio/releases/tag/desktop-v1.0.0

Normal users should download one of the package files below, not the source code
archives.

| System | File | Install |
| --- | --- | --- |
| Portable Linux | `Nivio-x86_64.AppImage` | `chmod +x Nivio-x86_64.AppImage && ./Nivio-x86_64.AppImage` |
| Ubuntu, Debian, Linux Mint, Kali, Pop!_OS, Zorin | `nivio-desktop_1.0.0_amd64.deb` | `sudo apt install ./nivio-desktop_1.0.0_amd64.deb` |
| Arch, Omarchy, Manjaro, EndeavourOS | `nivio-desktop-1.0.0-1-x86_64.pkg.tar.zst` | `sudo pacman -U ./nivio-desktop-1.0.0-1-x86_64.pkg.tar.zst` |

---

## Tech Stack

* **Frontend**: Flutter desktop
* **Language**: Dart
* **State Management**: Riverpod
* **Routing**: GoRouter
* **Playback**: `media_kit`, `media_kit_video`, `libmpv`
* **Embedded Web**: WebKitGTK through `webview_all_linux`
* **Local Storage**: Hive, SharedPreferences
* **Realtime**: Supabase for watch-party sessions
* **Packaging**: AppImage, Debian package, Arch package, Flatpak manifest

---

## Build From Source

Install Flutter with Linux desktop support, then run:

```bash
flutter pub get
scripts/build_linux_release.sh
```

Run the release bundle:

```bash
build/linux/x64/release/bundle/nivio_desktop
```

Packaging scripts:

```bash
scripts/package_appimage.sh
scripts/package_deb.sh
scripts/package_arch.sh
```

Flatpak packaging is prepared in `packaging/flatpak/`, but it is not included
in the first desktop release.

---

## Acknowledgements

Thank you to **Nirmaleeswar**, who started the Android version that Nivio
Desktop builds from.

Thank you to the creators of [NetMirror-Extension](https://github.com/Sushan64/NetMirror-Extension)
for their work and inspiration around provider logic.

---

## Disclaimer

**Nivio Desktop does not host any media content.** This application acts as an
aggregator for metadata and streaming links from publicly available third-party
sources. The developers of Nivio are not affiliated with those sources. You are
responsible for complying with your local laws, platform terms, and content
rights policies when using this application.
