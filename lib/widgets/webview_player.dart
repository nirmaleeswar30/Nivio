import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nivio/core/theme.dart';
// unused

/// WebView-based player for embedding streams using flutter_inappwebview
class WebViewPlayer extends StatefulWidget {
  final String streamUrl;
  final String? title;
  final Map<String, String>? headers;
  final Function(String event, double currentTime, double duration)? onPlayerEvent;
  final Function(int season, int episode)? onEpisodeChanged;
  final Function(String errorMessage)? onError;
  final VoidCallback? onEnterFullscreen;
  final VoidCallback? onExitFullscreen;
  final VoidCallback? onShowEpisodesRequested;

  const WebViewPlayer({
    super.key,
    required this.streamUrl,
    this.headers,
    this.title,
    this.onEpisodeChanged,
    this.onPlayerEvent,
    this.onError,
    this.onEnterFullscreen,
    this.onExitFullscreen,
    this.onShowEpisodesRequested,
  });

  @override
  State<WebViewPlayer> createState() => _WebViewPlayerState();
}

class _WebViewPlayerState extends State<WebViewPlayer> {
  bool _isLoading = true;
  double _progress = 0;
  int _internalErrorCount = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(widget.streamUrl),
            headers: widget.headers,
          ),
          initialUserScripts: UnmodifiableListView([
            UserScript(
              source: """
                // 1. Clever popup mocking to bypass anti-adblock crash loops
                var fakeWindow = {
                  close: function(){}, 
                  focus: function(){}, 
                  blur: function(){}, 
                  postMessage: function(){}, 
                  document: document, 
                  location: { href: '', reload: function(){} } 
                };
                window.open = function() { 
                  console.log('BLOCKED POPUP'); 
                  return fakeWindow; 
                };

                // 2. Play/Pause Promise Synchronizer to prevent AbortError console flood & crashes
                var originalPlay = HTMLMediaElement.prototype.play;
                var originalPause = HTMLMediaElement.prototype.pause;

                HTMLMediaElement.prototype.play = function() {
                    var self = this;
                    if (self._isPlayPending) return Promise.resolve();
                    self._isPlayPending = true;
                    
                    var p = originalPlay.apply(this, arguments);
                    if (p && p.then) {
                        p.then(function() { 
                            self._isPlayPending = false; 
                            if (self._wantsPause) {
                                self._wantsPause = false;
                                originalPause.apply(self);
                            }
                        }).catch(function(e) { 
                            self._isPlayPending = false; 
                            self._wantsPause = false;
                        });
                    } else {
                        self._isPlayPending = false;
                    }
                    return p || Promise.resolve();
                };

                HTMLMediaElement.prototype.pause = function() {
                    var self = this;
                    if (self._isPlayPending) {
                        // Delay the pause until play() resolves to prevent AbortError
                        self._wantsPause = true;
                        return;
                    }
                    originalPause.apply(this, arguments);
                };
                
                // 3. Mock document.referrer for anti-hotlinking bypass
                Object.defineProperty(document, 'referrer', {get : function(){ return "https://7reels.cc/"; }});
                
                // 3. Intercept ad clicks that redirect the main window
                document.addEventListener('click', function(e) {
                  const target = e.target.closest('a');
                  if (target && target.href) {
                    // If it's a known ad network redirect
                    if (target.href.includes('offertomynewbid') || target.href.includes('zrlqm')) {
                      e.preventDefault();
                      e.stopPropagation();
                      return false;
                    }
                  }
                }, true);
                
                // 4. TimeUpdate Sync Hook
                setInterval(function() {
                    var vids = document.getElementsByTagName('video');
                    if (vids && vids.length > 0) {
                        var video = vids[0];
                        var duration = video.duration || 0;
                        var currentTime = video.currentTime || 0;
                        if (!isNaN(duration) && duration > 0) {
                            window.flutter_inappwebview.callHandler('TimeUpdate', currentTime, duration);
                        }
                    }
                }, 1000);
              """,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: false,
            ),
            UserScript(
              source: """
                setInterval(function() {
                   var fs = document.fullscreenElement || document.webkitFullscreenElement || document.mozFullScreenElement || document.msFullscreenElement;
                   var btn = document.getElementById('nivio-fs-btn');
                   
                   if (fs) {
                       var target = fs;
                       if (fs.tagName && fs.tagName.toLowerCase() === 'video') {
                           target = fs.parentNode || document.body;
                       }
                       
                       if (!btn) {
                           btn = document.createElement('div');
                           btn.id = 'nivio-fs-btn';
                           btn.innerHTML = '&#9776; Episodes';
                           btn.style.position = 'fixed';
                           btn.style.top = '20px';
                           btn.style.right = '20px';
                           btn.style.zIndex = '2147483647';
                           btn.style.backgroundColor = 'rgba(0,0,0,0.8)';
                           btn.style.color = 'white';
                           btn.style.padding = '10px 16px';
                           btn.style.borderRadius = '8px';
                           btn.style.fontFamily = 'sans-serif';
                           btn.style.fontWeight = 'bold';
                           btn.style.fontSize = '14px';
                           btn.style.cursor = 'pointer';
                           btn.style.boxShadow = '0 4px 6px rgba(0,0,0,0.5)';
                           btn.style.pointerEvents = 'auto';
                           btn.style.transition = 'opacity 0.3s ease-in-out';
                           btn.onclick = function(e) {
                               e.preventDefault();
                               e.stopPropagation();
                               window.flutter_inappwebview.callHandler('ShowEpisodes', 'click');
                           };
                           
                           // Auto-hide logic
                           var hideTimeout;
                           var wakeUp = function() {
                               if (btn.style.display !== 'none') {
                                   btn.style.opacity = '1';
                                   clearTimeout(hideTimeout);
                                   hideTimeout = setTimeout(function() {
                                       btn.style.opacity = '0';
                                   }, 2500);
                               }
                           };
                           document.addEventListener('mousemove', wakeUp, true);
                           document.addEventListener('touchstart', wakeUp, true);
                           btn.wakeUp = wakeUp;
                       }
                       
                       if (btn.parentNode !== target) {
                           target.appendChild(btn);
                       }
                       if (btn.style.display === 'none') {
                           btn.style.display = 'block';
                           if (btn.wakeUp) btn.wakeUp();
                       }
                   } else {
                       if (btn) {
                           btn.style.display = 'none';
                       }
                   }
                }, 500);
              """,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
              forMainFrameOnly: false,
            ),
          ]),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            hardwareAcceleration: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            useOnLoadResource: true,
            useShouldOverrideUrlLoading: true,
            useShouldInterceptRequest: true,
            supportMultipleWindows: false, // BLOCK ALL POPUPS
            javaScriptCanOpenWindowsAutomatically: false,
            userAgent: 'Mozilla/5.0 (Linux; Android 13; SM-S901B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36',
            transparentBackground: true,
            blockNetworkImage: false,
            blockNetworkLoads: false,
            cacheEnabled: false,
          ),
          onCreateWindow: (controller, createWindowAction) async {
            // Drop any window creation requests (popups) into the void
            return false;
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url;
            if (url != null) {
              final urlString = url.toString().toLowerCase();
              final host = url.host.toLowerCase();
              
              // If the main frame tries to navigate AWAY from the stream URL
              if (navigationAction.isForMainFrame) {
                 final isMainProvider = host.contains('vidsrc') || 
                                        host.contains('vidcore') || 
                                        host.contains('vidup') ||
                                        host.contains('videasy') ||
                                        host.contains('vidplus');
                 
                 if (!isMainProvider && !urlString.contains('google.com/recaptcha')) {
                    debugPrint('Ã°Å¸Å¡Â« Blocked top-level redirect to: \$urlString');
                    return NavigationActionPolicy.CANCEL;
                 } else if (isMainProvider && widget.onEpisodeChanged != null) {
                    // Try to parse season and episode from URL: /tv/id/season/episode
                    final RegExp regex = RegExp(r'/tv/[^/]+/(\d+)/(\d+)');
                    final match = regex.firstMatch(urlString);
                    if (match != null) {
                      final season = int.tryParse(match.group(1)!);
                      final episode = int.tryParse(match.group(2)!);
                      if (season != null && episode != null) {
                        widget.onEpisodeChanged!(season, episode);
                      }
                    }
                 }
              }

              // Known aggressive ad domains seen in logs
              final blockedDomains = [
                'offertomynewbid.com',
                'zrlqm.com',
                'popcash.net',
                'popads.net',
                'clickadu.com',
                'adsterra.com',
              ];

              for (final domain in blockedDomains) {
                if (host.contains(domain)) {
                  debugPrint('Ã°Å¸Å¡Â« Blocked domain: \$urlString');
                  return NavigationActionPolicy.CANCEL;
                }
              }
            }
            return NavigationActionPolicy.ALLOW;
          },
          shouldInterceptRequest: (controller, request) async {
            final url = request.url.toString().toLowerCase();
            final adPatterns = [
              'google-analytics', 'googletagmanager', 'pagead', 'doubleclick',
              'popcash', 'popads', 'adsterra', 'offertomynewbid',
              '/ad/', '/ads/', 'banner', 'tracker', 'telemetry'
            ];
            for (final pattern in adPatterns) {
              if (url.contains(pattern)) {
                return WebResourceResponse(
                  contentType: 'text/plain',
                  data: Uint8List.fromList([]), // Empty response
                  statusCode: 200,
                  reasonPhrase: 'OK',
                );
              }
            }
            return null;
          },
          onLoadStart: (controller, url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _progress = 0;
              });
            }
          },
          onEnterFullscreen: (controller) async {
            widget.onEnterFullscreen?.call();
          },
          onExitFullscreen: (controller) async {
            widget.onExitFullscreen?.call();
          },
          onWebViewCreated: (controller) {
            controller.addJavaScriptHandler(
              handlerName: 'VideoErrorDetector',
              callback: (args) {
                if (!mounted) return;
                final message = args.isNotEmpty ? args[0].toString() : "Unknown Body Error";
                debugPrint("Ã°Å¸Å¡Â¨ JS Detector found error: \$message");
                widget.onError?.call(message);
              },
            );
            controller.addJavaScriptHandler(
              handlerName: 'ShowEpisodes',
              callback: (args) async {
                if (!mounted) return;
                debugPrint("Ã°Å¸Å¡Â¨ Requesting episodes from Fullscreen!");
                await controller.evaluateJavascript(source: "if(document.exitFullscreen) document.exitFullscreen(); else if(document.webkitExitFullscreen) document.webkitExitFullscreen();");
                widget.onShowEpisodesRequested?.call();
              },
            );
            controller.addJavaScriptHandler(
              handlerName: 'TimeUpdate',
              callback: (args) {
                if (!mounted) return;
                if (args.length >= 2) {
                  final currentTime = (args[0] as num).toDouble();
                  final duration = (args[1] as num).toDouble();
                  widget.onPlayerEvent?.call('timeupdate', currentTime, duration);
                }
              },
            );
          },
          onConsoleMessage: (controller, consoleMessage) {
            debugPrint("WebView Console [" + consoleMessage.messageLevel.toString() + "]: " + consoleMessage.message);
          },
          onTitleChanged: (controller, title) {
            debugPrint("WebView Title Changed: " + (title ?? "null"));
            if (title != null) {
              final t = title.toLowerCase();
              if (t.contains('404') || t.contains('not found') || t.contains('error')) {
                debugPrint("Ã°Å¸Å¡Â¨ Detected 404 in Title: " + title);
                widget.onError?.call("Title Error: " + title);
              }
            }
          },
          onProgressChanged: (controller, progress) {
            if (mounted) {
              setState(() {
                _progress = progress / 100;
                if (_progress >= 1.0) {
                  _isLoading = false;
                }
              });
            }
          },
          onReceivedError: (controller, request, error) {
            debugPrint("WebView Load Error: " + error.description + " on " + request.url.toString());
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            if (request.isForMainFrame ?? true) {
              debugPrint("Ã°Å¸Å¡Â¨ Main frame load error: " + error.description);
              widget.onError?.call(error.description);
            }
          },
          onReceivedHttpError: (controller, request, errorResponse) async {
            final statusCode = errorResponse.statusCode;
            final url = request.url.toString().toLowerCase();
            debugPrint("WebView HTTP Response: " + statusCode.toString() + " on " + url);
            
            if (statusCode != null && statusCode >= 400) {
              final isMain = request.isForMainFrame ?? false;
              
              if (isMain || url.contains('.m3u8') || url.contains('.mp4') || url.contains('playlist') || url.contains('/api/')) {
                debugPrint("Ã°Å¸Å¡Â¨ Critical HTTP Error detected: " + statusCode.toString() + " on " + url);
                widget.onError?.call("HTTP Error: " + statusCode.toString());
              } else {
                // If it's a long encrypted URL returning 404 (common when server has no sources)
                if (url.length > 50 && !url.endsWith('.png') && !url.endsWith('.jpg') && !url.endsWith('.css') && !url.endsWith('.js')) {
                  _internalErrorCount++;
                  if (_internalErrorCount >= 4) {
                    debugPrint("Ã°Å¸Å¡Â¨ Multiple internal 404s detected! Server is likely dead.");
                    widget.onError?.call("Multiple Internal HTTP Errors");
                  }
                }
              }
            }
          },
          onUpdateVisitedHistory: (controller, url, isReload) {
            if (url != null && widget.onEpisodeChanged != null) {
              final urlString = url.toString().toLowerCase();
              // Try to parse season and episode from URL: /tv/id/season/episode or /embed/tv/id/season/episode
              final RegExp regex = RegExp(r'/tv/[^/]+/(\d+)/(\d+)');
              final match = regex.firstMatch(urlString);
              if (match != null) {
                final season = int.tryParse(match.group(1)!);
                final episode = int.tryParse(match.group(2)!);
                if (season != null && episode != null) {
                  debugPrint("Ã°Å¸Å¡Â¨ Detected episode change from SPA navigation: S\$season E\$episode");
                  widget.onEpisodeChanged!(season, episode);
                }
              }
            }
          },
          onLoadStop: (controller, url) async {
            debugPrint("WebView Load Stop: " + (url?.toString() ?? "null"));
            if (url != null && widget.onEpisodeChanged != null) {
              final urlString = url.toString().toLowerCase();
              final RegExp regex = RegExp(r'/tv/[^/]+/(\d+)/(\d+)');
              final match = regex.firstMatch(urlString);
              if (match != null) {
                final season = int.tryParse(match.group(1)!);
                final episode = int.tryParse(match.group(2)!);
                if (season != null && episode != null) {
                  widget.onEpisodeChanged!(season, episode);
                }
              }
            }
            if (mounted) {
              setState(() {
                _isLoading = false;
                _progress = 1.0;
              });
            }
            
            try {
              // Inject a periodic checker because React/Next.js sites show "FETCHING DATA..." 
              // and only change to an error message seconds later.
              final js = """
                (function() {
                  if (window.errorDetectorInterval) clearInterval(window.errorDetectorInterval);
                  window.errorDetectorInterval = setInterval(function() {
                    if (!document.body) return;
                    var text = document.body.innerText.toLowerCase();
                    if (
                      text.includes('404 not found') || 
                      text.includes('video not found') || 
                      text.includes('file was deleted') ||
                      text.includes('page not found') ||
                      text.includes('no stream found') ||
                      text.includes("we couldn't find") ||
                      text.includes("could not find") ||
                      text.includes('no results') ||
                      text.includes('not available') ||
                      text.includes('video is unavailable') ||
                      text.includes('movie not found') ||
                      text.includes('episode not found') ||
                      (text.includes('error') && text.includes('loading'))
                    ) {
                       window.flutter_inappwebview.callHandler('VideoErrorDetector', 'Body Error Detected');
                       clearInterval(window.errorDetectorInterval);
                    }
                  }, 1000);
                })();
              """;
              await controller.evaluateJavascript(source: js);
            } catch (e) {
              debugPrint("Error evaluating javascript: " + e.toString());
            }
          },
        ),
        if (_isLoading)
          Container(
            color: const Color(0xFF0D0F14),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      NivioTheme.accentColorOf(context),
                    ),
                    value: _progress > 0 ? _progress : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading \${widget.title}...',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

}
