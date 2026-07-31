part of 'player_screen.dart';

class _EmbeddedWebServerDrawer extends StatelessWidget {
  const _EmbeddedWebServerDrawer({
    required this.generation,
    required this.width,
    required this.sourceOptions,
    required this.selectedSourceIndex,
    required this.providerLabel,
    required this.onClose,
    required this.onSourceSelected,
    this.serverLabel,
  });

  final int generation;
  final double width;
  final List<PlaybackSourceOption> sourceOptions;
  final int? selectedSourceIndex;
  final String providerLabel;
  final String? serverLabel;
  final VoidCallback onClose;
  final ValueChanged<PlaybackSourceOption> onSourceSelected;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<PlaybackSourceOption>>{};
    for (final option in sourceOptions) {
      final key = option.group ?? _providerGroup(option.provider);
      grouped.putIfAbsent(key, () => []).add(option);
    }
    final usedFallback = grouped.isEmpty;
    if (grouped.isEmpty) {
      grouped[providerLabel] = [
        PlaybackSourceOption(
          index: selectedSourceIndex ?? 0,
          provider: providerLabel,
          server: serverLabel ?? providerLabel,
        ),
      ];
    }
    final tileCount = grouped.values.fold<int>(
      0,
      (total, options) => total + options.length,
    );
    final selectedVisible = grouped.values.any(
      (options) => options.any((option) => option.index == selectedSourceIndex),
    );
    final groupSummary = grouped.entries
        .map(
          (entry) =>
              '${entry.key}(${entry.value.map((option) => option.index).join('|')})',
        )
        .join(', ');
    PlaybackRuntimeDiagnostics.overlayLog(
      'WebView-specific drawer content build generation=$generation '
      'inputSourceCount=${sourceOptions.length} effectiveGroupCount=${grouped.length} '
      'effectiveTileCount=$tileCount usedFallback=$usedFallback '
      'selectedSourceIndex=$selectedSourceIndex selectedVisible=$selectedVisible '
      'groups=[$groupSummary]',
    );

    final listChildren = <Widget>[];
    for (final entry in grouped.entries) {
      if (entry.value.length > 1) {
        listChildren.add(
          _DrawerGroupTitle(
            entry.key,
            diagnosticLabel:
                'web drawer group generation=$generation title=${entry.key}',
          ),
        );
      }
      for (final option in entry.value) {
        final title = _serverTitle(option);
        final selected = option.index == selectedSourceIndex;
        listChildren.add(
          _DrawerOptionTile(
            title: title,
            selected: selected,
            diagnosticLabel:
                'web drawer tile generation=$generation '
                'index=${option.index} title=$title selected=$selected',
            onTap: () => onSourceSelected(option),
          ),
        );
      }
    }

    final panel = Material(
      color: const Color(0x99101010),
      child: _RenderDiagnosticsProbe(
        label: 'web drawer material child generation=$generation',
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: SafeArea(
            left: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RenderDiagnosticsProbe(
                  label: 'web drawer header generation=$generation',
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        const Icon(Icons.dns, color: Colors.white, size: 26),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Select Server',
                            style: TextStyle(
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
                  ),
                ),
                Expanded(
                  child: _RenderDiagnosticsProbe(
                    label:
                        'web drawer list generation=$generation tileCount=$tileCount',
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: listChildren,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return KeyedSubtree(
      key: ValueKey('embedded-web-server-drawer-$generation'),
      child: _RenderDiagnosticsProbe(
        label: 'web drawer keyed subtree generation=$generation',
        child: panel,
      ),
    );
  }

  String _providerGroup(String provider) {
    if (provider.startsWith('Xon')) return 'Xon';
    if (provider.startsWith('Animetsu')) return 'Animetsu';
    if (provider.startsWith('Miruro')) return 'Miruro';
    if (provider.startsWith('Animex')) return 'Animex';
    return provider;
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

class _EmbeddedWebTopBar extends StatelessWidget {
  const _EmbeddedWebTopBar({
    required this.playback,
    required this.title,
    required this.providerLabel,
    required this.canSwitchServer,
    required this.onBack,
    required this.onServer,
    this.serverLabel,
    this.onRetry,
    this.onMiniPlayer,
  });

  final PlaybackState playback;
  final String title;
  final String providerLabel;
  final String? serverLabel;
  final bool canSwitchServer;
  final VoidCallback onBack;
  final VoidCallback onServer;
  final VoidCallback? onRetry;
  final VoidCallback? onMiniPlayer;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (playback.status) {
      PlaybackStatus.loading => 'Loading',
      PlaybackStatus.buffering => 'Buffering',
      PlaybackStatus.error => 'Unavailable',
      PlaybackStatus.completed => 'Completed',
      PlaybackStatus.stopped => 'Stopped',
      PlaybackStatus.ready => 'Ready',
      PlaybackStatus.idle => 'Opening',
    };
    final server =
        serverLabel == null ||
            serverLabel!.isEmpty ||
            serverLabel == providerLabel
        ? providerLabel
        : '$providerLabel · $serverLabel';
    final canRetry = onRetry != null;

    return Material(
      color: const Color(0xFF050505),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 54,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$statusLabel · $server',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canRetry)
                  IconButton(
                    tooltip: 'Retry',
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                  ),
                if (onMiniPlayer != null)
                  IconButton(
                    tooltip: 'Mini player',
                    onPressed: onMiniPlayer,
                    icon: const Icon(
                      Icons.picture_in_picture_alt,
                      color: Colors.white,
                    ),
                  ),
                if (canSwitchServer)
                  IconButton(
                    tooltip: 'Server',
                    onPressed: onServer,
                    icon: const Icon(Icons.sync, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmbeddedWebStatusBanner extends StatelessWidget {
  const _EmbeddedWebStatusBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 16,
      left: 16,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xB3000000),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
