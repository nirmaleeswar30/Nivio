import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nivio/widgets/youtube_webview_player.dart';
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
  final void Function(PointerScrollEvent) onScroll;
  final VoidCallback? onPlayAction;

  const HoverPreviewCard({
    super.key,
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.backdropPath,
    this.posterPath,
    required this.onDismiss,
    required this.onScroll,
    this.onPlayAction,
  });

  static final Map<String, Map<String, dynamic>> _detailsCache = {};
  static final Map<String, String?> _trailerCache = {};

  static Future<void> prefetch(WidgetRef ref, int tmdbId, String mediaType, String title) async {
    final cacheKey = '${mediaType}_$tmdbId';
    if (_detailsCache.containsKey(cacheKey)) return;

    try {
      final tmdbService = ref.read(tmdbServiceProvider);
      final Map<String, dynamic> data;
      String? youtubeUrl;

      if (mediaType == 'anime') {
        final anilistService = ref.read(aniListServiceProvider);
        final extras = await anilistService.getAnimeDetailsWithExtras(tmdbId);
        
        data = {
          'title': extras['title']?['english'] ?? extras['title']?['romaji'] ?? title,
          'overview': extras['description'],
          'release_date': extras['seasonYear'] != null ? '${extras['seasonYear']}-01-01' : null,
          'vote_average': extras['averageScore'] != null ? (extras['averageScore'] as num).toDouble() : null,
          'number_of_episodes': extras['episodes'],
          'number_of_seasons': 1,
        };

        try {
          final showTitle = data['title'] ?? '';
          final year = extras['seasonYear']?.toString() ?? '';
          final tmdbInfo = await tmdbService.getMediaInfoByTitle(showTitle, year: year);
          if (tmdbInfo != null) {
            data['backdrop_path'] = tmdbInfo['backdrop_path'];
            data['poster_path'] = tmdbInfo['poster_path'];
          }
        } catch (_) {}

        final trailer = extras['trailer'];
        if (trailer != null && trailer['site']?.toString().toLowerCase() == 'youtube') {
          final trailerKey = trailer['id']?.toString();
          if (trailerKey != null && trailerKey.isNotEmpty) {
            youtubeUrl = 'https://www.youtube.com/watch?v=$trailerKey';
          }
        }
      } else {
        final rawData = mediaType == 'tv'
            ? await tmdbService.getTVShowDetailsWithVideos(tmdbId)
            : await tmdbService.getMovieDetailsWithVideos(tmdbId);
        
        data = Map<String, dynamic>.from(rawData);

        if (data['vote_average'] != null) {
          data['vote_average'] = (data['vote_average'] as num).toDouble() * 10.0;
        }

        final videos = data['videos'];
        if (videos != null) {
          final results = videos['results'] as List<dynamic>?;
          if (results != null && results.isNotEmpty) {
            final candidates = <Map<String, dynamic>>[];
            for (final raw in results) {
              if (raw is! Map<String, dynamic>) continue;
              final site = (raw['site'] as String?)?.trim().toLowerCase();
              final key = (raw['key'] as String?)?.trim();
              if (site == null || key == null || key.isEmpty) continue;
              if (site != 'youtube') continue;

              int score = 0;
              final type = (raw['type'] as String?)?.toLowerCase() ?? '';
              if (type == 'trailer') score += 50;
              else if (type == 'teaser') score += 35;
              else if (type == 'clip') score += 20;
              if (raw['official'] == true) score += 20;

              candidates.add({'key': key, 'score': score});
            }
            if (candidates.isNotEmpty) {
              candidates.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
              final bestKey = candidates.first['key'] as String;
              youtubeUrl = 'https://www.youtube.com/watch?v=$bestKey';
            }
          }
        }
      }

      _detailsCache[cacheKey] = data;
      _trailerCache[cacheKey] = youtubeUrl;
    } catch (_) {}
  }

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

  bool _playerInitialized = false;
  String? _youtubeVideoId;
  final GlobalKey<YouTubeWebViewPlayerState> _ytPlayerKey = GlobalKey();

  bool _isMuted = true;
  bool _isPlaying = true;
  bool _showPlayPauseFeedback = false;
  Timer? _feedbackTimer;
  bool _isVideoPlaying = false;

  void _toggleMute() {
    if (_ytPlayerKey.currentState == null) return;
    setState(() {
      _isMuted = !_isMuted;
      if (_isMuted) {
        _ytPlayerKey.currentState!.mute();
      } else {
        _ytPlayerKey.currentState!.unMute();
        _ytPlayerKey.currentState!.setVolume(100);
      }
    });
  }

  void _togglePlayPause() {
    if (_ytPlayerKey.currentState == null) return;
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _ytPlayerKey.currentState!.play();
      } else {
        _ytPlayerKey.currentState!.pause();
      }
      _showPlayPauseFeedback = true;
    });
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showPlayPauseFeedback = false;
        });
      }
    });
  }

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

    // Check cache first for instant loading
    final cacheKey = '${widget.mediaType}_${widget.tmdbId}';
    if (HoverPreviewCard._detailsCache.containsKey(cacheKey)) {
      _details = HoverPreviewCard._detailsCache[cacheKey];
      _isLoading = false;
      final cachedTrailer = HoverPreviewCard._trailerCache[cacheKey];
      if (cachedTrailer != null) {
        _initPlayer(cachedTrailer);
      }
    } else {
      _fetchDetails();
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  void _initPlayer(String youtubeUrl) {
    if (_playerInitialized) return;
    
    // Extract video ID from YouTube URL
    final uri = Uri.tryParse(youtubeUrl);
    String? videoId;
    if (uri != null) {
      videoId = uri.queryParameters['v'];
      if (videoId == null && uri.host.contains('youtu.be')) {
        videoId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      }
    }
    
    if (videoId == null || videoId.isEmpty) return;
    
    _youtubeVideoId = videoId;
    _playerInitialized = true;
    _isVideoPlaying = false;
    
    if (mounted) setState(() {});
  }

  Future<void> _fetchDetails() async {
    try {
      final tmdbService = ref.read(tmdbServiceProvider);
      final Map<String, dynamic> data;
      String? youtubeUrl;

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

        final trailer = extras['trailer'];
        if (trailer != null && trailer['site']?.toString().toLowerCase() == 'youtube') {
          final trailerKey = trailer['id']?.toString();
          if (trailerKey != null && trailerKey.isNotEmpty) {
            youtubeUrl = 'https://www.youtube.com/watch?v=$trailerKey';
          }
        }
      } else {
        final rawData = widget.mediaType == 'tv'
            ? await tmdbService.getTVShowDetailsWithVideos(widget.tmdbId)
            : await tmdbService.getMovieDetailsWithVideos(widget.tmdbId);
        
        data = Map<String, dynamic>.from(rawData);

        if (data['vote_average'] != null) {
          data['vote_average'] = (data['vote_average'] as num).toDouble() * 10.0;
        }

        // Extract best trailer
        final videos = data['videos'];
        if (videos != null) {
          final results = videos['results'] as List<dynamic>?;
          if (results != null && results.isNotEmpty) {
            // Score and pick best trailer
            final candidates = <Map<String, dynamic>>[];
            for (final raw in results) {
              if (raw is! Map<String, dynamic>) continue;
              final site = (raw['site'] as String?)?.trim().toLowerCase();
              final key = (raw['key'] as String?)?.trim();
              if (site == null || key == null || key.isEmpty) continue;
              if (site != 'youtube') continue;

              int score = 0;
              final type = (raw['type'] as String?)?.toLowerCase() ?? '';
              if (type == 'trailer') score += 50;
              else if (type == 'teaser') score += 35;
              else if (type == 'clip') score += 20;
              if (raw['official'] == true) score += 20;

              candidates.add({'key': key, 'score': score});
            }
            if (candidates.isNotEmpty) {
              candidates.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
              final bestKey = candidates.first['key'] as String;
              youtubeUrl = 'https://www.youtube.com/watch?v=$bestKey';
            }
          }
        }
      }

      final cacheKey = '${widget.mediaType}_${widget.tmdbId}';
      HoverPreviewCard._detailsCache[cacheKey] = data;
      HoverPreviewCard._trailerCache[cacheKey] = youtubeUrl;

      if (mounted) {
        setState(() {
          _details = data;
          _isLoading = false;
        });
        if (youtubeUrl != null) {
          _initPlayer(youtubeUrl);
        }
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
    if (widget.mediaType == 'anime') {
      parts.add('Anime');
    } else if (widget.mediaType == 'tv') {
      parts.add('TV Series');
    } else {
      parts.add('Movie');
    }

    // Episodes / Runtime
    if (widget.mediaType == 'tv' || widget.mediaType == 'anime') {
      final numEpisodes = d['number_of_episodes'];
      final numSeasons = d['number_of_seasons'];
      if (numSeasons != null) {
        parts.add('$numSeasons Season${numSeasons > 1 ? 's' : ''}');
      }
      if (numEpisodes != null) {
        parts.add('$numEpisodes Eps');
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

    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final isInWatchlist = ref.watch(isInWatchlistProvider(widget.tmdbId));
    final resolvedBackdrop = widget.backdropPath ?? _details?['backdrop_path'];
    final backdropUrl = resolvedBackdrop != null
        ? (resolvedBackdrop.startsWith('http')
            ? resolvedBackdrop
            : '$tmdbImageBaseUrl/w780$resolvedBackdrop')
        : null;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Listener(
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              widget.onScroll?.call(pointerSignal);
            }
          },
          child: MouseRegion(
            onExit: (_) => widget.onDismiss(),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                widget.onDismiss();
                if (widget.onPlayAction != null) {
                  widget.onPlayAction!();
                } else {
                  context.push('/media/${widget.tmdbId}?type=${widget.mediaType}');
                }
              },
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 250,
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
                      height: 141, // 16:9 aspect for 250 width
                      width: 250,
                      child: _buildMediaSection(backdropUrl),
                    ),

                    // ── Info Section ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
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

                          Row(
                            children: [
                              // Play / Continue button
                              Expanded(
                                child: SizedBox(
                                  height: 30,
                                  child: _AnimatedHoverScale(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        widget.onDismiss();
                                        if (widget.onPlayAction != null) {
                                          widget.onPlayAction!();
                                        } else {
                                          context.push('/media/${widget.tmdbId}?type=${widget.mediaType}');
                                        }
                                      },
                                      icon: const Icon(Icons.play_arrow, size: 18),
                                      label: const Text('Watch Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.black,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Favourite Heart Icon
                              _ActionIconButton(
                                icon: isInWatchlist ? Icons.favorite : Icons.favorite_border,
                                iconColor: isInWatchlist ? const Color(0xFFE50914) : Colors.white,
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
                              const SizedBox(width: 4),
                              // Watchlist Plus/Check Icon
                              _ActionIconButton(
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
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
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
    ),
    ),
    );
  }

  Widget _buildMediaSection(String? backdropUrl) {
    if (_playerInitialized && _youtubeVideoId != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: _togglePlayPause,
            behavior: HitTestBehavior.opaque,
            child: YouTubeWebViewPlayer(
              key: _ytPlayerKey,
              videoId: _youtubeVideoId!,
              autoPlay: true,
              muted: true,
              showControls: false,
              loop: true,
              onStateChanged: (state) {
                // state 1 = playing
                if (state == 1 && !_isVideoPlaying && mounted) {
                  setState(() => _isVideoPlaying = true);
                }
              },
            ),
          ),
          // Show backdrop image until video starts rendering
          if (!_isVideoPlaying && backdropUrl != null)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: backdropUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: const Color(0xFF2F2F2F)),
                errorWidget: (context, url, error) => Container(
                  color: const Color(0xFF2F2F2F),
                  child: const Icon(Icons.movie, color: Colors.white24, size: 48),
                ),
              ),
            ),
          // Gradient overlay (fades to solid Color(0xFF181818))
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      const Color(0xFF181818).withOpacity(0.1),
                      const Color(0xFF181818),
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Mute control at top right
          Positioned(
            top: 8,
            right: 8,
            child: _MiniControlCircleButton(
              icon: _isMuted ? Icons.volume_off : Icons.volume_up,
              onPressed: _toggleMute,
            ),
          ),
          // Play/Pause feedback in the center
          if (_showPlayPauseFeedback)
            Center(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _showPlayPauseFeedback ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPlaying ? Icons.play_arrow : Icons.pause,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

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
          // Gradient overlay (fades to solid Color(0xFF181818))
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      const Color(0xFF181818).withOpacity(0.1),
                      const Color(0xFF181818),
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
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

  String _cleanHtml(String text) {
    return text.replaceAll(RegExp(r'<[^>]*>'), '');
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final VoidCallback onPressed;

  const _ActionIconButton({
    required this.icon,
    this.iconColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return _AnimatedHoverScale(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Icon(icon, color: iconColor ?? Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _MiniControlCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _MiniControlCircleButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey[700]!, width: 1.0),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}

class _AnimatedHoverScale extends StatefulWidget {
  final Widget child;
  const _AnimatedHoverScale({required this.child});

  @override
  State<_AnimatedHoverScale> createState() => _AnimatedHoverScaleState();
}

class _AnimatedHoverScaleState extends State<_AnimatedHoverScale> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _isHovered ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
