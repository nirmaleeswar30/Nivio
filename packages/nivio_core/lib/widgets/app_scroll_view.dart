import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// App-wide platform-optimized scroll views.
/// Uses smooth mouse-wheel impulse physics and native trackpad/touch pass-through on Desktop,
/// and standard native Flutter scroll physics on Mobile.
class AppListView {
  static Widget builder({
    Key? key,
    Axis scrollDirection = Axis.vertical,
    bool reverse = false,
    ScrollController? controller,
    bool? primary,
    ScrollPhysics? physics,
    bool shrinkWrap = false,
    EdgeInsetsGeometry? padding,
    required NullableIndexedWidgetBuilder itemBuilder,
    int? itemCount,
    double? itemExtent,
    Widget? prototypeItem,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
    double? cacheExtent,
    int? semanticChildCount,
    double scrollSpeed = 2.0,
    Duration silkyScrollDuration = const Duration(milliseconds: 500),
    Curve animationCurve = Curves.easeOutQuart,
  }) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return DesktopSmoothScrollWrapper(
        key: key,
        controller: controller,
        scrollDirection: scrollDirection,
        reverse: reverse,
        scrollSpeed: scrollSpeed,
        builder: (context, effectiveController) => ListView.builder(
          scrollDirection: scrollDirection,
          reverse: reverse,
          controller: effectiveController,
          primary: false,
          physics: physics ?? const AlwaysScrollableScrollPhysics(),
          shrinkWrap: shrinkWrap,
          padding: padding,
          itemBuilder: itemBuilder,
          itemCount: itemCount,
          itemExtent: itemExtent,
          prototypeItem: prototypeItem,
          addAutomaticKeepAlives: addAutomaticKeepAlives,
          addRepaintBoundaries: addRepaintBoundaries,
          addSemanticIndexes: addSemanticIndexes,
          cacheExtent: cacheExtent,
          semanticChildCount: semanticChildCount,
        ),
      );
    }
    return ListView.builder(
      key: key,
      scrollDirection: scrollDirection,
      reverse: reverse,
      controller: controller,
      primary: primary,
      physics: physics,
      shrinkWrap: shrinkWrap,
      padding: padding,
      itemBuilder: itemBuilder,
      itemCount: itemCount,
      itemExtent: itemExtent,
      prototypeItem: prototypeItem,
      addAutomaticKeepAlives: addAutomaticKeepAlives,
      addRepaintBoundaries: addRepaintBoundaries,
      addSemanticIndexes: addSemanticIndexes,
      cacheExtent: cacheExtent,
      semanticChildCount: semanticChildCount,
    );
  }
}

class AppCustomScrollView extends StatelessWidget {
  final List<Widget> slivers;
  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;
  final ScrollBehavior? scrollBehavior;
  final String? restorationId;
  final Clip clipBehavior;
  final double scrollSpeed;
  final Duration silkyScrollDuration;
  final Curve animationCurve;
  final double? cacheExtent;

  const AppCustomScrollView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.scrollBehavior,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
    required this.slivers,
    this.scrollSpeed = 2.0,
    this.silkyScrollDuration = const Duration(milliseconds: 500),
    this.animationCurve = Curves.easeOutQuart,
    this.cacheExtent,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return DesktopSmoothScrollWrapper(
        key: key,
        controller: controller,
        scrollDirection: scrollDirection,
        reverse: reverse,
        scrollSpeed: scrollSpeed,
        builder: (context, effectiveController) => CustomScrollView(
          scrollDirection: scrollDirection,
          reverse: reverse,
          controller: effectiveController,
          primary: false,
          physics: physics ?? const AlwaysScrollableScrollPhysics(),
          scrollBehavior: scrollBehavior,
          restorationId: restorationId,
          clipBehavior: clipBehavior,
          slivers: slivers,
          cacheExtent: cacheExtent,
        ),
      );
    }
    return CustomScrollView(
      key: key,
      scrollDirection: scrollDirection,
      reverse: reverse,
      controller: controller,
      primary: primary,
      physics: physics,
      scrollBehavior: scrollBehavior,
      restorationId: restorationId,
      clipBehavior: clipBehavior,
      slivers: slivers,
      cacheExtent: cacheExtent,
    );
  }
}

class AppGridView {
  static Widget builder({
    Key? key,
    Axis scrollDirection = Axis.vertical,
    bool reverse = false,
    ScrollController? controller,
    bool? primary,
    ScrollPhysics? physics,
    bool shrinkWrap = false,
    EdgeInsetsGeometry? padding,
    required SliverGridDelegate gridDelegate,
    required NullableIndexedWidgetBuilder itemBuilder,
    int? itemCount,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
    double? cacheExtent,
    int? semanticChildCount,
    Clip clipBehavior = Clip.hardEdge,
    double scrollSpeed = 2.0,
    Duration silkyScrollDuration = const Duration(milliseconds: 500),
    Curve animationCurve = Curves.easeOutQuart,
  }) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return DesktopSmoothScrollWrapper(
        key: key,
        controller: controller,
        scrollDirection: scrollDirection,
        reverse: reverse,
        scrollSpeed: scrollSpeed,
        builder: (context, effectiveController) => GridView.builder(
          scrollDirection: scrollDirection,
          reverse: reverse,
          controller: effectiveController,
          primary: false,
          physics: physics ?? const AlwaysScrollableScrollPhysics(),
          shrinkWrap: shrinkWrap,
          padding: padding,
          gridDelegate: gridDelegate,
          itemBuilder: itemBuilder,
          itemCount: itemCount,
          addAutomaticKeepAlives: addAutomaticKeepAlives,
          addRepaintBoundaries: addRepaintBoundaries,
          addSemanticIndexes: addSemanticIndexes,
          cacheExtent: cacheExtent,
          semanticChildCount: semanticChildCount,
          clipBehavior: clipBehavior,
        ),
      );
    }
    return GridView.builder(
      key: key,
      scrollDirection: scrollDirection,
      reverse: reverse,
      controller: controller,
      primary: primary,
      physics: physics,
      shrinkWrap: shrinkWrap,
      padding: padding,
      gridDelegate: gridDelegate,
      itemBuilder: itemBuilder,
      itemCount: itemCount,
      addAutomaticKeepAlives: addAutomaticKeepAlives,
      addRepaintBoundaries: addRepaintBoundaries,
      addSemanticIndexes: addSemanticIndexes,
      cacheExtent: cacheExtent,
      semanticChildCount: semanticChildCount,
      clipBehavior: clipBehavior,
    );
  }
}

class AppSingleChildScrollView extends StatelessWidget {
  final Widget child;
  final Axis scrollDirection;
  final bool reverse;
  final EdgeInsetsGeometry? padding;
  final bool? primary;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final Clip clipBehavior;
  final double scrollSpeed;
  final Duration silkyScrollDuration;
  final Curve animationCurve;

  const AppSingleChildScrollView({
    super.key,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.primary,
    this.physics,
    this.controller,
    this.clipBehavior = Clip.hardEdge,
    required this.child,
    this.scrollSpeed = 2.0,
    this.silkyScrollDuration = const Duration(milliseconds: 500),
    this.animationCurve = Curves.easeOutQuart,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return DesktopSmoothScrollWrapper(
        key: key,
        controller: controller,
        scrollDirection: scrollDirection,
        reverse: reverse,
        scrollSpeed: scrollSpeed,
        builder: (context, effectiveController) => SingleChildScrollView(
          scrollDirection: scrollDirection,
          reverse: reverse,
          padding: padding,
          physics: physics ?? const AlwaysScrollableScrollPhysics(),
          controller: effectiveController,
          primary: false,
          clipBehavior: clipBehavior,
          child: child,
        ),
      );
    }
    return SingleChildScrollView(
      key: key,
      scrollDirection: scrollDirection,
      reverse: reverse,
      padding: padding,
      primary: primary,
      physics: physics,
      controller: controller,
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}

/// Custom [ScrollPositionWithSingleContext] that filters out discrete mouse wheel
/// pointer scrolls so [DesktopSmoothScrollWrapper]'s impulse ticker can interpolate
/// them smoothly, while allowing trackpads and touch devices to scroll natively
/// with hardware kinetic momentum.
class DesktopSmoothScrollPosition extends ScrollPositionWithSingleContext {
  DesktopSmoothScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    super.initialPixels,
    super.keepScrollOffset,
    super.debugLabel,
  });

  PointerDeviceKind currentDeviceKind = PointerDeviceKind.trackpad;

  bool get isExternalScrolling =>
      activity is DragScrollActivity || activity is DrivenScrollActivity;

  @override
  void pointerScroll(double delta) {
    if (currentDeviceKind == PointerDeviceKind.mouse) {
      // Discrete mouse wheel notches are animated smoothly by DesktopSmoothScrollWrapper.
      return;
    }
    // Trackpads and touchpads execute standard native Flutter kinetic scrolling.
    super.pointerScroll(delta);
  }
}

/// Custom [ScrollController] that instantiates [DesktopSmoothScrollPosition]
/// and proxies position attachment to any user-provided [parentController].
class DesktopSmoothScrollController extends ScrollController {
  DesktopSmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.parentController,
  });

  ScrollController? parentController;
  DesktopSmoothScrollPosition? _position;
  DesktopSmoothScrollPosition? get smoothPosition => _position;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    _position = DesktopSmoothScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      debugLabel: debugLabel,
    );
    return _position!;
  }

  @override
  void attach(ScrollPosition position) {
    if (parentController != null && !parentController!.positions.contains(position)) {
      parentController!.attach(position);
    }
    super.attach(position);
  }

  @override
  void detach(ScrollPosition position) {
    if (parentController != null && parentController!.positions.contains(position)) {
      parentController!.detach(position);
    }
    super.detach(position);
  }
}

/// Desktop wrapper providing Chromium-style mouse-wheel impulse physics
/// and pure 1:1 pass-through for trackpad/touch gestures.
class DesktopSmoothScrollWrapper extends StatefulWidget {
  final ScrollController? controller;
  final Axis scrollDirection;
  final bool reverse;
  final double scrollSpeed;
  final Widget Function(BuildContext context, ScrollController controller) builder;

  const DesktopSmoothScrollWrapper({
    super.key,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.scrollSpeed = 2.0,
    required this.builder,
  });

  @override
  State<DesktopSmoothScrollWrapper> createState() => _DesktopSmoothScrollWrapperState();
}

class _DesktopSmoothScrollWrapperState extends State<DesktopSmoothScrollWrapper>
    with SingleTickerProviderStateMixin {
  late DesktopSmoothScrollController _effectiveController;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _targetOffset = 0.0;
  bool _isTickerActive = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _effectiveController = DesktopSmoothScrollController(
      parentController: widget.controller,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller == null) {
      final primary = PrimaryScrollController.maybeOf(context);
      if (primary != null && _effectiveController.parentController != primary) {
        _effectiveController.parentController = primary;
      }
    }
  }

  @override
  void didUpdateWidget(covariant DesktopSmoothScrollWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_effectiveController._position != null) {
        final pos = _effectiveController._position!;
        if (oldWidget.controller != null &&
            oldWidget.controller!.positions.contains(pos)) {
          oldWidget.controller!.detach(pos);
        }
        if (widget.controller != null &&
            !widget.controller!.positions.contains(pos)) {
          widget.controller!.attach(pos);
        }
      }
      _effectiveController.parentController = widget.controller;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    if (_effectiveController.parentController != null &&
        _effectiveController._position != null) {
      final pos = _effectiveController._position!;
      if (_effectiveController.parentController!.positions.contains(pos)) {
        _effectiveController.parentController!.detach(pos);
      }
    }
    _effectiveController.dispose();
    super.dispose();
  }

  void _startTicker() {
    if (!_isTickerActive && mounted) {
      _lastElapsed = Duration.zero;
      _isTickerActive = true;
      _ticker.start();
    }
  }

  void _stopTicker() {
    if (_isTickerActive) {
      _isTickerActive = false;
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted || !_effectiveController.hasClients || !_effectiveController.position.hasContentDimensions) {
      _stopTicker();
      return;
    }

    if (_effectiveController.smoothPosition?.isExternalScrolling == true) {
      _stopTicker();
      _targetOffset = _effectiveController.offset;
      return;
    }

    final double dt = _lastElapsed == Duration.zero
        ? 1.0 / 60.0
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    if (dt <= 0.0 || dt > 0.1) return;

    final double current = _effectiveController.offset;
    final double remaining = _targetOffset - current;

    if (remaining.abs() < 0.5) {
      _effectiveController.jumpTo(_targetOffset);
      _stopTicker();
      return;
    }

    // Exponential friction decay (Chromium impulse physics model)
    // Rate 22.0 provides instant acceleration with a buttery ~160ms settle time.
    final double factor = 1.0 - math.exp(-22.0 * dt);
    final double next = current + remaining * factor;
    _effectiveController.jumpTo(next);
  }

  bool _isTrackpad(PointerScrollEvent event) {
    if (event.kind == PointerDeviceKind.trackpad) return true;

    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;

    // Simultaneous 2D movement only occurs on touchpads
    if (dx != 0.0 && dy != 0.0) return true;

    // Fractional micro-deltas are characteristic of precision touchpads
    final absDy = dy.abs();
    if (absDy > 0.0 && absDy < 15.0 && (dy != dy.roundToDouble())) return true;

    final absDx = dx.abs();
    if (absDx > 0.0 && absDx < 15.0 && (dx != dx.roundToDouble())) return true;

    return false;
  }

  void _onPointerSignal(PointerSignalEvent signalEvent) {
    if (signalEvent is! PointerScrollEvent) return;

    final bool isTrackpad = _isTrackpad(signalEvent);
    final deviceKind = isTrackpad ? PointerDeviceKind.trackpad : signalEvent.kind;

    if (_effectiveController.smoothPosition != null) {
      _effectiveController.smoothPosition!.currentDeviceKind = deviceKind;
    }

    if (isTrackpad) {
      _stopTicker();
      return;
    }

    _handleMouseWheel(signalEvent);
  }

  void _handleMouseWheel(PointerScrollEvent event) {
    if (!_effectiveController.hasClients || !_effectiveController.position.hasContentDimensions) return;

    final bool isHorizontal = widget.scrollDirection == Axis.horizontal;
    final bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    double rawDelta;
    if (isHorizontal) {
      if (isShiftPressed) {
        rawDelta = event.scrollDelta.dy != 0 ? event.scrollDelta.dy : event.scrollDelta.dx;
      } else if (event.scrollDelta.dx != 0) {
        rawDelta = event.scrollDelta.dx;
      } else {
        // Vertical wheel on horizontal list without Shift: bubble to vertical parent
        return;
      }
    } else {
      if (isShiftPressed && event.scrollDelta.dx != 0) {
        rawDelta = event.scrollDelta.dx;
      } else {
        rawDelta = event.scrollDelta.dy;
      }
    }

    if (rawDelta == 0.0) return;

    final double effectiveDelta = (widget.reverse ? -rawDelta : rawDelta) * widget.scrollSpeed;
    final pos = _effectiveController.position;
    final double current = _effectiveController.offset;
    final double minScroll = pos.minScrollExtent;
    final double maxScroll = pos.maxScrollExtent;

    final bool isReversing = _isTickerActive &&
        ((effectiveDelta > 0 && _targetOffset < current) ||
         (effectiveDelta < 0 && _targetOffset > current));

    if (isReversing || !_isTickerActive) {
      _targetOffset = current + effectiveDelta;
    } else {
      _targetOffset += effectiveDelta;
    }

    _targetOffset = _targetOffset.clamp(minScroll, maxScroll);
    _startTicker();
  }

  void _onPointerDown(PointerDownEvent event) {
    _stopTicker();
    if (_effectiveController.hasClients) {
      _targetOffset = _effectiveController.offset;
    }
  }

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    _stopTicker();
    if (_effectiveController.smoothPosition != null) {
      _effectiveController.smoothPosition!.currentDeviceKind = PointerDeviceKind.trackpad;
    }
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _stopTicker();
    if (_effectiveController.smoothPosition != null) {
      _effectiveController.smoothPosition!.currentDeviceKind = PointerDeviceKind.trackpad;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      onPointerDown: _onPointerDown,
      onPointerPanZoomStart: _onPointerPanZoomStart,
      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
      child: widget.builder(context, _effectiveController),
    );
  }
}
