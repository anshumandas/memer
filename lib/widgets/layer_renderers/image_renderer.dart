import 'package:flutter/material.dart';

import '../../models/layer.dart';

/// Renders an [ImageLayer]. Uses `BoxFit.fill` so the explicit fractional
/// size the user resized to is exactly respected — preserving aspect ratio
/// is a job for the resize affordance in the inspector / selection overlay
/// (corner-handle drags lock aspect by default).
class ImageRenderer extends StatelessWidget {
  const ImageRenderer({super.key, required this.layer});

  final ImageLayer layer;

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      layer.bytes,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}
