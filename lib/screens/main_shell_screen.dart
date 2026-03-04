import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class MainShellScreen extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainShellScreen({super.key, required this.navigationShell});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  DateTime? _lastBackPressAt;

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  void _handleRootBackPress(BuildContext context) {
    final now = DateTime.now();

    // If not on home tab, navigate to home first
    if (widget.navigationShell.currentIndex != 0) {
      widget.navigationShell.goBranch(0);
      _lastBackPressAt = null; // Reset exit timer when switching tabs
      return;
    }

    // If GoRouter has navigation history (e.g., after returning from media detail),
    // clear it by going to home explicitly
    if (context.canPop()) {
      context.go('/home');
      _lastBackPressAt = null;
      return;
    }

    // On home tab with no navigation history - handle exit logic
    final shouldExit =
        _lastBackPressAt != null &&
        now.difference(_lastBackPressAt!) <= const Duration(seconds: 2);

    if (shouldExit) {
      SystemNavigator.pop();
      return;
    }

    _lastBackPressAt = now;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Press back again to exit'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleRootBackPress(context);
        }
      },
      child: Scaffold(
        body: widget.navigationShell,
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: NivioTheme.netflixBlack,
            border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
          ),
          child: BottomNavigationBar(
            currentIndex: widget.navigationShell.currentIndex,
            onTap: _onTap,
            backgroundColor: NivioTheme.netflixBlack,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: NivioTheme.netflixRed,
            unselectedItemColor: NivioTheme.netflixGrey,
            showUnselectedLabels: true,
            selectedLabelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            items: const [
              BottomNavigationBarItem(
                icon: PhosphorIcon(
                  PhosphorIconsRegular.house,
                  color: NivioTheme.netflixGrey,
                  size: 22,
                ),
                activeIcon: PhosphorIcon(
                  PhosphorIconsFill.house,
                  color: NivioTheme.netflixRed,
                  size: 22,
                ),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: PhosphorIcon(
                  PhosphorIconsRegular.magnifyingGlass,
                  color: NivioTheme.netflixGrey,
                  size: 22,
                ),
                activeIcon: PhosphorIcon(
                  PhosphorIconsFill.magnifyingGlass,
                  color: NivioTheme.netflixRed,
                  size: 22,
                ),
                label: 'Discover',
              ),
              BottomNavigationBarItem(
                icon: PhosphorIcon(
                  PhosphorIconsRegular.calendarBlank,
                  color: NivioTheme.netflixGrey,
                  size: 22,
                ),
                activeIcon: PhosphorIcon(
                  PhosphorIconsFill.calendarCheck,
                  color: NivioTheme.netflixRed,
                  size: 22,
                ),
                label: 'Library',
              ),
              BottomNavigationBarItem(
                icon: PhosphorIcon(
                  PhosphorIconsRegular.userCircle,
                  color: NivioTheme.netflixGrey,
                  size: 22,
                ),
                activeIcon: PhosphorIcon(
                  PhosphorIconsFill.userCircle,
                  color: NivioTheme.netflixRed,
                  size: 22,
                ),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
