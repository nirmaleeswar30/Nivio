import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/service_providers.dart';
import 'dart:io';
import 'package:nivio/widgets/search_result_card.dart';

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
                  ? ref.read(aniListServiceProvider).getAnimeRecommendations(mediaId)
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
                final isDesktop = !Platform.isAndroid && !Platform.isIOS;
                final columns = isDesktop ? 4 : 2;
                final aspectRatio = isDesktop ? 0.64 : 0.60;

                return GridView.builder(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 40),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: aspectRatio,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return SearchResultCard(
                      key: ValueKey('${item.mediaType}_${item.id}'),
                      media: item,
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
