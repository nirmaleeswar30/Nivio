import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nivio/main.dart'; // To access appRouter
import 'package:nivio/widgets/custom_title_bar.dart';

class TitleBarOverlay extends StatefulWidget {
  const TitleBarOverlay({super.key});

  @override
  State<TitleBarOverlay> createState() => _TitleBarOverlayState();
}

class _TitleBarOverlayState extends State<TitleBarOverlay> {
  bool _showTitleBar = true;

  @override
  void initState() {
    super.initState();
    appRouter.routerDelegate.addListener(_routeListener);
    _checkRoute();
  }

  @override
  void dispose() {
    appRouter.routerDelegate.removeListener(_routeListener);
    super.dispose();
  }

  void _routeListener() {
    _checkRoute();
  }

  void _checkRoute() {
    final path = appRouter.routerDelegate.currentConfiguration.uri.path;
    final isPlayer = path.startsWith('/player');
    if (_showTitleBar == isPlayer) {
      setState(() {
        _showTitleBar = !isPlayer;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return const SizedBox.shrink();
    }
    
    if (!_showTitleBar) {
      return const SizedBox.shrink();
    }

    return const Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: CustomTitleBar(),
    );
  }
}
