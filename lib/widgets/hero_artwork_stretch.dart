import 'package:flutter/widgets.dart';

/// Keeps the artwork anchored to the top while a pull stretches the hero.
class HeroArtworkStretch extends StatelessWidget {
  const HeroArtworkStretch({
    super.key,
    required this.controller,
    required this.height,
    required this.child,
    this.movesWithScroll = true,
  });

  final ScrollController controller;
  final double height;
  final Widget child;
  final bool movesWithScroll;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, artwork) {
        if (controller.positions.length != 1 ||
            !controller.position.hasContentDimensions) {
          return artwork!;
        }
        final position = controller.position;
        final pull = (position.minScrollExtent - position.pixels).clamp(
          0.0,
          height,
        );
        if (pull == 0) return artwork!;
        return ClipRect(
          clipper: _StretchClip(pull),
          child: Transform.translate(
            offset: Offset(0, movesWithScroll ? -pull : 0),
            child: Transform.scale(
              alignment: Alignment.topCenter,
              scale: 1 + pull / height,
              child: artwork,
            ),
          ),
        );
      },
    );
  }
}

class _StretchClip extends CustomClipper<Rect> {
  const _StretchClip(this.pull);

  final double pull;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, -pull, size.width, size.height);

  @override
  bool shouldReclip(_StretchClip oldClipper) => oldClipper.pull != pull;
}
