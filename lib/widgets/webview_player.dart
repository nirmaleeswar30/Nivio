import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// WebView-based player for embedding vidsrc iframe streams
class WebViewPlayer extends StatefulWidget {
  final String streamUrl;
  final String title;

  const WebViewPlayer({
    super.key,
    required this.streamUrl,
    required this.title,
  });

  @override
  State<WebViewPlayer> createState() => _WebViewPlayerState();
}

class _WebViewPlayerState extends State<WebViewPlayer> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    // Create HTML content with aggressive ad-blocking
    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        html, body {
            width: 100%;
            height: 100%;
            overflow: hidden;
            background-color: #000;
        }
        iframe {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            border: 0;
        }
    </style>
    <script>
        // Aggressive ad-blocking
        (function() {
            // Block all fetch/XHR requests globally
            const blockPatterns = [
                /ad[sx]?\\./i,
                /doubleclick/i,
                /googlesyndication/i,
                /googleadservices/i,
                /advertising/i,
                /analytics/i,
                /tracking/i,
                /banner/i,
                /popup/i,
                /sponsor/i,
                /promo/i
            ];
            
            const originalFetch = window.fetch;
            window.fetch = function(...args) {
                const url = String(args[0]);
                if (blockPatterns.some(pattern => pattern.test(url))) {
                    console.log('🚫 Blocked fetch:', url);
                    return Promise.reject(new Error('Blocked'));
                }
                return originalFetch.apply(this, args);
            };
            
            const originalOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(...args) {
                const url = String(args[1]);
                if (blockPatterns.some(pattern => pattern.test(url))) {
                    console.log('🚫 Blocked XHR:', url);
                    throw new Error('Blocked');
                }
                return originalOpen.apply(this, args);
            };
            
            // Aggressively remove modal overlays
            setInterval(() => {
                // Remove fixed/absolute positioned overlays
                document.querySelectorAll('*').forEach(el => {
                    const style = window.getComputedStyle(el);
                    if ((style.position === 'fixed' || style.position === 'absolute') &&
                        (parseInt(style.zIndex) > 1000 || 
                         el.className.toLowerCase().includes('modal') ||
                         el.className.toLowerCase().includes('popup') ||
                         el.className.toLowerCase().includes('overlay'))) {
                        el.remove();
                    }
                });
                
                // Enable scrolling if disabled
                document.body.style.overflow = 'auto';
                document.documentElement.style.overflow = 'auto';
            }, 300);
            
            // Block window.open popups
            window.open = function() {
                console.log('🚫 Blocked popup');
                return null;
            };
            
            // Prevent redirects
            let originalLocation = window.location.href;
            Object.defineProperty(window, 'location', {
                get: function() {
                    return {
                        href: originalLocation,
                        assign: () => {},
                        replace: () => {},
                        reload: () => {}
                    };
                }
            });

            // ===== AUTO-UNMUTE VIDEO =====
            function attemptUnmute() {
                const iframe = document.querySelector('iframe');
                if (iframe) {
                    try {
                        // Try to access iframe content (will fail due to CORS)
                        const iframeDoc = iframe.contentDocument || iframe.contentWindow.document;
                        const video = iframeDoc.querySelector('video');
                        if (video) {
                            video.muted = false;
                            video.volume = 1.0;
                            console.log('� Video unmuted successfully');
                        }
                    } catch (e) {
                        // CORS blocked - expected
                        console.log('⚠️ Cannot unmute due to CORS (normal)');
                    }
                }
            }
            
            // Try to unmute at different intervals
            setTimeout(attemptUnmute, 1000);
            setTimeout(attemptUnmute, 2000);
            setTimeout(attemptUnmute, 3000);
            setTimeout(attemptUnmute, 5000);
        })();
    </script>
</head>
<body>
    <iframe 
        src="${widget.streamUrl}"
        allowfullscreen
        allow="autoplay; fullscreen; picture-in-picture; encrypted-media"
        referrerpolicy="no-referrer"
        loading="lazy"
    ></iframe>
</body>
</html>
    ''';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _error = null;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            print('✅ WebView loaded successfully');
            
            // Inject aggressive modal/overlay remover
            _controller.runJavaScript('''
              // Remove ALL fixed/absolute overlays after page loads
              setTimeout(() => {
                document.querySelectorAll('*').forEach(el => {
                  const style = window.getComputedStyle(el);
                  const isOverlay = (
                    (style.position === 'fixed' || style.position === 'absolute') &&
                    parseInt(style.zIndex) > 100 &&
                    (style.width === '100%' || parseInt(style.width) > window.innerWidth * 0.8)
                  );
                  
                  if (isOverlay) {
                    console.log('Removing overlay:', el.className);
                    el.remove();
                  }
                });
                
                // Force enable scrolling
                document.body.style.overflow = 'auto';
                document.documentElement.style.overflow = 'auto';
              }, 2000);
              
              // Keep checking for new overlays
              setInterval(() => {
                document.querySelectorAll('[class*="modal"], [class*="popup"], [class*="overlay"]').forEach(el => {
                  el.remove();
                });
              }, 1000);
            ''');
          },
          onWebResourceError: (WebResourceError error) {
            // Ignore ORB errors completely - they're just cross-origin blocks
            if (error.description.contains('ERR_BLOCKED_BY_ORB')) {
              return; // Don't log these at all
            }
            
            // Only show critical errors
            if (error.errorType == WebResourceErrorType.hostLookup ||
                error.errorType == WebResourceErrorType.timeout ||
                error.errorType == WebResourceErrorType.connect) {
              setState(() {
                _error = 'Failed to load video player: ${error.description}';
                _isLoading = false;
              });
              print('❌ WebView critical error: ${error.description}');
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url.toLowerCase();
            
            // Block ad/tracking domains
            final blockedDomains = [
              'doubleclick',
              'googlesyndication',
              'googleadservices',
              'advertising',
              'ads.',
              '/ads/',
              'ad.',
              '/ad/',
              'analytics',
              'tracking',
              'telemetry',
            ];
            
            if (blockedDomains.any((domain) => url.contains(domain))) {
              print('🚫 Blocked navigation: $url');
              return NavigationDecision.prevent;
            }
            
            // Only allow vidlink.pro domain
            if (!url.contains('vidlink.pro') && !url.contains('vidsrc')) {
              print('🚫 Blocked external navigation: $url');
              return NavigationDecision.prevent;
            }
            
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(htmlContent, baseUrl: 'https://vidlink.pro');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // WebView container
        Container(
          color: Colors.black,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: WebViewWidget(controller: _controller),
          ),
        ),

        // Loading indicator
        if (_isLoading)
          Container(
            color: Colors.black,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Colors.red,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading player...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),

        // Error display
        if (_error != null && !_isLoading)
          Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Playback Error',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _isLoading = true;
                      });
                      _initializeWebView();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
