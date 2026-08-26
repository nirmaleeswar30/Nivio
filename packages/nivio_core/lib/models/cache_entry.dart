import 'package:hive/hive.dart';

part 'cache_entry.g.dart';

/// Generic cache entry with expiration
@HiveType(typeId: 0)
class CacheEntry {
  @HiveField(0)
  final String key;

  @HiveField(1)
  final String data;

  @HiveField(2)
  final DateTime timestamp;

  @HiveField(3)
  final int ttlMilliseconds;

  CacheEntry({
    required this.key,
    required this.data,
    required this.timestamp,
    required this.ttlMilliseconds,
  });

  Duration get ttl => Duration(milliseconds: ttlMilliseconds);

  bool get isExpired {
    return DateTime.now().difference(timestamp) > ttl;
  }
}
