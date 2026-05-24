import 'package:flutter/material.dart';

import '../../models/layer.dart';

/// Renders a [TextLayer]'s content inside its bounding box.
///
/// Outline mode stacks two [Text] passes — the bottom one stroked, the top
/// one filled — because Flutter has no native stroked-text primitive.
class TextRenderer extends StatelessWidget {
  const TextRenderer({
    super.key,
    required this.layer,
    required this.canvasSize,
  });

  final TextLayer layer;

  /// Used to convert the layer's *fractional* [TextLayer.fontSize] into a
  /// pixel value. Sizing off the canvas height keeps captions visually
  /// consistent across aspect ratios.
  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    if (layer.text.trim().isEmpty) return const SizedBox.shrink();
    final double fontSize = layer.fontSize * canvasSize.height;
    final TextStyle baseStyle = TextStyle(
      fontFamily: layer.fontFamily,
      fontSize: fontSize,
      fontWeight: layer.bold ? FontWeight.w900 : FontWeight.w500,
      fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: layer.outlined ? 1.2 : 0,
      height: 1.1,
    );

    final TextAlign textAlign = layer.align.toFlutter();

    final Widget fill = Text(
      layer.text,
      textAlign: textAlign,
      style: baseStyle.copyWith(color: layer.color),
    );

    if (!layer.outlined) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: _alignmentFor(textAlign),
        child: fill,
      );
    }

    // Outline contrasts with the fill so it stays legible on any background.
    final Color outlineColor =
        layer.color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    final double strokeWidth = (fontSize * 0.08).clamp(2.0, 8.0);

    final Widget stroked = Stack(
      alignment: _alignmentFor(textAlign),
      children: <Widget>[
        Text(
          layer.text,
          textAlign: textAlign,
          style: baseStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = outlineColor,
          ),
        ),
        fill,
      ],
    );

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: _alignmentFor(textAlign),
      child: stroked,
    );
  }

  Alignment _alignmentFor(TextAlign align) {
    switch (align) {
      case TextAlign.left:
      case TextAlign.start:
        return Alignment.centerLeft;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.centerRight;
      case TextAlign.center:
      case TextAlign.justify:
        return Alignment.center;
    }
  }
}
