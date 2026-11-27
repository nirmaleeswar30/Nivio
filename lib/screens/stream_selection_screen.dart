import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/services/playback/stream_selection.dart';
import 'package:nivio/services/playback/stream_selection_settings.dart';
import 'package:nivio/services/scrapers/net_mirror_source.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:nivio/widgets/stream_surfaces.dart';
import 'package:nivio/widgets/settings_page_header.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

Future<void> showStreamPickerSettings(
  BuildContext context, {
  bool asSheet = false,
}) {
  if (asSheet) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      clipBehavior: Clip.antiAlias,
      builder: (_) => const FractionallySizedBox(
        heightFactor: .92,
        child: StreamPickerSettingsScreen(),
      ),
    );
  }
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => const StreamPickerSettingsScreen()),
  );
}

Future<StreamSelectionSettings?> editPickerPlaybackSettings(
  BuildContext context, {
  required bool asSheet,
}) async {
  final scope = ProviderScope.containerOf(context, listen: false);
  final before = await scope.read(streamSelectionSettingsProvider.future);
  if (!context.mounted) return null;
  await showStreamPickerSettings(context, asSheet: asSheet);
  if (!context.mounted) return null;
  final after = scope.read(streamSelectionSettingsProvider).value;
  return before == after ? null : after;
}

class StreamPickerSettingsScreen extends StatelessWidget {
  const StreamPickerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: SettingsPageHeader(
      'Stream Selection',
      titleTextStyle: Theme.of(
        context,
      ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
    ),
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: const [StreamPlaybackSettings()],
          ),
        ),
      ),
    ),
  );
}

class StreamSourceSettings extends StatelessWidget {
  const StreamSourceSettings({super.key, this.inPanel = true});

  final bool inPanel;

  @override
  Widget build(BuildContext context) {
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!inPanel)
          const _SectionHeading('SOURCES', PhosphorIconsRegular.stack),
        ListTile(
          leading: const StreamGlyph(PhosphorIconsRegular.arrowsDownUp),
          visualDensity: VisualDensity.compact,
          title: const Text('Source priority'),
          subtitle: const Text('Reorder movie and TV sources.'),
          trailing: const Icon(PhosphorIconsRegular.caretRight, size: 16),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const _SourcePriorityScreen()),
          ),
        ),
        ListTile(
          leading: const StreamGlyph(PhosphorIconsRegular.arrowsDownUp),
          visualDensity: VisualDensity.compact,
          title: const Text('Anime source priority'),
          subtitle: const Text('Reorder anime sources.'),
          trailing: const Icon(PhosphorIconsRegular.caretRight, size: 16),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => const _SourcePriorityScreen(isAnime: true),
            ),
          ),
        ),
        const TorrentSourceSettingsLink(),
      ],
    );
    return inPanel ? StreamPanel(child: rows) : rows;
  }
}

class TorrentSourceSettingsLink extends StatelessWidget {
  const TorrentSourceSettingsLink({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const StreamGlyph(PhosphorIconsRegular.downloadSimple),
    visualDensity: VisualDensity.compact,
    title: const Text('Torrent sources'),
    subtitle: const Text('Torrent playback, indexers, and file options'),
    trailing: const Icon(PhosphorIconsRegular.caretRight, size: 16),
    onTap: () => Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const _TorrentSourceSettingsScreen()),
    ),
  );
}

class _TorrentSourceSettingsScreen extends ConsumerWidget {
  const _TorrentSourceSettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(enableTorrentsProvider);
    final autoplay = ref.watch(torrentAutoplayProvider);
    return Scaffold(
      appBar: const SettingsPageHeader('Torrent sources'),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                StreamPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        title: const Text('Torrent playback'),
                        subtitle: Text(
                          !enabled
                              ? 'Play opens the direct stream picker.'
                              : autoplay
                              ? 'Play starts the best torrent.'
                              : 'Play opens the torrent picker.',
                        ),
                        value: enabled,
                        onChanged: ref
                            .read(enableTorrentsProvider.notifier)
                            .setEnabled,
                      ),
                      SwitchListTile(
                        title: const Text('Autoplay torrents'),
                        subtitle: const Text(
                          'Skip the picker and play the best-ranked torrent '
                          'from the loading screen.',
                        ),
                        value: autoplay,
                        onChanged: enabled
                            ? ref
                                  .read(torrentAutoplayProvider.notifier)
                                  .setEnabled
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                StreamPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SectionHeading(
                        'INDEXERS',
                        PhosphorIconsRegular.magnifyingGlass,
                      ),
                      SwitchListTile(
                        title: const Text('Nyaa (Anime)'),
                        subtitle: const Text('Search anime torrents.'),
                        value: ref.watch(torrentNyaaEnabledProvider),
                        onChanged: enabled
                            ? ref
                                  .read(torrentNyaaEnabledProvider.notifier)
                                  .setEnabled
                            : null,
                      ),
                      SwitchListTile(
                        title: const Text('Torrentio (Movies & Shows)'),
                        subtitle: const Text(
                          'Search indexed movie and TV releases.',
                        ),
                        value: ref.watch(torrentTorrentioEnabledProvider),
                        onChanged: enabled
                            ? ref
                                  .read(
                                    torrentTorrentioEnabledProvider.notifier,
                                  )
                                  .setEnabled
                            : null,
                      ),
                      SwitchListTile(
                        title: const Text('PirateBay (Movies & Shows)'),
                        subtitle: const Text(
                          'Search by title, including manual searches.',
                        ),
                        value: ref.watch(torrentPirateBayEnabledProvider),
                        onChanged: enabled
                            ? ref
                                  .read(
                                    torrentPirateBayEnabledProvider.notifier,
                                  )
                                  .setEnabled
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                StreamPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SectionHeading(
                        'FILES',
                        PhosphorIconsRegular.folder,
                      ),
                      SwitchListTile(
                        title: const Text('Persist torrent files'),
                        subtitle: const Text(
                          'Keep files on disk after playback stops.',
                        ),
                        value: ref.watch(torrentPersistFilesProvider),
                        onChanged: enabled
                            ? ref
                                  .read(torrentPersistFilesProvider.notifier)
                                  .setEnabled
                            : null,
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

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
    child: Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: NivioTheme.themeColorsOf(context).textSecondary,
        ),
        const SizedBox(width: 7),
        StreamSectionLabel(label),
      ],
    ),
  );
}

class _SourcePriorityScreen extends ConsumerStatefulWidget {
  const _SourcePriorityScreen({this.isAnime = false});

  final bool isAnime;

  @override
  ConsumerState<_SourcePriorityScreen> createState() =>
      _SourcePriorityScreenState();
}

class _SourcePriorityScreenState extends ConsumerState<_SourcePriorityScreen> {
  // Desktop switches between the two lists in place.
  late var _isAnime = widget.isAnime;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(streamSelectionSettingsProvider).value;
    final streaming = ref.watch(streamingServiceProvider);
    final desktop =
        AppPlatform.useDesktopLayout && MediaQuery.sizeOf(context).width >= 900;
    final isAnime = _isAnime;
    return Scaffold(
      appBar: SettingsPageHeader(
        desktop
            ? 'Source priority'
            : isAnime
            ? 'Anime source priority'
            : 'Source priority',
        titleTextStyle: AppPlatform.useDesktopLayout
            ? null
            : Theme.of(context).textTheme.titleLarge,
      ),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final available = {
                  for (final name in streaming.streamSelectionBuiltIns(
                    isAnime: isAnime,
                  ))
                    streamSelectionSourceId('builtin:$name'): name,
                };
                final order = {
                  ...settings
                      .sourceOrderFor(isAnime: isAnime)
                      .where(available.containsKey),
                  ...available.keys,
                }.toList();
                void save(List<String> next) {
                  ref.read(streamSelectionSettingsProvider.notifier).change((
                    current,
                  ) {
                    final saved = [
                      ...next,
                      ...current
                          .sourceOrderFor(isAnime: isAnime)
                          .where((id) => !available.containsKey(id)),
                    ];
                    return isAnime
                        ? current.copyWith(animeSourceOrder: saved)
                        : current.copyWith(sourceOrder: saved);
                  });
                }

                void move(int from, int to) {
                  final next = [...order];
                  next.insert(to, next.removeAt(from));
                  save(next);
                }

                if (desktop) {
                  return _DesktopSourcePriority(
                    isAnime: isAnime,
                    order: order,
                    names: available,
                    onAnimeChanged: (value) => setState(() => _isAnime = value),
                    onMove: move,
                    onReset: () => save([...available.keys]),
                  );
                }

                return SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                        header: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionHeading(
                                'PLAYBACK ORDER',
                                PhosphorIconsRegular.arrowsDownUp,
                              ),
                              Text(
                                'Source priority breaks ties in the direct picker and Autoplay.',
                              ),
                            ],
                          ),
                        ),
                        buildDefaultDragHandles: false,
                        itemCount: order.length,
                        onReorder: (from, to) =>
                            move(from, from < to ? to - 1 : to),
                        itemBuilder: (_, index) {
                          final id = order[index];
                          final title = available[id]!;
                          return Padding(
                            key: ValueKey(id),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: StreamPanel(
                              child: ListTile(
                                leading: ReorderableDragStartListener(
                                  index: index,
                                  child: const StreamGlyph(
                                    PhosphorIconsRegular.dotsSixVertical,
                                  ),
                                ),
                                title: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                trailing: _MoveButtons(
                                  up: index > 0
                                      ? () => move(index, index - 1)
                                      : null,
                                  down: index + 1 < order.length
                                      ? () => move(index, index + 1)
                                      : null,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Desktop: the explanation and list switch on the left, the ranked list on
/// the right.
class _DesktopSourcePriority extends StatelessWidget {
  const _DesktopSourcePriority({
    required this.isAnime,
    required this.order,
    required this.names,
    required this.onAnimeChanged,
    required this.onMove,
    required this.onReset,
  });

  final bool isAnime;
  final List<String> order;
  final Map<String, String> names;
  final ValueChanged<bool> onAnimeChanged;
  final void Function(int from, int to) onMove;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final palette = NivioTheme.themeColorsOf(context);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Movies & TV'),
                            icon: Icon(PhosphorIconsRegular.filmStrip),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Anime'),
                            icon: Icon(PhosphorIconsRegular.sparkle),
                          ),
                        ],
                        selected: {isAnime},
                        onSelectionChanged: (value) =>
                            onAnimeChanged(value.first),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Play order',
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Autoplay tries sources from the top. In the direct '
                        'picker, streams that match equally well are listed '
                        'in this order.',
                        style: TextStyle(
                          color: palette.textSecondary,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Drag a row by its handle, or use the arrows. Changes '
                        'save right away.',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: onReset,
                        icon: const Icon(
                          PhosphorIconsRegular.arrowCounterClockwise,
                          size: 16,
                        ),
                        label: const Text('Reset to default order'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 40),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 32),
                    buildDefaultDragHandles: false,
                    itemCount: order.length,
                    onReorder: (from, to) =>
                        onMove(from, from < to ? to - 1 : to),
                    proxyDecorator: (child, _, animation) => AnimatedBuilder(
                      animation: animation,
                      builder: (context, child) => Material(
                        color: Colors.transparent,
                        elevation: 12 * animation.value,
                        shadowColor: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        child: child,
                      ),
                      child: child,
                    ),
                    itemBuilder: (_, index) => _PriorityRow(
                      key: ValueKey(order[index]),
                      index: index,
                      name: names[order[index]]!,
                      kind: _kind(names[order[index]]!),
                      onTop: index > 0 ? () => onMove(index, 0) : null,
                      onUp: index > 0 ? () => onMove(index, index - 1) : null,
                      onDown: index + 1 < order.length
                          ? () => onMove(index, index + 1)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _kind(String name) {
    if (isAnime) return 'Anime';
    if (NetMirrorSource.names.contains(name)) {
      return name.endsWith('M') ? 'Catalog · mobile' : 'Catalog';
    }
    return 'Direct';
  }
}

class _PriorityRow extends StatefulWidget {
  const _PriorityRow({
    super.key,
    required this.index,
    required this.name,
    required this.kind,
    this.onTop,
    this.onUp,
    this.onDown,
  });

  final int index;
  final String name;
  final String kind;
  final VoidCallback? onTop;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  State<_PriorityRow> createState() => _PriorityRowState();
}

class _PriorityRowState extends State<_PriorityRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = NivioTheme.themeColorsOf(context);
    final podium = widget.index < 3;
    final iconColor = palette.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            color: _hovered
                ? palette.textPrimary.withValues(alpha: .06)
                : palette.textPrimary.withValues(alpha: .025),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: podium
                  ? palette.primary.withValues(alpha: _hovered ? .5 : .28)
                  : palette.textPrimary.withValues(alpha: _hovered ? .12 : .06),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: podium
                      ? palette.primary
                      : palette.textPrimary.withValues(alpha: .08),
                ),
                child: Text(
                  '${widget.index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: podium
                        ? Theme.of(context).colorScheme.onPrimary
                        : palette.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.textPrimary.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.kind,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                opacity: _hovered ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: IgnorePointer(
                  ignoring: !_hovered,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move to top',
                        onPressed: widget.onTop,
                        icon: Icon(
                          PhosphorIconsRegular.arrowLineUp,
                          size: 17,
                          color: iconColor,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Move up',
                        onPressed: widget.onUp,
                        icon: Icon(
                          PhosphorIconsRegular.caretUp,
                          size: 17,
                          color: iconColor,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        onPressed: widget.onDown,
                        icon: Icon(
                          PhosphorIconsRegular.caretDown,
                          size: 17,
                          color: iconColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ReorderableDragStartListener(
                index: widget.index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      PhosphorIconsRegular.dotsSixVertical,
                      size: 20,
                      color: iconColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StreamPlaybackSettings extends ConsumerWidget {
  const StreamPlaybackSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(streamSelectionSettingsProvider);
    final change = ref.read(streamSelectionSettingsProvider.notifier).change;
    return settings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ListTile(
        title: const Text('Couldn’t load playback preferences'),
        trailing: TextButton(
          onPressed: () => ref.invalidate(streamSelectionSettingsProvider),
          child: const Text('Retry'),
        ),
      ),
      data: (current) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StreamPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeading(
                  'PLAYBACK MODE',
                  PhosphorIconsRegular.playCircle,
                ),
                for (final mode in StreamSelectionMode.values)
                  _PlaybackModeRow(
                    mode: mode,
                    active: mode == current.mode,
                    onTap: () => change((value) => value.copyWith(mode: mode)),
                  ),
                SwitchListTile(
                  title: const Text('Group results by source'),
                  subtitle: const Text('Show provider sections in All.'),
                  value: current.groupBySource,
                  onChanged: (enabled) =>
                      change((value) => value.copyWith(groupBySource: enabled)),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StreamPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeading(
                  'QUALITY PRESET',
                  PhosphorIconsRegular.filmStrip,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final preset in StreamPreset.values)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: preset == StreamPreset.values.last
                                      ? 0
                                      : 6,
                                ),
                                child: _PresetOption(
                                  preset: preset,
                                  active: preset == current.preset,
                                  onTap: () => change(
                                    (value) => value.copyWith(preset: preset),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        current.mode == StreamSelectionMode.match
                            ? current.preset.description
                            : '${current.preset.description} Used by Autoplay.',
                        style: TextStyle(
                          color: NivioTheme.themeColorsOf(
                            context,
                          ).textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ExpansionTile(
                  key: const PageStorageKey('stream-customise'),
                  title: const Text('Customise'),
                  children: [
                    ListTile(
                      title: const Text('Resolution priority'),
                      subtitle: Text(
                        current.resolutions
                            .map((height) => '${height}p')
                            .join(' → '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _editResolutions(
                        context,
                        current.resolutions,
                        (order) => change(
                          (value) => value.copyWith(customResolutions: order),
                        ),
                      ),
                    ),
                    const ListTile(dense: true, title: Text('Block releases')),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (final exclusion in StreamExclusion.values)
                              FilterChip(
                                label: Text(exclusion.label),
                                selected: current.exclusions.contains(
                                  exclusion,
                                ),
                                onSelected: (enabled) => change(
                                  (value) => value.copyWith(
                                    customExclusions: {...value.exclusions}
                                      ..remove(exclusion)
                                      ..addAll([if (enabled) exclusion]),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const ListTile(
                      dense: true,
                      title: Text('Prefer these formats'),
                      subtitle: Text(
                        'Also boosts matching movie and TV torrents.',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (final feature in StreamFeature.values)
                              FilterChip(
                                label: Text(feature.label),
                                selected: current.features.contains(feature),
                                onSelected: (enabled) => change(
                                  (value) => value.copyWith(
                                    customFeatures: {...value.features}
                                      ..remove(feature)
                                      ..addAll([if (enabled) feature]),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _NumberSlider(
                      label: 'Maximum file size',
                      valueText: current.maxFileGb == 0
                          ? 'No limit'
                          : '${current.maxFileGb} GiB',
                      value: current.maxFileGb,
                      min: 0,
                      max: 100,
                      description:
                          'With a limit, unknown sizes are available for manual selection. Torrent packs are checked when the video file is found.',
                      onChanged: (max) =>
                          change((value) => value.copyWith(maxFileGb: max)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StreamPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeading(
                  'AUTOPLAY RULES',
                  PhosphorIconsRegular.faders,
                ),
                SwitchListTile(
                  title: const Text('Match saved audio preference'),
                  subtitle: const Text(
                    'Use reported languages and the preferred anime Sub or Dub setting.',
                  ),
                  value: current.matchAudio,
                  onChanged: (enabled) =>
                      change((value) => value.copyWith(matchAudio: enabled)),
                ),
                SwitchListTile(
                  title: const Text('Reuse binge group'),
                  subtitle: const Text(
                    'Prefer the previous episode’s source and release in Autoplay.',
                  ),
                  value: current.reuseBingeGroup,
                  onChanged: (enabled) => change(
                    (value) => value.copyWith(reuseBingeGroup: enabled),
                  ),
                ),
                _NumberSlider(
                  label: 'Stream selection timeout',
                  valueText: '${current.timeoutSeconds} seconds',
                  value: current.timeoutSeconds,
                  min: 1,
                  max: 30,
                  description:
                      'The longest Autoplay waits for sources. It starts sooner once your preferred resolution and audio come from the highest-priority source still searching.',
                  onChanged: (seconds) => change(
                    (value) => value.copyWith(timeoutSeconds: seconds),
                  ),
                ),
                ExpansionTile(
                  key: const PageStorageKey('stream-advanced'),
                  title: const Text('Advanced'),
                  children: [
                    ListTile(
                      title: const Text('Custom Regex Override'),
                      subtitle: Text(
                        current.regex.isEmpty
                            ? 'In Autoplay, match the source name, release label, quality, or reported audio.'
                            : current.regex,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () async {
                        final regex = await showDialog<String>(
                          context: context,
                          builder: (_) => _RegexDialog(initial: current.regex),
                        );
                        if (regex != null && context.mounted) {
                          await change((value) => value.copyWith(regex: regex));
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackModeRow extends StatelessWidget {
  const _PlaybackModeRow({
    required this.mode,
    required this.active,
    required this.onTap,
  });

  final StreamSelectionMode mode;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = NivioTheme.themeColorsOf(context);
    final (icon, description) = switch (mode) {
      StreamSelectionMode.manual => (
        PhosphorIconsRegular.handPointing,
        'Open the picker when you press Play.',
      ),
      StreamSelectionMode.first => (
        PhosphorIconsRegular.lightning,
        'Play the first reachable stream that fits.',
      ),
      StreamSelectionMode.match => (
        PhosphorIconsRegular.sliders,
        'Find the best match and play it from the loading screen.',
      ),
    };
    const radius = BorderRadius.all(Radius.circular(11));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Semantics(
        selected: active,
        button: true,
        child: Material(
          color: active
              ? palette.primary.withValues(alpha: .085)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: active
                  ? palette.primary.withValues(alpha: .40)
                  : Colors.transparent,
            ),
          ),
          child: FocusableInkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              child: Row(
                children: [
                  StreamGlyph(icon, active: active, size: 35),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mode.label,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          description,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    active
                        ? PhosphorIconsFill.checkCircle
                        : PhosphorIconsRegular.circle,
                    color: active
                        ? palette.primary
                        : palette.textSecondary.withValues(alpha: .50),
                    size: 17,
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

class _PresetOption extends StatelessWidget {
  const _PresetOption({
    required this.preset,
    required this.active,
    required this.onTap,
  });

  final StreamPreset preset;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = NivioTheme.themeColorsOf(context);
    final icon = switch (preset) {
      StreamPreset.dataSaver => PhosphorIconsRegular.leaf,
      StreamPreset.balanced => PhosphorIconsRegular.scales,
      StreamPreset.maxQuality => PhosphorIconsRegular.sparkle,
    };
    const radius = BorderRadius.all(Radius.circular(11));
    return Semantics(
      selected: active,
      button: true,
      child: Material(
        color: active
            ? palette.primary.withValues(alpha: .13)
            : palette.textPrimary.withValues(alpha: .045),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: active
                ? palette.primary.withValues(alpha: .54)
                : palette.border.withValues(alpha: palette.border.a * .60),
          ),
        ),
        child: FocusableInkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: active ? palette.primary : palette.textSecondary,
                  size: 20,
                ),
                const SizedBox(height: 6),
                Text(
                  preset.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

Future<void> _editResolutions(
  BuildContext context,
  List<int> initial,
  ValueChanged<List<int>> onSave,
) async {
  final order = [...initial];
  final compact =
      !AppPlatform.useDesktopLayout || MediaQuery.sizeOf(context).width < 600;
  Widget buildEditor(BuildContext context) => StatefulBuilder(
    builder: (context, setState) {
      void move(int from, int to) =>
          setState(() => order.insert(to, order.removeAt(from)));
      final resolutions = ReorderableListView.builder(
        shrinkWrap: compact,
        padding: compact ? const EdgeInsets.symmetric(horizontal: 8) : null,
        buildDefaultDragHandles: false,
        itemCount: order.length,
        onReorder: (from, to) => move(from, from < to ? to - 1 : to),
        itemBuilder: (_, index) => ListTile(
          key: ValueKey(order[index]),
          leading: ReorderableDragStartListener(
            index: index,
            child: StreamGlyph(
              PhosphorIconsRegular.dotsSixVertical,
              size: compact ? 44 : 36,
            ),
          ),
          title: Text('${order[index]}p'),
          trailing: _MoveButtons(
            up: index > 0 ? () => move(index, index - 1) : null,
            down: index + 1 < order.length
                ? () => move(index, index + 1)
                : null,
          ),
        ),
      );
      final actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, order),
          child: const Text('Save'),
        ),
      ];

      if (!compact) {
        return AlertDialog(
          backgroundColor: NivioTheme.surfaceColorOf(context),
          title: const Text('Resolution priority'),
          content: SizedBox(width: 340, height: 290, child: resolutions),
          actions: actions,
        );
      }
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Resolution priority',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(child: resolutions),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      );
    },
  );
  final selected = compact
      ? await showModalBottomSheet<List<int>>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          enableDrag: false,
          showDragHandle: true,
          backgroundColor: NivioTheme.sheetColorOf(
            context,
            fallback: NivioTheme.surfaceColorOf(context),
          ),
          constraints: const BoxConstraints(maxWidth: 560),
          builder: buildEditor,
        )
      : await showDialog<List<int>>(context: context, builder: buildEditor);
  if (selected != null && context.mounted) onSave(selected);
}

class _MoveButtons extends StatelessWidget {
  const _MoveButtons({this.up, this.down});

  final VoidCallback? up;
  final VoidCallback? down;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        onPressed: up,
        tooltip: 'Move up',
        icon: const Icon(Icons.arrow_upward, size: 19),
      ),
      IconButton(
        onPressed: down,
        tooltip: 'Move down',
        icon: const Icon(Icons.arrow_downward, size: 19),
      ),
    ],
  );
}

class _NumberSlider extends StatefulWidget {
  const _NumberSlider({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.description,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final int value;
  final int min;
  final int max;
  final String description;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberSlider> createState() => _NumberSliderState();
}

class _NumberSliderState extends State<_NumberSlider> {
  int? _drag;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        title: Text(widget.label),
        subtitle: Text(widget.description),
        trailing: Text(widget.valueText),
      ),
      Slider(
        value: (_drag ?? widget.value).toDouble(),
        min: widget.min.toDouble(),
        max: widget.max.toDouble(),
        divisions: widget.max - widget.min,
        label: _drag?.toString() ?? widget.valueText,
        semanticFormatterCallback: (value) =>
            '${widget.label} ${value.round()}',
        onChanged: (value) => setState(() => _drag = value.round()),
        onChangeEnd: (value) {
          widget.onChanged(value.round());
          setState(() => _drag = null);
        },
      ),
    ],
  );
}

class _RegexDialog extends StatefulWidget {
  const _RegexDialog({required this.initial});

  final String initial;

  @override
  State<_RegexDialog> createState() => _RegexDialogState();
}

class _RegexDialogState extends State<_RegexDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: NivioTheme.surfaceColorOf(context),
    title: const Text('Custom Regex Override'),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PopupMenuButton<StreamRegexPreset>(
              tooltip: 'Choose a regex preset',
              color: NivioTheme.surfaceColorOf(context),
              onSelected: (preset) {
                _controller.value = TextEditingValue(
                  text: preset.pattern,
                  selection: TextSelection.collapsed(
                    offset: preset.pattern.length,
                  ),
                );
              },
              itemBuilder: (_) => [
                for (final preset in StreamRegexPreset.values)
                  CheckedPopupMenuItem(
                    value: preset,
                    checked: _controller.text.trim() == preset.pattern,
                    child: Text(preset.label),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: Text('Regex presets')),
                    Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            TextFormField(
              controller: _controller,
              maxLength: 512,
              decoration: const InputDecoration(
                labelText: 'Pattern',
                hintText: r'1080p.*WEB[ .-]?DL',
                helperText: 'Leave empty to use your quality preset.',
              ),
              validator: (value) => validateStreamRegex(value?.trim() ?? ''),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate())
            Navigator.pop(context, _controller.text.trim());
        },
        child: const Text('Save'),
      ),
    ],
  );
}
