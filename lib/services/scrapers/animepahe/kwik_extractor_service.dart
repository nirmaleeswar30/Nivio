import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nivio/core/debug_log.dart';

class KwikExtractionResult {
  final String m3u8Url;
  final String userAgent;
  final Map<String, String> cookies;

  KwikExtractionResult({
    required this.m3u8Url,
    required this.userAgent,
    required this.cookies,
  });
}

class KwikExtractorService {
  static Future<KwikExtractionResult?> extract(String kwikUrl) async {
    appDebugLog('🛡️ KwikExtractor: Initializing HeadlessInAppWebView for $kwikUrl');
    
    final completer = Completer<KwikExtractionResult?>();
    HeadlessInAppWebView? headlessWebView;
    Timer? timeoutTimer;
    
    String? extractedM3u8;
    const userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(kwikUrl)),
      initialSettings: InAppWebViewSettings(
        userAgent: userAgent,
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        useShouldInterceptRequest: false,
      ),
      onLoadStop: (controller, url) async {
        appDebugLog('🛡️ KwikExtractor: Page loaded: $url');
        if (url?.toString().contains('kwik.cx') == true) {
          // Poll for the source tag or packed script for up to 15 seconds
          for (int i = 0; i < 15; i++) {
            if (completer.isCompleted) return;
            await Future.delayed(const Duration(seconds: 1));
            try {
              final result = await controller.callAsyncJavaScript(functionBody: """
                try {
                  var src = document.querySelector('source')?.src;
                  if (src && src.includes('.m3u8')) return src;
                  
                  var response = await fetch(window.location.href);
                  var text = await response.text();
                  
                  var scriptMatch = text.match(/<script[^>]*>(eval\\(function\\(p,a,c,k,e,d\\)[\\s\\S]*?)<\\/script>/i);
                  if (!scriptMatch) {
                      scriptMatch = text.match(/(eval\\(function\\(p,a,c,k,e,d\\)[\\s\\S]*?\\.split\\('\\|'\\).*?\\)\\))/);
                  }
                  
                  if (scriptMatch) {
                     var unpacked = "";
                     var originalEval = window.eval;
                     window.eval = function(str) { unpacked = str; };
                     try { originalEval(scriptMatch[1] || scriptMatch[0]); } catch(e) { return "DEBUG_EVAL_ERROR: " + e.message; }
                     window.eval = originalEval;
                     if (unpacked) {
                        var urlMatch = unpacked.match(/(https:\\/\\/[^"']*?\\.(m3u8|mp4)[^"']*)/);
                        if (urlMatch) return urlMatch[1];
                     }
                  }
                  
                  var html = document.documentElement.outerHTML;
                  var hlsUrlMatch = html.match(/(https:\\/\\/[^"']*?\\.m3u8[^"']*)/);
                  if (hlsUrlMatch) return hlsUrlMatch[1];
                  
                  return "DEBUG_NO_MATCH: " + html.substring(0, 500);
                } catch(e) {
                  return "DEBUG_ERROR: " + e.message;
                }
              """);
              
              final val = result?.value;
              if (val != null) {
                if (val.toString().startsWith('http')) {
                  extractedM3u8 = val.toString();
                  appDebugLog('🛡️ KwikExtractor: Successfully extracted url: $extractedM3u8');
                  
                  // CRITICAL: Release hardware decoder lock
                  await controller.evaluateJavascript(source: """
                    document.querySelectorAll('video, audio').forEach(v => { 
                      v.pause(); 
                      v.removeAttribute('src'); 
                      v.load(); 
                    });
                  """);
                  
                  // Extract cookies
                  final cookieManager = CookieManager.instance();
                  final cookies = await cookieManager.getCookies(url: WebUri(kwikUrl));
                  final cookieMap = {for (var c in cookies) c.name: c.value.toString()};
                  
                  if (!completer.isCompleted) {
                    completer.complete(KwikExtractionResult(
                      m3u8Url: extractedM3u8!,
                      userAgent: userAgent,
                      cookies: cookieMap,
                    ));
                  }
                  break;
                } else if (i % 5 == 0) {
                  appDebugLog('🛡️ KwikExtractor: JS returned: $val');
                }
              }
            } catch (e) {
               if (i % 5 == 0) {
                 appDebugLog('🛡️ KwikExtractor: JS exception: $e');
               }
            }
          }
          
          if (!completer.isCompleted && extractedM3u8 == null) {
            appDebugLog('🛡️ KwikExtractor: Polling loop finished for this page load.');
          }
        }
      },
      onReceivedError: (controller, request, error) {
        appDebugLog('🛡️ KwikExtractor: WebView Error: ${error.description}');
      },
    );

    try {
      await headlessWebView.run();
      
      timeoutTimer = Timer(const Duration(seconds: 25), () {
        if (!completer.isCompleted) {
          appDebugLog('🛡️ KwikExtractor: Timeout reached!');
          completer.complete(null);
        }
      });
      
      final result = await completer.future;
      return result;
    } catch (e) {
      appDebugLog('🛡️ KwikExtractor: Exception during extraction: $e');
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return null;
    } finally {
      timeoutTimer?.cancel();
      await headlessWebView.dispose();
      appDebugLog('🛡️ KwikExtractor: WebView disposed.');
    }
  }
}
