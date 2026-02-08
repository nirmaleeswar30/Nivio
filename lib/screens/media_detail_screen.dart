import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/season_info.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/providers/media_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/providers/dynamic_colors_provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

class MediaDetailScreen extends ConsumerStatefulWidget {
  final int mediaId;
  final String? mediaType;

  const MediaDetailScreen({super.key, required this.mediaId, this.mediaType});

  @override
  ConsumerState<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends ConsumerState<MediaDetailScreen> {
  SearchResult? _media;
  bool _isLoading = true;
  String? _error;
  String? _trailerUrl;
  String _episodeSearchQuery = '';
  final TextEditingController _episodeSearchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchMediaDetails();
  }

  @override
  void dispose() {
    _episodeSearchController.dispose();
    super.dispose();
  }

  String? _extractTrailerKey(dynamic videosData) {
    if (videosData == null) return null;
    final results = videosData['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    for (final video in results) {
      if (video['site'] == 'YouTube' &&
          video['type'] == 'Trailer' &&
          video['official'] == true) {
        return 'https://www.youtube.com/watch?v=${video['key']}';
      }
    }
    return null;
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
            } catch (e) {
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

      final trailerUrl = _extractTrailerKey(detailsWithVideos['videos']);

      setState(() {
        _media = mediaDetails;
        _trailerUrl = trailerUrl;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Show trailer as a compact overlay dialog (not fullscreen)
  void _showTrailerPlayer(BuildContext context) {
    if (_trailerUrl == null) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
        child: TrailerOverlay(youtubeUrl: _trailerUrl!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: NivioTheme.netflixBlack,
        appBar: AppBar(backgroundColor: NivioTheme.netflixBlack, elevation: 0),
        body: const Center(
          child: CircularProgressIndicator(color: NivioTheme.netflixRed),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: NivioTheme.netflixBlack,
        appBar: AppBar(backgroundColor: NivioTheme.netflixBlack, elevation: 0),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: NivioTheme.netflixRed,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text('Failed to Load Details'),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: NivioTheme.netflixGrey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _fetchMediaDetails,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NivioTheme.netflixRed,
                ),
                child: const Text('RETRY'),
              ),
            ],
          ),
        ),
      );
    }

    final media = _media;
    if (media == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final tmdbService = ref.read(tmdbServiceProvider);
    final backdropUrl = tmdbService.getBackdropUrl(media.backdropPath);
    final posterUrl = tmdbService.getPosterUrl(media.posterPath);

    // Dynamic colors from poster
    final colorsAsync = ref.watch(dynamicColorsProvider(posterUrl));
    final colors = colorsAsync.valueOrNull ?? DynamicColors.fallback;

    return Scaffold(
      backgroundColor: colors.darkMuted,
      body: CustomScrollView(
        slivers: [
          // Hero section with backdrop
          SliverAppBar(
            expandedHeight: 480,
            pinned: true,
            backgroundColor: colors.darkMuted,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
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

                  // Gradient overlay using dynamic colors
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          colors.darkMuted.withOpacity(0.7),
                          colors.darkMuted,
                        ],
                        stops: const [0.0, 0.7, 1.0],
                      ),
                    ),
                  ),

                  // Title and info at bottom
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          media.title ?? media.name ?? 'Unknown',
                          style: Theme.of(context).textTheme.displayLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.onSurface,
                                shadows: const [
                                  Shadow(blurRadius: 10, color: Colors.black),
                                ],
                              ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (media.voteAverage != null) ...[
                              const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                media.voteAverage!.toStringAsFixed(1),
                                style: TextStyle(color: colors.onSurface),
                              ),
                              const SizedBox(width: 16),
                            ],
                            if (media.releaseDate != null &&
                                media.releaseDate!.length >= 4)
                              Text(
                                media.releaseDate!.substring(0, 4),
                                style: TextStyle(color: colors.onSurface),
                              )
                            else if (media.firstAirDate != null &&
                                media.firstAirDate!.length >= 4)
                              Text(
                                media.firstAirDate!.substring(0, 4),
                                style: TextStyle(color: colors.onSurface),
                              ),
                          ],
                        ),
                        // Trailer button
                        if (_trailerUrl != null) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => _showTrailerPlayer(context),
                            icon: const Icon(Icons.play_circle_outline),
                            label: const Text('Watch Trailer'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.onSurface,
                              side: BorderSide(
                                color: colors.onSurface,
                                width: 2,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overview
                  if (media.overview != null && media.overview!.isNotEmpty) ...[
                    Text(
                      'Overview',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(color: colors.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      media.overview!,
                      style: TextStyle(
                        color: colors.onSurface.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // TV controls or Movie controls
                  if (media.mediaType == 'tv')
                    _buildTVControls(context, media, colors)
                  else
                    _buildMovieControls(context, media, colors),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovieControls(
    BuildContext context,
    SearchResult media,
    DynamicColors colors,
  ) {
    final isInWatchlist = ref.watch(isInWatchlistProvider(media.id));

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () {
              context.push('/player/${media.id}?season=1&episode=1');
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('PLAY'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _toggleWatchlist(media, isInWatchlist),
            icon: Icon(isInWatchlist ? Icons.check : Icons.add, size: 20),
            label: Text(isInWatchlist ? 'SAVED' : 'LIST'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(
                color: isInWatchlist ? colors.dominant : colors.onSurface,
                width: 2,
              ),
              foregroundColor: isInWatchlist
                  ? colors.dominant
                  : colors.onSurface,
            ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Removed from watchlist'),
            duration: Duration(seconds: 2),
          ),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Added to watchlist'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildTVControls(
    BuildContext context,
    SearchResult media,
    DynamicColors colors,
  ) {
    final seriesInfoAsync = ref.watch(seriesInfoProvider(media.id));
    final isInWatchlist = ref.watch(isInWatchlistProvider(media.id));

    return seriesInfoAsync.when(
      data: (seriesInfo) {
        final selectedSeason = ref.watch(selectedSeasonProvider);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Watchlist button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _toggleWatchlist(media, isInWatchlist),
                icon: Icon(isInWatchlist ? Icons.check : Icons.add, size: 20),
                label: Text(isInWatchlist ? 'IN MY LIST' : 'ADD TO MY LIST'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(
                    color: isInWatchlist ? colors.dominant : colors.onSurface,
                    width: 2,
                  ),
                  foregroundColor: isInWatchlist
                      ? colors.dominant
                      : colors.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Season selector
            Text(
              'Select Season',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(color: colors.onSurface),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: selectedSeason <= seriesInfo.seasons.length
                  ? selectedSeason
                  : 1,
              dropdownColor: colors.darkMuted,
              decoration: InputDecoration(
                filled: true,
                fillColor: colors.darkMuted,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: colors.onSurface.withOpacity(0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.dominant, width: 2),
                ),
              ),
              items: seriesInfo.seasons
                  .where((s) => s.seasonNumber > 0)
                  .map(
                    (season) => DropdownMenuItem(
                      value: season.seasonNumber,
                      child: Text(
                        '${season.name} (${season.episodeCount} episodes)',
                        style: TextStyle(color: colors.onSurface),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref.read(selectedSeasonProvider.notifier).state = value;
                  ref.read(selectedEpisodeProvider.notifier).state = 1;
                  setState(() => _episodeSearchQuery = '');
                  _episodeSearchController.clear();
                }
              },
            ),
            const SizedBox(height: 24),

            // Episode list with search
            _buildEpisodeList(media, selectedSeason, colors),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: NivioTheme.netflixRed),
      ),
      error: (err, stack) => Text(
        'Error loading seasons: $err',
        style: TextStyle(color: colors.dominant),
      ),
    );
  }

  Widget _buildEpisodeList(
    SearchResult media,
    int season,
    DynamicColors colors,
  ) {
    final seasonDataAsync = ref.watch(
      seasonDataProvider((showId: media.id, seasonNumber: season)),
    );

    return seasonDataAsync.when(
      data: (seasonData) {
        // Filter episodes by search
        final filteredEpisodes = _episodeSearchQuery.isEmpty
            ? seasonData.episodes
            : seasonData.episodes.where((ep) {
                final query = _episodeSearchQuery.toLowerCase();
                final name = ep.episodeName?.toLowerCase() ?? '';
                final num = ep.episodeNumber.toString();
                return name.contains(query) || num.contains(query);
              }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with episode count
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Episodes',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(color: colors.onSurface),
                ),
                Text(
                  '${seasonData.episodes.length} total',
                  style: TextStyle(color: colors.onSurface.withOpacity(0.6)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Episode search bar
            TextField(
              controller: _episodeSearchController,
              onChanged: (val) => setState(() => _episodeSearchQuery = val),
              style: TextStyle(color: colors.onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search episodes...',
                hintStyle: TextStyle(color: colors.onSurface.withOpacity(0.5)),
                prefixIcon: Icon(
                  Icons.search,
                  color: colors.onSurface.withOpacity(0.5),
                  size: 20,
                ),
                suffixIcon: _episodeSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: colors.onSurface.withOpacity(0.5),
                          size: 18,
                        ),
                        onPressed: () {
                          _episodeSearchController.clear();
                          setState(() => _episodeSearchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colors.lightMuted,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Episode list
            if (filteredEpisodes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off,
                        color: colors.onSurface.withOpacity(0.4),
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No episodes match "$_episodeSearchQuery"',
                        style: TextStyle(
                          color: colors.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...filteredEpisodes.map((episode) {
                return _buildNetflixEpisodeCard(media, episode, season, colors);
              }),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: NivioTheme.netflixRed),
      ),
      error: (err, stack) => Text(
        'Error loading episodes: $err',
        style: TextStyle(color: colors.dominant),
      ),
    );
  }

  Widget _buildNetflixEpisodeCard(
    SearchResult media,
    EpisodeData episode,
    int season,
    DynamicColors colors,
  ) {
    final stillUrl = episode.stillPath != null
        ? 'https://image.tmdb.org/t/p/w500${episode.stillPath}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Episode thumbnail with play button
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: stillUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: stillUrl,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: double.infinity,
                          height: 200,
                          color: colors.lightMuted,
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: NivioTheme.netflixRed,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: double.infinity,
                          height: 200,
                          color: colors.lightMuted,
                          child: Icon(
                            Icons.movie,
                            color: colors.onSurface.withOpacity(0.3),
                            size: 48,
                          ),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        height: 200,
                        color: colors.lightMuted,
                        child: Icon(
                          Icons.movie,
                          color: colors.onSurface.withOpacity(0.3),
                          size: 48,
                        ),
                      ),
              ),
              // Play button overlay
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      context.push(
                        '/player/${media.id}?season=$season&episode=${episode.episodeNumber}',
                      );
                    },
                    child: Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.onSurface, width: 2),
                        ),
                        child: Icon(
                          Icons.play_arrow,
                          color: colors.onSurface,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Episode info
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${episode.episodeNumber}. ',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colors.onSurface,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            episode.episodeName ??
                                'Episode ${episode.episodeNumber}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colors.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (episode.runtime != null && episode.runtime! > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${episode.runtime}m',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      episode.overview != null && episode.overview!.isNotEmpty
                          ? episode.overview!
                          : 'No description available',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurface.withOpacity(0.7),
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: colors.onSurface.withOpacity(0.2), height: 1),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Compact Trailer Overlay — plays raw stream via youtube_explode
// ─────────────────────────────────────────────────────────────────
class TrailerOverlay extends StatefulWidget {
  final String youtubeUrl;

  const TrailerOverlay({super.key, required this.youtubeUrl});

  @override
  State<TrailerOverlay> createState() => _TrailerOverlayState();
}

class _TrailerOverlayState extends State<TrailerOverlay> {
  bool _isLoading = true;
  String? _streamUrl;
  String? _error;

  String? _extractYoutubeVideoId(String url) {
    final regExp = RegExp(
      r'(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }

  @override
  void initState() {
    super.initState();
    _fetchStreamUrl();
  }

  Future<void> _fetchStreamUrl() async {
    final videoId = _extractYoutubeVideoId(widget.youtubeUrl);
    if (videoId == null) {
      if (mounted)
        setState(() {
          _error = 'Invalid YouTube URL';
          _isLoading = false;
        });
      return;
    }

    try {
      final ytClient = yt.YoutubeExplode();
      final manifest = await ytClient.videos.streamsClient.getManifest(videoId);
      ytClient.close();

      // Prefer muxed (video+audio) streams, pick highest quality available
      final muxed = manifest.muxed.sortByVideoQuality();
      if (muxed.isNotEmpty) {
        if (mounted)
          setState(() {
            _streamUrl = muxed.last.url.toString();
            _isLoading = false;
          });
        return;
      }

      // Fallback: video-only
      final videoOnly = manifest.videoOnly.sortByVideoQuality();
      if (videoOnly.isNotEmpty) {
        if (mounted)
          setState(() {
            _streamUrl = videoOnly.last.url.toString();
            _isLoading = false;
          });
        return;
      }

      if (mounted)
        setState(() {
          _error = 'No streams available';
          _isLoading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = 'Failed to load trailer';
          _isLoading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 450),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const AspectRatio(
          aspectRatio: 16 / 9,
          child: Center(
            child: CircularProgressIndicator(
              color: NivioTheme.netflixRed,
              strokeWidth: 3,
            ),
          ),
        ),
      );
    }

    if (_error != null || _streamUrl == null) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 450),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Center(
            child: Text(
              _error ?? 'Unable to play trailer',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    // Play raw stream URL in HTML5 <video> — no YouTube embed, no restrictions
    final videoHtml =
        '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>*{margin:0;padding:0;background:#000}html,body{height:100%;width:100%;overflow:hidden}video{width:100%;height:100%;object-fit:contain}</style>
</head><body>
<video src="${_streamUrl!}" autoplay playsinline controls></video>
</body></html>
''';

    return Container(
      constraints: const BoxConstraints(maxWidth: 700, maxHeight: 450),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: InAppWebView(
                initialData: InAppWebViewInitialData(
                  data: videoHtml,
                  mimeType: 'text/html',
                  encoding: 'utf-8',
                ),
                initialSettings: InAppWebViewSettings(
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  transparentBackground: true,
                  javaScriptEnabled: true,
                ),
              ),
            ),
          ),
          // Close button
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
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
