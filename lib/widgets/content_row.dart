import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nivio/core/constants.dart';

class ContentRow extends StatelessWidget {
  final String title;
  final List<dynamic> items;

  const ContentRow({
    super.key,
    required this.title,
    required this.items,
  });

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
              itemBuilder: (context, index) {
                final item = items[index];
                final posterPath = item['poster_path'];
                final tmdbId = item['id'];
                final mediaType = item['media_type'] ?? 
                    (item['title'] != null ? 'movie' : 'tv');

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _AnimatedPosterCard(
                    posterPath: posterPath,
                    tmdbId: tmdbId,
                    mediaType: mediaType,
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

class _AnimatedPosterCard extends StatefulWidget {
  final String? posterPath;
  final int tmdbId;
  final String mediaType;

  const _AnimatedPosterCard({
    required this.posterPath,
    required this.tmdbId,
    required this.mediaType,
  });

  @override
  State<_AnimatedPosterCard> createState() => _AnimatedPosterCardState();
}

class _AnimatedPosterCardState extends State<_AnimatedPosterCard> with SingleTickerProviderStateMixin {
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
    return MouseRegion(
      onEnter: (_) {
        _animationController.forward();
      },
      onExit: (_) {
        _animationController.reverse();
      },
      child: GestureDetector(
        onTap: () => context.push('/media/${widget.tmdbId}?type=${widget.mediaType}'),
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
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5 * _elevationAnimation.value),
                      blurRadius: 15 * _elevationAnimation.value,
                      spreadRadius: 1 * _elevationAnimation.value,
                      offset: Offset(0, 6 * _elevationAnimation.value),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      // Poster Image
                      widget.posterPath != null
                          ? CachedNetworkImage(
                              imageUrl: '$tmdbImageBaseUrl/$posterSize${widget.posterPath}',
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
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
                            ),
                      // Hover Overlay with Play Icon
                      AnimatedOpacity(
                        opacity: _elevationAnimation.value,
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
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
