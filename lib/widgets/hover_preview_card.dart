import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/services/watchlist_service.dart';
import 'package:nivio/models/watchlist_item.dart';

/// A Netflix-style hover preview popup that appears when hovering over a shelf card on desktop.
/// Shows a premium backdrop preview, title, action buttons, metadata, and overview.
class HoverPreviewCard extends ConsumerStatefulWidget {
  final int tmdbId;
  final String mediaType;
  final String title;
  final String? backdropPath;
  final String? posterPath;
  final VoidCallback onDismiss;

  const HoverPreviewCard({
    super.key,
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.backdropPath,
    this.posterPath,
    required this.onDismiss,
  });

  @override
  ConsumerState<HoverPreviewCard> createState() => _HoverPreviewCardState();
}

class _HoverPreviewCardState extends ConsumerState<HoverPreviewCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  Map<String, dynamic>? _details;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _fadeController.forward();
    _fetchDetails();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetails() async {
    try {
      final tmdbService = ref.read(tmdbServiceProvider);
      final Map<String, dynamic> data;

      if (widget.mediaType == 'anime') {
        final anilistService = ref.read(aniListServiceProvider);
        final extras = await anilistService.getAnimeDetailsWithExtras(widget.tmdbId);
        
        data = {
          'title': extras['title']?['english'] ?? extras['title']?['romaji'] ?? widget.title,
          'overview': extras['description'],
          'release_date': extras['seasonYear'] != null ? '${extras['seasonYear']}-01-01' : null,
          'vote_average': extras['averageScore'] != null ? (extras['averageScore'] as num).toDouble() : null,
          'number_of_episodes': extras['episodes'],
          'number_of_seasons': 1,
        };

        // Try to fetch TMDB backdrop/poster mapping for better visual presentation
        try {
          final title = data['title'] ?? '';
          final year = extras['seasonYear']?.toString() ?? '';
          final tmdbInfo = await tmdbService.getMediaInfoByTitle(title, year: year);
          if (tmdbInfo != null) {
            data['backdrop_path'] = tmdbInfo['backdrop_path'];
            data['poster_path'] = tmdbInfo['poster_path'];
          }
        } catch (_) {}
      } else {
        final rawData = widget.mediaType == 'tv'
            ? await tmdbService.getTVShowDetailsWithVideos(widget.tmdbId)
            : await tmdbService.getMovieDetailsWithVideos(widget.tmdbId);
        
        data = Map<String, dynamic>.from(rawData);

        if (data['vote_average'] != null) {
          data['vote_average'] = (data['vote_average'] as num).toDouble() * 10.0;
        }
      }

      if (mounted) {
        setState(() {
          _details = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('HoverPreviewCard fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _buildMetadataLine() {
    final parts = <String>[];
    final d = _details;
    if (d == null) return '';

    // Media type
    if (widget.mediaType == 'tv' || widget.mediaType == 'anime') {
      parts.add('TV Series');
    } else {
      parts.add('Movie');
    }

    // Episodes / Runtime
    if (widget.mediaType == 'tv' || widget.mediaType == 'anime') {
      final numEpisodes = d['number_of_episodes'];
      final numSeasons = d['number_of_seasons'];
      if (numSeasons != null && numEpisodes != null) {
        parts.add('$numSeasons Season${numSeasons > 1 ? 's' : ''} · $numEpisodes Episodes');
      }
    } else {
      final runtime = d['runtime'];
      if (runtime != null && runtime > 0) {
        final h = runtime ~/ 60;
        final m = runtime % 60;
        parts.add(h > 0 ? '${h}h ${m}m' : '${m}m');
      }
    }

    // Year
    final date = d['release_date'] ?? d['first_air_date'];
    if (date != null && date.toString().length >= 4) {
      parts.add(date.toString().substring(0, 4));
    }

    // Rating
    final rating = d['vote_average'];
    if (rating != null && rating > 0) {
      parts.add('${(rating as num).toStringAsFixed(0)}%');
    }

    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final isInWatchlist = ref.watch(isInWatchlistProvider(widget.tmdbId));
    final backdropUrl = widget.backdropPath != null
        ? '$tmdbImageBaseUrl/w780${widget.backdropPath}'
        : null;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: MouseRegion(
          onExit: (_) => widget.onDismiss(),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 350,
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.7),
                    blurRadius: 24,
                    spreadRadius: 4,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Trailer / Backdrop ──
                    SizedBox(
                      height: 197, // 16:9 aspect for 350 width
                      width: 350,
                      child: _buildMediaSection(backdropUrl),
                    ),

                    // ── Info Section ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Action row
                          Row(
                            children: [
                              // Play / Continue button
                              Expanded(
                                child: SizedBox(
                                  height: 36,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      widget.onDismiss();
                                      context.push('/media/${widget.tmdbId}?type=${widget.mediaType}');
                                    },
                                    icon: const Icon(Icons.play_arrow, size: 20),
                                    label: const Text('Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Favourite / Watchlist
                              _ActionCircleButton(
                                icon: isInWatchlist ? Icons.check : Icons.add,
                                onPressed: () async {
                                  final watchlistService = ref.read(watchlistServiceProvider);
                                  if (isInWatchlist) {
                                    await watchlistService.removeFromWatchlist(widget.tmdbId);
                                  } else {
                                    final item = WatchlistItem(
                                      id: widget.tmdbId,
                                      title: widget.title,
                                      posterPath: widget.posterPath,
                                      mediaType: widget.mediaType,
                                      addedAt: DateTime.now(),
                                      voteAverage: _details?['vote_average']?.toDouble(),
                                      releaseDate: (_details?['release_date'] ?? _details?['first_air_date'])?.toString(),
                                      overview: _details?['overview']?.toString(),
                                    );
                                    await watchlistService.addToWatchlist(item);
                                  }
                                  ref.read(watchlistRefreshProvider.notifier).refresh();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Metadata line
                          if (!_isLoading && _details != null)
                            Text(
                              _buildMetadataLine(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),

                          // Overview
                          if (!_isLoading && _details != null && _details!['overview'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: ShaderMask(
                                shaderCallback: (rect) => const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.white, Colors.white, Colors.transparent],
                                  stops: [0.0, 0.6, 1.0],
                                ).createShader(rect),
                                blendMode: BlendMode.dstIn,
                                child: Text(
                                  _details!['overview'] as String,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaSection(String? backdropUrl) {
    if (backdropUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: backdropUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            placeholder: (context, url) => Container(color: const Color(0xFF2F2F2F)),
            errorWidget: (context, url, error) => Container(
              color: const Color(0xFF2F2F2F),
              child: const Icon(Icons.movie, color: Colors.white24, size: 48),
            ),
          ),
          // Gradient overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF181818).withOpacity(0.8),
                  ],
                ),
              ),
            ),
          ),
          // Play indicator overlay
          const Center(
            child: Icon(
              Icons.play_circle_fill,
              color: Colors.white,
              size: 48,
            ),
          ),
        ],
      );
    }

    // No image at all
    return Container(
      color: const Color(0xFF2F2F2F),
      child: const Center(
        child: Icon(Icons.movie, color: Colors.white24, size: 48),
      ),
    );
  }
}

class _ActionCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _ActionCircleButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey[600]!, width: 1.5),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
