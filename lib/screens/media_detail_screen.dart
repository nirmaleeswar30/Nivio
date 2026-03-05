import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/providers/dynamic_colors_provider.dart';
import 'package:nivio/providers/media_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/widgets/episode_list.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class _TrailerSource {
  const _TrailerSource({
    required this.site,
    required this.key,
    this.type,
    this.official = false,
  });

  final String site;
  final String key;
  final String? type;
  final bool official;

  String? get embedUrl {
    switch (site.toLowerCase()) {
      case 'youtube':
        return 'https://www.youtube-nocookie.com/embed/$key?autoplay=1&playsinline=1&rel=0&modestbranding=1';
      case 'vimeo':
        return 'https://player.vimeo.com/video/$key?autoplay=1';
      case 'dailymotion':
        return 'https://www.dailymotion.com/embed/video/$key?autoplay=1';
      default:
        return watchUrl;
    }
  }

  String? get watchUrl {
    switch (site.toLowerCase()) {
      case 'youtube':
        return 'https://www.youtube.com/watch?v=$key';
      case 'vimeo':
        return 'https://vimeo.com/$key';
      case 'dailymotion':
        return 'https://www.dailymotion.com/video/$key';
      default:
        return null;
    }
  }
}

class MediaDetailScreen extends ConsumerStatefulWidget {
  final int mediaId;
  final String? mediaType;

  const MediaDetailScreen({super.key, required this.mediaId, this.mediaType});

  @override
  ConsumerState<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends ConsumerState<MediaDetailScreen> {
  SearchResult? _media;
  List<String> _genres = const [];
  bool _aboutExpanded = false;
  bool _aboutOverflow = false;
  bool _isLoading = true;
  String? _error;
  _TrailerSource? _trailerSource;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchMediaDetails();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  _TrailerSource? _extractTrailerSource(dynamic videosData) {
    if (videosData == null) return null;
    final results = videosData['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    final candidates = <_TrailerSource>[];
    for (final raw in results) {
      if (raw is! Map<String, dynamic>) continue;
      final site = (raw['site'] as String?)?.trim();
      final key = (raw['key'] as String?)?.trim();
      if (site == null || site.isEmpty || key == null || key.isEmpty) {
        continue;
      }
      candidates.add(
        _TrailerSource(
          site: site,
          key: key,
          type: raw['type'] as String?,
          official: raw['official'] == true,
        ),
      );
    }

    if (candidates.isEmpty) return null;

    int score(_TrailerSource source) {
      int value = 0;
      final type = (source.type ?? '').toLowerCase();
      final site = source.site.toLowerCase();

      if (type == 'trailer') {
        value += 50;
      } else if (type == 'teaser') {
        value += 35;
      } else if (type == 'clip') {
        value += 20;
      }

      if (source.official) {
        value += 20;
      }

      if (site == 'youtube') {
        value += 10;
      } else if (site == 'vimeo') {
        value += 8;
      }

      return value;
    }

    candidates.sort((a, b) => score(b).compareTo(score(a)));
    return candidates.first;
  }

  Future<void> _fetchMediaDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tmdbService = ref.read(tmdbServiceProvider);
      Map<String, dynamic>? detailsWithVideos;

      int retries = 3;
      Duration delay = const Duration(milliseconds: 500);

      for (int attempt = 0; attempt < retries; attempt++) {
        try {
          if (widget.mediaType == 'movie') {
            detailsWithVideos = await tmdbService.getMovieDetailsWithVideos(
              widget.mediaId,
            );
            detailsWithVideos['media_type'] = 'movie';
          } else if (widget.mediaType == 'tv') {
            detailsWithVideos = await tmdbService.getTVShowDetailsWithVideos(
              widget.mediaId,
            );
            detailsWithVideos['media_type'] = 'tv';
          } else {
            try {
              detailsWithVideos = await tmdbService.getMovieDetailsWithVideos(
                widget.mediaId,
              );
              detailsWithVideos['media_type'] = 'movie';
            } catch (_) {
              detailsWithVideos = await tmdbService.getTVShowDetailsWithVideos(
                widget.mediaId,
              );
              detailsWithVideos['media_type'] = 'tv';
            }
          }
          break;
        } catch (e) {
          if (attempt == retries - 1) rethrow;
          await Future.delayed(delay);
          delay *= 2;
        }
      }

      final mediaDetails = SearchResult.fromJson(detailsWithVideos!);
      ref.read(selectedMediaProvider.notifier).state = mediaDetails;

      final trailerSource = _extractTrailerSource(detailsWithVideos['videos']);
      final genres = (detailsWithVideos['genres'] as List<dynamic>? ?? [])
          .map((genre) => (genre as Map<String, dynamic>)['name'] as String?)
          .whereType<String>()
          .toList();

      setState(() {
        _media = mediaDetails;
        _trailerSource = trailerSource;
        _genres = genres;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showTrailerPlayer(BuildContext context) {
    if (_trailerSource == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrailerFullscreenScreen(source: _trailerSource!),
      ),
    );
  }

  void _handleBackNavigation() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  Widget _withBackGuard(Widget child) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackNavigation();
        }
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _withBackGuard(
        Scaffold(
          backgroundColor: NivioTheme.netflixBlack,
          appBar: AppBar(
            backgroundColor: NivioTheme.netflixBlack,
            elevation: 0,
          ),
          body: Center(
            child: CircularProgressIndicator(
              color: NivioTheme.accentColorOf(context),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return _withBackGuard(
        Scaffold(
          backgroundColor: NivioTheme.netflixBlack,
          appBar: AppBar(
            backgroundColor: NivioTheme.netflixBlack,
            elevation: 0,
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PhosphorIcon(
                    PhosphorIconsRegular.warningCircle,
                    color: NivioTheme.accentColorOf(context),
                    size: 56,
                  ),
                  const SizedBox(height: 14),
                  const Text('Failed to load details'),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: NivioTheme.netflixGrey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _fetchMediaDetails,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final media = _media;
    if (media == null) {
      return _withBackGuard(
        const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final tmdbService = ref.read(tmdbServiceProvider);
    final fallbackBackdropUrl = tmdbService.getBackdropUrl(media.backdropPath);
    final fallbackPosterUrl = tmdbService.getPosterUrl(media.posterPath);
    final backdropUrl = fallbackBackdropUrl.isNotEmpty
        ? fallbackBackdropUrl
        : fallbackPosterUrl;
    final posterUrl = fallbackPosterUrl;
    final isInWatchlist = ref.watch(isInWatchlistProvider(media.id));
    final colorsAsync = ref.watch(dynamicColorsProvider(posterUrl));
    final colors = colorsAsync.valueOrNull ?? DynamicColors.fallback;
    final accentColor = colors.lightVibrant;

    final screenHeight = MediaQuery.sizeOf(context).height;
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final isTablet = shortestSide >= 600;
    final heroHeight = (screenHeight * (isTablet ? 0.58 : 0.50))
        .clamp(360.0, isTablet ? 700.0 : 560.0)
        .toDouble();
    const detailsOverlap = 0.0;
    final year =
        media.releaseDate?.substring(0, 4) ??
        media.firstAirDate?.substring(0, 4) ??
        'Unknown';
    final mediaName = media.title ?? media.name ?? 'Unknown';

    return _withBackGuard(
      Scaffold(
        backgroundColor: colors.darkMuted,
        body: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Radial gradient bloom ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
                  // Dominant color "leaks" from the hero image like light
                  // emitting from the artwork. Fades to transparent by ~150px
                  // below the image bottom. Very low opacity, heavily blurred.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: heroHeight + 220,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(
                        sigmaX: 64,
                        sigmaY: 64,
                        tileMode: TileMode.decal,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.topCenter,
                            radius: 1.4,
                            colors: [
                              colors.dominant.withValues(alpha: 0.20),
                              colors.dominant.withValues(alpha: 0.07),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.40, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Main content ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: heroHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (backdropUrl.isNotEmpty)
                              CachedNetworkImage(
                                imageUrl: backdropUrl,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) =>
                                    Container(color: colors.darkMuted),
                              )
                            else
                              Container(color: colors.darkMuted),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.5),
                                    colors.darkMuted,
                                  ],
                                  stops: [0.0, 0.7, 1.0],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 14,
                              right: 14,
                              top: MediaQuery.paddingOf(context).top + 4,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _glassIconButton(
                                    icon: const PhosphorIcon(
                                      PhosphorIconsRegular.caretLeft,
                                      color: NivioTheme.netflixWhite,
                                      size: 20,
                                    ),
                                    onTap: _handleBackNavigation,
                                  ),
                                  Row(
                                    children: [
                                      _glassIconButton(
                                        icon: const PhosphorIcon(
                                          PhosphorIconsRegular.video,
                                          color: NivioTheme.netflixWhite,
                                          size: 19,
                                        ),
                                        onTap: () {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text('Cast coming soon'),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 10),
                                      _glassIconButton(
                                        icon: const PhosphorIcon(
                                          PhosphorIconsRegular.shareNetwork,
                                          color: NivioTheme.netflixWhite,
                                          size: 19,
                                        ),
                                        onTap: () async {
                                          final shareUrl =
                                              media.mediaType == 'movie'
                                              ? 'https://www.themoviedb.org/movie/${media.id}'
                                              : 'https://www.themoviedb.org/tv/${media.id}';
                                          await Clipboard.setData(
                                            ClipboardData(text: shareUrl),
                                          );
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Link copied to clipboard',
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              left: 16,
                              bottom: 20,
                              child: Row(
                                children: [
                                  if ((media.voteAverage ?? 0) > 0) ...[
                                    _glassTag(
                                      '★ ${media.voteAverage!.toStringAsFixed(1)}',
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (year.isNotEmpty) ...[
                                    _glassTag(year),
                                    const SizedBox(width: 8),
                                  ],
                                  _glassTag(media.mediaType.toUpperCase()),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      Transform.translate(
                        offset: Offset(0, -detailsOverlap),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mediaName,
                                style: Theme.of(context).textTheme.displaySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: NivioTheme.netflixWhite,
                                      height: 1.2,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              // Genre subtext ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â wraps to next line on overflow
                              Text(
                                _buildGenreMeta(year, media.voteAverage),
                                style: TextStyle(
                                  color: NivioTheme.netflixLightGrey,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: _playAllButton(
                                      accentColor: accentColor,
                                      label: media.mediaType == 'movie'
                                          ? 'Play'
                                          : 'Play all episodes',
                                      onTap: () {
                                        final season = media.mediaType == 'tv'
                                            ? ref.read(selectedSeasonProvider)
                                            : 1;
                                        context.push(
                                          '/player/${media.id}?season=$season&episode=1&type=${media.mediaType}',
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Filled heart = in watchlist, outline = not
                                  _plainIconButton(
                                    icon: Icon(
                                      isInWatchlist
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: isInWatchlist
                                          ? colors.dominant
                                          : NivioTheme.netflixWhite,
                                      size: 24,
                                    ),
                                    iconColor: isInWatchlist
                                        ? colors.dominant
                                        : NivioTheme.netflixWhite,
                                    onTap: () =>
                                        _toggleWatchlist(media, isInWatchlist),
                                  ),
                                ],
                              ),
                              if (_trailerSource != null) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        _showTrailerPlayer(context),
                                    icon: Icon(
                                      Icons.play_circle_outline,
                                      size: 17,
                                      color: accentColor,
                                    ),
                                    label: Text(
                                      'Watch trailer',
                                      style: TextStyle(color: accentColor),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              Text(
                                'About',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: NivioTheme.netflixWhite,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              _buildAboutSection(
                                media.overview?.isNotEmpty == true
                                    ? media.overview!
                                    : 'No description available for this title yet.',
                                accentColor: accentColor,
                              ),
                              const SizedBox(height: 26),
                              if (media.mediaType == 'tv')
                                _buildTVControls(context, media, colors),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassIconButton({
    required Widget icon,
    required VoidCallback onTap,
    double size = 44,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: Material(
          color: const Color(0x26FFFFFF),
          shape: const CircleBorder(
            side: BorderSide(color: Color(0x33FFFFFF), width: 1),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassTag(String label) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0x26FFFFFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x4DFFFFFF)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: NivioTheme.netflixWhite,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _buildGenreMeta(String year, double? rating) {
    final parts = <String>[];
    if (rating != null && rating > 0) {
      parts.add('★ ${rating.toStringAsFixed(1)}');
    }
    final topGenres = _genres.take(3).toList();
    if (topGenres.isNotEmpty) {
      parts.add(topGenres.join(' | '));
    }
    if (year.isNotEmpty) {
      parts.add(year);
    }
    return parts.isEmpty ? 'Unknown' : parts.join(' | ');
  }

  Widget _plainIconButton({
    required Widget icon,
    required VoidCallback onTap,
    Color iconColor = NivioTheme.netflixWhite,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: icon,
      splashRadius: 24,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  Widget _playAllButton({
    required Color accentColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: NivioTheme.glassFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: accentColor.withValues(alpha: 0.65)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PhosphorIcon(
                    PhosphorIconsFill.play,
                    color: accentColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
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

  Future<void> _toggleWatchlist(SearchResult media, bool isInWatchlist) async {
    final watchlistService = ref.read(watchlistServiceProvider);

    if (isInWatchlist) {
      await watchlistService.removeFromWatchlist(media.id);
      ref.read(watchlistRefreshProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed from watchlist'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      final item = WatchlistItem(
        id: media.id,
        title: media.title ?? media.name ?? 'Unknown',
        posterPath: media.posterPath,
        mediaType: media.mediaType,
        addedAt: DateTime.now(),
        voteAverage: media.voteAverage,
        releaseDate: media.releaseDate ?? media.firstAirDate,
        overview: media.overview,
      );
      await watchlistService.addToWatchlist(item);
      ref.read(watchlistRefreshProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added to watchlist'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildTVControls(
    BuildContext context,
    SearchResult media,
    DynamicColors colors,
  ) {
    final seriesInfoAsync = ref.watch(seriesInfoProvider(media.id));

    return seriesInfoAsync.when(
      data: (seriesInfo) {
        final selectedSeason = ref.watch(selectedSeasonProvider);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Episodes',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: NivioTheme.netflixWhite,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  width: 154,
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0x241F2431),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0x36FFFFFF)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isDense: true,
                      value: selectedSeason <= seriesInfo.seasons.length
                          ? selectedSeason
                          : 1,
                      dropdownColor: NivioTheme.netflixDarkGrey,
                      borderRadius: BorderRadius.circular(14),
                      icon: Icon(
                        Icons.expand_more,
                        color: NivioTheme.netflixWhite,
                      ),
                      style: TextStyle(
                        color: NivioTheme.netflixWhite,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      items: seriesInfo.seasons
                          .where((s) => s.seasonNumber > 0)
                          .map(
                            (season) => DropdownMenuItem(
                              value: season.seasonNumber,
                              child: Text('Season ${season.seasonNumber}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        ref.read(selectedSeasonProvider.notifier).state = value;
                        ref.read(selectedEpisodeProvider.notifier).state = 1;
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            EpisodeList(
              media: media,
              season: selectedSeason,
              colors: colors,
              scrollController: _scrollController,
            ),
          ],
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(
          color: NivioTheme.accentColorOf(context),
        ),
      ),
      error: (err, stack) => Text(
        'Error loading seasons: $err',
        style: TextStyle(color: NivioTheme.netflixLightGrey),
      ),
    );
  }

  Widget _buildAboutSection(String aboutText, {required Color accentColor}) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: NivioTheme.netflixLightGrey,
      height: 1.45,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: aboutText, style: style),
          maxLines: 4,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        final hasOverflow = textPainter.didExceedMaxLines;
        if (_aboutOverflow != hasOverflow) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _aboutOverflow = hasOverflow);
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              aboutText,
              style: style,
              maxLines: _aboutExpanded ? null : 4,
              overflow: _aboutExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (_aboutOverflow) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: () {
                  setState(() => _aboutExpanded = !_aboutExpanded);
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _aboutExpanded ? 'Read less' : 'Read more',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class TrailerFullscreenScreen extends StatefulWidget {
  const TrailerFullscreenScreen({super.key, required this.source});

  final _TrailerSource source;

  @override
  State<TrailerFullscreenScreen> createState() =>
      _TrailerFullscreenScreenState();
}

class _TrailerFullscreenScreenState extends State<TrailerFullscreenScreen> {
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  Future<void> _openExternally() async {
    final url = widget.source.watchUrl ?? widget.source.embedUrl;
    if (url == null) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open trailer externally')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final trailerUrl = widget.source.embedUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: trailerUrl == null
                ? Center(
                    child: Text(
                      'Unsupported trailer source: ${widget.source.site}',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  )
                : InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(trailerUrl)),
                    initialSettings: InAppWebViewSettings(
                      mediaPlaybackRequiresUserGesture: false,
                      allowsInlineMediaPlayback: true,
                      transparentBackground: true,
                      javaScriptEnabled: true,
                    ),
                    onLoadStop: (controller, url) {
                      if (!mounted) return;
                      setState(() {
                        _isLoading = false;
                        _hasError = false;
                      });
                    },
                    onReceivedError: (controller, request, error) {
                      if (!mounted) return;
                      setState(() {
                        _isLoading = false;
                        _hasError = true;
                      });
                    },
                    onReceivedHttpError: (controller, request, response) {
                      if (!mounted) return;
                      setState(() {
                        _isLoading = false;
                        _hasError = true;
                      });
                    },
                    onConsoleMessage: (controller, consoleMessage) {
                      final msg = consoleMessage.message.toLowerCase();
                      final hasPlaybackRestriction =
                          msg.contains('error 153') ||
                          (msg.contains('youtube') &&
                              msg.contains('playback') &&
                              msg.contains('website'));
                      if (!hasPlaybackRestriction || !mounted) return;
                      setState(() {
                        _isLoading = false;
                        _hasError = true;
                      });
                    },
                  ),
          ),
          if (_hasError)
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unable to play trailer from ${widget.source.site}',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    if (widget.source.watchUrl != null) ...[
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _openExternally,
                        child: const Text('Open Externally'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_isLoading && trailerUrl != null && !_hasError)
            Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(
                  color: NivioTheme.accentColorOf(context),
                  strokeWidth: 3,
                ),
              ),
            ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 12,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
