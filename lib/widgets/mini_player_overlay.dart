import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:nivio/main.dart'; // To access appRouter
import 'package:nivio/providers/mini_player_provider.dart';

/// A floating, draggable mini video player overlay that snaps to screen edges.
///
/// Sits at the app root level (in [MaterialApp.router]'s builder) and only
/// renders when [miniPlayerProvider] is active. Desktop only.
class MiniPlayerOverlay extends ConsumerStatefulWidget {
  const MiniPlayerOverlay({super.key});

  @override
  ConsumerState<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends ConsumerState<MiniPlayerOverlay>
    with SingleTickerProviderStateMixin {
  // Position (bottom-right offset from edges)
  double _left = double.infinity; // Will be computed on first build
  double _top = double.infinity;
  bool _isPositionInitialized = false;

  // Drag state
  Offset? _dragStartOffset;
  double? _dragStartLeft;
  double? _dragStartTop;

  // Animation
  late final AnimationController _animController;
  late Animation<Offset> _snapAnimation;
  bool _isSnapping = false;

  // Dimensions
  static const double _width = 320.0;
  static const double _height = 180.0;
  static const double _edgePadding = 16.0;
  static const double _borderRadius = 12.0;

  // Hover
  bool _isHovered = false;
  bool _videoDetached = false; // When true, Video is removed before navigating to full player

  // Progress tracking
  // ignore: unused_field
  Duration _position = Duration.zero;
  // ignore: unused_field
  Duration _duration = Duration.zero;
  bool _isPlaying = true;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animController.addListener(() {
      if (_isSnapping) {
        setState(() {
          _left = _snapAnimation.value.dx;
          _top = _snapAnimation.value.dy;
        });
      }
    });
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _isSnapping = false;
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _subscribeToPlayer() {
    final state = ref.read(miniPlayerProvider);
    final player = state.player;
    if (player == null) return;

    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();

    _position = player.state.position;
    _duration = player.state.duration;
    _isPlaying = player.state.playing;

    _positionSub = player.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _durationSub = player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _playingSub = player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
  }

  void _initPosition(Size screenSize) {
    if (!_isPositionInitialized) {
      _left = screenSize.width - _width - _edgePadding;
      _top = screenSize.height - _height - _edgePadding;
      _isPositionInitialized = true;
    }
  }

  void _onPanStart(DragStartDetails details) {
    _dragStartOffset = details.globalPosition;
    _dragStartLeft = _left;
    _dragStartTop = _top;
    _isSnapping = false;
    _animController.stop();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final screenSize = MediaQuery.sizeOf(context);
    final dx = details.globalPosition.dx - _dragStartOffset!.dx;
    final dy = details.globalPosition.dy - _dragStartOffset!.dy;

    setState(() {
      _left = (_dragStartLeft! + dx).clamp(_edgePadding, screenSize.width - _width - _edgePadding);
      _top = (_dragStartTop! + dy).clamp(_edgePadding, screenSize.height - _height - _edgePadding);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final screenSize = MediaQuery.sizeOf(context);
    final centerX = _left + _width / 2;
    final centerY = _top + _height / 2;

    // Snap to nearest edge/corner
    final targetLeft = centerX < screenSize.width / 2
        ? _edgePadding
        : screenSize.width - _width - _edgePadding;
    final targetTop = centerY < screenSize.height / 2
        ? _edgePadding
        : screenSize.height - _height - _edgePadding;

    _snapAnimation = Tween<Offset>(
      begin: Offset(_left, _top),
      end: Offset(targetLeft, targetTop),
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _isSnapping = true;
    _animController.forward(from: 0);
  }

  void _expandToFullScreen() {
    final state = ref.read(miniPlayerProvider);
    final info = state.mediaInfo;
    if (info == null) return;
    if (_videoDetached) return; // Already expanding, prevent double-tap

    // Unfocus any active element to avoid AXTree focus node corruption on Windows
    FocusManager.instance.primaryFocus?.unfocus();

    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _positionSub = null;
    _durationSub = null;
    _playingSub = null;

    setState(() {
      _videoDetached = true;
      _isHovered = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      appRouter.push(
        '/player/${info.mediaId}?season=${info.season}&episode=${info.episode}'
        '${info.mediaType != null ? '&type=${info.mediaType}' : ''}',
      );
    });
  }

  void _close() {
    FocusManager.instance.primaryFocus?.unfocus();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _positionSub = null;
    _durationSub = null;
    _playingSub = null;

    setState(() {
      _videoDetached = true;
      _isHovered = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(miniPlayerProvider.notifier).deactivate();
      _isPositionInitialized = false;
      _videoDetached = false;
    });
  }

  void _togglePlayPause() {
    final player = ref.read(miniPlayerProvider).player;
    if (player == null) return;
    player.playOrPause();
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    if (!isDesktop) return const SizedBox.shrink();

    final miniState = ref.watch(miniPlayerProvider);
    if (!miniState.isActive || miniState.videoController == null) {
      // Clean up subscriptions when deactivated
      _positionSub?.cancel();
      _durationSub?.cancel();
      _playingSub?.cancel();
      _positionSub = null;
      _durationSub = null;
      _playingSub = null;
      _isPositionInitialized = false;
      _videoDetached = false;
      return const SizedBox.shrink();
    }

    // Subscribe to player streams if not yet subscribed
    if (_positionSub == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _subscribeToPlayer();
      });
    }

    final screenSize = MediaQuery.sizeOf(context);
    _initPosition(screenSize);

    return Positioned(
      left: _left,
      top: _top,
      child: ExcludeSemantics(
        child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTap: _expandToFullScreen,
        child: MouseRegion(
          onEnter: (_) {
            if (mounted) setState(() => _isHovered = true);
          },
          onExit: (_) {
            if (mounted) setState(() => _isHovered = false);
          },
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _width,
              height: _height,
              decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_borderRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _isHovered ? 0.6 : 0.4),
                  blurRadius: _isHovered ? 24 : 16,
                  spreadRadius: _isHovered ? 2 : 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_borderRadius),
              child: Stack(
                children: [
                  // Video surface
                  Positioned.fill(
                    child: _videoDetached
                        ? Container(color: Colors.black)
                        : Video(
                            controller: miniState.videoController!,
                            controls: NoVideoControls,
                            fill: Colors.black,
                          ),
                  ),

                  // Gradient overlay (always visible, stronger on hover)
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: _isHovered ? 1.0 : 0.3,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.4),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.7),
                            ],
                            stops: const [0.0, 0.4, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Title (top)
                  if (_isHovered && miniState.mediaInfo?.title != null)
                    Positioned(
                      top: 8,
                      left: 10,
                      right: 40,
                      child: Text(
                        miniState.mediaInfo!.title!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 4),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  // Close button (top-right)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: AnimatedOpacity(
                      opacity: _isHovered ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: _MiniPlayerButton(
                        icon: Icons.close_rounded,
                        size: 18,
                        onTap: _close,
                        tooltip: 'Close',
                      ),
                    ),
                  ),

                  // Center play/pause
                  Center(
                    child: AnimatedOpacity(
                      opacity: _isHovered ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: _MiniPlayerButton(
                        icon: _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 32,
                        onTap: _togglePlayPause,
                        tooltip: _isPlaying ? 'Pause' : 'Play',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ), // End Material
        ),
      ),
      ),
    );
  }
}

/// Small icon button for mini player controls.
class _MiniPlayerButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final String tooltip;

  const _MiniPlayerButton({
    required this.icon,
    required this.size,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}
