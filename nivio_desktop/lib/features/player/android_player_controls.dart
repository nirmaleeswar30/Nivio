part of 'player_screen.dart';

class _AndroidPlayerControls extends StatelessWidget {
  const _AndroidPlayerControls({
    required this.visible,
    required this.playback,
    required this.request,
    required this.providerLabel,
    required this.onClose,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSettings,
    required this.onServer,
    required this.onToggleFullscreen,
    required this.canSwitchServer,
    required this.isFullscreen,
    this.watchPartyMemberCount,
    this.onWatchParty,
    this.serverLabel,
    this.onEpisodes,
    this.onMiniPlayer,
  });

  final bool visible;
  final PlaybackState playback;
  final PlaybackRequest request;
  final String providerLabel;
  final String? serverLabel;
  final VoidCallback onClose;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSettings;
  final VoidCallback onServer;
  final VoidCallback onToggleFullscreen;
  final bool canSwitchServer;
  final bool isFullscreen;
  final int? watchPartyMemberCount;
  final VoidCallback? onWatchParty;
  final VoidCallback? onEpisodes;
  final VoidCallback? onMiniPlayer;

  @override
  Widget build(BuildContext context) {
    PlaybackRuntimeDiagnostics.uiLog(
      'AndroidPlayerControls build visible=$visible '
      'IgnorePointer active=${!visible} serverButtonOnPressed=true '
      'settingsButtonOnPressed=true',
    );
    return IgnorePointer(
      ignoring: !visible,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => PlaybackRuntimeDiagnostics.uiLog(
          'AndroidPlayerControls pointer down position=${event.position} '
          'visible=$visible',
        ),
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  minimum: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 22,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: onClose,
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              request.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (request.mediaType !=
                                        PlaybackMediaType.movie &&
                                    !request.isLive)
                                  _TinyPlayerChip(
                                    label:
                                        'S${request.season ?? 1} E${request.episode ?? 1}',
                                    color: AppColors.primary,
                                  ),
                                _TinyPlayerChip(label: providerLabel),
                                if (serverLabel != null &&
                                    serverLabel!.isNotEmpty &&
                                    serverLabel != providerLabel)
                                  _TinyPlayerChip(label: serverLabel!),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (onWatchParty != null)
                        IconButton(
                          tooltip: 'Watch Party',
                          onPressed: onWatchParty,
                          icon: Badge(
                            isLabelVisible: watchPartyMemberCount != null,
                            label: Text('${watchPartyMemberCount ?? 0}'),
                            child: const Icon(
                              Icons.groups_rounded,
                              color: Colors.white,
                              size: 27,
                            ),
                          ),
                        ),
                      if (onEpisodes != null)
                        IconButton(
                          tooltip: 'Episodes',
                          onPressed: onEpisodes,
                          icon: const Icon(
                            Icons.list,
                            color: Colors.white,
                            size: 27,
                          ),
                        ),
                      if (onMiniPlayer != null)
                        IconButton(
                          tooltip: 'Mini player',
                          onPressed: onMiniPlayer,
                          icon: const Icon(
                            Icons.picture_in_picture_alt,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      if (canSwitchServer)
                        IconButton(
                          tooltip: 'Server',
                          onPressed: () {
                            PlaybackRuntimeDiagnostics.uiLog(
                              'Server IconButton onPressed entered route=androidControls',
                            );
                            onServer();
                          },
                          icon: const Icon(
                            Icons.sync,
                            color: Colors.white,
                            size: 27,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () {
                          PlaybackRuntimeDiagnostics.uiLog(
                            'Settings IconButton onPressed entered route=androidControls',
                          );
                          onSettings();
                        },
                        icon: const Icon(
                          Icons.settings,
                          color: Colors.white,
                          size: 27,
                        ),
                      ),
                      IconButton(
                        tooltip: isFullscreen
                            ? 'Exit fullscreen'
                            : 'Enter fullscreen',
                        onPressed: onToggleFullscreen,
                        icon: Icon(
                          isFullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Center(
                child: IconButton(
                  tooltip: playback.isPlaying ? 'Pause' : 'Play',
                  iconSize: 74,
                  color: Colors.white,
                  onPressed: onPlayPause,
                  icon: Icon(
                    playback.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                ),
              ),
              if (!request.isLive)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 20,
                  child: SafeArea(
                    top: false,
                    child: _AndroidProgressBar(
                      playback: playback,
                      onSeek: onSeek,
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

class _AndroidProgressBar extends StatefulWidget {
  const _AndroidProgressBar({required this.playback, required this.onSeek});

  final PlaybackState playback;
  final ValueChanged<Duration> onSeek;

  @override
  State<_AndroidProgressBar> createState() => _AndroidProgressBarState();
}

class _AndroidProgressBarState extends State<_AndroidProgressBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final duration = widget.playback.duration;
    final position = widget.playback.position;
    final max = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final value = (_dragValue ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      max,
    );
    final buffered = widget.playback.bufferedPosition.inMilliseconds
        .toDouble()
        .clamp(0.0, max);

    return Row(
      children: [
        _TimeText(duration: Duration(milliseconds: value.round())),
        const SizedBox(width: 14),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: Colors.white30,
              secondaryActiveTrackColor: Colors.white70,
              thumbColor: AppColors.primary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
            ),
            child: ExcludeFocus(
              child: Slider(
                value: value,
                secondaryTrackValue: buffered,
                max: max,
                onChanged: (next) => setState(() => _dragValue = next),
                onChangeEnd: (next) {
                  setState(() => _dragValue = null);
                  widget.onSeek(Duration(milliseconds: next.round()));
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        _TimeText(duration: duration),
      ],
    );
  }
}
