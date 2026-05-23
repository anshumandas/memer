import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'callout.dart';

/// Horizontal alignment used by the header / footnote / link rows.
enum MemeTextAlign { left, center, right }

/// Immutable snapshot of everything that defines a meme.
///
/// Kept separate from the controller so it is trivially unit-testable and
/// could later be serialised to disk / JSON without touching UI code.
@immutable
class MemeConfig {
  const MemeConfig({
    this.backgroundColor = const Color(0xFF1E1E1E),
    this.backgroundImage,
    this.topText = '',
    this.bottomText = '',
    this.memeTextColor = Colors.white,
    this.headerText = '',
    this.headerAlign = MemeTextAlign.center,
    this.footnoteText = '',
    this.footnoteAlign = MemeTextAlign.center,
    this.linkUrl = '',
    this.linkLabel = '',
    this.linkAlign = MemeTextAlign.center,
    this.callouts = const <Callout>[],
  });

  /// Solid colour drawn behind everything. Visible wherever there is no
  /// background image (or when no image has been chosen).
  final Color backgroundColor;

  /// Optional background image, held in memory as raw bytes so the same
  /// config works identically on every platform (incl. web, where there is
  /// no file path).
  final Uint8List? backgroundImage;

  /// Classic top / bottom meme captions.
  final String topText;
  final String bottomText;

  /// Fill colour for the top/bottom captions (they always get a contrasting
  /// outline, drawn in [memeTextColor]'s opposite, for legibility).
  final Color memeTextColor;

  /// Small text rendered above the top caption.
  final String headerText;
  final MemeTextAlign headerAlign;

  /// Small text rendered below the bottom caption.
  final String footnoteText;
  final MemeTextAlign footnoteAlign;

  /// Optional clickable URL, rendered at the very bottom of the canvas.
  /// In the editor preview the rendered row is tappable; in the exported
  /// PNG it is just text, and the URL is appended to the share caption so
  /// it travels with the post.
  final String linkUrl;

  /// Optional display label for the link. When empty the URL itself is
  /// shown.
  final String linkLabel;
  final MemeTextAlign linkAlign;

  /// Optional speech-bubble overlays.
  final List<Callout> callouts;

  bool get hasBackgroundImage => backgroundImage != null;
  bool get hasHeader => headerText.trim().isNotEmpty;
  bool get hasFootnote => footnoteText.trim().isNotEmpty;
  bool get hasLink => linkUrl.trim().isNotEmpty;

  /// Text actually shown for the hyperlink (falls back to the URL when no
  /// label is set).
  String get linkDisplay =>
      linkLabel.trim().isNotEmpty ? linkLabel.trim() : linkUrl.trim();

  MemeConfig copyWith({
    Color? backgroundColor,
    Uint8List? backgroundImage,
    bool clearBackgroundImage = false,
    String? topText,
    String? bottomText,
    Color? memeTextColor,
    String? headerText,
    MemeTextAlign? headerAlign,
    String? footnoteText,
    MemeTextAlign? footnoteAlign,
    String? linkUrl,
    String? linkLabel,
    MemeTextAlign? linkAlign,
    List<Callout>? callouts,
  }) {
    return MemeConfig(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundImage: clearBackgroundImage
          ? null
          : (backgroundImage ?? this.backgroundImage),
      topText: topText ?? this.topText,
      bottomText: bottomText ?? this.bottomText,
      memeTextColor: memeTextColor ?? this.memeTextColor,
      headerText: headerText ?? this.headerText,
      headerAlign: headerAlign ?? this.headerAlign,
      footnoteText: footnoteText ?? this.footnoteText,
      footnoteAlign: footnoteAlign ?? this.footnoteAlign,
      linkUrl: linkUrl ?? this.linkUrl,
      linkLabel: linkLabel ?? this.linkLabel,
      linkAlign: linkAlign ?? this.linkAlign,
      callouts: callouts ?? this.callouts,
    );
  }
}
