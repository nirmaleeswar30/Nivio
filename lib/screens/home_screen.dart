import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/constants.dart';

import 'package:nivio/core/providers_data.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/providers/auth_provider.dart';
import 'package:nivio/providers/changelog_provider.dart';
import 'package:nivio/providers/home_providers.dart';
import 'package:nivio/providers/language_preferences_provider.dart';
import 'package:nivio/providers/home_layout_provider.dart';
import 'package:nivio/providers/recommendations_provider.dart';

import 'package:nivio/providers/watch_history_provider.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/services/episode_check_service.dart';
import 'package:nivio/services/api_status_service.dart';
import 'package:nivio/widgets/changelog_dialog.dart';
import 'package:nivio/widgets/content_row.dart';
import 'package:nivio/widgets/continue_watching_row.dart';
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
  bool _showAppBarBackground = false;
  bool _isBannerVisible = true;
  int _currentBannerIndex = 0;
  int _currentBannerPage = 0;
  Timer? _bannerTimer;
  final Map<int, bool> _pendingWatchlistState = <int, bool>{};
  final Map<int, Color> _ambientColors = {};
  Color _currentAmbientColor = const Color(0xFF0D0F14);



  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.offset > 50 && !_showAppBarBackground) {
        setState(() => _showAppBarBackground = true);
      } else if (_scrollController.offset <= 50 && _showAppBarBackground) {
        setState(() => _showAppBarBackground = false);
      }
      
      // The hero banner is ~500-600px tall. If we've scrolled past 800px, it's definitely offscreen.
      final isVisible = _scrollController.offset < 800;
      if (isVisible != _isBannerVisible) {
        // We don't setState here because we don't need to rebuild the UI,
        // we just need to update the flag so the timer knows to pause.
        _isBannerVisible = isVisible;
      }
    });

    _bannerTimer = Timer.periodic(const Duration(seconds: 14), (timer) {
      if (!_pageController.hasClients || !_isBannerVisible) return;
      // Don't waste cycles on banner animation while the video player is active
      if (ref.read(isPlayerActiveProvider)) return;
      final featuredContent = ref.read(featuredContentProvider).value ?? [];
      if (featuredContent.isEmpty) return;
      _pageController.animateToPage(
        _currentBannerPage + 1,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
      );
    });

    unawaited(_prewarmHomeContent());
  }

  Future<void> _prewarmHomeContent() async {
    await Future.wait([
      ref.read(featuredContentProvider.future),
      ref.read(popularMoviesProvider.future),
      ref.read(trendingMoviesProvider.future),
      ref.read(topRatedMoviesProvider.future),
      ref.read(popularTVShowsProvider.future),
      ref.read(trendingTVShowsProvider.future),
      ref.read(animeProvider.future),
      ref.read(trendingAnimeProvider.future),
    ]);
  }

  Future<void> _extractColorForIndex(List<Map<String, dynamic>> items, int index) async {
    if (items.isEmpty || index >= items.length) return;
    
    if (_ambientColors.containsKey(index)) return;

    // Don't run expensive color extraction while the video player is active
    if (ref.read(isPlayerActiveProvider)) return;
    
    final content = items[index];
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final posterPath = isDesktop
        ? (content['backdrop_path'] ?? content['poster_path'])?.toString()
        : (content['poster_path'] ?? content['backdrop_path'])?.toString();
    if (posterPath == null) return;
    
    try {
      final url = posterPath.startsWith('http') 
          ? posterPath 
          : '$tmdbImageBaseUrl/w200$posterPath';
      
      final colorScheme = await ColorScheme.fromImageProvider(
        provider: NetworkImage(url),
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
    } catch (_) {}
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pageController.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
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
        case 'popular_movies':
          dynamicSections.add(_buildRowSection('All Time Popular', popularMoviesProvider));
          break;
        case 'trending_movies':
          dynamicSections.add(_buildRowSection('Trending Now', trendingMoviesProvider));
          break;
        case 'top_rated_movies':
          dynamicSections.add(_buildRowSection('Top Rated Movies', topRatedMoviesProvider));
          break;
        case 'popular_tv':
          dynamicSections.add(_buildRowSection('Popular TV Shows', popularTVShowsProvider));
          break;
        case 'trending_tv':
          dynamicSections.add(_buildRowSection('Trending TV Shows', trendingTVShowsProvider));
          break;
        case 'popular_anime':
          if (languagePreferences.showAnime) dynamicSections.add(_buildRowSection('Popular Anime', animeProvider));
          break;
        case 'trending_anime':
          if (languagePreferences.showAnime) dynamicSections.add(_buildRowSection('Trending Anime', trendingAnimeProvider));
          break;
        case 'tamil':
          if (languagePreferences.showTamil) dynamicSections.add(_buildRowSection('Tamil Picks', tamilMoviesProvider));
          break;
        case 'telugu':
          if (languagePreferences.showTelugu) dynamicSections.add(_buildRowSection('Telugu Picks', teluguMoviesProvider));
          break;
        case 'hindi':
          if (languagePreferences.showHindi) dynamicSections.add(_buildRowSection('Hindi Picks', hindiMoviesProvider));
          break;
        case 'korean':
          if (languagePreferences.showKorean) dynamicSections.add(_buildRowSection('Korean Dramas', koreanDramasProvider));
          break;
        case 'malayalam':
          if (languagePreferences.showMalayalam) dynamicSections.add(_buildRowSection('Malayalam Picks', malayalamMoviesProvider));
          break;
      }
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: isDesktop ? null : PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          flexibleSpace: ClipRect(
            child: _showAppBarBackground
                ? Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFA0D0F14), // Near opaque dark background
                      border: Border(
                        bottom: BorderSide(color: Color(0x22FFFFFF)),
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
          title: isDesktop 
              ? const SizedBox.shrink()
              : const Padding(
                  padding: EdgeInsets.only(top: 6, left: 2),
                  child: SizedBox(
                    height: 80,
                    child: Image(
                      image: AssetImage('assets/images/nivio-dark.png'),
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
                  color: Color.lerp(const Color(0xFF0D0F14), _currentAmbientColor, 0.15),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AppCustomScrollView(
          controller: _scrollController,
          cacheExtent: 250,
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
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, child) {
                final continueWatching = ref.watch(continueWatchingProvider);
                return continueWatching.when(
                  data: (items) {
                    if (items.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: EdgeInsets.only(top: 0, left: isDesktop ? 68 : 16, right: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Continue Watching',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 12),
                          ContinueWatchingRow(),
                          SizedBox(height: 30),
                        ],
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (error, stackTrace) => const SizedBox.shrink(),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, child) {
                final watchlist = ref.watch(watchlistProvider);
                if (watchlist.isEmpty) return const SizedBox.shrink();

                final seenIds = <int>{};
                final watchlistItems = watchlist
                    .where((item) => seenIds.add(item.id))
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

                return ContentRow(title: 'Your List', items: watchlistItems);
              },
            ),
          ),
          _buildProviderSelectionRow(),
          const SliverToBoxAdapter(
            child: SizedBox(height: 40),
          ),
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, _) {
                final recsAsync = ref.watch(homeRecommendationsProvider);
                return recsAsync.when(
                  data: (recs) {
                    if (recs == null || recs.items.isEmpty) return const SizedBox.shrink();
                    final items = recs.items.map((e) => e.toJson()).toList();
                    return ContentRow(title: 'Recommended for You', items: items);
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ),
          ...dynamicSections,
          const SliverToBoxAdapter(child: SizedBox(height: 50)),
        ],
      ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowSection(
    String title,
    FutureProvider<List<dynamic>> provider,
  ) {
    return SliverToBoxAdapter(
      key: ValueKey(title),
      child: Consumer(
        builder: (context, ref, child) {
          final asyncItems = ref.watch(provider);
          return asyncItems.when(
            data: (items) => ContentRow(title: title, items: items),
            loading: () => const SizedBox(height: 220),
            error: (error, stackTrace) => const SizedBox.shrink(),
          );
        },
      ),
    );
  }


  Widget _buildProviderSelectionRow() {
    final providers = allProviders.take(20).toList();
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    return SliverToBoxAdapter(
      child: Column(
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
                TextButton(
                  onPressed: () {
                    context.push('/all-providers');
                  },
                  child: const Text(
                    'View All',
                    style: TextStyle(
                      color: Color(0xFF00B4D8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(left: isDesktop ? 64 : 10, right: 10),
              itemCount: providers.length,
              itemBuilder: (context, index) {
                final provider = providers[index];
                return GestureDetector(
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
                      child: CachedNetworkImage(
                        imageUrl: '$tmdbImageBaseUrl/w500${provider['logo_path']}',
                        fit: BoxFit.contain,
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
      ),
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
      child: GestureDetector(
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

  Widget _buildHeroBannerCarousel(BuildContext context, List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const SizedBox(height: 500);
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final watchlistIds = ref
        .watch(watchlistProvider)
        .map((item) => item.id)
        .toSet();
    final itemCount = items.length + 1;

    if (!_ambientColors.containsKey(0) && items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _extractColorForIndex(items, 0);
      });
    }
    final bannerHeight = isDesktop ? MediaQuery.sizeOf(context).height * 0.8 : 600.0;

    return SizedBox(
      height: bannerHeight,
      child: PageView.builder(
        controller: _pageController,
        itemCount: itemCount,
        onPageChanged: (index) {
          final actualIndex = index % items.length;
          _extractColorForIndex(items, actualIndex);

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

          final isDesktop = !Platform.isAndroid && !Platform.isIOS;
          // Desktop: use the TMDB-enriched backdrop (high quality; falls back to
          // the AniList backdrop only when TMDB has none). Mobile: portrait poster.
          // (Restored from commit b65a017 — the AniList "clean_backdrop" was
          // taking priority over the higher-quality TMDB backdrop.)
          final backdropPath = isDesktop ? (rawBackdropPath ?? posterPath) : posterPath;

          final isInWatchlist = tmdbId != 0
              ? (_pendingWatchlistState[tmdbId] ??
                    watchlistIds.contains(tmdbId))
              : false;

          final backdropUrl = (backdropPath != null && backdropPath.startsWith('http')) 
              ? backdropPath 
              : _tmdbImageUrl(backdropPath, backdropSize);

          final activeBgColor = Color.lerp(const Color(0xFF0D0F14), _currentAmbientColor, 0.15)!;
          final slideColor = _ambientColors[_currentBannerIndex] ?? NivioTheme.accentColorOf(context);

          final mobileMeta = <String>[
            if (genres.isNotEmpty) genres.take(3).join(' / '),
            if (voteAverage != null && voteAverage > 0) voteAverage.toStringAsFixed(1),
            if (year.isNotEmpty) year,
          ];

          return Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  image: backdropUrl != null
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(backdropUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: backdropUrl == null ? const Color(0xFF2F2F2F) : null,
                ),
              ),
              // Vignette overlay
              if (isDesktop)
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/vignette.png',
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
                                if (logoUrl != null && logoUrl.isNotEmpty)
                                  GestureDetector(
                                    onTap: () => context.push('/media/$tmdbId?type=$mediaType'),
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: CachedNetworkImage(
                                        imageUrl: logoUrl,
                                        height: 110,
                                        alignment: Alignment.bottomLeft,
                                        fit: BoxFit.contain,
                                        fadeInDuration: Duration.zero,
                                        fadeOutDuration: Duration.zero,
                                        placeholder: (context, url) => SizedBox(height: 110, child: _buildTitleText(title)),
                                        errorWidget: (_, __, ___) => _buildTitleText(title),
                                      ),
                                    ),
                                  )
                                else
                                  GestureDetector(
                                    onTap: () => context.push('/media/$tmdbId?type=$mediaType'),
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: _buildTitleText(title),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _buildDesktopBadges(episodes, format, status, season, voteAverage, slideColor),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    _AnimatedHoverScale(
                                      child: ElevatedButton.icon(
                                        onPressed: () => context.push('/media/$tmdbId?type=$mediaType'),
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
                          if (logoUrl != null && logoUrl.isNotEmpty)
                            GestureDetector(
                              onTap: () => context.push('/media/$tmdbId?type=$mediaType'),
                              child: CachedNetworkImage(
                                imageUrl: logoUrl,
                                height: 75,
                                alignment: Alignment.center,
                                fit: BoxFit.contain,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (context, url) => SizedBox(
                                  height: 75,
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
                                errorWidget: (_, __, ___) => Text(
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
                            AnimatedOpacity(
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
                          const SizedBox(height: 8),
                          if (mobileMeta.isNotEmpty)
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: _buildMetaChips(mobileMeta),
                            ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _AnimatedHoverScale(
                                child: ElevatedButton.icon(
                                  onPressed: () => context.push('/media/$tmdbId?type=$mediaType'),
                                  icon: PhosphorIcon(
                                    PhosphorIconsFill.play,
                                    color: slideColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                    size: 16,
                                  ),
                                  label: Text(
                                    'Watch Now',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: slideColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: slideColor,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              _smallSquareButton(
                                icon: PhosphorIcon(
                                  isInWatchlist
                                      ? PhosphorIconsFill.checkCircle
                                      : PhosphorIconsRegular.plus,
                                  color: isInWatchlist
                                      ? slideColor
                                      : Colors.white,
                                  size: 18,
                                ),
                                onTap: () => _toggleFeaturedWatchlist(content),
                              ),
                            ],
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
          );
        },
      ),
    );
  }

  Widget _buildHeroBannerShimmer() {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    return Container(
      height: isDesktop ? MediaQuery.sizeOf(context).height * 0.8 : 600.0,
      color: const Color(0xFF2F2F2F),
      child: Center(
        child: CircularProgressIndicator(
          color: NivioTheme.accentColorOf(context),
        ),
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
                  backgroundImage: CachedNetworkImageProvider(user!.photoURL!),
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

  Widget _smallSquareButton({required Widget icon, required VoidCallback onTap}) {
    return _AnimatedHoverScale(
      child: Material(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 38, height: 38, child: Center(child: icon)),
        ),
      ),
    );
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

  String? _tmdbImageUrl(String? path, String size) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$tmdbImageBaseUrl/$size$path';
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

