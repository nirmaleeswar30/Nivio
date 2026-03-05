import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/providers/home_providers.dart';
import 'package:nivio/providers/language_preferences_provider.dart';
import 'package:nivio/providers/watch_history_provider.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/services/episode_check_service.dart';
import 'package:nivio/widgets/content_row.dart';
import 'package:nivio/widgets/continue_watching_row.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const Map<int, String> _genreMap = {
    16: 'Animation',
    28: 'Action',
    12: 'Adventure',
    14: 'Fantasy',
    35: 'Comedy',
    18: 'Drama',
    9648: 'Mystery',
    878: 'Sci-Fi',
    80: 'Crime',
    10759: 'Action',
    10765: 'Fantasy',
  };

  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();
  bool _showAppBarBackground = false;
  int _currentBannerIndex = 0;
  int _currentBannerPage = 0;
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

    _bannerTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (!_pageController.hasClients) return;
      final featuredContent = ref.read(featuredContentProvider).value ?? [];
      if (featuredContent.isEmpty) return;
      _pageController.animateToPage(
        _currentBannerPage + 1,
        duration: const Duration(milliseconds: 1200),
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

  @override
  void dispose() {
    _scrollController.dispose();
    _pageController.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final featuredContent = ref.watch(featuredContentProvider);
    final languagePreferences = ref.watch(languagePreferencesProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: _showAppBarBackground ? 12 : 0,
                sigmaY: _showAppBarBackground ? 12 : 0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: _showAppBarBackground
                      ? const Color(0x6A0D0F14)
                      : Colors.transparent,
                  border: _showAppBarBackground
                      ? const Border(
                          bottom: BorderSide(color: Color(0x22FFFFFF)),
                        )
                      : null,
                  gradient: _showAppBarBackground
                      ? null
                      : LinearGradient(
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
          title: const Padding(
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
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: IconButton(
                icon: const PhosphorIcon(
                  PhosphorIconsRegular.magnifyingGlass,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: () => context.go('/search'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildNotificationBell(context),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildProfileButton(context),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        cacheExtent: 1000,
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
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF141414), Color(0xFF0D0F14)],
                ),
              ),
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
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, child) {
                final continueWatching = ref.watch(continueWatchingProvider);
                return continueWatching.when(
                  data: (items) {
                    if (items.length <= 1) return const SizedBox.shrink();
                    return const Padding(
                      padding: EdgeInsets.only(top: 0, left: 16, right: 16),
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
          _buildRowSection('All Time Popular', popularMoviesProvider),
          _buildRowSection('Trending Now', trendingMoviesProvider),
          _buildRowSection('Top Rated Movies', topRatedMoviesProvider),
          _buildRowSection('Popular TV Shows', popularTVShowsProvider),
          _buildRowSection('Trending TV Shows', trendingTVShowsProvider),
          if (languagePreferences.showAnime)
            _buildRowSection('Popular Anime', animeProvider),
          if (languagePreferences.showAnime)
            _buildRowSection('Trending Anime', trendingAnimeProvider),
          if (languagePreferences.showTamil)
            _buildRowSection('Tamil Picks', tamilMoviesProvider),
          if (languagePreferences.showTelugu)
            _buildRowSection('Telugu Picks', teluguMoviesProvider),
          if (languagePreferences.showHindi)
            _buildRowSection('Hindi Picks', hindiMoviesProvider),
          if (languagePreferences.showKorean)
            _buildRowSection('Korean Dramas', koreanDramasProvider),
          const SliverToBoxAdapter(child: SizedBox(height: 50)),
        ],
      ),
    );
  }

  Widget _buildRowSection(
    String title,
    FutureProvider<List<dynamic>> provider,
  ) {
    return SliverToBoxAdapter(
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

  Widget _buildHeroBannerCarousel(BuildContext context, List<dynamic> items) {
    if (items.isEmpty) return const SizedBox(height: 500);
    final itemCount = items.length + 1;

    return SizedBox(
      height: 600,
      child: PageView.builder(
        controller: _pageController,
        itemCount: itemCount,
        onPageChanged: (index) {
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
          });
        },
        itemBuilder: (context, index) {
          final content = items[index == items.length ? 0 : index];
          final tmdbId = content['id'];
          final mediaType =
              (content['media_type'] ??
                      (content['title'] != null ? 'movie' : 'tv'))
                  .toString();
          final title = (content['title'] ?? content['name'] ?? 'Featured')
              .toString();

          final backdropPath =
              (content['backdrop_path'] ?? content['poster_path'])?.toString();
          final backdropUrl = _tmdbImageUrl(backdropPath, backdropSize);
          final voteAverage = (content['vote_average'] as num?)?.toDouble();
          final year =
              ((content['first_air_date'] ?? content['release_date'])
                          ?.toString()
                          .split('-')
                          .first ??
                      '')
                  .trim();
          final genreIds = (content['genre_ids'] as List<dynamic>? ?? [])
              .whereType<num>()
              .map((genreId) => _genreMap[genreId.toInt()])
              .whereType<String>()
              .take(3)
              .toList();

          final meta = <String>[
            if (genreIds.isNotEmpty) genreIds.join(' / '),
            if (voteAverage != null && voteAverage > 0)
              voteAverage.toStringAsFixed(1),
            if (year.isNotEmpty) year,
          ];

          return Stack(
            children: [
              AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 500),
                child: Container(
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
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.5),
                      const Color(0xFF141414),
                    ],
                    stops: const [0.0, 0.7, 1.0],
                  ),
                ),
              ),
              Positioned(
                bottom: 76,
                left: 24,
                right: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedOpacity(
                      opacity: 1,
                      duration: const Duration(milliseconds: 500),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (meta.isNotEmpty)
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: _buildMetaChips(meta),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _smallSquareButton(
                          icon: const PhosphorIcon(
                            PhosphorIconsRegular.plus,
                            color: Colors.white,
                            size: 18,
                          ),
                          onTap: () => _addFeaturedToWatchlist(content),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: () =>
                              context.push('/media/$tmdbId?type=$mediaType'),
                          icon: const PhosphorIcon(
                            PhosphorIconsFill.play,
                            color: Colors.black,
                            size: 16,
                          ),
                          label: const Text('Play'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _smallSquareButton(
                          icon: const PhosphorIcon(
                            PhosphorIconsRegular.info,
                            color: Colors.white,
                            size: 18,
                          ),
                          onTap: () =>
                              context.push('/media/$tmdbId?type=$mediaType'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _currentBannerIndex == dotIndex ? 7 : 5,
                      height: _currentBannerIndex == dotIndex ? 7 : 5,
                      decoration: BoxDecoration(
                        color: _currentBannerIndex == dotIndex
                            ? NivioTheme.accentColorOf(context)
                            : Colors.white38,
                        shape: BoxShape.circle,
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
      child: Center(
        child: CircularProgressIndicator(
          color: NivioTheme.accentColorOf(context),
        ),
      ),
    );
  }

  Widget _buildProfileButton(BuildContext context) {
    return IconButton(
      icon: const PhosphorIcon(
        PhosphorIconsRegular.userCircle,
        color: Colors.white,
        size: 24,
      ),
      tooltip: 'Profile',
      onPressed: () => context.push('/profile'),
    );
  }

  Widget _buildNotificationBell(BuildContext context) {
    final unreadCount = EpisodeCheckService.getUnreadCount();

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

  Widget _smallSquareButton({
    required Widget icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0x30FFFFFF),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(width: 38, height: 38, child: Center(child: icon)),
      ),
    );
  }

  Future<void> _addFeaturedToWatchlist(Map<String, dynamic> content) async {
    final watchlistService = ref.read(watchlistServiceProvider);
    final mediaId = content['id'] as int?;
    if (mediaId == null) return;

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

    await watchlistService.addToWatchlist(item);
    ref.read(watchlistRefreshProvider.notifier).refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Added to watchlist')));
  }

  String? _tmdbImageUrl(String? path, String size) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$tmdbImageBaseUrl/$size$path';
  }
}
