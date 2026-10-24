import 'package:nivio/core/app_platform.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/screens/new_episodes_screen.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:nivio/widgets/latest_releases_shelf.dart';
import 'package:nivio/widgets/skeleton.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class LatestReleasesScreen extends ConsumerStatefulWidget {
  final String initialCategory;

  const LatestReleasesScreen({
    super.key,
    this.initialCategory = 'movie',
  });

  @override
  ConsumerState<LatestReleasesScreen> createState() => _LatestReleasesScreenState();
}

class _LatestReleasesScreenState extends ConsumerState<LatestReleasesScreen> {
  late final String _category;
  final ScrollController _scrollController = ScrollController();

  final List<dynamic> _items = [];
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isInitialLoading = false;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _category = _normalizeCategory(widget.initialCategory);
    _scrollController.addListener(_onScroll);
    _fetchInitialData();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  String _normalizeCategory(String cat) {
    final lower = cat.toLowerCase();
    if (lower.contains('tv') || lower.contains('show') || lower.contains('series')) {
      return 'tv';
    }
    if (lower.contains('anime')) {
      return 'anime';
    }
    return 'movie';
  }

  void _onScroll() {
    if (_isLoadingMore || _isInitialLoading || !_hasMore) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    if (currentScroll >= maxScroll - 400) {
      _loadMoreData();
    }
  }

  Future<void> _fetchInitialData() async {
    setState(() {
      _isInitialLoading = true;
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      List<dynamic> fetched = [];
      if (_category == 'movie') {
        final tmdb = ref.read(tmdbServiceProvider);
        fetched = await tmdb.getLatestMovieOTT(page: 1);
      } else if (_category == 'tv') {
        final tmdb = ref.read(tmdbServiceProvider);
        fetched = await tmdb.getLatestTvOTT(page: 1);
      } else if (_category == 'anime') {
        final anilist = ref.read(aniListServiceProvider);
        fetched = await anilist.getLatestAiringAnime();
      }

      fetched.sort(compareReleaseDates);

      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(fetched);
          _isInitialLoading = false;
          if (fetched.isEmpty || _category == 'anime') {
            _hasMore = false;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isInitialLoading = false);
      }
    }
  }

  Future<void> _loadMoreData() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    final nextPage = _currentPage + 1;

    try {
      List<dynamic> newItems = [];
      if (_category == 'movie') {
        final tmdb = ref.read(tmdbServiceProvider);
        newItems = await tmdb.getLatestMovieOTT(page: nextPage);
      } else if (_category == 'tv') {
        final tmdb = ref.read(tmdbServiceProvider);
        newItems = await tmdb.getLatestTvOTT(page: nextPage);
      }

      if (mounted) {
        setState(() {
          _currentPage = nextPage;
          if (newItems.isEmpty) {
            _hasMore = false;
          } else {
            final existingIds = _items.map((e) => e is Map ? e['id'] : null).toSet();
            final unique = newItems.where((e) {
              if (e is Map && e['id'] != null) {
                return !existingIds.contains(e['id']);
              }
              return true;
            }).toList();

            if (unique.isEmpty) {
              _hasMore = false;
            } else {
              _items.addAll(unique);
            }
          }
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  List<Color> get _categoryGradient {
    switch (_category) {
      case 'tv':
        return const [Color(0xFF8B5CF6), Color(0xFF6D28D9)];
      case 'anime':
        return const [Color(0xFF06B6D4), Color(0xFF0284C7)];
      case 'movie':
      default:
        return const [Color(0xFFF59E0B), Color(0xFFD97706)];
    }
  }

  String get _categoryTitle {
    switch (_category) {
      case 'tv':
        return 'Latest TV Releases';
      case 'anime':
        return 'Latest Anime Releases';
      case 'movie':
      default:
        return 'Latest OTT Releases';
    }
  }

  String get _categorySubtitle {
    switch (_category) {
      case 'tv':
        return 'New series & episodes streaming now';
      case 'anime':
        return 'Newly aired episodes in Japan';
      case 'movie':
      default:
        return 'Verified digital premieres & streaming drops';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = AppPlatform.useDesktopLayout;

    final scrollView = AppCustomScrollView(
      controller: _scrollController,
      cacheExtent: isDesktop ? 1200 : 400,
      scrollSpeed: 2.0,
      silkyScrollDuration: const Duration(milliseconds: 500),
      animationCurve: Curves.easeOutQuart,
      slivers: [
        // Top Header: Back button on Desktop only, glowing accent, title, and optional Schedule button
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 68 : 16,
              isDesktop ? 16 : 14,
              isDesktop ? 68 : 16,
              14,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Back button ONLY on desktop; removed on mobile as requested
                if (isDesktop) ...[
                  _DesktopBackButton(
                    onTap: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/home');
                      }
                    },
                  ),
                  const SizedBox(width: 14),
                ],

                // Accent bar
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _categoryGradient,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),

                        // Title and Subtitle
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _categoryTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isDesktop ? 22 : 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _categorySubtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: isDesktop ? 12.5 : 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Release Calendar action button for Anime
                        if (_category == 'anime')
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _DesktopScheduleButton(
                              accentColor: _categoryGradient.first,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const Scaffold(
                                      body: NewEpisodesScreen(embedded: false),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // Main Content Grid or Skeletons
                if (_isInitialLoading)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      isDesktop ? 68 : 14,
                      8,
                      isDesktop ? 68 : 14,
                      40,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: isDesktop ? 195 : 180,
                        childAspectRatio: 0.67,
                        crossAxisSpacing: isDesktop ? 14 : 10,
                        mainAxisSpacing: isDesktop ? 16 : 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF141720),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const SkeletonBox(
                                width: double.infinity,
                                height: double.infinity,
                                borderRadius: BorderRadius.zero,
                              ),
                              Positioned(
                                bottom: 10,
                                left: 8,
                                right: 8,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SkeletonBox(
                                      width: 105,
                                      height: 12,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    const SizedBox(height: 5),
                                    SkeletonBox(
                                      width: 60,
                                      height: 9,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        childCount: isDesktop ? 14 : 6,
                      ),
                    ),
                  )
                else if (_items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            PhosphorIconsRegular.filmStrip,
                            size: 46,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No releases found',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 14.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      isDesktop ? 68 : 14,
                      8,
                      isDesktop ? 68 : 14,
                      20,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: isDesktop ? 195 : 180,
                        childAspectRatio: 0.67,
                        crossAxisSpacing: isDesktop ? 14 : 10,
                        mainAxisSpacing: isDesktop ? 16 : 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = _items[index];
                          final id = item is Map ? item['id'] : (item is SearchResult ? item.id : index);
                          return _OptimizedReleaseCard(
                            key: ValueKey('rel_${_category}_${id}_$index'),
                            item: item,
                            isAnime: _category == 'anime',
                            accentGradient: _categoryGradient,
                          );
                        },
                        childCount: _items.length,
                        addRepaintBoundaries: true,
                      ),
                    ),
                  ),

                  // Loading More Spinner
                  if (_isLoadingMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: _categoryGradient.first,
                            ),
                          ),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: 40),
                  ),
                ],
              ],
            );

    return Scaffold(
      backgroundColor: NivioTheme.netflixBlack,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF141720),
              NivioTheme.netflixBlack,
            ],
          ),
        ),
        child: SafeArea(
          top: true,
          bottom: false,
          child: isDesktop
              ? scrollView
              : RefreshIndicator(
                  color: _categoryGradient.first,
                  backgroundColor: const Color(0xFF1A1D26),
                  onRefresh: _fetchInitialData,
                  child: scrollView,
                ),
        ),
      ),
    );
  }
}

class _DesktopBackButton extends StatefulWidget {
  final VoidCallback onTap;

  const _DesktopBackButton({required this.onTap});

  @override
  State<_DesktopBackButton> createState() => _DesktopBackButtonState();
}

class _DesktopBackButtonState extends State<_DesktopBackButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      style: DpadFocusStyle.highlight,
      onActivate: widget.onTap,
      child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.08),
              width: 1.0,
            ),
          ),
          child: Center(
            child: AnimatedSlide(
              offset: _isHovered ? const Offset(-0.08, 0) : Offset.zero,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              child: PhosphorIcon(
                PhosphorIconsRegular.caretLeft,
                color: _isHovered ? Colors.white : Colors.white.withValues(alpha: 0.8),
                size: 20,
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _DesktopScheduleButton extends StatefulWidget {
  final Color accentColor;
  final VoidCallback onTap;

  const _DesktopScheduleButton({
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_DesktopScheduleButton> createState() => _DesktopScheduleButtonState();
}

class _DesktopScheduleButtonState extends State<_DesktopScheduleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      style: DpadFocusStyle.highlight,
      onActivate: widget.onTap,
      child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
            decoration: BoxDecoration(
              color: _isHovered
                  ? widget.accentColor.withValues(alpha: 0.26)
                  : widget.accentColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isHovered
                    ? widget.accentColor.withValues(alpha: 0.75)
                    : widget.accentColor.withValues(alpha: 0.4),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIconsRegular.calendarBlank,
                  color: widget.accentColor,
                  size: 14,
                ),
                const SizedBox(width: 5),
                Text(
                  'Schedule',
                  style: TextStyle(
                    color: widget.accentColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Ultra-optimized poster release card:
/// - Fast GPU rendering with zero BackdropFilter blur overhead
/// - Downsampled cached images (memCacheWidth: 340) for minimal RAM usage
/// - Native RepaintBoundary layer caching
/// - Vertical poster aspect ratio matching industry-standard streaming catalogs
class _OptimizedReleaseCard extends StatefulWidget {
  final dynamic item;
  final bool isAnime;
  final List<Color> accentGradient;

  const _OptimizedReleaseCard({
    super.key,
    required this.item,
    required this.isAnime,
    required this.accentGradient,
  });

  @override
  State<_OptimizedReleaseCard> createState() => _OptimizedReleaseCardState();
}

class _OptimizedReleaseCardState extends State<_OptimizedReleaseCard> {
  bool _isHovered = false;

  String _formatReleaseTag(dynamic rawDate, dynamic digitalDate, dynamic airingAtSec) {
    DateTime? date;
    if (airingAtSec != null && airingAtSec is num && airingAtSec > 0) {
      date = DateTime.fromMillisecondsSinceEpoch(airingAtSec.toInt() * 1000);
    } else if (digitalDate != null && digitalDate.toString().isNotEmpty) {
      date = DateTime.tryParse(digitalDate.toString());
    } else if (rawDate != null && rawDate.toString().isNotEmpty) {
      date = DateTime.tryParse(rawDate.toString());
    }
    if (date == null) return '';

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.isNegative) {
      return 'Today';
    }
    if (diff.inMinutes < 60) {
      final mins = diff.inMinutes.clamp(1, 59);
      return '${mins}m ago';
    }
    if (diff.inHours < 24 && date.day == now.day && date.month == now.month && date.year == now.year) {
      return '${diff.inHours}h ago';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) {
      return 'Yesterday';
    }
    if (diff.inDays <= 7 && diff.inDays > 0) {
      return '${diff.inDays}d ago';
    }

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final yearSuffix = date.year != now.year ? ', ${date.year}' : '';
    return '${months[date.month - 1]} ${date.day}$yearSuffix';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    int id = 0;
    String title = '';
    String? posterPath;
    String? backdropPath;
    double? voteAverage;
    String mediaType = widget.isAnime ? 'anime' : 'movie';
    int? episodeNumber;
    dynamic rawDate;
    dynamic digitalDate;
    dynamic airingAtSec;

    if (item is SearchResult) {
      id = item.id;
      title = item.title ?? item.name ?? '';
      posterPath = item.posterPath;
      backdropPath = item.backdropPath;
      voteAverage = item.voteAverage;
      mediaType = item.mediaType;
      rawDate = item.releaseDate ?? item.firstAirDate;
    } else if (item is Map) {
      id = item['id'] as int? ?? 0;
      title = (item['title'] ?? item['name'] ?? '').toString();
      posterPath = item['poster_path']?.toString();
      backdropPath = item['backdrop_path']?.toString();
      voteAverage = (item['vote_average'] as num?)?.toDouble();
      mediaType = (item['media_type'] ?? (widget.isAnime ? 'anime' : (item['name'] != null ? 'tv' : 'movie'))).toString();
      episodeNumber = item['episode_number'] as int?;
      digitalDate = item['digital_release_date'];
      rawDate = item['release_date'] ?? item['first_air_date'];
      airingAtSec = item['airing_at'];
    }

    final releaseTag = _formatReleaseTag(rawDate, digitalDate, airingAtSec);

    // Prefer poster for vertical card format; fallback to backdrop if poster unavailable
    final imagePath = (posterPath != null && posterPath.isNotEmpty)
        ? posterPath
        : backdropPath;
    final imageUrl = imagePath != null && imagePath.isNotEmpty
        ? (imagePath.startsWith('http') ? imagePath : '$tmdbImageBaseUrl/w500$imagePath')
        : null;

    final isDesktop = AppPlatform.useDesktopLayout;

    Widget cardBody = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141720),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isHovered
              ? widget.accentGradient.first
              : const Color(0x14FFFFFF),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Stack(
          fit: StackFit.expand,
          children: [
          // Cached Poster Image
          if (imageUrl != null)
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              memCacheWidth: 340,
              filterQuality: FilterQuality.low,
              placeholder: (context, url) => const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFF1B1E28)),
              ),
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFF1B1E28),
                child: const Center(
                  child: Icon(Icons.movie_outlined, color: Colors.white24, size: 36),
                ),
              ),
            )
          else
            Container(
              color: const Color(0xFF1B1E28),
              child: const Center(
                child: Icon(Icons.movie_outlined, color: Colors.white24, size: 36),
              ),
            ),

          // Seamless bottom gradient scrim anchored to the bottom border edge
          const Positioned(
            left: 0,
            right: 0,
            bottom: -2,
            height: 75,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.4, 0.75, 1.0],
                  colors: [
                    Colors.transparent,
                    Color(0x66000000),
                    Color(0xCC000000),
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),

          // Top-Left Episode Badge (for Anime)
          if (episodeNumber != null)
            Positioned(
              top: 7,
              left: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: widget.accentGradient),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(PhosphorIconsFill.playCircle, size: 10, color: Colors.white),
                    const SizedBox(width: 3.5),
                    Text(
                      'EP $episodeNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Top-Right Rating Badge
          if (voteAverage != null && voteAverage > 0)
            Positioned(
              top: 7,
              right: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xB8000000),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0x26FFFFFF), width: 0.7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFC107)),
                    const SizedBox(width: 2.5),
                    Text(
                      voteAverage.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Content: Title & Release Date
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 4),
                    ],
                  ),
                ),
                if (releaseTag.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        PhosphorIconsRegular.clock,
                        size: 10,
                        color: widget.accentGradient.first.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 3.5),
                      Text(
                        releaseTag,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

    if (isDesktop) {
      cardBody = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedScale(
          scale: _isHovered ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: cardBody,
        ),
      );
    }

    return RepaintBoundary(
      child: FocusableTap(
        onTap: () {
          if (id == 0) return;
          GoRouter.of(context).push('/media/$id?type=$mediaType');
        },
        child: cardBody,
      ),
    );
  }
}
