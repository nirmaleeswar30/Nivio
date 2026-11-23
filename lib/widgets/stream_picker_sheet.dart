import 'package:flutter/material.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/screens/stream_selection_screen.dart';
import 'package:nivio/services/extensions/extension_repository.dart';
import 'package:nivio/services/extensions/extension_resolver.dart';
import 'package:nivio/services/extensions/stream_discovery.dart';
import 'package:nivio/services/extensions/stream_selection.dart';
import 'package:nivio/widgets/playback_picker.dart';

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
    this.fullScreen = false,
  });

  final StreamDiscovery discovery;
  final StreamFilter initialFilter;
  final ValueChanged<StreamFilter> onFilter;
  final String? fallbackMessage;
  final bool fullScreen;

  static Future<StreamPickerOutcome?> show(
    BuildContext context,
    StreamDiscovery discovery,
    StreamFilter initialFilter,
    ValueChanged<StreamFilter> onFilter, {
    String? fallbackMessage,
  }) => PlaybackPickerFrame.show<StreamPickerOutcome>(
    context,
    (fullScreen) => StreamPickerSheet(
      discovery: discovery,
      initialFilter: initialFilter,
      onFilter: onFilter,
      fallbackMessage: fallbackMessage,
      fullScreen: fullScreen,
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
    if (_opening != null) return;
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

  Future<void> _openSettings() async {
    await showStreamPickerSettings(context);
    if (!mounted) return;
    Navigator.of(context).pop(const StreamPickerOutcome(refresh: true));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _opening == null,
    child: PlaybackPickerFrame(
      media: discovery.media,
      fullScreen: widget.fullScreen,
      label: 'Choose stream',
      onClose: _opening == null ? () => Navigator.of(context).pop() : null,
      child: TextButtonTheme(
        data: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: playbackPickerAccent),
        ),
        child: ListenableBuilder(
          listenable: discovery,
          builder: (context, _) {
            final available = discovery.choices.where(_matchesAudio).toList();
            final direct = available.where((item) => item.isDirect).length;
            final torrents = available.where((item) => item.isTorrent).length;
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
                SliverToBoxAdapter(
                  child: _filters(available.length, direct, torrents),
                ),
                const SliverToBoxAdapter(
                  child: Divider(height: 1, color: Colors.white12),
                ),
                if (ordered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _empty(direct, torrents),
                  )
                else
                  SliverList.builder(
                    itemCount: ordered.length,
                    itemBuilder: (_, index) => _choice(ordered[index]),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _filters(int total, int direct, int torrents) {
    final preferred =
        discovery.selection.preferredType == StreamFilter.torrents &&
            !discovery.torrentsEnabled
        ? StreamFilter.direct
        : discovery.selection.preferredType;
    final episode = switch (discovery.media.mediaType) {
      'movie' => 'Movie',
      'anime' => 'Episode ${discovery.episode}',
      _ => 'S${discovery.season} · E${discovery.episode}',
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.fullScreen ? 16 : 24,
        0,
        widget.fullScreen ? 16 : 24,
        10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$episode  ·  Preferred type: ${preferred.label}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              TextButton.icon(
                onPressed: _opening == null ? _openSettings : null,
                icon: const Icon(Icons.tune, size: 17),
                label: const Text('Settings'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _tab(StreamFilter.all, total),
              _tab(StreamFilter.direct, direct),
              _tab(StreamFilter.torrents, torrents),
            ],
          ),
          if (discovery.isAnime)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final audio in <String?>[null, 'Sub', 'Dub'])
                    PlaybackPickerTab(
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
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          if (_status != null || discovery.searching)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: playbackPickerAccent,
              ),
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
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _status ??
                            (discovery.searching
                                ? 'Searching providers…'
                                : '${discovery.failures.length} provider(s) couldn’t be reached.'),
                        style: const TextStyle(
                          color: Colors.white70,
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
    );
  }

  Widget _tab(StreamFilter type, int count) => PlaybackPickerTab(
    label: '${type.label} $count',
    selected: _filter == type,
    autofocus: _filter == type,
    onTap:
        _opening != null ||
            type == StreamFilter.torrents && !discovery.torrentsEnabled
        ? null
        : () => _setFilter(type),
  );

  Widget _empty(int direct, int torrents) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
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
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
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

  Widget _choice(StreamChoice choice) {
    final failed = discovery.unavailable.contains(choice.id);
    final torrent = choice.torrent;
    final subtitles =
        choice.direct?.subtitles.map((track) => track.lang).toSet() ?? {};
    final bytes = choice.byteSize;
    final isPrevious = choice.bingeGroup == discovery.previous?.bingeGroup;
    final transport = choice.isTorrent
        ? 'Torrent'
        : choice.isWebPlayer
        ? 'Web player'
        : 'Direct';
    return PlaybackPickerRow(
      title: choice.title,
      marker: isPrevious ? 'PREVIOUS SOURCE' : null,
      highlighted: isPrevious,
      onTap: _opening != null || failed ? null : () => _open(choice),
      message: failed
          ? 'Couldn’t open this stream. Choose another result.'
          : null,
      actionLabel: choice.isTorrent ? 'Buffer & play' : 'Play',
      tags: [
        PlaybackPickerTag(
          choice.provider.toUpperCase(),
          color: playbackPickerProviderColor,
        ),
        PlaybackPickerTag(choice.quality, color: playbackPickerQualityColor),
        PlaybackPickerTag(transport, color: playbackPickerAccent),
        PlaybackPickerTag(choice.origin, color: Colors.white70),
        if (choice.audioType case final String audio)
          PlaybackPickerTag(audio, color: Colors.white70)
        else if (choice.audio == null && discovery.selection.matchAudio)
          const PlaybackPickerTag('Audio unconfirmed', color: Colors.white70),
        if (choice.audio != null && choice.audio != choice.audioType)
          PlaybackPickerTag(choice.audio!, color: Colors.white70),
        if (bytes != null)
          PlaybackPickerTag(
            formatPlaybackPickerSize(bytes),
            color: Colors.white70,
          )
        else if (discovery.selection.maxFileGb > 0)
          const PlaybackPickerTag('Size unknown', color: Colors.white70),
        if (torrent != null) ...playbackPickerPeerTags(torrent),
        if (torrent?.isBatch == true)
          PlaybackPickerTag(
            discovery.selection.maxFileGb > 0
                ? 'Episode size unknown'
                : 'Pack · episode ${discovery.episode}',
            color: Colors.white70,
          ),
        if (subtitles.isNotEmpty)
          PlaybackPickerTag(
            'Subtitles: ${subtitles.take(3).join(', ')}',
            color: Colors.white70,
          ),
      ],
    );
  }
}
