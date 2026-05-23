import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'callout.dart';

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

  /// Optional speech-bubble overlays.
  final List<Callout> callouts;

  bool get hasBackgroundImage => backgroundImage != null;

  MemeConfig copyWith({
    Color? backgroundColor,
    Uint8List? backgroundImage,
    bool clearBackgroundImage = false,
    String? topText,
    String? bottomText,
    Color? memeTextColor,
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
      callouts: callouts ?? this.callouts,
    );
  }
}
