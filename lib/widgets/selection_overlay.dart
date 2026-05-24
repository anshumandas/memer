import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/layer.dart';
import '../models/meme_controller.dart';

/// Sits on top of [MemeCanvas] (deliberately *outside* the RepaintBoundary)
/// and provides every direct-manipulation affordance:
///
///   * Tap to select the topmost layer under the pointer.
///   * Drag the selected layer's body to move it.
///   * Drag a corner handle to resize.
///   * Drag the rotate handle above the top edge to rotate.
///   * For [CalloutLayer], drag the small circular indicator to repoint the
///     tail target.
///
/// All gestures are tracked with **absolute** start-position snapshots
/// (captured `onPanStart`) and then re-applied on every `onPanUpdate` using
/// `globalPosition`. This avoids the drift you get when accumulating
/// per-tick deltas against a closure-captured (potentially stale) layer.
class LayerSelectionOverlay extends StatefulWidget {
  const LayerSelectionOverlay({super.key, required this.controller});

  final MemeController controller;

  @override
  State<LayerSelectionOverlay> createState() => _LayerSelectionOverlayState();
}

class _LayerSelectionOverlayState extends State<LayerSelectionOverlay> {
  final GlobalKey _overlayKey = GlobalKey();

  // Snapshots captured at onPanStart for the in-progress gesture. Each is
  // reset on pan end so the next gesture starts clean.
  Offset? _moveStartPointerCanvas; // pointer position in canvas-local px
  Offset? _moveStartLayerPos; // layer fractional position when grab began

  Offset? _resizeStartPointerCanvas;
  Offset? _resizeStartLayerPos;
  Size? _resizeStartLayerSize;
  double _resizeStartLayerRotation = 0;
  ({double dxSign, double dySign})? _resizeCorner;

  double? _rotateStartAngle;
  double _rotateStartLayerRotation = 0;

  Offset? _tailStartPointerCanvas;
  Offset? _tailStartTarget;

  /// Convert a global pointer position into canvas-local pixels using the
  /// overlay's own RenderBox. The overlay always exactly matches the canvas
  /// size, so a position relative to it == a position on the canvas.
  Offset? _toCanvas(Offset global) {
    final BuildContext? ctx = _overlayKey.currentContext;
    if (ctx == null) return null;
    final RenderObject? ro = ctx.findRenderObject();
    if (ro is! RenderBox) return null;
    return ro.globalToLocal(global);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, _) {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size canvasSize = constraints.biggest;
            final Layer? selected = widget.controller.selectedLayer;
            return Stack(
              key: _overlayKey,
              fit: StackFit.expand,
              children: <Widget>[
                // Bottom layer: a transparent tap-target that picks
                // whichever visible layer sits under the pointer.
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
    // (unrotated) bounding rect contains the point.
    final List<Layer> layers = widget.controller.config.layers;
    for (int i = layers.length - 1; i >= 0; i--) {
      final Layer l = layers[i];
      if (!l.visible || l.locked) continue;
      if (l is BackgroundLayer) continue;
      if (_layerRectFractional(l).contains(frac)) {
        widget.controller.selectLayer(l.id);
        return;
      }
    }
    // Fall back to the background (always selectable) or clear.
    final Layer? bg = layers.isNotEmpty ? layers.first : null;
    if (bg is BackgroundLayer && !bg.locked) {
      widget.controller.selectLayer(bg.id);
    } else {
      widget.controller.clearSelection();
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
            // Dashed bounding box (visual only).
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
                  onPanStart: (DragStartDetails d) {
                    final Offset? p = _toCanvas(d.globalPosition);
                    if (p == null) return;
                    _moveStartPointerCanvas = p;
                    _moveStartLayerPos =
                        widget.controller.selectedLayer?.position;
                  },
                  onPanUpdate: (DragUpdateDetails d) =>
                      _onMoveUpdate(d.globalPosition, canvasSize),
                  onPanEnd: (_) {
                    _moveStartPointerCanvas = null;
                    _moveStartLayerPos = null;
                  },
                ),
              ),
            // 4 corner resize handles.
            for (final ({double dxSign, double dySign}) corner
                in const <({double dxSign, double dySign})>[
              (dxSign: -1, dySign: -1),
              (dxSign: 1, dySign: -1),
              (dxSign: -1, dySign: 1),
              (dxSign: 1, dySign: 1),
            ])
              _CornerHandle(
                color: scheme.primary,
                left: corner.dxSign < 0 ? -8 : null,
                right: corner.dxSign > 0 ? -8 : null,
                top: corner.dySign < 0 ? -8 : null,
                bottom: corner.dySign > 0 ? -8 : null,
                onStart: (DragStartDetails d) {
                  final Offset? p = _toCanvas(d.globalPosition);
                  if (p == null) return;
                  _resizeStartPointerCanvas = p;
                  final Layer? current = widget.controller.selectedLayer;
                  if (current == null) return;
                  _resizeStartLayerPos = current.position;
                  _resizeStartLayerSize = current.size;
                  _resizeStartLayerRotation = current.rotation;
                  _resizeCorner = corner;
                },
                onUpdate: (DragUpdateDetails d) =>
                    _onResizeUpdate(d.globalPosition, canvasSize),
                onEnd: () {
                  _resizeStartPointerCanvas = null;
                  _resizeStartLayerPos = null;
                  _resizeStartLayerSize = null;
                  _resizeCorner = null;
                },
              ),
            // Rotate handle above the top edge.
            Positioned(
              top: -32,
              left: w / 2 - 12,
              child: _RotateHandle(
                color: scheme.primary,
                onStart: (DragStartDetails d) {
                  final Offset? p = _toCanvas(d.globalPosition);
                  if (p == null) return;
                  final Offset center = Offset(cx, cy);
                  _rotateStartAngle =
                      math.atan2(p.dy - center.dy, p.dx - center.dx);
                  _rotateStartLayerRotation =
                      widget.controller.selectedLayer?.rotation ?? 0;
                },
                onUpdate: (DragUpdateDetails d) {
                  if (_rotateStartAngle == null) return;
                  final Offset? p = _toCanvas(d.globalPosition);
                  if (p == null) return;
                  final Offset center = Offset(cx, cy);
                  final double now =
                      math.atan2(p.dy - center.dy, p.dx - center.dx);
                  final double delta = now - _rotateStartAngle!;
                  widget.controller.rotateLayer(
                    layer.id,
                    _rotateStartLayerRotation + delta,
                  );
                },
                onEnd: () => _rotateStartAngle = null,
              ),
            ),
          ],
        ),
      ),
    );

    final List<Widget> widgets = <Widget>[rotatedHandles];

    if (layer is CalloutLayer && layer.showTail) {
      widgets.add(_TailTargetHandle(
        canvasSize: canvasSize,
        target: layer.tailTarget,
        color: scheme.tertiary,
        onStart: (DragStartDetails d) {
          final Offset? p = _toCanvas(d.globalPosition);
          if (p == null) return;
          _tailStartPointerCanvas = p;
          _tailStartTarget = layer.tailTarget;
        },
        onUpdate: (DragUpdateDetails d) {
          if (_tailStartPointerCanvas == null || _tailStartTarget == null) {
            return;
          }
          final Offset? p = _toCanvas(d.globalPosition);
          if (p == null) return;
          final Offset deltaPx = p - _tailStartPointerCanvas!;
          final Offset next = Offset(
            (_tailStartTarget!.dx + deltaPx.dx / canvasSize.width)
                .clamp(0.0, 1.0),
            (_tailStartTarget!.dy + deltaPx.dy / canvasSize.height)
                .clamp(0.0, 1.0),
          );
          widget.controller.updateLayer(
            layer.id,
            (Layer l) => (l as CalloutLayer).copyWith(tailTarget: next),
          );
        },
        onEnd: () {
          _tailStartPointerCanvas = null;
          _tailStartTarget = null;
        },
      ));
    }

    return widgets;
  }

  // ---------------------------------------------------------- gesture math

  void _onMoveUpdate(Offset globalPointer, Size canvasSize) {
    if (_moveStartPointerCanvas == null || _moveStartLayerPos == null) return;
    final Offset? now = _toCanvas(globalPointer);
    if (now == null) return;
    final Offset deltaPx = now - _moveStartPointerCanvas!;
    final Offset target = Offset(
      _moveStartLayerPos!.dx + deltaPx.dx / canvasSize.width,
      _moveStartLayerPos!.dy + deltaPx.dy / canvasSize.height,
    );
    final Layer? current = widget.controller.selectedLayer;
    if (current == null) return;
    widget.controller.moveLayer(current.id, target);
  }

  void _onResizeUpdate(Offset globalPointer, Size canvasSize) {
    if (_resizeStartPointerCanvas == null ||
        _resizeStartLayerPos == null ||
        _resizeStartLayerSize == null ||
        _resizeCorner == null) {
      return;
    }
    final Offset? now = _toCanvas(globalPointer);
    if (now == null) return;
    final Offset deltaPx = now - _resizeStartPointerCanvas!;

    // Project the canvas-space delta back into the layer's own (rotated) frame.
    final double c = math.cos(-_resizeStartLayerRotation);
    final double s = math.sin(-_resizeStartLayerRotation);
    final Offset local = Offset(
      deltaPx.dx * c - deltaPx.dy * s,
      deltaPx.dx * s + deltaPx.dy * c,
    );

    final double dxSign = _resizeCorner!.dxSign;
    final double dySign = _resizeCorner!.dySign;

    final double newW =
        (_resizeStartLayerSize!.width + (local.dx / canvasSize.width) * dxSign)
            .clamp(0.04, 1.0);
    final double newH = (_resizeStartLayerSize!.height +
            (local.dy / canvasSize.height) * dySign)
        .clamp(0.04, 1.0);

    // The opposite corner stays anchored; the centre shifts by half of the
    // size delta (in the rotated frame), rotated back into canvas space.
    final double dxFrac = (newW - _resizeStartLayerSize!.width) * 0.5 * dxSign;
    final double dyFrac = (newH - _resizeStartLayerSize!.height) * 0.5 * dySign;
    final double rc = math.cos(_resizeStartLayerRotation);
    final double rs = math.sin(_resizeStartLayerRotation);
    final Offset shiftCanvas = Offset(
      dxFrac * rc - dyFrac * rs,
      dxFrac * rs + dyFrac * rc,
    );

    final Offset newPos = Offset(
      (_resizeStartLayerPos!.dx + shiftCanvas.dx).clamp(0.0, 1.0),
      (_resizeStartLayerPos!.dy + shiftCanvas.dy).clamp(0.0, 1.0),
    );

    final Layer? current = widget.controller.selectedLayer;
    if (current == null) return;
    widget.controller.updateLayer(
      current.id,
      (Layer l) => l.copyWithBase(position: newPos, size: Size(newW, newH)),
    );
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
    if (dist == 0) return;
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
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.left,
    this.right,
    this.top,
    this.bottom,
  });

  final Color color;
  final ValueChanged<DragStartDetails> onStart;
  final ValueChanged<DragUpdateDetails> onUpdate;
  final VoidCallback onEnd;
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
        onPanStart: onStart,
        onPanUpdate: onUpdate,
        onPanEnd: (_) => onEnd(),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpLeftDownRight,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: color, width: 2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
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
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final Color color;
  final ValueChanged<DragStartDetails> onStart;
  final ValueChanged<DragUpdateDetails> onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: onStart,
      onPanUpdate: onUpdate,
      onPanEnd: (_) => onEnd(),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
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
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final Size canvasSize;
  final Offset target;
  final Color color;
  final ValueChanged<DragStartDetails> onStart;
  final ValueChanged<DragUpdateDetails> onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    const double r = 20;
    return Positioned(
      left: target.dx * canvasSize.width - r / 2,
      top: target.dy * canvasSize.height - r / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: onStart,
        onPanUpdate: onUpdate,
        onPanEnd: (_) => onEnd(),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Container(
            width: r,
            height: r,
            decoration: BoxDecoration(
              color: color.withOpacity(0.85),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
