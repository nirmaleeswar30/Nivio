import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/screens/stream_selection_screen.dart';
import 'package:nivio/services/extensions/extension_repository.dart';
import 'package:nivio/services/extensions/extension_resolver.dart';
import 'package:nivio/services/extensions/stream_discovery.dart';
import 'package:nivio/services/extensions/stream_selection.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:nivio/widgets/stream_surfaces.dart';
import 'package:nivio/widgets/tab_artwork.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class StreamPickerOutcome {
  const StreamPickerOutcome({
    this.choice,
    this.result,
    this.refresh = false,
    this.automatic = false,
  });
  final StreamChoice? choice;
  final StreamResult? result;
  final bool refresh;
  final bool automatic;
}

class StreamPickerSheet extends StatefulWidget {
  const StreamPickerSheet({
    super.key,
    required this.discovery,
    required this.initialFilter,
    required this.onFilter,
    this.fallbackMessage,
    this.sidePanel = false,
  });

  final StreamDiscovery discovery;
  final StreamFilter initialFilter;
  final ValueChanged<StreamFilter> onFilter;
  final String? fallbackMessage;
  final bool sidePanel;

  static Future<StreamPickerOutcome?> show(
    BuildContext context,
    StreamDiscovery discovery,
    StreamFilter initialFilter,
    ValueChanged<StreamFilter> onFilter, {
    String? fallbackMessage,
  }) {
    final wide =
        AppPlatform.useDesktopLayout && MediaQuery.sizeOf(context).width >= 760;
    final sheet = StreamPickerSheet(
      discovery: discovery,
      initialFilter: initialFilter,
      onFilter: onFilter,
      fallbackMessage: fallbackMessage,
      sidePanel: wide,
    );
    if (wide) {
      return showGeneralDialog<StreamPickerOutcome>(
        context: context,
        barrierColor: const Color(0x70000000),
        transitionDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        transitionBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(.25, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        pageBuilder: (_, _, _) => Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            minimum: const EdgeInsets.all(12),
            child: SizedBox(width: 480, height: double.infinity, child: sheet),
          ),
        ),
      );
    }
    return showModalBottomSheet<StreamPickerOutcome>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      enableDrag: false,
      isDismissible: false,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x80000000),
      constraints: const BoxConstraints(maxWidth: 680),
      builder: (_) => FractionallySizedBox(heightFactor: .88, child: sheet),
    );
  }

  @override
  State<StreamPickerSheet> createState() => _StreamPickerSheetState();
}

class _StreamPickerSheetState extends State<StreamPickerSheet> {
  late StreamFilter _filter =
      widget.initialFilter == StreamFilter.torrents &&
          !discovery.torrentsEnabled
      ? StreamFilter.direct
      : widget.initialFilter;
  String? _audio;
  StreamChoice? _opening;
  String? _status;

  StreamDiscovery get discovery => widget.discovery;

  void _setFilter(StreamFilter filter) {
    setState(() => _filter = filter);
    widget.onFilter(filter);
  }

  bool _matchesAudio(StreamChoice choice) =>
      _audio == null ||
      choice.audioType == 'Both' ||
      choice.audioType == _audio;

  Future<void> _open(StreamChoice choice) async {
    setState(() {
      _opening = choice;
      _status = 'Opening ${choice.provider}…';
    });
    try {
      final result = await discovery.open(choice, (status) {
        if (mounted) setState(() => _status = status);
      });
      if (!mounted) return;
      if (result != null) {
        Navigator.of(
          context,
        ).pop(StreamPickerOutcome(choice: choice, result: result));
        return;
      }
    } catch (_) {
      // Keep the other search results visible for manual recovery.
    }
    if (!mounted) return;
    discovery.markFailed(choice);
    setState(() {
      _opening = null;
      _status = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = NivioTheme.themeColorsOf(context);
    final radius = widget.sidePanel
        ? const BorderRadius.all(Radius.circular(22))
        : const BorderRadius.vertical(top: Radius.circular(24));
    final content = Material(
      color: palette.surface.withValues(alpha: widget.sidePanel ? .94 : 1),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: palette.border),
      ),
      child: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: discovery,
          builder: (context, _) {
            final available = discovery.choices.where(_matchesAudio).toList();
            final direct = available.where((choice) => choice.isDirect).length;
            final torrents = available
                .where((choice) => choice.isTorrent)
                .length;
            final ordered = discovery.orderForPicker(
              available
                  .where(
                    (choice) => switch (_filter) {
                      StreamFilter.all => true,
                      StreamFilter.direct => choice.isDirect,
                      StreamFilter.torrents => choice.isTorrent,
                    },
                  )
                  .toList(),
            );
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header(palette)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _tab(StreamFilter.all, available.length),
                            _tab(StreamFilter.direct, direct),
                            _tab(StreamFilter.torrents, torrents),
                          ],
                        ),
                        if (discovery.isAnime)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 5,
                              children: [
                                for (final audio in <String?>[
                                  null,
                                  'Sub',
                                  'Dub',
                                ])
                                  StreamSegment(
                                    label: audio ?? 'All audio',
                                    selected: _audio == audio,
                                    onTap: _opening == null
                                        ? () => setState(() => _audio = audio)
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                        if (widget.fallbackMessage case final String message)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              message,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        if (_status != null || discovery.searching)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (_status != null ||
                            discovery.searching ||
                            discovery.failures.isNotEmpty)
                          Row(
                            children: [
                              Expanded(
                                child: Semantics(
                                  liveRegion: true,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      _status ??
                                          (discovery.searching
                                              ? 'Searching providers…'
                                              : '${discovery.failures.length} provider(s) couldn’t be reached.'),
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (_opening == null && discovery.searching)
                                TextButton(
                                  onPressed: discovery.stop,
                                  child: const Text('Stop search'),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                if (ordered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _empty(direct, torrents),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    sliver: SliverList.separated(
                      itemCount: ordered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 7),
                      itemBuilder: (_, index) =>
                          _choice(ordered[index], discovery.previous),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
    return PopScope(
      canPop: _opening == null,
      child: ClipRRect(
        borderRadius: radius,
        child: widget.sidePanel
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: content,
              )
            : content,
      ),
    );
  }

  Widget _header(NivioThemeColors palette) {
    final media = discovery.media;
    final episode = switch (media.mediaType) {
      'movie' => 'Movie',
      'anime' => 'Episode ${discovery.episode}',
      _ => 'S${discovery.season} · E${discovery.episode}',
    };
    final preferred =
        discovery.selection.preferredType == StreamFilter.torrents &&
            !discovery.torrentsEnabled
        ? StreamFilter.direct
        : discovery.selection.preferredType;
    final poster = media.posterPath;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.primary.withValues(alpha: .13),
            palette.surfaceContainer.withValues(alpha: .20),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: palette.border.withValues(alpha: palette.border.a * .70),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 6),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (poster != null && poster.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: ArtworkImage(
                      imageUrl: poster,
                      width: 44,
                      height: 62,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose stream',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${media.title ?? media.name ?? 'Video'} · $episode',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(PhosphorIconsRegular.x, size: 21),
                  onPressed: _opening == null
                      ? () => Navigator.of(context).pop()
                      : null,
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Preferred type · ${preferred.label}',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _opening == null
                      ? () async {
                          await showStreamPickerSettings(context);
                          if (!mounted) return;
                          Navigator.of(
                            context,
                          ).pop(const StreamPickerOutcome(refresh: true));
                        }
                      : null,
                  icon: const Icon(PhosphorIconsRegular.faders, size: 16),
                  label: const Text('Settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(StreamFilter filter, int count) => StreamSegment(
    label: '${filter.label} $count',
    selected: _filter == filter,
    autofocus: _filter == filter,
    onTap:
        _opening != null ||
            filter == StreamFilter.torrents && !discovery.torrentsEnabled
        ? null
        : () => _setFilter(filter),
  );

  Widget _empty(int direct, int torrents) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamGlyph(PhosphorIconsRegular.stack, size: 46),
          const SizedBox(height: 12),
          Text(
            discovery.searching
                ? 'Looking for streams…'
                : switch (_filter) {
                    StreamFilter.all => 'No streams found',
                    StreamFilter.direct => 'No direct streams found',
                    StreamFilter.torrents => 'No torrents found',
                  },
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!discovery.searching)
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (_audio != null)
                  TextButton(
                    onPressed: () => setState(() => _audio = null),
                    child: const Text('Show all audio'),
                  ),
                if (_filter != StreamFilter.all)
                  TextButton(
                    onPressed: () => _setFilter(StreamFilter.all),
                    child: const Text('Show all'),
                  ),
                if (direct > 0 && _filter != StreamFilter.direct)
                  TextButton(
                    onPressed: () => _setFilter(StreamFilter.direct),
                    child: const Text('Show direct'),
                  ),
                if (torrents > 0 && _filter != StreamFilter.torrents)
                  TextButton(
                    onPressed: () => _setFilter(StreamFilter.torrents),
                    child: const Text('Show torrents'),
                  ),
                TextButton(
                  onPressed: discovery.search,
                  child: const Text('Search again'),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _choice(StreamChoice choice, StreamChoice? previous) {
    final failed = discovery.unavailable.contains(choice.id);
    final torrent = choice.torrent;
    final subtitles =
        choice.direct?.subtitles.map((track) => track.lang).toSet() ?? {};
    final bytes = choice.byteSize;
    final palette = NivioTheme.themeColorsOf(context);
    final isPrevious = choice.bingeGroup == previous?.bingeGroup;
    final transport = choice.isTorrent
        ? 'Torrent'
        : choice.isWebPlayer
        ? 'Web player'
        : 'Direct';
    final details = [
      if (choice.audioType != null)
        choice.audioType!
      else if (choice.audio == null && discovery.selection.matchAudio)
        'Audio unconfirmed',
      if (choice.audio != null && choice.audio != choice.audioType)
        choice.audio!,
      if (bytes != null)
        bytes < 1073741824
            ? '${(bytes / 1048576).toStringAsFixed(1)} MiB'
            : '${(bytes / 1073741824).toStringAsFixed(1)} GiB',
      if (discovery.selection.maxFileGb > 0 && bytes == null) 'Size unknown',
      if (discovery.selection.maxFileGb > 0 && torrent?.isBatch == true)
        'Episode size unknown',
      if (torrent != null && torrent.seeders > 0) '${torrent.seeders} seeders',
      if (torrent?.isBatch == true) 'Pack · episode ${discovery.episode}',
      if (subtitles.isNotEmpty) 'Subtitles: ${subtitles.take(3).join(', ')}',
    ];
    const radius = BorderRadius.all(Radius.circular(12));
    return Material(
      color: isPrevious
          ? Color.alphaBlend(
              palette.primary.withValues(alpha: .09),
              palette.surface,
            )
          : Color.alphaBlend(
              palette.textPrimary.withValues(alpha: .04),
              palette.surface,
            ),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: isPrevious
              ? palette.primary.withValues(alpha: .45)
              : palette.border.withValues(alpha: palette.border.a * .70),
        ),
      ),
      child: FocusableInkWell(
        borderRadius: radius,
        onTap: _opening != null || failed ? null : () => _open(choice),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StreamGlyph(
                choice.isTorrent
                    ? PhosphorIconsRegular.downloadSimple
                    : choice.isWebPlayer
                    ? PhosphorIconsRegular.globe
                    : PhosphorIconsRegular.lightning,
                active: isPrevious,
                size: 32,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      choice.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${choice.provider} · ${choice.origin}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        _metadata(transport, palette),
                        _metadata(choice.quality, palette),
                        if (isPrevious)
                          _metadata('Previous source', palette, active: true),
                      ],
                    ),
                    if (details.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          details.join(' · '),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 11,
                            height: 1.25,
                          ),
                        ),
                      ),
                    if (failed)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          'Couldn’t open this stream. Choose another result.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: choice.isTorrent ? 'Buffer & play' : 'Play',
                child: Padding(
                  padding: const EdgeInsets.only(top: 5, right: 3),
                  child: Icon(
                    PhosphorIconsFill.play,
                    size: 16,
                    color: failed
                        ? palette.textSecondary.withValues(alpha: .5)
                        : palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metadata(
    String label,
    NivioThemeColors palette, {
    bool active = false,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: active
          ? palette.primary.withValues(alpha: .14)
          : palette.textPrimary.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        label,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
