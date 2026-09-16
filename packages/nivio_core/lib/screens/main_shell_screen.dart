import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nivio/services/github_release_update_service.dart';
import 'package:nivio/widgets/changelog_dialog.dart';

import 'package:nivio/providers/auth_provider.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:animations/animations.dart';
import 'package:nivio/services/schedule_api_service.dart';
import '../main.dart';
class MainShellScreen extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainShellScreen({super.key, required this.navigationShell});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  DateTime? _lastBackPressAt;
  DateTime? _lastBackHandledAt;
  bool _scrolled = false;
  String? _lastLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdatesOnStartup();
      _syncWatchlistFromCloud();
      _prefetchSchedule();
    });
  }

  void _prefetchSchedule() {
    // Fire and forget: Pre-fetch today's schedule into cache for instant load later
    ScheduleApiService.fetchScheduleForDate(DateTime.now(), watchlistOnly: true);
  }

  Future<void> _syncWatchlistFromCloud() async {
    try {
      final watchlistService = ref.read(watchlistServiceProvider);
      await watchlistService.downloadFromCloud();
    } catch (_) {}
  }

  Future<void> _checkForUpdatesOnStartup() async {
    try {
      final result = await GitHubReleaseUpdateService.checkForUpdate();
      if (!mounted) return;

      if (result.hasUpdate) {
        showModal<void>(
          context: context,
          configuration: const FadeScaleTransitionConfiguration(),
          builder: (ctx) {
            return ChangelogDialog(
              version: result.latestVersion,
              releaseNotes: result.releaseNotes ?? 'A new update is available. Please update to enjoy the latest features and bug fixes!',
              isUpdatePrompt: true,
              onDismiss: () {},
              onInstall: () async {
                await GitHubReleaseUpdateService.openReleasePage(result.releaseUrl);
              },
            );
          },
        );
      }
    } catch (e) {
      // Silently fail on startup check
    }
  }

  void _onTap(int index) {
    if (index == widget.navigationShell.currentIndex) {
      // Pop native modal routes (like OpenContainer) for the current branch
      final navigatorKeys = [
        homeNavigatorKey,
        libraryNavigatorKey,
        iptvNavigatorKey,
        partyNavigatorKey,
      ];
      if (index < navigatorKeys.length) {
        navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
      }
    }

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

  Widget _buildSidebar(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    final authState = ref.watch(authStateProvider);
    final user = authState.valueOrNull;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: 56,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12), // Align logo to the very top area
          // Logo / Header
          Image.asset(
            'assets/images/nivio.png',
            width: 48,
            height: 48,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 16),
          // Middle Items
          Expanded(
            child: Column(
              children: [
                _buildSidebarItem(
                  context: context,
                  index: 0,
                  icon: PhosphorIconsRegular.house,
                  activeIcon: PhosphorIconsFill.house,
                  label: 'Home',
                  isActive: widget.navigationShell.currentIndex == 0 &&
                      !location.startsWith('/search') &&
                      !location.startsWith('/profile'),
                ),
                const SizedBox(height: 8),
                _buildSidebarActionItem(
                  context: context,
                  route: '/search',
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  activeIcon: PhosphorIconsFill.magnifyingGlass,
                  label: 'Search',
                  isActive: location.startsWith('/search'),
                ),
                const SizedBox(height: 8),
                _buildSidebarItem(
                  context: context,
                  index: 1,
                  icon: PhosphorIconsRegular.calendarBlank,
                  activeIcon: PhosphorIconsFill.calendarCheck,
                  label: 'Library',
                  isActive: widget.navigationShell.currentIndex == 1 &&
                      !location.startsWith('/search') &&
                      !location.startsWith('/profile'),
                ),
                const SizedBox(height: 8),
                _buildSidebarItem(
                  context: context,
                  index: 2,
                  icon: PhosphorIconsRegular.television,
                  activeIcon: PhosphorIconsFill.television,
                  label: 'TV/Sports',
                  isActive: widget.navigationShell.currentIndex == 2 &&
                      !location.startsWith('/search') &&
                      !location.startsWith('/profile'),
                ),
                const SizedBox(height: 8),
                _buildSidebarItem(
                  context: context,
                  index: 3,
                  icon: PhosphorIconsRegular.users,
                  activeIcon: PhosphorIconsFill.users,
                  label: 'Party',
                  isActive: widget.navigationShell.currentIndex == 3 &&
                      !location.startsWith('/search') &&
                      !location.startsWith('/profile'),
                ),
              ],
            ),
          ),
          // Bottom Items
          _buildSidebarActionItem(
            context: context,
            route: '/profile',
            icon: PhosphorIconsRegular.user,
            activeIcon: PhosphorIconsFill.user,
            label: 'Profile',
            isActive: location.startsWith('/profile'),
            photoUrl: user?.photoURL,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isActive,
  }) {
    return Align(
      alignment: isActive ? Alignment.centerLeft : Alignment.center,
      child: InkWell(
        onTap: () => _onTap(index),
        borderRadius: isActive
            ? const BorderRadius.only(
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              )
            : BorderRadius.circular(8),
        child: Container(
          width: isActive ? 48 : 40,
          height: 40,
          padding: isActive ? const EdgeInsets.only(left: 8) : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: isActive
                ? const BorderRadius.only(
                    topRight: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  )
                : BorderRadius.circular(8),
          ),
          child: Center(
            child: _AnimatedIconWrapper(
              child: PhosphorIcon(
                isActive ? activeIcon : icon,
                color: isActive ? NivioTheme.netflixBlack : Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarActionItem({
    required BuildContext context,
    required String route,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isActive,
    String? photoUrl,
  }) {
    return Align(
      alignment: isActive ? Alignment.centerLeft : Alignment.center,
      child: InkWell(
        onTap: () {
          if (GoRouterState.of(context).matchedLocation.startsWith(route)) {
            context.go('/home');
          } else {
            context.push(route);
          }
        },
        borderRadius: isActive
            ? const BorderRadius.only(
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              )
            : BorderRadius.circular(8),
        child: Container(
          width: isActive ? 48 : 40,
          height: 40,
          padding: isActive ? const EdgeInsets.only(left: 8) : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: isActive
                ? const BorderRadius.only(
                    topRight: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  )
                : BorderRadius.circular(8),
          ),
          child: Center(
            child: _AnimatedIconWrapper(
              child: photoUrl != null
                  ? CircleAvatar(
                      radius: 14,
                      backgroundImage: CachedNetworkImageProvider(photoUrl),
                      backgroundColor: NivioTheme.netflixDarkGrey,
                    )
                  : PhosphorIcon(
                      isActive ? activeIcon : icon,
                      color: isActive ? NivioTheme.netflixBlack : Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final location = GoRouterState.of(context).matchedLocation;

    if (_lastLocation != location) {
      _lastLocation = location;
      _scrolled = false;
    }

    final leftPadding = 0.0;

    if (isDesktop) {
      return WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          body: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                if (notification.metrics.axis == Axis.vertical) {
                  final offset = notification.metrics.pixels;
                  if (offset > 50 && !_scrolled) {
                    setState(() => _scrolled = true);
                  } else if (offset <= 50 && _scrolled) {
                    setState(() => _scrolled = false);
                  }
                }
              }
              return false;
            },
            child: Stack(
              children: [
                // Main Layout (Sidebar + Shell Content)
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(left: leftPadding),
                    child: Stack(
                      children: [
                        widget.navigationShell,
                        const Positioned.fill(child: SizedBox.shrink()),
                      ],
                    ),
                  ),
                ),
                // Left Navigation Sidebar
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  width: 56,
                  child: _buildSidebar(context),
                ),
                // Floating TitleBar on top
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: CustomTitleBar(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: Stack(
          children: [
            // Foreground UI
            widget.navigationShell,
            // Background physical WebView for Cloudflare Turnstile bypass (drawn on top when needed)
            const Positioned.fill(child: SizedBox.shrink()),
          ],
        ),
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
                  PhosphorIconsRegular.television,
                  color: NivioTheme.netflixGrey,
                  size: 22,
                ),
                activeIcon: PhosphorIcon(
                  PhosphorIconsFill.television,
                  color: accentColor,
                  size: 22,
                ),
                label: 'Live TV',
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

class CustomTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        windowManager.startDragging();
      },
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          windowManager.unmaximize();
        } else {
          windowManager.maximize();
        }
      },
      child: Container(
        height: 32,
        color: Colors.transparent,
        child: Row(
          children: [
            const Expanded(child: SizedBox.shrink()),
            _TitleBarButton(
              icon: Icons.remove,
              onTap: () => windowManager.minimize(),
            ),
            _TitleBarButton(
              icon: Icons.crop_square,
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
            ),
            _TitleBarButton(
              icon: Icons.close,
              hoverColor: const Color(0xFFE81123),
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(32);
}

class _TitleBarButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? hoverColor;

  const _TitleBarButton({
    required this.icon,
    required this.onTap,
    this.hoverColor,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 32,
          color: _isHovered
              ? (widget.hoverColor ?? Colors.white.withOpacity(0.1))
              : Colors.transparent,
          child: Center(
            child: Icon(
              widget.icon,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedIconWrapper extends StatefulWidget {
  final Widget child;
  const _AnimatedIconWrapper({required this.child});

  @override
  State<_AnimatedIconWrapper> createState() => _AnimatedIconWrapperState();
}

class _AnimatedIconWrapperState extends State<_AnimatedIconWrapper> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.25 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
