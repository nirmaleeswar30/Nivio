import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/services/anilist_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SimilarContentScreen extends ConsumerWidget {
  final int mediaId;
  final String mediaType;
  final String title;

  const SimilarContentScreen({
    super.key,
    required this.mediaId,
    required this.mediaType,
    required this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'More like $title',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                color: Colors.black.withValues(alpha: 0.65),
              ),
            ),
          ),
          SafeArea(
            child: FutureBuilder<List<SearchResult>>(
              future: mediaType == 'anime' 
                  ? AniListService().getAnimeRecommendations(mediaId)
                  : ref.read(tmdbServiceProvider).getRecommendations(mediaId, mediaType),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: NivioTheme.accentColorOf(context)),
                  );
                }
                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'No similar content found',
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 40),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 20),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final tmdbService = ref.read(tmdbServiceProvider);
                    final displayTitle = item.title ?? item.name ?? 'Unknown';
                    
                    // Format year
                    final dateStr = item.releaseDate ?? item.firstAirDate ?? '';
                    final year = dateStr.isNotEmpty ? dateStr.split('-').first : '';
                    
                    // Format rating
                    final rating = item.voteAverage != null && item.voteAverage! > 0 
                        ? item.voteAverage!.toStringAsFixed(1) 
                        : '';

                    return GestureDetector(
                      onTap: () {
                        context.push('/media/${item.id}?type=${item.mediaType}');
                      },
                      child: Container(
                        height: 160,
                        decoration: BoxDecoration(
                          color: const Color(0x1AFFFFFF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x1AFFFFFF)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Poster
                            ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                bottomLeft: Radius.circular(12),
                              ),
                              child: AspectRatio(
                                aspectRatio: 0.68,
                                child: item.posterPath != null
                                    ? CachedNetworkImage(
                                        imageUrl: tmdbService.getPosterUrl(item.posterPath),
                                        fit: BoxFit.cover,
                                      )
                                    : Container(color: NivioTheme.netflixDarkGrey),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Details
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayTitle,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        if (rating.isNotEmpty) ...[
                                          const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                          const SizedBox(width: 4),
                                          Text(
                                            rating,
                                            style: const TextStyle(
                                              color: Colors.amber,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                        ],
                                        if (year.isNotEmpty)
                                          Text(
                                            year,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.7),
                                              fontSize: 13,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: Text(
                                        item.overview?.isNotEmpty == true 
                                            ? item.overview! 
                                            : 'No description available.',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.6),
                                          fontSize: 12,
                                          height: 1.4,
                                        ),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
