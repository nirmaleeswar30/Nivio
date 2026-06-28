enum WatchPartyRole { host, participant }

extension WatchPartyRoleX on WatchPartyRole {
  String get queryValue => switch (this) {
    WatchPartyRole.host => 'host',
    WatchPartyRole.participant => 'participant',
  };

  static WatchPartyRole? fromQuery(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'host':
        return WatchPartyRole.host;
      case 'participant':
      case 'guest':
      case 'joiner':
        return WatchPartyRole.participant;
      default:
        return null;
    }
  }
}

class WatchPartyParticipant {
  const WatchPartyParticipant({
    required this.id,
    required this.name,
    required this.isHost,
    this.photoUrl,
    required this.joinedAt,
  });

  final String id;
  final String name;
  final bool isHost;
  final String? photoUrl;
  final DateTime joinedAt;
}

class WatchPartyPlaybackState {
  const WatchPartyPlaybackState({
    required this.mediaId,
    required this.mediaType,
    this.providerIndex,
    required this.season,
    required this.episode,
    required this.positionMs,
    required this.isPlaying,
    required this.syncedAt,
    required this.hostId,
    required this.stateVersion,
  });

  final int mediaId;
  final String mediaType;
  final int? providerIndex;
  final int season;
  final int episode;
  final int positionMs;
  final bool isPlaying;
  final DateTime syncedAt;
  final String hostId;
  final int stateVersion;

  int get expectedPositionMs {
    if (!isPlaying) return positionMs;
    final elapsedMs = DateTime.now().difference(syncedAt).inMilliseconds;
    return (positionMs + elapsedMs).clamp(0, 1 << 31);
  }

  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    'mediaType': mediaType,
    'providerIndex': providerIndex,
    'season': season,
    'episode': episode,
    'positionMs': positionMs,
    'isPlaying': isPlaying,
    'syncedAt': syncedAt.toIso8601String(),
    'hostId': hostId,
    'stateVersion': stateVersion,
  };

  factory WatchPartyPlaybackState.fromJson(Map<String, dynamic> json) {
    return WatchPartyPlaybackState(
      mediaId: (json['mediaId'] as num?)?.toInt() ?? 0,
      mediaType: (json['mediaType'] as String? ?? '').trim(),
      providerIndex: (json['providerIndex'] as num?)?.toInt(),
      season: (json['season'] as num?)?.toInt() ?? 1,
      episode: (json['episode'] as num?)?.toInt() ?? 1,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      isPlaying: json['isPlaying'] == true,
      syncedAt:
          DateTime.tryParse(json['syncedAt'] as String? ?? '') ??
          DateTime.now(),
      hostId: (json['hostId'] as String? ?? '').trim(),
      stateVersion: (json['stateVersion'] as num?)?.toInt() ?? 0,
    );
  }
}

class WatchPartySession {
  const WatchPartySession({
    required this.sessionCode,
    required this.hostId,
    required this.hostName,
    required this.participants,
    this.controllerId,
    this.playbackState,
  });

  final String sessionCode;
  final String hostId;
  final String hostName;
  final List<WatchPartyParticipant> participants;
  final String? controllerId;
  final WatchPartyPlaybackState? playbackState;

  int get participantCount => participants.length;
}

class WatchPartyChatMessage {
  const WatchPartyChatMessage({
    required this.senderId,
    required this.senderName,
    this.senderPhotoUrl,
    required this.text,
    required this.timestamp,
  });

  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String text;
  final DateTime timestamp;

  factory WatchPartyChatMessage.fromJson(Map<String, dynamic> json) {
    return WatchPartyChatMessage(
      senderId: (json['senderId'] as String? ?? '').trim(),
      senderName: (json['senderName'] as String? ?? 'Guest').trim(),
      senderPhotoUrl: json['senderPhotoUrl'] as String?,
      text: (json['text'] as String? ?? '').trim(),
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'senderId': senderId,
    'senderName': senderName,
    'senderPhotoUrl': senderPhotoUrl,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
  };
}

class WatchPartyReaction {
  const WatchPartyReaction({
    required this.senderId,
    required this.senderName,
    required this.emoji,
    required this.timestamp,
  });

  final String senderId;
  final String senderName;
  final String emoji;
  final DateTime timestamp;

  factory WatchPartyReaction.fromJson(Map<String, dynamic> json) {
    return WatchPartyReaction(
      senderId: (json['senderId'] as String? ?? '').trim(),
      senderName: (json['senderName'] as String? ?? 'Guest').trim(),
      emoji: (json['emoji'] as String? ?? '').trim(),
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'senderId': senderId,
    'senderName': senderName,
    'emoji': emoji,
    'timestamp': timestamp.toIso8601String(),
  };
}
