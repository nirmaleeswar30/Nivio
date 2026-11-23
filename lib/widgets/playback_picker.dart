import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/core/tmdb_artwork.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/services/torrent/torrent_models.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:nivio/widgets/marquee_text.dart';
import 'package:nivio/widgets/tab_artwork.dart';

const playbackPickerAccent = Color(0xFF38BDF8);
const playbackPickerField = Color(0xFF1A1A1A);
const playbackPickerProviderColor = Color(0xFFC084FC);
const playbackPickerQualityColor = Color(0xFF60A5FA);

String formatPlaybackPickerSize(int bytes) {
  if (bytes >= 1073741824)
    return '${(bytes / 1073741824).toStringAsFixed(2)} GiB';
  if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MiB';
  if (bytes > 0) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '0 B';
}

List<Widget> playbackPickerPeerTags(TorrentResult torrent) => [
  PlaybackPickerTag(
    torrent.seeders.toString(),
    color: const Color(0xFF4ADE80),
    icon: Icons.arrow_upward_rounded,
  ),
  PlaybackPickerTag(
    torrent.leechers.toString(),
    color: const Color(0xFFF87171),
    icon: Icons.arrow_downward_rounded,
  ),
];

class PlaybackPickerFrame extends StatelessWidget {
  const PlaybackPickerFrame({
    super.key,
    required this.media,
    required this.fullScreen,
    required this.label,
    required this.onClose,
    required this.child,
  });

  final SearchResult media;
  final bool fullScreen;
  final String label;
  final VoidCallback? onClose;
  final Widget child;

  static Future<T?> show<T>(
    BuildContext context,
    Widget Function(bool fullScreen) builder,
  ) {
    final fullScreen = !AppPlatform.useDesktopLayout;
    return showGeneralDialog<T>(
      context: context,
      barrierColor: const Color(0x38000000),
      barrierDismissible: !fullScreen,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) {
        final picker = builder(fullScreen);
        if (fullScreen) return SizedBox.expand(child: picker);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: picker,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact =
        fullScreen &&
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final radius = fullScreen ? BorderRadius.zero : BorderRadius.circular(12);
    final artwork = media.backdropPath ?? media.posterPath;
    return ConstrainedBox(
      constraints: fullScreen
          ? const BoxConstraints.expand()
          : BoxConstraints(
              maxWidth: 800,
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Material(
            color: const Color(0x8C0F0F0F),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: fullScreen
                  ? BorderSide.none
                  : const BorderSide(color: Colors.white12),
            ),
            child: Stack(
              children: [
                if (artwork != null && artwork.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: compact ? 180 : 320,
                    child: IgnorePointer(
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99000000), Colors.transparent],
                          stops: [.15, .92],
                        ).createShader(rect),
                        child: DecoratedBox(
                          position: DecorationPosition.foreground,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x66000000), Color(0xB3000000)],
                            ),
                          ),
                          child: ArtworkImage(
                            imageUrl: artwork,
                            kind: media.backdropPath == null
                                ? ArtworkKind.poster
                                : ArtworkKind.backdrop,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                      ),
                    ),
                  ),
                SafeArea(
                  top: fullScreen,
                  bottom: fullScreen,
                  left: fullScreen,
                  right: fullScreen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          fullScreen ? 8 : 24,
                          fullScreen ? (compact ? 4 : 8) : 20,
                          16,
                          compact ? 6 : 12,
                        ),
                        child: Row(
                          children: [
                            if (fullScreen)
                              IconButton(
                                tooltip: 'Back',
                                icon: const Icon(Icons.arrow_back_rounded),
                                color: Colors.white,
                                onPressed: onClose,
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  MarqueeText(
                                    text: media.title ?? media.name ?? label,
                                    style: TextStyle(
                                      fontSize: fullScreen ? 19 : 22,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                    blankSpace: 40,
                                    velocity: 30,
                                  ),
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!fullScreen)
                              IconButton(
                                tooltip: 'Close',
                                icon: const Icon(Icons.close),
                                color: Colors.white70,
                                onPressed: onClose,
                              ),
                          ],
                        ),
                      ),
                      Expanded(child: child),
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

class PlaybackPickerRow extends StatelessWidget {
  const PlaybackPickerRow({
    super.key,
    required this.title,
    required this.onTap,
    required this.tags,
    this.marker,
    this.highlighted = false,
    this.message,
    this.actionLabel,
  });

  final String title;
  final VoidCallback? onTap;
  final List<Widget> tags;
  final String? marker;
  final bool highlighted;
  final String? message;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final compact = !AppPlatform.useDesktopLayout;
    final item = Material(
      color: highlighted
          ? Colors.white.withValues(alpha: .03)
          : Colors.transparent,
      shape: const Border(bottom: BorderSide(color: Color(0x0DFFFFFF))),
      child: FocusableInkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 24,
            vertical: compact ? 12 : 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: marker != null
                            ? Colors.white
                            : Colors.white.withValues(alpha: .85),
                        fontSize: compact ? 13.5 : 14.5,
                        height: 1.4,
                        fontWeight: marker != null
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (marker case final String text) ...[
                    const SizedBox(width: 12),
                    PlaybackPickerTag(text, color: playbackPickerAccent),
                  ],
                ],
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 5, children: tags),
              ],
              if (message case final String text) ...[
                const SizedBox(height: 8),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFFFCA5A5),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return actionLabel == null
        ? item
        : Tooltip(message: actionLabel!, child: item);
  }
}

class PlaybackPickerTag extends StatelessWidget {
  const PlaybackPickerTag(
    this.label, {
    super.key,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: .20)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final IconData icon) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: .3,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class PlaybackPickerTab extends StatelessWidget {
  const PlaybackPickerTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(6));
    final color = selected ? playbackPickerAccent : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Material(
        color: selected
            ? color.withValues(alpha: .16)
            : const Color(0x761A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? color.withValues(alpha: .32) : Colors.white12,
          ),
        ),
        child: FocusableInkWell(
          onTap: onTap,
          autofocus: autofocus,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Text(
              label,
              style: TextStyle(
                color: onTap == null ? Colors.white38 : color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
