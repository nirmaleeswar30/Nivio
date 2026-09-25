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
  final VoidCallback? onSeeAll;
  final String? seeAllLabel;

  const ContentRow({
    super.key,
    required this.title,
    required this.items,
    this.leftPadding,
    this.onSeeAll,
    this.seeAllLabel,
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
            padding: EdgeInsets.only(
              left: leftPadding ?? (isDesktop ? 68 : 16),
              right: 16,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (onSeeAll != null)
                  InkWell(
                    onTap: onSeeAll,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            seeAllLabel ?? 'See All',
                            style: TextStyle(
                              color: NivioTheme.accentColorOf(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 11,
                            color: NivioTheme.accentColorOf(context),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
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

class _AnimatedPosterCardState extends ConsumerState<_AnimatedPosterCard> {
  bool _isHovered = false;

  final GlobalKey _cardKey = GlobalKey();
  Timer? _hoverTimer;
  Timer? _dismissTimer;
  final LayerLink _layerLink = LayerLink();

  static OverlayEntry? _activeOverlay;
  static _AnimatedPosterCardState? _activeCardState;

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
              onScroll: (event) => _applyHoverScroll(event.scrollDelta),
              onPanScroll: _applyHoverScroll,
            ),
          ),
        );
      },
    );

    Overlay.of(_cardKey.currentContext!).insert(_activeOverlay!);
  }

  // Forward a scroll delta (from the hover preview's mouse wheel OR trackpad
  // pan) to the underlying horizontal row / vertical page scrollables, so the
  // app keeps scrolling while a hover preview is open.
  void _applyHoverScroll(Offset delta) {
    final ctx = _cardKey.currentContext;
    if (ctx == null) return;
    try {
      if (delta.dx != 0) {
        final pos = Scrollable.of(ctx, axis: Axis.horizontal).position;
        pos.jumpTo((pos.pixels + delta.dx)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent));
      }
      if (delta.dy != 0) {
        final pos = Scrollable.of(ctx, axis: Axis.vertical).position;
        pos.jumpTo((pos.pixels + delta.dy)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent));
      }
    } catch (_) {}
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isInWatchlist = ref.watch(isInWatchlistProvider(widget.tmdbId));
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    final activePath = widget.posterPath;
    final sizeSegment = isDesktop ? 'original' : posterSize;

    final staticImageContent = activePath != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CachedNetworkImage(
              imageUrl: activePath.startsWith('http') 
                  ? activePath 
                  : '$tmdbImageBaseUrl/$sizeSegment$activePath',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              memCacheWidth: 360,
              // Static skeleton-gray placeholder (no per-image spinner/animation
              // controller) so shelves stay light on GPU while posters load in.
              placeholder: (context, url) => const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFF23262E)),
              ),
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFF2F2F2F),
                child: const Icon(
                  Icons.movie,
                  color: Colors.white30,
                  size: 40,
                ),
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
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _isHovered = true);
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
          setState(() => _isHovered = false);
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
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              key: _cardKey,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: isDesktop ? 140 : 120,
              height: isDesktop ? 210 : 170,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: const Color(0xFF2F2F2F),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    // Poster Image (cached statically)
                    Positioned.fill(child: imageWithTitle),
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
          ),
        ),
      ),
    );
  }
}
