import 'package:flutter/widgets.dart';

/// Where the iPad share popover points. iPad requires an anchor rect for the
/// share sheet (share_plus fails without one); elsewhere it is ignored.
///
/// Anchors on [context]'s widget, or on the middle of it when that widget is
/// a whole screen.
Rect? shareOriginFor(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final screen = MediaQuery.maybeSizeOf(context);
  if (screen != null && rect.width * rect.height > screen.width * screen.height / 4) {
    return Rect.fromCenter(center: rect.center, width: 1, height: 1);
  }
  return rect;
}
