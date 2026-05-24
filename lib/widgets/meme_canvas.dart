import 'package:flutter/material.dart';

import '../models/layer.dart';
import '../models/meme_config.dart';
import '../models/meme_controller.dart';
import 'layer_renderers/background_renderer.dart';
import 'layer_renderers/callout_renderer.dart';
import 'layer_renderers/hyperlink_renderer.dart';
import 'layer_renderers/image_renderer.dart';
import 'layer_renderers/text_renderer.dart';

/// The visual meme.
///
/// Renders every layer in z-order inside a [RepaintBoundary] so the same
/// widget tree feeds both the on-screen editor preview and the off-screen
/// PNG export — preview is the export (WYSIWYG).
///
/// The canvas owns its own [ListenableBuilder] so a layer drag re-renders
/// the canvas without forcing the whole editor (layers panel, inspector,
/// scaffold) to rebuild. Each individual layer is wrapped in its own
/// [RepaintBoundary] (placed *inside* the [Positioned], so the Positioned
/// stays a direct child of [Stack] — otherwise Flutter throws "Incorrect
/// use of ParentDataWidget").
///
/// This widget deliberately knows nothing about selection / drag / resize
/// affordances. Those live in a sibling overlay (`LayerSelectionOverlay`)
/// so the handles never end up in the exported pixels.
class MemeCanvas extends StatelessWidget {
  const MemeCanvas({super.key, required this.controller, this.repaintKey});

  final MemeController controller;

  /// Attached to the [RepaintBoundary] so the export service can grab pixels.
  final GlobalKey? repaintKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final MemeConfig config = controller.config;
        return AspectRatio(
          aspectRatio: config.aspect.ratio,
          child: ClipRect(
            child: RepaintBoundary(
              key: repaintKey,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Size canvasSize = constraints.biggest;
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      for (final Layer layer in config.layers)
                        if (layer.visible) _positionedLayer(layer, canvasSize),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the [Positioned] (or [Positioned.fill]) child for a single layer.
  /// `Positioned` MUST be the direct child of the parent [Stack]; wrapping
  /// it in another widget like [RepaintBoundary] would silently break stack
  /// layout (and throw a ParentDataWidget assert on the web).
  Widget _positionedLayer(Layer layer, Size canvasSize) {
    if (layer is BackgroundLayer) {
      return Positioned.fill(
        key: ValueKey<String>(layer.id),
        child: RepaintBoundary(
          child: Opacity(
            opacity: layer.opacity,
            child: BackgroundRenderer(layer: layer),
          ),
        ),
      );
    }

    final double w = layer.size.width * canvasSize.width;
    final double h = layer.size.height * canvasSize.height;
    final double cx = layer.position.dx * canvasSize.width;
    final double cy = layer.position.dy * canvasSize.height;

    return Positioned(
      key: ValueKey<String>(layer.id),
      left: cx - w / 2,
      top: cy - h / 2,
      width: w,
      height: h,
      child: RepaintBoundary(
        child: Opacity(
          opacity: layer.opacity,
          child: Transform.rotate(
            angle: layer.rotation,
            child: _rendererFor(layer, canvasSize),
          ),
        ),
      ),
    );
  }

  Widget _rendererFor(Layer layer, Size canvasSize) {
    switch (layer) {
      case BackgroundLayer():
        return BackgroundRenderer(layer: layer);
      case TextLayer():
        return TextRenderer(layer: layer, canvasSize: canvasSize);
      case HyperlinkLayer():
        return HyperlinkRenderer(layer: layer, canvasSize: canvasSize);
      case ImageLayer():
        return ImageRenderer(layer: layer);
      case CalloutLayer():
        return CalloutRenderer(layer: layer, canvasSize: canvasSize);
    }
  }
}
