import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:nivio/widgets/search_result_card.dart';
import 'package:nivio/widgets/skeleton.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class SimilarContentScreen extends ConsumerStatefulWidget {
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
  ConsumerState<SimilarContentScreen> createState() => _SimilarContentScreenState();
}

class _SimilarContentScreenState extends ConsumerState<SimilarContentScreen> {
  late Future<List<SearchResult>> _recommendationsFuture;

  @override
  void initState() {
    super.initState();
    _fetchRecommendations();
  }

  void _fetchRecommendations() {
    _recommendationsFuture = widget.mediaType == 'anime'
        ? ref.read(aniListServiceProvider).getAnimeRecommendations(widget.mediaId)
        : ref.read(tmdbServiceProvider).getRecommendations(widget.mediaId, widget.mediaType);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    return Scaffold(
      backgroundColor: NivioTheme.netflixBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const PhosphorIcon(PhosphorIconsRegular.caretLeft, color: Colors.white),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: Text(
          widget.title.isNotEmpty ? 'More like ${widget.title}' : 'More Like This',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF151922),
              NivioTheme.netflixBlack,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: FutureBuilder<List<SearchResult>>(
            future: _recommendationsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return PosterGridSkeleton(
                  padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16, 16, isDesktop ? 68 : 16, 40),
                  maxCrossAxisExtent: isDesktop ? 180 : 185,
                  childAspectRatio: 0.65,
                  itemCount: isDesktop ? 18 : 8,
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 56,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load similar content',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _fetchRecommendations();
                          });
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Try Again'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NivioTheme.accentColorOf(context),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.movie_filter_outlined,
                        size: 64,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No similar content found',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return AppGridView.builder(
                padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16, 16, isDesktop ? 68 : 16, 40),
                cacheExtent: isDesktop ? 1000 : 350,
                scrollSpeed: 2.0,
                silkyScrollDuration: const Duration(milliseconds: 500),
                animationCurve: Curves.easeOutQuart,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: isDesktop ? 180 : 185,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 14,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _SimilarHoverCard(
                    key: ValueKey('${item.mediaType}_${item.id}'),
                    child: SearchResultCard(
                      media: item,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Interactive hover card with smooth scale and soft drop-shadow animation on desktop.
class _SimilarHoverCard extends StatefulWidget {
  final Widget child;

  const _SimilarHoverCard({
    super.key,
    required this.child,
  });

  @override
  State<_SimilarHoverCard> createState() => _SimilarHoverCardState();
}

class _SimilarHoverCardState extends State<_SimilarHoverCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _isHovered ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
