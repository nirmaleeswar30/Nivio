import 'package:nivio/models/watchlist_item.dart';

/// Supported anime tracking platforms.
enum TrackingProvider {
  anilist('AniList'),
  mal('MyAnimeList');

  final String label;
  const TrackingProvider(this.label);
}

/// Profile information of a connected anime tracking account.
class TrackingUser {
  final String id;
  final String username;
  final String? avatarUrl;
  final TrackingProvider provider;
  final DateTime connectedAt;

  const TrackingUser({
    required this.id,
    required this.username,
    this.avatarUrl,
    required this.provider,
    required this.connectedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'avatarUrl': avatarUrl,
        'provider': provider.name,
        'connectedAt': connectedAt.toIso8601String(),
      };

  factory TrackingUser.fromJson(Map<String, dynamic> json) => TrackingUser(
        id: json['id'] as String,
        username: json['username'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        provider: TrackingProvider.values.byName(
          json['provider'] as String? ?? 'anilist',
        ),
        connectedAt: DateTime.tryParse(json['connectedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Stored OAuth tokens for a tracking provider.
class TrackingTokens {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final TrackingProvider provider;

  const TrackingTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    required this.provider,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt?.toIso8601String(),
        'provider': provider.name,
      };

  factory TrackingTokens.fromJson(Map<String, dynamic> json) => TrackingTokens(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String?,
        expiresAt: json['expiresAt'] != null
            ? DateTime.tryParse(json['expiresAt'] as String)
            : null,
        provider: TrackingProvider.values.byName(
          json['provider'] as String? ?? 'anilist',
        ),
      );
}

/// Anime watch status matching AniList & MAL list states.
enum AnimeWatchStatus {
  watching,
  planning,
  completed,
  dropped,
  paused;

  String toAniListStatus() {
    switch (this) {
      case AnimeWatchStatus.watching:
        return 'CURRENT';
      case AnimeWatchStatus.planning:
        return 'PLANNING';
      case AnimeWatchStatus.completed:
        return 'COMPLETED';
      case AnimeWatchStatus.dropped:
        return 'DROPPED';
      case AnimeWatchStatus.paused:
        return 'PAUSED';
    }
  }

  String toMalStatus() {
    switch (this) {
      case AnimeWatchStatus.watching:
        return 'watching';
      case AnimeWatchStatus.planning:
        return 'plan_to_watch';
      case AnimeWatchStatus.completed:
        return 'completed';
      case AnimeWatchStatus.dropped:
        return 'dropped';
      case AnimeWatchStatus.paused:
        return 'on_hold';
    }
  }

  static AnimeWatchStatus fromAniList(String status) {
    switch (status.toUpperCase()) {
      case 'CURRENT':
        return AnimeWatchStatus.watching;
      case 'COMPLETED':
        return AnimeWatchStatus.completed;
      case 'DROPPED':
        return AnimeWatchStatus.dropped;
      case 'PAUSED':
        return AnimeWatchStatus.paused;
      case 'PLANNING':
      default:
        return AnimeWatchStatus.planning;
    }
  }

  static AnimeWatchStatus fromMal(String status) {
    switch (status.toLowerCase()) {
      case 'watching':
        return AnimeWatchStatus.watching;
      case 'completed':
        return AnimeWatchStatus.completed;
      case 'dropped':
        return AnimeWatchStatus.dropped;
      case 'on_hold':
        return AnimeWatchStatus.paused;
      case 'plan_to_watch':
      default:
        return AnimeWatchStatus.planning;
    }
  }

  static AnimeWatchStatus fromWatchStatus(WatchStatus status) {
    switch (status) {
      case WatchStatus.watching:
        return AnimeWatchStatus.watching;
      case WatchStatus.completed:
        return AnimeWatchStatus.completed;
      case WatchStatus.dropped:
        return AnimeWatchStatus.dropped;
      case WatchStatus.paused:
        return AnimeWatchStatus.paused;
      case WatchStatus.planning:
        return AnimeWatchStatus.planning;
    }
  }

  WatchStatus toWatchStatus() {
    switch (this) {
      case AnimeWatchStatus.watching:
        return WatchStatus.watching;
      case AnimeWatchStatus.completed:
        return WatchStatus.completed;
      case AnimeWatchStatus.dropped:
        return WatchStatus.dropped;
      case AnimeWatchStatus.paused:
        return WatchStatus.paused;
      case AnimeWatchStatus.planning:
        return WatchStatus.planning;
    }
  }
}

/// Preference for how to handle untracked anime when playback begins.
enum UntrackedAnimeBehavior {
  autoSync('Auto-Sync (>80% watched)'),
  prompt('Prompt to Track (Anime Slayer style)');

  final String label;
  const UntrackedAnimeBehavior(this.label);

  static UntrackedAnimeBehavior fromString(String? val) {
    if (val == 'prompt') return UntrackedAnimeBehavior.prompt;
    return UntrackedAnimeBehavior.autoSync;
  }
}

/// Item returned when syncing user list from AniList or MAL.
class SyncedAnimeItem {
  final int? anilistId;
  final int? malId;
  final String title;
  final String? posterUrl;
  final int episodesWatched;
  final int? totalEpisodes;
  final AnimeWatchStatus status;
  final double? score;

  const SyncedAnimeItem({
    this.anilistId,
    this.malId,
    required this.title,
    this.posterUrl,
    required this.episodesWatched,
    this.totalEpisodes,
    required this.status,
    this.score,
  });
}
