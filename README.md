# Nivio

Nivio is a Flutter streaming app with a Netflix-style UI, TMDB-powered discovery, direct and embed playback providers, cloud-synced watch progress, and optional real-time watch parties.

## Current Implementation

### Discovery and Browsing
- Home feed with language-focused sections (Anime, Tamil, Telugu, Hindi, Korean).
- TMDB-backed search with filters/sorting and paginated results.
- Media detail pages with trailer support and quick jump into playback.

### Playback
- Direct stream pipeline first, then embed fallback.
- Provider switching inside player.
- Season/episode picker for TV content.
- Continue watching and resume progress.
- Preferred playback speed and preferred quality settings.

### Provider Chain (Implemented)
- Anime direct: `animepahe` (via `aimi_lib`) -> `net22 (direct)` -> `flix (direct)`.
- Non-anime direct: `net22 (direct)` -> `flix (direct)`.
- Embed fallback: `vidsrc.cc` -> `vidsrc.to` -> `vidlink`.

### Watch Party (Supabase, Optional)
- Create or join a room using a 6-character code.
- Presence list with host and participants.
- Host can delegate playback control from Watch Party screen.
- Shared control model: host keeps control even when delegating.
- Last-action-wins sync behavior for party playback state.

### Library and Alerts
- Library tabs: New Episodes + Watchlist.
- Episode check background flow with configurable frequency.
- Manual "Check now" and in-app episode alert controls.

### Account and Sync
- Firebase authentication (Google + anonymous flows in codebase).
- Watch history/watch progress syncing through Firestore.
- Local-first persistence with Hive and SharedPreferences.

### App Updates
- Shorebird OTA background check path is integrated.
- GitHub release update prompt is integrated.

## Tech Stack

- Flutter (Dart SDK `^3.10.0`)
- State management: Riverpod
- Navigation: GoRouter (with `StatefulShellRoute` tabs)
- Backend: Firebase Auth + Cloud Firestore
- Realtime watch party: Supabase Realtime
- Local storage: Hive + SharedPreferences
- Networking/scraping: Dio + custom scraper services
- Playback: `better_player_plus` (local package) + `flutter_inappwebview`
- Background/notifications: Workmanager + Flutter Local Notifications

## Project Structure

```text
lib/
  main.dart
  core/
  models/
  providers/
  screens/
  services/
    watch_party/
  widgets/
packages/
  better_player_plus/
```

Key screens:
- `lib/screens/home_screen.dart`
- `lib/screens/search_screen.dart`
- `lib/screens/media_detail_screen.dart`
- `lib/screens/player_screen.dart`
- `lib/screens/library_screen.dart`
- `lib/screens/watch_party_screen.dart`
- `lib/screens/profile_screen.dart`

## Setup

### 1. Prerequisites
- Flutter SDK with Dart `^3.10.0`
- Firebase project (required)
- Supabase project (optional, only for Watch Party)

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Firebase setup (required)

Follow `FIREBASE_SETUP.md`.

At minimum:
- Configure Firebase for your target platform.
- Ensure `lib/firebase_options.dart` matches your Firebase project.
- Add platform config files where needed (for example `android/app/google-services.json`).
- Enable auth providers you plan to use.

### 4. TMDB API key (required)

TMDB key is currently read from `lib/core/constants.dart` (`tmdbApiKey`).
Replace it with your own key.

### 5. Supabase env (optional, Watch Party only)

Create `.env` at repo root:

```env
SUPABASE_URL=your_supabase_project_url
SUPABASE_ANON_KEY=your_supabase_anon_key
```

If these are missing, the app still runs and Watch Party is shown as unavailable.

### 6. Run

```bash
flutter run
```

## Build

```bash
flutter build apk --release
flutter build appbundle --release
```

For additional release/update workflows, see:
- `SHOREBIRD_SETUP.md`
- `build_universal_apk.ps1`

## Routing Overview

Main shell tabs:
- `/home`
- `/search`
- `/library`
- `/party`

Additional routes:
- `/auth`
- `/profile`
- `/media/:id?type=movie|tv`
- `/player/:id?...`

Compatibility redirects exist for `/watchlist`, `/new-episodes`, and `/watch-party`.

## Notes for Contributors

- Run analyzer before PR:

```bash
flutter analyze
```

- If you modify generated model/provider code patterns, run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## License

MIT. See `LICENSE`.

## Disclaimer

Nivio does not host media content. It aggregates metadata and streaming links from third-party sources. You are responsible for complying with local laws, platform terms, and content rights policies.
