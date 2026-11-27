import 'package:nivio/widgets/tab_artwork.dart';
import 'dart:io';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/core/tv_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/services/github_release_update_service.dart';
import 'package:nivio/services/desktop_self_updater.dart';
import 'package:nivio/widgets/changelog_dialog.dart';
import 'package:nivio/widgets/liquid_glass_nav.dart';
import 'package:nivio/providers/settings_providers.dart' show liquidGlassNavProvider;

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

  bool _navExpanded = true;
  double _navScrollDelta = 0;

  // TV: the side rail, so Back can jump to it (see _onWillPop).
  final FocusNode _railGroupNode = FocusNode(debugLabel: 'tvRail');
  final List<FocusNode> _railNodes =
      List.generate(4, (i) => FocusNode(debugLabel: 'tvRail$i'));

  // Android (phones and TV): Android 14+ predictive back ignores
  // WillPopScope, so with nothing to pop the system just closed the app
  // instead of showing "Press back again to exit". PopScope makes Back reach
  // _onWillPop. Desktop keeps WillPopScope alone, as before.
  Widget _androidBackScope(Widget child) {
    if (!Platform.isAndroid) return child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onWillPop();
      },
      child: child,
    );
  }

  /// TV: moves focus onto the rail's current tab, if the shell is on screen
  /// and focus isn't already in the rail.
  bool _enterRail() {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return false;
    if (_railGroupNode.hasFocus) return false;
    _railNodes[widget.navigationShell.currentIndex].requestFocus();
    return true;
  }

  bool _isRailNode(FocusNode node) =>
      node == _railGroupNode || node.ancestors.contains(_railGroupNode);

  @override
  void dispose() {
    if (TvRail.enter == _enterRail) {
      TvRail.enter = null;
      TvRail.contains = null;
      TvRail.returnTo = null;
    }
    _railGroupNode.dispose();
    for (final node in _railNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (AppPlatform.isTv) {
      TvRail.enter = _enterRail;
      TvRail.contains = _isRailNode;
    }
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
                await DesktopSelfUpdater.installOrOpen(context, result.releaseUrl);
              },
            );
          },
        );
      }
    } catch (e) {
      // Silently fail on startup check
    }
  }

  // Keep the destinations in reach while the pill and its labels collapse.
  bool _handleMobileScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification) {
      final pixels = notification.metrics.pixels;
      final delta = notification.scrollDelta ?? 0.0;
      if (pixels <= 24) {
        _navScrollDelta = 0;
        if (!_navExpanded) setState(() => _navExpanded = true);
        return false;
      }
      if (delta == 0) return false;
      _navScrollDelta = _navScrollDelta.sign == delta.sign ? _navScrollDelta + delta : delta;
      if (_navScrollDelta.abs() >= 60) {
        final expanded = _navScrollDelta < 0;
        _navScrollDelta = 0;
        if (_navExpanded != expanded) setState(() => _navExpanded = expanded);
      }
    }
    return false;
  }

  // A page that can't scroll (or was clamped back to the top, e.g. when the
  // keyboard closes) offers no way to scroll up and reveal the bar, so show it.
  // Only the page's outermost scrollable counts; nested non-scrolling lists
  // are laid out all the time while the page itself scrolls.
  bool _handleMobileScrollMetrics(ScrollMetricsNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth != 0 || metrics.axis != Axis.vertical) return false;
    if (_navExpanded) return false;
    final notScrollable = metrics.maxScrollExtent <= metrics.minScrollExtent;
    if (notScrollable || metrics.pixels <= 24) {
      setState(() => _navExpanded = true);
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

    // TV: Back first jumps to the side rail (like Netflix), so the rail is
    // always one press away; once there, Back carries on as below.
    if (AppPlatform.isTv &&
        TvRail.enterFrom(FocusManager.instance.primaryFocus)) {
      return false;
    }

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
    final user = authState.value;

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
      child: FocusableInkWell(
        focusNode: AppPlatform.isTv ? _railNodes[index] : null,
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
      child: FocusableInkWell(
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
                      backgroundImage: avatarArtworkImage(context, photoUrl, 28),
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
    final isDesktop = AppPlatform.useDesktopLayout;
    final location = GoRouterState.of(context).matchedLocation;

    if (_lastLocation != location) {
      _lastLocation = location;
      _scrolled = false;
      _navExpanded = true;
      _navScrollDelta = 0;
    }

    final leftPadding = 0.0;

    if (isDesktop) {
      return WillPopScope(
        onWillPop: _onWillPop,
        child: _androidBackScope(Scaffold(
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
                  child: Focus(
                    focusNode: _railGroupNode,
                    canRequestFocus: false,
                    skipTraversal: true,
                    child: _buildSidebar(context),
                  ),
                ),
              ],
            ),
          ),
        )),
      );
    }

    // Space the floating bar occupies, so page content can scroll clear of it.
    final mq = MediaQuery.of(context);
    final navReserve = 64.0 + 12.0 + mq.padding.bottom;

    final keyboardOpen = mq.viewInsets.bottom > 0;
    final useLiquidGlassNav = ref.watch(liquidGlassNavProvider);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: _androidBackScope(Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            // Foreground UI. Reserve bottom space via MediaQuery padding so
            // SafeArea/scroll-aware pages don't hide content behind the bar.
            // This Scaffold already shrinks its body above the keyboard, and
            // `mq` comes from above it, so drop the keyboard inset here or
            // every page Scaffold below shrinks by it a second time (leaving
            // a keyboard-sized black gap).
            MediaQuery(
              data: mq.removeViewInsets(removeBottom: true).copyWith(
                padding: mq.padding.copyWith(
                  bottom: keyboardOpen ? 0 : navReserve,
                ),
              ),
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: _handleMobileScrollMetrics,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleMobileScroll,
                  child: widget.navigationShell,
                ),
              ),
            ),
            // Floating navigation bar.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ExcludeSemantics(
                excluding: keyboardOpen,
                child: IgnorePointer(
                  ignoring: keyboardOpen,
                  child: AnimatedSlide(
                    offset: keyboardOpen ? const Offset(0, 1.4) : Offset.zero,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: _navExpanded ? 1 : 0),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      curve: const Cubic(0.2, 0, 0, 1),
                      builder: (context, fraction, _) => LiquidGlassNav(
                        items: [
                          for (final item in _mobileNavItems)
                            LiquidGlassNavItem(
                              icon: item.$1,
                              selectedIcon: item.$2,
                              label: item.$3,
                            ),
                        ],
                        currentIndex: widget.navigationShell.currentIndex,
                        onTap: _onTap,
                        isDark: true,
                        accentColor: accentColor,
                        labelFraction: fraction,
                        frosted: !useLiquidGlassNav,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      )),
    );
  }

}

const _mobileNavItems = <(IconData, IconData, String)>[
  (PhosphorIconsRegular.house, PhosphorIconsFill.house, 'Home'),
  (PhosphorIconsRegular.calendarBlank, PhosphorIconsFill.calendarCheck, 'Library'),
  (PhosphorIconsRegular.television, PhosphorIconsFill.television, 'Live TV'),
  (PhosphorIconsRegular.users, PhosphorIconsFill.users, 'Party'),
];

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
