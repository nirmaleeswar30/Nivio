import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:dio/dio.dart';
import 'dart:convert';
final cloudflareBypassProvider = ChangeNotifierProvider<CloudflareBypassService>((ref) {
  return CloudflareBypassService();
});

class CloudflareBypassService extends ChangeNotifier {
  static final CloudflareBypassService instance = CloudflareBypassService._internal();
  factory CloudflareBypassService() => instance;
  CloudflareBypassService._internal();

  InAppWebViewController? Function()? _controllerGetter;
  
  String _userAgent = 'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  Map<String, String> _cookies = {};
  
  Map<String, String> get headers => {
    'User-Agent': _userAgent,
    'Cookie': cookieString,
  };
  
  bool _isBypassing = false;
  bool _isBypassed = false;
  String _bypassedUrl = 'https://animepahe.pw';
  Completer<void>? _bypassCompleter;
  
  String get userAgent => _userAgent;
  Map<String, String> get cookies => _cookies;
  bool get isReady => _isBypassed;
  bool get isBypassing => _isBypassing;
  String get bypassedUrl => _bypassedUrl;
  
  String get cookieString {
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void registerWebViewController({required InAppWebViewController? Function() controllerGetter}) {
    _controllerGetter = controllerGetter;
  }

  /// Initialize the background bypass service. Should be called on app startup.
  Future<void> init() async {
    if (_isBypassed || _isBypassing) return;
    appDebugLog('🛡️ Initializing CloudflareBypassService for Animepahe...');
    await _startBypass();
    
    // Schedule a refresh every 45 minutes to keep cookies warm
    Timer.periodic(const Duration(minutes: 45), (timer) {
      appDebugLog('🛡️ Background refresh of Cloudflare cookies...');
      _startBypass(forceRefresh: true);
    });
  }
  
  /// Manually force a refresh of the bypass
  Future<void> forceRefresh() async {
    appDebugLog('🛡️ Manual refresh of Cloudflare bypass requested...');
    await _startBypass(forceRefresh: true);
  }
  
  /// Wait until bypass is complete. Returns immediately if already bypassed.
  Future<void> waitForBypass() async {
    if (_isBypassed) return;
    if (_bypassCompleter != null) return _bypassCompleter!.future;
    
    // If not bypassed and not bypassing, start it
    if (!_isBypassing) {
      await _startBypass();
    }
    
    return _bypassCompleter?.future;
  }

  Future<void> _startBypass({bool forceRefresh = false}) async {
    if (_isBypassing && !forceRefresh) return;
    _isBypassing = true;
    _bypassCompleter = Completer<void>();
    Future.microtask(() => notifyListeners()); // Tell the Widget to render the WebView
    
    appDebugLog('🛡️ Triggering visible WebView widget to bypass Cloudflare on animepahe.pw...');
    
    try {
      CookieManager cookieManager = CookieManager.instance();
      if (forceRefresh) {
        await cookieManager.deleteAllCookies();
        _isBypassed = false;
      }
      
      final controller = _controllerGetter?.call();
      if (controller != null) {
         // Widget is already mounted, tell it to load
         await controller.loadUrl(urlRequest: URLRequest(url: WebUri('https://animepahe.pw/')));
      }
      
      // Safety timeout
      Future.delayed(const Duration(seconds: 30), () {
        if (_isBypassing && _bypassCompleter != null && !_bypassCompleter!.isCompleted) {
          appDebugLog('🛡️ Bypass timed out after 30 seconds. Will retry later.');
          _isBypassing = false;
          Future.microtask(() => notifyListeners()); // Hide the WebView
          
          final completer = _bypassCompleter;
          _bypassCompleter = null; // Clear so we can retry next time
          completer?.completeError(Exception('Cloudflare bypass timed out'));
        }
      });
      
    } catch (e) {
      appDebugLog('🛡️ Bypass error: $e');
      _isBypassing = false;
      Future.microtask(() => notifyListeners());
      
      if (_bypassCompleter != null && !_bypassCompleter!.isCompleted) {
        final completer = _bypassCompleter;
        _bypassCompleter = null;
        completer?.completeError(e);
      }
    }
  }

  Future<void> onBypassSuccess(String url) async {
    appDebugLog('🛡️ Cloudflare bypassed successfully! Resolved URL: $url');
    
    // Save the resolved origin (e.g. if it redirected to .ru)
    try {
      final uri = Uri.parse(url);
      _bypassedUrl = '${uri.scheme}://${uri.host}';
    } catch (_) {
      _bypassedUrl = 'https://animepahe.pw';
    }
    
    await _extractCookies(url);
    
    _isBypassed = true;
    _isBypassing = false;
    Future.microtask(() => notifyListeners()); // Hide the WebView
    
    if (_bypassCompleter != null && !_bypassCompleter!.isCompleted) {
      _bypassCompleter!.complete();
    }
  }

  Future<String?> fetchViaWebView(String url, {bool retry = true}) async {
    final controller = _controllerGetter?.call();
    if (controller == null) return null;
    
    try {
      appDebugLog('🛡️ Executing Fetch via WebView for: $url');
      final result = await controller.callAsyncJavaScript(functionBody: """
        return fetch(url, {
          headers: {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'X-Requested-With': 'XMLHttpRequest'
          }
        })
        .then(response => {
          if (!response.ok) {
            return response.text().then(text => 'ERROR: HTTP ' + response.status + ' - ' + text).catch(e => 'ERROR: HTTP ' + response.status);
          }
          return response.text();
        })
        .catch(err => {
          return 'ERROR: Fetch failed - ' + err.toString();
        });
      """, arguments: {'url': url}).timeout(const Duration(seconds: 20));
      
      final val = result?.value as String?;
      appDebugLog('🛡️ Fetch completed. Value starts with: ${(val)?.substring(0, (val)?.length.clamp(0, 50) ?? 0)}...');
      
      if (val != null && val.startsWith('ERROR: HTTP 403') && retry) {
         appDebugLog('🛡️ Got 403. Likely Cloudflare challenge. Forcing refresh...');
         await forceRefresh();
         await waitForBypass();
         return fetchViaWebView(url, retry: false);
      }
      
      return val;
    } catch (e) {
      appDebugLog('🛡️ fetchViaWebView threw an exception: $e');
      return null;
    }
  }

  Future<String?> getFinalUrlViaWebView(String url) async {
    final controller = _controllerGetter?.call();
    if (controller == null) return null;
    
    try {
      final result = await controller.callAsyncJavaScript(functionBody: """
        return fetch(url, {
          method: 'GET'
        })
        .then(response => {
          return response.url;
        })
        .catch(err => {
          return null;
        });
      """, arguments: {'url': url}).timeout(const Duration(seconds: 15));
      
      return result?.value as String?;
    } catch (e) {
      appDebugLog('🛡️ getFinalUrlViaWebView threw an exception: $e');
      return null;
    }
  }

  /// Secretly load the kwik player and extract the direct .mp4 or .m3u8 source URL
  Future<String?> extractKwikVideoUrl(String kwikUrl) async {
    final controller = _controllerGetter?.call();
    if (controller == null) return null;
    
    appDebugLog('🛡️ Extracting direct video link from Kwik embed: $kwikUrl');
    
    try {
      // Use Dio to fetch the Kwik embed page directly
      final dio = Dio(BaseOptions(
        headers: {
          'Referer': 'https://animepahe.pw/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        validateStatus: (status) => true,
      ));
      
      final response = await dio.get(kwikUrl);
      final text = response.data.toString();
      
      if (text.contains('p,a,c,k,e,d')) {
        appDebugLog('🛡️ Found packed script via Dio!');
        
        // Use a hidden WebView just to execute the JavaScript unpacker
        final result = await controller.evaluateJavascript(source: """
          (function() {
            try {
              var text = ${jsonEncode(text)};
              var unpacked = "";
              var originalEval = window.eval;
              window.eval = function(str) {
                  unpacked = str;
              };
              
              // Find the eval script block
              var scriptMatch = text.match(/<script>(eval\\(function\\(p,a,c,k,e,d\\)[\\s\\S]*?)<\\/script>/);
              if (scriptMatch) {
                 var scriptContent = scriptMatch[1].replace('<\\/script>', '');
                 try {
                     originalEval(scriptContent);
                 } catch(e) {
                     return "DEBUG_DUMP:Error evaling: " + e.message;
                 }
                 window.eval = originalEval;
                 
                 if (unpacked) {
                    var urlMatch = unpacked.match(/(https:\\/\\/[^"']*?\\.(m3u8|mp4)[^"']*)/);
                    if (urlMatch) {
                        return urlMatch[1];
                    }
                 }
              }
              return "DEBUG_DUMP:No match or unpack failed";
            } catch(e) {
              return "DEBUG_DUMP:Catch " + e.message;
            }
          })();
        """);
        
        if (result != null && result is String && result.isNotEmpty && result != 'null') {
          if (result.startsWith('http')) {
            appDebugLog('🛡️ Extracted video URL: $result');
            return result;
          } else {
            appDebugLog('🛡️ DEBUG JS: $result');
          }
        }
      } else {
        appDebugLog('🛡️ Dio response did not contain p,a,c,k,e,d script');
      }
      
      return null;
    } catch (e) {
      appDebugLog('🛡️ Bypass error extracting Kwik URL: $e');
      return null;
    }
  }

  Future<void> _extractCookies(String url) async {
    try {
      // Give CookieManager a moment to flush cookies from the WebView into its store
      await Future.delayed(const Duration(seconds: 2));
      
      CookieManager cookieManager = CookieManager.instance();
      final uri = WebUri(url);
      List<Cookie> cookies = await cookieManager.getCookies(url: uri);
      
      // Fallback domain if exact URL doesn't return anything
      if (cookies.isEmpty) {
        cookies = await cookieManager.getCookies(url: WebUri('https://.animepahe.pw'));
      }
      
      _cookies.clear();
      for (var cookie in cookies) {
        _cookies[cookie.name] = cookie.value.toString();
      }
      appDebugLog('🛡️ Extracted ${_cookies.length} cookies from $url');
      if (_cookies.containsKey('cf_clearance')) {
        appDebugLog('🛡️ cf_clearance successfully captured!');
      }
    } catch (e) {
      appDebugLog('🛡️ Error extracting cookies: $e');
    }
  }
}
