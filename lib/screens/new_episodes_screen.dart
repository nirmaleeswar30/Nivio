import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/new_episode.dart';
import 'package:nivio/services/episode_check_service.dart';

final newEpisodesProvider = StateProvider<List<NewEpisode>>((ref) {
  return EpisodeCheckService.getNewEpisodes();
});

final unreadEpisodeCountProvider = StateProvider<int>((ref) {
  return EpisodeCheckService.getUnreadCount();
});

enum _EpisodeFilter { all, unread, read }

class NewEpisodesScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const NewEpisodesScreen({super.key, this.embedded = false});

  @override
  ConsumerState<NewEpisodesScreen> createState() => _NewEpisodesScreenState();
}

class _NewEpisodesScreenState extends ConsumerState<NewEpisodesScreen> {
  _EpisodeFilter _filter = _EpisodeFilter.all;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_refreshEpisodes);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshEpisodes() async {
    if (!mounted) return;
    ref.read(newEpisodesProvider.notifier).state =
        EpisodeCheckService.getNewEpisodes();
    ref.read(unreadEpisodeCountProvider.notifier).state =
        EpisodeCheckService.getUnreadCount();
  }

  Future<void> _markAllAsRead() async {
    await EpisodeCheckService.markAllAsRead();
    await _refreshEpisodes();
  }

  Future<void> _clearAll() async {
    await EpisodeCheckService.clearAll();
    await _refreshEpisodes();
  }

  Future<void> _checkNow() async {
    final count = await EpisodeCheckService.checkNow();
    await _refreshEpisodes();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? 'Found $count new episode${count > 1 ? 's' : ''}'
              : 'No new episodes found',
        ),
        backgroundColor: NivioTheme.accentColorOf(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final episodes = ref.watch(newEpisodesProvider);
    final unreadCount = ref.watch(unreadEpisodeCountProvider);
    final grouped = _buildGroupedEpisodes(episodes);

    final content = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF151922), NivioTheme.netflixBlack],
        ),
      ),
      child: SafeArea(
        top: !widget.embedded,
        child: CustomScrollView(
          slivers: [
            if (!widget.embedded)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _buildTopBar(),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  widget.embedded ? 10 : 14,
                  16,
                  0,
                ),
                child: _buildSummaryCard(
                  totalCount: episodes.length,
                  unreadCount: unreadCount,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: _buildSearchAndFilters(),
              ),
            ),
            if (grouped.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverList.builder(
                itemCount: grouped.length,
                itemBuilder: (context, index) {
                  final showId = grouped.keys.elementAt(index);
                  final showEpisodes = grouped[showId]!;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      index == 0 ? 16 : 10,
                      16,
                      index == grouped.length - 1 ? 24 : 0,
                    ),
                    child: _buildShowCard(showId, showEpisodes),
                  );
                },
              ),
          ],
        ),
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(backgroundColor: NivioTheme.netflixBlack, body: content);
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        IconButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/home');
          },
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        const SizedBox(width: 4),
        const Text(
          'New Episodes',
          style: TextStyle(
            color: NivioTheme.netflixWhite,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        PopupMenuButton<String>(
          color: NivioTheme.netflixDarkGrey,
          icon: Icon(Icons.more_horiz, color: NivioTheme.netflixWhite),
          onSelected: (value) async {
            if (value == 'mark_read') {
              await _markAllAsRead();
              return;
            }
            if (value == 'clear') {
              await _clearAll();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'mark_read',
              child: Row(
                children: [
                  Icon(
                    Icons.done_all,
                    color: NivioTheme.netflixWhite,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Text('Mark all as read'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    color: NivioTheme.netflixWhite,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Text('Clear all'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required int totalCount,
    required int unreadCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildMetric('Unread', unreadCount.toString()),
              const SizedBox(width: 10),
              _buildMetric('Total', totalCount.toString()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _markAllAsRead,
                  icon: Icon(Icons.done_all_rounded, size: 18),
                  label: const Text('Mark Read'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _checkNow,
                  icon: Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Check Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NivioTheme.accentColorOf(context),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: NivioTheme.netflixLightGrey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: NivioTheme.netflixWhite,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value.trim()),
          style: TextStyle(color: NivioTheme.netflixWhite, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search shows or episode names...',
            prefixIcon: Icon(
              Icons.search_rounded,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: NivioTheme.accentColorOf(context)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildFilterChip('All', _EpisodeFilter.all),
            const SizedBox(width: 8),
            _buildFilterChip('Unread', _EpisodeFilter.unread),
            const SizedBox(width: 8),
            _buildFilterChip('Read', _EpisodeFilter.read),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, _EpisodeFilter filterValue) {
    final isActive = _filter == filterValue;
    return InkWell(
      onTap: () => setState(() => _filter = filterValue),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? NivioTheme.accentColorOf(context).withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive
                ? NivioTheme.accentColorOf(context).withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildShowCard(int showId, List<NewEpisode> episodes) {
    final first = episodes.first;
    final hasUnread = episodes.any((episode) => !episode.isRead);
    final posterUrl = first.posterPath != null
        ? '$tmdbImageBaseUrl/$posterSize${first.posterPath}'
        : '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          for (final episode in episodes.where((episode) => !episode.isRead)) {
            await EpisodeCheckService.markAsRead(episode.key);
          }
          await _refreshEpisodes();
          if (!mounted) return;
          context.push('/media/$showId?type=tv');
        },
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasUnread
                  ? NivioTheme.accentColorOf(context).withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: posterUrl.isEmpty
                    ? _buildPosterPlaceholder()
                    : CachedNetworkImage(
                        imageUrl: posterUrl,
                        width: 72,
                        height: 108,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            _buildPosterPlaceholder(),
                        errorWidget: (context, url, error) =>
                            _buildPosterPlaceholder(),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            first.showName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: NivioTheme.netflixWhite,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (hasUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(
                              color: NivioTheme.accentColorOf(context),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _metaPill(
                          episodes.length == 1
                              ? 'S${first.seasonNumber}E${first.episodeNumber}'
                              : '${episodes.length} new episodes',
                        ),
                        _metaPill(DateFormat.yMMMd().format(first.airDate)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      episodes.length == 1
                          ? first.episodeName
                          : episodes
                                    .take(3)
                                    .map(
                                      (episode) =>
                                          'S${episode.seasonNumber}E${episode.episodeNumber}',
                                    )
                                    .join(', ') +
                                (episodes.length > 3 ? '...' : ''),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: NivioTheme.netflixLightGrey,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: NivioTheme.netflixGrey,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Open show',
                          style: TextStyle(
                            color: NivioTheme.netflixGrey,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosterPlaceholder() {
    return Container(
      width: 72,
      height: 108,
      color: NivioTheme.netflixDarkGrey,
      child: Icon(Icons.tv_rounded, color: NivioTheme.netflixGrey),
    );
  }

  Widget _metaPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: NivioTheme.netflixWhite,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final message = switch (_filter) {
      _EpisodeFilter.unread => 'No unread episodes',
      _EpisodeFilter.read => 'No read episodes',
      _EpisodeFilter.all => 'No new episodes',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 72,
              color: Colors.white.withValues(alpha: 0.32),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: TextStyle(
                color: NivioTheme.netflixWhite,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Episodes from your watchlist will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NivioTheme.netflixGrey),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _checkNow,
              icon: Icon(Icons.sync_rounded),
              label: const Text('Check Now'),
            ),
          ],
        ),
      ),
    );
  }

  Map<int, List<NewEpisode>> _buildGroupedEpisodes(List<NewEpisode> episodes) {
    final filtered = episodes.where((episode) {
      final matchesFilter = switch (_filter) {
        _EpisodeFilter.all => true,
        _EpisodeFilter.unread => !episode.isRead,
        _EpisodeFilter.read => episode.isRead,
      };

      if (!matchesFilter) return false;
      if (_query.isEmpty) return true;

      final normalized = _query.toLowerCase();
      return episode.showName.toLowerCase().contains(normalized) ||
          episode.episodeName.toLowerCase().contains(normalized);
    }).toList();

    final grouped = <int, List<NewEpisode>>{};
    for (final episode in filtered) {
      grouped.putIfAbsent(episode.showId, () => []).add(episode);
    }
    return grouped;
  }
}
