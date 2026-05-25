import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'layer.dart';
import 'meme_config.dart';

/// A reusable meme layout that is stored as JSON, rendered as a list of
/// [Layer]s, and exposes a small set of editable "slots" (text, image) the
/// user fills in through the template wizard.
///
/// Templates intentionally never embed binary image data — image layers are
/// stored as **slots** that the user populates at instantiation time with
/// their own picker selection. This keeps the JSON small, the app
/// copyright-clean, and the templates trivially diffable.
@immutable
class MemeTemplate {
  const MemeTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.aspect,
    required this.layers,
  });

  /// Stable, app-unique id (also used as the slug in the gallery).
  final String id;
  final String name;
  final String description;

  /// Coarse grouping for the gallery ("Classic", "Reaction", "Quote", ...).
  final String category;

  final CanvasAspect aspect;

  /// Ordered layers (index 0 = bottom of the stack).
  final List<LayerTemplate> layers;

  /// All template layers that should be exposed as a text input in the
  /// wizard, in the order they should be shown.
  List<LayerTemplate> get editableLayers =>
      layers.where((LayerTemplate l) => l.isEditable).toList(growable: false);

  /// All image slots the wizard should expose as image pickers.
  List<ImageLayerTemplate> get imageSlots => layers
      .whereType<ImageLayerTemplate>()
      .where((ImageLayerTemplate l) => l.slot)
      .toList(growable: false);

  /// Build a concrete [MemeConfig] from this template.
  ///
  /// [textValues] / [imageValues] override the corresponding template layer's
  /// default content; entries are keyed by [LayerTemplate.id]. Missing values
  /// fall through to the template defaults so the preview is never empty.
  MemeConfig instantiate({
    Map<String, String> textValues = const <String, String>{},
    Map<String, Uint8List> imageValues = const <String, Uint8List>{},
    required Uint8List placeholderImageBytes,
    String idPrefix = 't',
  }) {
    int counter = 0;
    final List<Layer> built = <Layer>[];
    for (final LayerTemplate t in layers) {
      built.add(
        t.instantiate(
          runtimeId: '${idPrefix}_${t.id}_${counter++}',
          textValues: textValues,
          imageValues: imageValues,
          placeholderImageBytes: placeholderImageBytes,
        ),
      );
    }
    return MemeConfig(aspect: aspect, layers: built);
  }

  factory MemeTemplate.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawLayers =
        (json['layers'] as List<dynamic>?) ?? const <dynamic>[];
    return MemeTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      category: (json['category'] as String?) ?? 'Other',
      aspect: _aspectFromString(json['aspect'] as String?),
      layers: <LayerTemplate>[
        for (final dynamic raw in rawLayers)
          LayerTemplate.fromJson(raw as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'description': description,
    'category': category,
    'aspect': _aspectToString(aspect),
    'layers': <Map<String, dynamic>>[
      for (final LayerTemplate l in layers) l.toJson(),
    ],
  };
}

// ---------------------------------------------------------------------------
// Layer templates
// ---------------------------------------------------------------------------

/// A single layer entry inside a [MemeTemplate]. Mirrors the [Layer] hierarchy
/// but without runtime-only state (selection, raw image bytes).
@immutable
sealed class LayerTemplate {
  const LayerTemplate({
    required this.id,
    this.name,
    this.position = const Offset(0.5, 0.5),
    this.size = const Size(0.6, 0.2),
    this.rotation = 0.0,
    this.opacity = 1.0,
  });

  /// Author-supplied id. Doubles as the key into the wizard's text/image
  /// override maps for editable templates.
  final String id;

  /// Optional human-readable layer name (defaults per kind otherwise).
  final String? name;

  final Offset position;
  final Size size;
  final double rotation;
  final double opacity;

  String get kind;

  /// Whether the wizard should expose this layer for editing.
  bool get isEditable => false;

  /// Label shown above the input in the wizard (e.g. "Top caption").
  String? get promptLabel => null;

  Layer instantiate({
    required String runtimeId,
    required Map<String, String> textValues,
    required Map<String, Uint8List> imageValues,
    required Uint8List placeholderImageBytes,
  });

  Map<String, dynamic> toJson();

  factory LayerTemplate.fromJson(Map<String, dynamic> json) {
    final String kind = json['kind'] as String;
    switch (kind) {
      case 'background':
        return BackgroundLayerTemplate.fromJson(json);
      case 'text':
        return TextLayerTemplate.fromJson(json);
      case 'hyperlink':
        return HyperlinkLayerTemplate.fromJson(json);
      case 'image':
        return ImageLayerTemplate.fromJson(json);
      case 'callout':
        return CalloutLayerTemplate.fromJson(json);
      default:
        throw FormatException('Unknown layer kind: $kind');
    }
  }
}

class BackgroundLayerTemplate extends LayerTemplate {
  const BackgroundLayerTemplate({
    required super.id,
    super.name,
    this.color = const Color(0xFF1E1E1E),
  });

  final Color color;

  @override
  String get kind => 'background';

  @override
  Layer instantiate({
    required String runtimeId,
    required Map<String, String> textValues,
    required Map<String, Uint8List> imageValues,
    required Uint8List placeholderImageBytes,
  }) {
    return BackgroundLayer(
      id: runtimeId,
      name: name ?? 'Background',
      color: color,
      opacity: opacity,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': 'background',
    'id': id,
    if (name != null) 'name': name,
    'color': _colorToHex(color),
  };

  factory BackgroundLayerTemplate.fromJson(Map<String, dynamic> json) {
    return BackgroundLayerTemplate(
      id: (json['id'] as String?) ?? 'bg',
      name: json['name'] as String?,
      color: _colorFromHex(json['color'] as String?) ?? const Color(0xFF1E1E1E),
    );
  }
}

class TextLayerTemplate extends LayerTemplate {
  const TextLayerTemplate({
    required super.id,
    super.name,
    super.position,
    super.size = const Size(0.9, 0.2),
    super.rotation,
    super.opacity,
    this.text = 'Text',
    this.fontFamily = 'Impact',
    this.fontSize = 0.08,
    this.color = Colors.white,
    this.bold = true,
    this.italic = false,
    this.align = LayerTextAlign.center,
    this.outlined = true,
    this.editable = false,
    this.promptLabelText,
  });

  final String text;
  final String fontFamily;
  final double fontSize;
  final Color color;
  final bool bold;
  final bool italic;
  final LayerTextAlign align;
  final bool outlined;

  final bool editable;
  final String? promptLabelText;

  @override
  String get kind => 'text';

  @override
  bool get isEditable => editable;

  @override
  String? get promptLabel => promptLabelText;

  @override
  Layer instantiate({
    required String runtimeId,
    required Map<String, String> textValues,
    required Map<String, Uint8List> imageValues,
    required Uint8List placeholderImageBytes,
  }) {
    return TextLayer(
      id: runtimeId,
      name: name ?? (editable ? (promptLabelText ?? 'Text') : 'Text'),
      position: position,
      size: size,
      rotation: rotation,
      opacity: opacity,
      text: textValues[id] ?? text,
      fontFamily: fontFamily,
      fontSize: fontSize,
      color: color,
      bold: bold,
      italic: italic,
      align: align,
      outlined: outlined,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': 'text',
    'id': id,
    if (name != null) 'name': name,
    'position': _offsetToJson(position),
    'size': _sizeToJson(size),
    if (rotation != 0) 'rotation': rotation,
    if (opacity != 1.0) 'opacity': opacity,
    'text': text,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'color': _colorToHex(color),
    'bold': bold,
    'italic': italic,
    'align': _alignToString(align),
    'outlined': outlined,
    if (editable) 'editable': true,
    if (promptLabelText != null) 'promptLabel': promptLabelText,
  };

  factory TextLayerTemplate.fromJson(Map<String, dynamic> json) {
    return TextLayerTemplate(
      id: (json['id'] as String?) ?? 'text',
      name: json['name'] as String?,
      position: _offsetFromJson(json['position']) ?? const Offset(0.5, 0.5),
      size: _sizeFromJson(json['size']) ?? const Size(0.9, 0.2),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      text: (json['text'] as String?) ?? '',
      fontFamily: (json['fontFamily'] as String?) ?? 'Impact',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 0.08,
      color: _colorFromHex(json['color'] as String?) ?? Colors.white,
      bold: (json['bold'] as bool?) ?? true,
      italic: (json['italic'] as bool?) ?? false,
      align: _alignFromString(json['align'] as String?),
      outlined: (json['outlined'] as bool?) ?? true,
      editable: (json['editable'] as bool?) ?? false,
      promptLabelText: json['promptLabel'] as String?,
    );
  }
}

class HyperlinkLayerTemplate extends LayerTemplate {
  const HyperlinkLayerTemplate({
    required super.id,
    super.name,
    super.position = const Offset(0.5, 0.92),
    super.size = const Size(0.9, 0.08),
    super.rotation,
    super.opacity,
    this.url = '',
    this.label = '',
    this.fontFamily = 'Roboto',
    this.fontSize = 0.04,
    this.color = const Color(0xFF4FB6FF),
    this.bold = false,
    this.italic = false,
    this.align = LayerTextAlign.center,
    this.editable = true,
    this.promptLabelText,
  });

  final String url;
  final String label;
  final String fontFamily;
  final double fontSize;
  final Color color;
  final bool bold;
  final bool italic;
  final LayerTextAlign align;

  final bool editable;
  final String? promptLabelText;

  @override
  String get kind => 'hyperlink';

  @override
  bool get isEditable => editable;

  @override
  String? get promptLabel => promptLabelText;

  @override
  Layer instantiate({
    required String runtimeId,
    required Map<String, String> textValues,
    required Map<String, Uint8List> imageValues,
    required Uint8List placeholderImageBytes,
  }) {
    // Editable hyperlinks accept a value of the form "label|url" so we can
    // round-trip a single wizard field; if it omits the pipe we treat the
    // whole value as the URL and reuse the template's label.
    final String? overrideText = textValues[id];
    String effectiveUrl = url;
    String effectiveLabel = label;
    if (overrideText != null) {
      if (overrideText.contains('|')) {
        final List<String> parts = overrideText.split('|');
        effectiveLabel = parts[0];
        effectiveUrl = parts.sublist(1).join('|');
      } else {
        effectiveUrl = overrideText;
      }
    }
    return HyperlinkLayer(
      id: runtimeId,
      name: name ?? (editable ? (promptLabelText ?? 'Link') : 'Link'),
      position: position,
      size: size,
      rotation: rotation,
      opacity: opacity,
      url: effectiveUrl,
      label: effectiveLabel,
      fontFamily: fontFamily,
      fontSize: fontSize,
      color: color,
      bold: bold,
      italic: italic,
      align: align,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': 'hyperlink',
    'id': id,
    if (name != null) 'name': name,
    'position': _offsetToJson(position),
    'size': _sizeToJson(size),
    if (rotation != 0) 'rotation': rotation,
    if (opacity != 1.0) 'opacity': opacity,
    'url': url,
    'label': label,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'color': _colorToHex(color),
    'bold': bold,
    'italic': italic,
    'align': _alignToString(align),
    if (editable) 'editable': true,
    if (promptLabelText != null) 'promptLabel': promptLabelText,
  };

  factory HyperlinkLayerTemplate.fromJson(Map<String, dynamic> json) {
    return HyperlinkLayerTemplate(
      id: (json['id'] as String?) ?? 'link',
      name: json['name'] as String?,
      position: _offsetFromJson(json['position']) ?? const Offset(0.5, 0.92),
      size: _sizeFromJson(json['size']) ?? const Size(0.9, 0.08),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      url: (json['url'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      fontFamily: (json['fontFamily'] as String?) ?? 'Roboto',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 0.04,
      color: _colorFromHex(json['color'] as String?) ?? const Color(0xFF4FB6FF),
      bold: (json['bold'] as bool?) ?? false,
      italic: (json['italic'] as bool?) ?? false,
      align: _alignFromString(json['align'] as String?),
      editable: (json['editable'] as bool?) ?? true,
      promptLabelText: json['promptLabel'] as String?,
    );
  }
}

/// A template image layer. When [slot] is true, the wizard prompts the user
/// to pick an image; until they do, [placeholderImageBytes] is used so the
/// preview / gallery thumbnail stays visually meaningful.
class ImageLayerTemplate extends LayerTemplate {
  const ImageLayerTemplate({
    required super.id,
    super.name,
    super.position,
    super.size = const Size(0.6, 0.6),
    super.rotation,
    super.opacity,
    this.slot = true,
    this.promptLabelText,
  });

  /// True when the user is expected to provide an image during the wizard.
  /// Always true in practice for now — we don't bundle binary template
  /// images — but kept explicit so future bundled-image templates can opt out.
  final bool slot;

  final String? promptLabelText;

  @override
  String get kind => 'image';

  /// Image slots show up in [MemeTemplate.imageSlots], not [editableLayers].
  @override
  bool get isEditable => false;

  @override
  String? get promptLabel => promptLabelText;

  @override
  Layer instantiate({
    required String runtimeId,
    required Map<String, String> textValues,
    required Map<String, Uint8List> imageValues,
    required Uint8List placeholderImageBytes,
  }) {
    final Uint8List? user = imageValues[id];
    final Uint8List bytes = user ?? placeholderImageBytes;
    return ImageLayer(
      id: runtimeId,
      name: name ?? (promptLabelText ?? 'Image'),
      position: position,
      size: size,
      rotation: rotation,
      opacity: opacity,
      bytes: bytes,
      originalBytes: bytes,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': 'image',
    'id': id,
    if (name != null) 'name': name,
    'position': _offsetToJson(position),
    'size': _sizeToJson(size),
    if (rotation != 0) 'rotation': rotation,
    if (opacity != 1.0) 'opacity': opacity,
    'slot': slot,
    if (promptLabelText != null) 'promptLabel': promptLabelText,
  };

  factory ImageLayerTemplate.fromJson(Map<String, dynamic> json) {
    return ImageLayerTemplate(
      id: (json['id'] as String?) ?? 'image',
      name: json['name'] as String?,
      position: _offsetFromJson(json['position']) ?? const Offset(0.5, 0.5),
      size: _sizeFromJson(json['size']) ?? const Size(0.6, 0.6),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      slot: (json['slot'] as bool?) ?? true,
      promptLabelText: json['promptLabel'] as String?,
    );
  }
}

class CalloutLayerTemplate extends LayerTemplate {
  const CalloutLayerTemplate({
    required super.id,
    super.name,
    super.position,
    super.size = const Size(0.45, 0.18),
    super.rotation,
    super.opacity,
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
    this.editable = true,
    this.promptLabelText,
  });

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
  final Offset tailTarget;
  final bool showTail;

  final bool editable;
  final String? promptLabelText;

  @override
  String get kind => 'callout';

  @override
  bool get isEditable => editable;

  @override
  String? get promptLabel => promptLabelText;

  @override
  Layer instantiate({
    required String runtimeId,
    required Map<String, String> textValues,
    required Map<String, Uint8List> imageValues,
    required Uint8List placeholderImageBytes,
  }) {
    return CalloutLayer(
      id: runtimeId,
      name: name ?? (editable ? (promptLabelText ?? 'Callout') : 'Callout'),
      position: position,
      size: size,
      rotation: rotation,
      opacity: opacity,
      shape: shape,
      text: textValues[id] ?? text,
      fillColor: fillColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
      textColor: textColor,
      fontFamily: fontFamily,
      fontSize: fontSize,
      bold: bold,
      italic: italic,
      tailTarget: tailTarget,
      showTail: showTail,
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': 'callout',
    'id': id,
    if (name != null) 'name': name,
    'position': _offsetToJson(position),
    'size': _sizeToJson(size),
    if (rotation != 0) 'rotation': rotation,
    if (opacity != 1.0) 'opacity': opacity,
    'shape': _calloutKindToString(shape),
    'text': text,
    'fillColor': _colorToHex(fillColor),
    'borderColor': _colorToHex(borderColor),
    'borderWidth': borderWidth,
    'textColor': _colorToHex(textColor),
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'bold': bold,
    'italic': italic,
    'tailTarget': _offsetToJson(tailTarget),
    'showTail': showTail,
    if (editable) 'editable': true,
    if (promptLabelText != null) 'promptLabel': promptLabelText,
  };

  factory CalloutLayerTemplate.fromJson(Map<String, dynamic> json) {
    return CalloutLayerTemplate(
      id: (json['id'] as String?) ?? 'callout',
      name: json['name'] as String?,
      position: _offsetFromJson(json['position']) ?? const Offset(0.5, 0.35),
      size: _sizeFromJson(json['size']) ?? const Size(0.45, 0.18),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      shape: _calloutKindFromString(json['shape'] as String?),
      text: (json['text'] as String?) ?? '',
      fillColor: _colorFromHex(json['fillColor'] as String?) ?? Colors.white,
      borderColor:
          _colorFromHex(json['borderColor'] as String?) ??
          const Color(0xFF222222),
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 1.5,
      textColor: _colorFromHex(json['textColor'] as String?) ?? Colors.black,
      fontFamily: (json['fontFamily'] as String?) ?? 'Roboto',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 0.045,
      bold: (json['bold'] as bool?) ?? false,
      italic: (json['italic'] as bool?) ?? false,
      tailTarget:
          _offsetFromJson(json['tailTarget']) ?? const Offset(0.5, 0.85),
      showTail: (json['showTail'] as bool?) ?? true,
      editable: (json['editable'] as bool?) ?? true,
      promptLabelText: json['promptLabel'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// JSON conversion helpers
// ---------------------------------------------------------------------------

String _colorToHex(Color c) {
  final int v = c.toARGB32();
  return '#${v.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

Color? _colorFromHex(String? s) {
  if (s == null || s.isEmpty) return null;
  String hex = s.replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final int? v = int.tryParse(hex, radix: 16);
  if (v == null) return null;
  return Color(v);
}

List<double> _offsetToJson(Offset o) => <double>[o.dx, o.dy];
Offset? _offsetFromJson(dynamic raw) {
  if (raw is! List || raw.length < 2) return null;
  final double dx = (raw[0] as num).toDouble();
  final double dy = (raw[1] as num).toDouble();
  return Offset(dx, dy);
}

List<double> _sizeToJson(Size s) => <double>[s.width, s.height];
Size? _sizeFromJson(dynamic raw) {
  if (raw is! List || raw.length < 2) return null;
  final double w = (raw[0] as num).toDouble();
  final double h = (raw[1] as num).toDouble();
  return Size(w, h);
}

String _alignToString(LayerTextAlign a) {
  switch (a) {
    case LayerTextAlign.left:
      return 'left';
    case LayerTextAlign.center:
      return 'center';
    case LayerTextAlign.right:
      return 'right';
  }
}

LayerTextAlign _alignFromString(String? s) {
  switch (s) {
    case 'left':
      return LayerTextAlign.left;
    case 'right':
      return LayerTextAlign.right;
    case 'center':
    default:
      return LayerTextAlign.center;
  }
}

String _calloutKindToString(CalloutKind k) {
  switch (k) {
    case CalloutKind.speechRound:
      return 'speechRound';
    case CalloutKind.speechSharp:
      return 'speechSharp';
    case CalloutKind.thoughtCloud:
      return 'thoughtCloud';
    case CalloutKind.rectangle:
      return 'rectangle';
    case CalloutKind.oval:
      return 'oval';
    case CalloutKind.scallop:
      return 'scallop';
  }
}

CalloutKind _calloutKindFromString(String? s) {
  switch (s) {
    case 'speechSharp':
      return CalloutKind.speechSharp;
    case 'thoughtCloud':
      return CalloutKind.thoughtCloud;
    case 'rectangle':
      return CalloutKind.rectangle;
    case 'oval':
      return CalloutKind.oval;
    case 'scallop':
      return CalloutKind.scallop;
    case 'speechRound':
    default:
      return CalloutKind.speechRound;
  }
}

String _aspectToString(CanvasAspect a) {
  switch (a) {
    case CanvasAspect.square:
      return 'square';
    case CanvasAspect.portrait4x5:
      return 'portrait4x5';
    case CanvasAspect.story9x16:
      return 'story9x16';
    case CanvasAspect.landscape16x9:
      return 'landscape16x9';
    case CanvasAspect.photo3x4:
      return 'photo3x4';
  }
}

CanvasAspect _aspectFromString(String? s) {
  switch (s) {
    case 'portrait4x5':
      return CanvasAspect.portrait4x5;
    case 'story9x16':
      return CanvasAspect.story9x16;
    case 'landscape16x9':
      return CanvasAspect.landscape16x9;
    case 'photo3x4':
      return CanvasAspect.photo3x4;
    case 'square':
    default:
      return CanvasAspect.square;
  }
}
