import 'dart:typed_data';

import 'package:flutter/material.dart';

/// The shape of a speech / thought callout.
enum CalloutKind {
  speechRound,
  speechSharp,
  thoughtCloud,
  rectangle,
  oval,
  scallop,
}

/// Horizontal alignment for text-bearing layers.
enum LayerTextAlign { left, center, right }

extension LayerTextAlignX on LayerTextAlign {
  TextAlign toFlutter() {
    switch (this) {
      case LayerTextAlign.left:
        return TextAlign.left;
      case LayerTextAlign.right:
        return TextAlign.right;
      case LayerTextAlign.center:
        return TextAlign.center;
    }
  }
}

/// Base type for every drawable element on the meme canvas.
///
/// Layers are stored in z-order in [MemeConfig.layers] (index 0 = bottom).
/// All geometric properties are stored in *fractional* canvas units
/// (0..1 along each axis), so the on-screen editor preview maps one-to-one to
/// the exported high-resolution PNG without any per-pixel maths.
///
/// Sealed so the inspector / renderer can pattern-match exhaustively.
@immutable
sealed class Layer {
  const Layer({
    required this.id,
    required this.name,
    this.visible = true,
    this.locked = false,
    this.opacity = 1.0,
    this.position = const Offset(0.5, 0.5),
    this.size = const Size(0.6, 0.2),
    this.rotation = 0.0,
  });

  /// Stable id used for selection and reorder operations.
  final String id;

  /// User-editable display name shown in the layers panel.
  final String name;

  final bool visible;
  final bool locked;

  /// 0..1; the renderer multiplies this onto every layer.
  final double opacity;

  /// Fractional centre of the layer on the canvas (0..1, 0..1).
  /// Ignored by [BackgroundLayer] (it always fills the canvas).
  final Offset position;

  /// Fractional width/height of the layer's bounding box. Height is treated
  /// as a *maximum* for intrinsically-sized content (text, callouts) and as
  /// an exact size for raster content (images).
  final Size size;

  /// Rotation around [position], in radians.
  final double rotation;

  /// Discriminator used by inspector / renderer / serialisation code that
  /// can't rely on `switch` over a sealed type at runtime.
  String get kind;

  Layer copyWithBase({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    Offset? position,
    Size? size,
    double? rotation,
  });
}

/// Solid colour drawn behind every other layer. There is at most one of these
/// at index 0; the controller enforces that invariant.
class BackgroundLayer extends Layer {
  const BackgroundLayer({
    required super.id,
    super.name = 'Background',
    super.visible,
    super.locked,
    super.opacity,
    this.color = const Color(0xFF1E1E1E),
  }) : super(
         position: const Offset(0.5, 0.5),
         size: const Size(1.0, 1.0),
         rotation: 0,
       );

  final Color color;

  @override
  String get kind => 'background';

  BackgroundLayer copyWith({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    Color? color,
  }) {
    return BackgroundLayer(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      opacity: opacity ?? this.opacity,
      color: color ?? this.color,
    );
  }

  @override
  BackgroundLayer copyWithBase({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    Offset? position,
    Size? size,
    double? rotation,
  }) {
    // Background ignores geometric edits — they're always full-bleed.
    return copyWith(
      name: name,
      visible: visible,
      locked: locked,
      opacity: opacity,
    );
  }
}

/// Plain rendered text (caption, label, etc.).
class TextLayer extends Layer {
  const TextLayer({
    required super.id,
    super.name = 'Text',
    super.visible,
    super.locked,
    super.opacity,
    super.position,
    super.size = const Size(0.7, 0.2),
    super.rotation,
    this.text = 'Double-tap to edit',
    this.fontFamily = 'Impact',
    this.fontSize = 0.08,
    this.color = Colors.white,
    this.bold = true,
    this.italic = false,
    this.align = LayerTextAlign.center,
    this.outlined = true,
  });

  final String text;

  /// One of [kAvailableFonts].
  final String fontFamily;

  /// Font size as a fraction of canvas height (0.08 ≈ 8% of height).
  /// Stored fractionally so the export and the editor render at exactly the
  /// same relative scale.
  final double fontSize;

  final Color color;
  final bool bold;
  final bool italic;
  final LayerTextAlign align;

  /// When true, paints a contrasting outline behind the fill — the classic
  /// "impact-style" meme caption look. Toggleable per-layer because the same
  /// layer family is also used for body copy where an outline would be ugly.
  final bool outlined;

  @override
  String get kind => 'text';

  TextLayer copyWith({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    Offset? position,
    Size? size,
    double? rotation,
    String? text,
    String? fontFamily,
    double? fontSize,
    Color? color,
    bool? bold,
    bool? italic,
    LayerTextAlign? align,
    bool? outlined,
  }) {
    return TextLayer(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      opacity: opacity ?? this.opacity,
      position: position ?? this.position,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      text: text ?? this.text,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      align: align ?? this.align,
      outlined: outlined ?? this.outlined,
    );
  }

  @override
  TextLayer copyWithBase({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    Offset? position,
    Size? size,
    double? rotation,
  }) {
    return copyWith(
      name: name,
      visible: visible,
      locked: locked,
      opacity: opacity,
      position: position,
      size: size,
      rotation: rotation,
    );
  }
}

/// Text that also carries a URL. Rendered with an underline; the exported
/// PNG can't carry a clickable link, but a "Copy link" button is exposed
/// in the inspector and the URL is also appended to the share caption.
class HyperlinkLayer extends Layer {
  const HyperlinkLayer({
    required super.id,
    super.name = 'Link',
    super.visible,
    super.locked,
    super.opacity,
    super.position,
    super.size = const Size(0.7, 0.08),
    super.rotation,
    this.url = '',
    this.label = '',
    this.fontFamily = 'Roboto',
    this.fontSize = 0.04,
    this.color = const Color(0xFF4FB6FF),
    this.bold = false,
    this.italic = false,
    this.align = LayerTextAlign.center,
  });

  final String url;

  /// Optional display label; when blank, the URL itself is shown.
  final String label;

  final String fontFamily;
  final double fontSize;
  final Color color;
  final bool bold;
  final bool italic;
  final LayerTextAlign align;

  String get displayText => label.trim().isEmpty ? url.trim() : label.trim();

  @override
  String get kind => 'hyperlink';

  HyperlinkLayer copyWith({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    Offset? position,
    Size? size,
    double? rotation,
    String? url,
    String? label,
    String? fontFamily,
    double? fontSize,
    Color? color,
    bool? bold,
    bool? italic,
    LayerTextAlign? align,
  }) {
    return HyperlinkLayer(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      opacity: opacity ?? this.opacity,
      position: position ?? this.position,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      url: url ?? this.url,
      label: label ?? this.label,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      align: align ?? this.align,
    );
  }

  @override
  HyperlinkLayer copyWithBase({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    Offset? position,
    Size? size,
    double? rotation,
  }) {
    return copyWith(
      name: name,
      visible: visible,
      locked: locked,
      opacity: opacity,
      position: position,
      size: size,
      rotation: rotation,
    );
  }
}

/// A raster image (PNG/JPG/etc.).
///
/// [bytes] always holds the *current* pixels — crops, rotations baked in by
/// the inspector, and the alpha mask produced by the background-removal tool
/// are all written back into [bytes]. [originalBytes] preserves the user's
/// last import so a destructive op (mask, crop) can be re-opened with a
/// fresh canvas. (Phase 2 wires the image tools; Phase 1 just stores them.)
class ImageLayer extends Layer {
  const ImageLayer({
    required super.id,
    super.name = 'Image',
    super.visible,
    super.locked,
    super.opacity,
    super.position,
    super.size = const Size(0.6, 0.6),
    super.rotation,
    required this.bytes,
    this.originalBytes,
  });

  final Uint8List bytes;
  final Uint8List? originalBytes;

  @override
  String get kind => 'image';

  ImageLayer copyWith({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    Offset? position,
    Size? size,
    double? rotation,
    Uint8List? bytes,
    Uint8List? originalBytes,
    bool clearOriginal = false,
  }) {
    return ImageLayer(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      opacity: opacity ?? this.opacity,
      position: position ?? this.position,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      bytes: bytes ?? this.bytes,
      originalBytes: clearOriginal
          ? null
          : (originalBytes ?? this.originalBytes),
    );
  }

  @override
  ImageLayer copyWithBase({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    Offset? position,
    Size? size,
    double? rotation,
  }) {
    return copyWith(
      name: name,
      visible: visible,
      locked: locked,
      opacity: opacity,
      position: position,
      size: size,
      rotation: rotation,
    );
  }
}

/// A speech / thought bubble that points at [tailTarget] (also fractional).
///
/// Keeping the tail target as a *separate* fractional point (rather than
/// derived from a corner enum, like the old [Callout]) lets the bubble's
/// tail re-orient automatically when the user drags either the bubble or
/// the target — and lets it point at any subject anywhere on the canvas,
/// including outside the bubble's own bounding box.
class CalloutLayer extends Layer {
  const CalloutLayer({
    required super.id,
    super.name = 'Callout',
    super.visible,
    super.locked,
    super.opacity,
    super.position,
    super.size = const Size(0.45, 0.18),
    super.rotation,
    this.shape = CalloutKind.speechRound,
    this.text = 'Say something…',
    this.fillColor = Colors.white,
    this.borderColor = const Color(0xFF222222),
    this.borderWidth = 1.5,
    this.textColor = Colors.black,
    this.fontFamily = 'Roboto',
    this.fontSize = 0.045,
    this.bold = false,
    this.italic = false,
    this.tailTarget = const Offset(0.5, 0.85),
    this.showTail = true,
  });

  /// Visual shape of the bubble. Named [shape] (not [kind]) to avoid colliding
  /// with [Layer.kind], which is the string discriminator used across all
  /// layer types.
  final CalloutKind shape;

  final String text;
  final Color fillColor;
  final Color borderColor;
  final double borderWidth;
  final Color textColor;
  final String fontFamily;
  final double fontSize;
  final bool bold;
  final bool italic;

  /// Fractional point on the canvas the tail should point to.
  final Offset tailTarget;

  final bool showTail;

  @override
  String get kind => 'callout';

  CalloutLayer copyWith({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    Offset? position,
    Size? size,
    double? rotation,
    CalloutKind? shape,
    String? text,
    Color? fillColor,
    Color? borderColor,
    double? borderWidth,
    Color? textColor,
    String? fontFamily,
    double? fontSize,
    bool? bold,
    bool? italic,
    Offset? tailTarget,
    bool? showTail,
  }) {
    return CalloutLayer(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      opacity: opacity ?? this.opacity,
      position: position ?? this.position,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      shape: shape ?? this.shape,
      text: text ?? this.text,
      fillColor: fillColor ?? this.fillColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      textColor: textColor ?? this.textColor,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      tailTarget: tailTarget ?? this.tailTarget,
      showTail: showTail ?? this.showTail,
    );
  }

  @override
  CalloutLayer copyWithBase({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    Offset? position,
    Size? size,
    double? rotation,
  }) {
    return copyWith(
      name: name,
      visible: visible,
      locked: locked,
      opacity: opacity,
      position: position,
      size: size,
      rotation: rotation,
    );
  }
}

/// Fonts the user can pick from. Kept tiny on purpose — every entry must be
/// either a Material-bundled font or registered in [pubspec.yaml]. Phase 1
/// uses only the system / Material defaults; richer choices arrive when we
/// wire [google_fonts] (see roadmap in CLAUDE.md).
const List<String> kAvailableFonts = <String>[
  'Roboto',
  'Impact',
  'Arial',
  'Courier',
  'Georgia',
];

/// Clamp helpers used by [MemeController] when accepting drag deltas.
extension OffsetClamp on Offset {
  Offset clamp01() => Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));
}

extension SizeClamp on Size {
  Size clamp01({double minSide = 0.04}) =>
      Size(width.clamp(minSide, 1.0), height.clamp(minSide, 1.0));
}
