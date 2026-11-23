import 'package:flutter/material.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/screens/extensions_screen.dart';
import 'package:nivio/services/extensions/extension_repository.dart';
import 'package:nivio/services/extensions/extension_resolver.dart';
import 'package:nivio/services/extensions/stream_discovery.dart';

class StreamPickerOutcome {
  const StreamPickerOutcome({this.choice, this.result, this.refresh = false});
  final StreamChoice? choice;
  final StreamResult? result;
  final bool refresh;
}

class StreamPickerSheet extends StatefulWidget {
  const StreamPickerSheet({
    super.key,
    required this.discovery,
    required this.initialFilter,
    required this.onFilter,
  });

  final StreamDiscovery discovery;
  final StreamFilter initialFilter;
  final ValueChanged<StreamFilter> onFilter;

  static Future<StreamPickerOutcome?> show(
    BuildContext context,
    StreamDiscovery discovery,
    StreamFilter initialFilter,
    ValueChanged<StreamFilter> onFilter,
  ) => showModalBottomSheet<StreamPickerOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    enableDrag: false,
    isDismissible: false,
    showDragHandle: false,
    constraints: const BoxConstraints(maxWidth: 760),
    builder: (_) => StreamPickerSheet(
      discovery: discovery,
      initialFilter: initialFilter,
      onFilter: onFilter,
    ),
  );

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
  Widget build(BuildContext context) => PopScope(
    canPop: _opening == null,
    child: FractionallySizedBox(
      heightFactor: .88,
      child: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: discovery,
          builder: (context, _) {
            final available = discovery.choices.where(_matchesAudio).toList();
            final direct = available.where((item) => item.isDirect).length;
            final torrents = available.where((item) => item.isTorrent).length;
            final visible = available
                .where(
                  (choice) => switch (_filter) {
                    StreamFilter.all => true,
                    StreamFilter.direct => choice.isDirect,
                    StreamFilter.torrents => choice.isTorrent,
                  },
                )
                .toList();
            final previous = discovery.previous;
            final ordered = [
              ...visible.where((choice) => choice.variant == previous?.variant),
              ...visible.where(
                (choice) =>
                    choice.variant != previous?.variant && !choice.isWebPlayer,
              ),
              ...visible.where(
                (choice) =>
                    choice.variant != previous?.variant && choice.isWebPlayer,
              ),
            ];
            final media = discovery.media;
            final episode = media.mediaType == 'movie'
                ? 'Movie'
                : discovery.isAnime
                ? 'Episode ${discovery.episode}'
                : 'Season ${discovery.season} · Episode ${discovery.episode}';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  title: const Text(
                    'Choose stream',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${media.title ?? media.name ?? 'Video'} · $episode',
                  ),
                  trailing: IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: _opening == null
                        ? () => Navigator.of(context).pop()
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _tab(StreamFilter.all, available.length),
                      _tab(StreamFilter.direct, direct),
                      _tab(StreamFilter.torrents, torrents),
                    ],
                  ),
                ),
                ListTile(
                  dense: true,
                  title: const Text(
                    'Set your default to All, Direct, or Torrents in Settings.',
                  ),
                  trailing: TextButton(
                    onPressed: _opening == null
                        ? () async {
                            final filter = await showStreamPickerSettings(
                              context,
                            );
                            if (!context.mounted) return;
                            if (filter != null) _setFilter(filter);
                            Navigator.of(
                              context,
                            ).pop(const StreamPickerOutcome(refresh: true));
                          }
                        : null,
                    child: const Text('Settings'),
                  ),
                ),
                if (discovery.isAnime)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final audio in <String?>[null, 'Sub', 'Dub'])
                          ChoiceChip(
                            label: Text(audio ?? 'All audio'),
                            selected: _audio == audio,
                            onSelected: _opening == null
                                ? (_) => setState(() => _audio = audio)
                                : null,
                          ),
                      ],
                    ),
                  ),
                if (_status != null || discovery.searching)
                  const LinearProgressIndicator(),
                if (_status != null ||
                    discovery.searching ||
                    discovery.failures.isNotEmpty)
                  ListTile(
                    dense: true,
                    title: Semantics(
                      liveRegion: true,
                      child: Text(
                        _status ??
                            (discovery.searching
                                ? 'Searching providers…'
                                : '${discovery.failures.length} provider(s) couldn’t be reached.'),
                      ),
                    ),
                    trailing: _opening == null && discovery.searching
                        ? TextButton(
                            onPressed: discovery.stop,
                            child: const Text('Stop search'),
                          )
                        : null,
                  ),
                Expanded(
                  child: ordered.isEmpty
                      ? _empty(direct, torrents)
                      : ListView.separated(
                          itemCount: ordered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, index) =>
                              _choice(ordered[index], previous),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _tab(StreamFilter filter, int count) => ChoiceChip(
    label: Text('${filter.label} $count'),
    selected: _filter == filter,
    autofocus: _filter == filter,
    onSelected:
        _opening != null ||
            filter == StreamFilter.torrents && !discovery.torrentsEnabled
        ? null
        : (_) => _setFilter(filter),
  );

  Widget _empty(int direct, int torrents) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            discovery.searching
                ? 'Looking for streams…'
                : switch (_filter) {
                    StreamFilter.all => 'No streams found',
                    StreamFilter.direct => 'No direct streams found',
                    StreamFilter.torrents => 'No torrents found',
                  },
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
    final details = [
      if (choice.isTorrent)
        'Torrent'
      else if (choice.isWebPlayer)
        'Web player'
      else
        'Direct',
      choice.quality,
      if (choice.audioType != null)
        choice.audioType!
      else if (discovery.isAnime && choice.audio == null)
        'Audio unconfirmed',
      if (choice.audio != null && choice.audio != choice.audioType)
        choice.audio!,
      if (bytes != null)
        bytes < 1073741824
            ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
            : '${(bytes / 1073741824).toStringAsFixed(1)} GB',
      if (torrent != null && torrent.seeders > 0) '${torrent.seeders} seeders',
      if (torrent?.isBatch == true) 'Pack · episode ${discovery.episode}',
      if (subtitles.isNotEmpty) 'Subtitles: ${subtitles.take(3).join(', ')}',
    ];
    return ListTile(
      leading: Icon(
        choice.isTorrent
            ? Icons.download_for_offline_outlined
            : choice.isWebPlayer
            ? Icons.language
            : Icons.bolt_outlined,
      ),
      title: Text(choice.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          details.join(' · '),
          '${choice.provider} · ${choice.origin}',
          if (choice.variant == previous?.variant) 'Previous source',
          if (failed) 'Couldn’t open this stream. Choose another result.',
        ].join('\n'),
      ),
      trailing: TextButton(
        onPressed: _opening != null || failed ? null : () => _open(choice),
        child: Text(choice.isTorrent ? 'Buffer & play' : 'Play'),
      ),
      onTap: _opening != null || failed ? null : () => _open(choice),
    );
  }
}
