import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WatchPartySupabaseConfig {
  static const String _fallbackSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
  );
  static const String _fallbackSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static bool _initialized = false;

  static String get _supabaseUrl {
    final fromEnv = (dotenv.env['SUPABASE_URL'] ?? '').trim();
    if (fromEnv.isNotEmpty) return fromEnv;
    return _fallbackSupabaseUrl.trim();
  }

  static String get _supabaseAnonKey {
    final fromEnv = (dotenv.env['SUPABASE_ANON_KEY'] ?? '').trim();
    if (fromEnv.isNotEmpty) return fromEnv;
    return _fallbackSupabaseAnonKey.trim();
  }

  static bool get isConfigured =>
      _supabaseUrl.trim().isNotEmpty && _supabaseAnonKey.trim().isNotEmpty;

  static bool get isAvailable => _initialized && isConfigured;

  static Future<void> initializeIfConfigured() async {
    if (_initialized || !isConfigured) return;

    try {
      await Supabase.initialize(
        url: _supabaseUrl.trim(),
        anonKey: _supabaseAnonKey.trim(),
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
        realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
      );
      _initialized = true;
      if (kDebugMode) {
        debugPrint('WatchPartySupabaseConfig: initialized');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('WatchPartySupabaseConfig: init failed: $e');
      }
    }
  }
}
