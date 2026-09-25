import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nivio/providers/home_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/providers_data.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/auth_provider.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/widgets/content_row.dart';
import 'package:nivio/widgets/skeleton.dart';
import 'package:nivio/widgets/search_result_card.dart';
import 'package:nivio/models/search_result.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class ProviderContentScreen extends ConsumerStatefulWidget {
  final int providerId;
  final String providerName;

  const ProviderContentScreen({
    super.key,
    required this.providerId,
    required this.providerName,
  });

  @override
  ConsumerState<ProviderContentScreen> createState() => _ProviderContentScreenState();
}

class _ProviderContentScreenState extends ConsumerState<ProviderContentScreen> {
  bool _isLoading = true;
  String _mediaType = 'tv'; // 'tv' or 'movie'
  
  static const Map<int, String> _genreMap = {
    16: 'Animation', 28: 'Action', 12: 'Adventure', 14: 'Fantasy', 
    35: 'Comedy', 18: 'Drama', 9648: 'Mystery', 878: 'Sci-Fi', 
    80: 'Crime', 10759: 'Action', 10765: 'Fantasy', 10749: 'Romance',
    53: 'Thriller', 27: 'Horror', 99: 'Documentary', 10402: 'Music',
    10751: 'Family', 36: 'History', 10752: 'War', 37: 'Western',
  };

  List<dynamic> _trending = [];
  List<dynamic> _genre1 = [];
  List<dynamic> _genre2 = [];
  List<dynamic> _genre3 = [];
  List<dynamic> _genre4 = [];

  late final PageController _pageController;
  int _currentBannerPage = 0;
  Timer? _bannerTimer;
  
  final Map<int, Color> _ambientColors = {};
  Color _currentAmbientColor = const Color(0xFF0D0F14);

  bool _isSearching = false;
  String _searchQuery = '';
  List<SearchResult> _searchResults = [];
  bool _isSearchLoading = false;
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  final ScrollController _scrollController = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    _pageController = PageController(viewportFraction: isDesktop ? 1.0 : 0.92);
    _fetchContent();

    _scrollController.addListener(() {
      final scrolled = _scrollController.offset > 20;
      if (scrolled != _scrolled) {
        setState(() {
          _scrolled = scrolled;
        });
      }
    });

    _bannerTimer = Timer.periodic(const Duration(seconds: 14), (timer) {
      if (!_pageController.hasClients) return;
      if (_trending.isEmpty) return;
      final maxPages = _trending.take(5).length;
      if (maxPages == 0) return;
      
      int nextPage = _currentBannerPage + 1;
      if (nextPage >= maxPages) nextPage = 0;

      _pageController.jumpToPage(nextPage);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _bannerTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchQuery = '';
        _searchResults.clear();
        _searchController.clear();
      } else {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });

    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _searchResults.clear();
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 700), () {
      _performDeepSearch(query);
    });
  }

  Future<void> _performDeepSearch(String query) async {
    setState(() {
      _isSearchLoading = true;
    });

    final tmdbService = ref.read(tmdbServiceProvider);
    final results = await tmdbService.searchByProvider(query, widget.providerId, _mediaType);

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearchLoading = false;
      });
    }
  }

  Future<void> _fetchContent() async {
    setState(() {
      _isLoading = true;
    });

    final tmdbService = ref.read(tmdbServiceProvider);
    
    try {
      // 1. Fetch Trending/Popular for this provider
      final trending = await tmdbService.getByProvider(widget.providerId, mediaType: _mediaType);
      
      // 2. Fetch Genres based on media type
      List<dynamic> g1 = [];
      List<dynamic> g2 = [];
      List<dynamic> g3 = [];
      List<dynamic> g4 = [];

      if (_mediaType == 'movie') {
        // Action(28), Romance(10749), Comedy(35), Animation(16)
        final results = await Future.wait([
          tmdbService.getByProviderAndGenre(widget.providerId, 28, mediaType: 'movie'),
          tmdbService.getByProviderAndGenre(widget.providerId, 10749, mediaType: 'movie'),
          tmdbService.getByProviderAndGenre(widget.providerId, 35, mediaType: 'movie'),
          tmdbService.getByProviderAndGenre(widget.providerId, 16, mediaType: 'movie'),
        ]);
        g1 = results[0]; g2 = results[1]; g3 = results[2]; g4 = results[3];
      } else {
        // Action/Adv(10759), Drama(18), Sci-Fi(10765), Animation(16)
        final results = await Future.wait([
          tmdbService.getByProviderAndGenre(widget.providerId, 10759, mediaType: 'tv'),
          tmdbService.getByProviderAndGenre(widget.providerId, 18, mediaType: 'tv'),
          tmdbService.getByProviderAndGenre(widget.providerId, 10765, mediaType: 'tv'),
          tmdbService.getByProviderAndGenre(widget.providerId, 16, mediaType: 'tv'),
        ]);
        g1 = results[0]; g2 = results[1]; g3 = results[2]; g4 = results[3];
      }

      // Add media_type to all items
      void addType(List<dynamic> list) {
        for (var item in list) {
          if (item is Map) item['media_type'] = _mediaType;
        }
      }
      
      addType(trending);
      addType(g1); addType(g2); addType(g3); addType(g4);

      if (mounted) {
        setState(() {
          _trending = trending;
          _genre1 = g1;
          _genre2 = g2;
          _genre3 = g3;
          _genre4 = g4;
          _isLoading = false;
        });
        
        // Extract color for the first item
        _extractColorForIndex(0);
        _extractColorForIndex(1); // Pre-fetch next

        // Fetch TMDB clear logos for top hero items
        Future.wait(_trending.take(5).map((item) async {
          if (item is Map) {
            final tmdbId = item['id'] as int?;
            if (tmdbId != null) {
              final logo = await tmdbService.getMediaLogo(tmdbId, _mediaType);
              if (logo != null) {
                item['logo_url'] = logo;
              }
            }
          }
        })).then((_) {
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _extractColorForIndex(int index) async {
    if (_trending.isEmpty || index >= _trending.length) return;
    final item = _trending[index];
    final posterPath = item['poster_path'];
    if (posterPath == null) return;
    
    if (_ambientColors.containsKey(index)) return;
    
    try {
      final url = '$tmdbImageBaseUrl/w200$posterPath';
      final colorScheme = await ColorScheme.fromImageProvider(
        provider: NetworkImage(url),
        brightness: Brightness.dark,
      );
      final color = colorScheme.primary;
      
      if (mounted) {
        setState(() {
          _ambientColors[index] = color;
          if (_currentBannerPage == index) {
            _currentAmbientColor = color;
            ref.read(ambientColorProvider.notifier).state = color;
          }
        });
      }
    } catch (_) {}
  }

  String? _getProviderLogo() {
    for (var provider in allProviders) {
      if (provider['id'] == widget.providerId) {
        return provider['logo_path'] as String?;
      }
    }
    return null;
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

  List<Widget> _buildDesktopBadges({
    required String mediaType,
    required String year,
    required String language,
    double? voteAverage,
    required Color themeColor,
  }) {
    final widgets = <Widget>[];

    if (mediaType.isNotEmpty) {
      widgets.add(_buildBadge(mediaType, themeColor));
    }
    if (year.isNotEmpty) {
      widgets.add(_buildBadge(year, themeColor));
    }
    if (language.isNotEmpty) {
      widgets.add(_buildBadge(language, themeColor));
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

  Future<void> _toggleWatchlist(Map<String, dynamic> item) async {
    final tmdbId = item['id'] as int?;
    if (tmdbId == null) return;
    final service = ref.read(watchlistServiceProvider);
    final inWatchlist = ref.read(isInWatchlistProvider(tmdbId));

    if (inWatchlist) {
      await service.removeFromWatchlist(tmdbId);
    } else {
      final title = item['title'] ?? item['name'] ?? 'Unknown';
      final posterPath = item['poster_path'] as String?;
      final backdropPath = item['backdrop_path'] as String?;
      await service.addToWatchlist(
        WatchlistItem(
          id: tmdbId,
          title: title,
          posterPath: posterPath ?? backdropPath,
          mediaType: _mediaType,
          addedAt: DateTime.now(),
          voteAverage: (item['vote_average'] as num?)?.toDouble(),
          releaseDate: item['release_date'] as String? ?? item['first_air_date'] as String?,
          overview: item['overview'] as String?,
        ),
      );
    }
    ref.read(watchlistRefreshProvider.notifier).refresh();
  }

@override
  Widget build(BuildContext context) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    if (isDesktop) return _buildDesktopLayout(context);
    return _buildMobileLayout(context);
  }

  Widget _buildFeaturedBanner() {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    if (isDesktop) return _buildDesktopFeaturedBanner();
    return _buildMobileFeaturedBanner();
  }

  Widget _buildMobileLayout(BuildContext context) {
    final logoPath = _getProviderLogo();

    return PopScope(
      canPop: !_isSearching,
      onPopInvoked: (didPop) {
        if (!didPop && _isSearching) {
          _toggleSearch();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0F14),
        body: _isLoading
            ? const PosterGridSkeleton(
                padding: EdgeInsets.fromLTRB(16, 80, 16, 16),
              )
            : Stack(
                children: [
                  // --- Base Layer (Main Content) ---
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeInOut,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _currentAmbientColor.withOpacity(0.6),
                          _currentAmbientColor.withOpacity(0.15),
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                    child: CustomScrollView(
                      slivers: [
                        // Minimal Header
                        SliverAppBar(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          pinned: true,
                          leadingWidth: 240,
                          leading: GestureDetector(
                            onTap: () => context.pop(),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 24.0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: logoPath != null 
                                  ? CachedNetworkImage(
                                      imageUrl: '$tmdbImageBaseUrl/w300$logoPath',
                                      height: 56,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.centerLeft,
                                      colorBlendMode: BlendMode.dst,
                                    )
                                  : Text(
                                      widget.providerName,
                                      style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 32, letterSpacing: -0.5),
                                    ),
                              ),
                            ),
                          ),
                          actions: [
                            IconButton(
                              icon: const PhosphorIcon(PhosphorIconsRegular.magnifyingGlass, color: Colors.white),
                              onPressed: _toggleSearch,
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                        
                        // Filter Chips
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 24.0),
                            child: Row(
                              children: [
                                _buildTab('TV Shows', 'tv'),
                                const SizedBox(width: 12),
                                _buildTab('Movies', 'movie'),
                              ],
                            ),
                          ),
                        ),

                        // Featured Banner
                        if (_trending.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _buildFeaturedBanner(),
                          ),

                        const SliverToBoxAdapter(child: SizedBox(height: 20)),

                        // Horizontal Rows
                        if (_trending.length > 5)
                          SliverToBoxAdapter(
                            child: ContentRow(
                              title: 'Top 10 ${_mediaType == 'movie' ? 'Movies' : 'Shows'} in ${widget.providerName}',
                              items: _trending.skip(5).toList(),
                            ),
                          ),
                          
                        SliverToBoxAdapter(
                          child: ContentRow(
                            title: _mediaType == 'movie' ? 'Action & Thrillers' : 'Action & Adventure',
                            items: _genre1,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: ContentRow(
                            title: _mediaType == 'movie' ? 'Romance Movies' : 'Drama',
                            items: _genre2,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: ContentRow(
                            title: _mediaType == 'movie' ? 'Comedy Movies' : 'Sci-Fi & Fantasy',
                            items: _genre3,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: ContentRow(
                            title: 'Animation',
                            items: _genre4,
                          ),
                        ),
                        
                        const SliverToBoxAdapter(child: SizedBox(height: 40)),
                      ],
                    ),
                  ),

                  // --- Search Overlay Layer ---
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_isSearching,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _isSearching
                            ? ClipRect(
                                key: const ValueKey('search_layer'),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                                  child: Container(
                                    color: const Color(0xFF0D0F14).withOpacity(0.65),
                                    child: SafeArea(
                                      child: CustomScrollView(
                                        slivers: [
                                          SliverAppBar(
                                            backgroundColor: Colors.transparent,
                                            elevation: 0,
                                            pinned: true,
                                            leading: IconButton(
                                              icon: const PhosphorIcon(PhosphorIconsRegular.caretLeft, color: Colors.white),
                                              onPressed: _toggleSearch,
                                            ),
                                            title: TextField(
                                              controller: _searchController,
                                              focusNode: _searchFocusNode,
                                              style: const TextStyle(color: Colors.white),
                                              decoration: InputDecoration(
                                                hintText: 'Search ${_mediaType == 'movie' ? 'Movies' : 'TV Shows'}...',
                                                hintStyle: const TextStyle(color: Colors.white54),
                                                border: InputBorder.none,
                                              ),
                                              onChanged: _onSearchChanged,
                                            ),
                                          ),
                                          if (_isSearchLoading)
                                            SliverFillRemaining(
                                              child: Center(child: CircularProgressIndicator(color: NivioTheme.accentColorOf(context))),
                                            )
                                          else if (_searchResults.isEmpty && _searchQuery.isNotEmpty)
                                            const SliverFillRemaining(
                                              child: Center(child: Text('No results found.', style: TextStyle(color: Colors.white70))),
                                            )
                                          else if (_searchResults.isNotEmpty)
                                            SliverPadding(
                                              padding: const EdgeInsets.all(16),
                                              sliver: SliverGrid(
                                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 2,
                                                  childAspectRatio: 0.68,
                                                  crossAxisSpacing: 16,
                                                  mainAxisSpacing: 16,
                                                ),
                                                delegate: SliverChildBuilderDelegate(
                                                  (context, index) {
                                                    return SearchResultCard(media: _searchResults[index]);
                                                  },
                                                  childCount: _searchResults.length,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('empty_layer')),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }


  Widget _buildMobileFeaturedBanner() {
    final bannerItems = _trending.take(5).toList();
    if (bannerItems.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 480,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentBannerPage = index;
                if (_ambientColors.containsKey(index)) {
                  _currentAmbientColor = _ambientColors[index]!;
                }
              });
              _extractColorForIndex(index + 1);
            },
            itemCount: bannerItems.length,
            itemBuilder: (context, index) {
              final item = bannerItems[index];
              final posterPath = item['poster_path'] as String?;
              final title = item['title'] ?? item['name'] ?? 'Unknown';
              final tmdbId = item['id'] as int;
              
              final rawGenres = item['genre_ids'] as List<dynamic>? ?? [];
              final genreNames = rawGenres
                  .take(4)
                  .map((id) => _genreMap[id])
                  .where((name) => name != null)
                  .join(' • ');

              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double value = 1.0;
                  if (_pageController.position.haveDimensions) {
                    value = _pageController.page! - index;
                    value = (1 - (value.abs() * 0.15)).clamp(0.0, 1.0);
                  }
                  return Transform.scale(
                    scale: value,
                    child: Opacity(
                      opacity: value.clamp(0.4, 1.0),
                      child: child,
                    ),
                  );
                },
                child: GestureDetector(
                  onTap: () {
                    context.push('/media/$tmdbId?type=$_mediaType');
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                    // Large Poster Image
                    if (posterPath != null)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                            width: 2.0,
                          ),
                          image: DecorationImage(
                            image: CachedNetworkImageProvider('$tmdbImageBaseUrl/w500$posterPath'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                    else
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E24),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.movie, size: 64, color: Colors.white30),
                      ),
                      
                    // Gradient Overlay to make text readable
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black54,
                            Colors.black87,
                          ],
                          stops: [0.0, 0.5, 0.8, 1.0],
                        ),
                      ),
                    ),
                    
                    // Content Details & Buttons
                    Positioned(
                      bottom: 24,
                      left: 32,
                      right: 32,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (item['logo_url'] != null)
                            CachedNetworkImage(
                              imageUrl: '$tmdbImageBaseUrl/w500${item['logo_url']}',
                              height: 80,
                              fit: BoxFit.contain,
                              alignment: Alignment.bottomCenter,
                            )
                          else
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                shadows: [Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))],
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (genreNames.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              genreNames,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    context.push('/player/$tmdbId?type=$_mediaType');
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _currentAmbientColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.play_arrow_rounded, size: 28, color: Colors.white),
                                  label: const Text('Play', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Consumer(
                                  builder: (context, ref, child) {
                                    final inWatchlist = ref.watch(isInWatchlistProvider(tmdbId));
                                    return ElevatedButton.icon(
                                      onPressed: () async {
                                        if (inWatchlist) {
                                          await ref.read(watchlistServiceProvider).removeFromWatchlist(tmdbId);
                                        } else {
                                          await ref.read(watchlistServiceProvider).addToWatchlist(
                                            WatchlistItem(
                                              id: tmdbId,
                                              title: title,
                                              posterPath: posterPath,
                                              mediaType: _mediaType,
                                              addedAt: DateTime.now(),
                                              voteAverage: (item['vote_average'] as num?)?.toDouble(),
                                              releaseDate: item['release_date'] as String? ?? item['first_air_date'] as String?,
                                              overview: item['overview'] as String?,
                                            )
                                          );
                                        }
                                        ref.read(watchlistRefreshProvider.notifier).refresh();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _currentAmbientColor.withOpacity(0.35),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      icon: Icon(inWatchlist ? Icons.check : Icons.add, size: 24, color: Colors.white),
                                      label: const Text('MyList', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                    );
                                  }
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ), // End of GestureDetector
            ); // End of AnimatedBuilder
            },
          ),
        ),
        
        const SizedBox(height: 12),
        // Page Indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(bannerItems.length, (index) {
            final isActive = _currentBannerPage == index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 6,
              width: isActive ? 16 : 6,
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.white30,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }


  Widget _buildDesktopLayout(BuildContext context) {
    final logoPath = _getProviderLogo();
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final activeBgColor = Color.lerp(const Color(0xFF0D0F14), _currentAmbientColor, 0.15)!;

    return PopScope(
      canPop: !_isSearching,
      onPopInvoked: (didPop) {
        if (!didPop && _isSearching) {
          _toggleSearch();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0F14),
        body: _isLoading
            ? const PosterGridSkeleton(
                padding: EdgeInsets.fromLTRB(16, 80, 16, 16),
              )
            : Stack(
                children: [
                  // --- 1. Base Ambient Background Layer ---
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          color: activeBgColor,
                        ),
                      ),
                    ),
                  ),

                  // --- 2. Main Scrollable Content starting at top 0 ---
                  Positioned.fill(
                    child: AppCustomScrollView(
                      controller: _scrollController,
                      cacheExtent: 250,
                      scrollSpeed: 2.0,
                      silkyScrollDuration: const Duration(milliseconds: 500),
                      animationCurve: Curves.easeOutQuart,
                      slivers: [
                        // Hero Banner at top (0 gap)
                        if (_trending.isNotEmpty)
                          SliverToBoxAdapter(
                            child: _buildFeaturedBanner(),
                          ),

                        const SliverToBoxAdapter(child: SizedBox(height: 20)),

                        // Horizontal Content Rows
                        if (_trending.length > 5)
                          SliverToBoxAdapter(
                            child: ContentRow(
                              title: 'Top 10 ${_mediaType == 'movie' ? 'Movies' : 'Shows'} in ${widget.providerName}',
                              items: _trending.skip(5).toList(),
                              leftPadding: isDesktop ? 80 : 16,
                            ),
                          ),

                        SliverToBoxAdapter(
                          child: ContentRow(
                            title: _mediaType == 'movie' ? 'Action & Thrillers' : 'Action & Adventure',
                            items: _genre1,
                            leftPadding: isDesktop ? 80 : 16,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: ContentRow(
                            title: _mediaType == 'movie' ? 'Romance Movies' : 'Drama',
                            items: _genre2,
                            leftPadding: isDesktop ? 80 : 16,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: ContentRow(
                            title: _mediaType == 'movie' ? 'Comedy Movies' : 'Sci-Fi & Fantasy',
                            items: _genre3,
                            leftPadding: isDesktop ? 80 : 16,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: ContentRow(
                            title: 'Animation',
                            items: _genre4,
                            leftPadding: isDesktop ? 80 : 16,
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 40)),
                      ],
                    ),
                  ),

                  // --- 3. Floating Header Controls Overlay ---
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Container(
                        padding: EdgeInsets.only(
                          top: isDesktop ? 16 : 8,
                          left: isDesktop ? 68 : 12,
                          right: 16,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Left Controls: Back button + Provider Logo + Category Bubbles
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                                  onPressed: () => context.pop(),
                                ),
                                const SizedBox(width: 4),
                                if (logoPath != null)
                                  CachedNetworkImage(
                                    imageUrl: '$tmdbImageBaseUrl/w300$logoPath',
                                    height: isDesktop ? 36 : 30,
                                    fit: BoxFit.contain,
                                  )
                                else
                                  Text(
                                    widget.providerName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      fontSize: 22,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                const SizedBox(width: 16),
                                _buildTab('TV Shows', 'tv'),
                                const SizedBox(width: 10),
                                _buildTab('Movies', 'movie'),
                              ],
                            ),
                            // Right Control: Search Icon padded down to avoid desktop title bar overlap
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: IconButton(
                                icon: const PhosphorIcon(PhosphorIconsRegular.magnifyingGlass, color: Colors.white, size: 22),
                                onPressed: _toggleSearch,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // --- 4. Search Overlay Layer ---
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_isSearching,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _isSearching
                            ? ClipRect(
                                key: const ValueKey('search_layer'),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                                  child: Container(
                                    color: const Color(0xFF0D0F14).withOpacity(0.65),
                                    margin: EdgeInsets.only(left: isDesktop ? 56 : 0),
                                    child: SafeArea(
                                      child: CustomScrollView(
                                        slivers: [
                                          SliverAppBar(
                                            backgroundColor: Colors.transparent,
                                            elevation: 0,
                                            pinned: true,
                                            leading: IconButton(
                                              icon: const PhosphorIcon(PhosphorIconsRegular.caretLeft, color: Colors.white),
                                              onPressed: _toggleSearch,
                                            ),
                                            title: TextField(
                                              controller: _searchController,
                                              focusNode: _searchFocusNode,
                                              style: const TextStyle(color: Colors.white),
                                              decoration: InputDecoration(
                                                hintText: 'Search ${_mediaType == 'movie' ? 'Movies' : 'TV Shows'}...',
                                                hintStyle: const TextStyle(color: Colors.white54),
                                                border: InputBorder.none,
                                              ),
                                              onChanged: _onSearchChanged,
                                            ),
                                          ),
                                          if (_isSearchLoading)
                                            SliverFillRemaining(
                                              child: Center(child: CircularProgressIndicator(color: NivioTheme.accentColorOf(context))),
                                            )
                                          else if (_searchResults.isEmpty && _searchQuery.isNotEmpty)
                                            const SliverFillRemaining(
                                              child: Center(child: Text('No results found.', style: TextStyle(color: Colors.white70))),
                                            )
                                          else if (_searchResults.isNotEmpty)
                                            SliverPadding(
                                              padding: const EdgeInsets.all(16),
                                              sliver: SliverGrid(
                                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 2,
                                                  childAspectRatio: 0.68,
                                                  crossAxisSpacing: 16,
                                                  mainAxisSpacing: 16,
                                                ),
                                                delegate: SliverChildBuilderDelegate(
                                                  (context, index) {
                                                    return SearchResultCard(media: _searchResults[index]);
                                                  },
                                                  childCount: _searchResults.length,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(key: ValueKey('empty_layer')),
                      ),
                    ),
                  ),
                  if (isDesktop)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 56,
                      child: _buildMediaSidebar(context),
                    ),
                ],
              ),
      ),
    );
  }


  Widget _buildDesktopFeaturedBanner() {
    final bannerItems = _trending.take(5).toList();
    if (bannerItems.isEmpty) return const SizedBox.shrink();
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final bannerHeight = isDesktop ? MediaQuery.sizeOf(context).height * 0.8 : 600.0;
    final watchlistIds = ref.watch(watchlistProvider).map((item) => item.id).toSet();

    final activeBgColor = Color.lerp(const Color(0xFF0D0F14), _currentAmbientColor, 0.15)!;
    final slideColor = _ambientColors[_currentBannerPage] ?? NivioTheme.accentColorOf(context);

    return SizedBox(
      height: bannerHeight,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentBannerPage = index;
            if (_ambientColors.containsKey(index)) {
              _currentAmbientColor = _ambientColors[index]!;
              ref.read(ambientColorProvider.notifier).state = _currentAmbientColor;
            }
          });
          _extractColorForIndex(index + 1);
        },
        itemCount: bannerItems.length,
        itemBuilder: (context, index) {
          final item = bannerItems[index];
          final tmdbId = item['id'] as int? ?? 0;
          final posterPath = item['poster_path'] as String?;
          final backdropPath = item['backdrop_path'] as String?;
          final imagePath = isDesktop ? (backdropPath ?? posterPath) : posterPath;
          final title = item['title'] ?? item['name'] ?? 'Featured';
          final logoUrl = item['logo_url'] as String?;
          final overview = item['overview'] as String? ?? '';
          final voteAverage = (item['vote_average'] as num?)?.toDouble();
          final rawGenres = item['genre_ids'] as List<dynamic>? ?? [];
          final genres = rawGenres
              .take(4)
              .map((id) => _genreMap[id])
              .where((name) => name != null)
              .cast<String>()
              .toList();

          final releaseDate = item['release_date'] as String? ?? item['first_air_date'] as String? ?? '';
          final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';
          final lang = (item['original_language'] as String? ?? '').toUpperCase();

          final desktopBadges = _buildDesktopBadges(
            mediaType: _mediaType.toUpperCase(),
            year: year,
            language: lang.isNotEmpty ? lang : 'HD',
            voteAverage: voteAverage,
            themeColor: slideColor,
          );

          final backdropUrl = imagePath != null
              ? (imagePath.startsWith('http')
                  ? imagePath
                  : '$tmdbImageBaseUrl/${isDesktop ? 'original' : 'w500'}$imagePath')
              : null;

          final isInWatchlist = tmdbId != 0 && watchlistIds.contains(tmdbId);

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Backdrop / Poster Image
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
              // 2. Vignette Asset Overlay
              Positioned.fill(
                child: Image.asset(
                  'assets/images/vignette.png',
                  fit: BoxFit.fill,
                ),
              ),
              // 3. Bottom Gradient Fade matching HomeScreen
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
              // 4. Content Details & Buttons
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
                                    onTap: () => context.push('/media/$tmdbId?type=$_mediaType'),
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
                                    onTap: () => context.push('/media/$tmdbId?type=$_mediaType'),
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: _buildTitleText(title),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: desktopBadges,
                                ),
                                const SizedBox(height: 28),
                                Row(
                                  children: [
                                    _AnimatedHoverScale(
                                      child: ElevatedButton.icon(
                                        onPressed: () => context.push('/player/$tmdbId?type=$_mediaType'),
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
                                      onTap: () => _toggleWatchlist(item),
                                    ),
                                    const SizedBox(width: 12),
                                    _desktopOutlineButton(
                                      icon: PhosphorIcon(
                                        isInWatchlist ? PhosphorIconsFill.bookmarkSimple : PhosphorIconsRegular.bookmarkSimple,
                                        color: isInWatchlist ? slideColor : Colors.white,
                                        size: 18,
                                      ),
                                      onTap: () => _toggleWatchlist(item),
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
                                  overview,
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
                          Text(
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
                          const SizedBox(height: 8),
                          if (genres.isNotEmpty)
                            Text(
                              genres.join(' • '),
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _AnimatedHoverScale(
                                child: ElevatedButton.icon(
                                  onPressed: () => context.push('/player/$tmdbId?type=$_mediaType'),
                                  icon: const PhosphorIcon(
                                    PhosphorIconsFill.play,
                                    color: Colors.black,
                                    size: 16,
                                  ),
                                  label: const Text('Play'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _desktopOutlineButton(
                                icon: PhosphorIcon(
                                  isInWatchlist ? PhosphorIconsFill.checkCircle : PhosphorIconsRegular.plus,
                                  color: isInWatchlist ? slideColor : Colors.white,
                                  size: 18,
                                ),
                                onTap: () => _toggleWatchlist(item),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              // 5. Slide Indicator Dots at Bottom Center
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    bannerItems.length,
                    (dotIndex) {
                      return _AnimatedProgressBarDot(
                        isActive: _currentBannerPage == dotIndex,
                        activeColor: slideColor,
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


  Widget _buildTab(String title, String type) {
    final isSelected = _mediaType == type;
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    
    Widget child = GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() {
            _mediaType = type;
            _currentBannerPage = 0;
            _pageController.jumpToPage(0);
          });
          _fetchContent();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isDesktop
              ? (isSelected ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.3))
              : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white24,
            width: isDesktop ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: isDesktop ? 13.5 : null,
            fontWeight: isSelected ? FontWeight.bold : (isDesktop ? FontWeight.w600 : FontWeight.normal),
            letterSpacing: isDesktop ? 0.3 : null,
          ),
        ),
      ),
    );

    if (isDesktop) {
      return _AnimatedHoverScale(child: child);
    }
    return child;
  }

  Widget _buildMediaSidebar(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.valueOrNull;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: 56,
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          Image.asset(
            'assets/images/nivio.png',
            width: 48,
            height: 48,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              children: [
                _buildSidebarItem(
                  context: context,
                  route: '/home',
                  icon: PhosphorIconsRegular.house,
                  activeIcon: PhosphorIconsFill.house,
                  label: 'Home',
                  isActive: false,
                ),
                const SizedBox(height: 8),
                _buildSidebarItem(
                  context: context,
                  route: '/search',
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  activeIcon: PhosphorIconsFill.magnifyingGlass,
                  label: 'Search',
                  isActive: false,
                ),
                const SizedBox(height: 8),
                _buildSidebarItem(
                  context: context,
                  route: '/library',
                  icon: PhosphorIconsRegular.calendarBlank,
                  activeIcon: PhosphorIconsFill.calendarCheck,
                  label: 'Library',
                  isActive: false,
                ),
                const SizedBox(height: 8),
                _buildSidebarItem(
                  context: context,
                  route: '/iptv',
                  icon: PhosphorIconsRegular.television,
                  activeIcon: PhosphorIconsFill.television,
                  label: 'Live TV',
                  isActive: false,
                ),
                const SizedBox(height: 8),
                _buildSidebarItem(
                  context: context,
                  route: '/party',
                  icon: PhosphorIconsRegular.users,
                  activeIcon: PhosphorIconsFill.users,
                  label: 'Party',
                  isActive: false,
                ),
              ],
            ),
          ),
          _buildSidebarItem(
            context: context,
            route: '/profile',
            icon: PhosphorIconsRegular.user,
            activeIcon: PhosphorIconsFill.user,
            label: 'Profile',
            isActive: false,
            photoUrl: user?.photoURL,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
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
          context.go(route);
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
    );
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
        scale: _isHovered ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

class _AnimatedProgressBarDot extends StatelessWidget {
  final bool isActive;
  final Color activeColor;

  const _AnimatedProgressBarDot({
    required this.isActive,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: isActive ? 24 : 12,
        height: 3,
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.white24,
          borderRadius: BorderRadius.circular(2),
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
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: AnimatedScale(
            scale: _isHovered ? 1.25 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutBack,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
