import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:nivio/widgets/hover_preview_card.dart';
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
                          boxShadow: [
                            BoxShadow(
                              color: badgeGradient.first.withValues(alpha: 0.6),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
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
                  InkWell(
                    onTap: onSeeAll,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'More',
                            style: TextStyle(
                              color: badgeGradient.first,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 11,
                            color: badgeGradient.first,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Horizontal Shelf Cards
          SizedBox(
            height: cardHeight + 8,
            child: AppListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(
                left: isDesktop ? 64 : 12,
                right: 12,
                top: 4,
                bottom: 4,
              ),
              itemCount: sortedItems.length,
              cacheExtent: 350,
              scrollSpeed: 2.0,
              silkyScrollDuration: const Duration(milliseconds: 500),
              animationCurve: Curves.easeOutQuart,
              itemBuilder: (context, index) {
                final item = sortedItems[index];
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: isDesktop ? 8 : 4),
                  child: LatestReleaseCard(
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

class LatestReleaseCard extends ConsumerStatefulWidget {
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
  ConsumerState<LatestReleaseCard> createState() => _LatestReleaseCardState();
}

class _LatestReleaseCardState extends ConsumerState<LatestReleaseCard> {
  bool _isHovered = false;
  String? _resolvedDigitalDate;

  @override
  void initState() {
    super.initState();
    _resolveDigitalDateIfNeeded();
  }

  @override
  void didUpdateWidget(covariant LatestReleaseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) {
      _resolveDigitalDateIfNeeded();
    }
  }

  void _resolveDigitalDateIfNeeded() {
    if (widget.isAnime) return;
    final item = widget.item;
    int? id;
    String? mediaType;
    String? existingDigital;

    if (item is Map) {
      id = item['id'] as int?;
      mediaType = (item['media_type'] ?? (item['name'] != null ? 'tv' : 'movie')).toString();
      existingDigital = item['digital_release_date']?.toString();
    } else if (item is SearchResult) {
      id = item.id;
      mediaType = item.mediaType;
    }

    if (mediaType == 'movie' && (existingDigital == null || existingDigital.isEmpty) && id != null && id > 0) {
      ref.read(tmdbServiceProvider).getMovieDigitalReleaseDate(id).then((resolved) {
        if (resolved != null && mounted) {
          setState(() => _resolvedDigitalDate = resolved);
        }
      });
    }
  }

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

    final effectiveDigitalDate = digitalDate ?? _resolvedDigitalDate;
    final releaseTag = _formatReleaseTag(rawDate, effectiveDigitalDate, airingAtSec);
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    void handleTap() {
      if (id == 0) return;
      GoRouter.of(context).push('/media/$id?type=$mediaType');
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _isHovered = true);
        if (isDesktop && id > 0) {
          unawaited(HoverPreviewCard.prefetch(ref, id, mediaType, title));
        }
      },
      onExit: (_) {
        setState(() => _isHovered = false);
      },
      child: GestureDetector(
        onTap: handleTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: const Color(0xFF14171F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isHovered
                    ? widget.badgeGradient.first.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.08),
                width: _isHovered ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isHovered
                      ? widget.badgeGradient.first.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.4),
                  blurRadius: _isHovered ? 18 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Backdrop Image
                if (imageUrl != null)
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 600,
                    placeholder: (context, url) => Container(
                      color: const Color(0xFF1B1E28),
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

                // Top Vignette (for badge legibility)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 50,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.65),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Deep Bottom Gradient Vignette (for text legibility)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: widget.height != null ? widget.height! * 0.68 : 110,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.45, 1.0],
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.65),
                          const Color(0xFF090B10).withValues(alpha: 0.96),
                        ],
                      ),
                    ),
                  ),
                ),

                // Top-Left Floating Frosted Badge (only for items with an episode number)
                if (episodeNumber != null)
                  Positioned(
                    top: 9,
                    left: 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                widget.badgeGradient.first.withValues(alpha: 0.85),
                                widget.badgeGradient.last.withValues(alpha: 0.75),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                PhosphorIconsFill.playCircle,
                                size: 11,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'EP $episodeNumber',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Top-Right Glassmorphic Rating Chip
                if (voteAverage != null && voteAverage > 0)
                  Positioned(
                    top: 9,
                    right: 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
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
                    ),
                  ),

                // Center Play Button (revealed on hover)
                Center(
                  child: AnimatedOpacity(
                    opacity: _isHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.6),
                        border: Border.all(
                          color: widget.badgeGradient.first.withValues(alpha: 0.8),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.badgeGradient.first.withValues(alpha: 0.4),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
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
                              blurRadius: 6,
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
            height: cardHeight + 8,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                left: isDesktop ? 64 : 12,
                right: 12,
                top: 4,
                bottom: 4,
              ),
              itemCount: 5,
              itemBuilder: (_, __) => Padding(
                padding: EdgeInsets.symmetric(horizontal: isDesktop ? 8 : 4),
                child: Container(
                  width: cardWidth,
                  height: cardHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF14171F),
                    borderRadius: BorderRadius.circular(14),
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
