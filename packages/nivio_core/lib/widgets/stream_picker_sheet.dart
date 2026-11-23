import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nivio/core/tmdb_artwork.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/screens/stream_selection_screen.dart';
import 'package:nivio/services/extensions/extension_resolver.dart';
import 'package:nivio/services/extensions/stream_discovery.dart';
import 'package:nivio/services/extensions/stream_selection.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:nivio/widgets/marquee_text.dart';
import 'package:nivio/widgets/skeleton.dart';

class StreamPickerOutcome {
  const StreamPickerOutcome({
    this.choice,
    this.result,
    this.refresh = false,
    this.automatic = false,
    this.preferredResolution,
  });

  final StreamChoice? choice;
  final StreamResult? result;
  final bool refresh;
  final bool automatic;
  final int? preferredResolution;
}

class DirectStreamPickerSheet extends StatefulWidget {
  const DirectStreamPickerSheet({
    super.key,
    required this.discovery,
    this.selectAutomatically,
    this.isFullScreen = false,
  });

  final StreamDiscovery discovery;
  final Future<StreamPickerOutcome?> Function()? selectAutomatically;
  final bool isFullScreen;

  static Future<StreamPickerOutcome?> show(
    BuildContext context,
    StreamDiscovery discovery, {
    Future<StreamPickerOutcome?> Function()? selectAutomatically,
  }) async {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final navigator = Navigator.of(context, rootNavigator: !isMobile);
    final route = isMobile
        ? MaterialPageRoute<StreamPickerOutcome>(
            builder: (_) => Scaffold(
              backgroundColor: const Color(0xFF0F0F0F),
              body: DirectStreamPickerSheet(
                discovery: discovery,
                selectAutomatically: selectAutomatically,
                isFullScreen: true,
              ),
            ),
          )
        : DialogRoute<StreamPickerOutcome>(
            context: context,
            themes: InheritedTheme.capture(
              from: context,
              to: navigator.context,
            ),
            barrierColor: Colors.black.withValues(alpha: .8),
            builder: (_) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: DirectStreamPickerSheet(
                discovery: discovery,
                selectAutomatically: selectAutomatically,
              ),
            ),
          );
    final outcome = await navigator.push(route);
    if (outcome?.refresh == true) await route.completed;
    return outcome;
  }

  @override
  State<DirectStreamPickerSheet> createState() =>
      _DirectStreamPickerSheetState();
}

class _DirectStreamPickerSheetState extends State<DirectStreamPickerSheet> {
  final _searchController = TextEditingController();
  late int? _resolution = _discovery.selection.resolutions.firstOrNull;
  var _changedResolution = false;
  var _autoCancelled = false;
  var _selecting = false;
  var _closed = false;
  String? _hoveredChoice;

  StreamDiscovery get _discovery => widget.discovery;

  @override
  void initState() {
    super.initState();
    if (widget.selectAutomatically != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_autoSelect());
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _autoSelect() async {
    if (_autoCancelled) return;
    setState(() => _selecting = true);
    StreamPickerOutcome? outcome;
    try {
      outcome = await widget.selectAutomatically!();
    } catch (_) {
      // Leave the picker open if autoplay fails.
    }
    if (!mounted || _closed || ModalRoute.of(context)?.isCurrent != true)
      return;
    setState(() => _selecting = false);
    if (!_autoCancelled && outcome != null) _finish(outcome);
  }

  void _cancelAutoPlay() {
    if (!_selecting || _autoCancelled) return;
    setState(() {
      _autoCancelled = true;
      _selecting = false;
    });
  }

  void _finish([StreamPickerOutcome? outcome]) {
    if (_closed) return;
    _closed = true;
    _autoCancelled = true;
    Navigator.of(context).pop(outcome);
  }

  void _play(StreamChoice choice) {
    if (!_discovery.unavailable.contains(choice.id) && choice.isDirect) {
      _finish(
        StreamPickerOutcome(
          choice: choice,
          result: choice.direct,
          preferredResolution: _resolution,
        ),
      );
    }
  }

  Future<void> _openSettings() async {
    _cancelAutoPlay();
    await showStreamPickerSettings(context);
    if (mounted) _finish(const StreamPickerOutcome(refresh: true));
  }

  void _filterChanged(String _) {
    _cancelAutoPlay();
    setState(() {});
  }

  List<StreamChoice> _visibleChoices() {
    final text = _searchController.text.trim().toLowerCase();
    final ordered = _discovery.orderForPicker(
      _discovery.choices.where((choice) {
        if (!choice.isDirect) return false;
        return text.isEmpty ||
            '${choice.title} ${choice.provider} ${choice.origin}'
                .toLowerCase()
                .contains(text);
      }).toList(),
    );
    final requested = _resolution;
    if (requested == null) return ordered;
    final matches = ordered.where(
      (choice) => choice.knownResolutions.contains(requested),
    );
    if (matches.isEmpty && !_changedResolution) return ordered;
    return [
      ...matches,
      ...ordered.where((choice) => choice.knownResolutions.isEmpty),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isFullScreen = widget.isFullScreen;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isCompactLandscape = isFullScreen && isLandscape;
    final spacing = isCompactLandscape ? 8.0 : 16.0;
    final horizontalPadding = isFullScreen ? 16.0 : 24.0;

    final title =
        _discovery.media.title ?? _discovery.media.name ?? 'Select Stream';
    final backdropPath =
        _discovery.media.backdropPath ?? _discovery.media.posterPath;

    return Listener(
      onPointerDown: (_) => _cancelAutoPlay(),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: isFullScreen
              ? BorderRadius.zero
              : BorderRadius.circular(12),
          border: isFullScreen
              ? null
              : Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: isFullScreen
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.8),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        constraints: isFullScreen
            ? const BoxConstraints.expand()
            : BoxConstraints(
                maxWidth: 800,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
        child: ClipRRect(
          borderRadius: isFullScreen
              ? BorderRadius.zero
              : BorderRadius.circular(12),
          child: Stack(
            children: [
              if (backdropPath != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: isCompactLandscape ? 180 : 320,
                  child: ShaderMask(
                    shaderCallback: (rect) {
                      return const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black, Colors.transparent],
                        stops: [0.4, 0.9],
                      ).createShader(rect);
                    },
                    blendMode: BlendMode.dstIn,
                    child: Container(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: artworkImageProvider(
                            backdropPath,
                            width: isFullScreen
                                ? MediaQuery.sizeOf(context).width
                                : MediaQuery.sizeOf(
                                    context,
                                  ).width.clamp(0, 800),
                            height:
                                MediaQuery.sizeOf(context).height *
                                (isFullScreen ? 1 : 0.85),
                            pixelRatio: MediaQuery.devicePixelRatioOf(context),
                            kind: _discovery.media.backdropPath != null
                                ? ArtworkKind.backdrop
                                : ArtworkKind.poster,
                          ),
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                        ),
                      ),
                      foregroundDecoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF0F0F0F).withOpacity(0.4),
                            const Color(0xFF0F0F0F).withOpacity(0.7),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              SafeArea(
                top: isFullScreen,
                bottom: isFullScreen,
                left: isFullScreen,
                right: isFullScreen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isFullScreen ? 8.0 : 24.0,
                        isFullScreen ? (isCompactLandscape ? 4.0 : 8.0) : 20.0,
                        16.0,
                        spacing,
                      ),
                      child: Row(
                        children: [
                          if (isFullScreen) ...[
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                _finish();
                              },
                              splashRadius: 20,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: MarqueeText(
                              text: title,
                              style: TextStyle(
                                fontSize: isFullScreen ? 19 : 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              blankSpace: 40.0,
                              velocity: 30.0,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Stream settings',
                            icon: const Icon(
                              Icons.settings_outlined,
                              color: Colors.white70,
                            ),
                            onPressed: _openSettings,
                            splashRadius: 20,
                          ),
                          if (!isFullScreen)
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                              ),
                              onPressed: () {
                                _finish();
                              },
                              hoverColor: Colors.white.withOpacity(0.1),
                              splashRadius: 20,
                            ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) => _buildControls(
                          spacing,
                          isCompactLandscape && constraints.maxWidth >= 520,
                        ),
                      ),
                    ),
                    SizedBox(height: spacing),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFF2A2A2A),
                    ),

                    // Results List
                    Expanded(child: _buildContent()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls(double spacing, bool compact) {
    final search = TextField(
      controller: _searchController,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      onChanged: _filterChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search direct streams...',
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: .3),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search,
          color: Colors.white.withValues(alpha: .5),
          size: 20,
        ),
        suffixIcon: IconButton(
          tooltip: 'Search',
          icon: const Icon(
            Icons.arrow_forward_rounded,
            color: Color(0xFF38BDF8),
            size: 20,
          ),
          onPressed: () => FocusScope.of(context).unfocus(),
        ),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        contentPadding: EdgeInsets.symmetric(vertical: spacing),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
    final filters = Wrap(
      spacing: 16,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_discovery.media.mediaType != 'movie')
          Text(
            'Episode ${_discovery.episode}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        _buildResolutionSelector(),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact)
          Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              Flexible(child: filters),
            ],
          )
        else ...[
          search,
          SizedBox(height: spacing),
          filters,
        ],
        SizedBox(height: spacing),
        ListenableBuilder(
          listenable: _discovery,
          builder: (context, _) {
            final visible = _visibleChoices();
            final first = visible
                .where((choice) => !_discovery.unavailable.contains(choice.id))
                .firstOrNull;
            if (first == null) return const SizedBox.shrink();
            final resolution = _resolution;
            final showingFallback =
                !_changedResolution &&
                !_discovery.searching &&
                resolution != null &&
                visible.any((choice) => choice.knownResolutions.isNotEmpty) &&
                !visible.any(
                  (choice) => choice.knownResolutions.contains(resolution),
                );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showingFallback)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'No confirmed ${resolution}p match. Showing available streams.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ElevatedButton(
                  onPressed: () => _play(first),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(vertical: spacing),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _selecting ? 'Selecting stream…' : 'Auto Select Stream',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildResolutionSelector() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Resolution ',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(width: 8),
      Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: .05)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _resolution ?? 0,
            dropdownColor: const Color(0xFF1A1A1A),
            icon: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.unfold_more, color: Colors.white54, size: 16),
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            onChanged: (value) {
              if (value == null) return;
              _cancelAutoPlay();
              setState(() {
                _resolution = value == 0 ? null : value;
                _changedResolution = true;
              });
            },
            items: [
              const DropdownMenuItem(value: 0, child: Text('Any')),
              for (final height in {
                480,
                720,
                1080,
                1440,
                2160,
                ..._discovery.selection.resolutions,
              }.toList()..sort())
                DropdownMenuItem(value: height, child: Text('${height}p')),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _buildContent() => ListenableBuilder(
    listenable: _discovery,
    builder: (context, _) {
      final results = _visibleChoices();
      if (results.isEmpty && _discovery.searching) return _buildLoading();
      if (results.isEmpty) {
        return Center(
          child: Text(
            _searchController.text.trim().isEmpty &&
                    _discovery.failures.isNotEmpty
                ? 'Couldn’t reach some direct sources.'
                : 'No direct streams found.',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: results.length,
        itemBuilder: (_, index) => _buildRow(results[index], index == 0),
      );
    },
  );

  Widget _buildRow(StreamChoice choice, bool best) {
    final disabled = _discovery.unavailable.contains(choice.id);
    final previous = choice.bingeGroup == _discovery.previous?.bingeGroup;
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final heights = choice.knownResolutions;
    final qualityLabel = heights.isEmpty
        ? (choice.direct!.isM3U8
              ? 'Auto · resolution unknown'
              : 'Resolution unknown')
        : heights.map((height) => '${height}p').join(' / ');
    final serverLabel = choice.quality.trim();
    final showServer =
        ![
          '',
          'auto',
          'unknown',
          'unknown quality',
        ].contains(serverLabel.toLowerCase()) &&
        choice.reportedResolution == null &&
        serverLabel != qualityLabel;
    return MouseRegion(
      cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredChoice = choice.id),
      onExit: (_) {
        if (_hoveredChoice == choice.id) setState(() => _hoveredChoice = null);
      },
      child: FocusableTap(
        onTap: disabled ? null : () => _play(choice),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 24,
            vertical: isMobile ? 12 : 16,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: .05)),
            ),
            color: _hoveredChoice == choice.id && !disabled
                ? Colors.white.withValues(alpha: .05)
                : best
                ? Colors.white.withValues(alpha: .03)
                : Colors.transparent,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      choice.title,
                      style: TextStyle(
                        fontSize: isMobile ? 13.5 : 14.5,
                        height: 1.4,
                        fontWeight: best ? FontWeight.bold : FontWeight.normal,
                        color: best
                            ? Colors.white
                            : Colors.white.withValues(alpha: .8),
                      ),
                    ),
                  ),
                  if (best || previous) ...[
                    const SizedBox(width: 12),
                    _marker(previous ? 'PREVIOUS SOURCE' : 'BEST MATCH'),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _tag(
                      choice.provider.toUpperCase(),
                      const Color(0xFFC084FC),
                    ),
                    const SizedBox(width: 8),
                    _tag(qualityLabel, const Color(0xFF60A5FA)),
                    if (showServer) ...[
                      const SizedBox(width: 8),
                      _tag(serverLabel, Colors.grey),
                    ],
                    const SizedBox(width: 8),
                    _tag(choice.origin, Colors.grey),
                    if (choice.audioType ?? choice.audio
                        case final String audio) ...[
                      const SizedBox(width: 8),
                      _tag(audio, Colors.grey),
                    ],
                  ],
                ),
              ),
              if (disabled) ...[
                const SizedBox(height: 8),
                const Text(
                  'Couldn’t open this stream. Choose another result.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _marker(String label) {
    const color = Color(0xFF38BDF8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: .5,
        ),
      ),
    );
  }

  Widget _buildLoading() {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    return Skeletonizer(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 7,
        itemBuilder: (_, _) => Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 24,
            vertical: isMobile ? 12 : 16,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: .05)),
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SkeletonBox(width: double.infinity, height: 15),
              SizedBox(height: 10),
              Row(
                children: [
                  SkeletonBox(
                    width: 60,
                    height: 20,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                  SizedBox(width: 8),
                  SkeletonBox(
                    width: 74,
                    height: 20,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                  SizedBox(width: 8),
                  SkeletonBox(
                    width: 54,
                    height: 20,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: .2)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: .3,
      ),
    ),
  );
}
