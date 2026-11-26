import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nivio/core/theme.dart';

OverlayEntry? _currentToast;

/// Shows a short confirmation pill near the bottom of the window.
///
/// Drawn on the root overlay, so it stays visible above dialogs, bottom
/// sheets and the player, unlike a SnackBar, which belongs to one Scaffold.
void showAppToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_rounded,
  Duration duration = const Duration(milliseconds: 2200),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _currentToast?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AppToast(
      message: message,
      icon: icon,
      duration: duration,
      onDone: () {
        if (identical(_currentToast, entry)) _currentToast = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _currentToast = entry;
  overlay.insert(entry);
}

class _AppToast extends StatefulWidget {
  const _AppToast({
    required this.message,
    required this.icon,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final IconData icon;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 200),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(widget.duration, () async {
      if (!mounted) return;
      await _controller.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = NivioTheme.themeColorsOf(context);
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    final bottom = MediaQuery.paddingOf(context).bottom + 32;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _controller,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, .6),
                end: Offset.zero,
              ).animate(curve),
              child: ScaleTransition(
                scale: Tween(begin: .9, end: 1.0).animate(curve),
                child: Material(
                  color: Color.alphaBlend(
                    palette.textPrimary.withValues(alpha: .08),
                    palette.surfaceContainer,
                  ),
                  elevation: 10,
                  shadowColor: Colors.black,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: palette.textPrimary.withValues(alpha: .10),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 11, 18, 11),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, size: 19, color: palette.primary),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
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
      ),
    );
  }
}

/// Shrinks its child while a pointer is down and springs it back on release.
class PressBounce extends StatefulWidget {
  const PressBounce({super.key, required this.child, this.pressedScale = .86});

  final Widget child;
  final double pressedScale;

  @override
  State<PressBounce> createState() => _PressBounceState();
}

class _PressBounceState extends State<PressBounce> {
  var _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _pressed ? widget.pressedScale : 1,
      duration: Duration(milliseconds: _pressed ? 90 : 420),
      curve: _pressed ? Curves.easeOut : Curves.elasticOut,
      child: widget.child,
    ),
  );
}

/// Swaps [icon] for a check mark while [done] is true, with a pop.
class ConfirmIconSwap extends StatelessWidget {
  const ConfirmIconSwap({
    super.key,
    required this.done,
    required this.icon,
    this.size = 24,
    this.color,
  });

  final bool done;
  final Widget icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 260),
    switchInCurve: Curves.easeOutBack,
    switchOutCurve: Curves.easeIn,
    transitionBuilder: (child, animation) => ScaleTransition(
      scale: animation,
      child: FadeTransition(opacity: animation, child: child),
    ),
    child: done
        ? Icon(
            Icons.check_rounded,
            key: const ValueKey(true),
            size: size,
            color: color ?? NivioTheme.accentColorOf(context),
          )
        : KeyedSubtree(key: const ValueKey(false), child: icon),
  );
}
