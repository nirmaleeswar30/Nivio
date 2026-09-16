import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/export.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/stream_result.dart';

final vidRockScraperProvider = Provider((ref) => VidRockScraperService());

/// Direct-stream scraper for VidRock (vidrock.net).
///
/// VidRock's API returns a map of named servers (Nova / Luna / Orion / Astra /
/// Atlas …), each with an AES-256-GCM encrypted `url` token. The token is
/// base64url( iv[12] | ciphertext | gcmTag[16] ), decrypted with a fixed key to
/// reveal the real HLS/MP4 URL. The CDN requires `Referer: https://vidrock.net/`.
///
/// Endpoints:
///   movie: https://vidrock.net/api/movie/{tmdbId}
///   tv:    https://vidrock.net/api/tv/{tmdbId}/{season}/{episode}
class VidRockScraperService {
  final String providerName;
  final Dio _dio;

  VidRockScraperService({this.providerName = 'VidRock'})
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'https://vidrock.net',
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            validateStatus: (status) => status != null && status < 600,
            headers: const {
              'Accept': 'application/json',
              'Referer': 'https://vidrock.net/',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
            },
          ),
        );

  // AES-256-GCM key (hex) used by VidRock to encrypt source URLs.
  static final Uint8List _key = _hexToBytes(
    '7f3e9c2a8b5d1f4e6a9c3b7d2e5f8a1c4b6d9e2f5a8c1b4d7e9f2a5c8b1d4e7f',
  );

  static const String _referer = 'https://vidrock.net/';

  Future<StreamResult?> fetchStreamUrl({
    required String tmdbId,
    required String title,
    required String mediaType,
    String? year,
    String? preferredAudio,
    int season = 1,
    int episode = 1,
  }) async {
    try {
      if (tmdbId.isEmpty) {
        appDebugLog('VidRock: Missing TMDB ID');
        return null;
      }

      final isTv = mediaType != 'movie';
      final path = isTv
          ? '/api/tv/$tmdbId/$season/$episode'
          : '/api/movie/$tmdbId';

      appDebugLog('VidRock: Fetching API - $path');
      final response = await _dio.get<Object?>(path);
      if (response.statusCode != 200) {
        appDebugLog('VidRock: API failed with status ${response.statusCode}');
        return null;
      }

      final data = _asMap(response.data);
      if (data == null || data.isEmpty) {
        appDebugLog('VidRock: Unexpected response format');
        return null;
      }

      final sources = <StreamSource>[];
      // Preserve VidRock's own server order (Nova first, etc.).
      data.forEach((serverName, value) {
        final entry = _asMap(value);
        final token = entry?['url']?.toString();
        if (entry == null || token == null || token.isEmpty || token == 'null') {
          return;
        }
        final type = entry['type']?.toString().toLowerCase();
        final decrypted = _tryDecrypt(token);
        if (decrypted == null || !decrypted.startsWith('http')) {
          appDebugLog('VidRock: failed to decrypt source "$serverName"');
          return;
        }
        final isHls = type == 'hls' || decrypted.contains('.m3u8');
        sources.add(StreamSource(
          url: decrypted,
          quality: serverName, // Nova / Luna / Orion …
          isM3U8: isHls,
        ));
      });

      if (sources.isEmpty) {
        appDebugLog('VidRock: No valid sources found in response');
        return null;
      }

      // Return every decrypted server (Nova/Luna/Orion/Astra…) in VidRock's own
      // order. The player pre-verifies each source in turn and promotes the first
      // reachable one before abandoning the provider, so no probing is needed here
      // (that would double the network round-trips and slow first play).
      appDebugLog(
          'VidRock: SUCCESS! ${sources.length} sources. Primary: ${sources.first.quality}');

      return StreamResult(
        url: sources.first.url,
        quality: sources.first.quality,
        provider: providerName,
        availableQualities: sources.map((s) => s.quality).toList(),
        isM3U8: sources.first.isM3U8,
        headers: const {
          'Referer': _referer,
          'Origin': 'https://vidrock.net',
        },
        sources: sources,
      );
    } catch (e) {
      appDebugLog('VidRock error: $e');
      return null;
    }
  }

  /// AES-256-GCM decrypt of a base64url( iv[12] | ciphertext | tag[16] ) token.
  String? _tryDecrypt(String token) {
    try {
      final data = _base64UrlToBytes(token);
      if (data.length <= 28) return null; // need iv(12) + tag(16) + payload
      final iv = data.sublist(0, 12);
      final cipherTextWithTag = data.sublist(12);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(_key), 128, iv, Uint8List(0)),
        );
      final clear = cipher.process(cipherTextWithTag);
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static Uint8List _base64UrlToBytes(String input) {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    final pad = s.length % 4;
    if (pad == 2) {
      s += '==';
    } else if (pad == 3) {
      s += '=';
    }
    return base64.decode(s);
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
