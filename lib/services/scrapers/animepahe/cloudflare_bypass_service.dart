import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/debug_log.dart';

final cloudflareBypassProvider = ChangeNotifierProvider<CloudflareBypassService>((ref) {
  return CloudflareBypassService();
});

class CloudflareBypassService extends ChangeNotifier {
  InAppWebViewController? Function()? _controllerGetter;
  
  String _userAgent = 'Mozilla/5.0 (Linux; Android 13; Pixel 7 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Mobile Safari/537.36';
  Map<String, String> _cookies = {};
  
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
    appDebugLog('🛡️ Cloudflare bypassed successfully!');
    await _extractCookies(url);
    
    _isBypassed = true;
    _isBypassing = false;
    Future.microtask(() => notifyListeners()); // Hide the WebView
    
    if (_bypassCompleter != null && !_bypassCompleter!.isCompleted) {
      _bypassCompleter!.complete();
    }
  }

  /// Proxies an HTTP GET request through the physical WebView to completely bypass Cloudflare's TLS fingerprinting
  Future<String?> fetchViaWebView(String url) async {
    final controller = _controllerGetter?.call();
    if (controller == null) return null;
    
    final result = await controller.callAsyncJavaScript(functionBody: """
      return new Promise((resolve) => {
        try {
          var xhr = new XMLHttpRequest();
          xhr.open('GET', url, true);
          xhr.setRequestHeader('Accept', 'application/json, text/javascript, */*; q=0.01');
          xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
          xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
              if (xhr.status === 200) {
                resolve(xhr.responseText);
              } else {
                resolve('ERROR: HTTP ' + xhr.status + ' - ' + xhr.responseText);
              }
            }
          };
          xhr.onerror = function() {
            resolve('ERROR: XHR failed');
          };
          xhr.send();
        } catch (e) {
          resolve('ERROR: ' + e.toString());
        }
      });
    """, arguments: {'url': url});
    
    return result?.value as String?;
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
