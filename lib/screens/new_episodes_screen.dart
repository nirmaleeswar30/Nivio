import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/models/new_episode.dart';
import 'package:nivio/services/episode_check_service.dart';

/// Provider for new episodes list
final newEpisodesProvider = StateProvider<List<NewEpisode>>((ref) {
  return EpisodeCheckService.getNewEpisodes();
});

/// Provider for unread count
final unreadEpisodeCountProvider = StateProvider<int>((ref) {
  return EpisodeCheckService.getUnreadCount();
});

class NewEpisodesScreen extends ConsumerStatefulWidget {
  const NewEpisodesScreen({super.key});

  @override
  ConsumerState<NewEpisodesScreen> createState() => _NewEpisodesScreenState();
}

class _NewEpisodesScreenState extends ConsumerState<NewEpisodesScreen> {
  @override
  void initState() {
    super.initState();
    // Delay the refresh to avoid modifying provider during build
    Future.microtask(() => _refreshEpisodes());
  }

  void _refreshEpisodes() {
    if (!mounted) return;
    ref.read(newEpisodesProvider.notifier).state = 
        EpisodeCheckService.getNewEpisodes();
    ref.read(unreadEpisodeCountProvider.notifier).state = 
        EpisodeCheckService.getUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    final episodes = ref.watch(newEpisodesProvider);

    return Scaffold(
      backgroundColor: NivioTheme.netflixBlack,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: NivioTheme.netflixBlack,
        title: const Text(
          'New Episodes',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (episodes.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              color: NivioTheme.netflixDarkGrey,
              onSelected: (value) async {
                switch (value) {
                  case 'mark_read':
                    await EpisodeCheckService.markAllAsRead();
                    _refreshEpisodes();
                    break;
                  case 'clear':
                    await EpisodeCheckService.clearAll();
                    _refreshEpisodes();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'mark_read',
                  child: Row(
                    children: [
                      Icon(Icons.done_all, color: Colors.white70, size: 20),
                      SizedBox(width: 12),
                      Text('Mark all as read', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.white70, size: 20),
                      SizedBox(width: 12),
                      Text('Clear all', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: episodes.isEmpty
          ? _buildEmptyState()
          : _buildEpisodeList(episodes),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none_outlined,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No new episodes',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'New episodes from your watchlist will appear here',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              final count = await EpisodeCheckService.checkNow();
              _refreshEpisodes();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      count > 0
                          ? '🎉 Found $count new episode${count > 1 ? 's' : ''}!'
                          : 'No new episodes found',
                    ),
                    backgroundColor: NivioTheme.netflixRed,
                  ),
                );
              }
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Check Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: NivioTheme.netflixRed,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeList(List<NewEpisode> episodes) {
    // Group episodes by show
    final Map<int, List<NewEpisode>> groupedByShow = {};
    for (final episode in episodes) {
      groupedByShow.putIfAbsent(episode.showId, () => []).add(episode);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: groupedByShow.length,
      itemBuilder: (context, index) {
        final showId = groupedByShow.keys.elementAt(index);
        final showEpisodes = groupedByShow[showId]!;
        final firstEpisode = showEpisodes.first;

        return _buildShowCard(context, showId, showEpisodes, firstEpisode);
      },
    );
  }

  Widget _buildShowCard(
    BuildContext context,
    int showId,
    List<NewEpisode> episodes,
    NewEpisode firstEpisode,
  ) {
    final hasUnread = episodes.any((e) => !e.isRead);
    final posterUrl = firstEpisode.posterPath != null
        ? '$tmdbImageBaseUrl/$posterSize${firstEpisode.posterPath}'
        : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: hasUnread
            ? NivioTheme.netflixRed.withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: hasUnread
            ? Border.all(color: NivioTheme.netflixRed.withOpacity(0.3))
            : null,
      ),
      child: InkWell(
        onTap: () {
          // Mark all episodes as read and navigate to show
          for (final ep in episodes) {
            EpisodeCheckService.markAsRead(ep.key);
          }
          _refreshEpisodes();
          context.push('/media/$showId?type=tv');
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: posterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: posterUrl,
                        width: 60,
                        height: 90,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 60,
                          height: 90,
                          color: NivioTheme.netflixDarkGrey,
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: NivioTheme.netflixRed,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 60,
                          height: 90,
                          color: NivioTheme.netflixDarkGrey,
                          child: const Icon(Icons.tv, color: Colors.white54),
                        ),
                      )
                    : Container(
                        width: 60,
                        height: 90,
                        color: NivioTheme.netflixDarkGrey,
                        child: const Icon(Icons.tv, color: Colors.white54),
                      ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (hasUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: const BoxDecoration(
                              color: NivioTheme.netflixRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            firstEpisode.showName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      episodes.length == 1
                          ? 'S${firstEpisode.seasonNumber}E${firstEpisode.episodeNumber}'
                          : '${episodes.length} new episodes',
                      style: TextStyle(
                        color: NivioTheme.netflixRed.withOpacity(0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (episodes.length == 1)
                      Text(
                        firstEpisode.episodeName,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        episodes
                            .take(3)
                            .map((e) => 'S${e.seasonNumber}E${e.episodeNumber}')
                            .join(', ') +
                            (episodes.length > 3 ? '...' : ''),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Aired ${DateFormat.yMMMd().format(firstEpisode.airDate)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Arrow
              Icon(
                Icons.chevron_right,
                color: Colors.white.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
