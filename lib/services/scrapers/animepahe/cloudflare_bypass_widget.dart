import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/scrapers/animepahe/cloudflare_bypass_service.dart';

class CloudflareBypassWidget extends ConsumerStatefulWidget {
  const CloudflareBypassWidget({super.key});

  @override
  ConsumerState<CloudflareBypassWidget> createState() => _CloudflareBypassWidgetState();
}

class _CloudflareBypassWidgetState extends ConsumerState<CloudflareBypassWidget> {
  InAppWebViewController? _controller;
  bool _isDisposed = false;

  bool _showChallengeUI = false;

  @override
  void initState() {
    super.initState();
    // Register the widget controller back to the service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        ref.read(cloudflareBypassProvider).registerWebViewController(
          controllerGetter: () => _controller,
        );
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The WebView must stay mounted permanently in the background 
    // so it can act as a proxy for fetchViaWebView() to bypass TLS fingerprinting
    final bypassState = ref.watch(cloudflareBypassProvider);

    return Stack(
      children: [
        SizedBox(
          width: _showChallengeUI ? MediaQuery.of(context).size.width : 1,
          height: _showChallengeUI ? MediaQuery.of(context).size.height : 1,
          child: IgnorePointer(
            ignoring: !_showChallengeUI,
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri('https://animepahe.pw/')),
              initialSettings: InAppWebViewSettings(
                userAgent: bypassState.userAgent,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                transparentBackground: true,
                useWideViewPort: true,
                loadWithOverviewMode: true,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
                bypassState.registerWebViewController(controllerGetter: () => _controller);
                appDebugLog('🛡️ Physical InAppWebView created');
              },
              onReceivedError: (controller, request, error) {
                if (request.url.toString() == 'https://animepahe.pw/') {
                  appDebugLog('🛡️ WebView Error: ${error.description}');
                  controller.evaluateJavascript(source: "window.webViewError = true;");
                }
              },
              onLoadStart: (controller, url) async {
                appDebugLog('🛡️ Loading $url');
                await controller.evaluateJavascript(source: """
                  window.webViewError = false;
                  Object.defineProperty(navigator, 'webdriver', {
                    get: () => undefined
                  });
                  window.chrome = {
                    runtime: {}
                  };
                """);
              },
              onLoadStop: (controller, url) async {
                appDebugLog('🛡️ Load stopped for $url');
                
                if (url?.toString().startsWith('chrome-error://') == true) {
                  appDebugLog('🛡️ WebView encountered a chrome-error. Retrying in 5s...');
                  Future.delayed(const Duration(seconds: 5), () {
                    controller.loadUrl(urlRequest: URLRequest(url: WebUri('https://animepahe.pw/')));
                  });
                  return;
                }
                
                final hasError = await controller.evaluateJavascript(source: "window.webViewError === true");
                if (hasError == true) {
                   appDebugLog('🛡️ WebView had a network error. Retrying in 5s...');
                   Future.delayed(const Duration(seconds: 5), () {
                     controller.loadUrl(urlRequest: URLRequest(url: WebUri('https://animepahe.pw/')));
                   });
                   return;
                }
                
                // Check if we bypassed the challenge
                Future<void> checkBypassStatus() async {
                  if (!mounted) return;
                  
                  final html = await controller.evaluateJavascript(source: "document.documentElement.outerHTML");
                  if (html == null) return;
                  
                  final isChallenge = html.contains('cf-browser-verification') || html.contains('cf-turnstile') || html.contains('Just a moment...');
                  
                  if (!isChallenge) {
                    if (_showChallengeUI) setState(() => _showChallengeUI = false);
                    bypassState.onBypassSuccess(url?.toString() ?? 'https://animepahe.pw/');
                  } else {
                    appDebugLog('🛡️ Still waiting on Cloudflare challenge...');
                    
                    if (!_showChallengeUI) {
                      Future.delayed(const Duration(seconds: 4), () {
                        if (mounted && ref.read(cloudflareBypassProvider).isBypassing) {
                          appDebugLog('🛡️ Showing challenge to user');
                          setState(() => _showChallengeUI = true);
                        }
                      });
                    }
                    
                    // Poll again in 2 seconds
                    if (bypassState.isBypassing) {
                      Future.delayed(const Duration(seconds: 2), checkBypassStatus);
                    }
                  }
                }
                
                checkBypassStatus();
              },
            ),
          ),
        ),
        if (_showChallengeUI)
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Please tap the "Verify you are human" checkbox below so Animepahe can verify your device. This will only happen once.',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
