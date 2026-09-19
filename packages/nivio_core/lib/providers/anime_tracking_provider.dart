import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nivio/models/anime_tracking_models.dart';
import 'package:nivio/services/anilist_auth_service.dart';
import 'package:nivio/services/mal_auth_service.dart';
import 'package:nivio/services/anime_tracking_coordinator.dart';

/// Provider for the AniList authenticated user state.
final aniListAuthProvider =
    StateNotifierProvider<AniListAuthNotifier, TrackingUser?>((ref) {
  return AniListAuthNotifier();
});

class AniListAuthNotifier extends StateNotifier<TrackingUser?> {
  final AniListAuthService _service = AniListAuthService.instance;

  AniListAuthNotifier() : super(null) {
    _init();
    _service.userNotifier.addListener(_onUserChanged);
  }

  void _onUserChanged() {
    state = _service.userNotifier.value;
  }

  @override
  void dispose() {
    _service.userNotifier.removeListener(_onUserChanged);
    super.dispose();
  }

  Future<void> _init() async {
    await _service.init();
    state = _service.currentUser;
  }

  Future<bool> launchAuth() => _service.launchAuthorization();

  Future<bool> loginWithToken(String token) async {
    final success = await _service.authenticateWithToken(token);
    if (success) {
      state = _service.currentUser;
    }
    return success;
  }

  Future<bool> loginWithCode(String code) async {
    final success = await _service.exchangeCodeForToken(code);
    if (success) {
      state = _service.currentUser;
    }
    return success;
  }

  Future<bool> loginWithInput(String input) async {
    final success = await _service.authenticateWithInput(input);
    if (success) {
      state = _service.currentUser;
    }
    return success;
  }

  Future<void> logout() async {
    await _service.disconnect();
    state = null;
  }
}

/// Provider for the MyAnimeList authenticated user state.
final malAuthProvider =
    StateNotifierProvider<MalAuthNotifier, TrackingUser?>((ref) {
  return MalAuthNotifier();
});

class MalAuthNotifier extends StateNotifier<TrackingUser?> {
  final MalAuthService _service = MalAuthService.instance;

  MalAuthNotifier() : super(null) {
    _init();
    _service.userNotifier.addListener(_onUserChanged);
  }

  void _onUserChanged() {
    state = _service.userNotifier.value;
  }

  @override
  void dispose() {
    _service.userNotifier.removeListener(_onUserChanged);
    super.dispose();
  }

  Future<void> _init() async {
    await _service.init();
    state = _service.currentUser;
  }

  Future<bool> launchAuth() => _service.launchAuthorization();

  Future<bool> loginWithCode(String code) async {
    final success = await _service.exchangeCodeForToken(code);
    if (success) {
      state = _service.currentUser;
    }
    return success;
  }

  Future<void> logout() async {
    await _service.disconnect();
    state = null;
  }
}

/// Toggle for auto-syncing anime watch progress (default: true).
final animeAutoSyncProgressProvider =
    StateNotifierProvider<AnimeAutoSyncProgressNotifier, bool>((ref) {
  return AnimeAutoSyncProgressNotifier();
});

class AnimeAutoSyncProgressNotifier extends StateNotifier<bool> {
  static const String _key = 'anime_auto_sync_progress';

  AnimeAutoSyncProgressNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

/// Toggle for auto-syncing anime watchlist additions/removals (default: true).
final animeAutoSyncWatchlistProvider =
    StateNotifierProvider<AnimeAutoSyncWatchlistNotifier, bool>((ref) {
  return AnimeAutoSyncWatchlistNotifier();
});

class AnimeAutoSyncWatchlistNotifier extends StateNotifier<bool> {
  static const String _key = 'anime_auto_sync_watchlist';

  AnimeAutoSyncWatchlistNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

/// Preference for how untracked anime is handled: auto-sync or prompt.
final untrackedAnimeBehaviorProvider =
    StateNotifierProvider<UntrackedAnimeBehaviorNotifier, UntrackedAnimeBehavior>((ref) {
  return UntrackedAnimeBehaviorNotifier();
});

class UntrackedAnimeBehaviorNotifier extends StateNotifier<UntrackedAnimeBehavior> {
  static const String _key = 'anime_untracked_behavior';

  UntrackedAnimeBehaviorNotifier() : super(UntrackedAnimeBehavior.autoSync) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    state = UntrackedAnimeBehavior.fromString(raw);
  }

  Future<void> setBehavior(UntrackedAnimeBehavior value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
  }
}

/// Coordinator singleton provider.
final animeTrackingCoordinatorProvider =
    Provider<AnimeTrackingCoordinator>((ref) {
  return AnimeTrackingCoordinator.instance;
});
