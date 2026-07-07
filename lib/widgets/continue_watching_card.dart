import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/models/season_info.dart';
import 'package:nivio/models/watch_history.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/service_providers.dart';

class ContinueWatchingCard extends ConsumerStatefulWidget {
  final WatchHistory history;

  const ContinueWatchingCard({super.key, required this.history});

  @override
  ConsumerState<ContinueWatchingCard> createState() => _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends ConsumerState<ContinueWatchingCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  EpisodeData? _episodeData;
  int? _totalEpisodesInSeason;
  bool _showRemoveOverlay = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _elevationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    if (widget.history.mediaType == 'tv' || widget.history.mediaType == 'anime') {
      _fetchEpisodeData();
    }
  }

  @override
  void didUpdateWidget(ContinueWatchingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history.tmdbId != widget.history.tmdbId ||
        oldWidget.history.currentEpisode != widget.history.currentEpisode ||
        oldWidget.history.currentSeason != widget.history.currentSeason) {
      if (widget.history.mediaType == 'tv' || widget.history.mediaType == 'anime') {
        _episodeData = null;
        _fetchEpisodeData();
      }
    }
  }

  Future<void> _fetchEpisodeData() async {
    try {
      if (widget.history.mediaType == 'anime') {
        final anilistService = ref.read(aniListServiceProvider);
        final seasonData = await anilistService.getAnimeSeasonData(widget.history.tmdbId);
        if (mounted) {
          setState(() {
            _totalEpisodesInSeason = seasonData.episodes.length;
            final idx = seasonData.episodes.indexWhere(
                (e) => e.episodeNumber == widget.history.currentEpisode);
            if (idx != -1) {
              _episodeData = seasonData.episodes[idx];
            } else {
              _episodeData = EpisodeData(episodeNumber: widget.history.currentEpisode);
            }
          });
        }
      } else {
        final tmdbService = ref.read(tmdbServiceProvider);
        final seasonData = await tmdbService.getSeasonInfo(
            widget.history.tmdbId, widget.history.currentSeason);
        if (mounted) {
          setState(() {
            _totalEpisodesInSeason = seasonData.episodes.length;
            final idx = seasonData.episodes.indexWhere(
                (e) => e.episodeNumber == widget.history.currentEpisode);
            if (idx != -1) {
              _episodeData = seasonData.episodes[idx];
            } else {
              _episodeData = EpisodeData(episodeNumber: widget.history.currentEpisode);
            }
          });
        }
      }
    } catch (e) {
      // ignore
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tmdbService = ref.watch(tmdbServiceProvider);
    
    String imageUrl = tmdbService.getBackdropUrl(widget.history.posterPath);
    String topTitle = widget.history.title;
    String subtitle = 'Movie';

    if (widget.history.mediaType == 'tv' || widget.history.mediaType == 'anime') {
      final total = _totalEpisodesInSeason ?? widget.history.totalEpisodes ?? 0;
      final totalStr = total > 0 ? '/$total' : '';
      
      String prefix;
      if (widget.history.mediaType == 'tv') {
        prefix = 'S${widget.history.currentSeason} E${widget.history.currentEpisode}';
      } else {
        prefix = 'Episode ${widget.history.currentEpisode}$totalStr';
      }

      if (_episodeData != null) {
        final epName = _episodeData!.episodeName;
        if (_episodeData!.stillPath != null && _episodeData!.stillPath!.isNotEmpty) {
          imageUrl = tmdbService.getBackdropUrl(_episodeData!.stillPath);
        }
        
        // Avoid redundancy if TMDB just returned "Episode X" as the name
        if (epName != null && epName.isNotEmpty && !epName.toLowerCase().startsWith('episode ${widget.history.currentEpisode}')) {
          subtitle = '$prefix - $epName';
        } else {
          subtitle = prefix;
        }
      } else {
        // While loading or if no episode data is available
        subtitle = prefix;
      }
    }

    final remainingSeconds = widget.history.totalDurationSeconds - widget.history.lastPositionSeconds;
    final remainingMinutes = remainingSeconds > 0 ? remainingSeconds ~/ 60 : 0;

    return MouseRegion(
      onEnter: (_) => _animationController.forward(),
      onExit: (_) => _animationController.reverse(),
      child: GestureDetector(
        onTap: () {
          if (_showRemoveOverlay) {
            setState(() => _showRemoveOverlay = false);
            return;
          }
          context.push(
            '/player/${widget.history.tmdbId}'
            '?season=${widget.history.currentSeason}'
            '&episode=${widget.history.currentEpisode}'
            '&type=${widget.history.mediaType}',
          );
        },
        onLongPress: () {
          setState(() => _showRemoveOverlay = true);
        },
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: 220, // Increased width
                margin: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Landscape Thumbnail with progress bar
                    Container(
                      height: 124, // ~16:9 ratio for 220 width
                      width: 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _elevationAnimation.value > 0
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.5 * _elevationAnimation.value),
                                  blurRadius: 15 * _elevationAnimation.value,
                                  spreadRadius: 1 * _elevationAnimation.value,
                                  offset: Offset(0, 6 * _elevationAnimation.value),
                                ),
                              ]
                            : null,
                      ),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: imageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    width: 220,
                                    height: 124,
                                    // Use alignment topCenter so faces in posters are less likely to be cut off
                                    alignment: Alignment.topCenter,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      color: NivioTheme.netflixDarkGrey,
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      color: NivioTheme.netflixDarkGrey,
                                      child: const Icon(Icons.movie, size: 32, color: Colors.grey),
                                    ),
                                  )
                                : Container(
                                    color: NivioTheme.netflixDarkGrey,
                                    child: const Center(
                                      child: Icon(Icons.movie, size: 32, color: Colors.grey),
                                    ),
                                  ),
                          ),
                          // Subtle gradient at bottom for the progress bar
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(10),
                                  bottomRight: Radius.circular(10),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // NO PLAY BUTTON - Removed per request
                          // Progress bar at bottom
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(10),
                                bottomRight: Radius.circular(10),
                              ),
                              child: LinearProgressIndicator(
                                value: widget.history.progressPercent,
                                backgroundColor: Colors.white.withOpacity(0.3),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  NivioTheme.accentColorOf(context),
                                ),
                                minHeight: 2,
                              ),
                            ),
                          ),
                          // Remove Overlay
                          if (_showRemoveOverlay)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: IconButton(
                                    iconSize: 48,
                                    icon: const Icon(Icons.delete_forever_rounded, color: Colors.white),
                                    onPressed: () async {
                                      setState(() => _showRemoveOverlay = false);
                                      final service = ref.read(watchHistoryServiceProvider);
                                      await service.deleteHistory(widget.history.tmdbId);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Removed ${widget.history.title}'),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Main Title (Episode title if TV, Movie title if Movie)
                    Text(
                      topTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Subtitle & Time (Episode X/Y - Series Name    12m)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (remainingMinutes > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '${remainingMinutes}m',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

}
