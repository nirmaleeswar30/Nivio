import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/core/tmdb_artwork.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/season_info.dart';
import 'package:nivio/providers/media_provider.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/providers/dynamic_colors_provider.dart';
import 'package:nivio/widgets/artwork_icon_button.dart';
import 'package:nivio/widgets/hero_artwork_stretch.dart';
import 'package:nivio/widgets/opening_overlay.dart' show titleLogoProvider;
import 'package:flutter/gestures.dart';
import 'package:nivio/widgets/tab_artwork.dart' show ArtworkImage;

Future<T?> pushMobileStreamPicker<T>(
  NavigatorState navigator,
  MaterialPageRoute<T> route,
  List<DeviceOrientation> restoreOrientations,
) async {
  // Phones only: desktops have no orientation, TVs stay landscape.
  final followsDevice =
      !AppPlatform.isTv && (Platform.isAndroid || Platform.isIOS);
  if (followsDevice) {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }
  try {
    if (!navigator.mounted) return null;
    final result = await navigator.push(route);
    await route.completed;
    return result;
  } finally {
    if (followsDevice) {
      await SystemChrome.setPreferredOrientations(restoreOrientations);
    }
  }
}

class StreamPickerInteraction extends StatelessWidget {
  const StreamPickerInteraction({
    super.key,
    required this.onInteraction,
    required this.child,
  });

  final VoidCallback onInteraction;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => onInteraction(),
    onPointerMove: (_) => onInteraction(),
    onPointerHover: (_) => onInteraction(),
    onPointerSignal: (_) => onInteraction(),
    onPointerPanZoomUpdate: (_) => onInteraction(),
    child: child,
  );
}

Iterable<Widget> mobileStreamResultRows<T>(
  BuildContext context, {
  required Iterable<T> results,
  required bool groupBySource,
  required (String, String) Function(T) source,
  required Widget Function(T) card,
}) sync* {
  if (!groupBySource) {
    yield* results.map(card);
    return;
  }
  final sections = <(String, String), List<T>>{};
  for (final result in results) {
    sections.putIfAbsent(source(result), () => []).add(result);
  }
  for (final entry in sections.entries) {
    yield Padding(
      padding: const EdgeInsets.fromLTRB(3, 8, 3, 8),
      child: Text(entry.key.$2, style: Theme.of(context).textTheme.titleMedium),
    );
    yield* entry.value.map(card);
  }
}

/// The mobile picker layout used by both playback paths.
class MobileStreamPicker extends StatefulWidget {
  const MobileStreamPicker({
    super.key,
    required this.media,
    required this.sources,
    required this.source,
    required this.onSourceChanged,
    required this.onBack,
    required this.onRefresh,
    required this.results,
    required this.loading,
    this.season,
    this.episode,
    this.onSettings,
  });

  final SearchResult media;
  final int? season;
  final int? episode;
  final Map<String, String> sources;
  final String? source;
  final ValueChanged<String?> onSourceChanged;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback? onSettings;
  final Widget results;
  final bool loading;

  @override
  State<MobileStreamPicker> createState() => _MobileStreamPickerState();
}

class _MobileStreamPickerState extends State<MobileStreamPicker> {
  final _scroll = ScrollController();
  Drag? _artworkDrag;

  @override
  void dispose() {
    _artworkDrag?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, bounds) {
        // A resizing Scaffold consumes the keyboard inset before building its body.
        final view = View.of(context);
        final availableHeight =
            bounds.maxHeight + view.viewInsets.bottom / view.devicePixelRatio;
        return _withMetadata(
          context,
          landscape: bounds.maxWidth > availableHeight,
        );
      },
    );
  }

  Widget _withMetadata(BuildContext context, {required bool landscape}) {
    if (context.getInheritedWidgetOfExactType<UncontrolledProviderScope>() ==
        null) {
      return _layout(context, landscape);
    }
    return Consumer(
      builder: (context, ref, _) {
        final media = widget.media;
        final current = ref.watch(selectedMediaProvider);
        final episode = widget.episode;
        final details =
            episode == null ||
                current?.id != media.id ||
                current?.mediaType != media.mediaType
            ? null
            : ref
                  .watch(
                    seasonDataProvider((
                      showId: media.id,
                      seasonNumber: widget.season ?? 1,
                    )),
                  )
                  .valueOrNull
                  ?.episodes
                  .where((item) => item.episodeNumber == episode)
                  .firstOrNull;
        final logo = ref.watch(titleLogoProvider(media)).valueOrNull;
        final useDynamicColors = ref.watch(dynamicArtworkColorsProvider);
        final art = _artwork(landscape, details);
        final palette = useDynamicColors && art.$1 != null
            ? ref.watch(dynamicColorsProvider(art.$1)).valueOrNull
            : null;
        return _layout(
          context,
          landscape,
          details: details,
          logo: logo,
          palette: identical(palette, DynamicColors.fallback) ? null : palette,
        );
      },
    );
  }

  (String?, ArtworkKind) _artwork(bool landscape, EpisodeData? details) {
    if (!landscape && details?.stillPath?.isNotEmpty == true) {
      return (details!.stillPath, ArtworkKind.still);
    }
    final media = widget.media;
    return media.backdropPath?.isNotEmpty == true
        ? (media.backdropPath, ArtworkKind.backdrop)
        : (media.posterPath, ArtworkKind.poster);
  }

  Widget _layout(
    BuildContext context,
    bool landscape, {
    EpisodeData? details,
    String? logo,
    DynamicColors? palette,
  }) {
    final theme = Theme.of(context);
    final base = theme.scaffoldBackgroundColor;
    final background = palette == null
        ? base
        : Color.alphaBlend(palette.darkMuted.withValues(alpha: .75), base);
    final colors = palette == null
        ? theme.colorScheme
        : theme.colorScheme.copyWith(
            primary: palette.lightVibrant,
            onPrimary:
                ThemeData.estimateBrightnessForColor(palette.lightVibrant) ==
                    Brightness.light
                ? const Color(0xFF111111)
                : Colors.white,
            surface: background,
            surfaceContainer: Color.alphaBlend(
              palette.darkVibrant.withValues(alpha: .55),
              background,
            ),
          );
    final headerInset = MediaQuery.paddingOf(context).top;
    final artwork = _artwork(landscape, details);
    final openSettings = widget.onSettings;
    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ArtworkIconButton(
          tooltip: 'Back',
          onTap: widget.onBack,
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        if (openSettings != null)
          ArtworkIconButton(
            tooltip: 'Stream settings',
            onTap: openSettings,
            icon: const Icon(
              Icons.settings_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
      ],
    );
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: background,
        colorScheme: colors,
      ),
      child: ColoredBox(
        color: background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (landscape)
              LayoutBuilder(
                builder: (context, bounds) => HeroArtworkStretch(
                  controller: _scroll,
                  height: bounds.maxHeight,
                  movesWithScroll: false,
                  child: _backdrop(artwork, background, landscape: true),
                ),
              ),
            SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final streams = _streams(context);
                  final title = _title(
                    context,
                    details,
                    logo,
                    landscape: landscape,
                  );
                  if (landscape) {
                    return Padding(
                      padding: EdgeInsets.fromLTRB(12, headerInset + 8, 12, 8),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 48),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: _pullArtwork(
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                        ),
                                        child: title,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(22),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: 20,
                                        sigmaY: 20,
                                      ),
                                      child: ColoredBox(
                                        color: colors.surface.withValues(
                                          alpha: .82,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: streams,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          actions,
                        ],
                      ),
                    );
                  }
                  final height = (bounds.maxHeight * .32).clamp(
                    0.0,
                    widget.episode == null ? 200.0 : 240.0,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: height,
                        child: _pullArtwork(
                          Stack(
                            fit: StackFit.expand,
                            children: [
                              HeroArtworkStretch(
                                controller: _scroll,
                                height: height,
                                movesWithScroll: false,
                                child: _backdrop(
                                  artwork,
                                  background,
                                  landscape: false,
                                ),
                              ),
                              Positioned(
                                left: 12,
                                right: 12,
                                top: headerInset + 4,
                                child: actions,
                              ),
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: 8,
                                child: title,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(child: streams),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pullArtwork(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (details) {
        if (_scroll.positions.length == 1) {
          _artworkDrag = _scroll.position.drag(
            details,
            () => _artworkDrag = null,
          );
        }
      },
      onVerticalDragUpdate: (details) => _artworkDrag?.update(details),
      onVerticalDragEnd: (details) => _artworkDrag?.end(details),
      onVerticalDragCancel: () => _artworkDrag?.cancel(),
      child: child,
    );
  }

  Widget _streams(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              IconButton(
                tooltip: widget.loading ? 'Finding streams' : 'Refresh streams',
                onPressed: widget.loading ? null : widget.onRefresh,
                icon: widget.loading
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 20),
              ),
              for (final item in <(String?, String)>[
                (null, 'All'),
                ...widget.sources.entries.map(
                  (entry) => (entry.key, entry.value),
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Center(
                    child: ChoiceChip(
                      label: Text(item.$2),
                      selected: item.$1 == widget.source,
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      side: BorderSide.none,
                      backgroundColor: Colors.white.withValues(alpha: .08),
                      selectedColor: colors.primary.withValues(alpha: .18),
                      onSelected: (_) => widget.onSourceChanged(item.$1),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: PrimaryScrollController(
            controller: _scroll,
            child: widget.results,
          ),
        ),
      ],
    );
  }

  Widget _backdrop(
    (String?, ArtworkKind) artwork,
    Color background, {
    required bool landscape,
  }) {
    final (image, kind) = artwork;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image != null && image.isNotEmpty)
          ArtworkImage(
            imageUrl: image,
            kind: kind,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                background.withValues(alpha: landscape ? .35 : .12),
                background.withValues(alpha: landscape ? .48 : .20),
                background.withValues(alpha: landscape ? .80 : 1),
              ],
              stops: const [0, .42, 1],
            ),
          ),
        ),
      ],
    );
  }

  Widget _title(
    BuildContext context,
    EpisodeData? details,
    String? logo, {
    required bool landscape,
  }) {
    final title = widget.media.title ?? widget.media.name ?? 'Choose stream';
    final episode = widget.episode;
    final subtitle = details?.episodeName;
    final text = Theme.of(context).textTheme;
    final fallback = Text(
      title,
      maxLines: landscape ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      textAlign: landscape ? TextAlign.center : TextAlign.start,
      style: text.headlineSmall?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: landscape
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        if (logo?.isNotEmpty == true)
          Semantics(
            label: title,
            image: true,
            child: ArtworkImage(
              imageUrl: logo!,
              kind: ArtworkKind.logo,
              fit: BoxFit.contain,
              alignment: landscape ? Alignment.center : Alignment.bottomLeft,
              width: landscape ? 250 : 220,
              height: landscape ? 76 : 55,
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            ),
          )
        else
          fallback,
        if (episode != null)
          Text(
            [
              widget.season == null
                  ? 'Episode ${episode}'
                  : 'S${widget.season} E${episode}',
              if (subtitle != null && subtitle.isNotEmpty && subtitle != title)
                subtitle,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: landscape ? TextAlign.center : TextAlign.start,
            style: text.labelLarge?.copyWith(color: Colors.white70),
          ),
      ],
    );
  }
}

class MobileStreamCard extends StatelessWidget {
  const MobileStreamCard({
    super.key,
    required this.title,
    required this.details,
    required this.source,
    required this.onTap,
    this.preferred = false,
    this.status,
    this.footer,
  });

  final String title;
  final List<String> details;
  final String source;
  final VoidCallback? onTap;
  final bool preferred;
  final String? status;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 9,
                            runSpacing: 1,
                            children: [
                              for (final detail in details)
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.primary.withValues(
                                      alpha: .09,
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    child: Text(
                                      detail,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: colors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (status case final message?)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              message,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.error,
                              ),
                            ),
                          ),
                        if (footer case final Widget action) action,
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    flex: 0,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 82),
                      child: Column(
                        children: [
                          Icon(
                            preferred
                                ? Icons.star_rounded
                                : Icons.play_circle_outline,
                            color: preferred
                                ? colors.primary
                                : colors.onSurfaceVariant,
                            size: 23,
                          ),
                          Text(
                            source,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
