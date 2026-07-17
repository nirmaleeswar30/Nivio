import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:silky_scroll/silky_scroll.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/auth_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/watchlist_provider.dart';

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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allWatchlist = ref.watch(watchlistProvider);
    final theme = Theme.of(context);
    final tmdbService = ref.watch(tmdbServiceProvider);

    final watchlist = allWatchlist.where((item) {
      if (_searchQuery.isEmpty) return true;
      return item.title.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    Widget buildItemCard(dynamic item, String posterUrl) {
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
                      placeholder: (context, url) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Center(child: CircularProgressIndicator()),
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
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.white),
                        onPressed: () async {
                          await ref.read(watchlistServiceProvider).removeFromWatchlist(item.id);
                          ref.read(watchlistRefreshProvider.notifier).refresh();
                        },
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (item.voteAverage != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.voteAverage!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
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
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (item.releaseDate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.releaseDate!.split('-').first,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget buildListItem(dynamic item, String posterUrl) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/media/${item.id}?type=${item.mediaType}'),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                height: 150,
                child: item.posterPath != null
                    ? CachedNetworkImage(
                        imageUrl: posterUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        placeholder: (context, url) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.error),
                        ),
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.movie, size: 48),
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
                      if (item.releaseDate != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.releaseDate!.split('-').first,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (item.voteAverage != null)
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              item.voteAverage!.toStringAsFixed(1),
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () async {
                  await ref.read(watchlistServiceProvider).removeFromWatchlist(item.id);
                  ref.read(watchlistRefreshProvider.notifier).refresh();
                },
              ),
            ],
          ),
        ),
      );
    }

    final gridContent = SilkyGridView.builder(
      padding: const EdgeInsets.all(16),
      cacheExtent: 1500,
      scrollSpeed: 2.0,
      silkyScrollDuration: const Duration(milliseconds: 500),
      animationCurve: Curves.easeOutQuart,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: watchlist.length,
      itemBuilder: (context, index) {
        final item = watchlist[index];
        final posterUrl = tmdbService.getPosterUrl(item.posterPath);
        return RepaintBoundary(
          child: InkWell(
            onTap: () => context.push('/media/${item.id}?type=${item.mediaType}'),
            child: buildItemCard(item, posterUrl),
          ),
        );
      },
    );

    final listContent = SilkyListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      cacheExtent: 1500,
      scrollSpeed: 2.0,
      silkyScrollDuration: const Duration(milliseconds: 500),
      animationCurve: Curves.easeOutQuart,
      itemCount: watchlist.length,
      itemBuilder: (context, index) {
        final item = watchlist[index];
        final posterUrl = tmdbService.getPosterUrl(item.posterPath);
        return RepaintBoundary(
          child: buildListItem(item, posterUrl),
        );
      },
    );

    final content = allWatchlist.isEmpty
        ? _buildEmptyState(theme)
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
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
              Expanded(
                child: watchlist.isEmpty
                    ? Center(child: Text('No results found for "$_searchQuery"'))
                    : (_isListView ? listContent : gridContent),
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
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
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
