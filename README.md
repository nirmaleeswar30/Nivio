# NIVIO 🎬

A Netflix-style streaming application built with Flutter, powered by streaming provider APIs and TMDB. Features full cross-platform support (mobile + desktop), watch history synchronization via Firebase, and seamless HLS video playback.

![Flutter](https://img.shields.io/badge/Flutter-3.10+-blue.svg)
![Firebase](https://img.shields.io/badge/Firebase-Integrated-orange.svg)

## ✨ Features

### 🎥 Core Functionality
- **Search** movies and TV shows via TMDB API
- **Multi-provider streaming** with automatic fallback (flixhq → vidsrc → vidsrcto → superstream → febbox → overflix → visioncine)
- **HLS video playback** with quality selection
- **Season/Episode picker** for TV shows
- **Netflix-style UI** with dark theme

### 📊 Watch History Sync
- **Local-first architecture** using Hive for instant updates
- **Cloud sync** to Firebase Firestore
- **Continue watching** across all devices
- **Automatic progress tracking** (updates every 5 seconds)
- **Conflict resolution** (newest timestamp wins)
- **Offline support** with background sync queue

## 🚀 Quick Start

### 1. Install Dependencies
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### 2. Setup Firebase

#### Create Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create new project "Nivio"
3. Enable **Anonymous Authentication**
4. Create **Firestore Database**

#### Set Firestore Rules
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/watchHistory/{historyId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

#### Add Firebase Config Files
- **Android**: Place `google-services.json` in `android/app/`
- **iOS**: Place `GoogleService-Info.plist` in `ios/Runner/`
- **Web**: Add Firebase config to `web/index.html`

### 3. Run the App
```bash
flutter run
```

## 📱 How to Use

1. **Launch app** → Anonymous sign-in automatically
2. **Search** for movies/TV shows using the search icon
3. **Select** a result to view details
4. **Choose** season/episode (TV shows) or tap Play (movies)
5. **Watch** with automatic progress tracking
6. **Continue watching** from home screen on any device

## 🏗️ Architecture

### Data Flow
```
User Action → Provider → Service → API/Firestore
                ↓
           UI Updates (Riverpod auto-rebuild)
                ↓
           Local Cache (Hive) → Background Sync → Cloud
```

### Provider fallback
```dart
Try providers in order until .m3u8 URL found:
flixhq → vidsrc → vidsrcto → superstream → febbox → overflix → visioncine

Headers:
- User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36
```

### Watch History Sync
- **Local-first**: Hive for instant UI updates
- **Cloud sync**: Firestore every 30 seconds
- **Conflict resolution**: Newest timestamp wins
- **Offline**: Queued syncs retry on reconnect

## 🎯 Tech Stack

- **Flutter 3.10+** - Cross-platform framework
- **Riverpod** - State management
- **Firebase Auth** - Anonymous authentication
- **Firestore** - Cloud database
- **Hive** - Local NoSQL database
- **Dio** - HTTP client with custom headers
- **video_player + chewie** - HLS video playback
- **Freezed** - Immutable models
- **cached_network_image** - Image caching

## 📊 Firebase Usage (Free Tier)

For 5 users:
- **Storage**: ~2.5 MB ✅
- **Reads**: ~15/day ✅
- **Writes**: ~3,850/day ✅

**All FREE within Firebase Spark plan!**

## 🐛 Troubleshooting

### "Failed to get stream URL"
- Try different media (provider may not have it)
- Check internet connection
- Wait and retry (providers may be down)

### Video won't play
- Select lower quality
- Check network speed
- Restart app

### Build errors
```bash
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

## 📁 Project Structure

```
lib/
├── core/               # Constants, theme
├── models/             # Data models (Freezed)
├── services/           # API & database services
├── providers/          # Riverpod state management
├── screens/            # UI screens
└── widgets/            # Reusable components
```

## ⚠️ Disclaimer

This application is for educational purposes only. Respect copyright laws and terms of service of all APIs used.

## 🙏 Credits

- **TMDB API**: Movie/TV metadata
-- **Streaming providers**: Stream aggregation (various provider APIs)
- **Firebase**: Auth & sync
- **mov-cli-rs**: Inspiration

---

Made with ❤️ using Flutter
