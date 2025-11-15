import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/season_info.dart';
import 'package:nivio/providers/media_provider.dart';
import 'package:nivio/services/tmdb_service.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

class MediaDetailScreen extends ConsumerStatefulWidget {
  final int mediaId;
  final String? mediaType;

  const MediaDetailScreen({
    super.key,
    required this.mediaId,
    this.mediaType,
  });

  @override
  ConsumerState<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends ConsumerState<MediaDetailScreen> {
  SearchResult? _media;
  bool _isLoading = true;
  String? _error;
  String? _trailerUrl;

  @override
  void initState() {
    super.initState();
    _fetchMediaDetails();
  }

  @override
  void dispose() {
    super.dispose();
  }

  String? _extractTrailerKey(dynamic videosData) {
    if (videosData == null) return null;
    
    final results = videosData['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;
    
    // ONLY get official trailers - nothing else
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
      // Otherwise, fetch from TMDB
      final tmdbService = TmdbService();
      Map<String, dynamic>? detailsWithVideos;
      
      // Use mediaType if provided, otherwise try both
      if (widget.mediaType == 'movie') {
        detailsWithVideos = await tmdbService.getMovieDetailsWithVideos(widget.mediaId);
        detailsWithVideos['media_type'] = 'movie';
        final movieDetails = SearchResult.fromJson(detailsWithVideos);
        ref.read(selectedMediaProvider.notifier).state = movieDetails;
        setState(() {
          _media = movieDetails;
        });
      } else if (widget.mediaType == 'tv') {
        detailsWithVideos = await tmdbService.getTVShowDetailsWithVideos(widget.mediaId);
        detailsWithVideos['media_type'] = 'tv';
        final tvDetails = SearchResult.fromJson(detailsWithVideos);
        ref.read(selectedMediaProvider.notifier).state = tvDetails;
        setState(() {
          _media = tvDetails;
        });
      } else {
        // Try movie first, then TV show
        try {
          detailsWithVideos = await tmdbService.getMovieDetailsWithVideos(widget.mediaId);
          detailsWithVideos['media_type'] = 'movie';
          final movieDetails = SearchResult.fromJson(detailsWithVideos);
          ref.read(selectedMediaProvider.notifier).state = movieDetails;
          setState(() {
            _media = movieDetails;
          });
        } catch (e) {
          // If movie fails, try TV show
          detailsWithVideos = await tmdbService.getTVShowDetailsWithVideos(widget.mediaId);
          detailsWithVideos['media_type'] = 'tv';
          final tvDetails = SearchResult.fromJson(detailsWithVideos);
          ref.read(selectedMediaProvider.notifier).state = tvDetails;
          setState(() {
            _media = tvDetails;
          });
        }
      }

      // Extract trailer URL
      final trailerUrl = _extractTrailerKey(detailsWithVideos['videos']);
      if (trailerUrl != null) {
        setState(() {
          _trailerUrl = trailerUrl;
        });
      }

      setState(() {
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
    if (_trailerUrl == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => TrailerPlayer(youtubeUrl: _trailerUrl!),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: NivioTheme.netflixBlack,
        appBar: AppBar(
          backgroundColor: NivioTheme.netflixBlack,
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: NivioTheme.netflixRed,
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: NivioTheme.netflixBlack,
        appBar: AppBar(
          backgroundColor: NivioTheme.netflixBlack,
          elevation: 0,
        ),
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

    final tmdbService = TmdbService();
    final backdropUrl = tmdbService.getBackdropUrl(media.backdropPath);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero section with backdrop
          SliverAppBar(
            expandedHeight: 500,
            pinned: true,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Backdrop image
                  if (backdropUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: backdropUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Container(
                        color: NivioTheme.netflixDarkGrey,
                      ),
                    )
                  else
                    Container(color: NivioTheme.netflixDarkGrey),
                  
                  // Gradient overlay (stronger for readability)
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.7),
                          NivioTheme.netflixBlack,
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
                              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  const Shadow(
                                    blurRadius: 10,
                                    color: Colors.black,
                                  ),
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
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                  const SizedBox(width: 16),
                                ],
                                if (media.releaseDate != null && media.releaseDate!.length >= 4)
                                  Text(
                                    media.releaseDate!.substring(0, 4),
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  )
                                else if (media.firstAirDate != null && media.firstAirDate!.length >= 4)
                                  Text(
                                    media.firstAirDate!.substring(0, 4),
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                              ],
                            ),
                            // Watch Trailer button (if trailer available)
                            if (_trailerUrl != null) ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () => _showTrailerPlayer(context),
                                icon: const Icon(Icons.play_circle_outline),
                                label: const Text('Watch Trailer'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white, width: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                      Text(
                        media.overview!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                    ],

                    // For TV shows - Season/Episode selection
                    if (media.mediaType == 'tv')
                      _buildTVControls(context, media)
                    else
                      _buildMovieControls(context, media),
                  ],
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildMovieControls(BuildContext context, SearchResult media) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          context.push('/player/${media.id}?season=1&episode=1');
        },
        icon: const Icon(Icons.play_arrow),
        label: const Text('PLAY'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildTVControls(BuildContext context, SearchResult media) {
    final seriesInfoAsync = ref.watch(seriesInfoProvider(media.id));

    return seriesInfoAsync.when(
      data: (seriesInfo) {
        final selectedSeason = ref.watch(selectedSeasonProvider);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Season selector
            Text(
              'Select Season',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: selectedSeason <= seriesInfo.seasons.length
                  ? selectedSeason
                  : 1,
              dropdownColor: NivioTheme.netflixDarkGrey,
              decoration: const InputDecoration(
                filled: true,
                fillColor: NivioTheme.netflixDarkGrey,
              ),
              items: seriesInfo.seasons
                  .where((s) => s.seasonNumber > 0)
                  .map((season) => DropdownMenuItem(
                        value: season.seasonNumber,
                        child: Text(
                          '${season.name} (${season.episodeCount} episodes)',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref.read(selectedSeasonProvider.notifier).state = value;
                  ref.read(selectedEpisodeProvider.notifier).state = 1;
                }
              },
            ),
            const SizedBox(height: 24),

            // Episode list
            _buildEpisodeList(media, selectedSeason),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: NivioTheme.netflixRed),
      ),
      error: (err, stack) => Text(
        'Error loading seasons: $err',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: NivioTheme.netflixRed,
            ),
      ),
    );
  }

  Widget _buildEpisodeList(SearchResult media, int season) {
    final seasonDataAsync = ref.watch(
      seasonDataProvider((showId: media.id, seasonNumber: season)),
    );

    return seasonDataAsync.when(
      data: (seasonData) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Episodes',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            ...seasonData.episodes.map((episode) {
              return _buildNetflixEpisodeCard(media, episode, season);
            }),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: NivioTheme.netflixRed),
      ),
      error: (err, stack) => Text(
        'Error loading episodes: $err',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: NivioTheme.netflixRed,
            ),
      ),
    );
  }

  Widget _buildNetflixEpisodeCard(SearchResult media, EpisodeData episode, int season) {
    final stillUrl = episode.stillPath != null 
        ? 'https://image.tmdb.org/t/p/w500${episode.stillPath}'
        : '';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Episode thumbnail with play button overlay
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
                          color: Colors.black.withOpacity(0.3),
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
                          color: Colors.black.withOpacity(0.3),
                          child: const Icon(Icons.movie, color: Colors.white54, size: 48),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        height: 200,
                        color: Colors.black.withOpacity(0.3),
                        child: const Icon(Icons.movie, color: Colors.white54, size: 48),
                      ),
              ),
              // Play button overlay
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      context.push(
                        '/player/${media.id}'
                        '?season=$season'
                        '&episode=${episode.episodeNumber}',
                      );
                    },
                    child: Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
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
          // Episode info row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Episode number and title
                    Row(
                      children: [
                        Text(
                          '${episode.episodeNumber}. ',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            episode.episodeName ?? 'Episode ${episode.episodeNumber}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // Runtime
                    if (episode.runtime != null && episode.runtime! > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${episode.runtime}m',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Description
                    Text(
                      episode.overview != null && episode.overview!.isNotEmpty
                          ? episode.overview!
                          : 'No description available',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[400],
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
          // Divider
          Divider(
            color: Colors.grey[800],
            height: 1,
            thickness: 1,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// Trailer Player Widget with YouTube support
class TrailerPlayer extends StatefulWidget {
  final String youtubeUrl;

  const TrailerPlayer({super.key, required this.youtubeUrl});

  @override
  State<TrailerPlayer> createState() => _TrailerPlayerState();
}

class _TrailerPlayerState extends State<TrailerPlayer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      // Extract YouTube video ID from URL
      final videoId = _extractYoutubeVideoId(widget.youtubeUrl);
      if (videoId == null) {
        setState(() {
          _error = 'Invalid YouTube URL';
          _isLoading = false;
        });
        return;
      }

      // Use youtube_explode_dart to get the actual video stream URL
      final youtubeClient = yt.YoutubeExplode();
      try {
        final manifest = await youtubeClient.videos.streamsClient.getManifest(videoId);
        
        // Get the best muxed stream (video + audio combined)
        final streamInfo = manifest.muxed.withHighestBitrate();
        final streamUrl = streamInfo.url.toString();
        
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(streamUrl),
          httpHeaders: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        );

        await _videoController!.initialize();

        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: true,
          looping: false,
          allowFullScreen: true,
          allowMuting: true,
          showControls: true,
          materialProgressColors: ChewieProgressColors(
            playedColor: NivioTheme.netflixRed,
            handleColor: NivioTheme.netflixRed,
            backgroundColor: Colors.grey,
            bufferedColor: Colors.white30,
          ),
          placeholder: Container(
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(
                color: NivioTheme.netflixRed,
              ),
            ),
          ),
          errorBuilder: (context, errorMessage) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: NivioTheme.netflixRed,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to play trailer',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    errorMessage,
                    style: const TextStyle(color: NivioTheme.netflixGrey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        );

        setState(() {
          _isLoading = false;
        });
      } finally {
        youtubeClient.close();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String? _extractYoutubeVideoId(String url) {
    final regExp = RegExp(
      r'(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Trailer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Video player
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: NivioTheme.netflixRed,
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: NivioTheme.netflixRed,
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Unable to load trailer',
                              style: TextStyle(color: Colors.white, fontSize: 18),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: const TextStyle(color: NivioTheme.netflixGrey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : _chewieController != null
                        ? Chewie(controller: _chewieController!)
                        : const Center(
                            child: Text(
                              'Video player not initialized',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
