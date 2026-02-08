import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/service_providers.dart';

class SearchResultCard extends ConsumerWidget {
  final SearchResult media;

  const SearchResultCard({super.key, required this.media});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tmdbService = ref.watch(tmdbServiceProvider);
    final posterUrl = tmdbService.getPosterUrl(media.posterPath);
    final title = media.title ?? media.name ?? 'Unknown';
    final year = _getYear();
    final rating = media.voteAverage;
    final language = (media.originalLanguage ?? '').toUpperCase();

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        context.push('/media/${media.id}?type=${media.mediaType}');
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          color: const Color(0xFF1A1A1A),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (posterUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: posterUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, url) => Container(
                          color: NivioTheme.netflixDarkGrey,
                          child: const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: NivioTheme.netflixRed,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: NivioTheme.netflixDarkGrey,
                          child: const Icon(
                            Icons.movie_creation_outlined,
                            color: NivioTheme.netflixGrey,
                            size: 42,
                          ),
                        ),
                      )
                    else
                      Container(
                        color: NivioTheme.netflixDarkGrey,
                        child: const Icon(
                          Icons.movie_creation_outlined,
                          color: NivioTheme.netflixGrey,
                          size: 42,
                        ),
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.05),
                            Colors.black.withValues(alpha: 0.72),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _TagPill(
                        label: media.mediaType.toUpperCase(),
                        background: NivioTheme.netflixRed.withValues(
                          alpha: 0.92,
                        ),
                        foreground: Colors.white,
                      ),
                    ),
                    if (year != 'N/A')
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _TagPill(
                          label: year,
                          background: Colors.black.withValues(alpha: 0.65),
                          foreground: Colors.white,
                        ),
                      ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Row(
                        children: [
                          if (rating != null && rating > 0)
                            _TagPill(
                              icon: Icons.star_rounded,
                              label: rating.toStringAsFixed(1),
                              background: Colors.amber.withValues(alpha: 0.92),
                              foreground: Colors.black,
                            ),
                          if (language.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _TagPill(
                              label: language,
                              background: Colors.white.withValues(alpha: 0.14),
                              foreground: Colors.white,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  height: 1.22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getYear() {
    final date = media.releaseDate ?? media.firstAirDate;
    if (date != null && date.isNotEmpty && date.length >= 4) {
      return date.substring(0, 4);
    }
    return 'N/A';
  }
}

class _TagPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color background;
  final Color foreground;

  const _TagPill({
    this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
