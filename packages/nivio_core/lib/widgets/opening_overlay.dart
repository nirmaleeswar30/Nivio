import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/tmdb_artwork.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/widgets/tab_artwork.dart' show ArtworkImage;

/// The title's clear logo (TMDB), or null when it has none.
final titleLogoProvider = FutureProvider.autoDispose
    .family<String?, SearchResult>((ref, media) async {
      final tmdb = ref.watch(tmdbServiceProvider);
      if (media.mediaType != 'anime') {
        return tmdb.getMediaLogo(media.id, media.mediaType);
      }
      final title = media.title ?? media.name;
      if (title == null || title.isEmpty) return null;
      return tmdb.getLogoByTitle(
        title,
        year: (media.releaseDate ?? media.firstAirDate)?.split('-').first,
      );
    });

/// A button under the loading status, such as opening the picker while
/// Autoplay searches.
class OpeningAction {
  const OpeningAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// Full-screen loading view shown while playback starts: the title's
/// artwork under a dark gradient, its clear logo gently zooming in the
/// middle, and the current status below it.
class OpeningOverlay extends ConsumerStatefulWidget {
  const OpeningOverlay({
    super.key,
    required this.media,
    required this.onClose,
    this.message,
    this.progress,
    this.details,
    this.action,
  });

  final SearchResult? media;
  final VoidCallback onClose;
  final String? message;
  final Widget? details;
  final OpeningAction? action;

  /// 0-1 when the stream reports progress (torrents); the logo fills with it.
  final double? progress;

  @override
  ConsumerState<OpeningOverlay> createState() => _OpeningOverlayState();
}

class _OpeningOverlayState extends ConsumerState<OpeningOverlay>
    with TickerProviderStateMixin {
  // Fades the logo in after a short pause.
  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  // Slow, endless zoom in and out.
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat(reverse: true);
  var _logoFailed = false;

  @override
  void dispose() {
    _reveal.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _pulse.isAnimating) _pulse.stop();
    final logo = media == null
        ? const AsyncValue<String?>.data(null)
        : ref.watch(titleLogoProvider(media));
    final artwork = media?.backdropPath?.isNotEmpty == true
        ? (media!.backdropPath!, ArtworkKind.backdrop)
        : media?.posterPath?.isNotEmpty == true
        ? (media!.posterPath!, ArtworkKind.poster)
        : null;
    final title = media?.title ?? media?.name;
    final progress = widget.progress?.clamp(0.0, 1.0);

    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final logoWidth = math.min(320.0, bounds.maxWidth - 48);
          final logoHeight = math.min(180.0, bounds.maxHeight * .4);
          final alpha = CurvedAnimation(
            parent: _reveal,
            // 400 ms wait, then a 700 ms fade.
            curve: const Interval(400 / 1100, 1),
          );
          Widget animate(Widget child, {bool zoom = true}) => FadeTransition(
            opacity: alpha,
            child: zoom && !reduceMotion
                ? ScaleTransition(
                    scale: Tween(begin: 1.0, end: 1.04).animate(_pulse),
                    child: child,
                  )
                : child,
          );

          Widget centre;
          final logoUrl = logo.value;
          if (logo.isLoading) {
            centre = SizedBox(width: logoWidth, height: logoHeight);
          } else if (logoUrl != null && logoUrl.isNotEmpty && !_logoFailed) {
            Widget image() => ArtworkImage(
              imageUrl: logoUrl,
              kind: ArtworkKind.logo,
              width: logoWidth,
              height: logoHeight,
              fit: BoxFit.contain,
              fadeInDuration: Duration.zero,
              errorWidget: (_, _, _) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_logoFailed) {
                    setState(() => _logoFailed = true);
                  }
                });
                return const SizedBox.shrink();
              },
            );
            centre = progress == null
                ? animate(image())
                : Stack(
                    children: [
                      Opacity(opacity: .25, child: image()),
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: progress),
                        duration: Duration(
                          milliseconds: progress >= .999 ? 160 : 400,
                        ),
                        builder: (context, value, child) => ClipRect(
                          clipper: _ProgressClipper(value),
                          child: child,
                        ),
                        child: image(),
                      ),
                    ],
                  );
          } else if (title != null && title.isNotEmpty) {
            centre = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: animate(
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: bounds.maxWidth < 600 ? 30 : 42,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            );
          } else {
            centre = const SizedBox.square(
              dimension: 54,
              child: _ArcLoadingIndicator(),
            );
          }

          final message = widget.message?.trim();
          final showBar =
              progress != null &&
              (logoUrl == null || logoUrl.isEmpty || _logoFailed);

          return Stack(
            fit: StackFit.expand,
            children: [
              if (artwork != null) ...[
                ArtworkImage(
                  imageUrl: artwork.$1,
                  kind: artwork.$2,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x4D000000),
                        Color(0x99000000),
                        Color(0xCC000000),
                        Color(0xE6000000),
                      ],
                      stops: [0, .35, .7, 1],
                    ),
                  ),
                ),
              ],
              // The logo sits in the exact middle; the status hangs below.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: CustomMultiChildLayout(
                  delegate: _CentreAndBelow(),
                  children: [
                    LayoutId(id: _Slot.centre, child: centre),
                    LayoutId(
                      id: _Slot.below,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: widget.details == null ? 16 : 12),
                          SizedBox(
                            height: widget.details == null ? 40 : 32,
                            width: bounds.maxWidth,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              child: message == null || message.isEmpty
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      key: ValueKey(message),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                      ),
                                      child: Text(
                                        message,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: .72,
                                          ),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: .5,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          if (widget.details case final details?)
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: details,
                              ),
                            ),
                          if (showBar) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: SizedBox(
                                width: 240,
                                height: 4,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(end: progress),
                                  duration: const Duration(milliseconds: 400),
                                  builder: (context, value, _) =>
                                      LinearProgressIndicator(
                                        value: value,
                                        backgroundColor: Colors.white
                                            .withValues(alpha: .2),
                                        color: Colors.white.withValues(
                                          alpha: .85,
                                        ),
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Autoplay's way out to the stream list: a compact pill in the
              // top-left corner, level with the close button and clear of the
              // logo and status.
              Positioned(
                top: MediaQuery.paddingOf(context).top + 20,
                left: 20,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: switch (widget.action) {
                      final action? => FilledButton.icon(
                        key: ValueKey(action.label),
                        onPressed: action.onPressed,
                        icon: const Icon(
                          Icons.format_list_bulleted_rounded,
                          size: 18,
                        ),
                        label: Text(action.label),
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.white,
                          // Same look as the close button opposite.
                          backgroundColor: Colors.black.withValues(alpha: .3),
                          overlayColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: .22),
                          ),
                          shape: const StadiumBorder(),
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      null => const SizedBox.shrink(),
                    },
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 20,
                right: 20,
                child: Material(
                  color: Colors.black.withValues(alpha: .3),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.onClose,
                    child: const SizedBox.square(
                      dimension: 44,
                      child: Tooltip(
                        message: 'Close',
                        child: Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _Slot { centre, below }

/// Centres [_Slot.centre] in the space and places [_Slot.below] right under
/// it, so a changing status never moves the logo.
class _CentreAndBelow extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size);
    final centre = layoutChild(_Slot.centre, loose);
    final top = (size.height - centre.height) / 2;
    positionChild(_Slot.centre, Offset((size.width - centre.width) / 2, top));
    final belowTop = top + centre.height;
    final below = layoutChild(
      _Slot.below,
      loose.copyWith(maxHeight: math.max(0, size.height - belowTop)),
    );
    positionChild(
      _Slot.below,
      Offset((size.width - below.width) / 2, belowTop),
    );
  }

  @override
  bool shouldRelayout(_CentreAndBelow oldDelegate) => false;
}

class _ProgressClipper extends CustomClipper<Rect> {
  _ProgressClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_ProgressClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

/// A single arc that chases itself round, for titles without logo or name.
class _ArcLoadingIndicator extends StatefulWidget {
  const _ArcLoadingIndicator();

  @override
  State<_ArcLoadingIndicator> createState() => _ArcLoadingIndicatorState();
}

class _ArcLoadingIndicatorState extends State<_ArcLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final _frame = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ArcPainter(_frame, Theme.of(context).colorScheme.primary),
  );
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.frame, this.color) : super(repaint: frame);

  final Animation<double> frame;
  final Color color;
  static const _easing = Cubic(.333, 0, .667, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final current = frame.value * 60;
    final scale = size.shortestSide * .75 / 350;
    final radius = 150 * scale;
    double lerp(double a, double b, double t) => a + (b - a) * t;
    final start = lerp(
      0,
      99,
      _easing.transform(((current - 10) / 50).clamp(0.0, 1.0)),
    );
    final end = lerp(1, 100, _easing.transform((current / 50).clamp(0.0, 1.0)));
    double radians(double degrees) => degrees * math.pi / 180;
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: radius),
      radians(-90 + current / 60 * 363 + start * 3.6),
      radians((end - start) * 3.6),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 50 * scale
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) => oldDelegate.color != color;
}
