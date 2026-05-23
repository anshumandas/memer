import 'package:flutter/material.dart';

import '../models/callout.dart';

/// Renders a single speech-bubble callout: a rounded rectangle with an
/// optional triangular tail, sized to its text.
///
/// [scale] lets the bubble grow/shrink with the canvas so the on-screen
/// editor preview matches the high-resolution export exactly.
class CalloutBubble extends StatelessWidget {
  const CalloutBubble({
    super.key,
    required this.callout,
    this.scale = 1.0,
    this.selected = false,
  });

  final Callout callout;
  final double scale;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final double fontSize = callout.fontSize * scale;
    final double tailSize = fontSize * 0.9;
    final double padH = fontSize * 0.7;
    final double padV = fontSize * 0.45;
    final double radius = fontSize * 0.6;

    final bool tailOnTop = callout.tail == CalloutTail.topLeft ||
        callout.tail == CalloutTail.topRight;
    final bool hasTail = callout.tail != CalloutTail.none;

    final EdgeInsets padding = EdgeInsets.only(
      left: padH,
      right: padH,
      top: padV + (tailOnTop && hasTail ? tailSize : 0),
      bottom: padV + (!tailOnTop && hasTail ? tailSize : 0),
    );

    return CustomPaint(
      painter: _BubblePainter(
        color: callout.bubbleColor,
        tail: callout.tail,
        tailSize: tailSize,
        radius: radius,
        borderColor: selected
            ? Theme.of(context).colorScheme.primary
            : Colors.black.withOpacity(0.12),
        borderWidth: selected ? 2.5 : 1.0,
      ),
      child: Padding(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 220 * scale),
          child: Text(
            callout.text.isEmpty ? ' ' : callout.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: callout.textColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.color,
    required this.tail,
    required this.tailSize,
    required this.radius,
    required this.borderColor,
    required this.borderWidth,
  });

  final Color color;
  final CalloutTail tail;
  final double tailSize;
  final double radius;
  final Color borderColor;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final bool hasTail = tail != CalloutTail.none;
    final bool tailOnTop =
        tail == CalloutTail.topLeft || tail == CalloutTail.topRight;
    final bool tailOnLeft =
        tail == CalloutTail.topLeft || tail == CalloutTail.bottomLeft;

    // Body rectangle leaves room for the tail on the relevant side.
    final double top = hasTail && tailOnTop ? tailSize : 0;
    final double bottom =
        hasTail && !tailOnTop ? size.height - tailSize : size.height;
    final Rect body = Rect.fromLTRB(0, top, size.width, bottom);

    final RRect rrect = RRect.fromRectAndRadius(body, Radius.circular(radius));
    final Path path = Path()..addRRect(rrect);

    if (hasTail) {
      // Anchor the tail roughly a third in from the chosen side.
      final double anchorX = tailOnLeft ? size.width * 0.28 : size.width * 0.72;
      final double baseHalf = tailSize * 0.6;
      final Path tailPath = Path();
      if (tailOnTop) {
        tailPath
          ..moveTo(anchorX - baseHalf, body.top)
          ..lineTo(anchorX + baseHalf, body.top)
          ..lineTo(anchorX - baseHalf * 0.2, 0)
          ..close();
      } else {
        tailPath
          ..moveTo(anchorX - baseHalf, body.bottom)
          ..lineTo(anchorX + baseHalf, body.bottom)
          ..lineTo(anchorX - baseHalf * 0.2, size.height)
          ..close();
      }
      path.addPath(tailPath, Offset.zero);
    }

    // Soft drop shadow for separation from the background.
    canvas.drawShadow(path, Colors.black.withOpacity(0.4), 3, false);

    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fill);

    if (borderWidth > 0) {
      final Paint border = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, border);
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) {
    return old.color != color ||
        old.tail != tail ||
        old.tailSize != tailSize ||
        old.radius != radius ||
        old.borderColor != borderColor ||
        old.borderWidth != borderWidth;
  }
}
