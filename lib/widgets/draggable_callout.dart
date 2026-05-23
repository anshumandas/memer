import 'package:flutter/material.dart';

import '../models/callout.dart';
import '../models/meme_controller.dart';
import 'callout_bubble.dart';

/// Wraps a [CalloutBubble] with tap-to-select and drag-to-move behaviour,
/// used only inside the interactive editor (never in the export canvas).
class DraggableCallout extends StatefulWidget {
  const DraggableCallout({
    super.key,
    required this.callout,
    required this.controller,
    required this.canvasSize,
    required this.scale,
    required this.selected,
  });

  final Callout callout;
  final MemeController controller;
  final Size canvasSize;
  final double scale;
  final bool selected;

  @override
  State<DraggableCallout> createState() => _DraggableCalloutState();
}

class _DraggableCalloutState extends State<DraggableCallout> {
  Offset _liveFraction = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.controller.selectCallout(widget.callout.id),
      onPanStart: (_) {
        widget.controller.selectCallout(widget.callout.id);
        _liveFraction = widget.callout.position;
      },
      onPanUpdate: (DragUpdateDetails d) {
        final double w = widget.canvasSize.width;
        final double h = widget.canvasSize.height;
        if (w == 0 || h == 0) return;
        _liveFraction += Offset(d.delta.dx / w, d.delta.dy / h);
        widget.controller.moveCallout(widget.callout.id, _liveFraction);
      },
      child: CalloutBubble(
        callout: widget.callout,
        scale: widget.scale,
        selected: widget.selected,
      ),
    );
  }
}
