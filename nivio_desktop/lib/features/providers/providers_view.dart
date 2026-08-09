import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/constants/constants.dart';
import '../../shared/theme/index.dart';
import '../../shared/widgets/widgets.dart';
import '../player/models/playback_request.dart';
import '../player/playback_request_factory.dart';
import '../search/models/search_media_item.dart';
import 'controllers/providers_controller.dart';
import 'models/provider_models.dart';

class ProvidersView extends StatefulWidget {
  const ProvidersView({
    super.key,
    required this.controller,
    this.onOpenDetail,
    this.onPlay,
    this.onBack,
  });

  final ProvidersController controller;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;
  final VoidCallback? onBack;

  @override
  State<ProvidersView> createState() => _ProvidersViewState();
}

class _ProvidersViewState extends State<ProvidersView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
    _searchController.addListener(() {
      widget.controller.setQuery(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack?.call();
      },
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          return DesktopScrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              child: PageContainer(
                maxWidth: 1520,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.xxl,
                    bottom: AppSpacing.massive,
                  ),
                  child: widget.controller.selectedProvider == null
                      ? _AllProvidersPane(
                          controller: widget.controller,
                          searchController: _searchController,
                          onBack: widget.onBack,
                        )
                      : _ProviderContentPane(
                          controller: widget.controller,
                          onOpenDetail: widget.onOpenDetail,
                          onPlay: widget.onPlay,
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AllProvidersPane extends StatelessWidget {
  const _AllProvidersPane({
    required this.controller,
    required this.searchController,
    this.onBack,
  });

  final ProvidersController controller;
  final TextEditingController searchController;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final providers = controller.filteredProviders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (onBack != null) ...[
              IconButton(
                tooltip: 'Back to home',
                onPressed: onBack,
                icon: const Icon(LucideIcons.arrowLeft),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(child: Text('Providers', style: AppTypography.pageTitle)),
            Text(
              '${providers.length} services',
              style: AppTypography.metadata.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Browse movies and TV shows by streaming service',
          style: AppTypography.body,
        ),
        const SizedBox(height: AppSpacing.xl),
        TextField(
          controller: searchController,
          decoration: InputDecoration(
            hintText: 'Search providers...',
            prefixIcon: const Icon(LucideIcons.search),
            suffixIcon: controller.query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(LucideIcons.x),
                    onPressed: searchController.clear,
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        if (providers.isEmpty)
          const EmptyState(
            title: 'No providers found',
            message: 'Try another provider name.',
          )
        else
          ResponsiveGrid(
            minItemWidth: 168,
            maxCrossAxisCount: 6,
            mainAxisSpacing: AppSpacing.lg,
            crossAxisSpacing: AppSpacing.lg,
            childAspectRatio: 1.10,
            children: [
              for (final provider in providers)
                ProviderCard(
                  name: provider.name.trim(),
                  label: 'Browse catalog',
                  logoImage: _providerLogo(provider.logoPath),
                  onTap: () => controller.selectProvider(provider),
                ),
            ],
          ),
      ],
    );
  }
}

class _ProviderContentPane extends StatelessWidget {
  const _ProviderContentPane({
    required this.controller,
    this.onOpenDetail,
    this.onPlay,
  });

  final ProvidersController controller;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    final provider = controller.selectedProvider!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProviderHeader(controller: controller, provider: provider),
        const SizedBox(height: AppSpacing.xxl),
        _ProviderContentBody(
          controller: controller,
          onOpenDetail: onOpenDetail,
          onPlay: onPlay,
        ),
      ],
    );
  }
}

class _ProviderHeader extends StatelessWidget {
  const _ProviderHeader({required this.controller, required this.provider});

  final ProvidersController controller;
  final StreamingProviderItem provider;

  @override
  Widget build(BuildContext context) {
    final logoUrl = _providerLogoUrl(provider.logoPath);
    final fallbackAccent = context.appAccent;

    return FutureBuilder<DynamicArtworkColors>(
      future: dynamicArtworkColorsForUrl(logoUrl),
      builder: (context, snapshot) {
        final accent = snapshot.data?.dominant ?? fallbackAccent;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(AppColors.surface, accent, 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: 'All providers',
                  onPressed: controller.showAllProviders,
                  icon: const Icon(LucideIcons.arrowLeft),
                ),
                const SizedBox(width: AppSpacing.md),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppRadius.large),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _providerLogo(provider.logoPath) == null
                      ? Center(
                          child: Text(
                            provider.name.characters.first,
                            style: AppTypography.sectionTitle,
                          ),
                        )
                      : Image(
                          image: _providerLogo(provider.logoPath)!,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.pageTitle,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final mediaType in ProviderMediaType.values)
                            ChoiceChip(
                              label: Text(mediaType.label),
                              selected:
                                  controller.selectedMediaType == mediaType,
                              selectedColor: accent.withValues(alpha: 0.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                                side: BorderSide(
                                  color:
                                      controller.selectedMediaType == mediaType
                                      ? accent.withValues(alpha: 0.65)
                                      : AppColors.borderSubtle,
                                ),
                              ),
                              onSelected: (_) =>
                                  controller.selectMediaType(mediaType),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProviderContentBody extends StatelessWidget {
  const _ProviderContentBody({
    required this.controller,
    this.onOpenDetail,
    this.onPlay,
  });

  final ProvidersController controller;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading) {
      return const LoadingView(message: 'Loading provider catalog...');
    }

    if (controller.status == ProvidersStatus.error) {
      return ErrorView(
        title: 'Provider unavailable',
        message:
            controller.errorMessage ??
            'We could not load this provider right now.',
        onRetry: controller.retry,
      );
    }

    if (controller.status == ProvidersStatus.empty) {
      return const EmptyState(
        title: 'No titles found',
        message: 'Try switching between TV shows and movies.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in controller.sections) ...[
          SectionHeader(title: section.title),
          const SizedBox(height: AppSpacing.lg),
          MediaRail(
            itemWidth: 172,
            height: 286,
            spacing: AppSpacing.md,
            children: [
              for (final item in section.items.take(20))
                _ProviderMediaCard(
                  item: item,
                  onOpenDetail: onOpenDetail,
                  onPlay: onPlay,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ],
    );
  }
}

class _ProviderMediaCard extends StatelessWidget {
  const _ProviderMediaCard({
    required this.item,
    this.onOpenDetail,
    this.onPlay,
  });

  final SearchMediaItem item;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    return MediaCard(
      mediaId: item.id,
      title: item.title,
      posterPath: item.posterPath,
      backdropPath: item.backdropPath,
      year: item.year > 0 ? item.yearLabel : null,
      rating: item.rating > 0 ? item.ratingLabel : null,
      subtitle: item.provider,
      overview: item.overview,
      onTap: () => onOpenDetail?.call(item.id),
      onPlay: () => onPlay?.call(PlaybackRequestFactory.fromSearchItem(item)),
      onMore: () => onOpenDetail?.call(item.id),
    );
  }
}

ImageProvider? _providerLogo(String? logoPath) {
  final logoUrl = _providerLogoUrl(logoPath);
  return logoUrl == null ? null : NetworkImage(logoUrl);
}

String? _providerLogoUrl(String? logoPath) {
  if (logoPath == null || logoPath.isEmpty) return null;
  if (logoPath.startsWith('http')) return logoPath;
  return '$tmdbImageBaseUrl/w200$logoPath';
}
