import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'gesture_layer.dart';

class CustomPlayerControls extends StatefulWidget {
  final BetterPlayerController controller;
  final Function(bool visbility) onPlayerVisibilityChanged;
  final BetterPlayerControlsConfiguration controlsConfiguration;
  
  final String? title;
  final String? subtitle;
  final String? providerName;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final VoidCallback? onServerChange;

  const CustomPlayerControls({
    super.key,
    required this.controller,
    required this.onPlayerVisibilityChanged,
    required this.controlsConfiguration,
    this.title,
    this.subtitle,
    this.providerName,
    this.onBack,
    this.onSettings,
    this.onServerChange,
  });

  @override
  State<CustomPlayerControls> createState() => _CustomPlayerControlsState();
}

class _CustomPlayerControlsState extends State<CustomPlayerControls> {
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideControlsTimer;
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.controller.isPlaying() ?? false;
    widget.controller.videoPlayerController?.addListener(_onPlayerStateChanged);
    _startHideTimer();
  }

  @override
  void dispose() {
    widget.controller.videoPlayerController?.removeListener(
      _onPlayerStateChanged,
    );
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    if (_isLocked) return;
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
        widget.onPlayerVisibilityChanged(false);
      }
    });
  }

  void _toggleControls() {
    if (_isLocked) return;
    setState(() {
      _showControls = !_showControls;
    });
    widget.onPlayerVisibilityChanged(_showControls);
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
        widget.onPlayerVisibilityChanged(false);
      } else {
        _showControls = true;
        widget.onPlayerVisibilityChanged(true);
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

  void _onPlayerStateChanged() {
    final isPlaying = widget.controller.isPlaying() ?? false;
    if (_isPlaying != isPlaying) {
      setState(() {
        _isPlaying = isPlaying;
      });
      if (!_isPlaying) {
        if (!_isLocked) {
          setState(() => _showControls = true);
          widget.onPlayerVisibilityChanged(true);
        }
        _hideControlsTimer?.cancel();
      } else {
        _startHideTimer();
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          // 1. Background (Darken when controls are shown)
          if (_showControls && !_isLocked)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
            ),

          // 2. Gesture Layer (Always active, receives drags & taps)
          PlayerGestureLayer(
            controller: widget.controller,
            isLocked: _isLocked,
            onSingleTap: _isLocked ? _onLockedSingleTap : _toggleControls,
            onLongPress: _toggleLock,
          ),

          // 3. UI Controls Layer (Toggleable)
          if (_showControls && !_isLocked)
            Stack(
              children: [
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
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.subtitle != null || widget.providerName != null)
                                  Row(
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
                                      if (widget.subtitle != null && widget.providerName != null)
                                        const SizedBox(width: 6),
                                      if (widget.providerName != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white24,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            widget.providerName!.toUpperCase(),
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
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
                          widget.controller.pause();
                        } else {
                          widget.controller.play();
                        }
                        _startHideTimer();
                      },
                    ),
                  ),
                  
                  // Bottom Controls
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
                        // Time & Progress Bar
                        // Time & Progress Bar
                          if (widget.controller.videoPlayerController != null)
                            ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: widget.controller.videoPlayerController!,
                              builder: (context, value, child) {
                                final position = value.position;
                                final duration = value.duration ?? Duration.zero;
                                
                                final buffered = value.buffered;
                                double maxBuffered = 0.0;
                                if (buffered.isNotEmpty) {
                                  maxBuffered = buffered.last.end.inMilliseconds.toDouble();
                                }
                                
                                if (duration.inMilliseconds > 0 && maxBuffered > duration.inMilliseconds.toDouble()) {
                                  maxBuffered = duration.inMilliseconds.toDouble();
                                }

                                return Row(
                                  children: [
                                    Text(
                                      _formatDuration(_dragValue != null ? Duration(milliseconds: _dragValue!.toInt()) : position),
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
                                          value: (_dragValue ?? position.inMilliseconds.toDouble()).clamp(0, duration.inMilliseconds.toDouble()),
                                          secondaryTrackValue: maxBuffered.clamp(0, duration.inMilliseconds.toDouble()),
                                          max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0,
                                          onChanged: (value) {
                                            setState(() {
                                              _dragValue = value;
                                            });
                                            _hideControlsTimer?.cancel();
                                          },
                                          onChangeEnd: (value) {
                                            widget.controller.seekTo(Duration(milliseconds: value.toInt()));
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
                                      _formatDuration(duration),
                                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}
