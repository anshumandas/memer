import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import '../models/meme_template.dart';

/// Loads bundled meme templates from `assets/templates/` and caches them.
///
/// Templates are tiny JSON files declared in `pubspec.yaml`. The service
/// also generates (once, lazily) a checkered placeholder PNG that
/// [ImageLayerTemplate] slots use until the user picks a real image, so the
/// gallery thumbnails and the wizard preview are never blank.
class TemplateService {
  TemplateService._();
  static final TemplateService instance = TemplateService._();

  /// Order matters — gallery shows them in this order so the most common
  /// formats float to the top.
  static const List<String> _assetFiles = <String>[
    'assets/templates/top_bottom.json',
    'assets/templates/drake.json',
    'assets/templates/distracted_boyfriend.json',
    'assets/templates/two_buttons.json',
    'assets/templates/expanding_brain.json',
    'assets/templates/change_my_mind.json',
    'assets/templates/side_by_side.json',
    'assets/templates/speech_bubble.json',
    'assets/templates/wojak_yelling.json',
    'assets/templates/quote_card.json',
  ];

  Future<List<MemeTemplate>>? _loadFuture;
  Uint8List? _placeholderBytes;

  /// Returns every bundled template (loaded and cached on first call).
  Future<List<MemeTemplate>> loadAll() {
    return _loadFuture ??= _loadAllImpl();
  }

  Future<List<MemeTemplate>> _loadAllImpl() async {
    final List<MemeTemplate> out = <MemeTemplate>[];
    for (final String path in _assetFiles) {
      try {
        final String raw = await rootBundle.loadString(path);
        final Map<String, dynamic> json =
            jsonDecode(raw) as Map<String, dynamic>;
        out.add(MemeTemplate.fromJson(json));
      } catch (e) {
        // Skip malformed/missing templates rather than crashing the gallery.
        // (Surfaced via assert in debug mode so authors notice.)
        assert(false, 'Failed to load template $path: $e');
      }
    }
    return out;
  }

  /// A 256x256 checkered PNG used wherever an image slot has no user image.
  /// Encoded synchronously on first access — `image` is pure Dart so this
  /// works on every platform without an isolate.
  Uint8List placeholderImage() {
    return _placeholderBytes ??= _buildPlaceholderImage();
  }

  Uint8List _buildPlaceholderImage() {
    const int size = 256;
    const int tile = 32;
    final img.Image image = img.Image(width: size, height: size);

    // Checkerboard so the slot reads as "transparent / unfilled" at a glance.
    final img.ColorRgb8 light = img.ColorRgb8(225, 228, 232);
    final img.ColorRgb8 dark = img.ColorRgb8(195, 200, 207);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final bool a = ((x ~/ tile) + (y ~/ tile)).isEven;
        image.setPixel(x, y, a ? light : dark);
      }
    }

    // Dashed-ish border so the slot edge is unmistakable.
    final img.ColorRgb8 border = img.ColorRgb8(120, 124, 130);
    img.drawRect(
      image,
      x1: 0,
      y1: 0,
      x2: size - 1,
      y2: size - 1,
      color: border,
      thickness: 4,
    );

    // Centered "+" glyph so the user knows it's a fillable slot.
    final img.ColorRgb8 plus = img.ColorRgb8(90, 95, 105);
    const int cx = size ~/ 2;
    const int cy = size ~/ 2;
    const int armLen = 36;
    const int armThick = 10;
    img.fillRect(
      image,
      x1: cx - armLen,
      y1: cy - armThick ~/ 2,
      x2: cx + armLen,
      y2: cy + armThick ~/ 2,
      color: plus,
    );
    img.fillRect(
      image,
      x1: cx - armThick ~/ 2,
      y1: cy - armLen,
      x2: cx + armThick ~/ 2,
      y2: cy + armLen,
      color: plus,
    );

    return Uint8List.fromList(img.encodePng(image));
  }
}
