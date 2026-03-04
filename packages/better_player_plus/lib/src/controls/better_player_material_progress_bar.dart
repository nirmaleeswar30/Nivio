// ignore_for_file: cascade_invocations

import 'dart:async';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';
import 'package:better_player_plus/src/video_player/video_player.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/material.dart';

class BetterPlayerMaterialVideoProgressBar extends StatefulWidget {
  BetterPlayerMaterialVideoProgressBar(
    this.controller,
    this.betterPlayerController, {
    BetterPlayerProgressColors? colors,
    this.onDragEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.onTapDown,
    super.key,
  }) : colors = colors ?? BetterPlayerProgressColors();

  final VideoPlayerController? controller;
  final BetterPlayerController? betterPlayerController;
  final BetterPlayerProgressColors colors;
  final void Function()? onDragStart;
  final void Function()? onDragEnd;
  final void Function()? onDragUpdate;
  final void Function()? onTapDown;

  @override
  State<BetterPlayerMaterialVideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<BetterPlayerMaterialVideoProgressBar> {
  _VideoProgressBarState() {
    listener = () {
      if (mounted) {
        setState(() {});
      }
    };
  }

  late VoidCallback listener;
  bool _controllerWasPlaying = false;

  VideoPlayerController? get controller => widget.controller;

  BetterPlayerController? get betterPlayerController => widget.betterPlayerController;

  bool shouldPlayAfterDragEnd = false;
  Duration? lastSeek;
  Timer? _updateBlockTimer;
  bool _isScrubbing = false;
  double _scrubDx = 0;
  Duration _scrubPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    controller!.addListener(listener);
  }

  @override
  void deactivate() {
    controller!.removeListener(listener);
    _cancelUpdateBlockTimer();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final bool enableProgressBarDrag =
        betterPlayerController!.betterPlayerConfiguration.controlsConfiguration.enableProgressBarDrag;

    return GestureDetector(
      onHorizontalDragStart: (DragStartDetails details) {
        if (!controller!.value.initialized || !enableProgressBarDrag) {
          return;
        }

        _controllerWasPlaying = controller!.value.isPlaying;
        if (_controllerWasPlaying) {
          controller!.pause();
        }

        setState(() {
          _isScrubbing = true;
        });

        unawaited(seekToRelativePosition(details.globalPosition, updatePreview: true));

        if (widget.onDragStart != null) {
          widget.onDragStart!.call();
        }
      },
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        if (!controller!.value.initialized || !enableProgressBarDrag) {
          return;
        }

        unawaited(seekToRelativePosition(details.globalPosition, updatePreview: true));

        if (widget.onDragUpdate != null) {
          widget.onDragUpdate!.call();
        }
      },
      onHorizontalDragEnd: (DragEndDetails details) {
        if (!enableProgressBarDrag) {
          return;
        }

        setState(() {
          _isScrubbing = false;
        });

        if (_controllerWasPlaying) {
          betterPlayerController?.play();
          shouldPlayAfterDragEnd = true;
        }
        _setupUpdateBlockTimer();

        if (widget.onDragEnd != null) {
          widget.onDragEnd!.call();
        }
      },
      onTapDown: (TapDownDetails details) {
        if (!controller!.value.initialized || !enableProgressBarDrag) {
          return;
        }
        unawaited(seekToRelativePosition(details.globalPosition));
        _setupUpdateBlockTimer();
        if (widget.onTapDown != null) {
          widget.onTapDown!.call();
        }
      },
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final barValue = _getValue();
            final barWidth = constraints.maxWidth;
            final progress = _progress(barValue);
            final playheadX = _isScrubbing ? _scrubDx.clamp(0.0, barWidth) : barWidth * progress;

            return SizedBox(
              height: 30,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _ProgressBarPainter(barValue, widget.colors)),
                  ),
                  if (_isScrubbing)
                    Positioned(
                      left: (playheadX - 70).clamp(0.0, (barWidth - 140).clamp(0.0, double.infinity)),
                      bottom: 16,
                      child: _buildScrubPreview(),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  double _progress(VideoPlayerValue value) {
    if (!value.initialized || value.duration == null || value.duration!.inMilliseconds <= 0) {
      return 0;
    }
    final progress = value.position.inMilliseconds / value.duration!.inMilliseconds;
    if (progress.isNaN) {
      return 0;
    }
    return progress.clamp(0.0, 1.0);
  }

  Widget _buildScrubPreview() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 140,
          height: 78,
          color: Colors.black87,
          child: _buildPreviewImage(),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        BetterPlayerUtils.formatDuration(_scrubPosition),
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    ],
  );

  void _setupUpdateBlockTimer() {
    _updateBlockTimer = Timer(const Duration(milliseconds: 1000), () {
      lastSeek = null;
      _cancelUpdateBlockTimer();
    });
  }

  void _cancelUpdateBlockTimer() {
    _updateBlockTimer?.cancel();
    _updateBlockTimer = null;
  }

  VideoPlayerValue _getValue() {
    if (lastSeek != null) {
      return controller!.value.copyWith(position: lastSeek);
    } else {
      return controller!.value;
    }
  }

  Future<void> seekToRelativePosition(Offset globalPosition, {bool updatePreview = false}) async {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject != null) {
      final box = renderObject as RenderBox;
      final Offset tapPos = box.globalToLocal(globalPosition);
      final double relative = (tapPos.dx / box.size.width).clamp(0.0, 1.0);
      if (relative >= 0) {
        final Duration position = controller!.value.duration! * relative;

        if (updatePreview && mounted) {
          setState(() {
            _scrubDx = tapPos.dx;
            _scrubPosition = position;
          });
        }

        lastSeek = position;
        await betterPlayerController!.seekTo(position);
        onFinishedLastSeek();
        if (relative >= 1) {
          lastSeek = controller!.value.duration;
          await betterPlayerController!.seekTo(controller!.value.duration!);
          onFinishedLastSeek();
        }
      }
    }
  }

  void onFinishedLastSeek() {
    if (shouldPlayAfterDragEnd) {
      shouldPlayAfterDragEnd = false;
      betterPlayerController?.play();
    }
  }

  Widget _buildPreviewImage() {
    final imageUrl = betterPlayerController?.betterPlayerDataSource?.notificationConfiguration?.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.movie_outlined, color: Colors.white70),
      );
    }

    return const Icon(Icons.movie_outlined, color: Colors.white70);
  }
}

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter(this.value, this.colors);

  VideoPlayerValue value;
  BetterPlayerProgressColors colors;

  @override
  bool shouldRepaint(CustomPainter painter) => true;

  @override
  void paint(Canvas canvas, Size size) {
    const height = 2.0;
    const handleRadius = 5.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(Offset(0, size.height / 2), Offset(size.width, size.height / 2 + height)),
        const Radius.circular(4),
      ),
      colors.backgroundPaint,
    );
    if (!value.initialized) {
      return;
    }
    double playedPartPercent = value.position.inMilliseconds / value.duration!.inMilliseconds;
    if (playedPartPercent.isNaN) {
      playedPartPercent = 0;
    }
    final double playedPart = playedPartPercent > 1 ? size.width : playedPartPercent * size.width;
    for (final DurationRange range in value.buffered) {
      double start = range.startFraction(value.duration!) * size.width;
      if (start.isNaN) {
        start = 0;
      }
      double end = range.endFraction(value.duration!) * size.width;
      if (end.isNaN) {
        end = 0;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(Offset(start, size.height / 2), Offset(end, size.height / 2 + height)),
          const Radius.circular(4),
        ),
        colors.bufferedPaint,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(Offset(0, size.height / 2), Offset(playedPart, size.height / 2 + height)),
        const Radius.circular(4),
      ),
      colors.playedPaint,
    );
    canvas.drawCircle(Offset(playedPart, size.height / 2 + height / 2), handleRadius, colors.handlePaint);
  }
}
