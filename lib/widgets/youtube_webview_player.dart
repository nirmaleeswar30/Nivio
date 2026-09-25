import 'dart:collection';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nivio/services/hls_proxy_service.dart';

/// A lightweight YouTube player built on top of flutter_inappwebview.
/// Works on all platforms that flutter_inappwebview supports (Android, iOS,
/// Linux, Windows, macOS).
///
/// Uses the YouTube IFrame Player API for playback, so no yt-dlp or
/// media_kit dependency is needed.
class YouTubeWebViewPlayer extends StatefulWidget {
  /// The YouTube video ID (e.g. 'dQw4w9WgXcQ').
  final String videoId;

  /// Whether to autoplay the video on load.
  final bool autoPlay;

  /// Whether to start muted.
  final bool muted;

  /// Whether to show YouTube player controls.
  final bool showControls;

  /// Whether to loop the video.
  final bool loop;

  /// Start time in seconds.
  final int startAt;

  /// Called when the player state changes.
  /// States: 'unstarted'(-1), 'ended'(0), 'playing'(1), 'paused'(2),
  /// 'buffering'(3), 'cued'(5)
  final ValueChanged<int>? onStateChanged;

  /// Called when the player is ready.
  final VoidCallback? onReady;

  /// Called when an error occurs.
  final ValueChanged<int>? onError;

  const YouTubeWebViewPlayer({
    super.key,
    required this.videoId,
    this.autoPlay = true,
    this.muted = false,
    this.showControls = true,
    this.loop = false,
    this.startAt = 0,
    this.onStateChanged,
    this.onReady,
    this.onError,
  });

  @override
  State<YouTubeWebViewPlayer> createState() => YouTubeWebViewPlayerState();
}

class YouTubeWebViewPlayerState extends State<YouTubeWebViewPlayer> {
  InAppWebViewController? _controller;
  bool _isReady = false;

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    // Only poke the WebView on mobile, where the platform view tears down in an
    // orderly way. On desktop (Windows/WebView2, Linux/WebKitGTK) the native
    // view is destroyed as the route pops, and in RELEASE builds that teardown
    // races ahead of this callback — calling evaluateJavascript() into a
    // half-destroyed controller crashes the app (works in debug only because
    // the slower teardown lets the call land first). Dropping the reference is
    // enough on desktop: the platform view stops playback when it is destroyed.
    if (_isReady && controller != null && (Platform.isAndroid || Platform.isIOS)) {
      try {
        controller.evaluateJavascript(
          source:
              'var mp = document.getElementById("movie_player"); if(mp && mp.stopVideo) mp.stopVideo(); else if(typeof player !== "undefined" && player && player.stopVideo) player.stopVideo(); else { var v = document.querySelector("video"); if(v) v.pause(); }',
        );
      } catch (_) {}
    }
    super.dispose();
  }

  String _buildWindowsUrl(String videoId, {int? startAt}) {
    final port = HlsProxyService.instance.port;
    if (port > 0) {
      final autoplay = widget.autoPlay ? 1 : 0;
      final controls = widget.showControls ? 1 : 0;
      final loop = widget.loop ? 1 : 0;
      final mute = widget.muted ? 1 : 0;
      final start = startAt ?? widget.startAt;

      return 'http://127.0.0.1:$port/youtube_trailer?v=$videoId'
          '&autoplay=$autoplay'
          '&controls=$controls'
          '&mute=$mute'
          '&loop=$loop'
          '&start=$start';
    }
    return _buildEmbedUrl(videoId, startAt: startAt);
  }

  String _buildEmbedUrl(String videoId, {int? startAt}) {
    final autoplay = widget.autoPlay ? '1' : '0';
    final controls = widget.showControls ? '1' : '0';
    final mute = widget.muted ? '1' : '0';
    final start = startAt ?? widget.startAt;

    final query = <String, String>{
      'autoplay': autoplay,
      'controls': controls,
      'mute': mute,
      'playsinline': '1',
      'rel': '0',
      'modestbranding': '1',
      if (start > 0) 'start': '$start',
      if (widget.loop) 'loop': '1',
      if (widget.loop) 'playlist': videoId,
    };

    return Uri.https('www.youtube.com', '/embed/$videoId', query).toString();
  }

  String _buildHtml() {
    final autoplay = widget.autoPlay ? 1 : 0;
    final controls = widget.showControls ? 1 : 0;
    final loop = widget.loop ? 1 : 0;
    // ignore: unused_local_variable
    final mute = widget.muted ? 1 : 0;
    final start = widget.startAt;
    final videoId = widget.videoId;

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <meta name="referrer" content="strict-origin-when-cross-origin">
  <style>
    * { margin: 0; padding: 0; overflow: hidden; }
    html, body { width: 100%; height: 100%; background: #000; }
    #player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: 0; }
  </style>
</head>
<body>
  <iframe 
    id="player"
    width="100%" 
    height="100%" 
    src="https://www.youtube-nocookie.com/embed/$videoId?enablejsapi=1&autoplay=$autoplay&mute=1&controls=$controls&start=$start&playsinline=1&fs=0&iv_load_policy=3&rel=0&modestbranding=1&loop=$loop&playlist=$videoId&origin=https://www.youtube-nocookie.com" 
    frameborder="0" 
    allow="autoplay; encrypted-media; fullscreen; picture-in-picture; accelerometer; clipboard-write; gyroscope" 
    referrerpolicy="strict-origin-when-cross-origin"
    allowfullscreen>
  </iframe>
  <script>
    var tag = document.createElement('script');
    tag.src = 'https://www.youtube.com/iframe_api';
    var firstScriptTag = document.getElementsByTagName('script')[0];
    firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

    var player;
    function onYouTubeIframeAPIReady() {
      player = new YT.Player('player', {
        events: {
          onReady: function(e) {
            window.flutter_inappwebview.callHandler('onReady');
          },
          onStateChange: function(e) {
            if (e.data === 0 && $loop === 1) {
              e.target.seekTo(0);
              e.target.playVideo();
            } else {
              window.flutter_inappwebview.callHandler('onStateChange', e.data);
            }
          },
          onError: function(e) {
            window.flutter_inappwebview.callHandler('onError', e.data);
          }
        }
      });
    }
  </script>
</body>
</html>
''';
  }

  // ─── Public API ──────────────────────────────────────────────

  /// Play the video.
  Future<void> play() async {
    await _controller?.evaluateJavascript(
      source:
          'if(typeof player !== "undefined" && player && player.playVideo) player.playVideo(); else { var mp = document.getElementById("movie_player"); if(mp && mp.playVideo) mp.playVideo(); else { var v = document.querySelector("video"); if(v) v.play(); } }',
    );
  }

  /// Pause the video.
  Future<void> pause() async {
    await _controller?.evaluateJavascript(
      source:
          'if(typeof player !== "undefined" && player && player.pauseVideo) player.pauseVideo(); else { var mp = document.getElementById("movie_player"); if(mp && mp.pauseVideo) mp.pauseVideo(); else { var v = document.querySelector("video"); if(v) v.pause(); } }',
    );
  }

  /// Seek to a position in seconds.
  Future<void> seekTo(int seconds) async {
    await _controller?.evaluateJavascript(
      source:
          'if(typeof player !== "undefined" && player && player.seekTo) player.seekTo($seconds, true); else { var mp = document.getElementById("movie_player"); if(mp && mp.seekTo) mp.seekTo($seconds, true); else { var v = document.querySelector("video"); if(v) v.currentTime = $seconds; } }',
    );
  }

  /// Mute the player.
  Future<void> mute() async {
    await _controller?.evaluateJavascript(
      source:
          'if(typeof player !== "undefined" && player && player.mute) player.mute(); else { var mp = document.getElementById("movie_player"); if(mp && mp.mute) mp.mute(); else { var v = document.querySelector("video"); if(v) v.muted = true; } }',
    );
  }

  /// Unmute the player.
  Future<void> unMute() async {
    await _controller?.evaluateJavascript(
      source:
          'if(typeof player !== "undefined" && player && player.unMute) player.unMute(); else { var mp = document.getElementById("movie_player"); if(mp && mp.unMute) mp.unMute(); else { var v = document.querySelector("video"); if(v) v.muted = false; } }',
    );
  }

  /// Set volume (0-100).
  Future<void> setVolume(int volume) async {
    await _controller?.evaluateJavascript(
      source:
          'if(typeof player !== "undefined" && player && player.setVolume) player.setVolume($volume); else { var mp = document.getElementById("movie_player"); if(mp && mp.setVolume) mp.setVolume($volume); else { var v = document.querySelector("video"); if(v) v.volume = ${volume / 100.0}; } }',
    );
  }

  /// Load a different video by ID.
  Future<void> loadVideo(String videoId, {int startAt = 0}) async {
    if (Platform.isWindows) {
      final url = _buildWindowsUrl(videoId, startAt: startAt);
      await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } else {
      await _controller?.evaluateJavascript(
        source:
            'if(typeof player !== "undefined" && player && player.loadVideoById) player.loadVideoById("$videoId", $startAt);',
      );
    }
  }

  /// Whether the player is ready.
  bool get isReady => _isReady;

  @override
  Widget build(BuildContext context) {
    final isWindows = Platform.isWindows;

    return InAppWebView(
      initialUrlRequest: isWindows
          ? URLRequest(url: WebUri(_buildWindowsUrl(widget.videoId)))
          : null,
      initialData: isWindows
          ? null
          : InAppWebViewInitialData(
              data: _buildHtml(),
              baseUrl: WebUri('https://www.youtube-nocookie.com'),
            ),
      initialUserScripts: UnmodifiableListView([]),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        transparentBackground: true,
        supportMultipleWindows: false,
        javaScriptCanOpenWindowsAutomatically: false,
      ),
      onLoadStop: (controller, url) async {
        _isReady = true;
        widget.onReady?.call();
      },
      onWebViewCreated: (controller) {
        _controller = controller;

        controller.addJavaScriptHandler(
          handlerName: 'onReady',
          callback: (args) {
            _isReady = true;
            widget.onReady?.call();
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'onStateChange',
          callback: (args) {
            if (args.isNotEmpty) {
              final state = args[0] as int;

              // Unmute workaround via native evaluateJavascript (often inherits user gesture context)
              if (state == 1 && widget.autoPlay && !widget.muted) {
                Future.delayed(const Duration(milliseconds: 250), () {
                  if (mounted && _controller != null) {
                    _controller!.evaluateJavascript(source: """
                      var mp = document.getElementById('movie_player');
                      if (mp && mp.unMute) {
                        mp.unMute();
                        mp.setVolume(100);
                      } else {
                        var iframe = document.getElementById('player');
                        if (iframe) {
                          iframe.contentWindow.postMessage('{"event":"command","func":"unMute","args":""}', '*');
                          iframe.contentWindow.postMessage('{"event":"command","func":"setVolume","args":[100]}', '*');
                        }
                      }
                    """);
                  }
                });
              }

              widget.onStateChanged?.call(state);
            }
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'onError',
          callback: (args) {
            if (args.isNotEmpty) {
              final errorCode = args[0] as int;
              debugPrint('YouTubeWebViewPlayer error: $errorCode');
              widget.onError?.call(errorCode);
            }
          },
        );
      },
    );
  }
}

