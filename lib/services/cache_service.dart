import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nivio/models/cache_entry.dart';

class CacheService {
  static const String _boxName = 'tmdb_cache';
  late Box<CacheEntry> _box;

  /// Default cache durations
  static const Duration shortCache = Duration(minutes: 15); // For trending/popular
  static const Duration mediumCache = Duration(hours: 1); // For search results
  static const Duration longCache = Duration(hours: 24); // For detail pages
  static const Duration extraLongCache = Duration(days: 7); // For static content

  /// Initialize the cache service
  Future<void> init() async {
    _box = await Hive.openBox<CacheEntry>(_boxName);
    // Clean expired entries on init
    await _cleanExpiredEntries();
  }

  /// Get cached data if available and not expired
  Future<T?> get<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final entry = _box.get(key);
      
      if (entry == null) {
        print('❌ Cache MISS: $key');
        return null;
      }

      if (entry.isExpired) {
        print('⏰ Cache EXPIRED: $key');
        await _box.delete(key);
        return null;
      }

      print('✅ Cache HIT: $key');
      final jsonData = json.decode(entry.data) as Map<String, dynamic>;
      return fromJson(jsonData);
    } catch (e) {
      print('⚠️  Cache ERROR: $key - $e');
      // If there's any error reading cache, delete it and return null
      await _box.delete(key);
      return null;
    }
  }

  /// Get cached list data if available and not expired
  Future<List<T>?> getList<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final entry = _box.get(key);
      
      if (entry == null) {
        print('❌ Cache MISS: $key');
        return null;
      }

      if (entry.isExpired) {
        print('⏰ Cache EXPIRED: $key');
        await _box.delete(key);
        return null;
      }

      print('✅ Cache HIT: $key');
      final jsonList = json.decode(entry.data) as List<dynamic>;
      return jsonList
          .map((item) => fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('⚠️  Cache ERROR: $key - $e');
      // If there's any error reading cache, delete it and return null
      await _box.delete(key);
      return null;
    }
  }

  /// Get cached raw JSON data if available and not expired
  Future<Map<String, dynamic>?> getRaw(String key) async {
    try {
      final entry = _box.get(key);
      
      if (entry == null) {
        print('❌ Cache MISS: $key');
        return null;
      }

      if (entry.isExpired) {
        print('⏰ Cache EXPIRED: $key');
        await _box.delete(key);
        return null;
      }

      print('✅ Cache HIT: $key');
      return json.decode(entry.data) as Map<String, dynamic>;
    } catch (e) {
      print('⚠️  Cache ERROR: $key - $e');
      // If there's any error reading cache, delete it and return null
      await _box.delete(key);
      return null;
    }
  }

  /// Get stale cached data (even if expired) - for stale-while-revalidate pattern
  Future<Map<String, dynamic>?> getStaleRaw(String key) async {
    try {
      final entry = _box.get(key);
      
      if (entry == null) {
        print('❌ Cache MISS: $key');
        return null;
      }

      if (entry.isExpired) {
        print('🔄 Cache STALE (will revalidate): $key');
      } else {
        print('✅ Cache HIT: $key');
      }
      
      return json.decode(entry.data) as Map<String, dynamic>;
    } catch (e) {
      print('⚠️  Cache ERROR: $key - $e');
      await _box.delete(key);
      return null;
    }
  }

  /// Check if cache entry exists and is expired
  bool isExpired(String key) {
    final entry = _box.get(key);
    return entry?.isExpired ?? true;
  }

  /// Store data in cache with TTL
  Future<void> set(
    String key,
    dynamic data, {
    Duration ttl = mediumCache,
  }) async {
    try {
      final entry = CacheEntry(
        key: key,
        data: json.encode(data),
        timestamp: DateTime.now(),
        ttlMilliseconds: ttl.inMilliseconds,
      );
      await _box.put(key, entry);
      print('💾 Cache STORED: $key (TTL: ${ttl.inMinutes}min)');
    } catch (e) {
      print('⚠️  Cache STORE ERROR: $key - $e');
      // Silently fail cache write - app should continue without cache
    }
  }

  /// Background update - updates cache without blocking (with retry logic)
  Future<void> updateInBackground(
    String key,
    Future<dynamic> Function() fetchFn,
    Duration ttl, {
    int maxRetries = 3,
  }) async {
    int retryCount = 0;
    
    while (retryCount < maxRetries) {
      try {
        final data = await fetchFn();
        await set(key, data, ttl: ttl);
        print('🔄 Background refresh completed: $key');
        return;
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          print('⚠️  Background refresh failed after $maxRetries attempts: $key - $e');
          return;
        }
        
        // Exponential backoff: wait 1s, 2s, 4s before retrying
        final waitTime = Duration(seconds: (1 << (retryCount - 1)));
        print('⏳ Retry $retryCount/$maxRetries for $key in ${waitTime.inSeconds}s...');
        await Future.delayed(waitTime);
      }
    }
  }

  /// Delete a specific cache entry
  Future<void> delete(String key) async {
    await _box.delete(key);
  }

  /// Clear all cache
  Future<void> clearAll() async {
    await _box.clear();
  }

  /// Clean expired entries - runs in background to not block init
  Future<void> _cleanExpiredEntries() async {
    // Run cleanup in background after a delay to not block app startup
    Future.delayed(const Duration(seconds: 2), () async {
      final expiredKeys = <String>[];
      
      for (final entry in _box.values) {
        if (entry.isExpired) {
          expiredKeys.add(entry.key);
        }
      }

      for (final key in expiredKeys) {
        await _box.delete(key);
      }
      
      if (expiredKeys.isNotEmpty) {
        print('🧹 Cleaned ${expiredKeys.length} expired cache entries');
      }
    });
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    final total = _box.length;
    var expired = 0;
    var valid = 0;

    for (final entry in _box.values) {
      if (entry.isExpired) {
        expired++;
      } else {
        valid++;
      }
    }

    return {
      'total': total,
      'valid': valid,
      'expired': expired,
    };
  }

  /// Close the cache box
  Future<void> close() async {
    await _box.close();
  }
}
