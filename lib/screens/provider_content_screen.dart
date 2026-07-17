import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:nivio/providers/dynamic_colors_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:silky_scroll/silky_scroll.dart';
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
  double _currentPageValue = 0.0;
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
    _pageController = PageController(viewportFraction: isDesktop ? 1.0 : 0.85);
    _fetchContent();
    _pageController.addListener(() {
      if (mounted) {
        setState(() {
          _currentPageValue = _pageController.page ?? 0.0;
        });
      }
    });

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
      final cacheManager = DefaultCacheManager();
      final fileInfo = await cacheManager.getFileFromCache(url);
      Uint8List bytes;
      if (fileInfo != null) {
        bytes = await fileInfo.file.readAsBytes();
      } else {
        final file = await cacheManager.getSingleFile(url);
        bytes = await file.readAsBytes();
      }

      final seedColorValue = await compute(extractSeedColor, bytes);
      final colorScheme = ColorScheme.fromSeed(
        seedColor: Color(seedColorValue),
        brightness: Brightness.dark,
      );
      final color = colorScheme.primary;
      
      if (mounted) {
        setState(() {
          _ambientColors[index] = color;
          if (_currentBannerPage == index) {
            _currentAmbientColor = color;
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

  @override
  Widget build(BuildContext context) {
    final logoPath = _getProviderLogo();
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

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
            ? Center(
                child: CircularProgressIndicator(color: NivioTheme.accentColorOf(context)),
              )
            : Stack(
                children: [
                  // --- Base Layer (Main Content) ---
                  Positioned.fill(
                    child: AnimatedContainer(
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
                    ),
                  ),
                  Positioned.fill(
                    child: SilkyCustomScrollView(
                      controller: _scrollController,
                      cacheExtent: 250,
                      scrollSpeed: 2.0,
                      silkyScrollDuration: const Duration(milliseconds: 500),
                      animationCurve: Curves.easeOutQuart,
                      slivers: [
                        // Minimal Header
                        SliverAppBar(
                          automaticallyImplyLeading: false,
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          pinned: true,
                          centerTitle: !isDesktop,
                          leadingWidth: isDesktop ? 68 : null,
                          leading: isDesktop
                            ? const SizedBox(width: 68)
                            : IconButton(
                                icon: const Icon(Icons.arrow_back, color: Colors.white),
                                onPressed: () => context.pop(),
                              ),
                          title: isDesktop 
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildTab('TV Shows', 'tv'),
                                  const SizedBox(width: 12),
                                  _buildTab('Movies', 'movie'),
                                ],
                              )
                            : (logoPath != null 
                                ? CachedNetworkImage(
                                    imageUrl: '$tmdbImageBaseUrl/w300$logoPath',
                                    height: 40,
                                    fit: BoxFit.contain,
                                  )
                                : Text(
                                    widget.providerName,
                                    style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 24, letterSpacing: -0.5),
                                  )),
                          actions: [
                            if (isDesktop) ...[
                              Padding(
                                padding: const EdgeInsets.only(right: 16.0),
                                child: Center(
                                  child: logoPath != null 
                                    ? CachedNetworkImage(
                                        imageUrl: '$tmdbImageBaseUrl/w300$logoPath',
                                        height: 32,
                                        fit: BoxFit.contain,
                                      )
                                    : Text(
                                        widget.providerName,
                                        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 20, letterSpacing: -0.5),
                                      ),
                                ),
                              ),
                            ],
                            IconButton(
                              icon: const PhosphorIcon(PhosphorIconsRegular.magnifyingGlass, color: Colors.white),
                              onPressed: _toggleSearch,
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                        
                        // Filter Chips
                        if (!isDesktop)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 24.0, bottom: 24.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
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
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: _scrolled ? 20 : 0,
                            sigmaY: _scrolled ? 20 : 0,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            decoration: BoxDecoration(
                              color: _scrolled
                                  ? _currentAmbientColor.withOpacity(0.2)
                                  : Colors.transparent,
                            ),
                            child: _buildMediaSidebar(context),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildFeaturedBanner() {
    final bannerItems = _trending.take(5).toList();
    if (bannerItems.isEmpty) return const SizedBox.shrink();
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final bannerHeight = isDesktop ? MediaQuery.sizeOf(context).height * 0.8 : 480.0;

    final bannerWidget = Column(
      children: [
        SizedBox(
          height: bannerHeight,
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
              final backdropPath = item['backdrop_path'] as String?;
              final imagePath = isDesktop ? (backdropPath ?? posterPath) : posterPath;
              final title = item['title'] ?? item['name'] ?? 'Unknown';
              final tmdbId = item['id'] as int;
              
              final rawGenres = item['genre_ids'] as List<dynamic>? ?? [];
              final genreNames = rawGenres
                  .take(4)
                  .map((id) => _genreMap[id])
                  .where((name) => name != null)
                  .join(' • ');

              final double value = isDesktop
                  ? 1.0
                  : (1.0 - ((_currentPageValue - index).abs() * 0.12)).clamp(0.88, 1.0);

              return Transform.scale(
                scale: value,
                child: GestureDetector(
                  onTap: () {
                    context.push('/media/$tmdbId?type=$_mediaType');
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Large Poster/Backdrop Image
                      if (imagePath != null)
                        Container(
                          margin: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 8),
                          decoration: BoxDecoration(
                            borderRadius: isDesktop ? BorderRadius.zero : BorderRadius.circular(16),
                            border: isDesktop
                                ? null
                                : Border.all(
                                    color: Colors.white.withOpacity(0.25),
                                    width: 2.0,
                                  ),
                            image: DecorationImage(
                              image: CachedNetworkImageProvider('$tmdbImageBaseUrl/${isDesktop ? 'original' : 'w500'}$imagePath'),
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      else
                        Container(
                          margin: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E24),
                            borderRadius: isDesktop ? BorderRadius.zero : BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.movie, size: 64, color: Colors.white30),
                        ),
                        
                      // Gradient Overlay to make text readable & fade into ambient color
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 8),
                        decoration: BoxDecoration(
                          borderRadius: isDesktop ? BorderRadius.zero : BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              _currentAmbientColor.withOpacity(0.5),
                              _currentAmbientColor,
                            ],
                            stops: const [0.0, 0.88, 1.0],
                          ),
                        ),
                      ),
                      
                      // Content Details & Buttons
                      Positioned(
                        bottom: isDesktop ? 60 : 24,
                        left: isDesktop ? 68 : 32,
                        right: isDesktop ? 48 : 32,
                        child: Column(
                          crossAxisAlignment: isDesktop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isDesktop ? 44 : 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                shadows: const [Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))],
                              ),
                              textAlign: isDesktop ? TextAlign.left : TextAlign.center,
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
                                textAlign: isDesktop ? TextAlign.left : TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: isDesktop ? MainAxisAlignment.start : MainAxisAlignment.center,
                              children: [
                                if (isDesktop) ...[
                                  SizedBox(
                                    width: 200,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        context.push('/player/$tmdbId?type=$_mediaType');
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        elevation: 0,
                                      ),
                                      icon: const Icon(Icons.play_arrow_rounded, size: 28, color: Colors.black87),
                                      label: const Text('Play', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 200,
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
                                            backgroundColor: Colors.white.withOpacity(0.15),
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
                                ] else ...[
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        context.push('/player/$tmdbId?type=$_mediaType');
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        elevation: 0,
                                      ),
                                      icon: const Icon(Icons.play_arrow_rounded, size: 28, color: Colors.black87),
                                      label: const Text('Play', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
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
                                            backgroundColor: Colors.white.withOpacity(0.15),
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
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
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

    return bannerWidget;
  }

  Widget _buildTab(String title, String type) {
    final isSelected = _mediaType == type;
    return GestureDetector(
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.15),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
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
    return Tooltip(
      message: label,
      child: Align(
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
            child: Center(
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
}
