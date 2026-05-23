import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/callout.dart';
import '../models/meme_config.dart';
import '../models/meme_controller.dart';
import 'callout_bubble.dart';
import 'draggable_callout.dart';
import 'meme_text.dart';
import 'small_meme_text.dart';

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
  static const double _baseSmallSize = 12.0;

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

                  // 3. Top stack: optional small header + top caption.
                  Positioned(
                    top: pad,
                    left: pad,
                    right: pad,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (config.hasHeader) ...<Widget>[
                          SmallMemeText(
                            text: config.headerText,
                            color: config.memeTextColor,
                            fontSize: _baseSmallSize * scale,
                            align: config.headerAlign,
                          ),
                          SizedBox(height: pad * 0.5),
                        ],
                        MemeText(
                          text: config.topText,
                          fillColor: config.memeTextColor,
                          fontSize: _baseCaptionSize * scale,
                        ),
                      ],
                    ),
                  ),

                  // 4. Bottom stack: bottom caption + optional footnote +
                  //    optional clickable link.
                  Positioned(
                    bottom: pad,
                    left: pad,
                    right: pad,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        MemeText(
                          text: config.bottomText,
                          fillColor: config.memeTextColor,
                          fontSize: _baseCaptionSize * scale,
                        ),
                        if (config.hasFootnote) ...<Widget>[
                          SizedBox(height: pad * 0.5),
                          SmallMemeText(
                            text: config.footnoteText,
                            color: config.memeTextColor,
                            fontSize: _baseSmallSize * scale,
                            align: config.footnoteAlign,
                          ),
                        ],
                        if (config.hasLink) ...<Widget>[
                          SizedBox(height: pad * 0.35),
                          _LinkRow(
                            url: config.linkUrl,
                            display: config.linkDisplay,
                            align: config.linkAlign,
                            fontSize: _baseSmallSize * scale,
                            color: config.memeTextColor,
                            interactive: interactive,
                          ),
                        ],
                      ],
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

/// Renders the hyperlink. In the interactive editor preview it is wrapped in
/// a [GestureDetector] so tapping launches the URL. The exported PNG is just
/// the text — links can't survive a raster image — so the URL is also
/// appended to the share caption by the caller.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.url,
    required this.display,
    required this.align,
    required this.fontSize,
    required this.color,
    required this.interactive,
  });

  final String url;
  final String display;
  final MemeTextAlign align;
  final double fontSize;
  final Color color;
  final bool interactive;

  Alignment _stackAlign() {
    switch (align) {
      case MemeTextAlign.left:
        return Alignment.centerLeft;
      case MemeTextAlign.right:
        return Alignment.centerRight;
      case MemeTextAlign.center:
        return Alignment.center;
    }
  }

  Future<void> _open() async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final Widget label = SmallMemeText(
      text: display,
      color: color,
      fontSize: fontSize,
      align: align,
      underline: true,
    );

    if (!interactive) return label;

    return Align(
      alignment: _stackAlign(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: label,
        ),
      ),
    );
  }
}
