import 'package:flutter/widgets.dart';

/// Lets the TV focus policy reach the side rail, which lives in the shell
/// route (a different focus scope from the page content). Set up by
/// MainShellScreen on TV.
class TvRail {
  TvRail._();

  /// Moves focus onto the rail if it is on screen; returns whether it did.
  static bool Function()? enter;

  /// Whether [node] is one of the rail's items.
  static bool Function(FocusNode node)? contains;

  /// Where focus was when it jumped into the rail, so Right comes back to it.
  static FocusNode? returnTo;

  /// Jumps into the rail, remembering [from] for the way back.
  static bool enterFrom(FocusNode? from) {
    final enter = TvRail.enter;
    if (enter == null) return false;
    final moved = enter();
    if (moved && from != null && contains?.call(from) != true) {
      returnTo = from;
    }
    return moved;
  }
}

/// D-pad focus movement for Android TV, on top of the reading-order policy:
///
///  * Left/right only move within the current row (items that overlap it
///    vertically), so a shelf never jumps to a card on another shelf.
///  * Left with nothing further left opens the side rail; right with nothing
///    further right stays put.
///  * Right from the rail goes back to where focus was before.
///  * Every move scrolls the new item to the middle of its scrollables, rather
///    than leaving it flush against the screen edge.
///
/// Up/down use the default behaviour.
class TvTraversalPolicy extends ReadingOrderTraversalPolicy {
  TvTraversalPolicy() : super(requestFocusCallback: _centerOnFocus);

  static void _centerOnFocus(
    FocusNode node, {
    ScrollPositionAlignmentPolicy? alignmentPolicy,
    double? alignment,
    Duration? duration,
    Curve? curve,
  }) {
    node.requestFocus();
    final context = node.context;
    var target = context?.findRenderObject();
    if (context == null || target == null) return;
    // Like Scrollable.ensureVisible (each scrollable centres the next-inner
    // one, ending with the item itself), but leaves page views alone:
    // centring a hero slide's button would drag the carousel part-way to the
    // next slide.
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null && target != null) {
      if (scrollable.widget.controller is! PageController) {
        scrollable.position.ensureVisible(
          target,
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      target = scrollable.context.findRenderObject();
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    if (currentNode is FocusScopeNode) {
      // Nothing focused yet (a page just opened): start at the top-left item
      // actually on screen, rather than the default's pick, which can be
      // scrolled off-screen.
      final first = _firstVisible(currentNode);
      if (first != null) {
        _centerOnFocus(first);
        return true;
      }
      return super.inDirection(currentNode, direction);
    }
    final horizontal = direction == TraversalDirection.left ||
        direction == TraversalDirection.right;
    if (!horizontal) return _vertical(currentNode, direction);
    final left = direction == TraversalDirection.left;

    if (!left && TvRail.contains?.call(currentNode) == true) {
      final back = TvRail.returnTo;
      TvRail.returnTo = null;
      if (back != null && back.context != null && back.canRequestFocus) {
        _centerOnFocus(back);
        return true;
      }
    }

    final scope = currentNode.nearestScope;
    if (scope == null) return super.inDirection(currentNode, direction);
    final from = currentNode.rect;
    final candidates = scope.traversalDescendants.where((node) {
      if (node == currentNode || node is FocusScopeNode) return false;
      // Skip containers wrapping the current item (e.g. the player's
      // full-screen key handler): they are "beside" everything.
      if (_wraps(node, currentNode)) return false;
      if (node.context == null || !node.canRequestFocus) return false;
      final r = node.rect;
      final sameRow = r.top < from.bottom && r.bottom > from.top;
      final onSide = left
          ? r.center.dx < from.center.dx
          : r.center.dx > from.center.dx;
      return sameRow && onSide;
    }).toList();

    if (candidates.isEmpty) {
      if (left && TvRail.enterFrom(currentNode)) return true;
      // Nothing that way in this row: pages without the shell rail (their
      // own sidebar sits elsewhere vertically) fall back to the default;
      // otherwise stay put rather than jumping to another row.
      if (left && TvRail.contains?.call(currentNode) != true) {
        return super.inDirection(currentNode, direction);
      }
      return true;
    }

    double gap(FocusNode node) => left
        ? from.left - node.rect.right
        : node.rect.left - from.right;
    candidates.sort((a, b) {
      final byGap = gap(a).compareTo(gap(b));
      if (byGap != 0) return byGap;
      return (a.rect.center.dy - from.center.dy)
          .abs()
          .compareTo((b.rect.center.dy - from.center.dy).abs());
    });
    _centerOnFocus(candidates.first);
    return true;
  }

  /// Whether [node] is a container around [current]: an ancestor in the focus
  /// tree, or a node whose area covers it (e.g. a full-screen Focus).
  static bool _wraps(FocusNode node, FocusNode current) {
    if (current.ancestors.contains(node)) return true;
    final r = node.rect;
    final c = current.rect;
    return r.left <= c.left &&
        r.top <= c.top &&
        r.right >= c.right &&
        r.bottom >= c.bottom;
  }

  static FocusNode? _firstVisible(FocusScopeNode scope) {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return null;
    final view = views.first;
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final visible = scope.traversalDescendants.where((node) {
      if (node is FocusScopeNode || node.context == null) return false;
      if (!node.canRequestFocus) return false;
      if (TvRail.contains?.call(node) == true) return false;
      return screen.overlaps(node.rect);
    }).toList()
      ..sort((a, b) {
        final byTop = a.rect.top.compareTo(b.rect.top);
        return byTop != 0 ? byTop : a.rect.left.compareTo(b.rect.left);
      });
    return visible.isEmpty ? null : visible.first;
  }

  /// Up/down: go to the nearest row above/below, and in it to the item most
  /// directly in line (largest horizontal overlap). The default picks by
  /// centre distance, so a small button inside a card (e.g. an episode's
  /// download icon) could win over the card itself. In the rail, up/down
  /// stays in the rail.
  bool _vertical(FocusNode currentNode, TraversalDirection direction) {
    final scope = currentNode.nearestScope;
    if (scope == null) return super.inDirection(currentNode, direction);
    final down = direction == TraversalDirection.down;
    final from = currentNode.rect;
    final inRail = TvRail.contains?.call(currentNode) == true;
    final candidates = scope.traversalDescendants.where((node) {
      if (node == currentNode || node is FocusScopeNode) return false;
      // Skip containers wrapping the current item (e.g. the player's
      // full-screen key handler): they are "beside" everything.
      if (_wraps(node, currentNode)) return false;
      if (node.context == null || !node.canRequestFocus) return false;
      if (inRail && TvRail.contains?.call(node) != true) return false;
      final r = node.rect;
      return down ? r.top >= from.bottom - 2 : r.bottom <= from.top + 2;
    }).toList();
    if (candidates.isEmpty) {
      // Nothing that way: stay put in the rail, otherwise let the default
      // policy try (it may still find something reachable).
      return inRail ? true : super.inDirection(currentNode, direction);
    }

    double gap(FocusNode node) =>
        down ? node.rect.top - from.bottom : from.top - node.rect.bottom;
    double overlap(FocusNode node) {
      final r = node.rect;
      final o = (r.right < from.right ? r.right : from.right) -
          (r.left > from.left ? r.left : from.left);
      return o > 0 ? o : 0;
    }

    // Prefer items in line with the current one (Android's "beam"), so a
    // small off-to-the-side target, like a shelf header's "View all" link
    // sitting just above the next shelf's cards, doesn't win over the card
    // straight below. Only when nothing lines up nearby, take the closest by
    // distance, weighting vertical distance like Android's FocusFinder.
    final nearest = candidates.map(gap).reduce((a, b) => a < b ? a : b);
    final inBeam = candidates.where((node) => overlap(node) > 0).toList();
    FocusNode target;
    if (inBeam.isNotEmpty) {
      final beamNearest = inBeam.map(gap).reduce((a, b) => a < b ? a : b);
      if (beamNearest <= nearest + 120) {
        final row = inBeam
            .where((node) => gap(node) <= beamNearest + 24)
            .toList()
          ..sort((a, b) => overlap(b).compareTo(overlap(a)));
        _centerOnFocus(row.first);
        return true;
      }
    }
    double score(FocusNode node) {
      final major = gap(node).clamp(0, double.infinity).toDouble();
      final minor = (node.rect.center.dx - from.center.dx).abs();
      return 13 * major * major + minor * minor;
    }
    target = candidates.reduce((a, b) => score(a) <= score(b) ? a : b);
    _centerOnFocus(target);
    return true;
  }
}
