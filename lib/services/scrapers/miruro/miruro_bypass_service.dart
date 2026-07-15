import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nivio/core/debug_log.dart';

final miruroBypassProvider = ChangeNotifierProvider<MiruroBypassService>((ref) {
  return MiruroBypassService();
});

class MiruroBypassService extends ChangeNotifier {
  HeadlessInAppWebView? _headlessWebView;
  bool _isBypassing = false;
  bool _isBypassed = false;
  Completer<void>? _bypassCompleter;
  InAppWebViewController? _webViewController;
  
  bool get isReady => _isBypassed;
  bool get isBypassing => _isBypassing;
  
  Future<void> init() async {
    if (_isBypassed || _isBypassing) {
      if (_bypassCompleter != null) await _bypassCompleter!.future;
      return;
    }
    appDebugLog('🛡️ Initializing MiruroBypassService...');
    await _startBypass();
  }

  Future<void> forceRefresh() async {
    appDebugLog('🛡️ Manual refresh of Miruro bypass requested...');
    await _startBypass(forceRefresh: true);
  }
  
  Future<void> _startBypass({bool forceRefresh = false}) async {
    if (_isBypassing && !forceRefresh) return;
    
    _isBypassing = true;
    _isBypassed = false;
    _bypassCompleter = Completer<void>();
    notifyListeners();
    
    appDebugLog('🛡️ Triggering Miruro Cloudflare bypass via HeadlessInAppWebView...');
    
    try {
      if (_headlessWebView != null) {
        await _headlessWebView?.dispose();
        _headlessWebView = null;
      }
      
      _headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri('https://www.miruro.bz/')),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller;
        },
        onLoadStop: (controller, url) async {
          appDebugLog('🛡️ Miruro loaded URL: $url');
          // Cloudflare challenge might take a second or two.
          // Check if we are past the challenge by looking for a specific element or title.
          // Actually, since the homepage doesn't have a challenge, it might be instant.
          final title = await controller.getTitle();
          appDebugLog('🛡️ Miruro title: $title');
          
          if (title != null && !title.toLowerCase().contains('just a moment')) {
            if (!_isBypassed) {
              _isBypassed = true;
              _isBypassing = false;
              appDebugLog('🛡️ Miruro bypass successful!');
              notifyListeners();
              if (_bypassCompleter != null && !_bypassCompleter!.isCompleted) {
                _bypassCompleter!.complete();
              }
            }
          }
        },
        onLoadError: (controller, url, code, message) {
          appDebugLog('🛡️ Miruro load error: $message');
        },
      );
      
      await _headlessWebView!.run();
      
      // Wait for it to complete or timeout
      await _bypassCompleter!.future.timeout(const Duration(seconds: 15));
      
    } catch (e) {
      appDebugLog('🛡️ Miruro Bypass error: $e');
      _isBypassing = false;
      notifyListeners();
      if (_bypassCompleter != null && !_bypassCompleter!.isCompleted) {
        final completer = _bypassCompleter;
        _bypassCompleter = null;
        completer?.completeError(e);
      }
    }
  }

  Future<Map<String, dynamic>> executePipeRequest(String encodedReq) async {
    await init();
    
    if (_webViewController == null) {
      throw Exception('Miruro bypass not initialized properly');
    }
    
    final js = '''
      (async function() {
        try {
          const res = await fetch('https://www.miruro.bz/api/secure/pipe?e=$encodedReq', {
            method: 'GET',
            headers: {
              'Accept': '*/*',
              'Accept-Language': 'en-US,en;q=0.9',
            }
          });
          const text = await res.text();
          const obfuscated = res.headers.get('x-obfuscated');
          return JSON.stringify({
            status: res.status,
            body: text,
            obfuscated: obfuscated
          });
        } catch (e) {
          return JSON.stringify({ error: e.toString() });
        }
      })();
    ''';
    
    final resultStr = await _webViewController!.evaluateJavascript(source: js);
    if (resultStr == null) {
      throw Exception('Failed to execute JS in Miruro bypass');
    }
    
    final result = jsonDecode(resultStr);
    if (result['error'] != null) {
      throw Exception('JS fetch error: ${result["error"]}');
    }
    
    if (result['status'] != 200) {
      throw Exception('Pipe request failed with status: ${result["status"]}');
    }
    
    return result;
  }
  
  @override
  void dispose() {
    _headlessWebView?.dispose();
    super.dispose();
  }
}
