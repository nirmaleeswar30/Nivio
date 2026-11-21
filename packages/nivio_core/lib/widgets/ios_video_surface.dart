import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nivio/services/ios_video_output.dart';

/// Shows [player]'s video on iOS: a native view holding the player's
/// AVSampleBufferDisplayLayer (see [IosVideoOutput]). Use it where the
/// media_kit `Video` widget goes on other platforms.
class IosVideoSurface extends StatefulWidget {
  final Player player;
  final BoxFit fit;

  const IosVideoSurface({super.key, required this.player, this.fit = BoxFit.contain});

  @override
  State<IosVideoSurface> createState() => _IosVideoSurfaceState();
}

class _IosVideoSurfaceState extends State<IosVideoSurface> {
  int? _handle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(IosVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player)) {
      _handle = null;
      _load();
    } else if (oldWidget.fit != widget.fit) {
      IosVideoOutput.instance.setFit(widget.player, _fitName(widget.fit));
    }
  }

  Future<void> _load() async {
    final player = widget.player;
    final handle = await IosVideoOutput.instance.prepare(player);
    if (!mounted || !identical(player, widget.player)) return;
    setState(() => _handle = handle);
  }

  static String _fitName(BoxFit fit) => switch (fit) {
        BoxFit.cover => 'cover',
        BoxFit.fill => 'fill',
        BoxFit.fitWidth => 'fitWidth',
        BoxFit.fitHeight => 'fitHeight',
        _ => 'contain',
      };

  @override
  Widget build(BuildContext context) {
    final handle = _handle;
    if (handle == null) return const ColoredBox(color: Colors.black);
    return UiKitView(
      // A new native view when the player changes, so it takes that player's layer.
      key: ValueKey(handle),
      viewType: 'nivio/ios_video',
      creationParams: {'handle': handle, 'fit': _fitName(widget.fit)},
      creationParamsCodec: const StandardMessageCodec(),
      // Touches belong to the player controls drawn on top.
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
    );
  }
}
