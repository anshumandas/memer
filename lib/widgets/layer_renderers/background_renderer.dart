import 'package:flutter/material.dart';

import '../../models/layer.dart';

/// Solid colour fill behind every other layer. Sized by its caller — when
/// hosted by [MemeCanvas] it sits inside a [Positioned.fill], so the
/// `ColoredBox` here just expands to whatever space is given.
class BackgroundRenderer extends StatelessWidget {
  const BackgroundRenderer({super.key, required this.layer});

  final BackgroundLayer layer;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: layer.color);
  }
}
