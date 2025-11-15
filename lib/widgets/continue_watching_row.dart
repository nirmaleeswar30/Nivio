import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/providers/watch_history_provider.dart';
import 'package:nivio/widgets/media_card.dart';
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
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, index) {
              return MediaCard(history: items[index]);
            },
          ),
        );
      },
      loading: () => const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(
            color: NivioTheme.netflixRed,
          ),
        ),
      ),
      error: (err, stack) => SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: NivioTheme.netflixRed,
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
