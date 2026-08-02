part of 'player_screen.dart';

class _RightPlayerDrawer extends StatelessWidget {
  const _RightPlayerDrawer({
    required this.drawer,
    required this.playback,
    required this.qualities,
    required this.selectedQuality,
    required this.qualityDiscoveryComplete,
    required this.sourceOptions,
    required this.selectedSourceIndex,
    required this.providerLabel,
    required this.streamAudioOptions,
    required this.selectedStreamAudio,
    required this.externalSubtitles,
    required this.displayFit,
    required this.debandingEnabled,
    required this.subtitleDelay,
    required this.subtitleScale,
    required this.subtitleBackground,
    required this.subtitleOutline,
    required this.onClose,
    required this.onSourceSelected,
    required this.onQualitySelected,
    required this.onStreamAudioSelected,
    required this.onAudioSelected,
    required this.onSubtitleSelected,
    required this.onLoadLocalSubtitle,
    required this.onLoadRemoteSubtitle,
    required this.onSubtitleDelayChanged,
    required this.onSubtitleScaleChanged,
    required this.onSubtitleBackgroundChanged,
    required this.onSubtitleOutlineChanged,
    required this.onDisplayFitChanged,
    required this.onDebandingChanged,
    required this.onVolumeChanged,
    required this.onDiagnosticsPressed,
    required this.onScreenshotPressed,
    required this.onSpeedSelected,
    required this.onRepeatPressed,
    required this.autoplayNextEpisode,
    this.inline = false,
    this.serverLabel,
    this.onAutoplayChanged,
  });

  final _PlayerDrawer drawer;
  final PlaybackState playback;
  final List<_QualityOption> qualities;
  final String selectedQuality;
  final bool qualityDiscoveryComplete;
  final List<PlaybackSourceOption> sourceOptions;
  final int? selectedSourceIndex;
  final String providerLabel;
  final String? serverLabel;
  final List<String> streamAudioOptions;
  final String selectedStreamAudio;
  final List<stream_models.SubtitleTrack> externalSubtitles;
  final BoxFit displayFit;
  final bool debandingEnabled;
  final Duration subtitleDelay;
  final double subtitleScale;
  final String subtitleBackground;
  final String subtitleOutline;
  final VoidCallback onClose;
  final ValueChanged<PlaybackSourceOption> onSourceSelected;
  final ValueChanged<_QualityOption> onQualitySelected;
  final ValueChanged<String> onStreamAudioSelected;
  final ValueChanged<String> onAudioSelected;
  final void Function(String trackId, String? externalUrl) onSubtitleSelected;
  final VoidCallback onLoadLocalSubtitle;
  final VoidCallback onLoadRemoteSubtitle;
  final ValueChanged<Duration> onSubtitleDelayChanged;
  final ValueChanged<double> onSubtitleScaleChanged;
  final ValueChanged<String> onSubtitleBackgroundChanged;
  final ValueChanged<String> onSubtitleOutlineChanged;
  final ValueChanged<BoxFit> onDisplayFitChanged;
  final ValueChanged<bool> onDebandingChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onDiagnosticsPressed;
  final VoidCallback onScreenshotPressed;
  final ValueChanged<double> onSpeedSelected;
  final VoidCallback onRepeatPressed;
  final bool autoplayNextEpisode;
  final bool inline;
  final ValueChanged<bool>? onAutoplayChanged;

  static const _subtitleSizeOptions = <_SubtitleSizeOption>[
    _SubtitleSizeOption('Small', 14.0 / 18.0),
    _SubtitleSizeOption('Medium', 1.0),
    _SubtitleSizeOption('Large', 24.0 / 18.0),
    _SubtitleSizeOption('Extra Large', 30.0 / 18.0),
  ];
  static const _subtitleBackgroundOptions = [
    'Transparent',
    'Semi-Transparent',
    'Solid',
  ];
  static const _subtitleOutlineOptions = ['None', 'Subtle Shadow', 'Outline'];

  static bool _sameAudioLabel(String a, String b) {
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    if (inline) return _buildDrawerPanel(context, animated: false);

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: onClose,
            child: const ColoredBox(color: Color(0x66000000)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _buildDrawerPanel(context, animated: true),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerPanel(BuildContext context, {required bool animated}) {
    final panel = ClipRRect(
      borderRadius: inline
          ? BorderRadius.zero
          : const BorderRadius.horizontal(left: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: inline ? 0 : 16,
          sigmaY: inline ? 0 : 16,
        ),
        child: Material(
          color: inline ? const Color(0xFF101010) : const Color(0xB3101010),
          child: SizedBox(
            width: 360,
            height: double.infinity,
            child: SafeArea(
              left: false,
              child: drawer == _PlayerDrawer.server
                  ? _buildServerDrawer(context)
                  : _buildSettingsDrawer(context),
            ),
          ),
        ),
      ),
    );
    if (!animated) return panel;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutExpo,
      builder: (context, value, child) =>
          Transform.translate(offset: Offset(360 * value, 0), child: child),
      child: panel,
    );
  }

  Widget _buildHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildServerDrawer(BuildContext context) {
    final grouped = <String, List<PlaybackSourceOption>>{};
    for (final option in sourceOptions) {
      final key = option.group ?? _providerGroup(option.provider);
      grouped.putIfAbsent(key, () => []).add(option);
    }
    if (grouped.isEmpty) {
      grouped[providerLabel] = [
        PlaybackSourceOption(
          index: selectedSourceIndex ?? 0,
          provider: providerLabel,
          server: serverLabel ?? providerLabel,
        ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(Icons.dns, 'Select Server'),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final entry in grouped.entries) ...[
                if (entry.value.length > 1) _DrawerGroupTitle(entry.key),
                for (final option in entry.value)
                  _DrawerOptionTile(
                    title: _serverTitle(option),
                    subtitle: option.provider == entry.key
                        ? null
                        : option.provider,
                    selected: option.index == selectedSourceIndex,
                    onTap: () => onSourceSelected(option),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsDrawer(BuildContext context) {
    final subtitleItems = <({String id, String label, String? externalUrl})>[
      for (final track in playback.subtitleTracks)
        (id: track.id, label: track.label, externalUrl: null),
      for (final track in externalSubtitles)
        (
          id: 'external:${track.lang}:${track.url}',
          label: _subtitleLabel(track),
          externalUrl: track.url,
        ),
    ];
    final hasOffSubtitle = subtitleItems.any((track) => track.id == 'no');
    final hasAutoSubtitle = subtitleItems.any((track) => track.id == 'auto');
    final nativeAudioTracks = streamAudioOptions.isEmpty
        ? playback.audioTracks
        : playback.audioTracks
              .where(
                (track) => !streamAudioOptions.any(
                  (audio) => _sameAudioLabel(audio, track.label),
                ),
              )
              .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(Icons.settings, 'Settings'),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _DrawerSection(
                icon: Icons.aspect_ratio,
                title: 'DISPLAY FIT',
                initiallyExpanded: false,
                children: [
                  _DrawerOptionTile(
                    title: 'Best Fit',
                    selected: displayFit == BoxFit.contain,
                    onTap: () => onDisplayFitChanged(BoxFit.contain),
                  ),
                  _DrawerOptionTile(
                    title: 'Fit Screen',
                    selected: displayFit == BoxFit.cover,
                    onTap: () => onDisplayFitChanged(BoxFit.cover),
                  ),
                  _DrawerOptionTile(
                    title: 'Fill',
                    selected: displayFit == BoxFit.fill,
                    onTap: () => onDisplayFitChanged(BoxFit.fill),
                  ),
                  _DrawerOptionTile(
                    title: 'None',
                    selected: displayFit == BoxFit.none,
                    onTap: () => onDisplayFitChanged(BoxFit.none),
                  ),
                ],
              ),
              _DrawerSection(
                icon: Icons.high_quality,
                title: qualityDiscoveryComplete
                    ? 'QUALITY'
                    : 'QUALITY · DISCOVERING',
                children: [
                  for (final option in qualities)
                    _DrawerOptionTile(
                      title: option.label,
                      selected: option.quality == selectedQuality,
                      onTap: () => onQualitySelected(option),
                    ),
                ],
              ),
              _DrawerSection(
                icon: Icons.audiotrack,
                title: 'AUDIO',
                children: [
                  if (streamAudioOptions.isNotEmpty) ...[
                    const _DrawerSubheading('STREAM AUDIO'),
                    for (final audio in streamAudioOptions)
                      _DrawerOptionTile(
                        title: audio,
                        selected: _sameAudioLabel(audio, selectedStreamAudio),
                        onTap: () => onStreamAudioSelected(audio),
                      ),
                  ],
                  if (streamAudioOptions.isNotEmpty &&
                      nativeAudioTracks.isNotEmpty)
                    const _DrawerSubheading('NATIVE TRACKS'),
                  if (nativeAudioTracks.isEmpty && streamAudioOptions.isEmpty)
                    const _DrawerMutedText('No audio tracks found'),
                  for (final track in nativeAudioTracks)
                    _DrawerOptionTile(
                      title: track.label,
                      selected: track.id == playback.selectedAudioTrackId,
                      onTap: () => onAudioSelected(track.id),
                    ),
                ],
              ),
              _DrawerSection(
                icon: Icons.subtitles,
                title: 'SUBTITLE SETTINGS',
                children: [
                  _DrawerSubsection(
                    title: 'TRACKS',
                    initiallyExpanded: true,
                    children: [
                      if (!hasAutoSubtitle)
                        _DrawerOptionTile(
                          title: 'Auto',
                          selected: playback.selectedSubtitleTrackId == 'auto',
                          onTap: () => onSubtitleSelected('auto', null),
                        ),
                      if (!hasOffSubtitle)
                        _DrawerOptionTile(
                          title: 'Off',
                          selected: playback.selectedSubtitleTrackId == 'no',
                          onTap: () => onSubtitleSelected('no', null),
                        ),
                      _DrawerOptionTile(
                        title: 'Load from Local File (.srt, .vtt)',
                        leading: Icons.folder_open,
                        selected: false,
                        onTap: onLoadLocalSubtitle,
                      ),
                      _DrawerOptionTile(
                        title: 'Load from URL (Internet)',
                        leading: Icons.link,
                        selected: false,
                        onTap: onLoadRemoteSubtitle,
                      ),
                      if (subtitleItems.isEmpty)
                        const _DrawerMutedText('No subtitle tracks found'),
                      for (final track in subtitleItems)
                        _DrawerOptionTile(
                          title: track.label,
                          selected:
                              track.id == playback.selectedSubtitleTrackId,
                          onTap: () =>
                              onSubtitleSelected(track.id, track.externalUrl),
                        ),
                    ],
                  ),
                  _DrawerSubsection(
                    title: 'SIZE',
                    children: [
                      for (final option in _subtitleSizeOptions)
                        _DrawerOptionTile(
                          title: option.label,
                          selected: (subtitleScale - option.scale).abs() < 0.01,
                          onTap: () => onSubtitleScaleChanged(option.scale),
                        ),
                    ],
                  ),
                  _DrawerSubsection(
                    title: 'BACKGROUND',
                    children: [
                      for (final option in _subtitleBackgroundOptions)
                        _DrawerOptionTile(
                          title: option,
                          selected: subtitleBackground == option,
                          onTap: () => onSubtitleBackgroundChanged(option),
                        ),
                    ],
                  ),
                  _DrawerSubsection(
                    title: 'TEXT STYLE',
                    children: [
                      for (final option in _subtitleOutlineOptions)
                        _DrawerOptionTile(
                          title: option,
                          selected: subtitleOutline == option,
                          onTap: () => onSubtitleOutlineChanged(option),
                        ),
                    ],
                  ),
                  _DrawerSubsection(
                    title: 'SYNC',
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => onSubtitleDelayChanged(
                                const Duration(milliseconds: -250),
                              ),
                              icon: const Icon(
                                Icons.remove,
                                color: Colors.white,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${subtitleDelay.inMilliseconds > 0 ? '+' : ''}${subtitleDelay.inMilliseconds} ms',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => onSubtitleDelayChanged(
                                const Duration(milliseconds: 250),
                              ),
                              icon: const Icon(Icons.add, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 0, 24, 10),
                        child: Text(
                          'Negative values show subtitles earlier, positive values show them later.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _DrawerSection(
                icon: Icons.blur_linear_rounded,
                title: 'DEBANDING',
                children: [
                  SwitchListTile(
                    value: debandingEnabled,
                    onChanged: onDebandingChanged,
                    activeThumbColor: AppColors.primary,
                    title: const Text(
                      'Enable Debanding',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Reduces color banding artifacts.',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _providerGroup(String provider) {
    if (provider.startsWith('Xon')) return 'Xon';
    if (provider.startsWith('Animetsu')) return 'Animetsu';
    if (provider.startsWith('Miruro')) return 'Miruro';
    if (provider.startsWith('Animex')) return 'Animex';
    return provider;
  }

  String _subtitleLabel(stream_models.SubtitleTrack track) {
    final language = track.lang.trim();
    if (language.isNotEmpty) return language;
    final uri = Uri.tryParse(track.url);
    final lastSegment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    return lastSegment.trim().isEmpty ? 'External subtitle' : lastSegment;
  }

  String _serverTitle(PlaybackSourceOption option) {
    var server = option.server;
    for (final prefix in const [
      'Xon (',
      'Animetsu (',
      'Miruro (',
      'Animex (',
    ]) {
      if (server.startsWith(prefix) && server.endsWith(')')) {
        server = server.substring(prefix.length, server.length - 1);
      }
    }
    return server.isEmpty ? option.provider : server;
  }
}

class _SubtitleSizeOption {
  const _SubtitleSizeOption(this.label, this.scale);

  final String label;
  final double scale;
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection({
    required this.icon,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        iconColor: AppColors.primary,
        collapsedIconColor: Colors.white54,
        leading: Icon(icon, color: Colors.white54),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        children: children,
      ),
    );
  }
}

class _DrawerSubsection extends StatelessWidget {
  const _DrawerSubsection({
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 24),
        childrenPadding: EdgeInsets.zero,
        iconColor: AppColors.primary,
        collapsedIconColor: Colors.white54,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        children: children,
      ),
    );
  }
}

class _DrawerOptionTile extends StatelessWidget {
  const _DrawerOptionTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.leading,
    this.subtitle,
    this.diagnosticLabel,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final IconData? leading;
  final String? subtitle;
  final String? diagnosticLabel;

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: leading == null
          ? null
          : Icon(leading, color: Colors.white70, size: 19),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? AppColors.primary : Colors.white,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null || subtitle!.trim().isEmpty
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
      trailing: selected
          ? const Icon(Icons.check, color: AppColors.primary, size: 19)
          : null,
      selected: selected,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
    final label = diagnosticLabel;
    if (label == null) return tile;
    return _RenderDiagnosticsProbe(label: label, child: tile);
  }
}

class _DrawerGroupTitle extends StatelessWidget {
  const _DrawerGroupTitle(this.title, {this.diagnosticLabel});

  final String title;
  final String? diagnosticLabel;

  @override
  Widget build(BuildContext context) {
    final groupTitle = Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final label = diagnosticLabel;
    if (label == null) return groupTitle;
    return _RenderDiagnosticsProbe(label: label, child: groupTitle);
  }
}

class _DrawerSubheading extends StatelessWidget {
  const _DrawerSubheading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _DrawerMutedText extends StatelessWidget {
  const _DrawerMutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Text(text, style: const TextStyle(color: Colors.white38)),
    );
  }
}

class _TinyPlayerChip extends StatelessWidget {
  const _TinyPlayerChip({required this.label, this.color = Colors.white24});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
