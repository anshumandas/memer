// Native (non-web) implementation of the image editor's crop / rotate /
// PNG-encode primitives.
//
// On native (Windows, macOS, Linux, Android, iOS) the Flutter engine runs
// Skia natively and `ui.Image.toByteData(png)` truly offloads work to an
// engine thread, so we just drive `ui.Canvas` and the built-in PNG encoder.
//
// On the web this file is replaced by `image_processor_web.dart` via the
// conditional import in `image_processing_service.dart` — see that file for
// why we have to go through `HTMLCanvasElement.toBlob` there.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// Raw decoded pixels: tightly-packed RGBA8 in row-major order, plus the
/// image's pixel dimensions. Used by the magic-wand flood fill (decoded
/// once per source image and cached).
///
/// Modelled as a record so the type is structural across the
/// `image_processor_default.dart` / `image_processor_web.dart` split — both
/// expose the same shape without sharing a class declaration.
typedef RawRgba = ({Uint8List bytes, int width, int height});

Future<Uint8List> cropPng(Uint8List bytes, Rect srcFractional) async {
  final ui.Image source = await _decode(bytes);
  try {
    final int sw = source.width;
    final int sh = source.height;
    final int x = (srcFractional.left * sw).round().clamp(0, sw);
    final int y = (srcFractional.top * sh).round().clamp(0, sh);
    final int w = (srcFractional.width * sw).round().clamp(1, sw - x);
    final int h = (srcFractional.height * sh).round().clamp(1, sh - y);
    return _renderToPng(w, h, (Canvas canvas) {
      canvas.drawImageRect(
        source,
        Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()),
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
    });
  } finally {
    source.dispose();
  }
}

Future<Uint8List> rotateAnyPng(Uint8List bytes, double degrees) async {
  final ui.Image source = await _decode(bytes);
  try {
    final double sw = source.width.toDouble();
    final double sh = source.height.toDouble();
    final double rad = degrees * math.pi / 180;
    // Snap FP residuals at multiples of 90° so a 90/180/270 rotation produces
    // exact integer dimensions instead of e.g. 41 px due to cos(π/2) ≈ 6e-17.
    double cosA = math.cos(rad).abs();
    double sinA = math.sin(rad).abs();
    if (cosA < 1e-10) cosA = 0;
    if (sinA < 1e-10) sinA = 0;
    final int newW = (sw * cosA + sh * sinA).ceil();
    final int newH = (sw * sinA + sh * cosA).ceil();
    return _renderToPng(newW, newH, (Canvas canvas) {
      canvas.translate(newW / 2, newH / 2);
      canvas.rotate(rad);
      canvas.translate(-sw / 2, -sh / 2);
      canvas.drawImage(
        source,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );
    });
  } finally {
    source.dispose();
  }
}

/// Encode an already-rendered [ui.Image] as PNG. On native this is the
/// engine's built-in encoder (runs on an engine thread). The web sibling
/// pipes raw RGBA through a browser canvas + `toBlob` instead.
Future<Uint8List> encodeUiImageAsPng(ui.Image image) async {
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('Could not encode the rendered image as PNG.');
  }
  return data.buffer.asUint8List();
}

/// Decode [bytes] into raw RGBA8 pixels — the format the magic-wand BFS
/// reads from. Runs in a background isolate via `compute`. The web sibling
/// uses the browser's native PNG decoder (much faster than pure-Dart on JS).
Future<RawRgba> decodeRawRgba(Uint8List bytes) {
  return compute(_decodeRawRgbaIsolate, bytes);
}

RawRgba _decodeRawRgbaIsolate(Uint8List bytes) {
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return (bytes: Uint8List(0), width: 0, height: 0);
  }
  final img.Image normalised =
      (decoded.numChannels == 4 && decoded.format == img.Format.uint8)
      ? decoded
      : decoded.convert(numChannels: 4, format: img.Format.uint8);
  return (
    bytes: Uint8List.fromList(normalised.getBytes()),
    width: normalised.width,
    height: normalised.height,
  );
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  return frame.image;
}

Future<Uint8List> _renderToPng(
  int width,
  int height,
  void Function(Canvas) paint,
) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  paint(canvas);
  final ui.Picture picture = recorder.endRecording();
  final ui.Image rendered = await picture.toImage(width, height);
  picture.dispose();
  try {
    return await encodeUiImageAsPng(rendered);
  } finally {
    rendered.dispose();
  }
}
