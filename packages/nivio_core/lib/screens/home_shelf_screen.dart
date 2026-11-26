import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/home_providers.dart';
import 'package:nivio/providers/watch_history_provider.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:nivio/widgets/continue_watching_card.dart';
import 'package:nivio/widgets/search_result_card.dart';
import 'package:nivio/widgets/skeleton.dart';

class HomeShelfScreen extends ConsumerStatefulWidget {
  const HomeShelfScreen({super.key, required this.shelf});

  final HomeShelf shelf;

  @override
  ConsumerState<HomeShelfScreen> createState() => _HomeShelfScreenState();
}

class _HomeShelfScreenState extends ConsumerState<HomeShelfScreen> {
  final _additionalItems = <SearchResult>[];
  int _nextPage = 2;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _loadMoreFailed = false;

  Future<void> _loadMore(List<SearchResult> firstPage) async {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
      _loadMoreFailed = false;
    });

    try {
      final loadPage = ref.read(homeShelfLoaderProvider(widget.shelf));
      final page = await loadPage(_nextPage);
      if (!mounted) return;

      final seen = {
        for (final item in firstPage) (item.mediaType, item.id),
        for (final item in _additionalItems) (item.mediaType, item.id),
      };
      final newItems = page.items
          .where((item) => seen.add((item.mediaType, item.id)))
          .toList();
      setState(() {
        _additionalItems.addAll(newItems);
        _nextPage++;
        _hasMore = page.hasMore && newItems.isNotEmpty;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadMoreFailed = true;
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = homeShelfProvider(widget.shelf);
    final isDesktop = AppPlatform.useDesktopLayout;
    final gutter = isDesktop ? 68.0 : 16.0;
    final padding = EdgeInsets.fromLTRB(gutter, 16, gutter, 24);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: Text(widget.shelf.title),
      ),
      body: SafeArea(
        top: false,
        child: ref
            .watch(provider)
            .when(
              loading: () => PosterGridSkeleton(
                padding: padding,
                maxCrossAxisExtent: 180,
                childAspectRatio: 0.65,
                itemCount: isDesktop ? 18 : 8,
              ),
              error: (_, _) => Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(provider),
                  child: const Text('Couldn’t load titles. Try again'),
                ),
              ),
              data: (page) {
                if (page.items.isEmpty) {
                  return const Center(child: Text('No titles found'));
                }

                final items = [...page.items, ..._additionalItems];
                final canLoadMore = page.hasMore && _hasMore;
                // Loads the next page as the grid nears its end, and again
                // when a page doesn't fill the screen.
                bool nearEnd(ScrollMetrics metrics) {
                  if (canLoadMore &&
                      !_isLoadingMore &&
                      !_loadMoreFailed &&
                      metrics.axis == Axis.vertical &&
                      metrics.extentAfter < 900) {
                    // Notifications can arrive mid-layout; load after it.
                    scheduleMicrotask(() {
                      if (mounted) _loadMore(page.items);
                    });
                  }
                  return false;
                }

                return NotificationListener<ScrollMetricsNotification>(
                  onNotification: (notification) =>
                      nearEnd(notification.metrics),
                  child: NotificationListener<ScrollUpdateNotification>(
                    onNotification: (notification) =>
                        nearEnd(notification.metrics),
                    child: AppCustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: padding,
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 180,
                                  childAspectRatio: 0.65,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 12,
                                ),
                            itemCount: items.length,
                            itemBuilder: (context, index) =>
                                SearchResultCard(media: items[index]),
                          ),
                        ),
                        if (canLoadMore)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Center(
                                child: _loadMoreFailed
                                    ? OutlinedButton(
                                        onPressed: () => _loadMore(page.items),
                                        child: const Text('Try again'),
                                      )
                                    : const SizedBox.square(
                                        dimension: 28,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
      ),
    );
  }
}

class ContinueWatchingScreen extends ConsumerWidget {
  const ContinueWatchingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gutter = AppPlatform.useDesktopLayout ? 68.0 : 16.0;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
        title: const Text('Continue Watching'),
      ),
      body: SafeArea(
        top: false,
        child: ref
            .watch(watchHistoryProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(watchHistoryProvider),
                  child: const Text('Couldn’t load watch history. Try again'),
                ),
              ),
              data: (history) {
                final items = history
                    .where((item) => !item.isCompleted)
                    .toList();
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No titles to continue watching'),
                  );
                }

                return AppGridView.builder(
                  padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 254,
                    mainAxisExtent: 196,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ContinueWatchingCard(
                      key: ValueKey((
                        item.tmdbId,
                        item.currentSeason,
                        item.currentEpisode,
                      )),
                      history: item,
                    );
                  },
                );
              },
            ),
      ),
    );
  }
}
