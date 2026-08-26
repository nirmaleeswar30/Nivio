import 'dart:io';
import 'package:flutter/material.dart';
import 'package:silky_scroll/silky_scroll.dart';

/// App-wide platform-optimized scroll views.
/// Uses smooth mouse-wheel physics on Desktop, and standard native Flutter scroll physics on Mobile.
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
    int? addAutomaticKeepAlives,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
    double? cacheExtent,
    int? semanticChildCount,
    double scrollSpeed = 2.0,
    Duration silkyScrollDuration = const Duration(milliseconds: 500),
    Curve animationCurve = Curves.easeOutQuart,
  }) {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return SilkyListView.builder(
        key: key,
        scrollDirection: scrollDirection,
        reverse: reverse,
        controller: controller,
        physics: physics ?? const AlwaysScrollableScrollPhysics(),
        shrinkWrap: shrinkWrap,
        padding: padding,
        itemBuilder: itemBuilder,
        itemCount: itemCount,
        itemExtent: itemExtent,
        prototypeItem: prototypeItem,
        addRepaintBoundaries: addRepaintBoundaries,
        addSemanticIndexes: addSemanticIndexes,
        cacheExtent: cacheExtent,
        semanticChildCount: semanticChildCount,
        scrollSpeed: scrollSpeed,
        silkyScrollDuration: silkyScrollDuration,
        animationCurve: animationCurve,
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
      return SilkyCustomScrollView(
        key: key,
        scrollDirection: scrollDirection,
        reverse: reverse,
        controller: controller,
        physics: physics ?? const AlwaysScrollableScrollPhysics(),
        restorationId: restorationId,
        clipBehavior: clipBehavior,
        slivers: slivers,
        scrollSpeed: scrollSpeed,
        silkyScrollDuration: silkyScrollDuration,
        animationCurve: animationCurve,
        cacheExtent: cacheExtent,
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
      return SilkyGridView.builder(
        key: key,
        scrollDirection: scrollDirection,
        reverse: reverse,
        controller: controller,
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
        scrollSpeed: scrollSpeed,
        silkyScrollDuration: silkyScrollDuration,
        animationCurve: animationCurve,
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
      return SilkySingleChildScrollView(
        key: key,
        scrollDirection: scrollDirection,
        reverse: reverse,
        padding: padding,
        physics: physics ?? const AlwaysScrollableScrollPhysics(),
        controller: controller,
        clipBehavior: clipBehavior,
        child: child,
        scrollSpeed: scrollSpeed,
        silkyScrollDuration: silkyScrollDuration,
        animationCurve: animationCurve,
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
