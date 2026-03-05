import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/services/watch_party/watch_party_models.dart';
import 'package:nivio/services/watch_party/watch_party_service_supabase.dart';
import 'package:nivio/services/watch_party/watch_party_supabase_config.dart';

final isWatchPartyAvailableProvider = Provider<bool>((ref) {
  return WatchPartySupabaseConfig.isAvailable;
});

final watchPartyServiceProvider = Provider<WatchPartyServiceSupabase?>((ref) {
  if (!WatchPartySupabaseConfig.isAvailable) return null;

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final displayName = (user.displayName ?? '').trim().isNotEmpty
      ? user.displayName!.trim()
      : 'Guest ${user.uid.substring(0, 6)}';

  final service = WatchPartyServiceSupabase(
    userId: user.uid,
    userName: displayName,
    userPhotoUrl: user.photoURL,
  );
  ref.onDispose(service.dispose);
  return service;
});

final watchPartySessionProvider = StreamProvider<WatchPartySession?>((ref) {
  final service = ref.watch(watchPartyServiceProvider);
  if (service == null) return Stream.value(null);
  return service.sessionStream;
});
