import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nivio/core/theme.dart';

/// WebView-based player for embedding vidsrc iframe streams using flutter_inappwebview
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
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.streamUrl)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            useOnLoadResource: true,
            useShouldOverrideUrlLoading: true,
            useShouldInterceptRequest: true, // Enable request interception for ad blocking
            userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            transparentBackground: true,
            // Additional settings for better ad blocking
            blockNetworkImage: false,
            blockNetworkLoads: false,
            cacheEnabled: false,
            clearCache: true,
            disableContextMenu: true,
            supportZoom: false,
          ),
          onWebViewCreated: (controller) {
            _webViewController = controller;
            print('🌐 WebView created for: ${widget.streamUrl}');
          },
          onLoadStart: (controller, url) {
            setState(() {
              _isLoading = true;
            });
            print('🔄 Loading started: $url');
          },
          onLoadStop: (controller, url) async {
            setState(() {
              _isLoading = false;
            });
            print('✅ Loading completed: $url');
            
            // Inject ultra aggressive ad-blocking and overlay removal script
            await controller.evaluateJavascript(source: '''
              (function() {
                console.log('🛡️ Ultra ad-blocking activated');
                
                // Block ALL popups and redirects
                window.open = function() {
                  console.log('🚫 Blocked popup');
                  return null;
                };
                
                // Override alert, confirm, prompt
                window.alert = function() { return true; };
                window.confirm = function() { return true; };
                window.prompt = function() { return null; };
                
                // Block location changes
                const originalLocation = window.location.href;
                Object.defineProperty(window, 'location', {
                  get: function() {
                    return {
                      href: originalLocation,
                      assign: function() { console.log('🚫 Blocked redirect'); },
                      replace: function() { console.log('🚫 Blocked redirect'); },
                      reload: function() { console.log('🚫 Blocked reload'); }
                    };
                  }
                });
                
                // Aggressive element removal
                function removeAds() {
                  try {
                    // Remove by class/id patterns
                    const selectors = [
                      '[class*="ad-"]', '[class*="ads-"]', '[class*="advert"]',
                      '[id*="ad-"]', '[id*="ads-"]', '[id*="advert"]',
                      '[class*="banner"]', '[id*="banner"]',
                      '[class*="popup"]', '[id*="popup"]',
                      '[class*="modal"]', '[id*="modal"]',
                      '[class*="overlay"]', '[id*="overlay"]',
                      '[class*="sponsor"]', '[id*="sponsor"]',
                      'iframe[src*="ad"]', 'iframe[src*="banner"]',
                      'iframe[src*="popup"]', 'iframe[src*="doubleclick"]',
                      'ins.adsbygoogle', '.advertisement', '.ad-container',
                      '[data-ad-slot]', '[data-ad-client]'
                    ];
                    
                    selectors.forEach(function(selector) {
                      try {
                        document.querySelectorAll(selector).forEach(function(el) {
                          el.remove();
                        });
                      } catch(e) {}
                    });
                    
                    // Remove elements with position fixed/absolute and high z-index
                    document.querySelectorAll('*').forEach(function(el) {
                      try {
                        const style = window.getComputedStyle(el);
                        const zIndex = parseInt(style.zIndex);
                        const position = style.position;
                        
                        if ((position === 'fixed' || position === 'absolute') && 
                            zIndex > 1000 && 
                            (el.offsetWidth > window.innerWidth * 0.5 || 
                             el.offsetHeight > window.innerHeight * 0.5)) {
                          el.remove();
                        }
                      } catch(e) {}
                    });
                    
                    // Force enable scrolling
                    document.body.style.overflow = 'auto !important';
                    document.documentElement.style.overflow = 'auto !important';
                    document.body.style.pointerEvents = 'auto';
                  } catch(e) {
                    console.error('Error removing ads:', e);
                  }
                }
                
                // Run immediately
                removeAds();
                
                // Run repeatedly to catch dynamically loaded ads
                setInterval(removeAds, 300);
                
                // Observer for DOM changes
                const observer = new MutationObserver(removeAds);
                observer.observe(document.body, {
                  childList: true,
                  subtree: true
                });
                
                // Block fetch requests to ad servers
                const originalFetch = window.fetch;
                window.fetch = function() {
                  const url = arguments[0];
                  if (typeof url === 'string') {
                    const adPatterns = ['ad', 'analytics', 'tracking', 'doubleclick', 'googlesyndication'];
                    if (adPatterns.some(pattern => url.toLowerCase().includes(pattern))) {
                      console.log('🚫 Blocked fetch:', url);
                      return Promise.reject(new Error('Blocked'));
                    }
                  }
                  return originalFetch.apply(this, arguments);
                };
                
                // Block XHR requests to ad servers
                const originalXHR = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function() {
                  const url = arguments[1];
                  if (typeof url === 'string') {
                    const adPatterns = ['ad', 'analytics', 'tracking', 'doubleclick', 'googlesyndication'];
                    if (adPatterns.some(pattern => url.toLowerCase().includes(pattern))) {
                      console.log('🚫 Blocked XHR:', url);
                      throw new Error('Blocked');
                    }
                  }
                  return originalXHR.apply(this, arguments);
                };
                
                console.log('✅ Ad-blocking fully initialized');
              })();
            ''');
          },
          onProgressChanged: (controller, progress) {
            setState(() {
              _progress = progress / 100;
            });
          },
          onReceivedError: (controller, request, error) {
            print('❌ WebView error: ${error.description}');
          },
          shouldInterceptRequest: (controller, request) async {
            final url = request.url.toString().toLowerCase();
            
            // Ultra aggressive ad blocking - block any suspicious domains
            final adPatterns = [
              'ad', 'ads', 'advert', 'advertising', 'advertisement',
              'doubleclick', 'googlesyndication', 'googleadservices',
              'google-analytics', 'googletagmanager', 'googletagservices',
              'facebook.com/tr', 'facebook.net',
              'analytics', 'tracking', 'tracker', 'track',
              'banner', 'popup', 'popunder', 'sponsor',
              'pagead', 'adservice', 'adserver', 'adsystem',
              'taboola', 'outbrain', 'revcontent', 'mgid',
              'criteo', 'pubmatic', 'openx', 'rubiconproject',
              'smartadserver', 'appnexus', 'adnxs',
              'exoclick', 'propellerads', 'popcash', 'popads',
              'clickadu', 'hilltopads', 'adsterra',
            ];
            
            // Check if URL contains any ad pattern
            for (final pattern in adPatterns) {
              if (url.contains(pattern)) {
                print('🚫 Blocked request: $url');
                return null; // Block the request
              }
            }
            
            return null; // Allow the request to proceed normally
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url;
            
            // Block navigation to ad domains
            if (url != null) {
              final urlString = url.toString().toLowerCase();
              final adDomains = [
                'ad', 'ads', 'doubleclick', 'googlesyndication',
                'advertising', 'popup', 'banner', 'sponsor',
                'analytics', 'tracking', 'facebook.com/tr',
                'exoclick', 'propeller', 'popcash', 'popads',
                'clickadu', 'adsterra',
              ];
              
              for (final domain in adDomains) {
                if (urlString.contains(domain)) {
                  print('🚫 Blocked navigation to: $urlString');
                  return NavigationActionPolicy.CANCEL;
                }
              }
            }
            
            return NavigationActionPolicy.ALLOW;
          },
            ),
          ),
        ),
        
        // Loading indicator
        if (_isLoading)
          Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: NivioTheme.netflixRed,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading player...',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (_progress > 0 && _progress < 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${(_progress * 100).toInt()}%',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
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
    _webViewController = null;
    super.dispose();
  }
}
