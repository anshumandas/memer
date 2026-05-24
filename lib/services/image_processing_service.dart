import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

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
  /// a fresh PNG. The output's RGB channels are copied verbatim; any alpha
  /// already present is preserved.
  Future<Uint8List> cropPng(Uint8List bytes, Rect srcFractional) async {
    final img.Image? src = img.decodeImage(bytes);
    if (src == null) return bytes;
    final int x = (srcFractional.left * src.width).round().clamp(0, src.width);
    final int y = (srcFractional.top * src.height).round().clamp(0, src.height);
    final int w = (srcFractional.width * src.width).round().clamp(
      1,
      src.width - x,
    );
    final int h = (srcFractional.height * src.height).round().clamp(
      1,
      src.height - y,
    );
    final img.Image cropped = img.copyCrop(
      src,
      x: x,
      y: y,
      width: w,
      height: h,
    );
    return Uint8List.fromList(img.encodePng(cropped));
  }

  /// Rotate [bytes] by [quarters] × 90° clockwise.
  Future<Uint8List> rotateQuarterPng(Uint8List bytes, int quarters) async {
    if (quarters % 4 == 0) return bytes;
    final img.Image? src = img.decodeImage(bytes);
    if (src == null) return bytes;
    final int angle = (quarters % 4) * 90;
    final img.Image rotated = img.copyRotate(src, angle: angle);
    return Uint8List.fromList(img.encodePng(rotated));
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
  /// Runs in a background isolate via [compute] so a multi-megapixel fill
  /// never blocks the UI thread.
  Future<FloodMask> floodFill(
    Uint8List bytes,
    int seedX,
    int seedY, {
    int tolerance = 60,
  }) async {
    final (Uint8List mask, int w, int h) = await compute(_floodFillIsolate, (
      bytes,
      seedX,
      seedY,
      tolerance,
    ));
    return FloodMask(bytes: mask, width: w, height: h);
  }

  /// Bake erasures into the source image and return a transparent PNG.
  ///
  /// [erasePaths] are accumulated brush strokes expressed in **image-pixel
  /// coordinates**. Each path is filled with [Paint.blendMode] = `dstOut`
  /// over the source so the pixels under the path become transparent.
  ///
  /// [floodMasks] are individual flood-fill results (also in image pixels).
  /// Each is composited the same way using a single-channel image with the
  /// mask value as alpha.
  Future<Uint8List> applyErasures(
    Uint8List sourceBytes, {
    required List<Path> erasePaths,
    required List<FloodMask> floodMasks,
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

    canvas.restore();

    final ui.Picture picture = recorder.endRecording();
    final ui.Image rendered = await picture.toImage(w, h);
    picture.dispose();
    source.dispose();

    final ByteData? png = await rendered.toByteData(
      format: ui.ImageByteFormat.png,
    );
    rendered.dispose();
    if (png == null) {
      throw StateError('Could not encode the edited image as PNG.');
    }
    return png.buffer.asUint8List();
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

/// Entry point for [ImageProcessingService.floodFill]'s background isolate.
///
/// Decodes the PNG, normalises to RGBA8 so we can read pixels via raw byte
/// indexing (the `image` package's `getPixel` is an order of magnitude slower
/// — it allocates a `Pixel` wrapper per call, which is what used to hang the
/// UI on big regions). Returns `(mask, width, height)` so the result can
/// cross the isolate boundary without depending on the [FloodMask] class.
(Uint8List, int, int) _floodFillIsolate((Uint8List, int, int, int) args) {
  final Uint8List bytes = args.$1;
  final int seedX = args.$2;
  final int seedY = args.$3;
  final int tolerance = args.$4;

  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) return (Uint8List(0), 0, 0);

  final img.Image src =
      (decoded.numChannels == 4 && decoded.format == img.Format.uint8)
      ? decoded
      : decoded.convert(numChannels: 4, format: img.Format.uint8);
  final int w = src.width;
  final int h = src.height;
  final Uint8List pixels = src.getBytes(); // flat RGBA, length = w*h*4

  if (seedX < 0 || seedY < 0 || seedX >= w || seedY >= h) {
    return (Uint8List(w * h), w, h);
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
  return (mask, w, h);
}
