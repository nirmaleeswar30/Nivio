import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/core/tmdb_artwork.dart';

/// Releases desktop artwork after its tab has been hidden for a short time.
/// The surrounding screen stays mounted, preserving its scroll and filters.
class TabArtworkScope extends StatefulWidget {
  const TabArtworkScope({super.key, required this.child});

  final Widget child;

  static bool retainsArtwork(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ArtworkRetention>()?.retain ??
      true;

  @override
  State<TabArtworkScope> createState() => _TabArtworkScopeState();
}

class _TabArtworkScopeState extends State<TabArtworkScope> {
  static const _releaseDelay = Duration(seconds: 5);
  Timer? _releaseTimer;
  bool _retain = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppPlatform.isDesktopOS) return;

    if (TickerMode.valuesOf(context).enabled) {
      _releaseTimer?.cancel();
      _releaseTimer = null;
      _retain = true;
    } else if (_retain) {
      _releaseTimer ??= Timer(_releaseDelay, () {
        _releaseTimer = null;
        setState(() => _retain = false);
      });
    }
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.isDesktopOS) return widget.child;
    return _ArtworkRetention(retain: _retain, child: widget.child);
  }
}

class _ArtworkRetention extends InheritedWidget {
  const _ArtworkRetention({required this.retain, required super.child});

  final bool retain;

  @override
  bool updateShouldNotify(_ArtworkRetention oldWidget) =>
      retain != oldWidget.retain;
}

ImageProvider? avatarArtworkImage(
  BuildContext context,
  String path,
  double diameter,
) {
  if (!TabArtworkScope.retainsArtwork(context)) return null;
  return artworkImageProvider(
    path,
    width: diameter,
    height: diameter,
    kind: ArtworkKind.profile,
    pixelRatio: MediaQuery.devicePixelRatioOf(context),
    maxDecodeWidth: 256,
  );
}

/// Loads artwork sized for its layout and releases it when its tab is hidden.
class ArtworkImage extends StatelessWidget {
  const ArtworkImage({
    super.key,
    required this.imageUrl,
    this.kind = ArtworkKind.poster,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.maxDecodeWidth,
    this.filterQuality = FilterQuality.low,
    this.fadeInDuration = const Duration(milliseconds: 500),
    this.fadeOutDuration = const Duration(seconds: 1),
    this.placeholder,
    this.errorWidget,
    this.colorBlendMode,
  });

  final String imageUrl;
  final ArtworkKind kind;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final int? maxDecodeWidth;
  final FilterQuality filterQuality;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;
  final BlendMode? colorBlendMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: TabArtworkScope.retainsArtwork(context)
          ? LayoutBuilder(
              builder: (context, constraints) => Image(
                image: artworkImageProvider(
                  imageUrl,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  pixelRatio: MediaQuery.devicePixelRatioOf(context),
                  kind: kind,
                  fit: fit ?? BoxFit.scaleDown,
                  maxDecodeWidth: maxDecodeWidth,
                ),
                fit: fit,
                alignment: alignment,
                filterQuality: filterQuality,
                colorBlendMode: colorBlendMode,
                frameBuilder: _buildFrame,
                errorBuilder: (context, error, stackTrace) =>
                    errorWidget?.call(context, imageUrl, error) ??
                    const SizedBox.shrink(),
              ),
            )
          : null,
    );
  }

  Widget _buildFrame(
    BuildContext context,
    Widget child,
    int? frame,
    bool synchronouslyLoaded,
  ) {
    if (synchronouslyLoaded) return child;
    final current = frame == null
        ? placeholder?.call(context, imageUrl) ?? const SizedBox.shrink()
        : child;
    if (fadeInDuration == Duration.zero && fadeOutDuration == Duration.zero) {
      return current;
    }
    return AnimatedSwitcher(
      duration: fadeInDuration,
      reverseDuration: fadeOutDuration,
      switchInCurve: Curves.easeIn,
      switchOutCurve: Curves.easeOut,
      child: KeyedSubtree(key: ValueKey(frame != null), child: current),
    );
  }
}
