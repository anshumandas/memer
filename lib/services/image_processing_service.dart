import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/painting.dart';

// Platform split for the slow paths (crop, rotate, PNG encode).
//
// Native: drive `ui.Canvas` and use the engine's PNG encoder — work runs on
// engine threads, doesn't block the Dart isolate.
//
// Web: drive an `HTMLCanvasElement` and use `canvas.toBlob`. CanvasKit's
// `picture.toImage` and `image.toByteData(png)` *look* async but run
// synchronously inside the Skia-WASM module on the JS main thread, which
// freezes the browser for any sizable image. `toBlob` runs on a browser
// worker, so the UI thread stays responsive.
import 'image_processor_default.dart'
    if (dart.library.html) 'image_processor_web.dart'
    as processor;

// Re-export the platform-agnostic types from the processor so callers can
// hold a [RawRgba] without importing the platform-split file themselves.
// `RawRgba` is a record typedef so the structural shape is identical across
// both impls — re-exporting is just a naming convenience.
export 'image_processor_default.dart' show RawRgba;

/// One contiguous region selected by the magic-wand tool, expressed as a
/// single-channel mask. Width/height match the *source image's* pixel
/// dimensions, not the on-screen canvas. A value of 255 means "erase this
/// pixel"; 0 means "leave it alone".
class FloodMask {
  const FloodMask({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Pure-Dart, cross-platform image manipulation used by the image editor:
/// crop, 90° rotate, magic-wand flood fill, and baking brush erasures +
/// flood masks into a final transparent PNG.
///
/// Crop / rotate run on the main isolate (one-shot, cheap). The magic-wand
/// flood fill walks every connected pixel and can hit millions of nodes on
/// a multi-megapixel image, so it is dispatched to a background isolate via
/// [compute] to keep the UI responsive.
class ImageProcessingService {
  const ImageProcessingService();

  /// Decode just enough of a PNG/JPG/etc. to learn its intrinsic size.
  Future<Size> intrinsicSize(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    final Size size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    return size;
  }

  /// Decode [bytes] into a [ui.Image] (kept resident for fast drawing in
  /// the editor canvas).
  Future<ui.Image> decodeUiImage(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Crop [bytes] by a fractional source rect (each component 0..1). Returns
  /// a fresh PNG. Delegates to the platform-specific processor (see the
  /// `processor` import at the top of this file).
  Future<Uint8List> cropPng(Uint8List bytes, Rect srcFractional) {
    return processor.cropPng(bytes, srcFractional);
  }

  /// Rotate [bytes] by [quarters] × 90° clockwise.
  Future<Uint8List> rotateQuarterPng(Uint8List bytes, int quarters) {
    final int q = quarters % 4;
    if (q == 0) return Future<Uint8List>.value(bytes);
    return processor.rotateAnyPng(bytes, q * 90.0);
  }

  /// Rotate [bytes] by an arbitrary [degrees] (clockwise positive). The output
  /// PNG's canvas grows so the rotated source fits without clipping; the new
  /// corners are transparent.
  Future<Uint8List> rotateAnyPng(Uint8List bytes, double degrees) {
    final double normalized = degrees % 360;
    if (normalized.abs() < 0.01) return Future<Uint8List>.value(bytes);
    return processor.rotateAnyPng(bytes, normalized);
  }

  /// Decode [bytes] into raw RGBA pixels — the format the flood fill reads.
  /// Hot callers (the wand) should call this once and reuse the result via
  /// [floodFillRgba] instead of re-decoding on every tap.
  Future<processor.RawRgba> decodeRawRgba(Uint8List bytes) =>
      processor.decodeRawRgba(bytes);

  /// Flood-fill over already-decoded RGBA pixels. The expensive PNG decode
  /// is the caller's job — this lets the wand reuse one decode across many
  /// taps. See [floodFill] for tolerance semantics.
  Future<FloodMask> floodFillRgba(
    processor.RawRgba rgba,
    int seedX,
    int seedY, {
    int tolerance = 60,
  }) async {
    final Uint8List mask = await compute(_floodFillRgbaIsolate, (
      rgba.bytes,
      rgba.width,
      rgba.height,
      seedX,
      seedY,
      tolerance,
    ));
    return FloodMask(bytes: mask, width: rgba.width, height: rgba.height);
  }

  /// Flood-fill from [seed] using a colour-similarity tolerance.
  ///
  /// Two pixels are considered "similar" when the sum of their RGB channel
  /// differences is ≤ [tolerance] (0..765). The walk is BFS over 4-connected
  /// neighbours and stops at the image's edge.
  ///
  /// The returned [FloodMask] has the same dimensions as the source image
  /// (not the on-screen canvas) — paint/erase ops in the editor convert
  /// pointer positions into image pixels before invoking this.
  ///
  /// Convenience wrapper that decodes [bytes] each call. Hot paths (every
  /// wand tap on the same image) should instead call [decodeRawRgba] once
  /// and reuse via [floodFillRgba].
  Future<FloodMask> floodFill(
    Uint8List bytes,
    int seedX,
    int seedY, {
    int tolerance = 60,
  }) async {
    final processor.RawRgba rgba = await decodeRawRgba(bytes);
    return floodFillRgba(rgba, seedX, seedY, tolerance: tolerance);
  }

  /// Bake erasures (and any restore strokes) into the source image and
  /// return a transparent PNG.
  ///
  /// [erasePaths] are accumulated brush strokes expressed in **image-pixel
  /// coordinates**. Each path is filled with [Paint.blendMode] = `dstOut`
  /// over the source so the pixels under the path become transparent.
  ///
  /// [floodMasks] are individual flood-fill results (also in image pixels).
  /// Each is composited the same way using a single-channel image with the
  /// mask value as alpha.
  ///
  /// [restorePaths] are brush strokes that bring previously-erased pixels
  /// back. After all erasures have been applied, the source image is drawn
  /// again clipped to each restore path using [BlendMode.dstOver], which
  /// fills only the already-transparent regions.
  Future<Uint8List> applyErasures(
    Uint8List sourceBytes, {
    required List<Path> erasePaths,
    required List<FloodMask> floodMasks,
    List<Path> restorePaths = const <Path>[],
  }) async {
    final ui.Image source = await decodeUiImage(sourceBytes);
    final int w = source.width;
    final int h = source.height;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );

    // Use a saveLayer so the dstOut erase ops operate on the source image
    // and *only* that layer (otherwise they would also erase whatever is
    // already on the destination, which here is nothing — but the saveLayer
    // also gives Skia a clear bounding box to work in).
    final Paint clearPaint = Paint();
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      clearPaint,
    );

    canvas.drawImage(source, Offset.zero, Paint());

    final Paint erasePaint = Paint()..blendMode = BlendMode.dstOut;
    for (final Path p in erasePaths) {
      canvas.drawPath(p, erasePaint);
    }

    for (final FloodMask m in floodMasks) {
      if (m.bytes.isEmpty || m.width == 0 || m.height == 0) continue;
      final ui.Image maskImage = await _maskToImage(m);
      canvas.drawImage(maskImage, Offset.zero, erasePaint);
      maskImage.dispose();
    }

    if (restorePaths.isNotEmpty) {
      final Paint restorePaint = Paint()..blendMode = BlendMode.dstOver;
      for (final Path p in restorePaths) {
        canvas.save();
        canvas.clipPath(p);
        canvas.drawImage(source, Offset.zero, restorePaint);
        canvas.restore();
      }
    }

    canvas.restore();

    final ui.Picture picture = recorder.endRecording();
    final ui.Image rendered = await picture.toImage(w, h);
    picture.dispose();
    source.dispose();

    try {
      // Hand the PNG encode to the platform processor — on web that routes
      // through HTMLCanvasElement.toBlob so the JS main thread stays free.
      return await processor.encodeUiImageAsPng(rendered);
    } finally {
      rendered.dispose();
    }
  }

  /// Build a [ui.Image] whose alpha channel equals the flood-mask bytes
  /// (RGB stay 0). Used as an erase brush via [BlendMode.dstOut].
  Future<ui.Image> _maskToImage(FloodMask m) async {
    final Uint8List rgba = Uint8List(m.width * m.height * 4);
    for (int i = 0; i < m.bytes.length; i++) {
      rgba[i * 4 + 3] = m.bytes[i];
    }
    final Completer<ui.Image> c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      m.width,
      m.height,
      ui.PixelFormat.rgba8888,
      c.complete,
    );
    return c.future;
  }
}

/// Entry point for [ImageProcessingService.floodFillRgba]'s background
/// isolate. Operates on already-decoded RGBA8 pixels — the caller (typically
/// the wand cache) is responsible for the PNG decode.
///
/// Args: `(rgba, width, height, seedX, seedY, tolerance)`. Returns just the
/// mask bytes (caller already knows the dimensions).
Uint8List _floodFillRgbaIsolate((Uint8List, int, int, int, int, int) args) {
  final Uint8List pixels = args.$1;
  final int w = args.$2;
  final int h = args.$3;
  final int seedX = args.$4;
  final int seedY = args.$5;
  final int tolerance = args.$6;

  if (w == 0 || h == 0 || pixels.length < w * h * 4) {
    return Uint8List(w * h);
  }
  if (seedX < 0 || seedY < 0 || seedX >= w || seedY >= h) {
    return Uint8List(w * h);
  }

  final int seedOff = (seedY * w + seedX) * 4;
  final int sr = pixels[seedOff];
  final int sg = pixels[seedOff + 1];
  final int sb = pixels[seedOff + 2];

  final Uint8List mask = Uint8List(w * h);
  // Separate visited buffer so rejected pixels aren't retested from each
  // matched neighbour (used to inflate the BFS by ~4x).
  final Uint8List visited = Uint8List(w * h);
  final List<int> stack = <int>[seedY * w + seedX];
  mask[seedY * w + seedX] = 255;
  visited[seedY * w + seedX] = 1;

  while (stack.isNotEmpty) {
    final int idx = stack.removeLast();
    final int x = idx % w;
    final int y = idx ~/ w;
    // 4-connected neighbours, inlined to keep the hot loop tight.
    for (int n = 0; n < 4; n++) {
      final int nx = n == 0 ? x - 1 : (n == 1 ? x + 1 : x);
      final int ny = n == 2 ? y - 1 : (n == 3 ? y + 1 : y);
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      final int nIdx = ny * w + nx;
      if (visited[nIdx] != 0) continue;
      visited[nIdx] = 1;
      final int off = nIdx * 4;
      final int diff =
          (pixels[off] - sr).abs() +
          (pixels[off + 1] - sg).abs() +
          (pixels[off + 2] - sb).abs();
      if (diff <= tolerance) {
        mask[nIdx] = 255;
        stack.add(nIdx);
      }
    }
  }
  return mask;
}
