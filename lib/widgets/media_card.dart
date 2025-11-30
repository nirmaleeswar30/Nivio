import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/models/watch_history.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/service_providers.dart';

class MediaCard extends ConsumerStatefulWidget {
  final WatchHistory history;

  const MediaCard({super.key, required this.history});

  @override
  ConsumerState<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends ConsumerState<MediaCard> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    
    _elevationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tmdbService = ref.watch(tmdbServiceProvider);
    final posterUrl = tmdbService.getPosterUrl(widget.history.posterPath);

    return MouseRegion(
      onEnter: (_) => _animationController.forward(),
      onExit: (_) => _animationController.reverse(),
      child: GestureDetector(
        onTap: () {
          context.push(
            '/player/${widget.history.tmdbId}'
            '?season=${widget.history.currentSeason}'
            '&episode=${widget.history.currentEpisode}'
            '&type=${widget.history.mediaType}',
          );
        },
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: 130,
                margin: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Poster with progress bar
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5 * _elevationAnimation.value),
                            blurRadius: 15 * _elevationAnimation.value,
                            spreadRadius: 1 * _elevationAnimation.value,
                            offset: Offset(0, 6 * _elevationAnimation.value),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: posterUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: posterUrl,
                                    height: 180,
                                    width: 130,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      color: NivioTheme.netflixDarkGrey,
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          color: NivioTheme.netflixRed,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      color: NivioTheme.netflixDarkGrey,
                                      child: const Icon(
                                        Icons.movie,
                                        color: NivioTheme.netflixGrey,
                                        size: 48,
                                      ),
                                    ),
                                  )
                                : Container(
                                    height: 180,
                                    width: 130,
                                    color: NivioTheme.netflixDarkGrey,
                                    child: const Icon(
                                      Icons.movie,
                                      color: NivioTheme.netflixGrey,
                                      size: 48,
                                    ),
                                  ),
                          ),
                          // Progress bar at bottom
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(
                              value: widget.history.progressPercent,
                              backgroundColor: Colors.grey.withOpacity(0.3),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                NivioTheme.netflixRed,
                              ),
                            ),
                          ),
                          // Play icon overlay with animation
                          Positioned.fill(
                            child: AnimatedOpacity(
                              opacity: 0.6 + (0.4 * _elevationAnimation.value),
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.7),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.white,
                                  size: 48 + (8 * _elevationAnimation.value),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Title
                    Text(
                      widget.history.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    // Episode info for TV shows
                    if (widget.history.mediaType == 'tv')
                      Text(
                        'S${widget.history.currentSeason} E${widget.history.currentEpisode}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NivioTheme.netflixGrey,
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
