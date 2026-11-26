import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nivio/main.dart'; // To access appRouter
import 'package:nivio/services/window_fullscreen.dart';
import 'package:nivio/widgets/custom_title_bar.dart';

/// Height of the custom window title bar drawn over the app on desktop.
const double kDesktopTitleBarHeight = 32;

/// Whether the custom title bar is currently drawn: desktop only, hidden in
/// the player and in fullscreen.
mixin _TitleBarVisibility<T extends StatefulWidget> on State<T> {
  bool _onPlayer = false;

  static bool get _desktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (!_desktop) return;
    appRouter.routerDelegate.addListener(_checkRoute);
    _onPlayer = _isPlayerRoute;
  }

  @override
  void dispose() {
    if (_desktop) appRouter.routerDelegate.removeListener(_checkRoute);
    super.dispose();
  }

  bool get _isPlayerRoute => appRouter
      .routerDelegate
      .currentConfiguration
      .uri
      .path
      .startsWith('/player');

  void _checkRoute() {
    final onPlayer = _isPlayerRoute;
    if (onPlayer != _onPlayer) setState(() => _onPlayer = onPlayer);
  }

  Widget buildWhenShown(Widget Function(bool shown) builder) {
    if (!_desktop || _onPlayer) return builder(false);
    return ValueListenableBuilder<bool>(
      valueListenable: windowFullScreenNotifier,
      builder: (context, isFullScreen, _) => builder(!isFullScreen),
    );
  }
}

class TitleBarOverlay extends StatefulWidget {
  const TitleBarOverlay({super.key});

  @override
  State<TitleBarOverlay> createState() => _TitleBarOverlayState();
}

class _TitleBarOverlayState extends State<TitleBarOverlay>
    with _TitleBarVisibility {
  @override
  Widget build(BuildContext context) => buildWhenShown(
    (shown) => shown
        ? const Positioned(top: 0, left: 0, right: 0, child: CustomTitleBar())
        : const SizedBox.shrink(),
  );
}

/// Reserves the title bar's strip as top padding while it is drawn, so
/// SafeArea, app bars and headers keep their buttons out from under it (the
/// bar's drag area takes every pointer event in that strip).
class TitleBarInset extends StatefulWidget {
  const TitleBarInset({super.key, required this.child});

  final Widget child;

  @override
  State<TitleBarInset> createState() => _TitleBarInsetState();
}

class _TitleBarInsetState extends State<TitleBarInset>
    with _TitleBarVisibility {
  @override
  Widget build(BuildContext context) => buildWhenShown((shown) {
    if (!shown) return widget.child;
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(
          top: math.max(media.padding.top, kDesktopTitleBarHeight),
        ),
        viewPadding: media.viewPadding.copyWith(
          top: math.max(media.viewPadding.top, kDesktopTitleBarHeight),
        ),
      ),
      child: widget.child,
    );
  });
}
