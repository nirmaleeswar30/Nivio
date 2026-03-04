import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class MainShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShellScreen({super.key, required this.navigationShell});

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: navigationShell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && navigationShell.currentIndex != 0) {
          navigationShell.goBranch(0);
        }
      },
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: NivioTheme.netflixBlack,
            border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
          ),
          child: BottomNavigationBar(
            currentIndex: navigationShell.currentIndex,
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
                label: 'Schedule',
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
