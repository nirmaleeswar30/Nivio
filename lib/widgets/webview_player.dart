import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nivio/core/theme.dart';

/// WebView-based player for embedding vidsrc iframe streams using flutter_inappwebview
class WebViewPlayer extends StatefulWidget {
  final String streamUrl;
  final String title;
  final Function(String event, double currentTime, double duration)? onPlayerEvent;

  const WebViewPlayer({
    super.key,
    required this.streamUrl,
    required this.title,
    this.onPlayerEvent,
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
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.streamUrl)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            useOnLoadResource: true,
            useShouldOverrideUrlLoading: true,
            useShouldInterceptRequest: true, // Enable request interception for ad blocking
            // userAgent: Use device default for proper mobile detection
            transparentBackground: true,
            // Additional settings for better ad blocking
            blockNetworkImage: false,
            blockNetworkLoads: false,
            cacheEnabled: false,
            clearCache: true,
            disableContextMenu: true,
            supportZoom: false,
            // Enable fullscreen support
            javaScriptCanOpenWindowsAutomatically: true,
            // Performance optimizations for smoother playback
            hardwareAcceleration: true,
            useWideViewPort: true,
            loadWithOverviewMode: true,
            layoutAlgorithm: LayoutAlgorithm.NORMAL,
          ),
          onWebViewCreated: (controller) {
            _webViewController = controller;
            print('🌐 WebView created for: ${widget.streamUrl}');
            
            // Add JavaScript handler to receive player events from vidsrc.cc
            controller.addJavaScriptHandler(
              handlerName: 'playerEvent',
              callback: (args) {
                if (args.isNotEmpty) {
                  final data = args[0] as Map<String, dynamic>;
                  final event = data['event'] as String?;
                  final currentTime = (data['currentTime'] as num?)?.toDouble() ?? 0.0;
                  final duration = (data['duration'] as num?)?.toDouble() ?? 0.0;
                  
                  if (event != null && widget.onPlayerEvent != null) {
                    widget.onPlayerEvent!(event, currentTime, duration);
                    print('📺 Player event: $event at ${currentTime.toInt()}s / ${duration.toInt()}s');
                  }
                }
              },
            );
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
            
            // Inject ultra-aggressive ad-blocking
            await controller.evaluateJavascript(source: '''
              (function() {
                console.log('🛡️ Ultra ad-blocking activated');
                
                // Block ALL popups and redirects
                window.open = function() { console.log('🚫 Blocked popup'); return null; };
                window.alert = function() { return true; };
                window.confirm = function() { return true; };
                window.prompt = function() { return null; };
                
                // Prevent location changes (safer approach)
                try {
                  let currentHref = window.location.href;
                  let descriptor = Object.getOwnPropertyDescriptor(window.location, 'href');
                  if (descriptor && descriptor.configurable) {
                    Object.defineProperty(window.location, 'href', {
                      set: function(val) {
                        if (val !== currentHref && !val.includes('vidsrc')) {
                          console.log('🚫 Blocked redirect to:', val);
                          return;
                        }
                        currentHref = val;
                      },
                      get: function() { return currentHref; }
                    });
                  }
                } catch(e) {
                  // If redefine fails, just intercept assign
                  Object.defineProperty(window.location, 'assign', {
                    value: function(url) {
                      if (!url.includes('vidsrc')) {
                        console.log('🚫 Blocked location.assign:', url);
                        return;
                      }
                    }
                  });
                  Object.defineProperty(window.location, 'replace', {
                    value: function(url) {
                      if (!url.includes('vidsrc')) {
                        console.log('🚫 Blocked location.replace:', url);
                        return;
                      }
                    }
                  });
                }
                
                // Aggressive ad element removal
                function removeAds() {
                  try {
                    // Expanded selector list
                    const selectors = [
                      '[class*="ad-"]', '[class*="ads-"]', '[class*="advert"]', '[class*="banner"]',
                      '[id*="ad-"]', '[id*="ads-"]', '[id*="advert"]', '[id*="banner"]',
                      '[class*="popup"]', '[id*="popup"]', '[class*="modal"]:not([class*="player"])',
                      '[class*="overlay"]:not([class*="player"])', '[id*="overlay"]:not([id*="player"])',
                      'ins.adsbygoogle', '.advertisement', '.ad-container', '.ad-wrapper',
                      '[data-ad-slot]', '[data-ad-client]', '[data-ad-unit]',
                      'iframe[src*="doubleclick"]', 'iframe[src*="googlesyndication"]',
                      'iframe[src*="adservice"]', 'div[style*="z-index: 2147483647"]',
                      'div[style*="position: fixed"][style*="top: 0"]'
                    ];
                    
                    selectors.forEach(sel => {
                      document.querySelectorAll(sel).forEach(el => {
                        const isPlayer = el.closest('[class*="player"]') || 
                                        el.closest('[class*="video"]') ||
                                        el.closest('[class*="episode"]') ||
                                        el.closest('[id*="player"]') ||
                                        el.id === 'vidsrc-player';
                        if (!isPlayer) {
                          el.remove();
                          console.log('🗑️ Removed ad element:', sel);
                        }
                      });
                    });
                    
                    // Remove suspicious fixed/absolute positioned overlays
                    document.querySelectorAll('div, section').forEach(el => {
                      const style = window.getComputedStyle(el);
                      const zIndex = parseInt(style.zIndex) || 0;
                      const position = style.position;
                      
                      if ((position === 'fixed' || position === 'absolute') && zIndex > 999999) {
                        const isPlayer = el.closest('[class*="player"]') || 
                                        el.closest('[id*="player"]') ||
                                        el.querySelector('video') ||
                                        el.querySelector('[class*="episode"]');
                        if (!isPlayer && el.offsetHeight > 100 && el.offsetWidth > 100) {
                          el.remove();
                          console.log('🗑️ Removed suspicious overlay');
                        }
                      }
                    });
                    
                    // Force enable interactions
                    document.body.style.overflow = 'auto !important';
                    document.body.style.pointerEvents = 'auto !important';
                    document.documentElement.style.overflow = 'auto !important';
                  } catch(e) {
                    console.error('Error removing ads:', e);
                  }
                }
                
                // Run immediately and repeatedly
                removeAds();
                setInterval(removeAds, 500);
                
                // MutationObserver to catch dynamically added ads
                const observer = new MutationObserver(removeAds);
                observer.observe(document.body, { childList: true, subtree: true });
                
                // Block fetch/XHR to ad servers
                const originalFetch = window.fetch;
                window.fetch = function() {
                  const url = String(arguments[0]);
                  const blockPatterns = ['doubleclick', 'googlesyndication', 'google-analytics', 
                                        'googletagmanager', 'adservice', 'adsystem', 'facebook.com/tr'];
                  if (blockPatterns.some(p => url.toLowerCase().includes(p))) {
                    console.log('🚫 Blocked fetch:', url);
                    return Promise.reject(new Error('Blocked'));
                  }
                  return originalFetch.apply(this, arguments);
                };
                
                const originalXHR = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function() {
                  const url = String(arguments[1]);
                  const blockPatterns = ['doubleclick', 'googlesyndication', 'adservice'];
                  if (blockPatterns.some(p => url.toLowerCase().includes(p))) {
                    console.log('🚫 Blocked XHR:', url);
                    throw new Error('Blocked');
                  }
                  return originalXHR.apply(this, arguments);
                };
                
                console.log('✅ Ultra ad-blocking initialized');
                
                // Listen for VidSrc player events via postMessage
                window.addEventListener('message', function(event) {
                  if (event.origin !== 'https://vidsrc.cc') return;
                  
                  if (event.data && event.data.type === 'PLAYER_EVENT') {
                    const eventData = event.data.data;
                    console.log('📺 VidSrc event:', eventData.event, 'at', eventData.currentTime, '/', eventData.duration);
                    
                    // Send to Flutter via JavaScript handler
                    if (window.flutter_inappwebview) {
                      window.flutter_inappwebview.callHandler('playerEvent', {
                        event: eventData.event,
                        currentTime: eventData.currentTime || 0,
                        duration: eventData.duration || 0,
                        tmdbId: eventData.tmdbId,
                        mediaType: eventData.mediaType,
                        season: eventData.season,
                        episode: eventData.episode
                      });
                    }
                  }
                });
                
                console.log('✅ VidSrc player event listener initialized');
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
            
            // Comprehensive ad blocking patterns
            final adPatterns = [
              // Google ads
              'doubleclick', 'googlesyndication', 'googleadservices', 'google-analytics',
              'googletagmanager', 'googletagservices', 'pagead',
              // Facebook
              'facebook.com/tr', 'facebook.net', 'connect.facebook',
              // General ad keywords
              'ad.', 'ads.', 'advert', 'advertising', 'advertisement',
              '/ad/', '/ads/', 'adserver', 'adservice', 'adsystem', 'adtech',
              // Analytics & tracking
              'analytics', 'tracking', 'tracker', 'track.', 'telemetry',
              // Ad networks
              'taboola', 'outbrain', 'revcontent', 'mgid', 'criteo',
              'pubmatic', 'openx', 'rubiconproject', 'smartadserver',
              'appnexus', 'adnxs', 'moatads', 'adsafeprotected',
              // Popup/redirect networks
              'exoclick', 'propellerads', 'popcash', 'popads', 'pop-ad',
              'clickadu', 'hilltopads', 'adsterra', 'popunder',
              // Banner & sponsor
              'banner', 'sponsor', 'promo.',
              // Video ad platforms
              'imasdk', 'doubleclick.net/instream',
              // Specific ad script domains
              'adform', 'advertising.com', 'adnxs.com', 'adsrvr.org',
            ];
            
            // Check if URL contains any ad pattern
            for (final pattern in adPatterns) {
              if (url.contains(pattern)) {
                print('🚫 Blocked: $url');
                return null; // Block the request
              }
            }
            
            return null; // Allow
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url;
            
            if (url != null) {
              final urlString = url.toString();
              final urlStringLower = urlString.toLowerCase();
              final scheme = url.scheme.toLowerCase();
              final host = url.host.toLowerCase();
              
              // BLOCK non-HTTP/HTTPS schemes (app deep links, malware redirects)
              if (scheme != 'http' && scheme != 'https') {
                print('🚫 Blocked non-HTTP scheme: $urlString');
                return NavigationActionPolicy.CANCEL;
              }
              
              // Block specific ad/malware domains
              final blockedDomains = [
                'zrlqm.com', 'enalibaba.com', 'taobao.com', 'alibaba.com',
                'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
                'exoclick.com', 'propellerads.com', 'popcash.net', 'popads.net',
                'clickadu.com', 'adsterra.com', 'hilltopads.net', 'adcash.com',
                'facebook.com', 'facebook.net', 'fbcdn.net',
                'outbrain.com', 'taboola.com', 'revcontent.com', 'mgid.com',
              ];
              
              for (final domain in blockedDomains) {
                if (host.contains(domain)) {
                  print('🚫 Blocked domain: $urlString');
                  return NavigationActionPolicy.CANCEL;
                }
              }
              
              // Block URLs with ad/tracking patterns
              final blockedPatterns = [
                '/ad/', '/ads/', '/advert', '/banner', '/popup',
                '/track/', '/tracker', '/analytics', '/telemetry',
                '?c=', '&c=', // Tracking campaign parameters seen in logs
                'click.', 'clk.', 'redirect', 'redir',
              ];
              
              for (final pattern in blockedPatterns) {
                if (urlStringLower.contains(pattern) && !host.contains('vidsrc')) {
                  print('🚫 Blocked pattern "$pattern": $urlString');
                  return NavigationActionPolicy.CANCEL;
                }
              }
              
              // Only allow trusted streaming domains (prevent cross-domain redirects)
              final trustedDomains = [
                'vidsrc.cc', 'vidsrc.to', 'vidsrc.xyz', 'vidsrc.me',
                'vidlink.pro', 'vidlink.org',
              ];
              
              final isTrustedDomain = trustedDomains.any((trusted) => host.contains(trusted));
              
              if (!isTrustedDomain) {
                print('🚫 Blocked untrusted domain: $urlString');
                return NavigationActionPolicy.CANCEL;
              }
            }
            
            return NavigationActionPolicy.ALLOW;
          },
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
