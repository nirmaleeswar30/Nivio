import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/season_info.dart';
import 'package:nivio/providers/dynamic_colors_provider.dart';
import 'package:nivio/providers/media_provider.dart';

class EpisodeList extends ConsumerStatefulWidget {
  final SearchResult media;
  final int season;
  final DynamicColors colors;
  final ScrollController? scrollController;

  const EpisodeList({
    super.key,
    required this.media,
    required this.season,
    required this.colors,
    this.scrollController,
  });

  @override
  ConsumerState<EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends ConsumerState<EpisodeList> {
  static const int _pageSize = 50;
  static const double _scrollThreshold = 400;

  String _searchQuery = '';
  int _displayedCount = _pageSize;
  bool _hasMore = false;
  bool _nearBottom = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(EpisodeList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
    }
    if (oldWidget.season != widget.season) {
      _searchController.clear();
      setState(() {
        _searchQuery = '';
        _displayedCount = _pageSize;
        _nearBottom = false;
      });
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final sc = widget.scrollController;
    if (sc == null || !sc.hasClients) return;
    final isNear = sc.position.extentAfter < _scrollThreshold;
    if (isNear && !_nearBottom && _hasMore) {
      _nearBottom = true;
      setState(() => _displayedCount += _pageSize);
    } else if (!isNear && _nearBottom) {
      _nearBottom = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasonDataAsync = ref.watch(
      seasonDataProvider((
        showId: widget.media.id,
        seasonNumber: widget.season,
      )),
    );

    return seasonDataAsync.when(
      data: (seasonData) {
        final filteredEpisodes = _searchQuery.isEmpty
            ? seasonData.episodes
            : seasonData.episodes.where((ep) {
                final query = _searchQuery.toLowerCase();
                final name = ep.episodeName?.toLowerCase() ?? '';
                final number = ep.episodeNumber.toString();
                return name.contains(query) || number.contains(query);
              }).toList();

        _hasMore = filteredEpisodes.length > _displayedCount;
        final visibleEpisodes = filteredEpisodes.take(_displayedCount).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() {
                _searchQuery = value;
                _displayedCount = _pageSize;
              }),
              style: const TextStyle(
                color: NivioTheme.netflixWhite,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Search episodes',
                hintStyle: const TextStyle(color: NivioTheme.netflixGrey),
                prefixIcon: Icon(
                  Icons.search,
                  color: NivioTheme.netflixLightGrey.withValues(alpha: 0.7),
                  size: 20,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _displayedCount = _pageSize;
                          });
                        },
                        icon: Icon(
                          Icons.close,
                          color: NivioTheme.netflixLightGrey.withValues(
                            alpha: 0.7,
                          ),
                          size: 18,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0x1FFFFFFF),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: Color(0x26FFFFFF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: NivioTheme.netflixRed),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (filteredEpisodes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off,
                        color: widget.colors.onSurface.withValues(alpha: 0.4),
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No episodes match "$_searchQuery"',
                        style: TextStyle(
                          color: widget.colors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              ...visibleEpisodes.asMap().entries.map(
                (entry) => _buildEpisodeCard(entry.key, entry.value),
              ),
              if (_hasMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: NivioTheme.netflixRed,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: NivioTheme.netflixRed),
      ),
      error: (err, stack) => Text(
        'Error loading episodes: $err',
        style: const TextStyle(color: NivioTheme.netflixLightGrey),
      ),
    );
  }

  Widget _buildEpisodeCard(int index, EpisodeData episode) {
    final stillPath = episode.stillPath;
    final stillUrl = stillPath == null || stillPath.isEmpty
        ? ''
        : stillPath.startsWith('http://') || stillPath.startsWith('https://')
        ? stillPath
        : '$tmdbImageBaseUrl/w500$stillPath';

    final bgColor = index.isEven ? const Color(0x0EFFFFFF) : Colors.transparent;
    final isUnaired = _isUnaired(episode.airDate);
    final relDate = _relativeDate(episode.airDate);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (!isUnaired)
            Positioned(
              left: -30,
              top: -40,
              width: 240,
              height: 200,
              child: IgnorePointer(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 55,
                    sigmaY: 55,
                    tileMode: TileMode.decal,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topLeft,
                        radius: 1,
                        colors: [
                          widget.colors.dominant.withValues(alpha: 0.18),
                          widget.colors.dominant.withValues(alpha: 0.06),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Material(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                context.push(
                  '/player/${widget.media.id}?season=${widget.season}&episode=${episode.episodeNumber}',
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (!isUnaired) ...[
                      SizedBox(
                        width: 130,
                        height: 80,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: stillUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: stillUrl,
                                      width: 140,
                                      height: 90,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          _thumbPlaceholder(),
                                      errorWidget: (context, url, error) =>
                                          _thumbError(),
                                    )
                                  : _thumbError(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${episode.episodeNumber}. ${episode.episodeName ?? 'Episode ${episode.episodeNumber}'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: NivioTheme.netflixWhite,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (relDate.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              relDate,
                              style: TextStyle(
                                fontSize: 11,
                                color: isUnaired
                                    ? NivioTheme.netflixGrey.withValues(
                                        alpha: 0.6,
                                      )
                                    : NivioTheme.netflixGrey,
                              ),
                            ),
                          ],
                          if (!isUnaired) ...[
                            const SizedBox(height: 4),
                            Text(
                              episode.overview ?? '',
                              style: const TextStyle(
                                fontSize: 12,
                                color: NivioTheme.netflixLightGrey,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isUnaired(String? airDate) {
    if (airDate == null || airDate.isEmpty) return true;
    try {
      final date = DateTime.parse(airDate);
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      return DateTime(date.year, date.month, date.day).isAfter(today);
    } catch (_) {
      return true;
    }
  }

  String _relativeDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      final target = DateTime(date.year, date.month, date.day);
      final diff = target.difference(today).inDays;

      if (diff == 0) return 'Today';
      if (diff == 1) return 'Tomorrow';
      if (diff == -1) return 'Yesterday';

      if (diff > 0) {
        if (diff < 7) return 'In $diff days';
        if (diff < 14) return 'In 1 week';
        if (diff < 21) return 'In 2 weeks';
        if (diff < 28) return 'In 3 weeks';
        if (diff >= 365) {
          final years = (diff / 365.25).round();
          return 'In ${years == 1 ? '1 year' : '$years years'}';
        }
        final months = (diff / 30.5).round();
        return 'In ${months == 1 ? '1 month' : '$months months'}';
      }

      final abs = diff.abs();
      if (abs < 7) return '$abs days ago';
      if (abs < 14) return '1 week ago';
      if (abs < 21) return '2 weeks ago';
      if (abs < 28) return '3 weeks ago';
      if (abs >= 365) {
        final years = (abs / 365.25).round();
        return '${years == 1 ? '1 year' : '$years years'} ago';
      }
      final months = (abs / 30.5).round();
      return '${months == 1 ? '1 month' : '$months months'} ago';
    } catch (_) {
      return '';
    }
  }

  Widget _thumbPlaceholder() => Container(
    width: 100,
    height: 75,
    color: const Color(0x33262C3D),
    child: const Center(
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: NivioTheme.netflixRed,
        ),
      ),
    ),
  );

  Widget _thumbError() => Container(
    width: 100,
    height: 75,
    color: const Color(0x33262C3D),
    child: const Icon(
      Icons.ondemand_video,
      color: NivioTheme.netflixGrey,
      size: 24,
    ),
  );
}
