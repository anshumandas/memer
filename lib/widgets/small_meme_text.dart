import 'package:flutter/material.dart';

import '../models/meme_config.dart';

/// Small caption used for the meme's header, footnote and link rows. Unlike
/// [MemeText] this is mixed case and uses a soft shadow rather than a heavy
/// outline — the intent is a subtle byline, not a punchy joke caption.
class SmallMemeText extends StatelessWidget {
  const SmallMemeText({
    super.key,
    required this.text,
    required this.color,
    required this.fontSize,
    required this.align,
    this.underline = false,
  });

  final String text;
  final Color color;
  final double fontSize;
  final MemeTextAlign align;
  final bool underline;

  static TextAlign textAlignOf(MemeTextAlign a) {
    switch (a) {
      case MemeTextAlign.left:
        return TextAlign.left;
      case MemeTextAlign.right:
        return TextAlign.right;
      case MemeTextAlign.center:
        return TextAlign.center;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    // Shadow contrasts with the fill so the byline stays legible over any
    // background.
    final Color shadowColor =
        color.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    return Text(
      text,
      textAlign: textAlignOf(align),
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        height: 1.2,
        decoration: underline ? TextDecoration.underline : TextDecoration.none,
        decorationColor: color,
        shadows: <Shadow>[
          Shadow(
            color: shadowColor.withOpacity(0.7),
            blurRadius: fontSize * 0.25,
          ),
        ],
      ),
    );
  }
}
