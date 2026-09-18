import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:nivio/core/debug_log.dart';

class _DnsCacheEntry {
  final List<InternetAddress> addresses;
  final DateTime expiresAt;

  _DnsCacheEntry(this.addresses, Duration ttl)
      : expiresAt = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Service for resolving hostnames via DNS over HTTPS (DoH)
class DnsOverHttpsService {
  final http.Client _client;
  final Map<String, _DnsCacheEntry> _cache = {};

  DnsOverHttpsService({http.Client? client})
      : _client = client ?? http.Client();

  /// Resolves [host] via DNS-over-HTTPS using [dohUrl].
  /// Falls back to standard system DNS if DoH fails.
  Future<List<InternetAddress>> lookup(
    String host, {
    String dohUrl = 'https://cloudflare-dns.com/dns-query',
    bool enabled = true,
  }) async {
    // If not enabled or host is already an IP address, use system lookup
    if (!enabled || InternetAddress.tryParse(host) != null) {
      return InternetAddress.lookup(host);
    }

    final cacheKey = '$dohUrl:$host';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.addresses;
    }

    try {
      final uri = Uri.parse(dohUrl).replace(
        queryParameters: {
          'name': host,
          'type': 'A',
        },
      );

      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/dns-json',
          'User-Agent': 'Nivio/1.0',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final answers = data['Answer'] as List<dynamic>?;

        if (answers != null && answers.isNotEmpty) {
          final addresses = <InternetAddress>[];
          int minTtl = 300;

          for (final ans in answers) {
            // Type 1 is A (IPv4), Type 28 is AAAA (IPv6)
            final type = ans['type'] as int?;
            final ip = ans['data'] as String?;
            final ttl = ans['TTL'] as int? ?? 300;
            if (ttl < minTtl) minTtl = ttl;

            if ((type == 1 || type == 28) && ip != null) {
              final parsed = InternetAddress.tryParse(ip);
              if (parsed != null) {
                addresses.add(parsed);
              }
            }
          }

          if (addresses.isNotEmpty) {
            _cache[cacheKey] = _DnsCacheEntry(
              addresses,
              Duration(seconds: minTtl.clamp(60, 3600)),
            );
            return addresses;
          }
        }
      }
    } catch (e) {
      appDebugLog('⚠️ [DoH] Lookup failed for $host via $dohUrl: $e. Falling back to system DNS.');
    }

    // Fallback to system DNS
    return InternetAddress.lookup(host);
  }

  void clearCache() {
    _cache.clear();
  }
}
