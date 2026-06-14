import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/scrapers/newtv/newtv_bypass_service.dart';

class NewTvBypassWidget extends ConsumerStatefulWidget {
  const NewTvBypassWidget({super.key});

  @override
  ConsumerState<NewTvBypassWidget> createState() => _NewTvBypassWidgetState();
}

class _NewTvBypassWidgetState extends ConsumerState<NewTvBypassWidget> {
  InAppWebViewController? _controller;
  bool _isDisposed = false;

  bool _mountWebView = false;
  String _currentUrl = 'https://net11.cc/';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        ref.read(newTvBypassProvider).registerWebViewController(
          controllerGetter: () => _controller,
        );
      }
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _mountWebView = true);
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
    final bypassState = ref.watch(newTvBypassProvider);

    return Stack(
      children: [
        if (_mountWebView)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !bypassState.isBypassing,
              child: AnimatedOpacity(
                opacity: bypassState.isBypassing ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: SafeArea(
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri('https://net11.cc/')),
                    initialSettings: InAppWebViewSettings(
                      userAgent: bypassState.userAgent,
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      transparentBackground: false,
                      useWideViewPort: true,
                      loadWithOverviewMode: true,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      bypassState.registerWebViewController(controllerGetter: () => _controller);
                      appDebugLog('🛡️ NewTV InAppWebView created');
                    },
                    onLoadStart: (controller, url) {
                      appDebugLog('🛡️ NewTV Loading $url');
                      if (url != null && mounted) {
                        setState(() {
                          _currentUrl = url.toString();
                        });
                      }
                    },
                    onLoadStop: (controller, url) async {
                      appDebugLog('🛡️ NewTV Load stopped for $url');
                      if (url != null && mounted) {
                        setState(() {
                          _currentUrl = url.toString();
                        });
                        
                        Future<void> checkBypassStatus() async {
                          if (!mounted) return;
                          
                          final html = await controller.evaluateJavascript(source: "document.documentElement.outerHTML");
                          if (html == null) return;
                          
                          final isChallenge = html.contains('cf-browser-verification') || html.contains('cf-turnstile') || html.contains('Just a moment...');
                          
                          if (!isChallenge) {
                            if (bypassState.isBypassing) {
                              bypassState.onBypassSuccess(_currentUrl);
                            }
                          } else {
                            appDebugLog('🛡️ Still waiting on NewTV Cloudflare challenge...');
                            if (bypassState.isBypassing) {
                              Future.delayed(const Duration(seconds: 2), checkBypassStatus);
                            }
                          }
                        }
                        
                        checkBypassStatus();
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        if (bypassState.isBypassing)
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
                  'Please tap the "Verify you are human" checkbox below so NewTV can verify your device. This will only happen once.',
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

