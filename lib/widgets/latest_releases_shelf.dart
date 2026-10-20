import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:nivio/widgets/skeleton.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Extracts the release date / air date from any shelf or search item.
DateTime? extractReleaseDate(dynamic item) {
  if (item == null) return null;
  if (item is SearchResult) {
    final raw = item.releaseDate ?? item.firstAirDate;
    if (raw != null && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }
  if (item is Map) {
    final airingAt = item['airing_at'];
    if (airingAt != null && airingAt is num && airingAt > 0) {
      return DateTime.fromMillisecondsSinceEpoch(airingAt.toInt() * 1000);
    }
    final digital = item['digital_release_date']?.toString();
    if (digital != null && digital.isNotEmpty) {
      final parsed = DateTime.tryParse(digital);
      if (parsed != null) return parsed;
    }
    final raw = (item['release_date'] ?? item['first_air_date'])?.toString();
    if (raw != null && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
  }
  return null;
}

/// Comparator to sort items by newest/latest release date first (descending).
int compareReleaseDates(dynamic a, dynamic b) {
  final dateA = extractReleaseDate(a);
  final dateB = extractReleaseDate(b);
  if (dateA == null && dateB == null) return 0;
  if (dateA == null) return 1;
  if (dateB == null) return -1;
  return dateB.compareTo(dateA);
}

class LatestReleasesShelf extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<dynamic> items;
  final String badgeText;
  final List<Color> badgeGradient;
  final IconData badgeIcon;
  final bool isAnime;
  final VoidCallback? onSeeAll;

  const LatestReleasesShelf({
    super.key,
    required this.title,
    this.subtitle,
    required this.items,
    required this.badgeText,
    required this.badgeGradient,
    required this.badgeIcon,
    this.isAnime = false,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    // Order items so the latest release is first, followed by previous releases
    final sortedItems = List<dynamic>.from(items)..sort(compareReleaseDates);

    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final cardWidth = isDesktop ? 280.0 : 240.0;
    final cardHeight = isDesktop ? 160.0 : 142.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shelf Header
          Padding(
            padding: EdgeInsets.only(
              left: isDesktop ? 68 : 16,
              right: 16,
              bottom: 12,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // Glowing Accent Bar
                      Container(
                        width: 4,
                        height: 22,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: badgeGradient,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (onSeeAll != null)
                  _ShelfMoreButton(
                    accentColor: badgeGradient.first,
                    onTap: onSeeAll!,
                  ),
              ],
            ),
          ),

          // Horizontal Shelf Cards
          SizedBox(
            height: cardHeight + 16,
            child: AppListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(
                left: isDesktop ? 64 : 12,
                right: 12,
                top: 8,
                bottom: 8,
              ),
              itemCount: sortedItems.length,
              cacheExtent: isDesktop ? 800 : 350,
              scrollSpeed: 2.0,
              silkyScrollDuration: const Duration(milliseconds: 500),
              animationCurve: Curves.easeOutQuart,
              itemBuilder: (context, index) {
                final item = sortedItems[index];
                final id = item is Map ? item['id'] : (item is SearchResult ? item.id : index);
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: isDesktop ? 8 : 4),
                  child: LatestReleaseCard(
                    key: ValueKey('shelf_${badgeText}_${id}_$index'),
                    item: item,
                    width: cardWidth,
                    height: cardHeight,
                    badgeText: badgeText,
                    badgeGradient: badgeGradient,
                    badgeIcon: badgeIcon,
                    isAnime: isAnime,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfMoreButton extends StatefulWidget {
  final Color accentColor;
  final VoidCallback onTap;

  const _ShelfMoreButton({
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_ShelfMoreButton> createState() => _ShelfMoreButtonState();
}

class _ShelfMoreButtonState extends State<_ShelfMoreButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.accentColor.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? widget.accentColor.withValues(alpha: 0.35)
                  : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'More',
                style: TextStyle(
                  color: widget.accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedSlide(
                offset: _isHovered ? const Offset(0.25, 0) : Offset.zero,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: widget.accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LatestReleaseCard extends StatefulWidget {
  final dynamic item;
  final double? width;
  final double? height;
  final String badgeText;
  final List<Color> badgeGradient;
  final IconData badgeIcon;
  final bool isAnime;

  const LatestReleaseCard({
    super.key,
    required this.item,
    this.width,
    this.height,
    required this.badgeText,
    required this.badgeGradient,
    required this.badgeIcon,
    this.isAnime = false,
  });

  @override
  State<LatestReleaseCard> createState() => _LatestReleaseCardState();
}

class _LatestReleaseCardState extends State<LatestReleaseCard> {
  bool _isHovered = false;

  String _formatReleaseTag(dynamic rawDate, dynamic digitalDate, dynamic airingAtSec) {
    DateTime? date;
    if (airingAtSec != null && airingAtSec is num && airingAtSec > 0) {
      date = DateTime.fromMillisecondsSinceEpoch(airingAtSec.toInt() * 1000);
    } else if (digitalDate != null && digitalDate.toString().isNotEmpty) {
      date = DateTime.tryParse(digitalDate.toString());
    } else if (rawDate != null && rawDate.toString().isNotEmpty) {
      date = DateTime.tryParse(rawDate.toString());
    }
    if (date == null) return '';

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.isNegative) {
      return 'Today';
    }
    if (diff.inMinutes < 60) {
      final mins = diff.inMinutes.clamp(1, 59);
      return '${mins}m ago';
    }
    if (diff.inHours < 24 && date.day == now.day && date.month == now.month && date.year == now.year) {
      return '${diff.inHours}h ago';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) {
      return 'Yesterday';
    }
    if (diff.inDays <= 7 && diff.inDays > 0) {
      return '${diff.inDays}d ago';
    }

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final yearSuffix = date.year != now.year ? ', ${date.year}' : '';
    return '${months[date.month - 1]} ${date.day}$yearSuffix';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    int id = 0;
    String title = '';
    String? posterPath;
    String? backdropPath;
    double? voteAverage;
    String mediaType = widget.isAnime ? 'anime' : 'movie';
    int? episodeNumber;
    dynamic rawDate;
    dynamic digitalDate;
    dynamic airingAtSec;

    if (item is SearchResult) {
      id = item.id;
      title = item.title ?? item.name ?? '';
      posterPath = item.posterPath;
      backdropPath = item.backdropPath;
      voteAverage = item.voteAverage;
      mediaType = item.mediaType;
      rawDate = item.releaseDate ?? item.firstAirDate;
    } else if (item is Map) {
      id = item['id'] as int? ?? 0;
      title = (item['title'] ?? item['name'] ?? '').toString();
      posterPath = item['poster_path']?.toString();
      backdropPath = item['backdrop_path']?.toString();
      voteAverage = (item['vote_average'] as num?)?.toDouble();
      mediaType = (item['media_type'] ?? (widget.isAnime ? 'anime' : (item['name'] != null ? 'tv' : 'movie'))).toString();
      episodeNumber = item['episode_number'] as int?;
      digitalDate = item['digital_release_date'];
      rawDate = item['release_date'] ?? item['first_air_date'];
      airingAtSec = item['airing_at'];
    }

    final imageUrl = (backdropPath != null && backdropPath.isNotEmpty)
        ? (backdropPath.startsWith('http') ? backdropPath : '$tmdbImageBaseUrl/w780$backdropPath')
        : (posterPath != null && posterPath.isNotEmpty)
            ? (posterPath.startsWith('http') ? posterPath : '$tmdbImageBaseUrl/w500$posterPath')
            : null;

    final releaseTag = _formatReleaseTag(rawDate, digitalDate, airingAtSec);

    void handleTap() {
      if (id == 0) return;
      GoRouter.of(context).push('/media/$id?type=$mediaType');
    }

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: handleTap,
          child: AnimatedScale(
            scale: _isHovered ? 1.025 : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                color: const Color(0xFF14171F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isHovered
                      ? widget.badgeGradient.first
                      : const Color(0x1AFFFFFF),
                  width: 1.2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                  // Backdrop Image
                  if (imageUrl != null)
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 600,
                      filterQuality: FilterQuality.low,
                      placeholder: (context, url) => const DecoratedBox(
                        decoration: BoxDecoration(color: Color(0xFF1B1E28)),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: const Color(0xFF1B1E28),
                        child: Center(
                          child: Icon(
                            widget.badgeIcon,
                            color: Colors.white24,
                            size: 32,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: const Color(0xFF1B1E28),
                      child: Center(
                        child: Icon(
                          widget.badgeIcon,
                          color: Colors.white24,
                          size: 32,
                        ),
                      ),
                    ),

                  // Seamless bottom gradient scrim anchored to the bottom border edge
                  const Positioned(
                    bottom: -2,
                    left: 0,
                    right: 0,
                    height: 72,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.0, 0.4, 0.75, 1.0],
                          colors: [
                            Colors.transparent,
                            Color(0x66000000),
                            Color(0xCC000000),
                            Colors.black,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Top-Left Badge (only for items with an episode number)
                  if (episodeNumber != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xB8000000),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: widget.badgeGradient.first.withValues(alpha: 0.6),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIconsFill.playCircle,
                              size: 11,
                              color: widget.badgeGradient.first,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'EP $episodeNumber',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Top-Right Rating Chip
                  if (voteAverage != null && voteAverage > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xB8000000),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0x26FFFFFF),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: Color(0xFFFFC107),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              voteAverage.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Bottom Metadata & Title
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 9,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),

                        // Meta details row
                        if (releaseTag.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                PhosphorIconsRegular.clock,
                                size: 11,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                releaseTag,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 11,
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
        ),
      ),
    ),
  );
  }
}

class LatestReleasesShelfSkeleton extends StatelessWidget {
  final String title;

  const LatestReleasesShelfSkeleton({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final cardWidth = isDesktop ? 280.0 : 240.0;
    final cardHeight = isDesktop ? 160.0 : 142.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: isDesktop ? 68 : 16,
              right: 16,
              bottom: 12,
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF23262E),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: cardHeight + 16,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                left: isDesktop ? 64 : 12,
                right: 12,
                top: 8,
                bottom: 8,
              ),
              itemCount: 5,
              itemBuilder: (_, __) => Padding(
                padding: EdgeInsets.symmetric(horizontal: isDesktop ? 8 : 4),
                child: Container(
                  width: cardWidth,
                  height: cardHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF14171F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      SkeletonBox(
                        width: cardWidth,
                        height: cardHeight,
                        borderRadius: BorderRadius.zero,
                      ),
                      Positioned(
                        top: 9,
                        left: 9,
                        child: SkeletonBox(
                          width: 80,
                          height: 18,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      Positioned(
                        bottom: 9,
                        left: 10,
                        right: 10,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SkeletonBox(
                              width: cardWidth * 0.65,
                              height: 14,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            const SizedBox(height: 6),
                            SkeletonBox(
                              width: cardWidth * 0.35,
                              height: 11,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
