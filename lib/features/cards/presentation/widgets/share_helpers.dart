import 'package:flutter/widgets.dart';

/// Anchor rect for the iPad share popover, from the tapped widget.
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
