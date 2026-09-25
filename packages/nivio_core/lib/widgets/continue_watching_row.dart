import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:nivio/providers/watch_history_provider.dart';
import 'package:nivio/widgets/continue_watching_card.dart';
import 'package:nivio/widgets/skeleton.dart';
import 'package:nivio/core/theme.dart';

class ContinueWatchingRow extends ConsumerWidget {
  const ContinueWatchingRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final continueWatching = ref.watch(continueWatchingProvider);

    return continueWatching.when(
      data: (items) {
        if (items.isEmpty) {
          return SizedBox(
            height: 200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.movie_outlined,
                    size: 64,
                    color: NivioTheme.netflixGrey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No continue watching items',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search for shows and movies to start watching',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        }
        return SizedBox(
          height: 196,
          child: AppListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 6),
            cacheExtent: 250,
            scrollSpeed: 2.0,
            silkyScrollDuration: const Duration(milliseconds: 500),
            animationCurve: Curves.easeOutQuart,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final history = items[index];
              return ContinueWatchingCard(
                key: ValueKey('${history.tmdbId}_${history.currentSeason}_${history.currentEpisode}'),
                history: history,
              );
            },
          ),
        );
      },
      loading: () => Skeletonizer(
        child: SizedBox(
          height: 196,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: 6,
            itemBuilder: (_, __) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                width: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFF151922),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                clipBehavior: Clip.antiAlias,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SkeletonBox(
                      width: 220,
                      height: 124,
                      borderRadius: BorderRadius.zero,
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(10, 8, 10, 9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 140, height: 13),
                          SizedBox(height: 5),
                          SkeletonBox(width: 80, height: 11),
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
      error: (err, stack) => SizedBox(
        height: 196,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: NivioTheme.accentColorOf(context),
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading continue watching',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                err.toString(),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
