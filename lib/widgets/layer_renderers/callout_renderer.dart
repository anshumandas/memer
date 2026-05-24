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

    final Offset targetCanvas = Offset(
      layer.tailTarget.dx * canvasSize.width,
      layer.tailTarget.dy * canvasSize.height,
    );
    // Translate the tail target into the bubble's local coordinate space
    // (origin = bubble's top-left, axes in pixels).
    final Offset targetLocal =
        targetCanvas - Offset(centerX - bubbleW / 2, centerY - bubbleH / 2);

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
        // Leave a bigger horizontal pad for oval/cloud where the corners
        // round in further; sufficient for the others too.
        padding: EdgeInsets.symmetric(
          horizontal: bubbleW * 0.10,
          vertical: bubbleH * 0.14,
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

    // For shapes whose perimeter is *complex* (cloud, scallop, oval) we draw
    // the tail as a separate sub-path UNIONED in via Path.combine so the
    // outline stays one continuous stroke. For shapes with a flat perimeter
    // (rounded rect, sharp rect) the same approach is used; the union is
    // robust enough and removes any visual seam at the tail base.
    Path fullPath = bodyPath;
    Path? tailOverlayPath; // for the trailing circles on a thought cloud

    if (showTail && shape != CalloutKind.rectangle) {
      if (shape == CalloutKind.thoughtCloud) {
        tailOverlayPath = _thoughtTrail(body, tailTargetLocal);
      } else {
        final Path? tail = _tailPath(body, tailTargetLocal, shape);
        if (tail != null) {
          fullPath = Path.combine(PathOperation.union, fullPath, tail);
        }
      }
    }

    // Soft shadow so the bubble lifts off the underlying layers.
    canvas.drawShadow(fullPath, Colors.black.withOpacity(0.32), 4, false);
    if (tailOverlayPath != null) {
      canvas.drawShadow(
          tailOverlayPath, Colors.black.withOpacity(0.32), 2, false);
    }

    final Paint fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(fullPath, fillPaint);
    if (tailOverlayPath != null) {
      canvas.drawPath(tailOverlayPath, fillPaint);
    }

    if (borderWidth > 0) {
      final Paint stroke = Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(fullPath, stroke);
      if (tailOverlayPath != null) {
        canvas.drawPath(tailOverlayPath, stroke);
      }
    }
  }

  // -------------------------------------------------- bubble body geometry

  Path _bodyPathFor(CalloutKind kind, Rect r) {
    switch (kind) {
      case CalloutKind.rectangle:
        return Path()..addRect(r);
      case CalloutKind.speechSharp:
        // A barely-rounded rect — corners are visible but not soft.
        return Path()
          ..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)));
      case CalloutKind.speechRound:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            r,
            Radius.circular(math.min(r.width, r.height) * 0.22),
          ));
      case CalloutKind.oval:
        return Path()..addOval(r);
      case CalloutKind.thoughtCloud:
        return _smoothCloudPath(r, bumps: 10);
      case CalloutKind.scallop:
        return _scallopedRectPath(r);
    }
  }

  /// Draws a fluffy cloud by walking around an inner ellipse and arcing
  /// outward between each step. Each segment is a circular arc, so adjacent
  /// bumps connect tangentially and the outline is smooth.
  Path _smoothCloudPath(Rect r, {required int bumps}) {
    final double cx = r.center.dx;
    final double cy = r.center.dy;
    // Inner ellipse the bumps are anchored to.
    final double baseRx = r.width / 2 * 0.86;
    final double baseRy = r.height / 2 * 0.86;
    final double bumpRadius =
        math.min(baseRx, baseRy) * (math.pi / bumps) * 1.05;

    final Path p = Path();
    for (int i = 0; i <= bumps; i++) {
      final double t = i / bumps * 2 * math.pi;
      final Offset pt =
          Offset(cx + math.cos(t) * baseRx, cy + math.sin(t) * baseRy);
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        // Arc outward: clockwise:false makes the bulge sit on the *outside*
        // of the ellipse (away from the center).
        p.arcToPoint(
          pt,
          radius: Radius.circular(bumpRadius),
          clockwise: false,
        );
      }
    }
    p.close();
    return p;
  }

  /// Rounded-rectangle whose edges are bumped outward with small semicircles.
  /// Bump count along each side is derived from edge length so the bumps
  /// stay roughly square regardless of aspect ratio.
  Path _scallopedRectPath(Rect r) {
    // Aim for ~0.12 of the shorter side per bump.
    final double s = math.min(r.width, r.height);
    final double targetBumpLen = s * 0.13;
    final int bumpsX = math.max(3, (r.width / targetBumpLen).round());
    final int bumpsY = math.max(3, (r.height / targetBumpLen).round());
    final double bumpW = r.width / bumpsX;
    final double bumpH = r.height / bumpsY;

    final Path p = Path();
    p.moveTo(r.left, r.top);
    // Top edge — bumps bulge UP (negative y).
    for (int i = 1; i <= bumpsX; i++) {
      p.arcToPoint(
        Offset(r.left + bumpW * i, r.top),
        radius: Radius.circular(bumpW / 2),
        clockwise: true,
      );
    }
    // Right edge — bumps bulge RIGHT.
    for (int i = 1; i <= bumpsY; i++) {
      p.arcToPoint(
        Offset(r.right, r.top + bumpH * i),
        radius: Radius.circular(bumpH / 2),
        clockwise: true,
      );
    }
    // Bottom edge — bumps bulge DOWN.
    for (int i = 1; i <= bumpsX; i++) {
      p.arcToPoint(
        Offset(r.right - bumpW * i, r.bottom),
        radius: Radius.circular(bumpW / 2),
        clockwise: true,
      );
    }
    // Left edge — bumps bulge LEFT, closing the path.
    for (int i = 1; i <= bumpsY; i++) {
      p.arcToPoint(
        Offset(r.left, r.bottom - bumpH * i),
        radius: Radius.circular(bumpH / 2),
        clockwise: true,
      );
    }
    p.close();
    return p;
  }

  // -------------------------------------------------------------- tail

  /// Returns a tail path whose tip sits at [targetLocal] and whose base sits
  /// against the body's perimeter. Returns null when the target falls inside
  /// the bubble (no tail to draw).
  ///
  /// The base is anchored on the nearest edge of the body's bounding rect
  /// for rectangular shapes, or on the ellipse perimeter for ovals — both
  /// approximations are visually fine because the shape outline is already
  /// close to its bounding rect.
  Path? _tailPath(Rect body, Offset targetLocal, CalloutKind kind) {
    // If the target is inside the body, skip the tail.
    if (body.deflate(2).contains(targetLocal)) return null;

    // Anchor point on the bubble perimeter facing the target.
    final Offset anchor = _perimeterAnchor(body, targetLocal, kind);

    // Direction from anchor to target.
    final Offset toTarget = targetLocal - anchor;
    final double dist = toTarget.distance;
    if (dist < 6) return null;

    // The tail base spans perpendicular to the anchor→target direction,
    // centred on the anchor. Width scales with bubble size and shape.
    final double baseHalf = math.min(body.width, body.height) *
        (kind == CalloutKind.speechSharp ? 0.08 : 0.11);
    final Offset perp = Offset(-toTarget.dy / dist, toTarget.dx / dist);
    final Offset baseA = anchor + perp * baseHalf;
    final Offset baseB = anchor - perp * baseHalf;

    final Path p = Path()..moveTo(baseA.dx, baseA.dy);

    if (kind == CalloutKind.speechSharp) {
      // Sharp triangle: straight lines to the tip and back.
      p.lineTo(targetLocal.dx, targetLocal.dy);
      p.lineTo(baseB.dx, baseB.dy);
    } else {
      // Smooth tail: gentle S-curve via quadratic beziers so the tail
      // doesn't look like a stuck-on shard. Control points pulled toward
      // the anchor side make the curve hug the bubble at the base.
      final Offset cp1 = Offset(
        anchor.dx + toTarget.dx * 0.35 + perp.dx * baseHalf * 0.4,
        anchor.dy + toTarget.dy * 0.35 + perp.dy * baseHalf * 0.4,
      );
      final Offset cp2 = Offset(
        anchor.dx + toTarget.dx * 0.35 - perp.dx * baseHalf * 0.4,
        anchor.dy + toTarget.dy * 0.35 - perp.dy * baseHalf * 0.4,
      );
      p.quadraticBezierTo(cp1.dx, cp1.dy, targetLocal.dx, targetLocal.dy);
      p.quadraticBezierTo(cp2.dx, cp2.dy, baseB.dx, baseB.dy);
    }
    p.close();
    return p;
  }

  /// Approximates the perimeter point of [body]'s shape closest to [target].
  /// Uses the ellipse formula for ovals/clouds and the rect clamp otherwise.
  Offset _perimeterAnchor(Rect body, Offset target, CalloutKind kind) {
    if (kind == CalloutKind.oval || kind == CalloutKind.thoughtCloud) {
      // Cast a ray from center to target; intersect with the ellipse.
      final Offset c = body.center;
      final double rx = body.width / 2;
      final double ry = body.height / 2;
      final double dx = target.dx - c.dx;
      final double dy = target.dy - c.dy;
      // Parameter t such that (t*dx/rx)^2 + (t*dy/ry)^2 = 1
      final double denom =
          math.sqrt((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry));
      if (denom == 0) return c;
      final double t = 1 / denom;
      return Offset(c.dx + dx * t, c.dy + dy * t);
    }
    // Default — rectangular shapes: clamp to the nearest edge.
    final double clampedX = target.dx.clamp(body.left, body.right);
    final double clampedY = target.dy.clamp(body.top, body.bottom);
    final double dxOut = (target.dx - clampedX).abs();
    final double dyOut = (target.dy - clampedY).abs();
    final bool anchorVertical = dxOut > dyOut;
    if (anchorVertical) {
      final double x = target.dx < body.center.dx ? body.left : body.right;
      return Offset(x, clampedY);
    } else {
      final double y = target.dy < body.center.dy ? body.top : body.bottom;
      return Offset(clampedX, y);
    }
  }

  /// Thought-cloud "tail" = a couple of shrinking bumps between the bubble
  /// edge and the target.
  Path _thoughtTrail(Rect body, Offset target) {
    final Path p = Path();
    if (body.deflate(2).contains(target)) return p;
    final Offset start =
        _perimeterAnchor(body, target, CalloutKind.thoughtCloud);
    final Offset toTarget = target - start;
    final double dist = toTarget.distance;
    if (dist < 8) return p;
    for (int i = 1; i <= 2; i++) {
      final double t = i / 3.0;
      final Offset c = start + toTarget * t;
      final double r = math.min(body.width, body.height) * (0.075 - i * 0.02);
      if (r <= 1) continue;
      p.addOval(Rect.fromCircle(center: c, radius: r));
    }
    return p;
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
