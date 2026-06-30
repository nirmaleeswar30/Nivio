# Changelog

All notable changes to this project will be documented in this file.

## Nivio-v2.1.0

### ✨ New Features & Enhancements
*   ⚡ **Parallel Better Downloads:** Completely revamped the download engine to support significantly faster, highly reliable parallel downloading!
*   🎉 **Watch Party Chats & Reactions:** The ultimate watch party experience is here! You can now chat in real-time and send live emoji reactions while watching movies perfectly synced with your friends!
*   📱 **Picture-in-Picture (PiP) Support:** The highly anticipated PiP mode is here! Watch movies in a floating window while multitasking. What's even better? Watch Party sync works flawlessly while in PiP mode!
*   🔗 **Cloudstream-Style Deep Link Sharing:** Say goodbye to broken share links! Sharing a movie or show now generates an elegant web-redirect link that works perfectly across all social apps and deep-links directly into the exact movie inside Nivio!
*   ❤️ **GitHub Sponsors Integration:** You can now accept donations directly! A shiny new "Sponsor Nivio" button with a pink heart has been added to the Profile screen. (Your repository also has a sponsor button now thanks to the new `FUNDING.yml`!)

### 🛠️ UI Tweaks & Improvements
*   **Share Icon Repositioning:** Moved the share icon to a more convenient location alongside the other media action buttons for easier access.

### 🐛 Bug Fixes
*   **Anime Batch Download Quality Selector:** Fixed a bug where batch downloading a full season of anime would skip the quality/language selector. It now correctly prompts you to choose your preferred resolution and Sub/Dub variation!
*   **Parallel Download Corruption Fix:** Fixed a critical bug where anime episodes downloaded via the new parallel engine would sometimes be corrupted or unplayable due to missing FFmpeg packet-fixing flags. The parallel engine is now just as bulletproof as the sequential one.
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
