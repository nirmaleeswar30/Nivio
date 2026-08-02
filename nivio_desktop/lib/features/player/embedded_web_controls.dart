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
