// Web implementation of the image editor's crop / rotate / PNG-encode
// primitives.
//
// Why a separate file: in CanvasKit (Flutter web's default renderer) both
// `ui.Picture.toImage` and `ui.Image.toByteData(format: png)` are wrapped
// in Futures but actually run *synchronously* inside the Skia-WASM module
// on the JS main thread. A multi-megapixel PNG encode locks the browser
// tab for several seconds — that's the "hang" the user was seeing on the
// Apply crop / Apply rotate / Apply erasures buttons.
//
// The browser's native `HTMLCanvasElement.toBlob('image/png')` is genuinely
// asynchronous (it runs the PNG codec on a browser worker), so we route all
// the heavy work through a `<canvas>` element instead.
//
// `image_processor_default.dart` covers every non-web target with the same
// public API; conditional import in `image_processing_service.dart` picks
// between them.

import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:web/web.dart' as web;

/// Raw decoded pixels: tightly-packed RGBA8 in row-major order, plus the
/// image's pixel dimensions. Used by the magic-wand flood fill (decoded
/// once per source image and cached).
///
/// Modelled as a record so the type is structural across the
/// `image_processor_default.dart` / `image_processor_web.dart` split — both
/// expose the same shape without sharing a class declaration.
typedef RawRgba = ({Uint8List bytes, int width, int height});

Future<Uint8List> cropPng(Uint8List bytes, Rect srcFractional) async {
  final web.HTMLImageElement image = await _loadImage(bytes);
  final int sw = image.naturalWidth;
  final int sh = image.naturalHeight;
  final int x = (srcFractional.left * sw).round().clamp(0, sw);
  final int y = (srcFractional.top * sh).round().clamp(0, sh);
  final int w = (srcFractional.width * sw).round().clamp(1, sw - x);
  final int h = (srcFractional.height * sh).round().clamp(1, sh - y);
  final (web.HTMLCanvasElement canvas, web.CanvasRenderingContext2D ctx) =
      _makeCanvas(w, h);
  // 9-arg drawImage: source rect (sx, sy, sw, sh) → dest rect (dx, dy, dw, dh).
  ctx.drawImage(
    image,
    x.toDouble(),
    y.toDouble(),
    w.toDouble(),
    h.toDouble(),
    0,
    0,
    w.toDouble(),
    h.toDouble(),
  );
  return _canvasToPngBytes(canvas);
}

Future<Uint8List> rotateAnyPng(Uint8List bytes, double degrees) async {
  final web.HTMLImageElement image = await _loadImage(bytes);
  final double sw = image.naturalWidth.toDouble();
  final double sh = image.naturalHeight.toDouble();
  final double rad = degrees * math.pi / 180;
  // Snap FP residuals at multiples of 90° so a 90/180/270 rotation produces
  // exact integer dimensions instead of e.g. 41 px due to cos(π/2) ≈ 6e-17.
  double cosA = math.cos(rad).abs();
  double sinA = math.sin(rad).abs();
  if (cosA < 1e-10) cosA = 0;
  if (sinA < 1e-10) sinA = 0;
  final int newW = (sw * cosA + sh * sinA).ceil();
  final int newH = (sw * sinA + sh * cosA).ceil();
  final (web.HTMLCanvasElement canvas, web.CanvasRenderingContext2D ctx) =
      _makeCanvas(newW, newH);
  ctx
    ..translate(newW / 2, newH / 2)
    ..rotate(rad)
    ..translate(-sw / 2, -sh / 2)
    ..drawImage(image, 0, 0);
  return _canvasToPngBytes(canvas);
}

/// Encode an already-rendered [ui.Image] as PNG. Uses the browser canvas
/// for the actual compression so we don't block the main thread.
///
/// `toByteData(rawRgba)` is a single memcpy out of the Skia surface and runs
/// in negligible time even for large images; the slow part — DEFLATE +
/// CRC32 for PNG — happens inside the browser's `toBlob` worker.
Future<Uint8List> encodeUiImageAsPng(ui.Image image) async {
  final ByteData? raw = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (raw == null) {
    throw StateError('Could not read rawRgba bytes from the rendered image.');
  }
  final int w = image.width;
  final int h = image.height;
  final (web.HTMLCanvasElement canvas, web.CanvasRenderingContext2D ctx) =
      _makeCanvas(w, h);
  final Uint8ClampedList clamped = raw.buffer.asUint8ClampedList(
    raw.offsetInBytes,
    raw.lengthInBytes,
  );
  // `package:web`'s ImageData binding takes (data, sw) — the height is
  // inferred from `data.length / (sw * 4)`.
  final web.ImageData imageData = web.ImageData(clamped.toJS, w);
  ctx.putImageData(imageData, 0, 0);
  return _canvasToPngBytes(canvas);
}

/// Decode [bytes] into raw RGBA8 pixels via the browser's native PNG/JPG
/// decoder. Orders of magnitude faster than `package:image` on web because
/// the compiled-to-JS pure-Dart decoder is slow; here we hand the work to
/// the browser and just `getImageData` the result.
Future<RawRgba> decodeRawRgba(Uint8List bytes) async {
  final web.HTMLImageElement image = await _loadImage(bytes);
  final int w = image.naturalWidth;
  final int h = image.naturalHeight;
  final (web.HTMLCanvasElement canvas, web.CanvasRenderingContext2D ctx) =
      _makeCanvas(w, h);
  ctx.drawImage(image, 0, 0);
  final web.ImageData data = ctx.getImageData(0, 0, w, h);
  // `data.data` is a Uint8ClampedArray; copy into a Uint8List so we own a
  // tight typed buffer (the JS-backed clamped view is fine to read but
  // mismatches the BFS code's Uint8List signature).
  final Uint8ClampedList clamped = data.data.toDart;
  return (bytes: Uint8List.fromList(clamped), width: w, height: h);
}

// ============================================================ helpers

(web.HTMLCanvasElement, web.CanvasRenderingContext2D) _makeCanvas(
  int w,
  int h,
) {
  final web.HTMLCanvasElement canvas =
      web.document.createElement('canvas') as web.HTMLCanvasElement
        ..width = w
        ..height = h;
  final web.CanvasRenderingContext2D ctx =
      canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  return (canvas, ctx);
}

/// Decode [bytes] into an off-DOM `<img>` element via a Blob URL. The image
/// is never attached to the page — we only need its pixels for the canvas.
Future<web.HTMLImageElement> _loadImage(Uint8List bytes) async {
  final web.Blob blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final String url = web.URL.createObjectURL(blob);
  final web.HTMLImageElement img =
      web.document.createElement('img') as web.HTMLImageElement;
  final Completer<void> done = Completer<void>();
  img.onload = ((web.Event _) {
    if (!done.isCompleted) done.complete();
  }).toJS;
  img.onerror = ((web.Event _) {
    if (!done.isCompleted) {
      done.completeError(StateError('Browser failed to decode the image.'));
    }
  }).toJS;
  img.src = url;
  try {
    await done.future;
  } finally {
    web.URL.revokeObjectURL(url);
  }
  return img;
}

/// Encode [canvas] as a PNG. `toBlob` hands the encode to a browser worker
/// (off the JS main thread), so even large images don't freeze the UI.
Future<Uint8List> _canvasToPngBytes(web.HTMLCanvasElement canvas) async {
  final Completer<Uint8List> done = Completer<Uint8List>();
  canvas.toBlob(
    ((web.Blob? blob) {
      if (blob == null) {
        done.completeError(StateError('canvas.toBlob returned null.'));
        return;
      }
      blob.arrayBuffer().toDart.then((JSArrayBuffer ab) {
        done.complete(ab.toDart.asUint8List());
      });
    }).toJS,
    'image/png',
  );
  return done.future;
}
