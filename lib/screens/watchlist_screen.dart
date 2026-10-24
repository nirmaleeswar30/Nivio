import 'dart:async';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/auth_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/models/watchlist_item.dart';
import 'package:nivio/services/anime_tracking_coordinator.dart';
import 'package:nivio/services/simkl_auth_service.dart';
import 'package:nivio/widgets/skeleton.dart';

class WatchlistScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const WatchlistScreen({super.key, this.embedded = false});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isListView = false;
  String _searchQuery = '';
  WatchStatus? _selectedStatusFilter;
  bool _isInitialLoading = true;
  bool _isSyncing = false;
  Timer? _initialLoadingTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });

    final initialItems = ref.read(watchlistProvider);
    if (initialItems.isNotEmpty) {
      _isInitialLoading = false;
    } else {
      _initialLoadingTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted && _isInitialLoading) {
          setState(() {
            _isInitialLoading = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _initialLoadingTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _syncWatchlist() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      final watchlistService = ref.read(watchlistServiceProvider);
      if (ref.read(isSignedInProvider)) {
        await watchlistService.downloadFromCloud();
      }
      if (AnimeTrackingCoordinator.instance.hasAnyAccountConnected) {
        await watchlistService.importFromAnimeTracking(pushOfflineChanges: true);
      }
      if (SimklAuthService.instance.isAuthenticated) {
        await watchlistService.importFromSimkl(pushOfflineChanges: true);
      }
      ref.read(watchlistRefreshProvider.notifier).refresh();
    } catch (e) {
      debugPrint('[WatchlistScreen] Sync error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _isInitialLoading = false;
        });
      }
    }
  }

  Color _getStatusColor(WatchStatus status) {
    switch (status) {
      case WatchStatus.watching:
        return const Color(0xFF4CAF50);
      case WatchStatus.planning:
        return const Color(0xFF2196F3);
      case WatchStatus.completed:
        return const Color(0xFF9C27B0);
      case WatchStatus.paused:
        return const Color(0xFFFF9800);
      case WatchStatus.dropped:
        return const Color(0xFFE91E63);
    }
  }

  IconData _getStatusIcon(WatchStatus status) {
    switch (status) {
      case WatchStatus.watching:
        return Icons.play_circle_outline_rounded;
      case WatchStatus.planning:
        return Icons.bookmark_border_rounded;
      case WatchStatus.completed:
        return Icons.check_circle_outline_rounded;
      case WatchStatus.paused:
        return Icons.pause_circle_outline_rounded;
      case WatchStatus.dropped:
        return Icons.remove_circle_outline_rounded;
    }
  }

  Future<void> _updateItemStatus(WatchlistItem item, WatchStatus newStatus) async {
    await ref.read(watchlistServiceProvider).updateWatchStatus(
      item.id,
      newStatus,
      currentEpisode: item.currentEpisode,
      totalEpisodes: item.totalEpisodes,
    );
    ref.read(watchlistRefreshProvider.notifier).refresh();

    if (item.mediaType == 'anime' || item.anilistId != null || item.malId != null) {
      unawaited(
        AnimeTrackingCoordinator.instance.syncWatchStatus(
          anilistId: item.anilistId ?? (item.mediaType == 'anime' ? item.id : null),
          malId: item.malId,
          status: newStatus,
          episode: item.currentEpisode ?? 1,
        ),
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved "${item.title}" to ${newStatus.label}'),
          backgroundColor: NivioTheme.accentColorOf(context),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildItemStatusMenu(WatchlistItem item) {
    return PopupMenuButton<dynamic>(
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      tooltip: '',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      splashRadius: 20,
      onSelected: (value) async {
        if (value is WatchStatus) {
          await _updateItemStatus(item, value);
        } else if (value == 'remove') {
          await ref.read(watchlistServiceProvider).removeFromWatchlist(item.id);
          ref.read(watchlistRefreshProvider.notifier).refresh();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Removed "${item.title}" from watchlist'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<dynamic>(
          enabled: false,
          height: 30,
          child: Text(
            'STATUS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Colors.grey,
            ),
          ),
        ),
        ...WatchStatus.values.map((status) {
          final isCurrent = item.watchStatus == status;
          final color = _getStatusColor(status);
          return PopupMenuItem<dynamic>(
            value: status,
            height: 38,
            child: Row(
              children: [
                Icon(_getStatusIcon(status), size: 16, color: color),
                const SizedBox(width: 8),
                Text(
                  status.label,
                  style: TextStyle(
                    color: isCurrent ? color : null,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
                if (isCurrent) ...[
                  const Spacer(),
                  Icon(Icons.check, size: 16, color: color),
                ],
              ],
            ),
          );
        }),
        const PopupMenuDivider(),
        const PopupMenuItem<dynamic>(
          value: 'remove',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
              SizedBox(width: 8),
              Text(
                'Remove',
                style: TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = AppPlatform.useDesktopLayout;
    final allWatchlist = ref.watch(watchlistProvider);
    if (allWatchlist.isNotEmpty && _isInitialLoading) {
      _isInitialLoading = false;
      _initialLoadingTimer?.cancel();
    }
    final theme = Theme.of(context);
    final tmdbService = ref.watch(tmdbServiceProvider);

    final watchlist = allWatchlist.where((item) {
      if (_selectedStatusFilter != null && item.watchStatus != _selectedStatusFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty &&
          !item.title.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    Widget buildItemCard(WatchlistItem item, String posterUrl) {
      final statusColor = _getStatusColor(item.watchStatus);
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.posterPath != null)
                    CachedNetworkImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      placeholder: (context, url) => const Skeletonizer(
                        child: SkeletonBox(
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.error),
                      ),
                    )
                  else
                    Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.movie, size: 48),
                    ),
                  // Status badge top-left
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: statusColor.withOpacity(0.5), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.watchStatus.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (item.voteAverage != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 13,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              item.voteAverage!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (item.releaseDate != null)
                        Text(
                          item.releaseDate!.split('-').first,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                            fontSize: 11,
                          ),
                        ),
                      if (item.currentEpisode != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Ep ${item.currentEpisode}${item.totalEpisodes != null ? '/${item.totalEpisodes}' : ''}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      _buildItemStatusMenu(item),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget buildListItem(WatchlistItem item, String posterUrl) {
      final statusColor = _getStatusColor(item.watchStatus);
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/media/${item.id}?type=${item.mediaType}'),
          child: Row(
            children: [
              SizedBox(
                width: 85,
                height: 122,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.posterPath != null)
                      CachedNetworkImage(
                        imageUrl: posterUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        placeholder: (context, url) => const Skeletonizer(
                          child: SkeletonBox(
                            width: double.infinity,
                            height: double.infinity,
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.error),
                        ),
                      )
                    else
                      Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.movie, size: 40),
                      ),
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: statusColor.withOpacity(0.6)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.watchStatus.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (item.releaseDate != null)
                            Text(
                              item.releaseDate!.split('-').first,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                          if (item.voteAverage != null) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.star, color: Colors.amber, size: 14),
                            const SizedBox(width: 3),
                            Text(
                              item.voteAverage!.toStringAsFixed(1),
                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ],
                      ),
                      if (item.currentEpisode != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Episode ${item.currentEpisode}${item.totalEpisodes != null ? ' of ${item.totalEpisodes}' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _buildItemStatusMenu(item),
              const SizedBox(width: 8),
            ],
          ),
        ),
      );
    }

    Widget buildFilterChips() {
      final counts = <WatchStatus?, int>{
        null: allWatchlist.length,
      };
      for (final item in allWatchlist) {
        counts[item.watchStatus] = (counts[item.watchStatus] ?? 0) + 1;
      }

      final options = [
        (null, 'All', counts[null] ?? 0),
        (WatchStatus.watching, 'Watching', counts[WatchStatus.watching] ?? 0),
        (WatchStatus.planning, 'Plan to Watch', counts[WatchStatus.planning] ?? 0),
        (WatchStatus.completed, 'Completed', counts[WatchStatus.completed] ?? 0),
        (WatchStatus.paused, 'On Hold', counts[WatchStatus.paused] ?? 0),
        (WatchStatus.dropped, 'Dropped', counts[WatchStatus.dropped] ?? 0),
      ];

      return SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 68 : 16),
          itemCount: options.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, idx) {
            final (status, label, count) = options[idx];
            final isSelected = _selectedStatusFilter == status;
            final color = status != null ? _getStatusColor(status) : NivioTheme.accentColorOf(context);

            return ChoiceChip(
              label: Text('$label ($count)'),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.8),
              ),
              selected: isSelected,
              selectedColor: color.withOpacity(0.85),
              backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: isSelected ? color : Colors.white10,
                  width: 1,
                ),
              ),
              onSelected: (_) {
                setState(() {
                  _selectedStatusFilter = isSelected ? null : status;
                });
              },
            );
          },
        ),
      );
    }

    final bottomGridPad = isDesktop ? 16.0 : (widget.embedded ? 96.0 : 16.0);
    final bottomListPad = isDesktop ? 8.0 : (widget.embedded ? 96.0 : 8.0);

    final gridContent = AppGridView.builder(
      padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16, 16, 16, bottomGridPad),
      cacheExtent: isDesktop ? 1000 : 350,
      scrollSpeed: 2.0,
      silkyScrollDuration: const Duration(milliseconds: 500),
      animationCurve: Curves.easeOutQuart,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: isDesktop ? 180 : 185,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: watchlist.length,
      itemBuilder: (context, index) {
        final item = watchlist[index];
        final posterUrl = tmdbService.getPosterUrl(item.posterPath);
        return _WatchlistHoverCard(
          onTap: () => context.push('/media/${item.id}?type=${item.mediaType}'),
          hoverScale: 1.05,
          child: buildItemCard(item, posterUrl),
        );
      },
    );

    final listContent = AppListView.builder(
      padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16, 8, 16, bottomListPad),
      cacheExtent: isDesktop ? 1000 : 350,
      scrollSpeed: 2.0,
      silkyScrollDuration: const Duration(milliseconds: 500),
      animationCurve: Curves.easeOutQuart,
      itemCount: watchlist.length,
      itemBuilder: (context, index) {
        final item = watchlist[index];
        final posterUrl = tmdbService.getPosterUrl(item.posterPath);
        return _WatchlistHoverCard(
          onTap: () => context.push('/media/${item.id}?type=${item.mediaType}'),
          hoverScale: 1.015,
          borderRadius: BorderRadius.circular(12),
          child: buildListItem(item, posterUrl),
        );
      },
    );

    final showSkeleton = (_isInitialLoading || _isSyncing) && allWatchlist.isEmpty;

    final content = showSkeleton
        ? _buildSkeletonView(isDesktop)
        : allWatchlist.isEmpty
            ? RefreshIndicator(
                onRefresh: _syncWatchlist,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.7,
                    child: _buildEmptyState(theme),
                  ),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16, 16, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TvTextFieldGate(builder: (context, focusNode) => TextField(focusNode: focusNode,
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search watchlist...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () => _searchController.clear(),
                                    )
                                  : null,
                              filled: true,
                              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 0),
                            ),
                          ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(_isListView ? Icons.grid_view : Icons.view_list),
                          onPressed: () {
                            setState(() {
                              _isListView = !_isListView;
                            });
                          },
                          tooltip: _isListView ? 'Grid View' : 'List View',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  buildFilterChips(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: watchlist.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isNotEmpty
                                  ? 'No results found for "$_searchQuery"'
                                  : 'No items in ${_selectedStatusFilter?.label ?? 'this category'}',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                                fontSize: 14,
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _syncWatchlist,
                            child: _isListView ? listContent : gridContent,
                          ),
                  ),
                ],
              );

    if (widget.embedded) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF151922), NivioTheme.netflixBlack],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16, 10, 16, 0),
              child: Row(
                children: [
                  const Text(
                    'My Watchlist',
                    style: TextStyle(
                      color: NivioTheme.netflixWhite,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: NivioTheme.netflixWhite,
                            ),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            color: NivioTheme.netflixWhite,
                          ),
                    tooltip: 'Sync Watchlist',
                    onPressed: _syncWatchlist,
                  ),
                  if (allWatchlist.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        Icons.info_outline,
                        color: NivioTheme.netflixWhite,
                      ),
                      tooltip: 'About Watchlist',
                      onPressed: () => _showInfoDialog(context, ref),
                    ),
                ],
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Watchlist'),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Sync Watchlist',
            onPressed: _syncWatchlist,
          ),
          if (allWatchlist.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'About Watchlist',
              onPressed: () => _showInfoDialog(context, ref),
            ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildSkeletonView(bool isDesktop) {
    return Column(
      children: [
        // Search bar skeleton
        Padding(
          padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Skeletonizer(
                  child: SkeletonBox(
                    width: double.infinity,
                    height: 48,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Skeletonizer(
                child: SkeletonBox(
                  width: 40,
                  height: 40,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Filter chips skeleton
        SizedBox(
          height: 36,
          child: Skeletonizer(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 68 : 16),
              itemCount: 6,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, idx) => SkeletonBox(
                width: idx == 0 ? 55 : (70.0 + (idx * 8)),
                height: 32,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Grid or List skeleton
        Expanded(
          child: _isListView
              ? WatchlistListSkeleton(
                  padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16, 8, 16, 8),
                  itemCount: 8,
                )
              : WatchlistGridSkeleton(
                  padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16, 16, 16, 16),
                  maxCrossAxisExtent: isDesktop ? 180 : 185,
                  childAspectRatio: 0.65,
                  itemCount: 16,
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bookmark_border,
            size: 120,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'Your watchlist is empty',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add movies and TV shows to watch later',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context, WidgetRef ref) {
    final isSignedIn = ref.read(isSignedInProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Watchlist Info'),
        content: Text(
          'Your watchlist is saved locally and ${isSignedIn ? 'synced to the cloud' : 'will sync when you sign in'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Interactive hover card with smooth scale and soft drop-shadow animation on desktop.
class _WatchlistHoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double hoverScale;
  final BorderRadius borderRadius;

  const _WatchlistHoverCard({
    required this.child,
    required this.onTap,
    this.hoverScale = 1.05,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<_WatchlistHoverCard> createState() => _WatchlistHoverCardState();
}

class _WatchlistHoverCardState extends State<_WatchlistHoverCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      onActivate: widget.onTap,
      child: MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _isHovered ? widget.hoverScale : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
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
            child: widget.child,
          ),
        ),
      ),
    ),
    );
  }
}
