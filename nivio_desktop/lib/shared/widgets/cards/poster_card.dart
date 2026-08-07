import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/index.dart';
import '../common/animated_fade_container.dart';
import '../native_trailer_preview.dart';

class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    this.mediaId,
    required this.title,
    this.imageProvider,
    this.previewImageProvider,
    this.year,
    this.rating,
    this.subtitle,
    this.overview,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.isLoading = false,
    this.onPlay,
    this.onWatchlist,
    this.isInWatchlist = false,
    this.onMore,
    this.progress,
  });

  final String? mediaId;
  final String title;
  final ImageProvider? imageProvider;
  final ImageProvider? previewImageProvider;
  final String? year;
  final String? rating;
  final String? subtitle;
  final String? overview;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSecondaryTap;
  final bool isLoading;
  final VoidCallback? onPlay;
  final VoidCallback? onWatchlist;
  final bool isInWatchlist;
  final VoidCallback? onMore;
  final double? progress;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  static Offset? _lastPointerPosition;
  static _PosterCardState? _activeOverlayOwner;

  final GlobalKey _targetKey = GlobalKey();

  OverlayEntry? _overlayEntry;
  Timer? _showTimer;
  Timer? _postScrollHoverTimer;
  ScrollPosition? _horizontalScrollPosition;
  ScrollPosition? _verticalScrollPosition;
  _PosterCardLayout? _latestLayout;
  Offset? _overlayOffset;
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isDeactivated = false;
  bool _isScrolling = false;

  bool get _isActive => _isHovered || _isFocused;

  @override
  void didUpdateWidget(covariant PosterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_overlayEntry != null) {
      _scheduleOverlayUpdate();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncScrollPosition(
      current: _horizontalScrollPosition,
      next: Scrollable.maybeOf(context, axis: Axis.horizontal)?.position,
      update: (position) => _horizontalScrollPosition = position,
    );
    _syncScrollPosition(
      current: _verticalScrollPosition,
      next: Scrollable.maybeOf(context, axis: Axis.vertical)?.position,
      update: (position) => _verticalScrollPosition = position,
    );
    _isScrolling = _isAnyScrollPositionActive;
  }

  @override
  void activate() {
    super.activate();
    _isDeactivated = false;
  }

  @override
  void deactivate() {
    _isDeactivated = true;
    _showTimer?.cancel();
    _removeOverlay();
    super.deactivate();
  }

  @override
  void dispose() {
    _horizontalScrollPosition?.isScrollingNotifier.removeListener(
      _onScrollChanged,
    );
    _verticalScrollPosition?.isScrollingNotifier.removeListener(
      _onScrollChanged,
    );
    _showTimer?.cancel();
    _postScrollHoverTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  bool get _isAnyScrollPositionActive =>
      (_horizontalScrollPosition?.isScrollingNotifier.value ?? false) ||
      (_verticalScrollPosition?.isScrollingNotifier.value ?? false);

  void _syncScrollPosition({
    required ScrollPosition? current,
    required ScrollPosition? next,
    required ValueChanged<ScrollPosition?> update,
  }) {
    if (identical(current, next)) return;
    current?.isScrollingNotifier.removeListener(_onScrollChanged);
    update(next);
    next?.isScrollingNotifier.addListener(_onScrollChanged);
  }

  void _onScrollChanged() {
    final scrolling = _isAnyScrollPositionActive;
    if (_isScrolling == scrolling) return;
    _isScrolling = scrolling;
    if (scrolling) {
      _cancelHoverForScroll();
    } else {
      _scheduleHoverFromPointerPosition();
    }
  }

  void _cancelHoverForScroll() {
    _showTimer?.cancel();
    _postScrollHoverTimer?.cancel();
    _removeOverlay();
    if ((_isHovered || _isFocused) && mounted && !_isDeactivated) {
      setState(() {
        _isHovered = false;
        _isFocused = false;
      });
    }
  }

  void _handleOverlayPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _lastPointerPosition = event.position;
    final position = _scrollPositionForPointerDelta(event.scrollDelta);
    if (position == null) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (
      resolvedEvent,
    ) {
      if (resolvedEvent is PointerScrollEvent) {
        position.pointerScroll(
          _scrollDeltaForPosition(position, resolvedEvent.scrollDelta),
        );
        _forceCloseHover();
      }
    });
  }

  void _forceCloseHover() {
    _showTimer?.cancel();
    _postScrollHoverTimer?.cancel();
    _removeOverlay();
    if (mounted && !_isDeactivated) {
      setState(() {
        _isHovered = false;
        _isFocused = false;
      });
    }
  }

  ScrollPosition? _scrollPositionForPointerDelta(Offset delta) {
    final verticalDelta = delta.dy;
    final horizontalDelta = delta.dx;
    final preferVertical = verticalDelta.abs() >= horizontalDelta.abs();
    final verticalPosition = _resolveScrollPosition(Axis.vertical);
    final horizontalPosition = _resolveScrollPosition(Axis.horizontal);

    if (preferVertical) {
      return _scrollablePositionForDelta(verticalPosition, verticalDelta) ??
          _scrollablePositionForDelta(horizontalPosition, verticalDelta) ??
          _scrollablePositionForDelta(horizontalPosition, horizontalDelta);
    }

    return _scrollablePositionForDelta(horizontalPosition, horizontalDelta) ??
        _scrollablePositionForDelta(verticalPosition, verticalDelta);
  }

  ScrollPosition? _resolveScrollPosition(Axis axis) {
    final targetContext = _targetKey.currentContext;
    final resolved = targetContext == null
        ? null
        : Scrollable.maybeOf(targetContext, axis: axis)?.position;
    return resolved ??
        switch (axis) {
          Axis.horizontal => _horizontalScrollPosition,
          Axis.vertical => _verticalScrollPosition,
        };
  }

  ScrollPosition? _scrollablePositionForDelta(
    ScrollPosition? position,
    double delta,
  ) {
    if (position == null || delta == 0 || !position.hasPixels) {
      return null;
    }
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (target == position.pixels) return null;
    return position;
  }

  double _scrollDeltaForPosition(ScrollPosition position, Offset delta) {
    if (identical(position, _resolveScrollPosition(Axis.vertical))) {
      return delta.dy;
    }
    if (delta.dx != 0 && delta.dx.abs() > delta.dy.abs()) {
      return delta.dx;
    }
    return delta.dy;
  }

  void _setHovered(bool value) {
    if (!mounted || _isDeactivated) return;
    if (value && _isScrolling) return;
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
    _syncOverlay();
  }

  void _setFocused(bool value) {
    if (!mounted || _isDeactivated) return;
    if (_isFocused == value) return;
    setState(() => _isFocused = value);
    _syncOverlay();
  }

  void _handlePointerEnter(PointerEnterEvent event) {
    _lastPointerPosition = event.position;
    _removeOtherActiveOverlay();
    _setHovered(true);
  }

  void _handlePointerHover(PointerHoverEvent event) {
    _lastPointerPosition = event.position;
    _removeOtherActiveOverlay();
    if (!_isHovered) _setHovered(true);
  }

  void _handlePointerExit(PointerExitEvent event) {
    _lastPointerPosition = event.position;
    _closeHoverIfPointerOutside(event.position);
  }

  void _closeHoverIfPointerOutside(Offset globalPosition) {
    if (_isPointerOverHoverRegion(globalPosition)) return;
    _forceCloseHover();
  }

  void _scheduleHoverFromPointerPosition() {
    _postScrollHoverTimer?.cancel();
    _postScrollHoverTimer = Timer(const Duration(milliseconds: 90), () {
      if (!mounted || _isDeactivated || _isScrolling || _isHovered) return;
      final pointerPosition = _lastPointerPosition;
      if (pointerPosition == null || !_isPointerOverCard(pointerPosition)) {
        return;
      }
      _setHovered(true);
    });
  }

  bool _isPointerOverCard(Offset globalPosition) {
    final targetContext = _targetKey.currentContext;
    if (targetContext == null || !targetContext.mounted) return false;
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final targetBox = renderObject;
    final localPosition = targetBox.globalToLocal(globalPosition);
    return (Offset.zero & targetBox.size).contains(localPosition);
  }

  bool _isPointerOverOverlay(Offset globalPosition) {
    final layout = _latestLayout;
    final offset = _overlayOffset;
    if (layout == null || offset == null) return false;
    final overlayContext = Overlay.maybeOf(context)?.context;
    if (overlayContext == null || !overlayContext.mounted) return false;
    final renderObject = overlayContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final overlayBox = renderObject;
    final localPosition = overlayBox.globalToLocal(globalPosition);
    return Rect.fromLTWH(
      offset.dx,
      offset.dy,
      layout.expandedWidth,
      layout.availableHeight,
    ).contains(localPosition);
  }

  bool _isPointerOverHoverRegion(Offset globalPosition) {
    return _isPointerOverCard(globalPosition) ||
        _isPointerOverOverlay(globalPosition);
  }

  void _scheduleOverlayUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDeactivated || !_isActive || _isScrolling) {
        return;
      }
      _showOrUpdateOverlay();
    });
  }

  void _scheduleDelayedOverlay() {
    _showTimer?.cancel();
    if (_isScrolling) return;
    _showTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || _isDeactivated || !_isActive || _isScrolling) return;
      _scheduleOverlayUpdate();
    });
  }

  void _syncOverlay() {
    _showTimer?.cancel();
    if (_isActive) {
      if (_overlayEntry != null) {
        _scheduleOverlayUpdate();
      } else {
        _scheduleDelayedOverlay();
      }
      return;
    }

    final pointerPosition = _lastPointerPosition;
    if (pointerPosition != null && _isPointerOverHoverRegion(pointerPosition)) {
      _setHovered(true);
      return;
    }
    _removeOverlay();
  }

  void _showOrUpdateOverlay() {
    if (!mounted || _isDeactivated || _isScrolling) {
      return;
    }
    _removeOtherActiveOverlay();

    final layout = _latestLayout;
    if (layout == null || !layout.canShowDetails) return;

    final targetContext = _targetKey.currentContext;
    if (targetContext == null || !targetContext.mounted) {
      return;
    }

    final overlay = Overlay.maybeOf(context);
    final overlayContext = overlay?.context;
    if (overlay == null || overlayContext == null) {
      return;
    }

    final targetRenderObject = targetContext.findRenderObject();
    final overlayRenderObject = overlayContext.findRenderObject();
    if (targetRenderObject is! RenderBox ||
        overlayRenderObject is! RenderBox ||
        !targetRenderObject.hasSize ||
        !overlayRenderObject.hasSize) {
      return;
    }
    final targetBox = targetRenderObject;
    final overlayBox = overlayRenderObject;

    final targetOffset = targetBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final targetBottom = targetOffset.dy + targetBox.size.height;
    if (targetBottom <= 0 || targetOffset.dy >= overlayBox.size.height) {
      _removeOverlay();
      return;
    }
    final maxLeft = (overlayBox.size.width - layout.expandedWidth).clamp(
      0.0,
      double.infinity,
    );
    final maxTop = (overlayBox.size.height - layout.availableHeight).clamp(
      0.0,
      double.infinity,
    );
    _overlayOffset = Offset(
      (targetOffset.dx - ((layout.expandedWidth - layout.baseWidth) / 2))
          .clamp(0.0, maxLeft)
          .toDouble(),
      (targetOffset.dy - 6).clamp(0.0, maxTop).toDouble(),
    );

    if (_overlayEntry == null) {
      _activeOverlayOwner = this;
      _overlayEntry = OverlayEntry(builder: _buildOverlay);
      overlay.insert(_overlayEntry!);
    } else {
      _activeOverlayOwner = this;
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _overlayOffset = null;
    if (identical(_activeOverlayOwner, this)) {
      _activeOverlayOwner = null;
    }
  }

  void _removeOtherActiveOverlay() {
    final activeOwner = _activeOverlayOwner;
    if (activeOwner == null || identical(activeOwner, this)) return;
    activeOwner
      .._showTimer?.cancel()
      .._postScrollHoverTimer?.cancel()
      .._removeOverlay();
    if (activeOwner.mounted && !activeOwner._isDeactivated) {
      activeOwner.setState(() {
        activeOwner._isHovered = false;
        activeOwner._isFocused = false;
      });
    }
  }

  void _handleOverlayDetailsPressed() {
    final openDetails = widget.onMore ?? widget.onSecondaryTap ?? widget.onTap;
    _forceCloseHover();
    openDetails?.call();
  }

  Widget _buildOverlay(BuildContext context) {
    final layout = _latestLayout;
    final offset = _overlayOffset;
    if (layout == null || offset == null || !layout.canShowDetails) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      width: layout.expandedWidth,
      height: layout.availableHeight,
      child: Listener(
        onPointerSignal: _handleOverlayPointerSignal,
        child: MouseRegion(
          cursor: SystemMouseCursors.basic,
          onEnter: (event) {
            _lastPointerPosition = event.position;
            _setHovered(true);
          },
          onHover: (event) {
            _lastPointerPosition = event.position;
            if (!_isHovered) _setHovered(true);
          },
          onExit: (event) {
            _lastPointerPosition = event.position;
            _closeHoverIfPointerOutside(event.position);
          },
          child: _HoverUplift(
            child: Material(
              color: Colors.transparent,
              child: _ExpandedPosterTrayCard(
                mediaId: widget.mediaId,
                title: widget.title,
                imageProvider:
                    widget.previewImageProvider ?? widget.imageProvider,
                isLoading: widget.isLoading,
                subtitle: widget.subtitle,
                year: widget.year,
                rating: widget.rating,
                overview: widget.overview,
                isInWatchlist: widget.isInWatchlist,
                onPlay: widget.onPlay ?? widget.onTap,
                onWatchlist: widget.onWatchlist,
                onOpenDetail: widget.onTap,
                onMore: _handleOverlayDetailsPressed,
                progress: widget.progress,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 236.0;
        final availableHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : baseWidth / AppBreakpoints.posterRatio;
        final compactHeight = (baseWidth / AppBreakpoints.posterRatio)
            .clamp(0.0, availableHeight)
            .toDouble();
        final maxExpandedHeight = availableHeight
            .clamp(compactHeight, compactHeight > 460 ? compactHeight : 460.0)
            .toDouble();
        final expandedHeight = (compactHeight + 112)
            .clamp(compactHeight, maxExpandedHeight)
            .toDouble();
        final expandedWidth = (baseWidth * 1.46)
            .clamp(baseWidth, 356.0)
            .toDouble();
        final canShowDetails = availableHeight >= 220 && baseWidth >= 140;
        _latestLayout = _PosterCardLayout(
          baseWidth: baseWidth,
          compactHeight: compactHeight,
          availableHeight: expandedHeight,
          expandedWidth: expandedWidth,
          canShowDetails: canShowDetails,
        );

        return FocusableActionDetector(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: _setFocused,
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onTap?.call();
                return null;
              },
            ),
          },
          child: Semantics(
            label: widget.semanticLabel ?? widget.title,
            button: widget.onTap != null,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: _handlePointerEnter,
              onHover: _handlePointerHover,
              onExit: _handlePointerExit,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                onDoubleTap: widget.onDoubleTap,
                onSecondaryTap: widget.onSecondaryTap,
                child: SizedBox(
                  key: _targetKey,
                  width: baseWidth,
                  height: compactHeight,
                  child: _CompactPosterTrayCard(
                    title: widget.title,
                    imageProvider: widget.imageProvider,
                    isLoading: widget.isLoading,
                    progress: widget.progress,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HoverUplift extends StatelessWidget {
  const _HoverUplift({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 190),
      curve: AppAnimation.emphasized,
      builder: (context, value, child) {
        final easedOpacity = Curves.easeOut.transform(value);
        return Opacity(
          opacity: easedOpacity,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: Transform.scale(
              scale: 0.975 + (value * 0.025),
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class _PosterCardLayout {
  const _PosterCardLayout({
    required this.baseWidth,
    required this.compactHeight,
    required this.availableHeight,
    required this.expandedWidth,
    required this.canShowDetails,
  });

  final double baseWidth;
  final double compactHeight;
  final double availableHeight;
  final double expandedWidth;
  final bool canShowDetails;
}

class _CompactPosterTrayCard extends StatelessWidget {
  const _CompactPosterTrayCard({
    required this.title,
    required this.imageProvider,
    required this.isLoading,
    required this.progress,
  });

  final String title;
  final ImageProvider? imageProvider;
  final bool isLoading;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _PosterArtwork(
          title: title,
          imageProvider: imageProvider,
          isLoading: isLoading,
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        if (progress != null && progress! > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppRadius.medium),
              ),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: progress!.clamp(0.0, 1.0),
                backgroundColor: Colors.white24,
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }
}

class _ExpandedPosterTrayCard extends StatelessWidget {
  const _ExpandedPosterTrayCard({
    required this.mediaId,
    required this.title,
    required this.imageProvider,
    required this.isLoading,
    required this.subtitle,
    required this.year,
    required this.rating,
    required this.overview,
    required this.isInWatchlist,
    required this.onPlay,
    required this.onWatchlist,
    required this.onOpenDetail,
    required this.onMore,
    required this.progress,
  });

  final String? mediaId;
  final String title;
  final ImageProvider? imageProvider;
  final bool isLoading;
  final String? subtitle;
  final String? year;
  final String? rating;
  final String? overview;
  final bool isInWatchlist;
  final VoidCallback? onPlay;
  final VoidCallback? onWatchlist;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onMore;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF171B24),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.62),
              blurRadius: 38,
              spreadRadius: -8,
              offset: const Offset(0, 22),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 58,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _PosterArtwork(
                      title: title,
                      imageProvider: imageProvider,
                      isLoading: isLoading,
                      borderRadius: BorderRadius.zero,
                    ),
                    NativeTrailerPreviewOverlay(
                      mediaId: mediaId,
                      isLoading: isLoading,
                    ),
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x00000000),
                              Color(0x33000000),
                              Color(0xD9171B24),
                            ],
                            stops: [0, 0.58, 1],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      bottom: AppSpacing.sm,
                      child: IgnorePointer(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.title.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            shadows: const [
                              Shadow(color: Color(0xCC000000), blurRadius: 12),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 42,
                child: _PosterHoverPanel(
                  title: title,
                  subtitle: subtitle,
                  year: year,
                  rating: rating,
                  overview: overview,
                  isInWatchlist: isInWatchlist,
                  onPlay: onPlay,
                  onWatchlist: onWatchlist,
                  onMore: onMore ?? onOpenDetail,
                  progress: progress,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterArtwork extends StatelessWidget {
  const _PosterArtwork({
    required this.title,
    required this.imageProvider,
    required this.isLoading,
    required this.borderRadius,
  });

  final String title;
  final ImageProvider? imageProvider;
  final bool isLoading;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    if (imageProvider == null || isLoading) {
      return _Placeholder(borderRadius: borderRadius);
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image(
        image: imageProvider!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return _Placeholder(borderRadius: borderRadius);
        },
        errorBuilder: (context, error, stackTrace) =>
            _Placeholder(errorState: true, borderRadius: borderRadius),
      ),
    );
  }
}

class _PosterHoverPanel extends StatelessWidget {
  const _PosterHoverPanel({
    required this.title,
    required this.subtitle,
    required this.year,
    required this.rating,
    required this.overview,
    required this.isInWatchlist,
    required this.onPlay,
    required this.onWatchlist,
    required this.onMore,
    required this.progress,
  });

  final String title;
  final String? subtitle;
  final String? year;
  final String? rating;
  final String? overview;
  final bool isInWatchlist;
  final VoidCallback? onPlay;
  final VoidCallback? onWatchlist;
  final VoidCallback? onMore;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final metadata = <String>[
      if (year != null && year!.isNotEmpty) year!,
      if (rating != null && rating!.isNotEmpty) rating!,
      if (subtitle != null && subtitle!.isNotEmpty) subtitle!,
    ];
    final description = overview?.trim().isNotEmpty == true
        ? overview!.trim()
        : title;

    return ColoredBox(
      color: const Color(0xFF171B24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _TrayActionButton.primary(
                    icon: Icons.play_arrow_rounded,
                    label: 'Watch Now',
                    onPressed: onPlay,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _TrayIconButton(
                  icon: isInWatchlist ? Icons.check_rounded : Icons.add_rounded,
                  tooltip: isInWatchlist ? 'In watchlist' : 'Add to watchlist',
                  onPressed: onWatchlist,
                ),
                const SizedBox(width: AppSpacing.sm),
                _TrayIconButton(
                  icon: Icons.info_outline_rounded,
                  tooltip: 'Details',
                  onPressed: onMore,
                ),
              ],
            ),
            if (metadata.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                metadata.join('  •  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textPrimary.withValues(alpha: 0.86),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.28,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (progress != null && progress! > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  value: progress!.clamp(0.0, 1.0),
                  backgroundColor: Colors.white24,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrayActionButton extends StatelessWidget {
  const _TrayActionButton._({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.primary,
  });

  const _TrayActionButton.primary({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) : this._(icon: icon, label: label, onPressed: onPressed, primary: true);

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          borderRadius: BorderRadius.circular(AppRadius.small),
          child: AnimatedContainer(
            duration: AppAnimation.hover,
            curve: AppAnimation.standard,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: primary
                  ? AppColors.textPrimary.withValues(
                      alpha: enabled ? 0.92 : 0.42,
                    )
                  : AppColors.surfaceVariant.withValues(
                      alpha: enabled ? 0.92 : 0.42,
                    ),
              borderRadius: BorderRadius.circular(AppRadius.small),
              border: Border.all(
                color: primary
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: primary ? AppColors.background : AppColors.textPrimary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.title.copyWith(
                      color: primary
                          ? AppColors.background
                          : AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrayIconButton extends StatelessWidget {
  const _TrayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          borderRadius: BorderRadius.circular(AppRadius.small),
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant.withValues(
                alpha: enabled ? 0.92 : 0.42,
              ),
              borderRadius: BorderRadius.circular(AppRadius.small),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(icon, size: 21, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.borderRadius, this.errorState = false});

  final BorderRadius borderRadius;
  final bool errorState;

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: errorState
          ? [AppColors.surfaceVariant, AppColors.surface]
          : [AppColors.surfaceVariant, AppColors.background],
    );

    return Container(
      decoration: BoxDecoration(gradient: gradient, borderRadius: borderRadius),
      child: Center(
        child: AnimatedFadeContainer(
          visible: true,
          child: Icon(
            errorState ? Icons.broken_image_outlined : Icons.image_outlined,
            color: AppColors.textMuted,
            size: 40,
          ),
        ),
      ),
    );
  }
}
