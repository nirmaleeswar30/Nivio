import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nivio/providers/watch_party_provider.dart';
import 'package:nivio/widgets/watch_party_chat_overlay.dart';
import 'package:nivio/widgets/watch_party_reactions_overlay.dart';
import 'package:nivio/widgets/watch_party_participants_sheet.dart';
import 'gesture_layer.dart';

class CustomPlayerControls extends ConsumerStatefulWidget {
  final BetterPlayerController controller;
  final Function(bool visbility) onPlayerVisibilityChanged;
  final BetterPlayerControlsConfiguration controlsConfiguration;
  
  final String? title;
  final String? subtitle;
  final String? providerName;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final VoidCallback? onServerChange;
  final VoidCallback? onEpisodes;
  final bool isLive;

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
    this.onEpisodes,
    this.isLive = false,
  });

  @override
  ConsumerState<CustomPlayerControls> createState() => _CustomPlayerControlsState();
}

class _CustomPlayerControlsState extends ConsumerState<CustomPlayerControls> {
  bool _isPlaying = false;
  bool _showControls = true;
  bool _showChatOnly = false;
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
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() {
          _showControls = false;
          _showChatOnly = false;
        });
        widget.onPlayerVisibilityChanged(false);
      }
    });
  }

  void _showParticipantsPanel() {
    _startHideTimer();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Participants Overlay',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return const WatchPartyParticipantsSheet();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutExpo),
          ),
          child: child,
        );
      },
    );
  }

  void _onSingleTap() {
    if (_isLocked) {
      _onLockedSingleTap();
      return;
    }

    final isWatchParty = ref.read(watchPartySessionProvider).value != null;
    if (isWatchParty) {
      // Cycle: State 0 (Hidden) -> State 1 (Chat Only) -> State 2 (Both) -> State 0
      if (!_showControls && !_showChatOnly) {
        // Go to State 1 (Chat Only)
        setState(() {
          _showChatOnly = true;
          _showControls = false;
        });
        widget.onPlayerVisibilityChanged(false);
        _startHideTimer();
      } else if (!_showControls && _showChatOnly) {
        // Go to State 2 (Both)
        setState(() {
          _showChatOnly = false;
          _showControls = true;
        });
        widget.onPlayerVisibilityChanged(true);
        _startHideTimer();
      } else {
        // Go to State 0 (Hidden)
        setState(() {
          _showChatOnly = false;
          _showControls = false;
        });
        widget.onPlayerVisibilityChanged(false);
        _hideControlsTimer?.cancel();
      }
      return;
    }

    _toggleControls();
  }

  void _toggleControls() {
    if (_isLocked) return;
    setState(() {
      _showControls = !_showControls;
      _showChatOnly = false;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 250 || constraints.maxHeight < 200) {
          return const SizedBox.shrink();
        }
        return SizedBox.expand(
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
            onSingleTap: _onSingleTap,
            onLongPress: _toggleLock,
            onPinchZoom: (zoomIn) {
              final newFit = zoomIn ? BoxFit.cover : BoxFit.contain;
              widget.controller.setOverriddenFit(newFit);
            },
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
                          if (ref.watch(watchPartySessionProvider).value != null)
                            GestureDetector(
                              onTap: _showParticipantsPanel,
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.people, color: Colors.white, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${ref.watch(watchPartySessionProvider).value!.participants.length}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
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
                          if (!widget.isLive)
                            StreamBuilder(
                              stream: Stream.periodic(const Duration(milliseconds: 500)),
                              builder: (context, _) {
                                final vpController = widget.controller.videoPlayerController;
                                if (vpController == null) return const SizedBox.shrink();
                                
                                VideoPlayerValue? value;
                                try {
                                  value = vpController.value;
                                } catch (_) {
                                  // Controller was disposed during provider switch, ignore.
                                  return const SizedBox.shrink();
                                }
                                
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
                                          onChanged: (val) {
                                            setState(() {
                                              _dragValue = val;
                                            });
                                            _hideControlsTimer?.cancel();
                                          },
                                          onChangeEnd: (val) {
                                            widget.controller.seekTo(Duration(milliseconds: val.toInt()));
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
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
          // 4. Watch Party Overlays
          Consumer(
            builder: (context, ref, child) {
              if (ref.watch(watchPartySessionProvider).value == null) {
                return const SizedBox.shrink();
              }
              return Stack(
                children: [
                  Positioned.fill(
                    child: WatchPartyReactionsOverlay(),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: WatchPartyChatOverlay(
                      areControlsVisible: _showChatOnly && !_isLocked,
                      forceHide: _showControls,
                      onFocusChanged: (hasFocus) {
                        if (!hasFocus) {
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (!mounted) return;
                            final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
                            if (widget.controller.isFullScreen || isLandscape) {
                              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                            }
                          });
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
      },
    );
  }
}
