import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/debug_log.dart';

final newTvBypassProvider = ChangeNotifierProvider<NewTvBypassService>((ref) {
  return NewTvBypassService();
});

class NewTvBypassService extends ChangeNotifier {
  final String _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0 /OS.GatuNewTV v1.0';
  final Map<String, String> _cookies = {};
  
  bool _isBypassing = false;
  bool _isBypassed = false;
  Completer<void>? _bypassCompleter;
  
  String get userAgent => _userAgent;
  Map<String, String> get cookies => _cookies;
  bool get isReady => _isBypassed;
  bool get isBypassing => _isBypassing;
  
  String get cookieString {
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<void> init() async {
    if (_isBypassed || _isBypassing) return;
    appDebugLog('🛡️ Initializing NewTvBypassService...');
    await _startBypass();
  }

  Future<void> forceRefresh() async {
    appDebugLog('🛡️ Manual refresh of NewTV bypass requested...');
    await _startBypass(forceRefresh: true);
  }
  
  Future<void> _startBypass({bool forceRefresh = false}) async {
    if (_isBypassing && !forceRefresh) return;
    _isBypassing = true;
    _bypassCompleter = Completer<void>();
    notifyListeners();
    
    appDebugLog('🛡️ Triggering NewTV verify.php bypass...');
    
    try {
      if (forceRefresh) {
        _cookies.clear();
        _isBypassed = false;
      }
      
      final dio = Dio(BaseOptions(
        validateStatus: (status) => true,
        followRedirects: false,
      ));

      final response = await dio.post(
        'https://net52.cc/verify.php',
        data: 'g-recaptcha-response=5a6f2c2b-6b71-41f2-8c1a-2b3c4d5e6f7g',
        options: Options(
          headers: {
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
            'Accept-Encoding': 'gzip, deflate, br, zstd',
            'Accept-Language': 'en-US,en;q=0.9',
            'Cache-Control': 'max-age=0',
            'Connection': 'keep-alive',
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': 'https://net52.cc',
            'Referer': 'https://net52.cc/verify2',
            'sec-ch-ua': '"Google Chrome";v="147", "Not.A/Brand";v="8", "Chromium";v="147"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"Windows"',
            'Sec-Fetch-Dest': 'document',
            'Sec-Fetch-Mode': 'navigate',
            'Sec-Fetch-Site': 'same-origin',
            'Sec-Fetch-User': '?1',
            'Upgrade-Insecure-Requests': '1',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
          },
        ),
      );

      final setCookies = response.headers['set-cookie'];
      if (setCookies != null && setCookies.isNotEmpty) {
        for (final c in setCookies) {
          final parts = c.split(';');
          if (parts.isNotEmpty) {
            final firstPart = parts[0];
            final eqIdx = firstPart.indexOf('=');
            if (eqIdx != -1) {
              final key = firstPart.substring(0, eqIdx).trim();
              final val = firstPart.substring(eqIdx + 1).trim();
              _cookies[key] = val;
            }
          }
        }
      }

      if (_cookies.containsKey('t_hash_t')) {
        appDebugLog('🛡️ NewTV bypass successful! t_hash_t obtained.');
        _isBypassed = true;
      } else {
        appDebugLog('🛡️ NewTV bypass failed: t_hash_t not found in response.');
        _isBypassed = false;
      }
      
      _isBypassing = false;
      notifyListeners();
      _bypassCompleter?.complete();
      
    } catch (e) {
      appDebugLog('🛡️ NewTV Bypass error: $e');
      _isBypassing = false;
      notifyListeners();
      if (_bypassCompleter != null && !_bypassCompleter!.isCompleted) {
        final completer = _bypassCompleter;
        _bypassCompleter = null;
        completer?.completeError(e);
      }
    }
  }
}
