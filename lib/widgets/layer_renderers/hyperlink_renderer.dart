import 'package:flutter/material.dart';

import '../../models/layer.dart';

/// Renders a [HyperlinkLayer] as underlined coloured text. The PNG export can
/// only carry visible text — the actual URL is exposed in the inspector
/// ("Copy link" button) and appended to the share caption so it survives.
class HyperlinkRenderer extends StatelessWidget {
  const HyperlinkRenderer({
    super.key,
    required this.layer,
    required this.canvasSize,
  });

  final HyperlinkLayer layer;
  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    final String display = layer.displayText;
    if (display.isEmpty) return const SizedBox.shrink();
    final double fontSize = layer.fontSize * canvasSize.height;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: _alignFor(layer.align),
      child: Text(
        display,
        textAlign: layer.align.toFlutter(),
        style: TextStyle(
          fontFamily: layer.fontFamily,
          fontSize: fontSize,
          color: layer.color,
          fontWeight: layer.bold ? FontWeight.w700 : FontWeight.w500,
          fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
          decoration: TextDecoration.underline,
          decorationColor: layer.color,
          height: 1.1,
        ),
      ),
    );
  }

  Alignment _alignFor(LayerTextAlign a) {
    switch (a) {
      case LayerTextAlign.left:
        return Alignment.centerLeft;
      case LayerTextAlign.right:
        return Alignment.centerRight;
      case LayerTextAlign.center:
        return Alignment.center;
    }
  }
}
