import 'dart:async';

import '../../auth/firebase_auth_rest_service.dart';
import 'watch_party_identity.dart';
import 'watch_party_service_supabase.dart';
import 'watch_party_supabase_config.dart';

class WatchPartySessionManager {
  WatchPartySessionManager._();

  static final WatchPartySessionManager instance = WatchPartySessionManager._();

  final WatchPartyIdentityStore _identityStore = WatchPartyIdentityStore();
  WatchPartyServiceSupabase? _service;

  WatchPartyServiceSupabase? get currentService => _service;

  Future<WatchPartyServiceSupabase?> ensureService() async {
    await WatchPartySupabaseConfig.initializeIfConfigured();
    if (!WatchPartySupabaseConfig.isAvailable) return null;

    final existing = _service;
    final identity = await _loadIdentity();
    if (existing != null && existing.userId == identity.userId) {
      return existing;
    }
    if (existing != null) {
      _service = null;
      await existing.leaveSession();
      existing.dispose();
    }

    final service = WatchPartyServiceSupabase(
      userId: identity.userId,
      userName: identity.userName,
      userPhotoUrl: identity.userPhotoUrl,
    );
    _service = service;
    return service;
  }

  Future<WatchPartyIdentity> _loadIdentity() async {
    final auth = FirebaseAuthRestService.instance;
    await auth.initialize();
    final user = auth.currentUser;
    if (user == null) return _identityStore.load();

    final displayName = _firstNonEmpty([
      user.displayName,
      user.isAnonymous ? null : user.email,
    ]);
    final fallbackId = user.uid.length <= 6
        ? user.uid
        : user.uid.substring(0, 6);
    return WatchPartyIdentity(
      userId: user.uid,
      userName: displayName ?? 'Guest ${fallbackId.toUpperCase()}',
      userPhotoUrl: user.photoUrl,
    );
  }

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final normalized = value?.trim();
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  Future<void> leaveOrEndCurrentSession() async {
    final service = _service;
    if (service == null) return;
    if (service.isHost) {
      await service.endSession();
    } else {
      await service.leaveSession();
    }
  }

  Future<void> disposeService() async {
    final service = _service;
    _service = null;
    service?.dispose();
    await Future<void>.delayed(Duration.zero);
  }
}
