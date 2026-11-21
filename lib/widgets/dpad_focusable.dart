import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:nivio/core/app_platform.dart';

/// How a [DpadFocusable] shows remote focus on a TV.
enum DpadFocusStyle {
  /// Draw the outline while keeping the control's appearance steady.
  outline,

  /// Also scale up visual cards slightly.
  lift,
}

/// Makes a mouse/touch-only tappable (e.g. a `MouseRegion` + `GestureDetector`
/// poster card) reachable with an Android TV remote.
///
/// On a TV it joins focus traversal, so the D-pad arrows can move onto it
/// (and scrolling lists bring it into view), runs [onActivate] on OK, and
/// animates in [style] while focused. Everywhere else it is a no-op and just
/// returns [child], so phone and desktop behave exactly as before.
class DpadFocusable extends StatefulWidget {
  const DpadFocusable({
    super.key,
    required this.child,
    required this.onActivate,
    this.style = DpadFocusStyle.outline,
    this.onFocusChange,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.autofocus = false,
    this.requestFocusOnMount = false,
    this.focusNode,
  });

  final Widget child;

  /// What OK does; normally the same as the card's tap.
  final VoidCallback? onActivate;

  final DpadFocusStyle style;

  /// Reports when the focus look appears or goes away.
  final ValueChanged<bool>? onFocusChange;

  final BorderRadius borderRadius;


  final bool autofocus;

  /// Takes focus as soon as it appears, even when something else on the page
  /// already has it (unlike [autofocus]), e.g. a "Skip Intro" button popping
  /// up over the player.
  final bool requestFocusOnMount;

  final FocusNode? focusNode;

  @override
  State<DpadFocusable> createState() => _DpadFocusableState();
}

/// Drop-in for a tap-only `GestureDetector` that a TV remote can also focus
/// and activate (see [DpadFocusable]). Off TV it is exactly that
/// `GestureDetector`.
class FocusableTap extends StatelessWidget {
  const FocusableTap({
    super.key,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.onDoubleTap,
    this.behavior,
    this.style = DpadFocusStyle.outline,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.requestFocusOnMount = false,
    this.autofocus = false,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final HitTestBehavior? behavior;
  final DpadFocusStyle style;
  final BorderRadius borderRadius;
  final bool requestFocusOnMount;
  final bool autofocus;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final detector = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onDoubleTap: onDoubleTap,
      behavior: behavior,
      child: child,
    );
    if (!AppPlatform.isTv) return detector;
    return DpadFocusable(
      onActivate: onTap,
      style: style,
      borderRadius: borderRadius,
      requestFocusOnMount: requestFocusOnMount,
      autofocus: autofocus,
      child: detector,
    );
  }
}

/// Drop-in for an `InkWell` that gets its TV remote focus look and OK
/// activation from [DpadFocusable] (InkWell's own focus highlight is faint,
/// or hidden under opaque children). Off TV it is exactly that `InkWell`.
class FocusableInkWell extends StatelessWidget {
  const FocusableInkWell({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius,
    this.style = DpadFocusStyle.outline,
    this.autofocus = false,
    this.requestFocusOnMount = false,
    this.focusNode,
  });

  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final DpadFocusStyle style;
  final bool autofocus;
  final bool requestFocusOnMount;
  final FocusNode? focusNode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.isTv) {
      return InkWell(onTap: onTap, borderRadius: borderRadius, child: child);
    }
    return DpadFocusable(
      onActivate: onTap,
      style: style,
      borderRadius: borderRadius ?? const BorderRadius.all(Radius.circular(8)),
      autofocus: autofocus,
      requestFocusOnMount: requestFocusOnMount,
      focusNode: focusNode,
      child: InkWell(
        canRequestFocus: false,
        onTap: onTap,
        borderRadius: borderRadius,
        child: child,
      ),
    );
  }
}

class _DpadFocusableState extends State<DpadFocusable> {
  FocusNode? _ownNode;

  FocusNode get _node =>
      widget.focusNode ?? (_ownNode ??= FocusNode(debugLabel: 'DpadFocusable'));

  @override
  void initState() {
    super.initState();
    if (AppPlatform.isTv && widget.requestFocusOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.isTv) return widget.child;
    final node = _node;
    final lift = widget.style == DpadFocusStyle.lift;
    return FocusableActionDetector(
      focusNode: node,
      autofocus: widget.autofocus,
      enabled: widget.onActivate != null,
      mouseCursor: MouseCursor.defer,
      onShowFocusHighlight: widget.onFocusChange,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate?.call();
            return null;
          },
        ),
      },
      child: ListenableBuilder(
        listenable: node,
        child: widget.child,
        builder: (context, child) {
          final focused = node.hasPrimaryFocus && widget.onActivate != null;
          final outlined = TvFocusOutline(
            focused: focused,
            borderRadius: widget.borderRadius,
            child: child!,
          );
          if (!lift) return outlined;
          return AnimatedScale(
            scale: focused ? 1.04 : 1.0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: outlined,
          );
        },
      ),
    );
  }
}

/// Paints remote focus over the control so opaque cards cannot hide it.
/// The outline sits inside the control's bounds, where list clips won't cut it off.
class TvFocusOutline extends StatelessWidget {
  const TvFocusOutline({
    super.key,
    required this.focused,
    required this.borderRadius,
    required this.child,
  });

  final bool focused;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: focused ? _TvFocusOutlinePainter(borderRadius) : null,
      child: child,
    );
  }
}

class _TvFocusOutlinePainter extends CustomPainter {
  const _TvFocusOutlinePainter(this.borderRadius);

  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    const edgeWidth = 5.0;
    if (size.shortestSide <= edgeWidth) return;
    final outline = borderRadius
        .toRRect(Offset.zero & size)
        .scaleRadii()
        .deflate(edgeWidth / 2);
    final paint = Paint()..style = PaintingStyle.stroke;
    canvas.drawRRect(
      outline,
      paint
        ..strokeWidth = edgeWidth
        ..color = const Color(0xE6000000),
    );
    canvas.drawRRect(
      outline,
      paint
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_TvFocusOutlinePainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius;
}

/// TV: a "View all" tile for the end of a shelf. The shelf's header link sits
/// top-right where the remote rarely reaches it; this puts it one Right press
/// past the last card. Only build it on TV.
class TvSeeAllTile extends StatelessWidget {
  const TvSeeAllTile({
    super.key,
    required this.onTap,
    required this.width,
    required this.height,
    this.label = 'View all',
  });

  final VoidCallback onTap;
  final double width;
  final double height;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E24),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white70,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// TV: stops a text field from grabbing D-pad focus as you move past it
/// (focusing it opens the on-screen keyboard and up/down get stuck in it).
/// The arrows stop on a highlight around the field instead; OK starts typing
/// and up/down while typing move on. Off TV it just builds the field, with a
/// null focus node, exactly as before.
class TvTextFieldGate extends StatefulWidget {
  const TvTextFieldGate({
    super.key,
    required this.builder,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
  });

  /// Builds the field; pass `focusNode` to its `focusNode`.
  final Widget Function(BuildContext context, FocusNode? focusNode) builder;
  final BorderRadius borderRadius;

  @override
  State<TvTextFieldGate> createState() => _TvTextFieldGateState();
}

class _TvTextFieldGateState extends State<TvTextFieldGate> {
  final FocusNode _gateNode = FocusNode(debugLabel: 'tvFieldGate');
  final FocusNode _fieldNode =
      FocusNode(debugLabel: 'tvField', skipTraversal: true);

  @override
  void dispose() {
    _gateNode.dispose();
    _fieldNode.dispose();
    super.dispose();
  }

  KeyEventResult _leaveField(FocusNode node, KeyEvent event) {
    if (!_fieldNode.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;
    if (!_gateNode.focusInDirection(direction)) _gateNode.requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.isTv) return widget.builder(context, null);
    return DpadFocusable(
      focusNode: _gateNode,
      borderRadius: widget.borderRadius,
      onActivate: _fieldNode.requestFocus,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _leaveField,
        child: widget.builder(context, _fieldNode),
      ),
    );
  }
}

/// TV: draws [child] at [factor] of its normal size while still filling the
/// same width (it is laid out with 1/[factor] the room, then scaled down).
/// Off TV it just returns [child].
class TvShrink extends StatelessWidget {
  const TvShrink({
    super.key,
    required this.child,
    this.factor = 0.85,
    this.alignment = Alignment.bottomLeft,
  });

  final Widget child;
  final double factor;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.isTv) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) return child;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: SizedBox(width: constraints.maxWidth / factor, child: child),
        );
      },
    );
  }
}
