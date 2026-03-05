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
  DateTime? _lastBackHandledAt;

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  Future<bool> _onWillPop() async {
    final now = DateTime.now();

    // Some devices/OS versions may dispatch back callbacks twice for one press.
    // Ignore duplicate callbacks arriving too close together.
    if (_lastBackHandledAt != null &&
        now.difference(_lastBackHandledAt!) <=
            const Duration(milliseconds: 350)) {
      return false;
    }
    _lastBackHandledAt = now;

    // If not on home tab, navigate to home first
    if (widget.navigationShell.currentIndex != 0) {
      widget.navigationShell.goBranch(0);
      _lastBackPressAt = null; // Reset exit timer when switching tabs
      return false;
    }

    // If GoRouter has navigation history (e.g., after returning from media detail),
    // clear it by going to home explicitly
    if (context.canPop()) {
      context.go('/home');
      _lastBackPressAt = null;
      return false;
    }

    // On home tab with no navigation history - handle exit logic
    final backGap = _lastBackPressAt == null
        ? null
        : now.difference(_lastBackPressAt!);
    final shouldExit =
        backGap != null &&
        backGap >= const Duration(milliseconds: 500) &&
        backGap <= const Duration(seconds: 2);

    if (shouldExit) {
      SystemNavigator.pop();
      return false;
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

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;

    return WillPopScope(
      onWillPop: _onWillPop,
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
            selectedItemColor: accentColor,
            unselectedItemColor: NivioTheme.netflixGrey,
            showUnselectedLabels: true,
            selectedLabelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            items: [
              BottomNavigationBarItem(
                icon: PhosphorIcon(
                  PhosphorIconsRegular.house,
                  color: NivioTheme.netflixGrey,
                  size: 22,
                ),
                activeIcon: PhosphorIcon(
                  PhosphorIconsFill.house,
                  color: accentColor,
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
                  color: accentColor,
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
                  color: accentColor,
                  size: 22,
                ),
                label: 'Library',
              ),
              BottomNavigationBarItem(
                icon: PhosphorIcon(
                  PhosphorIconsRegular.users,
                  color: NivioTheme.netflixGrey,
                  size: 22,
                ),
                activeIcon: PhosphorIcon(
                  PhosphorIconsFill.users,
                  color: accentColor,
                  size: 22,
                ),
                label: 'Party',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
