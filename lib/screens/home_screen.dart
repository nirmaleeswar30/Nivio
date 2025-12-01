import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/providers/home_providers.dart';
import 'package:nivio/providers/language_preferences_provider.dart';
import 'package:nivio/widgets/continue_watching_row.dart';
import 'package:nivio/widgets/content_row.dart';
import 'package:nivio/services/episode_check_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();
  bool _showAppBarBackground = false;
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.offset > 50 && !_showAppBarBackground) {
        setState(() => _showAppBarBackground = true);
      } else if (_scrollController.offset <= 50 && _showAppBarBackground) {
        setState(() => _showAppBarBackground = false);
      }
    });

    // Preload critical data first (featured, trending) for instant display
    // Other content loads lazily in background
    // Removed progressive loading - providers now load lazily via Consumer widgets

    // Auto-slide banner every 6 seconds
    _bannerTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (_pageController.hasClients) {
        final featuredContent = ref.read(featuredContentProvider).value ?? [];
        if (featuredContent.isNotEmpty) {
          final nextPage = (_currentBannerIndex + 1) % featuredContent.length;
          _pageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeInOutCubic,
          );
        }
      }
    });
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
    // CRITICAL: Only watch featured content in build to avoid blocking
    // Other providers load lazily when their widgets scroll into view
    final featuredContent = ref.watch(featuredContentProvider);
    final languagePreferences = ref.watch(languagePreferencesProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          elevation: 0,
          backgroundColor: _showAppBarBackground 
              ? const Color(0xFF141414) 
              : Colors.transparent,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: _showAppBarBackground 
                  ? null 
                  : LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
            ),
          ),
          title: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Image.asset(
              'assets/images/nivio-dark.png',
              height: 100,
              fit: BoxFit.contain,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: IconButton(
                icon: const Icon(Icons.search, color: Colors.white, size: 28),
                onPressed: () => context.push('/search'),
              ),
            ),
            // Notification bell with badge
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: _buildNotificationBell(context),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: IconButton(
                icon: const Icon(Icons.bookmark_border, color: Colors.white, size: 28),
                tooltip: 'My List',
                onPressed: () => context.push('/watchlist'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: IconButton(
                icon: const Icon(Icons.account_circle_outlined, color: Colors.white, size: 28),
                tooltip: 'Profile',
                onPressed: () => context.push('/profile'),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Hero Banner Carousel with Regional + General Content
          SliverToBoxAdapter(
            child: featuredContent.when(
              data: (content) => _buildHeroBannerCarousel(context, content),
              loading: () => _buildHeroBannerShimmer(),
              error: (_, __) => const SizedBox(height: 500),
            ),
          ),

          // Continue Watching Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 0, left: 16, right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Continue Watching',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const ContinueWatchingRow(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),

          // Anime Section (if enabled)
          if (languagePreferences.showAnime) ...[
            SliverToBoxAdapter(
              child: Consumer(
                builder: (context, ref, child) {
                  final anime = ref.watch(animeProvider);
                  return anime.when(
                    data: (shows) => ContentRow(
                      title: '🎌 Popular Anime',
                      items: shows,
                    ),
                    loading: () => const SizedBox(height: 220),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ),

            // Trending Anime
            SliverToBoxAdapter(
              child: Consumer(
                builder: (context, ref, child) {
                  final trendingAnime = ref.watch(trendingAnimeProvider);
                  return trendingAnime.when(
                    data: (shows) => ContentRow(
                      title: '🔥 Trending Anime',
                      items: shows,
                    ),
                    loading: () => const SizedBox(height: 220),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ],

          // Tamil Movies (if enabled)
          if (languagePreferences.showTamil) ...[
            SliverToBoxAdapter(
              child: Consumer(
                builder: (context, ref, child) {
                  final tamilMovies = ref.watch(tamilMoviesProvider);
                  return tamilMovies.when(
                    data: (movies) => ContentRow(
                      title: '🎬 Latest Tamil OTT Releases',
                      items: movies,
                    ),
                    loading: () => const SizedBox(height: 220),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ),

            // Trending Tamil
            SliverToBoxAdapter(
              child: Consumer(
                builder: (context, ref, child) {
                  final trendingTamil = ref.watch(trendingTamilMoviesProvider);
                  return trendingTamil.when(
                    data: (movies) => ContentRow(
                      title: '🔥 Trending Tamil Movies',
                      items: movies,
                    ),
                    loading: () => const SizedBox(height: 220),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ],

          // Telugu Movies (if enabled)
          if (languagePreferences.showTelugu) ...[
            SliverToBoxAdapter(
              child: Consumer(
                builder: (context, ref, child) {
                  final teluguMovies = ref.watch(teluguMoviesProvider);
                  return teluguMovies.when(
                    data: (movies) => ContentRow(
                      title: '🎥 Popular Telugu Movies',
                      items: movies,
                    ),
                    loading: () => const SizedBox(height: 220),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ),

            // Trending Telugu
            SliverToBoxAdapter(
              child: Consumer(
                builder: (context, ref, child) {
                  final trendingTelugu = ref.watch(trendingTeluguMoviesProvider);
                  return trendingTelugu.when(
                    data: (movies) => ContentRow(
                      title: '🔥 Trending Telugu Movies',
                      items: movies,
                    ),
                    loading: () => const SizedBox(height: 220),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ],

          // Hindi Movies (if enabled)
          if (languagePreferences.showHindi) ...[
            SliverToBoxAdapter(
              child: Consumer(
                builder: (context, ref, child) {
                  final hindiMovies = ref.watch(hindiMoviesProvider);
                  return hindiMovies.when(
                    data: (movies) => ContentRow(
                      title: '🎞️ Popular Hindi Movies',
                      items: movies,
                    ),
                    loading: () => const SizedBox(height: 220),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ),

            // Trending Hindi
            SliverToBoxAdapter(
              child: Consumer(
                builder: (context, ref, child) {
                  final trendingHindi = ref.watch(trendingHindiMoviesProvider);
                  return trendingHindi.when(
                    data: (movies) => ContentRow(
                      title: '🔥 Trending Hindi Movies',
                      items: movies,
                    ),
                    loading: () => const SizedBox(height: 220),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ],

          // Korean Dramas (if enabled)
          if (languagePreferences.showKorean) ...[
            SliverToBoxAdapter(
              child: Consumer(
                builder: (context, ref, child) {
                  final koreanDramas = ref.watch(koreanDramasProvider);
                  return koreanDramas.when(
                    data: (shows) => ContentRow(
                      title: '🇰🇷 Popular Korean Dramas',
                      items: shows,
                    ),
                    loading: () => const SizedBox(height: 220),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ),

            // Trending Korean
            SliverToBoxAdapter(
              child: Consumer(
                builder: (context, ref, child) {
                  final trendingKorean = ref.watch(trendingKoreanDramasProvider);
                  return trendingKorean.when(
                    data: (shows) => ContentRow(
                      title: '🔥 Trending Korean Dramas',
                      items: shows,
                    ),
                    loading: () => const SizedBox(height: 220),
                    error: (_, __) => const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ],

          // Trending Movies
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, child) {
                final trendingMovies = ref.watch(trendingMoviesProvider);
                return trendingMovies.when(
                  data: (movies) => ContentRow(
                    title: 'Trending Movies',
                    items: movies,
                  ),
                  loading: () => const SizedBox(height: 220),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ),

          // Trending TV Shows
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, child) {
                final trendingTVShows = ref.watch(trendingTVShowsProvider);
                return trendingTVShows.when(
                  data: (shows) => ContentRow(
                    title: 'Trending TV Shows',
                    items: shows,
                  ),
                  loading: () => const SizedBox(height: 220),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ),

          // Popular Movies
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, child) {
                final popularMovies = ref.watch(popularMoviesProvider);
                return popularMovies.when(
                  data: (movies) => ContentRow(
                    title: 'Popular Movies',
                    items: movies,
                  ),
                  loading: () => const SizedBox(height: 220),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ),

          // Popular TV Shows
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, child) {
                final popularTVShows = ref.watch(popularTVShowsProvider);
                return popularTVShows.when(
                  data: (shows) => ContentRow(
                    title: 'Popular TV Shows',
                    items: shows,
                  ),
                  loading: () => const SizedBox(height: 220),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ),

          // Top Rated Movies
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, child) {
                final topRatedMovies = ref.watch(topRatedMoviesProvider);
                return topRatedMovies.when(
                  data: (movies) => ContentRow(
                    title: 'Top Rated Movies',
                    items: movies,
                  ),
                  loading: () => const SizedBox(height: 220),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ),

          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 50),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBannerCarousel(BuildContext context, List<dynamic> items) {
    if (items.isEmpty) return const SizedBox(height: 500);

    return SizedBox(
      height: 600,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _currentBannerIndex = index);
        },
        itemCount: items.length,
        itemBuilder: (context, index) {
          final content = items[index];
          final backdropPath = content['backdrop_path'] ?? content['poster_path'];
          final title = content['title'] ?? content['name'] ?? 'Featured';
          final overview = content['overview'] ?? '';
          final tmdbId = content['id'];
          final mediaType = content['media_type'] ?? (content['title'] != null ? 'movie' : 'tv');

          return Stack(
            children: [
              // Background Image with Animation
              AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 500),
                child: Container(
                  decoration: BoxDecoration(
                    image: backdropPath != null
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(
                              '$tmdbImageBaseUrl/$backdropSize$backdropPath',
                            ),
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: backdropPath == null ? const Color(0xFF2F2F2F) : null,
                  ),
                ),
              ),
              // Gradient Overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.5),
                      const Color(0xFF141414),
                    ],
                    stops: const [0.0, 0.7, 1.0],
                  ),
                ),
              ),
              // Content
              Positioned(
                bottom: 80,
                left: 30,
                right: 30,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 500),
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              blurRadius: 10.0,
                              color: Colors.black,
                              offset: Offset(2, 2),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (overview.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      AnimatedOpacity(
                        opacity: 1.0,
                        duration: const Duration(milliseconds: 500),
                        child: Text(
                          overview,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.4,
                            shadows: [
                              Shadow(
                                blurRadius: 8.0,
                                color: Colors.black,
                                offset: Offset(1, 1),
                              ),
                            ],
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => context.push('/media/$tmdbId', extra: mediaType),
                          icon: const Icon(Icons.play_arrow, size: 32, color: Colors.black),
                          label: const Text(
                            'Play',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/media/$tmdbId', extra: mediaType),
                          icon: const Icon(Icons.info_outline, size: 28, color: Colors.white),
                          label: const Text(
                            'More Info',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            side: const BorderSide(color: Colors.white70, width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Page Indicators
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    items.length,
                    (dotIndex) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentBannerIndex == dotIndex ? 24 : 8,
                      height: 3,
                      decoration: BoxDecoration(
                        color: _currentBannerIndex == dotIndex
                            ? const Color(0xFFE50914)
                            : Colors.white38,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
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
    return Container(
      height: 600,
      color: const Color(0xFF2F2F2F),
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xFFE50914)),
      ),
    );
  }

  Widget _buildNotificationBell(BuildContext context) {
    final unreadCount = EpisodeCheckService.getUnreadCount();
    
    return Stack(
      children: [
        IconButton(
          icon: Icon(
            unreadCount > 0 ? Icons.notifications : Icons.notifications_none,
            color: Colors.white,
            size: 28,
          ),
          tooltip: 'New Episodes',
          onPressed: () => context.push('/new-episodes'),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Color(0xFFE50914),
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Text(
                unreadCount > 9 ? '9+' : unreadCount.toString(),
                style: const TextStyle(
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
}
