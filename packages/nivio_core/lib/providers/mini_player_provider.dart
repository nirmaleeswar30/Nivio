import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/services/discord_rpc_service.dart';

/// Metadata about the media currently playing in the mini player.
class MiniPlayerMediaInfo {
  final int mediaId;
  final int season;
  final int episode;
  final String? mediaType;
  final String? title;
  final String? posterPath;
  final int totalSeasons;
  final int? totalEpisodes;

  const MiniPlayerMediaInfo({
    required this.mediaId,
    required this.season,
    required this.episode,
    this.mediaType,
    this.title,
    this.posterPath,
    this.totalSeasons = 1,
    this.totalEpisodes,
  });
}

/// Immutable state for the global mini player.
@immutable
class MiniPlayerState {
  final Player? player;
  final VideoController? videoController;
  final bool isActive;
  final MiniPlayerMediaInfo? mediaInfo;

  const MiniPlayerState({
    this.player,
    this.videoController,
    this.isActive = false,
    this.mediaInfo,
  });

  MiniPlayerState copyWith({
    Player? player,
    VideoController? videoController,
    bool? isActive,
    MiniPlayerMediaInfo? mediaInfo,
  }) {
    return MiniPlayerState(
      player: player ?? this.player,
      videoController: videoController ?? this.videoController,
      isActive: isActive ?? this.isActive,
      mediaInfo: mediaInfo ?? this.mediaInfo,
    );
  }
}

/// Manages the lifecycle of the global mini player.
/// 
/// The mini player keeps a [Player] and [VideoController] alive when the user
/// navigates away from the full player screen via the back button.
class MiniPlayerNotifier extends StateNotifier<MiniPlayerState> {
  final Ref ref;
  MiniPlayerNotifier(this.ref) : super(const MiniPlayerState());

  /// Activate the mini player by taking ownership of a player instance
  /// that was previously managed by [PlayerScreen].
  void activate({
    required Player player,
    required VideoController videoController,
    required MiniPlayerMediaInfo mediaInfo,
  }) {
    appDebugLog(
      '🧪 [CW_DEBUG] MiniPlayer.activate — player=${_h(player)} ctrl=${_h(videoController)} '
      'media=${mediaInfo.mediaId} S${mediaInfo.season}E${mediaInfo.episode} '
      '| wasActive=${state.isActive} prevPlayer=${_h(state.player)}',
    );
    // If there's already an active mini player with a different player instance,
    // dispose the old one first.
    if (state.isActive && state.player != null && state.player != player) {
      state.player!.dispose();
    }

    state = MiniPlayerState(
      player: player,
      videoController: videoController,
      isActive: true,
      mediaInfo: mediaInfo,
    );
  }

  /// Deactivate and fully dispose the mini player.
  void deactivate() {
    final player = state.player;
    final info = state.mediaInfo;
    appDebugLog(
      '🧪 [CW_DEBUG] MiniPlayer.deactivate — disposing player=${_h(player)} '
      'media=${info?.mediaId} E${info?.episode} pos=${player?.state.position} '
      '(torrent stopActive will also run)',
    );

    if (player != null && info != null && player.state.duration > Duration.zero) {
      final historyService = ref.read(watchHistoryServiceProvider);
      historyService.updateProgress(
        tmdbId: info.mediaId,
        mediaType: info.mediaType ?? 'unknown',
        title: info.title ?? 'Unknown',
        posterPath: info.posterPath,
        currentSeason: info.season,
        currentEpisode: info.episode,
        totalSeasons: info.totalSeasons,
        totalEpisodes: info.totalEpisodes,
        lastPosition: player.state.position,
        totalDuration: player.state.duration,
      );
    }

    try {
      final torrentService = ref.read(torrentStreamServiceProvider);
      torrentService.stopActive();
    } catch (_) {}

    state = const MiniPlayerState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      DiscordRpcService.instance.setBrowsing();
    }
    Future.microtask(() {
      player?.dispose();
    });
  }

  /// Reclaim the player and controller when expanding back to full screen.
  /// Returns the current state and clears the mini player without disposing
  /// the underlying player (the full screen will take ownership).
  MiniPlayerState? reclaim() {
    if (!state.isActive || state.player == null) {
      appDebugLog('🧪 [CW_DEBUG] MiniPlayer.reclaim — nothing to reclaim (active=${state.isActive})');
      return null;
    }
    appDebugLog(
      '🧪 [CW_DEBUG] MiniPlayer.reclaim — player=${_h(state.player)} '
      'media=${state.mediaInfo?.mediaId} E${state.mediaInfo?.episode}',
    );
    final reclaimed = state;
    // Clear state without disposing — the full-screen player now owns it.
    state = const MiniPlayerState();
    return reclaimed;
  }

  @override
  void dispose() {
    state.player?.dispose();
    super.dispose();
  }
}

String _h(Object? o) =>
    o == null ? 'null' : (identityHashCode(o) & 0xFFFF).toRadixString(16);

final miniPlayerProvider =
    StateNotifierProvider<MiniPlayerNotifier, MiniPlayerState>(
  (ref) => MiniPlayerNotifier(ref),
);
