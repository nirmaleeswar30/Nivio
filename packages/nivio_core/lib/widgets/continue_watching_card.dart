import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/models/season_info.dart';
import 'package:nivio/models/watch_history.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/core/debug_log.dart';
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
          subtitle = '$prefix • $epName';
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
          appDebugLog(
            '🧪 [CW_DEBUG] ContinueWatching tap — media=${widget.history.tmdbId} '
            'type=${widget.history.mediaType} S${widget.history.currentSeason}'
            'E${widget.history.currentEpisode} pos=${widget.history.lastPositionSeconds}s '
            'preferredProvider=${widget.history.preferredProviderIndex}',
          );
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
            final accentColor = NivioTheme.accentColorOf(context);

            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: 220,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF151922),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Landscape Thumbnail with progress bar
                        SizedBox(
                          height: 124,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              imageUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      width: double.infinity,
                                      height: 124,
                                      alignment: Alignment.topCenter,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          const DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Color(0xFF23262E),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                        color: NivioTheme.netflixDarkGrey,
                                        child: const Icon(
                                          Icons.movie,
                                          size: 32,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: NivioTheme.netflixDarkGrey,
                                      child: const Center(
                                        child: Icon(
                                          Icons.movie,
                                          size: 32,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                              // Subtle gradient at bottom for the progress bar
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                height: 28,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.65),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Progress bar at bottom of thumbnail
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: LinearProgressIndicator(
                                  value: widget.history.progressPercent.clamp(0.0, 1.0),
                                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    accentColor,
                                  ),
                                  minHeight: 2.5,
                                ),
                              ),
                              // Quick dismiss/remove button on hover for desktop
                              Positioned(
                                top: 6,
                                right: 6,
                                child: AnimatedOpacity(
                                  opacity: _elevationAnimation.value > 0.3 ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 150),
                                  child: IgnorePointer(
                                    ignoring: _elevationAnimation.value <= 0.3,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () async {
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
                                        child: Container(
                                          padding: const EdgeInsets.all(5),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.7),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white.withValues(alpha: 0.15),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.close_rounded,
                                            size: 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Card Content Info Section
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Main Title
                              Text(
                                topTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.1,
                                ),
                              ),
                              const SizedBox(height: 3),
                              // Subtitle & Time
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.55),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  if (remainingMinutes > 0) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '${remainingMinutes}m left',
                                      style: TextStyle(
                                        color: accentColor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
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

                    // Full Card Remove Overlay (on long press)
                    if (_showRemoveOverlay)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.82),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  iconSize: 42,
                                  icon: const Icon(
                                    Icons.delete_forever_rounded,
                                    color: Colors.white,
                                  ),
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
                                const Text(
                                  'Remove',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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
