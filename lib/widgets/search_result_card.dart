import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/services/tmdb_service.dart';

class SearchResultCard extends StatelessWidget {
  final SearchResult media;

  const SearchResultCard({super.key, required this.media});

  @override
  Widget build(BuildContext context) {
    final tmdbService = TmdbService();
    final posterUrl = tmdbService.getPosterUrl(media.posterPath);

    return GestureDetector(
      onTap: () {
        context.push('/media/${media.id}?type=${media.mediaType}');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: posterUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (context, url) => Container(
                        color: NivioTheme.netflixDarkGrey,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: NivioTheme.netflixRed,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: NivioTheme.netflixDarkGrey,
                        child: const Icon(
                          Icons.movie,
                          color: NivioTheme.netflixGrey,
                          size: 48,
                        ),
                      ),
                    )
                  : Container(
                      color: NivioTheme.netflixDarkGrey,
                      child: const Icon(
                        Icons.movie,
                        color: NivioTheme.netflixGrey,
                        size: 48,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          // Title
          Text(
            media.title ?? media.name ?? 'Unknown',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          // Media type and year
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: NivioTheme.netflixRed,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  media.mediaType.toUpperCase(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _getYear(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: NivioTheme.netflixGrey,
                      fontSize: 10,
                    ),
              ),
            ],
          ),
        ],
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
