import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;

import '../../../core/network/image/tmdb_image_builder.dart';
import '../../../shared/theme/index.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/services/watchlist_sync_controller.dart';
import '../../player/models/playback_request.dart';
import '../../player/playback_request_factory.dart';
import '../controllers/search_controller.dart';
import '../models/search_media_item.dart';
import '../widgets/search_toolbar.dart';

class SearchView extends StatefulWidget {
  const SearchView({
    super.key,
    required this.controller,
    required this.queryController,
    required this.searchFocusNode,
    this.onOpenDetail,
    this.onPlay,
  });

  final SearchController controller;
  final TextEditingController queryController;
  final FocusNode searchFocusNode;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final ScrollController _resultsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initialize());
    _resultsScrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_resultsScrollController.hasClients) return;
    if (_resultsScrollController.position.pixels >=
        _resultsScrollController.position.maxScrollExtent - 500) {
      unawaited(widget.controller.loadMore());
    }
  }

  @override
  void dispose() {
    _resultsScrollController.removeListener(_onScroll);
    _resultsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox.expand(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _horizontalPadding(constraints.maxWidth),
              vertical: AppSpacing.xxl,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppBreakpoints.contentMaxWidth,
                ),
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SearchToolbar(
                          controller: widget.controller,
                          queryController: widget.queryController,
                          searchFocusNode: widget.searchFocusNode,
                        ),
                        if (widget.controller.query.isEmpty &&
                            widget.controller.recentSearches.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxl),
                          _RecentSearchesRow(
                            searches: widget.controller.recentSearches,
                            onRemove: widget.controller.removeRecentSearch,
                            onSelected: (value) {
                              widget.queryController.text = value;
                              widget.controller.setQuery(value);
                              widget.controller.submitQuery();
                              FocusScope.of(
                                context,
                              ).requestFocus(widget.searchFocusNode);
                            },
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xxl),
                        if (widget.controller.query.trim().isEmpty &&
                            !widget.controller.isLoading &&
                            !widget.controller.hasError)
                          const Spacer()
                        else
                          Expanded(
                            child: _SearchResultsPane(
                              controller: widget.controller,
                              scrollController: _resultsScrollController,
                              onOpenDetail: widget.onOpenDetail,
                              onPlay: widget.onPlay,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _horizontalPadding(double width) {
    if (AppBreakpoints.isUltraWide(width)) {
      return AppSpacing.massive;
    }
    if (AppBreakpoints.isLarge(width)) {
      return AppSpacing.xxxl;
    }
    if (AppBreakpoints.isStandard(width)) {
      return AppSpacing.xxl;
    }
    return AppSpacing.xl;
  }
}

class _RecentSearchesRow extends StatelessWidget {
  const _RecentSearchesRow({
    required this.searches,
    required this.onSelected,
    required this.onRemove,
  });

  final List<String> searches;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final search in searches)
          _RecentSearchChip(
            label: search,
            onTap: () => onSelected(search),
            onRemove: () => onRemove(search),
          ),
      ],
    );
  }
}

class _RecentSearchChip extends StatelessWidget {
  const _RecentSearchChip({
    required this.label,
    required this.onTap,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.history,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: 'Remove $label',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 19),
                  color: AppColors.textSecondary,
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(32),
                    padding: EdgeInsets.zero,
                    hoverColor: AppColors.hover,
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

class _SearchResultsPane extends StatelessWidget {
  const _SearchResultsPane({
    required this.controller,
    required this.scrollController,
    this.onOpenDetail,
    this.onPlay,
  });

  final SearchController controller;
  final ScrollController scrollController;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    final showLoading = controller.isLoading && controller.results.isEmpty;

    return AnimatedSwitcher(
      duration: AppAnimation.fast,
      child: _buildBody(showLoading),
    );
  }

  Widget _buildBody(bool showLoading) {
    if (showLoading) {
      return controller.viewMode == SearchViewMode.grid
          ? const _LoadingGrid()
          : const _LoadingList();
    }

    if (controller.hasError) {
      return ErrorView(
        title: 'Search failed',
        message: controller.errorMessage ?? 'Something went wrong.',
        onRetry: controller.retry,
      );
    }

    if (controller.results.isEmpty) {
      return EmptyState(
        title: controller.query.isEmpty
            ? 'Start searching'
            : 'No results found',
        message: controller.query.isEmpty
            ? 'Search movies, shows, and anime using the field above.'
            : 'Try a different title.',
      );
    }

    if (controller.viewMode == SearchViewMode.list) {
      final watchlist = WatchlistSyncController.instance;
      return ListenableBuilder(
        listenable: watchlist,
        builder: (context, _) {
          return DesktopScrollbar(
            controller: scrollController,
            child: ListView.separated(
              controller: scrollController,
              itemCount:
                  controller.results.length +
                  (controller.isLoadingMore ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                if (index == controller.results.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final item = controller.results[index];
                return _SearchResultListItem(
                  item: item,
                  isInWatchlist: watchlist.isInWatchlist(item.id),
                  onWatchlist: () => watchlist.toggleSearchItem(item),
                  onOpenDetail: onOpenDetail,
                  onPlay: onPlay,
                );
              },
            ),
          );
        },
      );
    }

    final watchlist = WatchlistSyncController.instance;
    return ListenableBuilder(
      listenable: watchlist,
      builder: (context, _) {
        return DesktopScrollbar(
          controller: scrollController,
          child: MediaGrid(
            controller: scrollController,
            itemCount:
                controller.results.length + (controller.isLoadingMore ? 1 : 0),
            minItemWidth: 236,
            mainAxisSpacing: AppSpacing.xl,
            crossAxisSpacing: AppSpacing.sm,
            itemBuilder: (context, index) {
              if (index == controller.results.length) {
                return const Center(child: CircularProgressIndicator());
              }
              final item = controller.results[index];
              return _SearchResultPosterCard(
                item: item,
                isInWatchlist: watchlist.isInWatchlist(item.id),
                onWatchlist: () => watchlist.toggleSearchItem(item),
                onOpenDetail: onOpenDetail,
                onPlay: onPlay,
              );
            },
          ),
        );
      },
    );
  }
}

class _SearchResultPosterCard extends StatelessWidget {
  const _SearchResultPosterCard({
    required this.item,
    required this.isInWatchlist,
    required this.onWatchlist,
    this.onOpenDetail,
    this.onPlay,
  });

  final SearchMediaItem item;
  final bool isInWatchlist;
  final VoidCallback onWatchlist;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    return MediaCard(
      mediaId: item.id,
      title: item.title,
      year: item.year > 0 ? item.yearLabel : null,
      rating: item.rating > 0 ? item.ratingLabel : null,
      subtitle: item.mediaTypeLabel,
      posterPath: item.posterPath,
      backdropPath: item.backdropPath,
      overview: item.overview,
      onTap: () => onOpenDetail?.call(item.id),
      onPlay: () => onPlay?.call(PlaybackRequestFactory.fromSearchItem(item)),
      isInWatchlist: isInWatchlist,
      onWatchlist: onWatchlist,
      onMore: () => onOpenDetail?.call(item.id),
    );
  }
}

class _SearchResultListItem extends StatelessWidget {
  const _SearchResultListItem({
    required this.item,
    required this.isInWatchlist,
    required this.onWatchlist,
    this.onOpenDetail,
    this.onPlay,
  });

  final SearchMediaItem item;
  final bool isInWatchlist;
  final VoidCallback onWatchlist;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    final imageProvider = _landscapeImageProvider(item);
    return LandscapeCard(
      title: item.title,
      imageProvider: imageProvider,
      subtitle: item.overview,
      metadata: [
        item.yearLabel,
        item.ratingLabel,
        item.mediaTypeLabel,
        item.languageLabel,
        item.provider,
      ],
      semanticLabel:
          '${item.title}, ${item.yearLabel}, ${item.ratingLabel} rating, ${item.languageLabel}, ${item.provider}',
      onTap: () => onOpenDetail?.call(item.id),
      onSecondaryTap: () => onOpenDetail?.call(item.id),
      onDoubleTap: () =>
          onPlay?.call(PlaybackRequestFactory.fromSearchItem(item)),
      isInWatchlist: isInWatchlist,
      onWatchlist: onWatchlist,
      onMore: () => onOpenDetail?.call(item.id),
    );
  }

  ImageProvider? _landscapeImageProvider(SearchMediaItem item) {
    final backdropPath = item.backdropPath?.trim();
    if (backdropPath != null && backdropPath.isNotEmpty) {
      return NetworkImage(TmdbImageBuilder.backdrop(backdropPath));
    }
    final posterPath = item.posterPath?.trim();
    if (posterPath != null && posterPath.isNotEmpty) {
      return NetworkImage(TmdbImageBuilder.poster(posterPath));
    }
    return null;
  }
}

class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid();

  @override
  Widget build(BuildContext context) {
    return MediaGrid(
      itemCount: 12,
      minItemWidth: 236,
      mainAxisSpacing: AppSpacing.xl,
      crossAxisSpacing: AppSpacing.sm,
      itemBuilder: (context, index) => const PosterSkeleton(),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: 8,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) =>
          const SizedBox(height: 160, child: LandscapeSkeleton()),
    );
  }
}
