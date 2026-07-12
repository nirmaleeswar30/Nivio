import 'package:flutter/material.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'dart:async';

import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

class PlayerGestureLayer extends StatefulWidget {
  final BetterPlayerController controller;
  final VoidCallback onSingleTap;
  final VoidCallback? onLongPress;
  final void Function(bool zoomIn)? onPinchZoom;
  final bool isLocked;

  const PlayerGestureLayer({
    super.key,
    required this.controller,
    required this.onSingleTap,
    this.onLongPress,
    this.onPinchZoom,
    this.isLocked = false,
  });

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer>
    with SingleTickerProviderStateMixin {
  double _volume = 0.5;
  double _brightness = 0.5;

  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;

  String _seekText = '';
  bool _showSeekRipple = false;
  bool _isSeekingRight = true;

  Timer? _hideIndicatorTimer;

  @override
  void initState() {
    super.initState();
    _initHardwareLevels();
  }

  @override
  void dispose() {
    FlutterVolumeController.removeListener();
    try {
      ScreenBrightness().resetScreenBrightness();
    } catch (e) {
      debugPrint('Error resetting screen brightness: $e');
    }
    super.dispose();
  }

  Future<void> _initHardwareLevels() async {
    try {
      _brightness = await ScreenBrightness().current;
      final vol = await FlutterVolumeController.getVolume();
      if (vol != null) {
        setState(() {
          _volume = vol;
        });
      }
      // Listen to volume button changes
      FlutterVolumeController.addListener((volume) {
        if (mounted) {
          setState(() {
            if (volume < 1.0) {
              _volume = volume;
              widget.controller.setVolume(1.0);
            }
          });
        }
      });
    } catch (e) {
      debugPrint('Error getting hardware levels: $e');
    }
  }

  bool _ignoreCurrentDrag = false;

  void _onVerticalDragStart(DragStartDetails details) {
    if (widget.isLocked) return;
    
    final screenHeight = MediaQuery.of(context).size.height;
    final yPos = details.globalPosition.dy;
    
    // Ignore drags that start within 60 pixels of the top or bottom edge
    // to avoid conflicting with system notification/home gestures.
    if (yPos < 60 || yPos > screenHeight - 60) {
      _ignoreCurrentDrag = true;
    } else {
      _ignoreCurrentDrag = false;
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, bool isLeftSide) {
    if (widget.isLocked || _ignoreCurrentDrag) return;
    final delta = details.delta.dy;
    final sensitivity = 0.005;

    setState(() {
      if (isLeftSide) {
        _brightness = (_brightness - (delta * sensitivity)).clamp(0.0, 1.0);
        _showBrightnessIndicator = true;
        _showVolumeIndicator = false;
        ScreenBrightness().setScreenBrightness(_brightness);
      } else {
        _volume = (_volume - (delta * sensitivity)).clamp(0.0, 2.0);
        _showVolumeIndicator = true;
        _showBrightnessIndicator = false;
        if (_volume <= 1.0) {
          FlutterVolumeController.setVolume(_volume);
          widget.controller.setVolume(1.0);
        } else {
          FlutterVolumeController.setVolume(1.0);
          widget.controller.setVolume(_volume);
        }
      }
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (widget.isLocked) return;
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
    if (widget.isLocked) return;

    final currentPos =
        widget.controller.videoPlayerController?.value.position ??
        Duration.zero;
    final newPos = isRightSide
        ? currentPos + const Duration(seconds: 10)
        : currentPos - const Duration(seconds: 10);

    widget.controller.seekTo(newPos);

    setState(() {
      _isSeekingRight = isRightSide;
      _seekText = isRightSide ? '+10s' : '-10s';
      _showSeekRipple = true;
    });

    _hideIndicatorTimer?.cancel();
    _hideIndicatorTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showSeekRipple = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onScaleUpdate: (details) {
            if (widget.isLocked) return;
            if (details.pointerCount >= 2) {
              if (details.scale > 1.05) {
                widget.onPinchZoom?.call(true);
              } else if (details.scale < 0.95) {
                widget.onPinchZoom?.call(false);
              }
            }
          },
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onSingleTap,
                  onLongPress: widget.onLongPress,
                  onDoubleTap: widget.isLocked ? null : () => _onDoubleTap(false),
                  onVerticalDragStart: widget.isLocked ? null : _onVerticalDragStart,
                  onVerticalDragUpdate: widget.isLocked ? null : (d) => _onVerticalDragUpdate(d, true),
                  onVerticalDragEnd: widget.isLocked ? null : _onVerticalDragEnd,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onSingleTap,
                  onLongPress: widget.onLongPress,
                  onDoubleTap: widget.isLocked ? null : () => _onDoubleTap(true),
                  onVerticalDragStart: widget.isLocked ? null : _onVerticalDragStart,
                  onVerticalDragUpdate: widget.isLocked ? null : (d) => _onVerticalDragUpdate(d, false),
                  onVerticalDragEnd: widget.isLocked ? null : _onVerticalDragEnd,
                ),
              ),
            ],
          ),
        ),

        // Seek Ripple Indicator
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
                  begin: _isSeekingRight
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  end: _isSeekingRight
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                ),
                borderRadius: BorderRadius.horizontal(
                  left: _isSeekingRight
                      ? const Radius.circular(100)
                      : Radius.zero,
                  right: _isSeekingRight
                      ? Radius.zero
                      : const Radius.circular(100),
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isSeekingRight
                          ? Icons.fast_forward_rounded
                          : Icons.fast_rewind_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _seekText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Brightness Indicator
        if (_showBrightnessIndicator)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 32.0),
              child: _buildVerticalIndicator(
                Icons.brightness_6_rounded,
                _brightness,
              ),
            ),
          ),

        // Volume Indicator
        if (_showVolumeIndicator)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 32.0),
              child: _buildVerticalIndicator(Icons.volume_up_rounded, _volume, isVolume: true),
            ),
          ),
      ],
    );
  }

  Widget _buildVerticalIndicator(IconData icon, double value, {bool isVolume = false}) {
    final displayValue = isVolume && value > 1.0 ? value - 1.0 : value;
    final progressColor = isVolume && value > 1.0 ? Colors.orangeAccent : Colors.white;
    final pct = (value * 100).round();
    
    return Container(
      width: 42,
      height: 170,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
            child: Icon(
              isVolume && value > 1.0 ? Icons.volume_up_rounded : icon,
              color: progressColor, 
              size: 20
            ),
          ),
          Text(
            '$pct%',
            style: TextStyle(
              color: progressColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12.0, left: 16, right: 16),
              child: RotatedBox(
                quarterTurns: 3,
                child: LinearProgressIndicator(
                  value: displayValue,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
