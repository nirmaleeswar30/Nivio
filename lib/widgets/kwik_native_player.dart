import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

class KwikNativePlayer extends StatefulWidget {
  final String url;
  final Map<String, String> headers;
  final Duration? startAt;
  final String? title;
  final String? subtitle;
  final String providerName;
  final Function(Duration position, Duration duration)? onProgress;
  final VoidCallback? onEnded;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final VoidCallback? onServerChange;
  final VoidCallback? onEpisodes;

  const KwikNativePlayer({
    super.key,
    required this.url,
    required this.headers,
    this.startAt,
    this.title,
    this.subtitle,
    required this.providerName,
    this.onProgress,
    this.onEnded,
    this.onBack,
    this.onSettings,
    this.onServerChange,
    this.onEpisodes,
  });

  @override
  State<KwikNativePlayer> createState() => _KwikNativePlayerState();
}

class _KwikNativePlayerState extends State<KwikNativePlayer> {
  late final Player player;
  late final VideoController controller;
  
  bool _isPlaying = true;
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideControlsTimer;
  double? _dragValue;
  
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Hardware levels
  double _volume = 0.5;
  double _brightness = 0.5;
  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;
  String _seekText = '';
  bool _showSeekRipple = false;
  bool _isSeekingRight = true;
  Timer? _hideIndicatorTimer;
  bool _ignoreCurrentDrag = false;
  
  int _seekAccumulation = 0;
  Timer? _seekAccumulationTimer;

  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);

    player.open(
      Media(widget.url, httpHeaders: widget.headers),
      play: true,
    );

    _subscriptions.addAll([
      player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      }),
      player.stream.position.listen((position) {
        if (mounted) {
          setState(() => _position = position);
          widget.onProgress?.call(_position, _duration);
        }
      }),
      player.stream.duration.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      }),
      player.stream.completed.listen((completed) {
        if (completed && mounted) {
          widget.onEnded?.call();
        }
      }),
      player.stream.buffer.listen((buffer) {
        // Handle buffering state if needed
      }),
    ]);

    if (widget.startAt != null) {
      player.stream.duration.first.then((_) {
        player.seek(widget.startAt!);
      });
    }

    _initHardwareLevels();
    _startHideTimer();
  }

  @override
  void dispose() {
    // Save final progress
    widget.onProgress?.call(player.state.position, player.state.duration);
    for (final s in _subscriptions) {
      s.cancel();
    }
    player.dispose();
    FlutterVolumeController.removeListener();
    _hideControlsTimer?.cancel();
    _hideIndicatorTimer?.cancel();
    super.dispose();
  }

  Future<void> _initHardwareLevels() async {
    try {
      _brightness = await ScreenBrightness().current;
      final vol = await FlutterVolumeController.getVolume();
      if (vol != null) _volume = vol;
      FlutterVolumeController.addListener((volume) {
        if (mounted) setState(() => _volume = volume);
      });
    } catch (e) {
      debugPrint('Error getting hardware levels: $e');
    }
  }

  void _startHideTimer() {
    if (_isLocked) return;
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_isLocked) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        _showControls = false;
      } else {
        _showControls = true;
        _startHideTimer();
      }
    });

    final marginHorizontal = (MediaQuery.of(context).size.width - 250) / 2;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: 32, left: marginHorizontal, right: marginHorizontal),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_isLocked ? Icons.lock : Icons.lock_open, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              _isLocked ? 'Screen Locked' : 'Screen Unlocked',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xE6000000),
      ),
    );
  }

  void _onLockedSingleTap() {
    final marginHorizontal = (MediaQuery.of(context).size.width - 250) / 2;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: 32, left: marginHorizontal, right: marginHorizontal),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        content: const Text(
          'Long press to unlock',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xE6000000),
      ),
    );
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_isLocked) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final yPos = details.globalPosition.dy;
    
    if (yPos < 60 || yPos > screenHeight - 60) {
      _ignoreCurrentDrag = true;
    } else {
      _ignoreCurrentDrag = false;
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, bool isLeftSide) {
    if (_isLocked || _ignoreCurrentDrag) return;
    final delta = details.delta.dy;
    final sensitivity = 0.005;

    setState(() {
      if (isLeftSide) {
        _brightness = (_brightness - (delta * sensitivity)).clamp(0.0, 1.0);
        _showBrightnessIndicator = true;
        _showVolumeIndicator = false;
        ScreenBrightness().setScreenBrightness(_brightness);
      } else {
        _volume = (_volume - (delta * sensitivity)).clamp(0.0, 1.0);
        _showVolumeIndicator = true;
        _showBrightnessIndicator = false;
        FlutterVolumeController.setVolume(_volume);
      }
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isLocked) return;
    _hideIndicatorTimer?.cancel();
    _hideIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showVolumeIndicator = false;
          _showBrightnessIndicator = false;
        });
      }
    });
  }

  void _onDoubleTap(bool isRightSide) {
    if (_isLocked) return;

    // Reset accumulation if direction changed
    if (_isSeekingRight != isRightSide || _seekAccumulation == 0) {
      _seekAccumulation = 10;
      _isSeekingRight = isRightSide;
    } else {
      _seekAccumulation += 10;
    }

    final currentPos = player.state.position;
    final newPos = isRightSide
        ? currentPos + const Duration(seconds: 10)
        : currentPos - const Duration(seconds: 10);

    player.seek(newPos);

    setState(() {
      _seekText = isRightSide ? '+${_seekAccumulation}s' : '-${_seekAccumulation}s';
      _showSeekRipple = true;
    });

    _seekAccumulationTimer?.cancel();
    _seekAccumulationTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showSeekRipple = false;
          _seekAccumulation = 0;
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Widget _buildVerticalIndicator(IconData icon, double value) {
    return Container(
      width: 40,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12.0, left: 16, right: 16),
              child: RotatedBox(
                quarterTurns: 3,
                child: LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. Video Layer
        Video(
          controller: controller,
          controls: NoVideoControls, // We use custom controls
          fit: BoxFit.contain, // Default fit, could be customized
        ),

        // 2. Gesture Layer
        Positioned.fill(
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _isLocked ? _onLockedSingleTap : _toggleControls,
                      onLongPress: _toggleLock,
                      onDoubleTap: _isLocked ? null : () => _onDoubleTap(false),
                      onVerticalDragStart: _isLocked ? null : _onVerticalDragStart,
                      onVerticalDragUpdate: _isLocked ? null : (d) => _onVerticalDragUpdate(d, true),
                      onVerticalDragEnd: _isLocked ? null : _onVerticalDragEnd,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _isLocked ? _onLockedSingleTap : _toggleControls,
                      onLongPress: _toggleLock,
                      onDoubleTap: _isLocked ? null : () => _onDoubleTap(true),
                      onVerticalDragStart: _isLocked ? null : _onVerticalDragStart,
                      onVerticalDragUpdate: _isLocked ? null : (d) => _onVerticalDragUpdate(d, false),
                      onVerticalDragEnd: _isLocked ? null : _onVerticalDragEnd,
                    ),
                  ),
                ],
              ),
              
              if (_showSeekRipple)
                Positioned(
                  left: _isSeekingRight ? null : 0,
                  right: _isSeekingRight ? 0 : null,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.white.withValues(alpha: 0.1),
                        ],
                        begin: _isSeekingRight ? Alignment.centerLeft : Alignment.centerRight,
                        end: _isSeekingRight ? Alignment.centerRight : Alignment.centerLeft,
                      ),
                      borderRadius: BorderRadius.horizontal(
                        left: _isSeekingRight ? const Radius.circular(100) : Radius.zero,
                        right: _isSeekingRight ? Radius.zero : const Radius.circular(100),
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isSeekingRight ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _seekText,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (_showBrightnessIndicator)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 32.0),
                    child: _buildVerticalIndicator(Icons.brightness_6_rounded, _brightness),
                  ),
                ),

              if (_showVolumeIndicator)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 32.0),
                    child: _buildVerticalIndicator(Icons.volume_up_rounded, _volume),
                  ),
                ),
            ],
          ),
        ),

        // 3. UI Controls Layer
        if (_showControls && !_isLocked)
          Positioned.fill(
            child: Stack(
              children: [
                Container(color: Colors.black.withValues(alpha: 0.5)),
                // Top Bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    minimum: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                          onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title ?? 'Playing',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.subtitle != null || widget.providerName.isNotEmpty)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (widget.subtitle != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).primaryColor,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          widget.subtitle!,
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white24,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        widget.providerName.toUpperCase(),
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        if (widget.onEpisodes != null)
                          IconButton(
                            icon: const Icon(Icons.list, color: Colors.white, size: 28),
                            onPressed: () {
                              _startHideTimer();
                              widget.onEpisodes?.call();
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.sync, color: Colors.white, size: 28),
                          onPressed: () {
                            _startHideTimer();
                            widget.onServerChange?.call();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white, size: 28),
                          onPressed: () {
                            _startHideTimer();
                            widget.onSettings?.call();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Center Play/Pause
                Center(
                  child: IconButton(
                    iconSize: 72,
                    color: Colors.white,
                    icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                    onPressed: () {
                      if (_isPlaying) {
                        player.pause();
                      } else {
                        player.play();
                      }
                      _startHideTimer();
                    },
                  ),
                ),
                
                // Bottom Controls (Progress bar)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              _formatDuration(_dragValue != null ? Duration(milliseconds: _dragValue!.toInt()) : _position),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 4.0,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
                                  activeTrackColor: Theme.of(context).primaryColor,
                                  inactiveTrackColor: Colors.white30,
                                  secondaryActiveTrackColor: Colors.white70,
                                  thumbColor: Theme.of(context).primaryColor,
                                ),
                                child: Slider(
                                  value: (_dragValue ?? _position.inMilliseconds.toDouble()).clamp(0, _duration.inMilliseconds.toDouble()),
                                  secondaryTrackValue: player.state.buffer.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
                                  max: _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                                  onChanged: (value) {
                                    setState(() {
                                      _dragValue = value;
                                    });
                                    _hideControlsTimer?.cancel();
                                  },
                                  onChangeEnd: (value) {
                                    player.seek(Duration(milliseconds: value.toInt()));
                                    setState(() {
                                      _dragValue = null;
                                    });
                                    _startHideTimer();
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              _formatDuration(_duration),
                              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
