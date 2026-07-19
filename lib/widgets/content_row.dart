import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/widgets/hover_preview_card.dart';

class ContentRow extends StatelessWidget {
  final String title;
  final List<dynamic> items;
  final double? leftPadding;

  const ContentRow({
    super.key,
    required this.title,
    required this.items,
    this.leftPadding,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: leftPadding ?? (isDesktop ? 68 : 16), right: 16),
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
            height: isDesktop ? 210 : 180,
            child: AppListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(
                left: leftPadding != null 
                    ? (leftPadding! - (isDesktop ? 16 : 4)).clamp(0.0, double.infinity) 
                    : (isDesktop ? 64 : 12), 
                right: 12,
              ),
              itemCount: items.length,
              cacheExtent: 250,
              scrollSpeed: 2.0,
              silkyScrollDuration: const Duration(milliseconds: 500),
              animationCurve: Curves.easeOutQuart,
              itemBuilder: (context, index) {
                final item = items[index];
                String? posterPath;
                String? backdropPath;
                int tmdbId = 0;
                String mediaType = 'movie';
                String title = '';

                if (item is SearchResult) {
                  posterPath = item.posterPath;
                  backdropPath = item.backdropPath;
                  tmdbId = item.id;
                  mediaType = item.mediaType;
                  title = item.title ?? item.name ?? '';
                } else if (item is Map) {
                  posterPath = item['poster_path'];
                  backdropPath = item['backdrop_path'];
                  tmdbId = item['id'];
                  mediaType = item['media_type'] ?? (item['title'] != null ? 'movie' : 'tv');
                  title = (item['title'] ?? item['name'] ?? '').toString();
                }

                return Padding(
                   padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 4),
                   child: _AnimatedPosterCard(
                     posterPath: posterPath,
                     backdropPath: backdropPath,
                     tmdbId: tmdbId,
                     mediaType: mediaType,
                     title: title,
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
  final String? backdropPath;
  final int tmdbId;
  final String mediaType;
  final String title;

  const _AnimatedPosterCard({
    required this.posterPath,
    this.backdropPath,
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

  final GlobalKey _cardKey = GlobalKey();
  Timer? _hoverTimer;
  Timer? _dismissTimer;
  final LayerLink _layerLink = LayerLink();

  static OverlayEntry? _activeOverlay;
  static _AnimatedPosterCardState? _activeCardState;

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

  void _showOverlay([VoidCallback? onPlayAction]) {
    if (!mounted) return;
    
    // Dismiss any existing overlay first
    _dismissActiveOverlay();

    final renderBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final hoverWidth = 250.0;
    final hoverHeight = 260.0;

    // Centered on the card horizontally and vertically
    // ignore: unused_local_variable
    final left = (position.dx + size.width / 2) - hoverWidth / 2;
    // ignore: unused_local_variable
    final top = (position.dy + size.height / 2) - hoverHeight / 2;

    _activeCardState = this;
    _activeOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: hoverWidth,
          height: hoverHeight,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.center,
            followerAnchor: Alignment.center,
            child: HoverPreviewCard(
              tmdbId: widget.tmdbId,
              mediaType: widget.mediaType,
              title: widget.title,
              backdropPath: widget.backdropPath,
              posterPath: widget.posterPath,
              onDismiss: _dismissOverlay,
              onPlayAction: onPlayAction,
              onScroll: (event) {
                try {
                  if (event.scrollDelta.dx != 0) {
                    final scrollable = Scrollable.of(_cardKey.currentContext!, axis: Axis.horizontal);
                    final pos = scrollable.position;
                    pos.jumpTo((pos.pixels + event.scrollDelta.dx).clamp(
                      pos.minScrollExtent,
                      pos.maxScrollExtent,
                    ));
                  }
                  if (event.scrollDelta.dy != 0) {
                    final scrollable = Scrollable.of(_cardKey.currentContext!, axis: Axis.vertical);
                    final pos = scrollable.position;
                    pos.jumpTo((pos.pixels + event.scrollDelta.dy).clamp(
                      pos.minScrollExtent,
                      pos.maxScrollExtent,
                    ));
                  }
                } catch (_) {}
              },
            ),
          ),
        );
      },
    );

    Overlay.of(_cardKey.currentContext!).insert(_activeOverlay!);
  }

  void _dismissOverlay() {
    _activeOverlay?.remove();
    _activeOverlay = null;
    _activeCardState = null;
  }

  static void _dismissActiveOverlay() {
    _activeCardState?._dismissTimer?.cancel();
    _activeCardState?._hoverTimer?.cancel();
    _activeOverlay?.remove();
    _activeOverlay = null;
    _activeCardState = null;
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _dismissTimer?.cancel();
    if (_activeCardState == this) {
      _dismissOverlay();
    }
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isInWatchlist = ref.watch(isInWatchlistProvider(widget.tmdbId));
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    final activePath = widget.posterPath;
    final sizeSegment = isDesktop ? 'original' : posterSize;

    final staticImageContent = activePath != null
        ? CachedNetworkImage(
            imageUrl: activePath.startsWith('http') 
                ? activePath 
                : '$tmdbImageBaseUrl/$sizeSegment$activePath',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            memCacheWidth: 360,
            imageBuilder: (context, imageProvider) => Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                image: DecorationImage(
                  image: imageProvider,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            placeholder: (context, url) => Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2F2F2F),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFE50914),
                  strokeWidth: 2,
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2F2F2F),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.movie,
                color: Colors.white30,
                size: 40,
              ),
            ),
          )
        : Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2F2F2F),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(
              Icons.movie,
              color: Colors.white30,
              size: 40,
            ),
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
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
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

    void action() {
      GoRouter.of(context).push('/media/${widget.tmdbId}?type=${widget.mediaType}');
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
            onEnter: (_) {
              _animationController.forward();
              if (isDesktop) {
                _dismissTimer?.cancel();
                if (_activeCardState == this) return;
                _hoverTimer?.cancel();
                
                // Prefetch details and trailer URL immediately on hover enter
                unawaited(HoverPreviewCard.prefetch(ref, widget.tmdbId, widget.mediaType, widget.title));
                
                _hoverTimer = Timer(const Duration(milliseconds: 500), () {
                  _showOverlay(action);
                });
              }
            },
            onExit: (event) {
              _animationController.reverse();
              if (isDesktop) {
                _hoverTimer?.cancel();
                if (_activeCardState == this) {
                  // Check if cursor is inside the hover overlay bounds
                  final renderBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
                  if (renderBox != null) {
                    final position = renderBox.localToGlobal(Offset.zero);
                    final size = renderBox.size;
                    final hoverWidth = 250.0;
                    final hoverHeight = 260.0;
                    final left = (position.dx + size.width / 2) - hoverWidth / 2;
                    final top = (position.dy + size.height / 2) - hoverHeight / 2;
                    final hoverRect = Rect.fromLTWH(left, top, hoverWidth, hoverHeight);
                    
                    if (hoverRect.contains(event.position)) {
                      // Cursor is over the hover preview overlay, don't dismiss
                      return;
                    }
                  }
      
                  _dismissTimer?.cancel();
                  _dismissTimer = Timer(const Duration(milliseconds: 200), () {
                    _dismissOverlay();
                  });
                }
              }
            },
            child: GestureDetector(
              onTap: () {
                _dismissActiveOverlay();
                action();
              },
              child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  key: _cardKey,
                  width: isDesktop ? 140 : 120,
                  height: isDesktop ? 210 : 180,
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
                              borderRadius: BorderRadius.circular(4),
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
              );
            },
            child: imageWithTitle,
          ),
        ),
      ),
    );
  }
}
