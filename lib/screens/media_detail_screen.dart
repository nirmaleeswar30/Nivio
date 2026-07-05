import 'dart:ui';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:flutter/material.dart';
import '../widgets/download_prompt.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/models/download_item.dart';
import 'package:nivio/providers/dynamic_colors_provider.dart';
import 'package:nivio/widgets/marquee_text.dart';
import 'package:nivio/providers/media_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/watch_party_provider.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/widgets/episode_list.dart';
import 'package:nivio/services/download_service.dart';
import 'package:nivio/services/streaming_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
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
        return 'https://www.youtube.com/embed/$key?autoplay=1&playsinline=1&rel=0&modestbranding=1&enablejsapi=1&origin=https://www.youtube.com';
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
  List<dynamic> _cast = [];
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
      final anilistService = ref.read(aniListServiceProvider);
      
      SearchResult? mediaDetails;
      _TrailerSource? trailerSource;
      List<dynamic> castData = [];
      List<String> genres = [];
      Map<String, dynamic>? detailsWithVideos;

      if (widget.mediaType == 'anime') {
        final extras = await anilistService.getAnimeDetailsWithExtras(widget.mediaId);
        mediaDetails = anilistService.mapToSearchResult(extras);

        if (extras['trailer'] != null && extras['trailer']['site'] == 'youtube') {
          trailerSource = _TrailerSource(
            site: 'YouTube',
            key: extras['trailer']['id'],
            type: 'Trailer',
          );
        } else {
          trailerSource = null;
        }

        final characters = extras['characters']?['edges'] as List<dynamic>? ?? [];
        castData = characters.map((char) {
          final node = char['node'] is Map ? char['node'] : {};
          final voiceActors = char['voiceActors'] is List ? char['voiceActors'] as List : [];
          final voiceActor = voiceActors.isNotEmpty && voiceActors.first is Map ? voiceActors.first : null;
          
          final nodeName = node['name'] is Map ? node['name']['full'] : null;
          final voiceActorName = voiceActor != null && voiceActor['name'] is Map ? voiceActor['name']['full'] : null;
          final nodeImage = node['image'] is Map ? node['image']['large'] : null;
          final voiceActorImage = voiceActor != null && voiceActor['image'] is Map ? voiceActor['image']['large'] : null;

          return {
            'id': node['id'] ?? 0,
            'name': voiceActorName ?? nodeName,
            'character': nodeName ?? char['role'],
            'profile_path': voiceActorImage ?? nodeImage,
            'is_anilist': true,
          };
        }).toList();

        genres = ['Animation', 'Anime'];
      } else {
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

      }
      
      if (widget.mediaType != 'anime') {
        mediaDetails = SearchResult.fromJson(detailsWithVideos!);
        trailerSource = _extractTrailerSource(detailsWithVideos['videos']);
        castData = detailsWithVideos['credits']?['cast'] as List<dynamic>? ?? [];
        genres = (detailsWithVideos['genres'] as List<dynamic>? ?? [])
            .map((genre) => (genre as Map<String, dynamic>)['name'] as String?)
            .whereType<String>()
            .toList();
      }
      
      ref.read(selectedMediaProvider.notifier).state = mediaDetails;

      setState(() {
        _media = mediaDetails;
        _trailerSource = trailerSource;
        _cast = castData;
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

  String _buildPlayerRoute({
    required SearchResult media,
    required int season,
    required int episode,
  }) {
    final watchPartyService = ref.read(watchPartyServiceProvider);
    final sessionCode = watchPartyService?.sessionCode;
    final hasPartyContext =
        watchPartyService?.isInSession == true &&
        sessionCode != null &&
        sessionCode.trim().isNotEmpty;

    final query = <String, String>{
      'season': '$season',
      'episode': '$episode',
      if (media.mediaType.isNotEmpty) 'type': media.mediaType,
      if (hasPartyContext) 'partyCode': sessionCode.trim().toUpperCase(),
      if (hasPartyContext)
        'partyRole': watchPartyService!.isHost ? 'host' : 'participant',
    };
    return Uri(path: '/player/${media.id}', queryParameters: query).toString();
  }

  void _openWatchPartyHub(SearchResult media) {
    final season = (media.mediaType == 'tv' || media.mediaType == 'anime')
        ? ref.read(selectedSeasonProvider)
        : 1;
    context.go(
      Uri(
        path: '/party',
        queryParameters: {
          'mediaId': '${media.id}',
          'type': media.mediaType,
          'season': '$season',
          'title': media.title ?? media.name ?? 'Untitled',
        },
      ).toString(),
    );
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
    final backdropUrl = fallbackPosterUrl.isNotEmpty
        ? fallbackPosterUrl
        : fallbackBackdropUrl;
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
                                          PhosphorIconsRegular.users,
                                          color: NivioTheme.netflixWhite,
                                          size: 19,
                                        ),
                                        onTap: () => _openWatchPartyHub(media),
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
                              MarqueeText(
                                text: mediaName,
                                style: Theme.of(context).textTheme.displaySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: NivioTheme.netflixWhite,
                                      height: 1.2,
                                    ),
                                blankSpace: 50.0,
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
                                        final season = (media.mediaType == 'tv' || media.mediaType == 'anime')
                                            ? ref.read(selectedSeasonProvider)
                                            : 1;
                                        context.push(
                                          _buildPlayerRoute(
                                            media: media,
                                            season: season,
                                            episode: 1,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
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
                                  const SizedBox(width: 6),
                                  ValueListenableBuilder<Box<DownloadItem>>(
                                    valueListenable: DownloadService.box.listenable(),
                                    builder: (context, box, _) {
                                      final downloads = box.values.where((item) => item.mediaId == media.id).toList();
                                      final isDownloading = downloads.any((item) => item.status == DownloadStatus.downloading || item.status == DownloadStatus.pending || item.status == DownloadStatus.extracting);
                                      final allCompleted = downloads.isNotEmpty && downloads.every((item) => item.status == DownloadStatus.completed);
                                      
                                      if (isDownloading) {
                                        final downloadingItems = downloads.where((item) => item.status == DownloadStatus.downloading || item.status == DownloadStatus.extracting).toList();
                                        double progress = 0;
                                        if (downloadingItems.isNotEmpty) {
                                          progress = downloadingItems.map((e) => e.progress).reduce((a, b) => a + b) / downloadingItems.length;
                                        }
                                        return SizedBox(
                                          width: 40,
                                          height: 40,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: CircularProgressIndicator(
                                              value: progress > 0 ? progress : null,
                                              strokeWidth: 3,
                                              valueColor: AlwaysStoppedAnimation<Color>(NivioTheme.accentColorOf(context)),
                                            ),
                                          ),
                                        );
                                      }
                                      
                                      return _plainIconButton(
                                        icon: Icon(
                                          allCompleted ? Icons.download_done_rounded : (media.mediaType == 'movie' ? Icons.download_rounded : Icons.file_download),
                                          color: allCompleted ? NivioTheme.accentColorOf(context) : NivioTheme.netflixWhite,
                                          size: 24,
                                        ),
                                        iconColor: NivioTheme.netflixWhite,
                                        onTap: () => _handleDownload(media),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  _plainIconButton(
                                    icon: const Icon(
                                      Icons.share_rounded,
                                      color: NivioTheme.netflixWhite,
                                      size: 24,
                                    ),
                                    iconColor: NivioTheme.netflixWhite,
                                    onTap: () => _shareMedia(media),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  if (_trailerSource != null)
                                    TextButton.icon(
                                      onPressed: () => _showTrailerPlayer(context),
                                      icon: Icon(
                                        Icons.play_circle_outline,
                                        size: 17,
                                        color: accentColor,
                                      ),
                                      label: Text(
                                        'Watch trailer',
                                        style: TextStyle(color: accentColor),
                                      ),
                                    )
                                  else
                                    const SizedBox.shrink(),
                                  TextButton.icon(
                                    onPressed: () {
                                      final title = Uri.encodeComponent(media.title ?? media.name ?? '');
                                      context.push('/similar/${media.id}?type=${media.mediaType}&title=$title');
                                    },
                                    icon: PhosphorIcon(
                                      PhosphorIconsRegular.magicWand,
                                      size: 17,
                                      color: accentColor,
                                    ),
                                    label: Text(
                                      'More Like This',
                                      style: TextStyle(color: accentColor),
                                    ),
                                  ),
                                ],
                              ),
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
                              if (_cast.isNotEmpty) _buildCastRow(),
                              const SizedBox(height: 26),
                              if (media.mediaType == 'tv' || media.mediaType == 'anime')
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: NivioTheme.glassFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: accentColor.withValues(alpha: 0.65)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PhosphorIcon(
                    PhosphorIconsFill.play,
                    color: accentColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
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

  Widget _buildCastRow() {
    if (_cast.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          'Cast',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: NivioTheme.netflixWhite,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _cast.length > 20 ? 20 : _cast.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final actor = _cast[index];
              final profilePath = actor['profile_path'] as String?;
              final name = actor['name'] as String? ?? 'Unknown';
              final character = actor['character'] as String? ?? '';
              final tmdbService = ref.read(tmdbServiceProvider);

              return SizedBox(
                width: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          color: NivioTheme.netflixDarkGrey,
                          child: profilePath != null
                              ? CachedNetworkImage(
                                  imageUrl: (actor['is_anilist'] == true || profilePath.startsWith('http'))
                                      ? profilePath
                                      : tmdbService.getPosterUrl(profilePath),
                                  fit: BoxFit.cover,
                                )
                              : const Icon(Icons.person, color: Colors.white54, size: 40),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (character.isNotEmpty)
                      Text(
                        character,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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

  void _shareMedia(SearchResult media) {
    final title = media.title ?? media.name ?? 'this title';
    
    // Create the deep link URL
    final mediaType = media.mediaType;
    final deepLink = 'nivio://open/media/${media.id}?type=$mediaType';
    
    // Encode the deep link into Base64
    final bytes = utf8.encode(deepLink);
    final base64DeepLink = base64.encode(bytes);
    
    // Build the redirect URL using our hosted HTML file
    final baseUrl = dotenv.env['SHARE_REDIRECT_URL'] ?? 'https://nirmaleeswar30.github.io/Nivio/redirect.html';
    final redirectUrl = '$baseUrl?url=$base64DeepLink';
    
    final overview = media.overview != null && media.overview!.isNotEmpty 
        ? '\n\n${media.overview}' 
        : '';
    final shareText = 'Check out "$title"!$overview\n\nWatch here: $redirectUrl';
    Share.share(shareText, subject: title);
  }

  Future<void> _handleDownload(SearchResult media) async {
    final streamingService = ref.read(streamingServiceProvider);
    final isAnime = media.originalLanguage == 'ja';
    
    // Auto-select provider for downloads
    final providerIndex = 0; 
    
    if (!StreamingService.isDownloadable(providerIndex, isAnime: isAnime)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected provider does not support downloading.')),
      );
      return;
    }

    if (media.mediaType == 'movie') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparing movie download...')),
      );
      
      final result = await streamingService.fetchStreamUrl(
        media: media,
        providerIndex: providerIndex,
      );
      
      if (result != null && result.url.isNotEmpty) {
        await DownloadPrompt.showAndQueue(
          context: context,
          ref: ref,
          streamResult: result,
          mediaId: media.id,
          title: media.title ?? media.name ?? 'Movie',
          mediaType: media.mediaType,
          posterPath: media.posterPath,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to find downloadable stream.')),
          );
        }
      }
    } else {
      // Show dialog for Download All vs Season
      _showDownloadDialog(media, providerIndex);
    }
  }

  void _showDownloadDialog(SearchResult media, int providerIndex) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: NivioTheme.netflixDarkGrey,
          title: const Text('Download Episodes', style: TextStyle(color: Colors.white)),
          content: const Text('Do you want to download all episodes in this season, or all seasons?', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _startBatchDownload(media, providerIndex, singleSeason: ref.read(selectedSeasonProvider));
              },
              child: const Text('This Season'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _startBatchDownload(media, providerIndex);
              },
              child: const Text('All Seasons'),
            ),
          ],
        );
      }
    );
  }

  /// Probes the first episode to discover available languages, shows the language picker,
  /// then queues all episodes with the selected languages.
  Future<void> _startBatchDownload(SearchResult media, int providerIndex, {int? singleSeason}) async {
    final streamingService = ref.read(streamingServiceProvider);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Probing first episode for language options...')),
    );

    // Probe the first episode to discover available audio/subtitle tracks
    final seriesInfoAsync = ref.read(seriesInfoProvider(media.id));
    final seriesInfo = seriesInfoAsync.valueOrNull;
    if (seriesInfo == null) return;

    // Find the first valid episode to probe
    int probeSeason = singleSeason ?? seriesInfo.seasons.firstWhere((s) => s.seasonNumber > 0, orElse: () => seriesInfo.seasons.first).seasonNumber;
    final probeSeasonData = await ref.read(seasonDataProvider((showId: media.id, seasonNumber: probeSeason)).future);
    final probeEpisode = probeSeasonData.episodes.firstWhere(
      (ep) => ep.airDate != null && DateTime.tryParse(ep.airDate!)?.isBefore(DateTime.now()) == true,
      orElse: () => probeSeasonData.episodes.first,
    );

    final probeResult = await streamingService.fetchStreamUrl(
      media: media,
      season: probeSeason,
      episode: probeEpisode.episodeNumber,
      providerIndex: providerIndex,
    );

    if (probeResult == null || probeResult.url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to probe first episode. Cannot determine languages.')),
        );
      }
      return;
    }

    if (!mounted) return;

    // Show language picker (returns null if user cancels)
    final langChoice = await DownloadPrompt.pickLanguages(
      context: context,
      ref: ref,
      streamResult: probeResult,
    );

    if (langChoice == null) return; // User cancelled

    final preferredQuality = langChoice.selectedSource?.quality;
    final subDubPreference = langChoice.selectedSource != null ? (langChoice.selectedSource!.isDub ? 'dub' : 'sub') : null;

    // Now queue the actual downloads
    if (singleSeason != null) {
      _downloadSeason(media, providerIndex, singleSeason, langChoice.audioLang, langChoice.subtitleLang, preferredQuality: preferredQuality, subDubPreference: subDubPreference);
    } else {
      _downloadAllSeasons(media, providerIndex, langChoice.audioLang, langChoice.subtitleLang, preferredQuality: preferredQuality, subDubPreference: subDubPreference);
    }
  }

  Future<void> _downloadSeason(SearchResult media, int providerIndex, int season, String? audioLang, String? subtitleLang, {String? preferredQuality, String? subDubPreference}) async {
    final streamingService = ref.read(streamingServiceProvider);
    final seriesInfoAsync = ref.read(seriesInfoProvider(media.id));
    seriesInfoAsync.whenData((seriesInfo) async {
       final seasonData = await ref.read(seasonDataProvider((showId: media.id, seasonNumber: season)).future);
       
       final validEpisodes = seasonData.episodes.where((ep) => ep.airDate != null && DateTime.tryParse(ep.airDate!)?.isBefore(DateTime.now()) == true).toList();
       if (validEpisodes.isEmpty) return;

       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Preparing ${validEpisodes.length} episodes for download...')),
          );
       }

       int count = 0;
       for (final ep in validEpisodes) {
          await _downloadEpisode(streamingService, media, season, ep.episodeNumber, ep.episodeName ?? 'Episode', ep.stillPath, providerIndex, audioLang, subtitleLang, preferredQuality: preferredQuality, subDubPreference: subDubPreference);
          count++;
       }
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Queued $count episodes for download!')),
          );
       }
    });
  }

  Future<void> _downloadAllSeasons(SearchResult media, int providerIndex, String? audioLang, String? subtitleLang, {String? preferredQuality, String? subDubPreference}) async {
    final streamingService = ref.read(streamingServiceProvider);
    final seriesInfoAsync = ref.read(seriesInfoProvider(media.id));
    seriesInfoAsync.whenData((seriesInfo) async {
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Preparing all seasons for download. This may take a while...')),
          );
       }

       int count = 0;
       for (final s in seriesInfo.seasons) {
          if (s.seasonNumber == 0) continue;
          final seasonData = await ref.read(seasonDataProvider((showId: media.id, seasonNumber: s.seasonNumber)).future);
          
          final validEpisodes = seasonData.episodes.where((ep) => ep.airDate != null && DateTime.tryParse(ep.airDate!)?.isBefore(DateTime.now()) == true).toList();
          
          for (final ep in validEpisodes) {
             await _downloadEpisode(streamingService, media, s.seasonNumber, ep.episodeNumber, ep.episodeName ?? 'Episode', ep.stillPath, providerIndex, audioLang, subtitleLang, preferredQuality: preferredQuality, subDubPreference: subDubPreference);
             count++;
          }
       }
       if (mounted && count > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Queued $count episodes for download!')),
          );
       }
    });
  }

  Future<void> _downloadEpisode(StreamingService streamingService, SearchResult media, int season, int episode, String episodeName, String? stillPath, int providerIndex, String? audioLang, String? subtitleLang, {String? preferredQuality, String? subDubPreference}) async {
    try {
      final result = await streamingService.fetchStreamUrl(
      media: media,
      season: season,
      episode: episode,
      providerIndex: providerIndex,
      preferredQuality: preferredQuality,
      subDubPreference: subDubPreference ?? 'sub',
    );
    
    if (result != null && result.url.isNotEmpty) {
      await DownloadService.queueDownload(
        mediaId: media.id,
        title: '${media.title ?? media.name ?? 'Episode'}|||$episodeName',
        mediaType: media.mediaType,
        season: season,
        episode: episode,
        posterPath: '${media.posterPath}|||${stillPath ?? media.posterPath}',
        streamUrl: result.url,
        headers: result.headers,
        selectedAudioLanguage: audioLang,
        selectedSubtitleLanguage: subtitleLang,
      );
    }
    } catch (e) {
      debugPrint('Error queueing download for episode $episode: $e');
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
  static const Map<String, String> _youtubeQualityLabels = {
    'auto': 'Auto',
    'hd1080': '1080p',
    'hd720': '720p',
    'large': '480p',
  };

  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  YoutubePlayerController? _youtubeController;
  String _selectedYoutubeQuality = 'auto';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initPlayer();
  }

  void _initPlayer() {
    if (widget.source.site.toLowerCase() == 'youtube') {
      _initYoutubePlayer();
    } else {
      // For non-YouTube sources, mark as loaded (WebView will handle)
      setState(() => _isLoading = false);
    }
  }

  void _initYoutubePlayer() {
    try {
      final videoId = widget.source.key;

      _youtubeController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          enableCaption: false,
          hideControls: false,
          forceHD: false,
          useHybridComposition: true,
        ),
      );

      _youtubeController!.addListener(() {
        if (!mounted) return;
        if (_youtubeController!.value.isReady && _isLoading) {
          setState(() => _isLoading = false);
          _applyYoutubeQuality(_selectedYoutubeQuality);
        }
        if (_youtubeController!.value.hasError && !_hasError) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Failed to load YouTube video';
          });
        }
      });

      setState(() {});
    } catch (e) {
      debugPrint('YouTube player error: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Failed to load YouTube video';
      });
    }
  }

  @override
  void dispose() {
    _youtubeController?.dispose();
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

  Future<void> _applyYoutubeQuality(String quality) async {
    if (widget.source.site.toLowerCase() != 'youtube') return;

    final controller = _youtubeController;
    if (controller == null || !controller.value.isReady) return;
    final web = controller.value.webViewController;
    if (web == null) return;

    final target = quality == 'auto' ? 'default' : quality;
    await web.evaluateJavascript(
      source:
          '''
      (function() {
        try {
          if (typeof player === 'undefined' || !player) return;
          if (player.setPlaybackQualityRange) {
            player.setPlaybackQualityRange('$target');
          }
          if (player.setPlaybackQuality) {
            player.setPlaybackQuality('$target');
          }
        } catch (_) {}
      })();
      ''',
    );
  }

  Future<void> _showTrailerQualityDialog() async {
    if (widget.source.site.toLowerCase() != 'youtube') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quality control is available for YouTube trailers only',
          ),
        ),
      );
      return;
    }

    final current = _selectedYoutubeQuality;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: NivioTheme.netflixDarkGrey,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Trailer Quality',
                  style: TextStyle(
                    color: NivioTheme.netflixWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ..._youtubeQualityLabels.entries.map((entry) {
                final key = entry.key;
                final label = entry.value;
                final isSelected = key == current;
                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected
                        ? NivioTheme.accentColorOf(context)
                        : NivioTheme.netflixGrey,
                  ),
                  title: Text(
                    label,
                    style: const TextStyle(color: NivioTheme.netflixWhite),
                  ),
                  onTap: () => Navigator.pop(sheetContext, key),
                );
              }),
            ],
          ),
        );
      },
    );

    if (selected == null || selected == _selectedYoutubeQuality) return;
    setState(() {
      _selectedYoutubeQuality = selected;
    });
    await _applyYoutubeQuality(selected);
  }

  Widget _buildYoutubePlayer() {
    if (_youtubeController == null) {
      return const SizedBox.shrink();
    }
    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _youtubeController!,
        showVideoProgressIndicator: true,
        progressIndicatorColor: Colors.red,
        progressColors: const ProgressBarColors(
          playedColor: Colors.red,
          handleColor: Colors.redAccent,
        ),
      ),
      builder: (context, player) => player,
    );
  }

  Widget _buildWebViewPlayer() {
    final trailerUrl = widget.source.embedUrl;
    if (trailerUrl == null) {
      return Center(
        child: Text(
          'Unsupported trailer source: ${widget.source.site}',
          style: const TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      );
    }
    return InAppWebView(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isYoutube = widget.source.site.toLowerCase() == 'youtube';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: isYoutube ? _buildYoutubePlayer() : _buildWebViewPlayer(),
          ),
          if (_hasError)
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _errorMessage ??
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
          if (_isLoading && !_hasError)
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
            child: Row(
              children: [
                GestureDetector(
                  onTap: _showTrailerQualityDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.hd_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isYoutube
                              ? (_youtubeQualityLabels[_selectedYoutubeQuality] ??
                                    'Auto')
                              : 'Quality',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
