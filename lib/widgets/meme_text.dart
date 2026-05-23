import 'package:flutter/material.dart';

/// Classic meme caption: bold, upper-cased, with a contrasting outline so it
/// stays readable over any background.
///
/// Flutter has no built-in stroked text, so we stack two [Text] layers — one
/// painted as an outline (stroke), one as the solid fill.
class MemeText extends StatelessWidget {
  const MemeText({
    super.key,
    required this.text,
    required this.fillColor,
    required this.fontSize,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final Color fillColor;
  final double fontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    // Outline contrasts with the fill so it reads on light or dark fills.
    final Color outlineColor =
        fillColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    final double strokeWidth = (fontSize * 0.08).clamp(2.0, 8.0);

    final TextStyle base = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.2,
      height: 1.05,
    );

    final String display = text.toUpperCase();

    return Stack(
      children: <Widget>[
        // Stroke layer.
        Text(
          display,
          textAlign: textAlign,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = outlineColor,
          ),
        ),
        // Fill layer.
        Text(
          display,
          textAlign: textAlign,
          style: base.copyWith(color: fillColor),
        ),
      ],
    );
  }
}
