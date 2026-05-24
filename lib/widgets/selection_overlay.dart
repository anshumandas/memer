import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/layer.dart';
import '../models/meme_controller.dart';

/// Sits on top of [MemeCanvas] (deliberately *outside* the RepaintBoundary)
/// and provides every direct-manipulation affordance:
///
///   * Tap to select the topmost layer under the pointer (or clear selection
///     by tapping the canvas chrome).
///   * Drag the selected layer's body to move it.
///   * Drag a corner handle to resize. For raster images this is free-form;
///     aspect ratio can be regained from the inspector.
///   * Drag the rotate handle above the top edge to rotate.
///   * For [CalloutLayer], drag the small circular indicator to repoint the
///     tail target.
///
/// The overlay deliberately lives in canvas-local fractional space — all
/// drag deltas are divided by the canvas's on-screen size so the model
/// stays resolution-independent (and the export keeps matching the preview).
class LayerSelectionOverlay extends StatelessWidget {
  const LayerSelectionOverlay({super.key, required this.controller});

  final MemeController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size canvasSize = constraints.biggest;
        final Layer? selected = controller.selectedLayer;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Bottom layer: a transparent tap-target that picks whichever
            // visible layer sits under the pointer. translucent so we keep
            // receiving pointer events but don't paint anything.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (TapDownDetails d) =>
                    _selectAt(d.localPosition, canvasSize),
              ),
            ),
            if (selected != null && selected is! BackgroundLayer)
              ..._buildHandlesFor(context, selected, canvasSize),
          ],
        );
      },
    );
  }

  // -------------------------------------------------------------- selection

  void _selectAt(Offset localPx, Size canvasSize) {
    final Offset frac = Offset(
      localPx.dx / canvasSize.width,
      localPx.dy / canvasSize.height,
    );
    // Walk top-down (last drawn first) and pick the first layer whose
    // (unrotated) bounding rect contains the point. Locked & invisible
    // layers don't accept selection.
    for (int i = controller.config.layers.length - 1; i >= 0; i--) {
      final Layer l = controller.config.layers[i];
      if (!l.visible || l.locked) continue;
      if (l is BackgroundLayer) {
        // Background is the last-resort hit; only consider it after every
        // other layer has been checked.
        continue;
      }
      if (_layerRectFractional(l).contains(frac)) {
        controller.selectLayer(l.id);
        return;
      }
    }
    // Nothing else hit — fall back to the background (always selectable
    // when present) or clear the selection.
    final Layer? bg = controller.config.layers.isNotEmpty
        ? controller.config.layers.first
        : null;
    if (bg is BackgroundLayer && !bg.locked) {
      controller.selectLayer(bg.id);
    } else {
      controller.clearSelection();
    }
  }

  Rect _layerRectFractional(Layer l) {
    return Rect.fromCenter(
      center: l.position,
      width: l.size.width,
      height: l.size.height,
    );
  }

  // ------------------------------------------------------------- handles

  List<Widget> _buildHandlesFor(
      BuildContext context, Layer layer, Size canvasSize) {
    final double w = layer.size.width * canvasSize.width;
    final double h = layer.size.height * canvasSize.height;
    final double cx = layer.position.dx * canvasSize.width;
    final double cy = layer.position.dy * canvasSize.height;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    // We build a single rotated layer composed of:
    //   - selection box + drag-to-move
    //   - 4 corner resize handles
    //   - 1 rotate handle above top edge
    // Wrapping all of them in one Transform.rotate keeps them visually pinned
    // to the layer even when [layer.rotation] is non-zero.
    final Widget rotatedHandles = Positioned(
      left: cx - w / 2,
      top: cy - h / 2,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: layer.rotation,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: <Widget>[
            // Dashed bounding box.
            IgnorePointer(
              child: CustomPaint(
                painter: _SelectionBoxPainter(color: scheme.primary),
              ),
            ),
            // Drag-anywhere-to-move.
            if (!layer.locked)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: (DragUpdateDetails d) {
                    final Offset frac = Offset(
                      d.delta.dx / canvasSize.width,
                      d.delta.dy / canvasSize.height,
                    );
                    controller.moveLayer(
                      layer.id,
                      Offset(
                        layer.position.dx + frac.dx,
                        layer.position.dy + frac.dy,
                      ),
                    );
                  },
                ),
              ),
            // 4 corner resize handles. Each (dxSign, dySign) tells _resize
            // which corner this handle is and which direction to grow.
            for (final (double dxSign, double dySign) corner
                in const <(double, double)>[
              (-1, -1),
              (1, -1),
              (-1, 1),
              (1, 1),
            ])
              _CornerHandle(
                color: scheme.primary,
                left: corner.$1 < 0 ? -8 : null,
                right: corner.$1 > 0 ? -8 : null,
                top: corner.$2 < 0 ? -8 : null,
                bottom: corner.$2 > 0 ? -8 : null,
                onDrag: (DragUpdateDetails d) =>
                    _resize(layer, canvasSize, corner.$1, corner.$2, d.delta),
              ),
            // Rotate handle above the top edge.
            Positioned(
              top: -32,
              left: w / 2 - 12,
              child: _RotateHandle(
                color: scheme.primary,
                onDrag: (Offset globalDelta) =>
                    _rotate(layer, canvasSize, globalDelta),
                centerCanvas: Offset(cx, cy),
                getRenderBox: () =>
                    null, // overlay coords; we use deltas directly
              ),
            ),
          ],
        ),
      ),
    );

    final List<Widget> widgets = <Widget>[rotatedHandles];

    // Callouts get a separate (non-rotated) draggable indicator at their
    // tail target so the user can re-aim the tail without first moving the
    // bubble.
    if (layer is CalloutLayer && layer.showTail) {
      widgets.add(_TailTargetHandle(
        canvasSize: canvasSize,
        target: layer.tailTarget,
        color: scheme.tertiary,
        onDrag: (Offset deltaPx) {
          final Offset next = Offset(
            (layer.tailTarget.dx + deltaPx.dx / canvasSize.width)
                .clamp(0.0, 1.0),
            (layer.tailTarget.dy + deltaPx.dy / canvasSize.height)
                .clamp(0.0, 1.0),
          );
          controller.updateLayer(
            layer.id,
            (Layer l) => (l as CalloutLayer).copyWith(tailTarget: next),
          );
        },
      ));
    }

    return widgets;
  }

  // ---------------------------------------------------------- gesture math

  void _resize(Layer layer, Size canvasSize, double dxSign, double dySign,
      Offset deltaPx) {
    // Local delta (in the layer's own rotated frame) is screen delta rotated
    // by the inverse layer rotation.
    final double c = math.cos(-layer.rotation);
    final double s = math.sin(-layer.rotation);
    final Offset local = Offset(
      deltaPx.dx * c - deltaPx.dy * s,
      deltaPx.dx * s + deltaPx.dy * c,
    );

    // Pulling a corner outward = grow; we keep the *opposite* corner anchored.
    final double newW =
        (layer.size.width + (local.dx / canvasSize.width) * dxSign)
            .clamp(0.04, 1.0);
    final double newH =
        (layer.size.height + (local.dy / canvasSize.height) * dySign)
            .clamp(0.04, 1.0);

    // Position shifts by half the size change (in the rotated frame) so the
    // anchored corner stays still.
    final double dxFrac = (newW - layer.size.width) * 0.5 * dxSign;
    final double dyFrac = (newH - layer.size.height) * 0.5 * dySign;
    final Offset shiftLocal = Offset(dxFrac, dyFrac);

    // Rotate the shift back into canvas-aligned coordinates.
    final double rc = math.cos(layer.rotation);
    final double rs = math.sin(layer.rotation);
    final Offset shiftCanvas = Offset(
      shiftLocal.dx * rc - shiftLocal.dy * rs,
      shiftLocal.dx * rs + shiftLocal.dy * rc,
    );

    final Offset newPos = Offset(
      (layer.position.dx + shiftCanvas.dx).clamp(0.0, 1.0),
      (layer.position.dy + shiftCanvas.dy).clamp(0.0, 1.0),
    );

    controller.updateLayer(
      layer.id,
      (Layer l) => l.copyWithBase(
        position: newPos,
        size: Size(newW, newH),
      ),
    );
  }

  void _rotate(Layer layer, Size canvasSize, Offset deltaPx) {
    // Treat the screen delta as an angular nudge proportional to the bubble
    // size. This avoids the need to know the global pointer position — works
    // well enough for desktop and touch.
    final double scale = math.max(canvasSize.width, canvasSize.height);
    final double delta = deltaPx.dx / scale * math.pi; // ~180° per canvas-width
    controller.rotateLayer(layer.id, layer.rotation + delta);
  }
}

// ============================================================ handle widgets

class _SelectionBoxPainter extends CustomPainter {
  _SelectionBoxPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    // Simple dashed rectangle.
    const double dash = 6;
    const double gap = 4;
    final Path path = Path();
    _dashedLine(path, Offset.zero, Offset(size.width, 0), dash, gap);
    _dashedLine(path, Offset(size.width, 0), Offset(size.width, size.height),
        dash, gap);
    _dashedLine(path, Offset(size.width, size.height), Offset(0, size.height),
        dash, gap);
    _dashedLine(path, Offset(0, size.height), Offset.zero, dash, gap);
    canvas.drawPath(path, p);
  }

  void _dashedLine(Path path, Offset a, Offset b, double dash, double gap) {
    final double dist = (b - a).distance;
    final Offset dir = (b - a) / dist;
    double t = 0;
    while (t < dist) {
      final double next = math.min(t + dash, dist);
      path.moveTo(a.dx + dir.dx * t, a.dy + dir.dy * t);
      path.lineTo(a.dx + dir.dx * next, a.dy + dir.dy * next);
      t = next + gap;
    }
  }

  @override
  bool shouldRepaint(_SelectionBoxPainter old) => old.color != color;
}

class _CornerHandle extends StatelessWidget {
  const _CornerHandle({
    required this.color,
    required this.onDrag,
    this.left,
    this.right,
    this.top,
    this.bottom,
  });

  final Color color;
  final ValueChanged<DragUpdateDetails> onDrag;
  final double? left;
  final double? right;
  final double? top;
  final double? bottom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: onDrag,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.rectangle,
              border: Border.all(color: color, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _RotateHandle extends StatelessWidget {
  const _RotateHandle({
    required this.color,
    required this.onDrag,
    required this.centerCanvas,
    required this.getRenderBox,
  });

  final Color color;
  final ValueChanged<Offset> onDrag;
  final Offset centerCanvas;
  // Reserved for a future "absolute pointer angle" rotate; the simple
  // delta-based rotate doesn't need it.
  final RenderBox? Function() getRenderBox;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (DragUpdateDetails d) => onDrag(d.delta),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(Icons.refresh, size: 16, color: color),
        ),
      ),
    );
  }
}

class _TailTargetHandle extends StatelessWidget {
  const _TailTargetHandle({
    required this.canvasSize,
    required this.target,
    required this.color,
    required this.onDrag,
  });

  final Size canvasSize;
  final Offset target;
  final Color color;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    const double r = 18;
    return Positioned(
      left: target.dx * canvasSize.width - r / 2,
      top: target.dy * canvasSize.height - r / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (DragUpdateDetails d) => onDrag(d.delta),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Container(
            width: r,
            height: r,
            decoration: BoxDecoration(
              color: color.withOpacity(0.85),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}
