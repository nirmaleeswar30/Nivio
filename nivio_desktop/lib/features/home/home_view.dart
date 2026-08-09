import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/constants/providers_data.dart';
import '../../core/network/image/tmdb_image_builder.dart';
import '../../shared/theme/index.dart';
import '../../shared/widgets/widgets.dart';
import '../library/services/watchlist_sync_controller.dart';
import '../player/models/playback_request.dart';
import '../player/playback_request_factory.dart';
import '../providers/models/provider_models.dart';
import '../search/models/search_media_item.dart';
import 'controllers/home_controller.dart';

class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.controller,
    this.onOpenDetail,
    this.onPlay,
    this.onOpenAllProviders,
    this.onOpenProvider,
    this.onOpenSection,
  });

  final HomeController controller;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;
  final VoidCallback? onOpenAllProviders;
  final ValueChanged<StreamingProviderItem>? onOpenProvider;
  final ValueChanged<String>? onOpenSection;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final ScrollController _scrollController = ScrollController();
  late final PageController _pageController;
  Timer? _carouselTimer;
  int _currentPage = 0;
  Timer? _resumeAutoplayTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _startCarouselTimer();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _carouselTimer?.cancel();
    _resumeAutoplayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startCarouselTimer() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (!mounted) return;
      if (!_pageController.hasClients) return;

      final items = widget.controller.featuredItems;
      if (items.isEmpty) return;

      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _onPageUserInteraction() {
    _carouselTimer?.cancel();
    _resumeAutoplayTimer?.cancel();
    _resumeAutoplayTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        _startCarouselTimer();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final ctrl = widget.controller;
        final featuredItems = ctrl.featuredItems;

        return DesktopScrollbar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FeaturedMasthead(
                  controller: _pageController,
                  scrollController: _scrollController,
                  items: featuredItems,
                  currentPage: _currentPage,
                  isLoading: ctrl.isLoadingFeatured,
                  onUserInteraction: _onPageUserInteraction,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });

                    if (index == featuredItems.length) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!_pageController.hasClients) {
                          return;
                        }
                        _pageController.jumpToPage(0);
                        setState(() => _currentPage = 0);
                      });
                    }
                  },
                  onPlay: widget.onPlay,
                ),
                ColoredBox(
                  color: AppColors.background,
                  child: PageContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionPadding(
                          vertical: AppSpacing.md,
                          child: _ContinueWatchingSection(
                            items: ctrl.watchHistory,
                            isLoading: ctrl.isLoadingHistory,
                            onOpenDetail: widget.onOpenDetail,
                            onPlay: widget.onPlay,
                          ),
                        ),
                        SectionPadding(
                          child: _ProvidersSection(
                            onOpenAllProviders: widget.onOpenAllProviders,
                            onOpenProvider: widget.onOpenProvider,
                          ),
                        ),
                        SectionPadding(
                          child: _MediaSection(
                            sectionId: 'recommendations',
                            title: 'Recommended for You',
                            items: ctrl.recommendations,
                            isLoading: ctrl.isLoadingRecommendations,
                            error: ctrl.recommendationsError,
                            hideWhenEmpty: true,
                            onRetry: ctrl.retryRecommendations,
                            onOpenDetail: widget.onOpenDetail,
                            onPlay: widget.onPlay,
                            onOpenSection: widget.onOpenSection,
                          ),
                        ),
                        for (final sectionId in ctrl.visibleSectionOrder)
                          SectionPadding(
                            child: _MediaSection(
                              sectionId: sectionId,
                              title:
                                  HomeController.sectionTitles[sectionId] ??
                                  sectionId,
                              items:
                                  ctrl.sections[sectionId]?.items ?? const [],
                              isLoading:
                                  ctrl.sections[sectionId]?.isLoading ?? true,
                              error: ctrl.sections[sectionId]?.error,
                              onRetry: () => ctrl.retrySection(sectionId),
                              onOpenDetail: widget.onOpenDetail,
                              onPlay: widget.onPlay,
                              onOpenSection: widget.onOpenSection,
                            ),
                          ),
                        const SizedBox(height: AppSpacing.massive),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

double _heroHeight(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final availableHeight = size.height;
  final target = availableHeight * 0.88;
  if (size.width < AppBreakpoints.compact) {
    return target.clamp(520.0, 660.0).toDouble();
  }
  return target.clamp(640.0, 780.0).toDouble();
}

class _FeaturedMasthead extends StatelessWidget {
  const _FeaturedMasthead({
    required this.controller,
    required this.scrollController,
    required this.items,
    required this.currentPage,
    required this.isLoading,
    required this.onUserInteraction,
    required this.onPageChanged,
    this.onPlay,
  });

  final PageController controller;
  final ScrollController scrollController;
  final List<SearchMediaItem> items;
  final int currentPage;
  final bool isLoading;
  final VoidCallback onUserInteraction;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: _heroHeight(context),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedIndex = currentPage % items.length;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < AppBreakpoints.compact;
    final contentInset = compact ? AppSpacing.xl : 92.0;
    final heroHeight = _heroHeight(context);
    final narrowDesktop = screenWidth < AppBreakpoints.standard;
    final contentWidth = compact
        ? screenWidth - (contentInset * 2)
        : narrowDesktop
        ? 380.0
        : 460.0;
    final thumbnailWidth = compact
        ? screenWidth - (contentInset * 2)
        : narrowDesktop
        ? 320.0
        : (screenWidth * 0.34).clamp(360.0, 560.0).toDouble();

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            onUserInteraction();
            controller.previousPage(
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeInOutCubic,
            );
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            onUserInteraction();
            controller.nextPage(
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeInOutCubic,
            );
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        height: heroHeight,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: scrollController,
                builder: (context, child) {
                  final offset = scrollController.hasClients
                      ? scrollController.offset.clamp(0.0, heroHeight)
                      : 0.0;
                  final fade = (offset / (heroHeight * 0.72)).clamp(0.0, 0.54);

                  return Transform.translate(
                    offset: Offset(0, offset),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        child!,
                        IgnorePointer(
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: fade),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: PageView.builder(
                  controller: controller,
                  itemCount: items.length + 1,
                  onPageChanged: onPageChanged,
                  itemBuilder: (context, index) {
                    final actualIndex = index % items.length;
                    final item = items[actualIndex];
                    return HeroBackdropLayer(item: item);
                  },
                ),
              ),
            ),
            Positioned(
              left: contentInset,
              right: compact ? contentInset : null,
              bottom: compact ? 104 : 88,
              child: SizedBox(
                width: contentWidth,
                child: _HeroForeground(
                  item: items[selectedIndex],
                  onPlay: onPlay,
                ),
              ),
            ),
            Positioned(
              right: contentInset,
              bottom: compact ? AppSpacing.xxl : 46,
              child: SizedBox(
                width: thumbnailWidth,
                child: _HeroThumbnailStrip(
                  items: items,
                  selectedIndex: selectedIndex,
                  onPrevious: () {
                    onUserInteraction();
                    controller.previousPage(
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeInOutCubic,
                    );
                  },
                  onNext: () {
                    onUserInteraction();
                    controller.nextPage(
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeInOutCubic,
                    );
                  },
                  onSelect: (index) {
                    onUserInteraction();
                    controller.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeInOutCubic,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroForeground extends StatelessWidget {
  const _HeroForeground({required this.item, this.onPlay});

  final SearchMediaItem item;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    final watchlist = WatchlistSyncController.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListenableBuilder(
          listenable: watchlist,
          builder: (context, _) {
            final isInWatchlist = watchlist.isInWatchlist(item.id);
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0.025, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: HeroContentPanel(
                key: ValueKey(item.id),
                item: item,
                primaryActionLabel: 'Watch Now',
                secondaryActionLabel: isInWatchlist
                    ? 'In watchlist'
                    : 'Add to watchlist',
                onPrimaryAction: () =>
                    onPlay?.call(PlaybackRequestFactory.fromSearchItem(item)),
                onSecondaryAction: () => watchlist.toggleSearchItem(item),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HeroThumbnailStrip extends StatelessWidget {
  const _HeroThumbnailStrip({
    required this.items,
    required this.selectedIndex,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final List<SearchMediaItem> items;
  final int selectedIndex;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (items.length <= 1) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth =
            (MediaQuery.sizeOf(context).width - (AppSpacing.xxl * 2))
                .clamp(260.0, 520.0)
                .toDouble();
        final stripWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : fallbackWidth;

        return SizedBox(
          width: stripWidth,
          height: 46,
          child: Row(
            children: [
              _CarouselStepButton(
                icon: LucideIcons.chevronLeft,
                label: 'Previous featured title',
                onPressed: onPrevious,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _HeroThumbnail(
                      item: item,
                      selected: selectedIndex == index,
                      onTap: () => onSelect(index),
                    );
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _CarouselStepButton(
                icon: LucideIcons.chevronRight,
                label: 'Next featured title',
                onPressed: onNext,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroThumbnail extends StatefulWidget {
  const _HeroThumbnail({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SearchMediaItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_HeroThumbnail> createState() => _HeroThumbnailState();
}

class _HeroThumbnailState extends State<_HeroThumbnail> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final imagePath = widget.item.backdropPath?.isNotEmpty == true
        ? widget.item.backdropPath
        : widget.item.posterPath;
    final usesBackdrop = widget.item.backdropPath?.isNotEmpty == true;
    final imageProvider = imagePath?.isNotEmpty == true
        ? NetworkImage(
            usesBackdrop
                ? TmdbImageBuilder.backdrop(imagePath!, size: 'w500')
                : TmdbImageBuilder.poster(imagePath!),
          )
        : null;
    final active = widget.selected || _hovered;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.item.title,
      child: Tooltip(
        message: widget.item.title,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: active ? 1.08 : 1,
              duration: AppAnimation.hover,
              curve: AppAnimation.standard,
              child: AnimatedSlide(
                offset: _hovered ? const Offset(0, -0.04) : Offset.zero,
                duration: AppAnimation.hover,
                curve: AppAnimation.standard,
                child: AnimatedContainer(
                  duration: AppAnimation.hover,
                  curve: AppAnimation.standard,
                  width: 88,
                  height: 46,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                    border: Border.all(
                      color: widget.selected
                          ? context.appAccent
                          : _hovered
                          ? Colors.white.withValues(alpha: 0.78)
                          : Colors.white.withValues(alpha: 0.16),
                      width: widget.selected ? 2 : 1,
                    ),
                    boxShadow: active ? AppShadows.hover : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageProvider != null)
                          Image(
                            image: imageProvider,
                            fit: usesBackdrop ? BoxFit.cover : BoxFit.cover,
                            alignment: usesBackdrop
                                ? Alignment.center
                                : Alignment.topCenter,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, _, _) =>
                                _ThumbnailFallback(title: widget.item.title),
                          )
                        else
                          _ThumbnailFallback(title: widget.item.title),
                        AnimatedOpacity(
                          opacity: widget.selected
                              ? 0
                              : _hovered
                              ? 0.12
                              : 0.38,
                          duration: AppAnimation.hover,
                          child: const ColoredBox(color: Colors.black),
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
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _CarouselStepButton extends StatelessWidget {
  const _CarouselStepButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: AppColors.textPrimary,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(36),
          backgroundColor: Colors.black.withValues(alpha: 0.18),
          hoverColor: Colors.white.withValues(alpha: 0.10),
          focusColor: Colors.white.withValues(alpha: 0.10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
    );
  }
}

class _ContinueWatchingSection extends StatelessWidget {
  const _ContinueWatchingSection({
    required this.items,
    required this.isLoading,
    this.onOpenDetail,
    this.onPlay,
  });

  final List<Map<String, dynamic>> items;
  final bool isLoading;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Continue Watching',
          subtitle: 'Pick up where you left off',
        ),
        const SizedBox(height: AppSpacing.lg),
        MediaRail(
          itemWidth: 360,
          height: 340,
          children: items.map((item) {
            final id = item['id']?.toString();
            final title = (item['title'] ?? item['name'] ?? 'Untitled')
                .toString();
            final mediaType = (item['mediaType'] ?? item['type'] ?? '')
                .toString()
                .toLowerCase();
            final isSeries = mediaType == 'tv' || mediaType == 'anime';
            final season = item['currentSeason'] ?? item['season'];
            final episode = item['currentEpisode'] ?? item['episode'];
            final rawProgress =
                (item['progressPercent'] as num?)?.toDouble() ??
                (item['progress'] as num?)?.toDouble() ??
                0;
            final progress = rawProgress > 1 ? rawProgress / 100 : rawProgress;
            final episodeLabel = isSeries && season != null && episode != null
                ? 'Season $season · Episode $episode'
                : 'Movie';

            final posterPath = (item['posterPath'] ?? item['poster_path'])
                ?.toString();
            final backdropPath = (item['backdropPath'] ?? item['backdrop_path'])
                ?.toString();
            final imagePath = backdropPath?.isNotEmpty == true
                ? backdropPath
                : posterPath;
            final imageUrl = imagePath?.isNotEmpty == true
                ? backdropPath?.isNotEmpty == true
                      ? TmdbImageBuilder.backdrop(imagePath!)
                      : TmdbImageBuilder.poster(imagePath!)
                : null;
            final remainingSeconds =
                ((item['totalDurationSeconds'] as num?)?.toInt() ?? 0) -
                ((item['lastPositionSeconds'] as num?)?.toInt() ?? 0);
            final remainingMinutes = remainingSeconds > 0
                ? remainingSeconds ~/ 60
                : 0;

            return ContinueWatchingCard(
              title: title,
              episodeLabel: episodeLabel,
              trailingLabel: remainingMinutes > 0
                  ? '${remainingMinutes}m'
                  : null,
              posterLabel: title,
              imageProvider: imageUrl == null ? null : NetworkImage(imageUrl),
              progress: progress,
              onResume: id == null
                  ? null
                  : () =>
                        onPlay?.call(PlaybackRequestFactory.fromHistory(item)),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.sectionId,
    required this.title,
    required this.items,
    required this.isLoading,
    this.error,
    this.hideWhenEmpty = false,
    this.onRetry,
    this.onOpenDetail,
    this.onPlay,
    this.onOpenSection,
  });

  final String sectionId;
  final String title;
  final List<SearchMediaItem> items;
  final bool isLoading;
  final String? error;
  final bool hideWhenEmpty;
  final VoidCallback? onRetry;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;
  final ValueChanged<String>? onOpenSection;

  @override
  Widget build(BuildContext context) {
    if (!isLoading && error == null && items.isEmpty && hideWhenEmpty) {
      return const SizedBox.shrink();
    }

    if (error != null && !isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title),
          const SizedBox(height: AppSpacing.lg),
          _SectionStatus(
            icon: Icons.warning_amber_rounded,
            message: error!,
            actionLabel: 'Retry',
            onAction: onRetry,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title),
        const SizedBox(height: AppSpacing.lg),
        if (!isLoading && items.isEmpty)
          _SectionStatus(
            icon: Icons.movie_filter_outlined,
            message: 'No titles available right now.',
            actionLabel: 'Retry',
            onAction: onRetry,
          )
        else
          MediaRail(
            itemWidth: 236,
            height: 420,
            spacing: AppSpacing.sm,
            children: isLoading
                ? List.generate(
                    8,
                    (index) => const PosterCard(title: '', isLoading: true),
                  )
                : items.map((item) {
                    final watchlist = WatchlistSyncController.instance;
                    return ListenableBuilder(
                      listenable: watchlist,
                      builder: (context, _) {
                        final isInWatchlist = watchlist.isInWatchlist(item.id);
                        return PosterCard(
                          mediaId: item.id,
                          title: item.title,
                          year: item.year > 0 ? item.yearLabel : null,
                          rating: item.rating > 0 ? item.ratingLabel : null,
                          subtitle: item.mediaTypeLabel,
                          overview: item.overview,
                          imageProvider:
                              item.posterPath != null &&
                                  item.posterPath!.isNotEmpty
                              ? NetworkImage(
                                  TmdbImageBuilder.poster(item.posterPath!),
                                )
                              : null,
                          previewImageProvider:
                              item.backdropPath != null &&
                                  item.backdropPath!.isNotEmpty
                              ? NetworkImage(
                                  TmdbImageBuilder.backdrop(item.backdropPath!),
                                )
                              : null,
                          onTap: () => onOpenDetail?.call(item.id),
                          onSecondaryTap: () => onOpenDetail?.call(item.id),
                          onPlay: () => onPlay?.call(
                            PlaybackRequestFactory.fromSearchItem(item),
                          ),
                          isInWatchlist: isInWatchlist,
                          onWatchlist: () => watchlist.toggleSearchItem(item),
                          onMore: () => onOpenDetail?.call(item.id),
                        );
                      },
                    );
                  }).toList(),
          ),
      ],
    );
  }
}

class _SectionStatus extends StatelessWidget {
  const _SectionStatus({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textMuted, size: 40),
          const SizedBox(height: AppSpacing.md),
          SelectableText(
            message,
            style: const TextStyle(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

class _ProvidersSection extends StatelessWidget {
  const _ProvidersSection({this.onOpenAllProviders, this.onOpenProvider});

  final VoidCallback? onOpenAllProviders;
  final ValueChanged<StreamingProviderItem>? onOpenProvider;

  @override
  Widget build(BuildContext context) {
    final providers = allProviders.take(20).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'Studios', onSeeAllPressed: onOpenAllProviders),
        const SizedBox(height: AppSpacing.lg),
        MediaRail(
          itemWidth: 332,
          height: 198,
          spacing: AppSpacing.sm,
          thumbVisibility: false,
          children: providers.map((provider) {
            final logoPath = provider['logo_path'] as String?;
            final name = provider['name'] as String;
            return ProviderCard(
              name: name,
              variant: ProviderCardVariant.studio,
              logoImage: logoPath != null
                  ? NetworkImage(TmdbImageBuilder.logo(logoPath))
                  : null,
              onTap: () => onOpenProvider?.call(_providerFromMap(provider)),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.massive),
      ],
    );
  }
}

StreamingProviderItem _providerFromMap(Map<String, dynamic> provider) {
  return StreamingProviderItem(
    id: (provider['id'] as num).toInt(),
    name: provider['name'] as String,
    logoPath: provider['logo_path'] as String?,
  );
}
