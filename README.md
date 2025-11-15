<div align="center">

# 🎬 Nivio

### *Your Gateway to Global Entertainment*

A modern, Netflix-inspired streaming platform built with Flutter. Discover movies and TV shows across multiple languages with intelligent search, personalized recommendations, and seamless playback.

[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Integrated-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com)
[![TMDB](https://img.shields.io/badge/TMDB-API-01D277?logo=themoviedatabase&logoColor=white)](https://www.themoviedb.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[Features](#-features) • [Screenshots](#-screenshots) • [Installation](#-installation) • [Tech Stack](#-tech-stack) • [Contributing](#-contributing)

</div>

---

## 🌟 Features

### 🌍 **Multi-Language Content Discovery**
- **5 Language Hubs**: Tamil, Telugu, Hindi, Korean, and Japanese (Anime)
- **Customizable Preferences**: Toggle languages on/off in settings
- **Latest OTT Releases**: Dedicated Tamil OTT section with 6-month filter
- **Trending & Popular**: Curated content for each language

### 🔍 **Advanced Search**
- **Universal Search**: Find content across all languages
- **Smart Filters**: Filter by language (Tamil, Telugu, Hindi, Korean, Japanese)
- **Sort Options**: By popularity, title, or release year
- **Infinite Scroll Pagination**: Instagram-style smooth loading
- **Auto-Load Optimization**: Automatically loads more pages when results are sparse

### 📺 **Seamless Viewing Experience**
- **Continue Watching**: Pick up exactly where you left off
- **Progress Tracking**: Automatic playback position sync
- **Multiple Streaming Providers**: Falls back across vidsrc.cc, vidsrc.to, and vidlink for reliability
- **Embedded Playback**: Webview-based streaming
- **Season/Episode Picker**: Easy TV show navigation

### 🎨 **Beautiful UI/UX**
- **Netflix-Inspired Design**: Familiar dark theme with red accents
- **Hero Slider**: Mixed regional and trending content
- **Custom Branding**: Professional logo integration
- **Native Splash Screen**: Branded app launch experience
- **Adaptive Icons**: Platform-specific app icons

### ☁️ **Cloud-Powered Features**
- **Firebase Authentication**: Secure anonymous login
- **Cloud Firestore Sync**: Watch history across devices
- **Local-First Architecture**: Instant UI updates with Hive
- **Offline Support**: Background sync when online

---

## 📸 Screenshots

> *Coming soon - Add your app screenshots here!*

---

## 🚀 Installation

### Prerequisites

- Flutter SDK (^3.10.0)
- Android Studio / Xcode (for mobile development)
- Firebase account
- TMDB API key ([Get one here](https://www.themoviedb.org/settings/api))

### Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/nirmaleeswar30/Nivio.git
   cd Nivio
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate code**
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Configure Firebase** (See [FIREBASE_SETUP.md](FIREBASE_SETUP.md))
   - Add `google-services.json` to `android/app/`
   - Add `GoogleService-Info.plist` to `ios/Runner/`
   - Enable Anonymous Auth in Firebase Console
   - Create Firestore database

5. **Update TMDB API Key**
   - Edit `lib/core/constants.dart`
   - Replace with your API key

6. **Run the app**
   ```bash
   flutter run
   ```

### Build for Production

```bash
# Android APK
flutter build apk --release

# Android App Bundle (Play Store)
flutter build appbundle --release

# iOS
flutter build ios --release
```

See [BUILD_GUIDE.md](BUILD_GUIDE.md) for detailed instructions.

---

## 🏗️ Architecture

### **State Management**
- **Riverpod**: Reactive, compile-safe state management
- **Freezed**: Immutable data models with unions
- **Code Generation**: Type-safe JSON serialization

### **Data Layer**
```
┌─────────────┐
│   UI Layer  │ ← Riverpod Providers
└──────┬──────┘
       │
┌──────▼──────┐
│  Services   │ ← TMDB API, Streaming Providers, Firebase
└──────┬──────┘
       │
┌──────▼──────┐
│Local Storage│ ← Hive (Watch History)
└─────────────┘
```

### **Key Features Implementation**

#### 🔍 Search Pagination
- Local state management for smooth scrolling
- Fetches next page at 500px from bottom
- Auto-loads additional pages when results < 10
- Filters out 'person' type results
- Preserves scroll position with `PageStorageKey`

#### 🌐 Language Filtering
- SharedPreferences for user preferences
- Conditional rendering based on toggles
- Separate providers per language
- Popular + Trending sections for each

#### ⏯️ Watch History Sync
- Hive for local caching (instant updates)
- Firestore for cloud backup
- Conflict resolution by timestamp
- Progress tracked every 5 seconds

---

## 🛠️ Tech Stack

| Category | Technologies |
|----------|-------------|
| **Framework** | Flutter 3.10+ |
| **State Management** | Riverpod 2.6+, Freezed 2.5+ |
| **Backend** | Firebase (Auth, Firestore) |
| **APIs** | TMDB v3, Streaming Providers (vidsrc.cc, vidsrc.to, vidlink) |
| **Storage** | Hive (local), SharedPreferences |
| **Video** | video_player, Chewie, youtube_player_flutter |
| **Network** | Dio 5.7+, cached_network_image |
| **Navigation** | GoRouter 14.6+ |
| **UI Components** | Shimmer, flutter_svg |

---

## 📂 Project Structure

```
lib/
├── core/
│   ├── constants.dart          # API keys, endpoints
│   └── theme.dart              # App theme (Netflix-style)
├── models/                     # Freezed data models
│   ├── search_result.dart
│   ├── season_info.dart
│   └── watch_history.dart
├── providers/                  # Riverpod providers
│   ├── home_providers.dart
│   ├── search_provider.dart
│   ├── language_preferences_provider.dart
│   └── watch_history_provider.dart
├── screens/                    # UI screens
│   ├── auth_screen.dart
│   ├── home_screen.dart
│   ├── search_screen.dart
│   ├── media_detail_screen.dart
│   ├── player_screen.dart
│   └── settings_screen.dart
├── services/                   # Business logic
│   ├── tmdb_service.dart
│   ├── streaming_service.dart
│   └── watch_history_service.dart
└── widgets/                    # Reusable components
    ├── content_row.dart
    ├── continue_watching_row.dart
    ├── featured_content_slider.dart
    └── search_result_card.dart

assets/
└── images/
    ├── nivio-dark.png         # App logo
    └── app-icon.png           # Launcher icon

android/
└── app/
    └── src/main/
        ├── AndroidManifest.xml
        └── res/                # Generated icons & splash

ios/
└── Runner/
    ├── Info.plist
    └── Assets.xcassets/       # Generated icons
```

---

## 🎯 Roadmap

- [ ] **Watchlist Feature**: Save shows for later
- [ ] **User Profiles**: Multiple profiles per account
- [ ] **Download Support**: Offline viewing
- [ ] **Chromecast**: Cast to TV
- [ ] **Recommendations**: AI-powered suggestions
- [ ] **Social Features**: Share & discuss with friends
- [ ] **Multi-Audio Support**: Select audio tracks
- [ ] **Subtitle Options**: Multiple languages

---

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

Please ensure your code follows the project's style guidelines and includes appropriate tests.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## ⚠️ Disclaimer

**Nivio is for educational purposes only.** This project demonstrates Flutter development best practices and API integration. Users are responsible for ensuring their usage complies with TMDB's Terms of Service and applicable copyright laws. The developers do not host or distribute any copyrighted content.

---

## 🙏 Acknowledgments

- **[The Movie Database (TMDB)](https://www.themoviedb.org/)** - Movie and TV show metadata
- **[Firebase](https://firebase.google.com)** - Backend infrastructure
- **[Flutter](https://flutter.dev)** - Amazing cross-platform framework
- **Netflix** - UI/UX inspiration
- **Open Source Community** - For incredible packages and tools

---

## 📞 Support & Contact

- **Issues**: [GitHub Issues](https://github.com/nirmaleeswar30/Nivio/issues)
- **Discussions**: [GitHub Discussions](https://github.com/nirmaleeswar30/Nivio/discussions)
- **Email**: [Your Email]

---

<div align="center">

### ⭐ Star this repo if you find it useful!

**Made with ❤️ and Flutter**

[Report Bug](https://github.com/nirmaleeswar30/Nivio/issues) • [Request Feature](https://github.com/nirmaleeswar30/Nivio/issues)

</div>
