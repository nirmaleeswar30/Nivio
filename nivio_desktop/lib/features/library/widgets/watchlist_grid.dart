import 'package:flutter/material.dart';

import '../../../core/network/image/tmdb_image_builder.dart';
import '../../../shared/theme/index.dart';
import '../../../shared/widgets/widgets.dart';
import '../models/library_models.dart';
import '../services/library_data_service.dart';
import '../../player/models/playback_request.dart';
import '../../player/playback_request_factory.dart';
import 'library_empty_state.dart';

class WatchlistGrid extends StatefulWidget {
  const WatchlistGrid({
    super.key,
    required this.items,
    required this.service,
    required this.historyByMediaId,
    required this.scrollController,
    this.onOpenDetail,
    this.onPlay,
  });

  final List<LibraryWatchlistItem> items;
  final LibraryWatchlistService service;
  final Map<int, Map<String, dynamic>> historyByMediaId;
  final ScrollController scrollController;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  State<WatchlistGrid> createState() => _WatchlistGridState();
}

class _WatchlistGridState extends State<WatchlistGrid> {
  final TextEditingController _searchController = TextEditingController();
  var _isListView = false;
  var _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((item) {
      if (_query.isEmpty) return true;
      return item.title.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                cursorColor: AppColors.textPrimary,
                decoration: InputDecoration(
                  hintText: 'Search watchlist...',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.textSecondary,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: _searchController.clear,
                        ),
                  filled: true,
                  fillColor: AppColors.surfaceVariant.withValues(alpha: 0.55),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                    borderSide: const BorderSide(color: AppColors.borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                    borderSide: const BorderSide(color: AppColors.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                    borderSide: const BorderSide(color: AppColors.borderStrong),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppRadius.medium),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: IconButton(
                tooltip: _isListView ? 'Grid view' : 'List view',
                onPressed: () => setState(() => _isListView = !_isListView),
                icon: Icon(_isListView ? Icons.grid_view : Icons.view_list),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(child: _buildResults(filtered)),
      ],
    );
  }

  Widget _buildResults(List<LibraryWatchlistItem> filtered) {
    if (filtered.isEmpty) {
      return Center(
        child: LibraryEmptyState(
          title: _query.isEmpty
              ? 'Your watchlist is empty'
              : 'No results found for "$_query"',
          message: _query.isEmpty
              ? 'Add movies and TV shows to watch later.'
              : 'Try a different title.',
        ),
      );
    }

    if (_isListView) {
      return DesktopScrollbar(
        controller: widget.scrollController,
        child: ListView.separated(
          controller: widget.scrollController,
          itemCount: filtered.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            return _WatchlistListItem(
              item: filtered[index],
              service: widget.service,
              onOpenDetail: widget.onOpenDetail,
              onPlay: widget.onPlay,
            );
          },
        ),
      );
    }

    return DesktopScrollbar(
      controller: widget.scrollController,
      child: MediaGrid(
        controller: widget.scrollController,
        itemCount: filtered.length,
        minItemWidth: 236,
        mainAxisSpacing: AppSpacing.xl,
        crossAxisSpacing: AppSpacing.sm,
        itemBuilder: (context, index) {
          final item = filtered[index];
          return MediaCard(
            mediaId: '${item.mediaType}:${item.id}',
            title: item.title,
            posterPath: item.posterPath,
            year: _year(item.releaseDate),
            rating: item.voteAverage?.toStringAsFixed(1),
            subtitle: _subtitle(item),
            overview: item.overview,
            progress: _progress(item.id),
            onTap: () =>
                widget.onOpenDetail?.call('${item.mediaType}:${item.id}'),
            onPlay: () =>
                widget.onPlay?.call(PlaybackRequestFactory.fromWatchlist(item)),
            onMore: () =>
                widget.onOpenDetail?.call('${item.mediaType}:${item.id}'),
            isInWatchlist: true,
            onWatchlist: () => widget.service.remove(item.id),
          );
        },
      ),
    );
  }

  String? _year(String? releaseDate) {
    if (releaseDate == null || releaseDate.length < 4) return null;
    return releaseDate.substring(0, 4);
  }

  double? _progress(int mediaId) {
    final history = widget.historyByMediaId[mediaId];
    if (history == null || history['isCompleted'] == true) return null;
    final value = (history['progressPercent'] as num?)?.toDouble();
    return value == null || value <= 0 ? null : value.clamp(0.0, 1.0);
  }

  String _subtitle(LibraryWatchlistItem item) {
    final progress = _progress(item.id);
    if (progress == null) return item.mediaType.toUpperCase();
    return '${item.mediaType.toUpperCase()} · ${(progress * 100).round()}% watched';
  }
}

class _WatchlistListItem extends StatelessWidget {
  const _WatchlistListItem({
    required this.item,
    required this.service,
    this.onOpenDetail,
    this.onPlay,
  });

  final LibraryWatchlistItem item;
  final LibraryWatchlistService service;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surfaceVariant.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          onTap: () => onOpenDetail?.call('${item.mediaType}:${item.id}'),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                _WatchlistPoster(path: item.posterPath),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.title,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        [
                          item.mediaType.toUpperCase(),
                          if (item.releaseDate != null &&
                              item.releaseDate!.length >= 4)
                            item.releaseDate!.substring(0, 4),
                          if (item.voteAverage != null)
                            item.voteAverage!.toStringAsFixed(1),
                        ].join(' · '),
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    IconButton(
                      tooltip: 'Play',
                      onPressed: () => onPlay?.call(
                        PlaybackRequestFactory.fromWatchlist(item),
                      ),
                      icon: const Icon(Icons.play_circle_fill),
                    ),
                    IconButton(
                      tooltip: 'Remove from watchlist',
                      icon: const Icon(Icons.close),
                      onPressed: () => service.remove(item.id),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WatchlistPoster extends StatelessWidget {
  const _WatchlistPoster({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final url = path == null || path!.isEmpty
        ? null
        : TmdbImageBuilder.poster(path!);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: SizedBox(
        width: 64,
        height: 96,
        child: url == null
            ? const ColoredBox(
                color: AppColors.surface,
                child: Icon(Icons.movie_outlined),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const ColoredBox(
                  color: AppColors.surface,
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }
}
