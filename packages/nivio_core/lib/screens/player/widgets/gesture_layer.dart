import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'dart:async';

import 'package:device_screen_brightness/device_screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

class PlayerGestureLayer extends StatefulWidget {
  final Player controller;
  final VoidCallback onSingleTap;
  final VoidCallback? onLongPress;
  final void Function(bool zoomIn)? onPinchZoom;
  final VoidCallback? onDoubleTapSeekStart;
  final bool isLocked;
  final int seekDuration;

  const PlayerGestureLayer({
    super.key,
    required this.controller,
    required this.onSingleTap,
    this.onLongPress,
    this.onPinchZoom,
    this.onDoubleTapSeekStart,
    this.isLocked = false,
    this.seekDuration = 10,
  });

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer>
    with TickerProviderStateMixin {
  double _volume = 0.5;
  double _brightness = 0.5;
  bool _useLocalOverlayFallback = false;

  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;

  // Double-tap & incremental skip state
  bool _isDoubleTapSeeking = false;
  bool _isSeekingRight = true;
  int _accumulatedSeconds = 0;
  Duration _baseSeekPosition = Duration.zero;
  String _seekText = '';
  bool _showSeekRipple = false;

  DateTime? _lastTapTime;
  bool? _lastTapSide;
  Timer? _singleTapTimer;
  Timer? _doubleTapTimeoutTimer;
  Timer? _hideIndicatorTimer;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseScaleAnimation;

  @override
  void initState() {
    super.initState();
    _initHardwareLevels();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _pulseScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.25).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.25, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 65,
      ),
    ]).animate(_pulseController);
  }

  @override
  void dispose() {
    _singleTapTimer?.cancel();
    _doubleTapTimeoutTimer?.cancel();
    _hideIndicatorTimer?.cancel();
    _fadeController.dispose();
    _pulseController.dispose();
    FlutterVolumeController.removeListener();
    super.dispose();
  }

  Future<void> _initHardwareLevels() async {
    try {
      final brightnessVal = await DeviceScreenBrightness.getBrightness(mode: BrightnessMode.app);
      setState(() {
        _brightness = brightnessVal / 100.0;
        _useLocalOverlayFallback = false;
      });
    } catch (e) {
      debugPrint('Error getting hardware levels, falling back to local overlay: $e');
      setState(() {
        _brightness = 1.0;
        _useLocalOverlayFallback = true;
      });
    }
    
    try {
      final vol = await FlutterVolumeController.getVolume();
      if (vol != null) {
        setState(() {
          _volume = vol;
        });
      }
      FlutterVolumeController.addListener((volume) {
        if (mounted) {
          setState(() {
            if (volume < 1.0) {
              _volume = volume;
              widget.controller.setVolume(100.0);
            }
          });
        }
      });
    } catch (e) {
      debugPrint('Error getting volume levels: $e');
    }
  }

  bool _ignoreCurrentDrag = false;

  void _onVerticalDragStart(DragStartDetails details) {
    if (widget.isLocked) return;
    
    _singleTapTimer?.cancel();
    _singleTapTimer = null;
    _lastTapTime = null;
    _lastTapSide = null;
    if (_isDoubleTapSeeking) {
      _endDoubleTapSeek();
    }

    final screenHeight = MediaQuery.sizeOf(context).height;
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
    const sensitivity = 0.005;

    setState(() {
      if (isLeftSide) {
        _brightness = (_brightness - (delta * sensitivity)).clamp(0.0, 1.0);
        _showBrightnessIndicator = true;
        _showVolumeIndicator = false;
        if (!_useLocalOverlayFallback) {
          try {
            DeviceScreenBrightness.setBrightness((_brightness * 100).round(), mode: BrightnessMode.app);
          } catch (_) {
            _useLocalOverlayFallback = true;
          }
        }
      } else {
        _volume = (_volume - (delta * sensitivity)).clamp(0.0, 2.0);
        _showVolumeIndicator = true;
        _showBrightnessIndicator = false;
        if (_volume <= 1.0) {
          FlutterVolumeController.setVolume(_volume);
          widget.controller.setVolume(100.0);
        } else {
          FlutterVolumeController.setVolume(1.0);
          widget.controller.setVolume(_volume * 100.0);
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

  void _handleTap(bool isRightSide) {
    if (widget.isLocked) {
      widget.onSingleTap();
      return;
    }

    final now = DateTime.now();
    final step = widget.seekDuration > 0 ? widget.seekDuration : 10;

    // Case 1: An incremental double-tap seek session is actively in progress
    if (_isDoubleTapSeeking) {
      if (_isSeekingRight == isRightSide) {
        // Tap on the SAME side: increment seek duration
        _doubleTapTimeoutTimer?.cancel();
        _accumulatedSeconds += step;
        _performSeek();

        try {
          HapticFeedback.selectionClick();
        } catch (_) {}

        _pulseController.forward(from: 0.0);
        setState(() {
          _seekText = _isSeekingRight
              ? '+$_accumulatedSeconds seconds'
              : '-$_accumulatedSeconds seconds';
        });

        _doubleTapTimeoutTimer = Timer(const Duration(milliseconds: 650), _endDoubleTapSeek);
        return;
      } else {
        // Tapped the OPPOSITE side: finish the active seek immediately
        _endDoubleTapSeek();
      }
    }

    // Case 2: Check if this tap constitutes the 2nd tap of a double-tap gesture
    final isWithinDoubleTapWindow = _lastTapTime != null &&
        now.difference(_lastTapTime!) < const Duration(milliseconds: 300);
    final isSameSide = _lastTapSide == isRightSide;

    if (isWithinDoubleTapWindow && isSameSide) {
      _singleTapTimer?.cancel();
      _singleTapTimer = null;
      _lastTapTime = null;
      _lastTapSide = null;

      widget.onDoubleTapSeekStart?.call();

      _isDoubleTapSeeking = true;
      _isSeekingRight = isRightSide;
      _accumulatedSeconds = step;
      _baseSeekPosition = widget.controller.state.position;

      _performSeek();

      try {
        HapticFeedback.selectionClick();
      } catch (_) {}

      setState(() {
        _seekText = _isSeekingRight
            ? '+$_accumulatedSeconds seconds'
            : '-$_accumulatedSeconds seconds';
        _showSeekRipple = true;
      });

      _fadeController.forward(from: 0.0);
      _pulseController.forward(from: 0.0);

      _doubleTapTimeoutTimer?.cancel();
      _doubleTapTimeoutTimer = Timer(const Duration(milliseconds: 650), _endDoubleTapSeek);
      return;
    }

    // Case 3: First tap of a potential double-tap, or an isolated single tap
    _lastTapTime = now;
    _lastTapSide = isRightSide;

    _singleTapTimer?.cancel();
    _singleTapTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      _lastTapTime = null;
      _lastTapSide = null;
      widget.onSingleTap();
    });
  }

  void _performSeek() {
    final maxDuration = widget.controller.state.duration;
    final delta = Duration(seconds: _accumulatedSeconds);
    Duration targetPos;
    if (_isSeekingRight) {
      targetPos = _baseSeekPosition + delta;
      if (maxDuration > Duration.zero && targetPos > maxDuration) {
        targetPos = maxDuration;
      }
    } else {
      targetPos = _baseSeekPosition - delta;
      if (targetPos < Duration.zero) {
        targetPos = Duration.zero;
      }
    }
    widget.controller.seek(targetPos);
  }

  void _endDoubleTapSeek() {
    _doubleTapTimeoutTimer?.cancel();
    _doubleTapTimeoutTimer = null;
    _isDoubleTapSeeking = false;
    _accumulatedSeconds = 0;
    _lastTapTime = null;
    _lastTapSide = null;

    if (mounted && _showSeekRipple) {
      _fadeController.reverse().then((_) {
        if (mounted && !_isDoubleTapSeeking) {
          setState(() {
            _showSeekRipple = false;
          });
        }
      });
    }
  }

  void _handleLongPress() {
    if (widget.isLocked) return;
    _singleTapTimer?.cancel();
    _singleTapTimer = null;
    _lastTapTime = null;
    _lastTapSide = null;
    if (_isDoubleTapSeeking) {
      _endDoubleTapSeek();
    }
    widget.onLongPress?.call();
  }

  Widget _buildChevrons(bool isRight) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final t = _pulseController.value;
        // Staggered opacity wave in direction of travel
        double c1, c2, c3;
        if (isRight) {
          c1 = (0.3 + 0.7 * (1.0 - (t - 0.0).abs() * 2.5)).clamp(0.25, 1.0);
          c2 = (0.3 + 0.7 * (1.0 - (t - 0.35).abs() * 2.5)).clamp(0.25, 1.0);
          c3 = (0.3 + 0.7 * (1.0 - (t - 0.7).abs() * 2.5)).clamp(0.25, 1.0);
        } else {
          c3 = (0.3 + 0.7 * (1.0 - (t - 0.0).abs() * 2.5)).clamp(0.25, 1.0);
          c2 = (0.3 + 0.7 * (1.0 - (t - 0.35).abs() * 2.5)).clamp(0.25, 1.0);
          c1 = (0.3 + 0.7 * (1.0 - (t - 0.7).abs() * 2.5)).clamp(0.25, 1.0);
        }

        final icon = isRight ? Icons.chevron_right_rounded : Icons.chevron_left_rounded;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white.withOpacity(c1), size: isRight ? 22 : 30),
            Icon(icon, color: Colors.white.withOpacity(c2), size: 26),
            Icon(icon, color: Colors.white.withOpacity(c3), size: isRight ? 30 : 22),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_useLocalOverlayFallback)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                color: Colors.black.withOpacity((1.0 - _brightness).clamp(0.0, 0.85)),
              ),
            ),
          ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onScaleUpdate: (details) {
            if (widget.isLocked) return;
            if (details.pointerCount >= 2) {
              _singleTapTimer?.cancel();
              _singleTapTimer = null;
              _lastTapTime = null;
              _lastTapSide = null;
              if (_isDoubleTapSeeking) {
                _endDoubleTapSeek();
              }
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
                  onTap: () => _handleTap(false),
                  onLongPress: _handleLongPress,
                  onVerticalDragStart: widget.isLocked ? null : _onVerticalDragStart,
                  onVerticalDragUpdate: widget.isLocked ? null : (d) => _onVerticalDragUpdate(d, true),
                  onVerticalDragEnd: widget.isLocked ? null : _onVerticalDragEnd,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _handleTap(true),
                  onLongPress: _handleLongPress,
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
            child: IgnorePointer(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ClipPath(
                  clipper: _SideArcClipper(isRight: _isSeekingRight),
                  child: Container(
                    width: MediaQuery.sizeOf(context).width * 0.42,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _isSeekingRight
                              ? Colors.white.withOpacity(0.0)
                              : Colors.white.withOpacity(0.18),
                          _isSeekingRight
                              ? Colors.white.withOpacity(0.18)
                              : Colors.white.withOpacity(0.0),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildChevrons(_isSeekingRight),
                          const SizedBox(height: 10),
                          ScaleTransition(
                            scale: _pulseScaleAnimation,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.45),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.15),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                _seekText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(0, 1),
                                      blurRadius: 4,
                                      color: Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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

class _SideArcClipper extends CustomClipper<Path> {
  final bool isRight;
  const _SideArcClipper({required this.isRight});

  @override
  Path getClip(Size size) {
    final path = Path();
    if (isRight) {
      path.moveTo(size.width, 0);
      path.lineTo(size.width * 0.25, 0);
      path.quadraticBezierTo(
        -size.width * 0.15,
        size.height * 0.5,
        size.width * 0.25,
        size.height,
      );
      path.lineTo(size.width, size.height);
      path.close();
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width * 0.75, 0);
      path.quadraticBezierTo(
        size.width * 1.15,
        size.height * 0.5,
        size.width * 0.75,
        size.height,
      );
      path.lineTo(0, size.height);
      path.close();
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _SideArcClipper oldClipper) => oldClipper.isRight != isRight;
}
