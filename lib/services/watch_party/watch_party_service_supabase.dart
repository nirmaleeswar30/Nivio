import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'watch_party_models.dart';
import 'watch_party_supabase_config.dart';

class WatchPartyServiceSupabase {
  WatchPartyServiceSupabase({
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
  });

  final String userId;
  final String userName;
  final String? userPhotoUrl;

  RealtimeChannel? _channel;
  String? _sessionCode;
  bool _isHost = false;
  int _stateVersion = 0;
  int _lastAppliedStateVersion = 0;
  String? _controllerId;
  final Map<String, WatchPartyParticipant> _participants = {};
  WatchPartyPlaybackState? _playbackState;
  WatchPartySession? _session;

  final StreamController<WatchPartySession?> _sessionController =
      StreamController<WatchPartySession?>.broadcast();
  final StreamController<WatchPartyPlaybackState> _playbackController =
      StreamController<WatchPartyPlaybackState>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  WatchPartySession? get currentSession => _session;
  bool get isHost => _isHost;
  bool get canControlPlayback => _isHost || (_controllerId == userId);
  String? get controllerId => _controllerId;
  bool get isInSession => _sessionCode != null;
  String? get sessionCode => _sessionCode;

  Stream<WatchPartySession?> get sessionStream => _sessionController.stream;
  Stream<WatchPartyPlaybackState> get playbackStream =>
      _playbackController.stream;
  Stream<String> get errorStream => _errorController.stream;

  String generateSessionCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<String?> createSession({String? preferredCode}) async {
    if (!WatchPartySupabaseConfig.isAvailable) {
      _emitError('Watch party is not configured.');
      return null;
    }

    await leaveSession();
    _isHost = true;
    _sessionCode =
        (preferredCode?.trim().isNotEmpty == true
                ? preferredCode!.trim()
                : generateSessionCode())
            .toUpperCase();
    _stateVersion = 0;
    _lastAppliedStateVersion = 0;
    _controllerId = null;
    _participants.clear();
    _playbackState = null;

    try {
      await _joinChannel(_sessionCode!);
      _emitSessionUpdate();
      return _sessionCode;
    } catch (e) {
      _emitError('Failed to create watch party: $e');
      await leaveSession();
      return null;
    }
  }

  Future<bool> joinSession(String code) async {
    if (!WatchPartySupabaseConfig.isAvailable) {
      _emitError('Watch party is not configured.');
      return false;
    }

    await leaveSession();
    _isHost = false;
    _sessionCode = code.trim().toUpperCase();
    _stateVersion = 0;
    _lastAppliedStateVersion = 0;
    _controllerId = null;
    _participants.clear();
    _playbackState = null;

    try {
      await _joinChannel(_sessionCode!);
      await Future.delayed(const Duration(milliseconds: 700));

      final hasHost = _participants.values.any(
        (participant) => participant.isHost && participant.id != userId,
      );
      if (!hasHost) {
        _emitError('No watch party found for this code.');
        await leaveSession();
        return false;
      }

      await requestStateSync(reason: 'join');
      _emitSessionUpdate();
      return true;
    } catch (e) {
      _emitError('Failed to join watch party: $e');
      await leaveSession();
      return false;
    }
  }

  Future<void> _joinChannel(String code) async {
    final supabase = Supabase.instance.client;
    final subscribedCompleter = Completer<void>();

    final previousChannel = _channel;
    if (previousChannel != null) {
      try {
        await previousChannel.untrack().timeout(
          const Duration(milliseconds: 700),
        );
      } catch (_) {}
      try {
        await previousChannel.unsubscribe().timeout(
          const Duration(milliseconds: 700),
        );
      } catch (_) {}
    }

    _channel = supabase.channel(
      'watch_party:$code',
      opts: const RealtimeChannelConfig(self: true),
    );

    _channel!.onBroadcast(
      event: 'playback',
      callback: _handlePlaybackBroadcast,
    );
    _channel!.onBroadcast(
      event: 'state_request',
      callback: _handleStateRequest,
    );
    _channel!.onBroadcast(
      event: 'state_snapshot',
      callback: _handleStateSnapshot,
    );
    _channel!.onBroadcast(
      event: 'controller_update',
      callback: _handleControllerUpdate,
    );
    _channel!.onBroadcast(event: 'session_end', callback: _handleSessionEnd);

    _channel!.onPresenceSync((_) => _handlePresenceSync());
    _channel!.onPresenceJoin((payload) {
      _handlePresenceJoin(payload.newPresences);
    });
    _channel!.onPresenceLeave((payload) {
      _handlePresenceLeave(payload.leftPresences);
    });

    _channel!.subscribe((status, error) async {
      if (kDebugMode) {
        debugPrint('WatchParty channel status: $status, error: $error');
      }
      if (status == RealtimeSubscribeStatus.subscribed) {
        try {
          await _channel!.track({
            'user_id': userId,
            'user_name': userName,
            'photo_url': userPhotoUrl,
            'is_host': _isHost,
            'joined_at': DateTime.now().toIso8601String(),
          });
          if (!subscribedCompleter.isCompleted) {
            subscribedCompleter.complete();
          }
        } catch (e) {
          if (!subscribedCompleter.isCompleted) {
            subscribedCompleter.completeError(e);
          }
        }
        return;
      }

      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.timedOut) {
        if (!subscribedCompleter.isCompleted) {
          subscribedCompleter.completeError(
            Exception(error?.toString() ?? status.name),
          );
        }
      }
    });

    await subscribedCompleter.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        throw TimeoutException('Timed out while joining watch party.');
      },
    );
  }

  Future<void> syncPlayback({
    required int mediaId,
    required String mediaType,
    int? providerIndex,
    required int season,
    required int episode,
    required int positionMs,
    required bool isPlaying,
  }) async {
    if (!canControlPlayback || _channel == null || _sessionCode == null) {
      return;
    }

    final version = _nextStateVersion();
    final state = WatchPartyPlaybackState(
      mediaId: mediaId,
      mediaType: mediaType,
      providerIndex: providerIndex,
      season: season,
      episode: episode,
      positionMs: positionMs,
      isPlaying: isPlaying,
      syncedAt: DateTime.now(),
      hostId: userId,
      stateVersion: version,
    );

    _playbackState = state;
    _playbackController.add(state);
    _emitSessionUpdate();

    await _channel!.sendBroadcastMessage(
      event: 'playback',
      payload: state.toJson(),
    );
  }

  Future<void> requestStateSync({String reason = 'manual'}) async {
    if (_isHost || _channel == null) return;
    await _channel!.sendBroadcastMessage(
      event: 'state_request',
      payload: {
        'requesterId': userId,
        'requestedAt': DateTime.now().toIso8601String(),
        'reason': reason,
      },
    );
  }

  Future<void> setPlaybackController(String? participantId) async {
    if (!_isHost || _channel == null || _sessionCode == null) return;

    String? normalized;
    final raw = (participantId ?? '').trim();
    if (raw.isNotEmpty && raw != userId && _participants.containsKey(raw)) {
      normalized = raw;
    }

    if (_controllerId == normalized) return;
    _controllerId = normalized;
    final version = _nextStateVersion();
    _emitSessionUpdate();

    await _channel!.sendBroadcastMessage(
      event: 'controller_update',
      payload: {
        'controllerId': _controllerId,
        'stateVersion': version,
        'updatedBy': userId,
      },
    );
  }

  Future<void> endSession({
    String reason = 'Host ended the watch party.',
  }) async {
    if (!_isHost || _channel == null) return;
    final version = _nextStateVersion();
    await _channel!.sendBroadcastMessage(
      event: 'session_end',
      payload: {'reason': reason, 'stateVersion': version},
    );
    await leaveSession();
  }

  Future<void> leaveSession() async {
    final oldChannel = _channel;
    _channel = null;

    if (oldChannel != null) {
      try {
        await oldChannel.untrack().timeout(const Duration(milliseconds: 700));
      } catch (_) {}
      try {
        await oldChannel.unsubscribe().timeout(
          const Duration(milliseconds: 700),
        );
      } catch (_) {}
    }

    _sessionCode = null;
    _isHost = false;
    _stateVersion = 0;
    _lastAppliedStateVersion = 0;
    _controllerId = null;
    _participants.clear();
    _playbackState = null;
    _session = null;
    _sessionController.add(null);
  }

  int _nextStateVersion() {
    _stateVersion += 1;
    _lastAppliedStateVersion = _stateVersion;
    return _stateVersion;
  }

  bool _isStaleStateVersion(int incomingVersion) {
    if (incomingVersion <= 0) return false;
    return incomingVersion < _lastAppliedStateVersion;
  }

  void _markAppliedStateVersion(int version) {
    if (version <= 0) return;
    if (version > _lastAppliedStateVersion) {
      _lastAppliedStateVersion = version;
    }
    if (version > _stateVersion) {
      _stateVersion = version;
    }
  }

  void _handlePlaybackBroadcast(Map<String, dynamic> payload) {
    final incomingVersion = (payload['stateVersion'] as num?)?.toInt() ?? 0;
    if (_isStaleStateVersion(incomingVersion)) {
      if (kDebugMode) {
        debugPrint(
          'WatchParty playback ignored as stale: incoming=$incomingVersion local=$_lastAppliedStateVersion',
        );
      }
      return;
    }
    _markAppliedStateVersion(incomingVersion);

    try {
      final playback = WatchPartyPlaybackState.fromJson(payload);
      _playbackState = playback;
      _playbackController.add(playback);
      if (kDebugMode) {
        debugPrint(
          'WatchParty playback applied: v=${playback.stateVersion} media=${playback.mediaId} type=${playback.mediaType} provider=${playback.providerIndex} pos=${playback.positionMs} playing=${playback.isPlaying}',
        );
      }
      _emitSessionUpdate();
    } catch (e) {
      _emitError('Failed to parse party playback state: $e');
    }
  }

  void _handleControllerUpdate(Map<String, dynamic> payload) {
    final incomingVersion = (payload['stateVersion'] as num?)?.toInt() ?? 0;
    if (_isStaleStateVersion(incomingVersion)) return;
    _markAppliedStateVersion(incomingVersion);

    final nextController =
        (payload['controllerId'] as String?)?.trim().isNotEmpty == true
        ? (payload['controllerId'] as String).trim()
        : null;

    _controllerId = nextController;
    _emitSessionUpdate();
  }

  void _handleStateRequest(Map<String, dynamic> payload) {
    if (!_isHost || _channel == null || _sessionCode == null) return;
    final requesterId = (payload['requesterId'] as String?)?.trim();
    if (requesterId == null || requesterId.isEmpty || requesterId == userId) {
      return;
    }
    _broadcastStateSnapshot(targetRequesterId: requesterId);
  }

  void _handleStateSnapshot(Map<String, dynamic> payload) {
    final targetRequesterId = (payload['targetRequesterId'] as String?)?.trim();
    if (targetRequesterId != null && targetRequesterId != userId) return;

    final incomingVersion = (payload['stateVersion'] as num?)?.toInt() ?? 0;
    if (_isStaleStateVersion(incomingVersion)) {
      if (kDebugMode) {
        debugPrint(
          'WatchParty snapshot ignored as stale: incoming=$incomingVersion local=$_lastAppliedStateVersion',
        );
      }
      return;
    }
    _markAppliedStateVersion(incomingVersion);

    try {
      final playbackRaw = payload['playback'];
      if (playbackRaw is Map) {
        final playback = WatchPartyPlaybackState.fromJson(
          Map<String, dynamic>.from(playbackRaw),
        );
        _playbackState = playback;
        _playbackController.add(playback);
        if (kDebugMode) {
          debugPrint(
            'WatchParty snapshot playback applied: v=${playback.stateVersion} media=${playback.mediaId} provider=${playback.providerIndex}',
          );
        }
      }

      final snapshotControllerId =
          (payload['controllerId'] as String?)?.trim().isNotEmpty == true
          ? (payload['controllerId'] as String).trim()
          : null;
      _controllerId = snapshotControllerId;

      final participantsRaw = payload['participants'];
      if (participantsRaw is List) {
        _participants.clear();
        for (final raw in participantsRaw) {
          if (raw is! Map) continue;
          final map = Map<String, dynamic>.from(raw);
          final participant = WatchPartyParticipant(
            id: (map['id'] as String? ?? '').trim(),
            name: (map['name'] as String? ?? 'Guest').trim(),
            photoUrl: map['photoUrl'] as String?,
            isHost: map['isHost'] == true,
            joinedAt:
                DateTime.tryParse(map['joinedAt'] as String? ?? '') ??
                DateTime.now(),
          );
          if (participant.id.isNotEmpty) {
            _participants[participant.id] = participant;
          }
        }
      }

      _emitSessionUpdate();
    } catch (e) {
      _emitError('Failed to apply watch party snapshot: $e');
    }
  }

  void _handleSessionEnd(Map<String, dynamic> payload) {
    final reason = (payload['reason'] as String?)?.trim().isNotEmpty == true
        ? (payload['reason'] as String).trim()
        : 'Watch party ended.';

    _emitError(reason);
    unawaited(leaveSession());
  }

  Future<void> _broadcastStateSnapshot({String? targetRequesterId}) async {
    if (_channel == null || _sessionCode == null) return;
    final version = _nextStateVersion();

    final participantsJson = _participants.values
        .map(
          (participant) => {
            'id': participant.id,
            'name': participant.name,
            'photoUrl': participant.photoUrl,
            'isHost': participant.isHost,
            'joinedAt': participant.joinedAt.toIso8601String(),
          },
        )
        .toList(growable: false);

    await _channel!.sendBroadcastMessage(
      event: 'state_snapshot',
      payload: {
        'stateVersion': version,
        'senderId': userId,
        'targetRequesterId': targetRequesterId,
        'controllerId': _controllerId,
        'playback': _playbackState?.toJson(),
        'participants': participantsJson,
      },
    );
  }

  void _handlePresenceSync() {
    final channel = _channel;
    if (channel == null) return;
    final presenceState = channel.presenceState();
    final nextParticipants = <String, WatchPartyParticipant>{};

    for (final singleState in presenceState) {
      for (final presence in singleState.presences) {
        final participant = _participantFromPresencePayload(presence.payload);
        if (participant != null) {
          nextParticipants[participant.id] = participant;
        }
      }
    }

    _participants
      ..clear()
      ..addAll(nextParticipants);
    _emitSessionUpdate();
  }

  void _handlePresenceJoin(List<Presence> newPresences) {
    for (final presence in newPresences) {
      final participant = _participantFromPresencePayload(presence.payload);
      if (participant != null) {
        _participants[participant.id] = participant;
      }
    }
    _emitSessionUpdate();

    if (_isHost && newPresences.isNotEmpty) {
      for (final presence in newPresences) {
        final requesterId = (presence.payload['user_id'] as String?)?.trim();
        if (requesterId != null &&
            requesterId.isNotEmpty &&
            requesterId != userId) {
          unawaited(_broadcastStateSnapshot(targetRequesterId: requesterId));
        }
      }
    }
  }

  void _handlePresenceLeave(List<Presence> leftPresences) {
    for (final presence in leftPresences) {
      final participantId = (presence.payload['user_id'] as String?)?.trim();
      if (participantId != null && participantId.isNotEmpty) {
        _participants.remove(participantId);
      }
    }
    _emitSessionUpdate();
  }

  WatchPartyParticipant? _participantFromPresencePayload(
    Map<String, dynamic> payload,
  ) {
    final id = (payload['user_id'] as String? ?? '').trim();
    if (id.isEmpty) return null;

    return WatchPartyParticipant(
      id: id,
      name: (payload['user_name'] as String? ?? 'Guest').trim(),
      photoUrl: payload['photo_url'] as String?,
      isHost: payload['is_host'] == true,
      joinedAt:
          DateTime.tryParse(payload['joined_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  void _emitSessionUpdate() {
    final code = _sessionCode;
    if (code == null) return;

    final participants = _participants.values.toList(growable: false)
      ..sort((a, b) {
        if (a.isHost == b.isHost) return a.name.compareTo(b.name);
        return a.isHost ? -1 : 1;
      });

    final hostParticipant = participants.where((p) => p.isHost).firstOrNull;
    final hostId = hostParticipant?.id ?? (_isHost ? userId : '');
    final hostName = hostParticipant?.name ?? (_isHost ? userName : 'Host');

    _session = WatchPartySession(
      sessionCode: code,
      hostId: hostId,
      hostName: hostName,
      participants: participants,
      controllerId: _controllerId,
      playbackState: _playbackState,
    );
    _sessionController.add(_session);
  }

  void _emitError(String message) {
    if (_errorController.isClosed) return;
    _errorController.add(message);
  }

  void dispose() {
    unawaited(leaveSession());
    _sessionController.close();
    _playbackController.close();
    _errorController.close();
  }
}
