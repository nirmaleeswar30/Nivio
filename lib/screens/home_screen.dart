import 'dart:async';
import 'dart:ui';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:go_router/go_router.dart';

import 'package:nivio/core/providers_data.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/core/tmdb_artwork.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/providers/auth_provider.dart';
import 'package:nivio/providers/changelog_provider.dart';
import 'package:nivio/providers/home_providers.dart';
import 'package:nivio/providers/language_preferences_provider.dart';
import 'package:nivio/providers/home_layout_provider.dart';

import 'package:nivio/providers/watch_history_provider.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/services/episode_check_service.dart';
import 'package:nivio/services/api_status_service.dart';
import 'package:nivio/widgets/changelog_dialog.dart';
import 'package:nivio/widgets/content_row.dart';
import 'package:nivio/widgets/latest_releases_shelf.dart';
import 'package:nivio/widgets/shelf_more_button.dart';
import 'package:nivio/widgets/skeleton.dart';
import 'package:nivio/widgets/continue_watching_row.dart';
import 'package:nivio/widgets/tab_artwork.dart';
import 'package:nivio/widgets/hero_artwork_stretch.dart';
import 'package:nivio/providers/settings_providers.dart' show dynamicArtworkColorsProvider;
import 'package:nivio/providers/player_active_provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';



class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();
  final ValueNotifier<bool> _showAppBarBg = ValueNotifier<bool>(false);
  bool _isBannerVisible = true;
  int _currentBannerIndex = 0;
  int _currentBannerPage = 0;
  Timer? _bannerTimer;
  bool _heroHasFocus = false;
  // TV: each hero slide's Watch Now, so paging can move focus onto the new one.
  final Map<int, FocusNode> _heroWatchNodes = {};

  FocusNode _heroWatchNode(int page) => _heroWatchNodes.putIfAbsent(
        page,
        () => FocusNode(debugLabel: 'heroWatchNow$page'),
      );

  /// TV: right on the last hero button shows the next slide and left on
  /// Watch Now the previous one; on the first slide left falls through to
  /// the side rail.
  KeyEventResult _handleHeroButtonsKey(FocusNode row, KeyEvent event) {
    if (event is! KeyDownEvent || !_pageController.hasClients) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    final buttons = row.traversalDescendants.toList()
      ..sort((a, b) => a.rect.left.compareTo(b.rect.left));
    if (buttons.isEmpty) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus;
    if (key == LogicalKeyboardKey.arrowRight && primary == buttons.last) {
      _pageHero(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft &&
        primary == buttons.first &&
        _currentBannerIndex > 0) {
      _pageHero(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pageHero(int delta) async {
    await _pageController.animateToPage(
      _currentBannerPage + delta,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
    // Let the loop-around jump (last slide -> first) settle first.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    _heroWatchNode(_currentBannerPage).requestFocus();
  }
  final Map<int, bool> _pendingWatchlistState = <int, bool>{};
  final Map<int, Color> _ambientColors = {};
  final Set<int> _loadingAmbientColors = {};
  Color _currentAmbientColor = const Color(0xFF0D0F14);



  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final offset = _scrollController.offset;
      // Use a ValueNotifier (not setState) so crossing the threshold only
      // repaints the appbar background — NOT the whole HomeScreen. A full
      // rebuild here janked the first scroll (and on desktop there's no appbar
      // at all, so setState was pure waste that stuttered the first swipe).
      if (offset > 50 && !_showAppBarBg.value) {
        _showAppBarBg.value = true;
      } else if (offset <= 50 && _showAppBarBg.value) {
        _showAppBarBg.value = false;
      }

      // The hero banner is ~500-600px tall. If we've scrolled past 800px, it's definitely offscreen.
      final isVisible = offset < 800;
      if (isVisible != _isBannerVisible) {
        // We don't setState here because we don't need to rebuild the UI,
        // we just need to update the flag so the timer knows to pause.
        _isBannerVisible = isVisible;
      }
    });

    _bannerTimer = Timer.periodic(const Duration(seconds: 14), (timer) {
      if (!_pageController.hasClients || !_isBannerVisible || _heroHasFocus) {
        return;
      }
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      if (!TickerMode.getValuesNotifier(context).value.enabled) return;
      // Don't waste cycles on banner animation while the video player is active
      if (ref.read(isPlayerActiveProvider)) return;
      final featuredContent = ref.read(featuredContentProvider).value ?? [];
      if (featuredContent.length < 2) return;
      _pageController.animateToPage(
        _currentBannerPage + 1,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  Future<void> _extractColorForIndex(List<Map<String, dynamic>> items, int index) async {
    if (!mounted || index >= items.length) return;
    
    if (_ambientColors.containsKey(index)) return;

    // Don't run expensive color extraction while the video player is active
    if (ref.read(isPlayerActiveProvider)) return;
    
    final content = items[index];
    final backdrop = tmdbArtworkUrl(content['backdrop_path'] as String?, 'w300');
    final poster = tmdbArtworkUrl(content['poster_path'] as String?, 'w185');
    final url = AppPlatform.useDesktopLayout
        ? backdrop ?? poster
        : poster ?? backdrop;
    if (url == null || !_loadingAmbientColors.add(index)) return;

    try {
      final colorScheme = await ColorScheme.fromImageProvider(
        provider: artworkPaletteProvider(url),
        brightness: Brightness.dark,
      );
      final color = colorScheme.primary;
      
      if (mounted) {
        setState(() {
          _ambientColors[index] = color;
          if (_currentBannerIndex == index) {
            _currentAmbientColor = color;
            ref.read(ambientColorProvider.notifier).state = color;
          }
        });
      }
    } catch (_) {
      // Keep the current ambient color if artwork is unavailable.
    } finally {
      _loadingAmbientColors.remove(index);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pageController.dispose();
    _showAppBarBg.dispose();
    _bannerTimer?.cancel();
    for (final node in _heroWatchNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = AppPlatform.useDesktopLayout;
    ref.listen(changelogProvider, (previous, next) {
      if (!next.isLoading && !next.hasSeenCurrentVersion && next.releaseNotes != null) {
        ref.read(changelogProvider.notifier).markAsSeen();
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => ChangelogDialog(
            version: next.currentVersion,
            releaseNotes: next.releaseNotes!,
            onDismiss: () {},
          ),
        );
      }
    });

    final featuredContent = ref.watch(featuredContentProvider);
    final languagePreferences = ref.watch(languagePreferencesProvider);
    final homeLayout = ref.watch(homeLayoutProvider);

    final List<Widget> dynamicSections = [];
    for (final sectionId in homeLayout) {
      switch (sectionId) {
        case 'latest_movies_ott':
          dynamicSections.add(_buildLatestShelfSection(
            title: 'Latest OTT Releases',
            subtitle: 'Verified digital premieres & streaming drops',
            badgeText: 'DIGITAL PREMIERE',
            badgeGradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
            badgeIcon: PhosphorIconsFill.filmStrip,
            provider: latestMoviesOttProvider,
            onSeeAll: () => context.push('/latest-releases?category=movie'),
          ));
          break;
        case 'latest_tv_ott':
          dynamicSections.add(_buildLatestShelfSection(
            title: 'Latest TV Releases',
            subtitle: 'New series & episodes streaming now',
            badgeText: 'STREAMING NOW',
            badgeGradient: const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
            badgeIcon: PhosphorIconsFill.television,
            provider: latestTvOttProvider,
            onSeeAll: () => context.push('/latest-releases?category=tv'),
          ));
          break;
        case 'latest_anime':
          if (languagePreferences.showAnime) {
            dynamicSections.add(_buildLatestShelfSection(
              title: 'Latest Anime Releases',
              subtitle: 'Newly aired episodes in Japan',
              badgeText: 'NEW EPISODE',
              badgeGradient: const [Color(0xFF06B6D4), Color(0xFF0284C7)],
              badgeIcon: PhosphorIconsFill.sparkle,
              provider: latestAnimeReleasesProvider,
              isAnime: true,
              onSeeAll: () => context.push('/latest-releases?category=anime'),
            ));
          }
          break;
        default:
          final shelf = HomeShelf.fromId(sectionId);
          final enabled = switch (shelf) {
            HomeShelf.popularAnime || HomeShelf.trendingAnime =>
              languagePreferences.showAnime,
            HomeShelf.tamil => languagePreferences.showTamil,
            HomeShelf.telugu => languagePreferences.showTelugu,
            HomeShelf.hindi => languagePreferences.showHindi,
            HomeShelf.korean => languagePreferences.showKorean,
            HomeShelf.malayalam => languagePreferences.showMalayalam,
            HomeShelf.recommendations || null => false,
            _ => true,
          };
          if (shelf != null && enabled) {
            dynamicSections.add(_buildRowSection(shelf));
          }
      }
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: isDesktop ? null : PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          flexibleSpace: ValueListenableBuilder<bool>(
            valueListenable: _showAppBarBg,
            builder: (context, showBg, _) => ClipRect(
              child: showBg
                  ? BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.38),
                              const Color(0xFF101010).withValues(alpha: 0.32),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          title: isDesktop 
              ? const SizedBox.shrink()
              : const Padding(
                  padding: EdgeInsets.only(top: 6, left: 2),
                  child: SizedBox(
                    height: 48,
                    child: Image(
                      image: AssetImage('assets/images/nivio.png'),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
          actions: [
            _buildBypassIndicator(context),
            if (!isDesktop) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: IconButton(
                  icon: const PhosphorIcon(
                    PhosphorIconsRegular.magnifyingGlass,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: () => context.push('/search'),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildNotificationBell(context),
            ),
            if (!isDesktop) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildProfileButton(context),
              ),
            ],
            const SizedBox(width: 8),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: _artworkBackground(context),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AppCustomScrollView(
              controller: _scrollController,
              physics: isDesktop ? null : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              // TV keeps the next shelf in reach of D-pad focus.
              cacheExtent: AppPlatform.isTv ? 420 : 250,
              scrollSpeed: 2.0,
              silkyScrollDuration: const Duration(milliseconds: 500),
              animationCurve: Curves.easeOutQuart,
              slivers: [
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: featuredContent.when(
                      data: (content) => _buildHeroBannerCarousel(context, content),
                      loading: _buildHeroBannerShimmer,
                      error: (error, stackTrace) => const SizedBox(height: 500),
                    ),
                  ),
                ),
                // One delegate builds shelves and subscribes to their providers
                // only when they approach the viewport.
                SliverList.list(
                  children: [
                    _buildContinueWatchingSection(isDesktop),
                    _buildWatchlistSection(),
                    _buildProviderSelectionRow(),
                    const SizedBox(height: 40),
                    _buildRowSection(HomeShelf.recommendations),
                    ...dynamicSections,
                    const SizedBox(height: 50),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueWatchingSection(bool isDesktop) {
    return Consumer(
      key: const PageStorageKey<String>('home-continue-watching'),
      builder: (context, ref, child) {
        return ref.watch(continueWatchingProvider).when(
          data: (items) {
            if (items.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.only(left: isDesktop ? 68 : 16, right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Continue Watching',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ShelfMoreButton(
                        onPressed: () => context.push('/continue-watching'),
                      ),
                    ],
                  ),
                  const ContinueWatchingRow(),
                  const SizedBox(height: 30),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (error, stackTrace) => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildWatchlistSection() {
    return Consumer(
      key: const PageStorageKey<String>('home-watchlist'),
      builder: (context, ref, child) {
        final watchlist = ref.watch(watchlistProvider);
        final seenIds = <int>{};
        final watchlistItems = watchlist
            // Only currently watched and planned titles appear on Home.
            .where((item) =>
                (item.watchStatus == WatchStatus.watching ||
                    item.watchStatus == WatchStatus.planning) &&
                seenIds.add(item.id))
            .take(20)
            .map(
              (WatchlistItem item) => {
                'id': item.id,
                'name': item.title,
                'title': item.title,
                'poster_path': item.posterPath,
                'vote_average': item.voteAverage,
                'first_air_date': item.releaseDate,
                'release_date': item.releaseDate,
                'media_type': item.mediaType,
              },
            )
            .toList(growable: false);

        if (watchlistItems.isEmpty) return const SizedBox.shrink();
        return ContentRow(
          title: 'Your List',
          items: watchlistItems,
          onSeeAll: () => context.go('/library?tab=watchlist'),
        );
      },
    );
  }

  Widget _buildRowSection(HomeShelf shelf) {
    return Consumer(
      key: PageStorageKey<String>('home-${shelf.id}'),
      builder: (context, ref, child) {
        return ref.watch(homeShelfProvider(shelf)).when(
          data: (page) => ContentRow(
            title: shelf.title,
            items: page.items.take(20).toList(growable: false),
            onSeeAll: () => context.push('/home/shelf/${shelf.id}'),
          ),
          loading: () => shelf == HomeShelf.recommendations
              ? const SizedBox.shrink()
              : const ContentRowSkeleton(),
          error: (error, stackTrace) => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildLatestShelfSection({
    required String title,
    String? subtitle,
    required String badgeText,
    required List<Color> badgeGradient,
    required IconData badgeIcon,
    required FutureProvider<List<dynamic>> provider,
    bool isAnime = false,
    VoidCallback? onSeeAll,
  }) {
    return Consumer(
      key: PageStorageKey<String>(title),
      builder: (context, ref, child) {
        return ref.watch(provider).when(
          data: (items) => LatestReleasesShelf(
            title: title,
            subtitle: subtitle,
            items: items,
            badgeText: badgeText,
            badgeGradient: badgeGradient,
            badgeIcon: badgeIcon,
            isAnime: isAnime,
            onSeeAll: onSeeAll,
          ),
          loading: () => LatestReleasesShelfSkeleton(title: title, subtitle: subtitle),
          error: (error, stackTrace) => const SizedBox.shrink(),
        );
      },
    );
  }


  Widget _buildProviderSelectionRow() {
    final providers = allProviders.take(20).toList();
    final isDesktop = AppPlatform.useDesktopLayout;

    return Column(
      key: const PageStorageKey<String>('home-studios'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Padding(
            padding: EdgeInsets.only(top: 8.0, bottom: 8.0, left: isDesktop ? 68 : 16, right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Studios',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ShelfMoreButton(
                  onPressed: () => context.push('/all-providers'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              clipBehavior: AppPlatform.isTv ? Clip.none : Clip.hardEdge,
              padding: EdgeInsets.only(left: isDesktop ? 64 : 10, right: 10),
              // TV: a trailing "View all" tile, see TvSeeAllTile.
              itemCount: providers.length + (AppPlatform.isTv ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == providers.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: TvSeeAllTile(
                      onTap: () => context.push('/all-providers'),
                      width: 160,
                      height: 90,
                    ),
                  );
                }
                final provider = providers[index];
                return FocusableTap(
                  onTap: () {
                    context.push('/provider/${provider['id']}?name=${Uri.encodeComponent(provider['name'] as String)}');
                  },
                  child: Container(
                    width: 160,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E24), // Sleek dark mode color
                      borderRadius: BorderRadius.circular(6), // Reduced roundness
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: ArtworkImage(
                        imageUrl: provider['logo_path'] as String,
                        kind: ArtworkKind.logo,
                        fit: BoxFit.contain,
                        maxDecodeWidth: 240,
                        errorWidget: (context, url, error) => Center(
                          child: Text(
                            provider['name'] as String,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTitleText(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 32,
        fontWeight: FontWeight.bold,
        height: 1.2,
      ),
    );
  }

  Widget _desktopOutlineButton({required Widget icon, required VoidCallback onTap}) {
    return _AnimatedHoverScale(
      child: FocusableTap(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black26,
            border: Border.all(color: Colors.white24, width: 1.5),
            shape: BoxShape.circle,
          ),
          child: Center(child: icon),
        ),
      ),
    );
  }

  Widget _buildGenreBubble(String genre, Color themeColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
         color: themeColor.withOpacity(0.12),
         border: Border.all(color: themeColor.withOpacity(0.4), width: 1.2),
         borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        genre,
        style: TextStyle(
          color: themeColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<Widget> _buildDesktopBadges(
    int? episodes,
    String format,
    String status,
    String? season,
    double? voteAverage,
    Color themeColor,
  ) {
    final widgets = <Widget>[];
     
    if (episodes != null && episodes > 0) {
      widgets.add(_buildBadge("$episodes Episode${episodes > 1 ? 's' : ''}", themeColor));
    }
    if (format.isNotEmpty) {
      widgets.add(_buildBadge(format, themeColor));
    }
    if (status.isNotEmpty) {
      widgets.add(_buildBadge(status, themeColor));
    }
    if (season != null && season.isNotEmpty) {
      widgets.add(_buildBadge(season, themeColor));
    }
    if (voteAverage != null && voteAverage > 0) {
      final pct = (voteAverage * 10).toInt();
      widgets.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: pct >= 70 ? const Color(0xFF4CAF50).withOpacity(0.12) : themeColor.withOpacity(0.12),
            border: Border.all(
              color: pct >= 70 ? const Color(0xFF4CAF50).withOpacity(0.4) : themeColor.withOpacity(0.4),
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            "$pct%",
            style: TextStyle(
              color: pct >= 70 ? const Color(0xFF4CAF50) : themeColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
     
    return widgets;
  }

  Widget _buildBadge(String text, Color themeColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.12),
        border: Border.all(color: themeColor.withOpacity(0.4), width: 1.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: themeColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Total pan of the current trackpad gesture over the hero (see the Listener
  // in the carousel — the outer scroll eats these so we handle them directly).
  Offset _heroPanTotal = Offset.zero;
  bool _heroPanActive = false;

  /// Advance/rewind the hero on a horizontal-dominant trackpad swipe. Vertical
  /// gestures are ignored here so they keep scrolling the page normally.
  void _handleHeroTrackpadSwipe(Offset pan) {
    if (!_pageController.hasClients) return;
    if (pan.dx.abs() < 24 || pan.dx.abs() <= pan.dy.abs()) return; // not horizontal
    final current =
        (_pageController.page ?? _currentBannerPage.toDouble()).round();
    final next = pan.dx < 0 ? current + 1 : current - 1; // swipe left => next
    if (next < 0) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  Color _artworkBackground(BuildContext context) {
    final base = NivioTheme.backgroundColorOf(context);
    return ref.watch(dynamicArtworkColorsProvider)
        ? Color.lerp(base, _currentAmbientColor, 0.15)!
        : base;
  }

  Widget _buildHeroBannerCarousel(BuildContext context, List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox(height: 500);
    final isDesktop = AppPlatform.useDesktopLayout;
    final retainArtwork = TabArtworkScope.retainsArtwork(context);
    final watchlistIds = ref
        .watch(watchlistProvider)
        .map((item) => item.id)
        .toSet();
    final itemCount = items.length + 1;

    final dynamicColors = ref.watch(dynamicArtworkColorsProvider);
    if (dynamicColors && retainArtwork && !_ambientColors.containsKey(0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _extractColorForIndex(items, 0);
      });
    }
    final viewport = MediaQuery.sizeOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final bannerHeight = isDesktop ? viewport.height * 0.8 : 600.0;
    final logoHeight = isDesktop ? 110.0 : 75.0;

    return SizedBox(
      height: bannerHeight,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        // On desktop the hero PageView is set to NeverScrollable so it never
        // competes for trackpad/mouse gestures (that competition ate the first
        // vertical swipe over the hero and froze page scrolling). Instead we
        // drive it here: a horizontal-dominant swipe/drag changes the banner,
        // while vertical gestures fall straight through to scroll the page.
        // Mobile keeps native touch paging.
        onPointerDown: isDesktop
            ? (e) {
                _heroPanTotal = Offset.zero;
                _heroPanActive = true;
              }
            : null,
        onPointerMove: isDesktop
            ? (e) {
                if (_heroPanActive) _heroPanTotal += e.delta;
              }
            : null,
        onPointerUp: isDesktop
            ? (e) {
                if (_heroPanActive) {
                  _heroPanActive = false;
                  _handleHeroTrackpadSwipe(_heroPanTotal);
                }
              }
            : null,
        onPointerCancel: isDesktop ? (e) => _heroPanActive = false : null,
        onPointerPanZoomStart: isDesktop
            ? (_) {
                _heroPanTotal = Offset.zero;
                _heroPanActive = true;
              }
            : null,
        onPointerPanZoomUpdate: isDesktop ? (e) => _heroPanTotal = e.pan : null,
        onPointerPanZoomEnd: isDesktop
            ? (_) {
                if (_heroPanActive) {
                  _heroPanActive = false;
                  _handleHeroTrackpadSwipe(_heroPanTotal);
                }
              }
            : null,
        // TV: pause the auto-advance while a hero button has D-pad focus, or
        // the slide would change (and drop focus) under the user.
        child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasFocus) => _heroHasFocus = AppPlatform.isTv && hasFocus,
        child: PageView.builder(
        controller: _pageController,
        clipBehavior: isDesktop ? Clip.hardEdge : Clip.none,
        itemCount: itemCount,
        physics: isDesktop
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        onPageChanged: (index) {
          final actualIndex = index % items.length;
          if (dynamicColors && retainArtwork) _extractColorForIndex(items, actualIndex);

          if (index == items.length) {
            setState(() {
              _currentBannerIndex = 0;
              _currentBannerPage = index;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_pageController.hasClients) return;
              _pageController.jumpToPage(0);
              if (mounted) {
                setState(() => _currentBannerPage = 0);
              }
            });
            return;
          }

          setState(() {
            _currentBannerPage = index;
            _currentBannerIndex = index % items.length;
            if (_ambientColors.containsKey(_currentBannerIndex)) {
              _currentAmbientColor = _ambientColors[_currentBannerIndex]!;
              ref.read(ambientColorProvider.notifier).state = _currentAmbientColor;
            }
          });
        },
        itemBuilder: (context, index) {
          final content = items[index == items.length ? 0 : index];
          
          final tmdbId = content['id'] as int? ?? 0;
          final mediaType = content['media_type'] as String? ?? 'movie';
          final seasonNumber = content['season_number'] as int? ?? 1;
          final seasonQuery = (mediaType == 'tv' && seasonNumber > 1) ? '&season=$seasonNumber' : '';
          final title = content['title'] as String? ?? 'Featured';
          final rawBackdropPath = content['backdrop_path'] as String?;
          final posterPath = content['poster_path'] as String?;
          final voteAverage = content['vote_average'] as double?;
          final year = content['year'] as String? ?? '';
          final genres = List<String>.from(content['genres'] ?? []);
          
          final episodes = content['episodes'] as int?;
          final format = content['format'] as String? ?? '';
          final status = content['status'] as String? ?? '';
          final season = content['season'] as String?;

          final logoUrl = content['logo_url'] as String?;
          final logoImage = logoUrl == null || !retainArtwork
              ? null
              : artworkImageProvider(
                  logoUrl,
                  width: viewport.width * (isDesktop ? 0.6 : 1),
                  height: logoHeight,
                  pixelRatio: pixelRatio,
                  kind: ArtworkKind.logo,
                  fit: BoxFit.contain,
                );

          // Desktop: use the TMDB-enriched backdrop (high quality; falls back to
          // the AniList backdrop only when TMDB has none). Mobile: portrait poster.
          // (Restored from commit b65a017 — the AniList "clean_backdrop" was
          // taking priority over the higher-quality TMDB backdrop.)
          final backdropPath = isDesktop ? (rawBackdropPath ?? posterPath) : posterPath;

          final isInWatchlist = tmdbId != 0
              ? (_pendingWatchlistState[tmdbId] ??
                    watchlistIds.contains(tmdbId))
              : false;


          final activeBgColor = _artworkBackground(context);
          final slideColor = (dynamicColors ? _ambientColors[_currentBannerIndex] : null) ?? NivioTheme.accentColorOf(context);

          final mobileMeta = <String>[
            if (genres.isNotEmpty) genres.take(3).join(' / '),
            if (voteAverage != null && voteAverage > 0) voteAverage.toStringAsFixed(1),
            if (year.isNotEmpty) year,
          ];

          final art = Container(
                decoration: BoxDecoration(
                  image: backdropPath != null && retainArtwork
                      ? DecorationImage(
                          image: artworkImageProvider(
                            backdropPath,
                            width: viewport.width,
                            height: bannerHeight,
                            pixelRatio: pixelRatio,
                            kind: isDesktop && rawBackdropPath != null
                                ? ArtworkKind.backdrop
                                : ArtworkKind.poster,
                          ),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: backdropPath == null || !retainArtwork
                      ? const Color(0xFF2F2F2F)
                      : null,
                ),
              );
          // TV: off-screen hero slides stay built in the PageView; keep them out
          // of D-pad focus so arrows never land on (and scroll to) them.
          return ExcludeFocus(
            excluding: AppPlatform.isTv && index != _currentBannerPage,
            child: Stack(
            children: [
              if (isDesktop) art else HeroArtworkStretch(
                controller: _scrollController,
                height: bannerHeight,
                child: art,
              ),
              // Vignette overlay
              if (isDesktop && retainArtwork)
                Positioned.fill(
                  child: Image.asset(
                    // TV ships the desktop vignette (the mobile package's
                    // vignette.png is an older, different image).
                    AppPlatform.isTv
                        ? 'assets/images/vignette_tv.png'
                        : 'assets/images/vignette.png',
                    fit: BoxFit.fill,
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: bannerHeight * 0.4,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        activeBgColor.withOpacity(0.8),
                        activeBgColor,
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: isDesktop ? 40 : 76,
                left: isDesktop ? 68 : 24,
                right: isDesktop ? 48 : 24,
                child: isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            flex: 6,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (logoImage != null)
                                  GestureDetector(
                                    onTap: () => context.push('/media/$tmdbId?type=$mediaType$seasonQuery'),
                                    child: DpadFocusable(
                                      onActivate: () => context.push('/media/$tmdbId?type=$mediaType$seasonQuery'),
                                      child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: Image(
                                        image: logoImage,
                                        height: logoHeight,
                                        alignment: Alignment.bottomLeft,
                                        fit: BoxFit.contain,
                                        frameBuilder: (_, child, frame, _) =>
                                            frame == null
                                                ? SizedBox(height: logoHeight, child: _buildTitleText(title))
                                                : child,
                                        errorBuilder: (_, __, ___) => _buildTitleText(title),
                                      ),
                                    ),
                                    ),
                                  )
                                else
                                  GestureDetector(
                                    onTap: () => context.push('/media/$tmdbId?type=$mediaType$seasonQuery'),
                                    child: DpadFocusable(
                                      onActivate: () => context.push('/media/$tmdbId?type=$mediaType$seasonQuery'),
                                      child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: _buildTitleText(title),
                                    ),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _buildDesktopBadges(episodes, format, status, season, voteAverage, slideColor),
                                ),
                                const SizedBox(height: 24),
                                // TV: left/right on the outer buttons pages the
                                // hero (see _handleHeroButtonsKey).
                                Focus(
                                canRequestFocus: false,
                                skipTraversal: true,
                                onKeyEvent: AppPlatform.isTv
                                    ? (node, event) => _handleHeroButtonsKey(node, event)
                                    : null,
                                child: Row(
                                  children: [
                                    _AnimatedHoverScale(
                                      child: ElevatedButton.icon(
                                        focusNode: AppPlatform.isTv ? _heroWatchNode(index) : null,
                                        onPressed: () => context.push('/media/$tmdbId?type=$mediaType$seasonQuery'),
                                        icon: PhosphorIcon(
                                          PhosphorIconsFill.play,
                                          color: slideColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                          size: 15,
                                        ),
                                        label: Text(
                                          'Watch Now',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: slideColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: slideColor,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 19),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    _desktopOutlineButton(
                                      icon: PhosphorIcon(
                                        isInWatchlist ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                                        color: isInWatchlist ? slideColor : Colors.white,
                                        size: 18,
                                      ),
                                      onTap: () => _toggleFeaturedWatchlist(content),
                                    ),
                                    const SizedBox(width: 12),
                                    _desktopOutlineButton(
                                      icon: PhosphorIcon(
                                        isInWatchlist ? PhosphorIconsFill.bookmarkSimple : PhosphorIconsRegular.bookmarkSimple,
                                        color: isInWatchlist ? slideColor : Colors.white,
                                        size: 18,
                                      ),
                                      onTap: () => _toggleFeaturedWatchlist(content),
                                    ),
                                  ],
                                ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 40),
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  content['overview'] as String? ?? '',
                                  textAlign: TextAlign.right,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.end,
                                  children: genres.map((genre) => _buildGenreBubble(genre, slideColor)).toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (logoImage != null)
                            FocusableTap(
                              onTap: () => context.push('/media/$tmdbId?type=$mediaType$seasonQuery'),
                              child: Image(
                                image: logoImage,
                                height: logoHeight,
                                alignment: Alignment.center,
                                fit: BoxFit.contain,
                                frameBuilder: (_, child, frame, _) => frame != null ? child : SizedBox(
                                  height: logoHeight,
                                  child: Center(
                                    child: Text(
                                      title,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                errorBuilder: (_, __, ___) => Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                          else
                            FocusableTap(
                              onTap: () => context.push('/media/$tmdbId?type=$mediaType$seasonQuery'),
                              child: AnimatedOpacity(
                                opacity: 1,
                                duration: const Duration(milliseconds: 500),
                                child: Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          if (mobileMeta.isNotEmpty)
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: _buildMetaChips(mobileMeta),
                            ),
                        ],
                      ),
              ),
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    items.length,
                    (dotIndex) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _currentBannerIndex == dotIndex ? 7 : 5,
                        height: _currentBannerIndex == dotIndex ? 7 : 5,
                        decoration: BoxDecoration(
                          color: _currentBannerIndex == dotIndex
                              ? (_ambientColors[_currentBannerIndex] ?? NivioTheme.accentColorOf(context))
                              : Colors.white38,
                          shape: BoxShape.circle,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          );
        },
        ),
        ),
      ),
    );
  }

  Widget _buildHeroBannerShimmer() {
    final isDesktop = AppPlatform.useDesktopLayout;
    final height = isDesktop ? MediaQuery.sizeOf(context).height * 0.8 : 600.0;
    // Low-cost skeleton block instead of a spinning indicator.
    return Skeletonizer(
      child: SkeletonBox(
        width: double.infinity,
        height: height,
        borderRadius: BorderRadius.zero,
      ),
    );
  }

  Widget _buildProfileButton(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final authState = ref.watch(authStateProvider);
        final user = authState.value;

        return IconButton(
          icon: user?.photoURL != null
              ? CircleAvatar(
                  radius: 14,
                  backgroundImage: avatarArtworkImage(context, user!.photoURL!, 28),
                  backgroundColor: NivioTheme.netflixDarkGrey,
                )
              : const PhosphorIcon(
                  PhosphorIconsRegular.userCircle,
                  color: Colors.white,
                  size: 24,
                ),
          tooltip: 'Profile',
          onPressed: () => context.push('/profile'),
        );
      },
    );
  }

  Widget _buildBypassIndicator(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final apiStatus = ref.watch(apiStatusProvider);
        
        final isApiDown = apiStatus.anilistStatus == ApiServiceStatus.offline || apiStatus.newTvStatus == ApiServiceStatus.offline;
        
        Widget icon;
        String tooltip;
        
        if (isApiDown) {
           icon = const PhosphorIcon(PhosphorIconsFill.warningCircle, color: Colors.red, size: 22);
           if (apiStatus.anilistStatus == ApiServiceStatus.offline && apiStatus.newTvStatus == ApiServiceStatus.offline) {
             tooltip = 'Both AniList & NetMirror APIs are Offline';
           } else if (apiStatus.anilistStatus == ApiServiceStatus.offline) {
             tooltip = 'AniList API is Offline';
           } else {
             tooltip = 'NetMirror API is Offline';
           }
        } else {
           return const SizedBox.shrink();
        }
        
        return Padding(
          padding: const EdgeInsets.only(top: 8, right: 4),
          child: PopupMenuButton<int>(
            icon: icon,
            tooltip: tooltip,
            position: PopupMenuPosition.under,
            color: const Color(0xFF1E2126),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 2,
                child: Row(
                  children: [
                    apiStatus.anilistStatus == ApiServiceStatus.checking
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : apiStatus.anilistStatus == ApiServiceStatus.online
                        ? const PhosphorIcon(PhosphorIconsFill.checkCircle, color: Colors.green, size: 20)
                        : const PhosphorIcon(PhosphorIconsFill.warningCircle, color: Colors.red, size: 20),
                    const SizedBox(width: 12),
                    const Text('AniList API', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 3,
                child: Row(
                  children: [
                    const PhosphorIcon(PhosphorIconsRegular.arrowsClockwise, size: 20, color: Colors.white),
                    const SizedBox(width: 12),
                    const Text('Refresh All', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 2 || value == 3) {
                ref.read(apiStatusProvider.notifier).checkAll();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retrying APIs...')));
              }
            },
          ),
        );
      }
    );
  }

  Widget _buildNotificationBell(BuildContext context) {
    final unreadCount = EpisodeCheckService.getUnreadCount();
    
    if (unreadCount == 0) return const SizedBox.shrink();

    return Stack(
      children: [
        IconButton(
          icon: unreadCount > 0
              ? const PhosphorIcon(
                  PhosphorIconsFill.bellSimpleRinging,
                  color: Colors.white,
                  size: 22,
                )
              : const PhosphorIcon(
                  PhosphorIconsRegular.bell,
                  color: Colors.white,
                  size: 22,
                ),
          tooltip: 'New Episodes',
          onPressed: () => context.go('/library'),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Color(0xFFE50914),
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                unreadCount > 9 ? '9+' : unreadCount.toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildMetaChips(List<String> meta) {
    final widgets = <Widget>[];
    for (var index = 0; index < meta.length; index++) {
      widgets.add(
        Text(
          meta[index],
          style: TextStyle(
            color: Color(0xFFD4D8E3),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
      if (index != meta.length - 1) {
        widgets.add(
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Color(0xFFD4D8E3),
              shape: BoxShape.circle,
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Future<void> _toggleFeaturedWatchlist(Map<String, dynamic> content) async {
    final watchlistService = ref.read(watchlistServiceProvider);
    final mediaId = _parseMediaId(content['id']);
    if (mediaId == null) return;

    final currentlyInWatchlist =
        _pendingWatchlistState[mediaId] ??
        watchlistService.isInWatchlist(mediaId);
    final nextInWatchlist = !currentlyInWatchlist;
    setState(() {
      _pendingWatchlistState[mediaId] = nextInWatchlist;
    });

    final mediaType =
        (content['media_type'] ?? (content['title'] != null ? 'movie' : 'tv'))
            .toString();
    final item = WatchlistItem(
      id: mediaId,
      title: (content['title'] ?? content['name'] ?? 'Unknown').toString(),
      posterPath: content['poster_path']?.toString(),
      mediaType: mediaType,
      addedAt: DateTime.now(),
      voteAverage: (content['vote_average'] as num?)?.toDouble(),
      releaseDate: (content['first_air_date'] ?? content['release_date'])
          ?.toString(),
      overview: content['overview']?.toString(),
    );

    try {
      if (nextInWatchlist) {
        await watchlistService.addToWatchlist(item);
      } else {
        await watchlistService.removeFromWatchlist(mediaId);
      }
      ref.read(watchlistRefreshProvider.notifier).refresh();
    } finally {
      if (mounted) {
        setState(() {
          _pendingWatchlistState.remove(mediaId);
        });
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          nextInWatchlist ? 'Added to watchlist' : 'Removed from watchlist',
        ),
      ),
    );
  }

  int? _parseMediaId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class _AnimatedHoverScale extends StatefulWidget {
  final Widget child;
  const _AnimatedHoverScale({required this.child});

  @override
  State<_AnimatedHoverScale> createState() => _AnimatedHoverScaleState();
}

class _AnimatedHoverScaleState extends State<_AnimatedHoverScale> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _isHovered ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

