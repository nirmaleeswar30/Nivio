import 'dart:io';
import 'package:flutter/material.dart';

/// Lightweight skeleton placeholders — a low-cost replacement for spinners.
///
/// Design for minimal GPU/CPU:
/// * A single [Skeletonizer] ancestor owns ONE [AnimationController]; every
///   [SkeletonBox] below it reads the shared value via an [InheritedWidget], so
///   a whole screen of placeholders animates from one ticker (not one per box,
///   and not a spinning/rotating render like [CircularProgressIndicator]).
/// * The animated subtree is wrapped in a [RepaintBoundary], so the gentle
///   pulse never repaints anything outside the skeleton region.
/// * The pulse is a cheap two-colour [Color.lerp] (alpha/paint only) — no
///   moving gradient shader.
/// Set `animate: false` for a fully static skeleton (zero per-frame cost).
class Skeletonizer extends StatefulWidget {
  final Widget child;
  final bool animate;
  const Skeletonizer({super.key, required this.child, this.animate = true});

  @override
  State<Skeletonizer> createState() => _SkeletonizerState();
}

class _SkeletonizerState extends State<Skeletonizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    if (widget.animate) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => _ShimmerScope(
          t: widget.animate ? _controller.value : 1.0,
          child: child!,
        ),
        child: widget.child,
      ),
    );
  }
}

class _ShimmerScope extends InheritedWidget {
  final double t;
  const _ShimmerScope({required this.t, required super.child});

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.t ?? 1.0;

  @override
  bool updateShouldNotify(_ShimmerScope oldWidget) => oldWidget.t != t;
}

/// A single rounded placeholder block. Must have a [Skeletonizer] ancestor to
/// pulse; without one it renders as a static block.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadiusGeometry borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  static const Color _base = Color(0xFF23262E);
  static const Color _highlight = Color(0xFF31353F);

  @override
  Widget build(BuildContext context) {
    final t = _ShimmerScope.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.lerp(_base, _highlight, t),
        borderRadius: borderRadius,
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}

/// A horizontal content-row placeholder (title bar + poster cards) sized to
/// match [ContentRow].
class ContentRowSkeleton extends StatelessWidget {
  final bool showTitle;
  final int itemCount;
  const ContentRowSkeleton({super.key, this.showTitle = true, this.itemCount = 8});

  @override
  Widget build(BuildContext context) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final cardW = isDesktop ? 140.0 : 120.0;
    final cardH = isDesktop ? 210.0 : 170.0;
    final rowH = isDesktop ? 210.0 : 180.0;
    final leftPad = isDesktop ? 64.0 : 12.0;

    return Skeletonizer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTitle)
            Padding(
              padding: EdgeInsets.fromLTRB(leftPad, 0, 12, 12),
              child: const SkeletonBox(width: 170, height: 18),
            ),
          SizedBox(
            height: rowH,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.only(left: leftPad, right: 12),
              itemCount: itemCount,
              itemBuilder: (_, __) => Padding(
                padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 4),
                child: SkeletonBox(
                  width: cardW,
                  height: cardH,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A media-detail placeholder: backdrop, poster, and a few text lines.
class MediaDetailSkeleton extends StatelessWidget {
  const MediaDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final backdropH = (width * 0.56).clamp(180.0, 420.0);
    return Skeletonizer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(
              width: double.infinity,
              height: backdropH,
              borderRadius: BorderRadius.zero,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(
                    width: 110,
                    height: 165,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(width: double.infinity, height: 24),
                        SizedBox(height: 12),
                        SkeletonBox(width: 150, height: 16),
                        SizedBox(height: 22),
                        SkeletonBox(width: double.infinity, height: 12),
                        SizedBox(height: 8),
                        SkeletonBox(width: double.infinity, height: 12),
                        SizedBox(height: 8),
                        SkeletonBox(width: 200, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A poster-grid placeholder for full-screen grids (provider content, search…).
class PosterGridSkeleton extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final double maxCrossAxisExtent;
  final double childAspectRatio;
  final int itemCount;

  const PosterGridSkeleton({
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.maxCrossAxisExtent = 200,
    this.childAspectRatio = 0.68,
    this.itemCount = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      child: GridView.builder(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxCrossAxisExtent,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: itemCount,
        itemBuilder: (_, __) =>
            SkeletonBox(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}
