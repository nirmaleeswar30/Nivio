import 'dart:async';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/constants.dart';
import '../models/new_episode.dart';
import '../models/watchlist_item.dart';

/// Service for checking new episodes of watchlist TV shows
/// Uses WorkManager for battery-efficient background tasks (Android/iOS only)
class EpisodeCheckService {
  static const String _taskName = 'episodeCheckTask';
  static const String _boxName = 'new_episodes';
  static const String _lastCheckKey = 'last_episode_check';
  static const String _frequencyKey = 'episode_check_frequency';
  static const String _enabledKey = 'episode_check_enabled';

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: tmdbBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      queryParameters: {'api_key': tmdbApiKey},
    ),
  );

  /// Android always supports background tasks
  static bool get _supportsBackgroundTasks => true;

  /// Initialize the service and notifications
  static Future<void> init() async {
    // Initialize notifications (supported on most platforms)
    await _initNotifications();

    // Initialize Hive box for new episodes
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<NewEpisode>(_boxName);
    }

    // WorkManager only works on Android and iOS
    if (_supportsBackgroundTasks) {
      // Initialize WorkManager
      await Workmanager().initialize(
        episodeCheckCallbackDispatcher,
        isInDebugMode: false, // Set to true for debugging
      );

      // Register periodic task if enabled
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_enabledKey) ?? true;
      if (enabled) {
        await registerPeriodicTask();
      }
    }

    print(
      '📺 EpisodeCheckService initialized${_supportsBackgroundTasks ? '' : ' (background tasks not supported on this platform)'}',
    );
  }

  /// Initialize local notifications
  static Future<void> _initNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(android: androidSettings);

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      // Request permissions on Android 13+
      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e) {
      print('⚠️ Failed to initialize notifications: $e');
    }
  }

  /// Handle notification tap
  static void _onNotificationTap(NotificationResponse response) {
    // Navigate to the show's detail page
    // This will be handled by the app when it opens
    print('🔔 Notification tapped: ${response.payload}');
  }

  /// Register the periodic background task
  static Future<void> registerPeriodicTask() async {
    if (!_supportsBackgroundTasks) return;

    final prefs = await SharedPreferences.getInstance();
    final frequencyHours = prefs.getInt(_frequencyKey) ?? 24;

    // Cancel existing task first
    await Workmanager().cancelByUniqueName(_taskName);

    // Register new task with updated frequency
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: Duration(hours: frequencyHours),
      constraints: Constraints(
        networkType: NetworkType.unmetered, // Wi-Fi only
        requiresBatteryNotLow: true, // Don't run on low battery
        requiresCharging: false, // Don't require charging (user preference)
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 10),
    );

    print('📅 Registered periodic task with frequency: ${frequencyHours}h');
  }

  /// Cancel the periodic task
  static Future<void> cancelPeriodicTask() async {
    if (!_supportsBackgroundTasks) return;

    await Workmanager().cancelByUniqueName(_taskName);
    print('❌ Cancelled periodic episode check task');
  }

  /// Get check frequency in hours
  static Future<int> getFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_frequencyKey) ?? 24;
  }

  /// Set check frequency in hours
  static Future<void> setFrequency(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_frequencyKey, hours);

    // Re-register task with new frequency
    final enabled = prefs.getBool(_enabledKey) ?? true;
    if (enabled) {
      await registerPeriodicTask();
    }
  }

  /// Check if episode checking is enabled
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  /// Enable or disable episode checking
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);

    if (enabled) {
      await registerPeriodicTask();
    } else {
      await cancelPeriodicTask();
    }
  }

  /// Get last check timestamp
  static Future<DateTime?> getLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lastCheckKey);
    return timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;
  }

  /// Get all new episode notifications
  static List<NewEpisode> getNewEpisodes() {
    if (!Hive.isBoxOpen(_boxName)) return [];
    final box = Hive.box<NewEpisode>(_boxName);
    return box.values.toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
  }

  /// Get unread episode count
  static int getUnreadCount() {
    if (!Hive.isBoxOpen(_boxName)) return 0;
    final box = Hive.box<NewEpisode>(_boxName);
    return box.values.where((e) => !e.isRead).length;
  }

  /// Mark episode as read
  static Future<void> markAsRead(String key) async {
    if (!Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box<NewEpisode>(_boxName);
    final episode = box.get(key);
    if (episode != null) {
      await box.put(key, episode.copyWith(isRead: true));
    }
  }

  /// Mark all episodes as read
  static Future<void> markAllAsRead() async {
    if (!Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box<NewEpisode>(_boxName);
    for (final key in box.keys) {
      final episode = box.get(key);
      if (episode != null && !episode.isRead) {
        await box.put(key, episode.copyWith(isRead: true));
      }
    }
  }

  /// Clear all episode notifications
  static Future<void> clearAll() async {
    if (!Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box<NewEpisode>(_boxName);
    await box.clear();
  }

  /// Manually trigger episode check (for testing or user-initiated refresh)
  static Future<int> checkNow() async {
    print('🔍 Manual episode check triggered');
    return await _performEpisodeCheck();
  }

  /// Public method for background task to initialize notifications
  static Future<void> initNotificationsForBackground() async {
    await _initNotifications();
  }

  /// Public method for background task to perform episode check
  static Future<int> performEpisodeCheckForBackground() async {
    return await _performEpisodeCheck();
  }

  /// The main episode checking logic
  static Future<int> _performEpisodeCheck() async {
    try {
      // Check connectivity first
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        print('❌ No network connection, skipping check');
        return 0;
      }

      // Get watchlist items (TV shows only)
      if (!Hive.isBoxOpen('watchlist')) {
        await Hive.openBox<WatchlistItem>('watchlist');
      }
      final watchlistBox = Hive.box<WatchlistItem>('watchlist');
      final tvShows = watchlistBox.values
          .where((item) => item.mediaType == 'tv')
          .toList();

      if (tvShows.isEmpty) {
        print('📺 No TV shows in watchlist');
        return 0;
      }

      print('📺 Checking ${tvShows.length} TV shows for new episodes');

      // Get last check time
      final prefs = await SharedPreferences.getInstance();
      final lastCheckTimestamp = prefs.getInt(_lastCheckKey);
      final lastCheck = lastCheckTimestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(lastCheckTimestamp)
          : DateTime.now().subtract(const Duration(days: 7));

      // Open new episodes box
      if (!Hive.isBoxOpen(_boxName)) {
        await Hive.openBox<NewEpisode>(_boxName);
      }
      final episodesBox = Hive.box<NewEpisode>(_boxName);

      int newEpisodesFound = 0;
      final List<NewEpisode> newEpisodesList = [];

      // Check each TV show
      for (final show in tvShows) {
        try {
          // Add delay between requests to avoid rate limiting
          await Future.delayed(const Duration(milliseconds: 500));

          final episodes = await _checkShowForNewEpisodes(
            show.id,
            show.title,
            show.posterPath,
            lastCheck,
          );

          for (final episode in episodes) {
            // Check if we already have this episode
            if (!episodesBox.containsKey(episode.key)) {
              await episodesBox.put(episode.key, episode);
              newEpisodesList.add(episode);
              newEpisodesFound++;
            }
          }
        } catch (e) {
          print('⚠️ Error checking ${show.title}: $e');
          // Continue with other shows
        }
      }

      // Update last check time
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);

      // Show notification if new episodes found
      if (newEpisodesFound > 0) {
        await _showNewEpisodeNotification(newEpisodesList);
      }

      print('✅ Episode check complete: $newEpisodesFound new episodes');
      return newEpisodesFound;
    } catch (e) {
      print('❌ Episode check failed: $e');
      return 0;
    }
  }

  /// Check a specific show for new episodes
  static Future<List<NewEpisode>> _checkShowForNewEpisodes(
    int showId,
    String showName,
    String? posterPath,
    DateTime since,
  ) async {
    final List<NewEpisode> newEpisodes = [];

    try {
      // Get show details to find latest season
      final response = await _dio.get('/3/tv/$showId');
      final showData = response.data;

      final seasons = showData['seasons'] as List<dynamic>? ?? [];
      if (seasons.isEmpty) return [];

      // Get the last 2 seasons (current and previous)
      final seasonsToCheck =
          seasons.where((s) => (s['season_number'] as int? ?? 0) > 0).toList()
            ..sort(
              (a, b) => (b['season_number'] as int).compareTo(
                a['season_number'] as int,
              ),
            );

      final recentSeasons = seasonsToCheck.take(2).toList();

      for (final season in recentSeasons) {
        final seasonNumber = season['season_number'] as int;

        try {
          // Get season episodes
          final seasonResponse = await _dio.get(
            '/3/tv/$showId/season/$seasonNumber',
          );
          final episodes =
              seasonResponse.data['episodes'] as List<dynamic>? ?? [];

          for (final episode in episodes) {
            final airDateStr = episode['air_date'] as String?;
            if (airDateStr == null || airDateStr.isEmpty) continue;

            final airDate = DateTime.tryParse(airDateStr);
            if (airDate == null) continue;

            // Check if episode aired after last check AND not in the future
            if (airDate.isAfter(since) && airDate.isBefore(DateTime.now())) {
              newEpisodes.add(
                NewEpisode(
                  showId: showId,
                  showName: showName,
                  seasonNumber: seasonNumber,
                  episodeNumber: episode['episode_number'] as int,
                  episodeName:
                      episode['name'] as String? ??
                      'Episode ${episode['episode_number']}',
                  posterPath: posterPath,
                  airDate: airDate,
                  detectedAt: DateTime.now(),
                ),
              );
            }
          }
        } catch (e) {
          print('⚠️ Error checking season $seasonNumber: $e');
        }
      }
    } catch (e) {
      print('⚠️ Error fetching show $showId: $e');
    }

    return newEpisodes;
  }

  /// Show notification for new episodes
  static Future<void> _showNewEpisodeNotification(
    List<NewEpisode> episodes,
  ) async {
    if (episodes.isEmpty) return;

    const androidDetails = AndroidNotificationDetails(
      'new_episodes',
      'New Episodes',
      channelDescription:
          'Notifications for new episodes of shows in your watchlist',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFE50914), // Netflix red
      groupKey: 'new_episodes_group',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    if (episodes.length == 1) {
      final episode = episodes.first;
      await _notifications.show(
        episode.hashCode,
        '📺 New Episode Available!',
        '${episode.showName} S${episode.seasonNumber}E${episode.episodeNumber}: ${episode.episodeName}',
        details,
        payload: '${episode.showId}',
      );
    } else {
      // Group notification for multiple episodes
      final showNames = episodes.map((e) => e.showName).toSet().toList();
      final title = showNames.length == 1
          ? '📺 ${showNames.first}'
          : '📺 ${episodes.length} New Episodes';
      final body = showNames.length == 1
          ? '${episodes.length} new episodes available'
          : 'New episodes from ${showNames.take(3).join(", ")}${showNames.length > 3 ? " and more" : ""}';

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
      );
    }
  }
}

/// WorkManager callback dispatcher (must be top-level)
@pragma('vm:entry-point')
void episodeCheckCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('🔔 Background task started: $task');

      // Initialize Hive for background isolate
      await Hive.initFlutter();

      // Register adapters
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(WatchlistItemAdapter());
      }
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter(NewEpisodeAdapter());
      }

      // Initialize notifications
      await EpisodeCheckService.initNotificationsForBackground();

      // Perform the check
      await EpisodeCheckService.performEpisodeCheckForBackground();

      print('✅ Background task completed');
      return true;
    } catch (e) {
      print('❌ Background task failed: $e');
      return false;
    }
  });
}
