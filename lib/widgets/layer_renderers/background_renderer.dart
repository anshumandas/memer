import 'package:flutter/material.dart';

import '../../models/layer.dart';

/// Solid colour fill behind every other layer.
class BackgroundRenderer extends StatelessWidget {
  const BackgroundRenderer({super.key, required this.layer});

  final BackgroundLayer layer;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(color: layer.color),
    );
  }
}
