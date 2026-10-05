import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/services/github_release_update_service.dart';
import 'package:nivio/widgets/changelog_dialog.dart';

import 'package:nivio/providers/auth_provider.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:animations/animations.dart';
import 'package:nivio/services/schedule_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nivio/services/anime_tracking_coordinator.dart';
import 'package:nivio/services/simkl_auth_service.dart';
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

  // Frosted mobile nav: hides when scrolling down, reappears when scrolling up
  // or when the view is back at the top.
  bool _navVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdatesOnStartup();
      _syncWatchlistFromCloud();
      _prefetchSchedule();
      _syncAnimeTrackingOnStartup();
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

  Future<void> _syncAnimeTrackingOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoSyncEnabled = prefs.getBool('anime_auto_sync_watchlist') ?? true;
      if (!autoSyncEnabled) return;

      final watchlistService = ref.read(watchlistServiceProvider);

      // AniList/MAL: two-way anime sync (import remote + push offline changes).
      if (AnimeTrackingCoordinator.instance.hasAnyAccountConnected) {
        final count =
            await watchlistService.importFromAnimeTracking(pushOfflineChanges: true);
        if (count > 0 && mounted) {
          ref.read(watchlistRefreshProvider.notifier).refresh();
        }
      }

      // Simkl: two-way library sync (movies, TV & anime) — pulls the remote
      // list, merges it in, and pushes local changes. Independent of whether
      // AniList/MAL are connected.
      if (SimklAuthService.instance.isAuthenticated) {
        final simklCount =
            await watchlistService.importFromSimkl(pushOfflineChanges: true);
        if (simklCount > 0 && mounted) {
          ref.read(watchlistRefreshProvider.notifier).refresh();
        }
      }
    } catch (e) {
      debugPrint('[AnimeSyncStartup] Background sync failed: $e');
    }
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

  // Drives the hide-on-scroll behaviour of the mobile frosted nav.
  bool _handleMobileScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification) {
      final pixels = notification.metrics.pixels;
      final delta = notification.scrollDelta ?? 0;

      // Always reveal near the very top so the bar greets you there.
      if (pixels <= 24) {
        if (!_navVisible) setState(() => _navVisible = true);
        return false;
      }
      // Ignore tiny jitter; otherwise hide when scrolling down, show when up.
      if (delta > 6 && _navVisible) {
        setState(() => _navVisible = false);
      } else if (delta < -6 && !_navVisible) {
        setState(() => _navVisible = true);
      }
    }
    return false;
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
      _navVisible = true;
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
              ],
            ),
          ),
        ),
      );
    }

    // Space the floating bar occupies, so page content can scroll clear of it.
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final navReserve = 64.0 + 12.0 + bottomSafe;
    final mq = MediaQuery.of(context);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            // Foreground UI. Reserve bottom space via MediaQuery padding so
            // SafeArea/scroll-aware pages don't hide content behind the bar.
            MediaQuery(
              data: mq.copyWith(
                padding: mq.padding.copyWith(bottom: navReserve),
              ),
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleMobileScroll,
                child: widget.navigationShell,
              ),
            ),
            // Background physical WebView for Cloudflare Turnstile bypass (drawn on top when needed)
            const Positioned.fill(child: SizedBox.shrink()),
            // Frosted floating navigation bar.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_navVisible,
                child: AnimatedSlide(
                  offset: _navVisible ? Offset.zero : const Offset(0, 1.4),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeInOutCubicEmphasized,
                  child: AnimatedOpacity(
                    opacity: _navVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    child: _NivioFloatingNav(
                      currentIndex: widget.navigationShell.currentIndex,
                      onTap: _onTap,
                      accentColor: accentColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// Floating frosted navigation bar with a sliding radial-glow indicator that
/// tracks the active tab, plus a bounce on selection. Ported from the standard
/// floating nav design.
class _NivioFloatingNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color accentColor;

  const _NivioFloatingNav({
    required this.currentIndex,
    required this.onTap,
    required this.accentColor,
  });

  @override
  State<_NivioFloatingNav> createState() => _NivioFloatingNavState();
}

class _NivioFloatingNavState extends State<_NivioFloatingNav>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _bounceController;
  late Animation<double> _slideAnimation;
  late Animation<double> _bounceAnimation;
  int _previousIndex = 0;

  static const _navItems = <(IconData, IconData, String)>[
    (PhosphorIconsRegular.house, PhosphorIconsFill.house, 'Home'),
    (PhosphorIconsRegular.calendarBlank, PhosphorIconsFill.calendarCheck, 'Library'),
    (PhosphorIconsRegular.television, PhosphorIconsFill.television, 'Live TV'),
    (PhosphorIconsRegular.users, PhosphorIconsFill.users, 'Party'),
  ];

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.currentIndex;

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<double>(
      begin: widget.currentIndex.toDouble(),
      end: widget.currentIndex.toDouble(),
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
    );
    _bounceAnimation = _makeBounce();
  }

  Animation<double> _makeBounce() {
    return TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.85), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.1), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 40),
    ]).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(covariant _NivioFloatingNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _previousIndex = oldWidget.currentIndex;
      _slideAnimation = Tween<double>(
        begin: _previousIndex.toDouble(),
        end: widget.currentIndex.toDouble(),
      ).animate(
        CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
      );
      _slideController.forward(from: 0);

      _bounceAnimation = _makeBounce();
      _bounceController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final accent = widget.accentColor;
    final bottomMargin = (bottomPadding > 0 ? bottomPadding : 10.0) + 14.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, bottomMargin),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 16,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.62),
                    const Color(0xFF101010).withValues(alpha: 0.56),
                  ],
                ),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: accent.withValues(alpha: 0.38),
                  width: 1.0,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth / _navItems.length;
                  const indicatorWidth = 44.0;

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Sliding radial glow indicator behind the active tab.
                      AnimatedBuilder(
                        animation: _slideController,
                        builder: (context, child) {
                          final position = _slideController.isAnimating
                              ? _slideAnimation.value
                              : widget.currentIndex.toDouble();
                          final leftOffset =
                              (itemWidth - indicatorWidth) / 2 +
                              (position * itemWidth);

                          return Positioned(
                            left: leftOffset,
                            top: (56.0 - indicatorWidth) / 2,
                            child: Container(
                              width: indicatorWidth,
                              height: indicatorWidth,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    accent.withValues(alpha: 0.35),
                                    accent.withValues(alpha: 0.10),
                                    accent.withValues(alpha: 0.0),
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.40),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      // Nav items.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(_navItems.length, (index) {
                          final item = _navItems[index];
                          final isSelected = widget.currentIndex == index;

                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              widget.onTap(index);
                            },
                            behavior: HitTestBehavior.opaque,
                            child: SizedBox(
                              width: itemWidth,
                              child: AnimatedBuilder(
                                animation: _bounceController,
                                builder: (context, child) {
                                  final scale = isSelected &&
                                          _bounceController.isAnimating
                                      ? _bounceAnimation.value
                                      : 1.0;
                                  return Transform.scale(
                                    scale: scale,
                                    child: _NivioNavItem(
                                      icon: item.$1,
                                      selectedIcon: item.$2,
                                      label: item.$3,
                                      isSelected: isSelected,
                                      accentColor: accent,
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NivioNavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final Color accentColor;

  const _NivioNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? accentColor.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          child: PhosphorIcon(
            isSelected ? selectedIcon : icon,
            size: isSelected ? 23 : 21,
            color: isSelected ? accentColor : NivioTheme.netflixLightGrey,
          ),
        ),
        const SizedBox(height: 1),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            fontSize: isSelected ? 10.5 : 9.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? accentColor : NivioTheme.netflixLightGrey,
            letterSpacing: isSelected ? 0.2 : 0,
          ),
          child: Text(label),
        ),
      ],
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
