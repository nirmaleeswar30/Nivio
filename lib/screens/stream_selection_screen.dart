import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/services/extensions/extension_repository.dart';
import 'package:nivio/services/extensions/extension_resolver.dart';
import 'package:nivio/services/extensions/stream_selection.dart';
import 'package:nivio/services/extensions/stream_selection_settings.dart';

import 'extensions_screen.dart';

Future<void> showStreamPickerSettings(BuildContext context) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const StreamPickerSettingsScreen()),
    );

class StreamPickerSettingsScreen extends StatelessWidget {
  const StreamPickerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stream selection')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: const [
              StreamSourceSettings(),
              Divider(),
              StreamPlaybackSettings(),
            ],
          ),
        ),
      ),
    ),
  );
}

class StreamSourceSettings extends ConsumerStatefulWidget {
  const StreamSourceSettings({super.key});

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
    final settings = ref.watch(streamSelectionSettingsProvider).valueOrNull;
    return Column(
      children: [
        FutureBuilder<List<ExtensionRepo>>(
          future: _repositories,
          builder: (context, snapshot) {
            final count = snapshot.data
                ?.expand((repo) => repo.providers)
                .where((provider) => provider.enabled)
                .length;
            return ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('Extensions'),
              subtitle: Text(
                count == null || count == 0
                    ? 'Add a Nuvio or Cloudstream repository'
                    : '$count enabled · Manage repositories',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openExtensions,
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.low_priority),
          title: const Text('Source priority'),
          subtitle: const Text(
            'Reorder built-in sources and enabled extensions together.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const _SourcePriorityScreen()),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.download_outlined),
          title: const Text('Enable torrents'),
          subtitle: const Text('Applies to built-in and extension streams.'),
          value: torrentsEnabled,
          onChanged: ref.read(enableTorrentsProvider.notifier).setEnabled,
        ),
        if (settings != null)
          ListTile(
            title: const Text('Preferred stream type'),
            subtitle: Text(
              settings.preferredType == StreamFilter.torrents &&
                      !torrentsEnabled
                  ? 'Using Direct while torrents are disabled.'
                  : 'Opens that picker tab and favors that type in autoplay.',
            ),
            trailing: DropdownButton<StreamFilter>(
              value: settings.preferredType,
              items: [
                for (final type in StreamFilter.values)
                  DropdownMenuItem(
                    value: type,
                    enabled: type != StreamFilter.torrents || torrentsEnabled,
                    child: Text(type.label),
                  ),
              ],
              onChanged: (type) {
                if (type != null)
                  ref
                      .read(streamSelectionSettingsProvider.notifier)
                      .change(
                        (current) => current.copyWith(preferredType: type),
                      );
              },
            ),
          ),
      ],
    );
  }
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
      appBar: AppBar(title: const Text('Source priority')),
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
            for (final source in {
              ...streaming.torrentStreamService.animeSources.map((s) => s.name),
              ...streaming.torrentStreamService.mediaSources.map((s) => s.name),
            })
              'torrent:$source': (source, 'Built-in torrent source'),
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
                    child: Text(
                      'Higher sources appear first in the picker and break ties in Match Preferences.',
                    ),
                  ),
                  buildDefaultDragHandles: false,
                  itemCount: order.length,
                  onReorder: (from, to) => move(from, from < to ? to - 1 : to),
                  itemBuilder: (_, index) {
                    final id = order[index];
                    final (title, origin) = available[id]!;
                    return ListTile(
                      key: ValueKey(id),
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      ),
                      title: Text(title),
                      subtitle: Text(origin),
                      trailing: _MoveButtons(
                        up: index > 0 ? () => move(index, index - 1) : null,
                        down: index + 1 < order.length
                            ? () => move(index, index + 1)
                            : null,
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
          ListTile(
            title: const Text('Playback mode'),
            subtitle: Text(switch (current.mode) {
              StreamSelectionMode.manual =>
                'Open the stream picker when you press Play.',
              StreamSelectionMode.first =>
                'Play the first reachable stream that fits your preferences.',
              StreamSelectionMode.match =>
                'Pick the best match within the selection timeout.',
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final mode in StreamSelectionMode.values)
                  ChoiceChip(
                    label: Text(mode.label),
                    selected: mode == current.mode,
                    onSelected: (_) =>
                        change((value) => value.copyWith(mode: mode)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            title: const Text('Quality preset'),
            subtitle: Text(
              current.mode == StreamSelectionMode.match
                  ? current.preset.description
                  : '${current.preset.description} Used by Match Preferences.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final preset in StreamPreset.values)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: preset == current.preset,
                    onSelected: (selected) {
                      if (selected)
                        change((value) => value.copyWith(preset: preset));
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.bolt, size: 17),
                  label: const Text('Fastest Load'),
                  onPressed: () => change(
                    (value) => value.copyWith(
                      mode: StreamSelectionMode.first,
                      matchAudio: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ExpansionTile(
            title: const Text('Customise'),
            children: [
              ListTile(
                title: const Text('Resolution priority'),
                subtitle: Text(
                  current.resolutions.map((height) => '${height}p').join(' → '),
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
                          selected: current.exclusions.contains(exclusion),
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
              const ListTile(dense: true, title: Text('Prefer these formats')),
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
            onChanged: (enabled) =>
                change((value) => value.copyWith(reuseBingeGroup: enabled)),
          ),
          _NumberSlider(
            label: 'Stream selection timeout',
            valueText: '${current.timeoutSeconds} seconds',
            value: current.timeoutSeconds,
            min: 1,
            max: 30,
            description:
                'How long autoplay waits for search results before choosing or opening the picker.',
            onChanged: (seconds) =>
                change((value) => value.copyWith(timeoutSeconds: seconds)),
          ),
          ExpansionTile(
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
                  child: const Icon(Icons.drag_handle),
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
    title: const Text('Custom Regex Override'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: TextFormField(
          controller: _controller,
          maxLength: 512,
          decoration: const InputDecoration(
            labelText: 'Pattern',
            hintText: r'1080p.*WEB[ .-]?DL',
            helperText: 'Leave empty to use your quality preset.',
          ),
          validator: (value) => validateStreamRegex(value?.trim() ?? ''),
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
