import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/models/search_result.dart';

class ContentRow extends StatelessWidget {
  final String title;
  final List<dynamic> items;

  const ContentRow({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: items.length,
              cacheExtent: 200,
              itemBuilder: (context, index) {
                final item = items[index];
                String? posterPath;
                int tmdbId = 0;
                String mediaType = 'movie';
                String title = '';

                if (item is SearchResult) {
                  posterPath = item.posterPath;
                  tmdbId = item.id;
                  mediaType = item.mediaType;
                  title = item.title ?? item.name ?? '';
                } else if (item is Map) {
                  posterPath = item['poster_path'];
                  tmdbId = item['id'];
                  mediaType = item['media_type'] ?? (item['title'] != null ? 'movie' : 'tv');
                  title = (item['title'] ?? item['name'] ?? '').toString();
                  debugPrint('📋 ContentRow [$title]: id=$tmdbId, media_type=${item['media_type']}, resolved=$mediaType, has_title=${item['title'] != null}, has_name=${item['name'] != null}');
                }

                return RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _AnimatedPosterCard(
                      posterPath: posterPath,
                      tmdbId: tmdbId,
                      mediaType: mediaType,
                      title: title,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedPosterCard extends ConsumerStatefulWidget {
  final String? posterPath;
  final int tmdbId;
  final String mediaType;
  final String title;

  const _AnimatedPosterCard({
    required this.posterPath,
    required this.tmdbId,
    required this.mediaType,
    required this.title,
  });

  @override
  ConsumerState<_AnimatedPosterCard> createState() =>
      _AnimatedPosterCardState();
}

class _AnimatedPosterCardState extends ConsumerState<_AnimatedPosterCard>
    with SingleTickerProviderStateMixin {
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

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
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
    final isInWatchlist = ref.watch(isInWatchlistProvider(widget.tmdbId));

    final staticImageContent = widget.posterPath != null
        ? CachedNetworkImage(
            imageUrl: widget.posterPath!.startsWith('http') 
                ? widget.posterPath! 
                : '$tmdbImageBaseUrl/$posterSize${widget.posterPath}',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            memCacheWidth: 360,
            placeholder: (context, url) => Container(
              color: const Color(0xFF2F2F2F),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFE50914),
                  strokeWidth: 2,
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: const Color(0xFF2F2F2F),
              child: const Icon(
                Icons.movie,
                color: Colors.white30,
                size: 40,
              ),
            ),
          )
        : const Icon(
            Icons.movie,
            color: Colors.white30,
            size: 40,
          );

    final imageWithTitle = Stack(
      fit: StackFit.expand,
      children: [
        staticImageContent,
        if (widget.title.isNotEmpty && widget.mediaType == 'anime')
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                    Colors.black,
                  ],
                ),
              ),
              child: Text(
                widget.title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ),
          ),
      ],
    );

    return MouseRegion(
      onEnter: (_) {
        _animationController.forward();
      },
      onExit: (_) {
        _animationController.reverse();
      },
      child: GestureDetector(
        onTap: () =>
            context.push('/media/${widget.tmdbId}?type=${widget.mediaType}'),
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: 120,
                height: 170,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: const Color(0xFF2F2F2F),
                  boxShadow: _elevationAnimation.value > 0
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: 0.5 * _elevationAnimation.value,
                            ),
                            blurRadius: 15 * _elevationAnimation.value,
                            spreadRadius: 1 * _elevationAnimation.value,
                            offset: Offset(0, 6 * _elevationAnimation.value),
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      // Poster Image (cached statically)
                      Positioned.fill(child: child!),
                      
                      // Hover Overlay with Play Icon
                      if (_elevationAnimation.value > 0)
                        Opacity(
                          opacity: _elevationAnimation.value,
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
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.play_circle_fill,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                          ),
                        ),
                      if (isInWatchlist)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: NivioTheme.accentColorOf(
                                context,
                              ).withValues(alpha: 0.95),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
          child: imageWithTitle,
        ),
      ),
    );
  }
}
