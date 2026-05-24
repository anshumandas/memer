import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// Platform-specific "save to disk / download" implementation. The default
// (native) version uses a file_selector save dialog; the web version triggers
// a browser download. Conditional import keeps `dart:html` out of native
// builds and `file_selector`'s unsupported-on-web save path out of web builds.
import 'platform_saver_default.dart'
    if (dart.library.html) 'platform_saver_web.dart'
    as saver;

/// Turns the on-screen meme into PNG bytes and (optionally) writes them out.
/// Pure client-side — nothing leaves the device unless the user shares it.
class ImageExportService {
  const ImageExportService();

  /// Renders the widget behind [repaintKey] to PNG bytes.
  ///
  /// The output is scaled so its width is roughly [targetWidth] pixels,
  /// regardless of how big the editor canvas is on screen, giving a
  /// consistent, high-resolution export everywhere.
  Future<Uint8List> capturePng(
    GlobalKey repaintKey, {
    double targetWidth = 1080,
  }) async {
    final BuildContext? ctx = repaintKey.currentContext;
    if (ctx == null) {
      throw StateError('Meme canvas is not currently on screen.');
    }
    final RenderObject? object = ctx.findRenderObject();
    if (object is! RenderRepaintBoundary) {
      throw StateError('Meme canvas render object was not found.');
    }

    // In debug builds the boundary can still need a paint on the very first
    // frame; wait one frame rather than throwing.
    if (object.debugNeedsPaint) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    final double logicalWidth = object.size.width;
    final double pixelRatio = logicalWidth <= 0
        ? 3.0
        : (targetWidth / logicalWidth).clamp(1.0, 6.0);

    final ui.Image image = await object.toImage(pixelRatio: pixelRatio);
    try {
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (data == null) {
        throw StateError('Failed to encode the meme as PNG.');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Saves [bytes] as a PNG.
  ///
  /// On native platforms this opens a "save file" dialog and returns the
  /// chosen path (or `null` if cancelled). On the web it triggers a download
  /// and returns the file name.
  Future<String?> savePngToDisk(
    Uint8List bytes, {
    String suggestedName = 'meme.png',
  }) {
    return saver.savePng(bytes, suggestedName);
  }
}
