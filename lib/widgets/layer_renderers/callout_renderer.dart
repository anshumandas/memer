import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/layer.dart';

/// Renders a [CalloutLayer]: bubble body + optional tail that points at the
/// layer's [CalloutLayer.tailTarget].
///
/// The renderer needs the *canvas* size, not just the bubble's local size,
/// because the tail target is stored in fractional canvas coordinates. We
/// translate that target into the bubble's local painting space here.
class CalloutRenderer extends StatelessWidget {
  const CalloutRenderer({
    super.key,
    required this.layer,
    required this.canvasSize,
  });

  final CalloutLayer layer;
  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    final double bubbleW = layer.size.width * canvasSize.width;
    final double bubbleH = layer.size.height * canvasSize.height;
    final double centerX = layer.position.dx * canvasSize.width;
    final double centerY = layer.position.dy * canvasSize.height;
    final Offset bubbleCenter = Offset(centerX, centerY);

    final Offset targetCanvas = Offset(
      layer.tailTarget.dx * canvasSize.width,
      layer.tailTarget.dy * canvasSize.height,
    );
    // Translate the tail target into the bubble's local coordinate space
    // (origin = bubble's top-left, axes in pixels).
    final Offset targetLocal = targetCanvas -
        Offset(bubbleCenter.dx - bubbleW / 2, bubbleCenter.dy - bubbleH / 2);

    final double fontSize = layer.fontSize * canvasSize.height;

    return CustomPaint(
      painter: _CalloutPainter(
        shape: layer.shape,
        fill: layer.fillColor,
        border: layer.borderColor,
        borderWidth: layer.borderWidth,
        showTail: layer.showTail,
        tailTargetLocal: targetLocal,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: bubbleW * 0.08,
          vertical: bubbleH * 0.12,
        ),
        child: Center(
          child: Text(
            layer.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: layer.fontFamily,
              fontSize: fontSize,
              color: layer.textColor,
              fontWeight: layer.bold ? FontWeight.w700 : FontWeight.w500,
              fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}

class _CalloutPainter extends CustomPainter {
  _CalloutPainter({
    required this.shape,
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.showTail,
    required this.tailTargetLocal,
  });

  final CalloutKind shape;
  final Color fill;
  final Color border;
  final double borderWidth;
  final bool showTail;

  /// Tail target expressed in local pixel coordinates (origin at top-left
  /// of the painted rect).
  final Offset tailTargetLocal;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect body = Offset.zero & size;
    final Path bodyPath = _bodyPathFor(shape, body);

    Path fullPath = Path.from(bodyPath);
    if (showTail && shape != CalloutKind.rectangle) {
      final Path? tail = _tailPath(body, tailTargetLocal, shape);
      if (tail != null) {
        fullPath = Path.combine(PathOperation.union, fullPath, tail);
      }
    }

    // Soft shadow so the bubble lifts off the underlying layers.
    canvas.drawShadow(fullPath, Colors.black.withOpacity(0.35), 4, false);

    final Paint fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill;
    canvas.drawPath(fullPath, fillPaint);

    if (borderWidth > 0) {
      final Paint stroke = Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(fullPath, stroke);
    }

    // Thought-cloud bubbles get a trail of shrinking circles between the
    // body and the tail target.
    if (showTail && shape == CalloutKind.thoughtCloud) {
      _drawThoughtTrail(
          canvas,
          body,
          tailTargetLocal,
          fillPaint,
          borderWidth > 0
              ? (Paint()
                ..color = border
                ..style = PaintingStyle.stroke
                ..strokeWidth = borderWidth)
              : null);
    }
  }

  // -------------------------------------------------- bubble body geometry

  Path _bodyPathFor(CalloutKind kind, Rect r) {
    switch (kind) {
      case CalloutKind.rectangle:
        return Path()..addRect(r);
      case CalloutKind.speechSharp:
        return Path()..addRect(r);
      case CalloutKind.oval:
        return Path()..addOval(r);
      case CalloutKind.speechRound:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            r,
            Radius.circular(math.min(r.width, r.height) * 0.22),
          ));
      case CalloutKind.thoughtCloud:
        // A thought cloud is a chain of overlapping circles around the bubble
        // perimeter, unioned into one path.
        return _cloudPath(r, 14, irregular: false);
      case CalloutKind.scallop:
        return _cloudPath(r, 22, irregular: true);
    }
  }

  Path _cloudPath(Rect r, int bumps, {required bool irregular}) {
    final Path p = Path();
    final double cx = r.center.dx;
    final double cy = r.center.dy;
    final double rx = r.width / 2 - 2;
    final double ry = r.height / 2 - 2;
    final double bumpR = math.min(rx, ry) * (irregular ? 0.18 : 0.22);

    // Inner ellipse fills the middle so the cloud isn't hollow.
    p.addOval(Rect.fromCenter(
      center: r.center,
      width: r.width * 0.78,
      height: r.height * 0.74,
    ));

    for (int i = 0; i < bumps; i++) {
      final double t = i / bumps * 2 * math.pi;
      final double wobble = irregular ? math.sin(t * 3) * 4 : 0;
      final double bx = cx + math.cos(t) * (rx - bumpR + wobble);
      final double by = cy + math.sin(t) * (ry - bumpR + wobble);
      p.addOval(Rect.fromCircle(center: Offset(bx, by), radius: bumpR));
    }
    return p;
  }

  // -------------------------------------------------------------- tail

  /// Returns a triangular tail path whose tip sits at [targetLocal] and whose
  /// base spans a short segment on the closest body edge. Returns null when
  /// the target is inside the bubble (no tail to draw).
  Path? _tailPath(Rect body, Offset targetLocal, CalloutKind kind) {
    // If the target falls inside the bubble, skip the tail.
    if (body.inflate(2).contains(targetLocal)) return null;

    // Find the closest point on the body rect's perimeter to the target.
    final double clampedX = targetLocal.dx.clamp(body.left, body.right);
    final double clampedY = targetLocal.dy.clamp(body.top, body.bottom);
    final double dxOut = (targetLocal.dx - clampedX).abs();
    final double dyOut = (targetLocal.dy - clampedY).abs();
    // Choose which edge to anchor on by which axis has the larger overshoot.
    final bool anchorVertical = dxOut > dyOut;
    Offset anchorOnRect;
    Offset baseAxis; // along-edge unit vector
    if (anchorVertical) {
      final double x = targetLocal.dx < body.center.dx ? body.left : body.right;
      anchorOnRect = Offset(x, clampedY);
      baseAxis = const Offset(0, 1);
    } else {
      final double y = targetLocal.dy < body.center.dy ? body.top : body.bottom;
      anchorOnRect = Offset(clampedX, y);
      baseAxis = const Offset(1, 0);
    }

    final double baseHalfWidth = math.min(body.width, body.height) *
        (kind == CalloutKind.speechSharp ? 0.08 : 0.12);
    final Offset baseA = anchorOnRect + baseAxis * baseHalfWidth;
    final Offset baseB = anchorOnRect - baseAxis * baseHalfWidth;
    return Path()
      ..moveTo(baseA.dx, baseA.dy)
      ..lineTo(targetLocal.dx, targetLocal.dy)
      ..lineTo(baseB.dx, baseB.dy)
      ..close();
  }

  void _drawThoughtTrail(
    Canvas canvas,
    Rect body,
    Offset target,
    Paint fillPaint,
    Paint? strokePaint,
  ) {
    if (body.inflate(2).contains(target)) return;
    // Two shrinking circles between the bubble edge and the target.
    final Offset edge = Offset(
      target.dx.clamp(body.left, body.right),
      target.dy.clamp(body.top, body.bottom),
    );
    final Offset toTarget = target - edge;
    final double dist = toTarget.distance;
    if (dist < 6) return;
    for (int i = 1; i <= 2; i++) {
      final double t = i / 3.0;
      final Offset c = edge + toTarget * t;
      final double r = math.min(body.width, body.height) * (0.06 - i * 0.018);
      canvas.drawCircle(c, r, fillPaint);
      if (strokePaint != null) canvas.drawCircle(c, r, strokePaint);
    }
  }

  @override
  bool shouldRepaint(_CalloutPainter old) {
    return old.shape != shape ||
        old.fill != fill ||
        old.border != border ||
        old.borderWidth != borderWidth ||
        old.showTail != showTail ||
        old.tailTargetLocal != tailTargetLocal;
  }
}
