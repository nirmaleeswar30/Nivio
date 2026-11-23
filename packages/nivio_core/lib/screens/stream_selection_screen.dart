import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/services/extensions/extension_repository.dart';
import 'package:nivio/services/extensions/extension_resolver.dart';
import 'package:nivio/services/extensions/stream_selection.dart';
import 'package:nivio/services/extensions/stream_selection_settings.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:nivio/widgets/stream_surfaces.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'extensions_screen.dart';

Future<void> showStreamPickerSettings(BuildContext context) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const StreamPickerSettingsScreen()),
    );

class StreamPickerSettingsScreen extends StatefulWidget {
  const StreamPickerSettingsScreen({super.key});

  @override
  State<StreamPickerSettingsScreen> createState() =>
      _StreamPickerSettingsScreenState();
}

class _StreamPickerSettingsScreenState
    extends State<StreamPickerSettingsScreen> {
  var _sources = false;

  @override
  Widget build(BuildContext context) {
    final palette = NivioTheme.themeColorsOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stream selection'),
        titleTextStyle: Theme.of(
          context,
        ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
        backgroundColor: palette.background,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(PhosphorIconsRegular.caretLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: NivioTheme.backgroundGradientOf(context),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 820;
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: wide ? 26 : 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!wide)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                StreamSegment(
                                  label: 'Playback',
                                  selected: !_sources,
                                  onTap: () => setState(() => _sources = false),
                                ),
                                StreamSegment(
                                  label: 'Sources',
                                  selected: _sources,
                                  onTap: () => setState(() => _sources = true),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: ListView(
                            key: PageStorageKey(
                              wide ? 'stream-wide' : 'stream-$_sources',
                            ),
                            padding: const EdgeInsets.only(top: 8, bottom: 24),
                            children: [
                              if (wide)
                                const Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: StreamPlaybackSettings(),
                                    ),
                                    SizedBox(width: 18),
                                    Expanded(
                                      flex: 3,
                                      child: StreamSourceSettings(),
                                    ),
                                  ],
                                )
                              else if (_sources)
                                const StreamSourceSettings()
                              else
                                const StreamPlaybackSettings(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StreamSourceSettings extends ConsumerStatefulWidget {
  const StreamSourceSettings({super.key, this.showHeading = true});

  final bool showHeading;

  @override
  ConsumerState<StreamSourceSettings> createState() =>
      _StreamSourceSettingsState();
}

class _StreamSourceSettingsState extends ConsumerState<StreamSourceSettings> {
  late Future<List<ExtensionRepo>> _repositories = _loadRepositories();

  Future<List<ExtensionRepo>> _loadRepositories() =>
      ref.read(extensionRepositoryProvider).list();

  Future<void> _openExtensions() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const ExtensionsScreen()));
    if (mounted) setState(() => _repositories = _loadRepositories());
  }

  @override
  Widget build(BuildContext context) {
    final torrentsEnabled = ref.watch(enableTorrentsProvider);
    return StreamPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeading)
            const _SectionHeading('SOURCES', PhosphorIconsRegular.stack),
          FutureBuilder<List<ExtensionRepo>>(
            future: _repositories,
            builder: (context, snapshot) {
              final count = snapshot.data
                  ?.expand((repo) => repo.providers)
                  .where((provider) => provider.enabled)
                  .length;
              return ListTile(
                leading: const StreamGlyph(PhosphorIconsRegular.puzzlePiece),
                visualDensity: VisualDensity.compact,
                title: const Text('Extensions'),
                subtitle: Text(
                  count == null || count == 0
                      ? 'Add a plugin repository'
                      : '$count enabled',
                ),
                trailing: const Icon(PhosphorIconsRegular.caretRight, size: 16),
                onTap: _openExtensions,
              );
            },
          ),
          ListTile(
            leading: const StreamGlyph(PhosphorIconsRegular.arrowsDownUp),
            visualDensity: VisualDensity.compact,
            title: const Text('Source priority'),
            subtitle: const Text('Reorder built-ins and extensions.'),
            trailing: const Icon(PhosphorIconsRegular.caretRight, size: 16),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const _SourcePriorityScreen()),
            ),
          ),
          SwitchListTile(
            secondary: const StreamGlyph(PhosphorIconsRegular.downloadSimple),
            visualDensity: VisualDensity.compact,
            title: const Text('Enable torrents'),
            subtitle: Text(
              torrentsEnabled
                  ? 'Play opens the torrent picker.'
                  : 'Play opens the direct stream picker.',
            ),
            value: torrentsEnabled,
            onChanged: ref.read(enableTorrentsProvider.notifier).setEnabled,
          ),
        ],
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
  const _SourcePriorityScreen();

  @override
  ConsumerState<_SourcePriorityScreen> createState() =>
      _SourcePriorityScreenState();
}

class _SourcePriorityScreenState extends ConsumerState<_SourcePriorityScreen> {
  late final _sources = ref.read(extensionRepositoryProvider).list();

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(streamSelectionSettingsProvider).valueOrNull;
    final streaming = ref.watch(streamingServiceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Source priority'),
        titleTextStyle: AppPlatform.useDesktopLayout
            ? null
            : Theme.of(context).textTheme.titleLarge,
      ),
      body: FutureBuilder<List<ExtensionRepo>>(
        future: _sources,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const Center(child: Text('Couldn’t load sources.'));
          if (!snapshot.hasData || settings == null)
            return const Center(child: CircularProgressIndicator());
          final available = <String, (String, String)>{
            for (final name in streaming.streamSelectionBuiltIns)
              streamSelectionSourceId('builtin:$name'): (
                name,
                'Built-in source',
              ),
            for (final repo in snapshot.data!)
              for (final provider in repo.providers)
                if (provider.enabled && ExtensionResolver.supports(repo.format))
                  provider.id: (provider.name, repo.name),
          };
          final order = {
            ...settings.sourceOrder.where(available.containsKey),
            ...available.keys,
          }.toList();
          void move(int from, int to) {
            final next = [...order];
            next.insert(to, next.removeAt(from));
            ref
                .read(streamSelectionSettingsProvider.notifier)
                .change(
                  (current) => current.copyWith(
                    sourceOrder: [
                      ...next,
                      ...current.sourceOrder.where(
                        (id) => !available.containsKey(id),
                      ),
                    ],
                  ),
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
                          'Higher sources appear first in the direct picker and break ties in Match Preferences.',
                        ),
                      ],
                    ),
                  ),
                  buildDefaultDragHandles: false,
                  itemCount: order.length,
                  onReorder: (from, to) => move(from, from < to ? to - 1 : to),
                  itemBuilder: (_, index) {
                    final id = order[index];
                    final (title, origin) = available[id]!;
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
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(origin),
                          trailing: _MoveButtons(
                            up: index > 0 ? () => move(index, index - 1) : null,
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
                  'DIRECT PLAYBACK MODE',
                  PhosphorIconsRegular.playCircle,
                ),
                for (final mode in StreamSelectionMode.values)
                  _PlaybackModeRow(
                    mode: mode,
                    active: mode == current.mode,
                    onTap: () => change((value) => value.copyWith(mode: mode)),
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
                            : '${current.preset.description} Used by Match Preferences.',
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
                          'With a limit, streams with unknown file sizes remain available in the picker.',
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
                    'Prefer the previous episode’s source and release in Match Preferences.',
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
                      'How long autoplay waits for search results before choosing or opening the picker.',
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
                            ? 'In Match Preferences, match the source name, release label, quality, or reported audio.'
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
        'Match your quality, audio, and source preferences.',
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
  final selected = await showDialog<List<int>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void move(int from, int to) =>
            setState(() => order.insert(to, order.removeAt(from)));
        return AlertDialog(
          backgroundColor: NivioTheme.surfaceColorOf(context),
          title: const Text('Resolution priority'),
          content: SizedBox(
            width: 340,
            height: 290,
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: order.length,
              onReorder: (from, to) => move(from, from < to ? to - 1 : to),
              itemBuilder: (_, index) => ListTile(
                key: ValueKey(order[index]),
                leading: ReorderableDragStartListener(
                  index: index,
                  child: const StreamGlyph(
                    PhosphorIconsRegular.dotsSixVertical,
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
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, order),
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
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
