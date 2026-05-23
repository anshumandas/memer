import 'package:flutter/material.dart';

/// Which corner the speech-bubble tail points out from.
enum CalloutTail { bottomLeft, bottomRight, topLeft, topRight, none }

/// A draggable speech-bubble overlaid on the meme.
///
/// [position] is stored as a *fractional* offset (each component in the
/// 0..1 range, relative to the canvas size). Storing it this way means the
/// bubble lands in the same spot whether it is drawn on the small on-screen
/// editor canvas or on the high-resolution exported image.
@immutable
class Callout {
  const Callout({
    required this.id,
    this.text = 'Say something…',
    this.position = const Offset(0.5, 0.5),
    this.tail = CalloutTail.bottomLeft,
    this.bubbleColor = Colors.white,
    this.textColor = Colors.black,
    this.fontSize = 18,
  });

  final String id;
  final String text;
  final Offset position;
  final CalloutTail tail;
  final Color bubbleColor;
  final Color textColor;
  final double fontSize;

  Callout copyWith({
    String? text,
    Offset? position,
    CalloutTail? tail,
    Color? bubbleColor,
    Color? textColor,
    double? fontSize,
  }) {
    return Callout(
      id: id,
      text: text ?? this.text,
      position: position ?? this.position,
      tail: tail ?? this.tail,
      bubbleColor: bubbleColor ?? this.bubbleColor,
      textColor: textColor ?? this.textColor,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  /// Clamp the fractional position so the bubble can never be dragged fully
  /// off the canvas.
  Callout clampedToCanvas() {
    return copyWith(
      position: Offset(
        position.dx.clamp(0.0, 1.0),
        position.dy.clamp(0.0, 1.0),
      ),
    );
  }
}
