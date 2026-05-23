import 'package:flutter/material.dart';

import '../models/callout.dart';
import '../models/meme_config.dart';
import '../models/meme_controller.dart';
import 'callout_bubble.dart';
import 'draggable_callout.dart';
import 'meme_text.dart';

/// The visual meme. The same widget is used both for the on-screen editor
/// (interactive) and for the off-screen render that gets exported to PNG,
/// which guarantees the export looks exactly like the preview.
class MemeCanvas extends StatelessWidget {
  const MemeCanvas({
    super.key,
    required this.controller,
    this.repaintKey,
    this.interactive = true,
  });

  final MemeController controller;

  /// Attached to the [RepaintBoundary] so the screen can grab the pixels.
  final GlobalKey? repaintKey;

  /// When false, callouts are static (used for the export render).
  final bool interactive;

  /// All sizes are derived from this reference width so the layout scales
  /// uniformly between the small editor canvas and the large export.
  static const double _referenceWidth = 360.0;
  static const double _baseCaptionSize = 30.0;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: repaintKey,
      child: AspectRatio(
        aspectRatio: 1, // square — the friendliest format across social apps
        child: ClipRect(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Size size = constraints.biggest;
              final double scale = size.width / _referenceWidth;
              final double pad = size.width * 0.04;
              final MemeConfig config = controller.config;

              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // 1. Solid background colour.
                  ColoredBox(color: config.backgroundColor),

                  // 2. Optional background image.
                  if (config.backgroundImage != null)
                    Positioned.fill(
                      child: Image.memory(
                        config.backgroundImage!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),

                  // 3. Top caption.
                  Positioned(
                    top: pad,
                    left: pad,
                    right: pad,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: MemeText(
                        text: config.topText,
                        fillColor: config.memeTextColor,
                        fontSize: _baseCaptionSize * scale,
                      ),
                    ),
                  ),

                  // 4. Bottom caption.
                  Positioned(
                    bottom: pad,
                    left: pad,
                    right: pad,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: MemeText(
                        text: config.bottomText,
                        fillColor: config.memeTextColor,
                        fontSize: _baseCaptionSize * scale,
                      ),
                    ),
                  ),

                  // 5. Callouts.
                  ...config.callouts.map(
                    (Callout c) => _positionedCallout(c, size, scale),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _positionedCallout(Callout c, Size size, double scale) {
    final bool selected = interactive && controller.selectedCalloutId == c.id;
    final Widget bubble = interactive
        ? DraggableCallout(
            callout: c,
            controller: controller,
            canvasSize: size,
            scale: scale,
            selected: selected,
          )
        : CalloutBubble(callout: c, scale: scale);

    return Positioned(
      left: c.position.dx * size.width,
      top: c.position.dy * size.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: bubble,
      ),
    );
  }
}
