# Changelog

All notable changes to this project will be documented in this file.

## Nivio-v2.2.0

### ✨ New Features & Enhancements
*   ⏩ **Upgraded Skip Intro/Outro UI:** The "Skip Intro" and "Skip Outro" buttons have been completely redesigned with a much thicker, bolder white background for a premium, highly visible OTT experience.
*   📦 **Massive APK Size Reduction:** Reduced the primary GitHub Release APK size from ~300MB down to a lightning-fast ~90MB! We introduced a custom Python stripper script to automatically generate Shorebird-compatible `arm64-v8a` APKs out of the universal `.aab` file.

### 🛠️ Bug Fixes & Improvements
*   **AnimePahe Native Stream Proxy Fix:** Fixed a critical issue where direct `.m3u8` streams extracted from Kwik (AnimePahe) were failing to play on the native `media_kit` player due to strict CORS and referer policies. Implemented a robust local `HlsProxyService` to securely proxy the master playlist and dynamically rewrite segment URLs with the correct headers, allowing native stream playback!
*   **"Lock Upp" Series Split-Season Fix:** Fixed a major metadata mapping bug where highly popular split-season Indian shows (like *Lock Upp*) would fail to play because TMDB grouped their episodes entirely differently than source providers. The scraper now intelligently falls back and cross-references "Season 1" entries!
*   **Kwik Embed Provider Stability:** Fixed a bug where viewing an Anime via the Kwik Embed player would mistakenly trigger a "Provider Failed" error and switch sources if a background Kwik analytics script failed. The engine now ignores harmless background HTTP 404s so the video plays flawlessly!
*   **Outro Skipping Edge Case Fixed:** Fixed a bug where skipping the Outro would accidentally skip vital post-credits scenes in anime.
*   **Massive Codebase Cleanup:** Purged a variety of dead code, unused providers, and redundant null-aware expressions across the `downloads_screen`, `media_detail_screen`, and `download_service`. `dart analyze` now reports 0 issues!


## Nivio-v2.1.0

### ✨ New Features & Enhancements
*   ⚡ **Parallel Better Downloads:** Completely revamped the download engine to support significantly faster, highly reliable parallel downloading!
*   🎉 **Watch Party Chats & Reactions:** The ultimate watch party experience is here! You can now chat in real-time and send live emoji reactions while watching movies perfectly synced with your friends!
*   📱 **Picture-in-Picture (PiP) Support:** The highly anticipated PiP mode is here! Watch movies in a floating window while multitasking. What's even better? Watch Party sync works flawlessly while in PiP mode!
*   🔗 **Cloudstream-Style Deep Link Sharing:** Say goodbye to broken share links! Sharing a movie or show now generates an elegant web-redirect link that works perfectly across all social apps and deep-links directly into the exact movie inside Nivio!
*   ❤️ **GitHub Sponsors Integration:** You can now accept donations directly! A shiny new "Sponsor Nivio" button with a pink heart has been added to the Profile screen. (Your repository also has a sponsor button now thanks to the new `FUNDING.yml`!)

### 🛠️ UI Tweaks & Improvements
*   **Instant Playback:** The video player's internal buffering engine has been heavily optimized! Videos will now start playing *instantly* the moment the first frame is downloaded, instead of forcing you to wait for a mandatory 2.5-second buffer.
*   **Zero-Delay Binge Watching (Stream Prefetching):** When watching a TV show or anime, the app will now silently fetch and process the stream links for the *next* episode in the background while you are watching the current one. When you click "Next Episode" (or when it auto-plays), the video will load instantly without any scraper loading screens!
*   **Share Icon Repositioning:** Moved the share icon to a more convenient location alongside the other media action buttons for easier access.

*   **Anime Mapping Fix:** Fixed an issue where slight punctuation differences between TMDB and AniList (such as "Journey's End" vs "Journey’s End" in Frieren) would cause the scraper to fetch an obscure mini-spin-off instead of the massively popular main series. The AniList scraper now strictly prioritizes search matches by popularity.
*   **Episode Picker Orientation Bug:** Fixed a bug where selecting an episode from the in-player Episode Picker would lock the screen into a forced portrait (vertical) orientation. The player now seamlessly changes episodes in-place without reloading the entire screen, ensuring it stays perfectly locked in landscape mode!
*   **Anime Batch Download Quality Selector:** Fixed a bug where batch downloading a full season of anime would skip the quality/language selector. It now correctly prompts you to choose your preferred resolution and Sub/Dub variation!
*   **Parallel Download Merge Fix:** Fixed an issue where "Normal Series" videos would get stuck indefinitely on the "Merging files..." phase due to unnecessary audio transcoding. The app now intelligently distinguishes between Anime and Normal series, applying the instant direct-copy merging to normal series while preserving the timestamp-fixing audio transcode for Animepahe downloads.
*   **Parallel Download Subtitle Fix:** Fixed a bug where subtitles chosen for normal TV shows/movies (via the parallel downloader engine) were being completely ignored. The parallel engine now correctly downloads and processes external subtitles into `.srt` format exactly like the sequential fallback engine does.
*   **Premature Download Merge Fix:** Fixed a major bug where unstable networks would cause the parallel downloader to silently drop connections and prematurely merge incomplete files. The engine now features strict byte-verification and dynamically adjusts HTTP Range headers to seamlessly resume from the exact failed byte without corrupting the file!
*   **Audio Track Reversion Bug:** Fixed a bug where resuming HLS streams would occasionally cause the player to abandon your preferred audio language and switch to an unnamed track. The player is now fully aware of dynamic chunk loading and strictly enforces your preferred track at all times.
*   **Player Exit Crash Fix:** Fixed a "Bad state" crash that occurred when backing out of the video player, caused by attempting to read Riverpod providers while the widget was unmounting.
*   **Video Player UI Crash Fix:** Fixed a layout rendering exception in the custom player controls that caused a solid white error overlay to appear instead of the video.
*   **Auto-PiP Glitch Fixed:** Fixed an extremely annoying bug where the app would mistakenly enter Picture-in-Picture mode even after you fully backed out of the player and went to the home screen. PiP will now strictly only trigger if the video player is actually open!
*   **System UI Navigation Fix:** Fixed a UI glitch where swiping back from the video player would cause the Android bottom navigation bar to permanently stick on the screen. The app now properly re-applies immersive mode to stay full-screen!

## NIvio-v2.0.0

### ✨ New Features & Enhancements
*   🧠 **Smart Preferences Memory:** The player now securely remembers your manually selected Audio Track, Subtitle Track, Video Quality, and Streaming Provider (e.g. Netflix vs Amazon) on a per-movie/per-show basis, automatically applying them the next time you hit play!
*   🖼️ **Cinematic Continue Watching:** The "Continue Watching" row now elegantly uses horizontal thumbnails (backdrops) for both Movies and TV Episodes instead of standard vertical posters.
*   📡 **Live TV Multi-Playlist:** You can now add an infinite number of IPTV M3U playlists at the same time and switch between them using the new Playlist Manager!
*   ❤️ **Live TV Favorites:** Tap the heart icon on any channel to instantly save it. Your favorites will now automatically pin to the very top of your channel list!
*   🗂️ **Live TV Filtering:** Easily filter your Live TV channels to show *only* your Favorites with the new dropdown category option!
*   📱 **Native Playback:** Brought native playback to both anime and movies for a smoother, superior viewing experience!
*   🎉 **In-App Changelog:** Added an elegant, auto-triggering popup to view release notes directly in the app!
*   📥 **Full Download Support:** You can now download your favorite movies and anime episodes for offline viewing!
*   🎥 **Brand New Video Player:** A completely rebuilt and improved video player experience!
*   ⏩ **Double-Tap Seeking:** Polished incremental double-tap to seek (10s, 20s, 30s) just like Netflix!
*   🔠 **Subtitle Resizing:** Added the ability to dynamically resize subtitles for a perfectly tailored viewing experience!
*   📺 **Better Studio Screens:** Overhauled the studio screens for OTT platforms giving them a much more premium look!
*   🎬 **TV Show Episode Titles:** The player now beautifully displays the specific episode title while you're watching!
*   🛡️ **Animepahe Bypass Indicator:** Added a visual indicator when bypassing Animepahe's Cloudflare protection!
*   🗂️ **Provider Categories:** Added better categorization to easily find and switch between stream providers!

### 🛠️ Bug Fixes & Under the Hood
*   🔄 **Provider Stability:** Fixed a player crash that occurred when rapidly switching between streaming providers.
*   🎧 **Dynamic Track Switching:** Fixed dynamic audio and subtitle track switching specifically for anime!
*   🎌 **Animepahe Improvements:** Massive under-the-hood fixes for Animepahe direct streams, mapping, and stability!
*   🚀 **Performance Boosts:** Completely refactored IPTV data storage to the local device drive to prevent memory-limit crashes on massive 30MB+ playlists!
*   ⚡ **Smoother UI:** Fixed several UI jank issues for buttery smooth scrolling across the app!
*   ⏱️ **Watch Tracking:** Fixed and improved watch history tracking so you never lose your place!
*   🔧 **Provider Fixes:** Fixed and improved the bypass for direct providers and the episode picker!
*   💾 **More Reliable Downloads:** Improved download stability for anime and general media!
