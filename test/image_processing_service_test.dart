import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memer/services/image_processing_service.dart';

void main() {
  const ImageProcessingService svc = ImageProcessingService();

  /// Build a deterministic test PNG: a 60×40 image, left half red, right
  /// half blue. Used to exercise crop and flood-fill without depending on
  /// any external assets.
  Uint8List makeTwoTonePng() {
    final img.Image i = img.Image(width: 60, height: 40);
    for (int y = 0; y < 40; y++) {
      for (int x = 0; x < 60; x++) {
        if (x < 30) {
          i.setPixelRgba(x, y, 255, 0, 0, 255);
        } else {
          i.setPixelRgba(x, y, 0, 0, 255, 255);
        }
      }
    }
    return Uint8List.fromList(img.encodePng(i));
  }

  test('cropPng returns an image of the expected dimensions', () async {
    final Uint8List src = makeTwoTonePng();
    final Uint8List cropped = await svc.cropPng(
      src,
      const Rect.fromLTRB(0.0, 0.0, 0.5, 1.0), // left half — red region
    );
    final img.Image? out = img.decodePng(cropped);
    expect(out, isNotNull);
    expect(out!.width, 30);
    expect(out.height, 40);
    final img.Pixel topLeft = out.getPixel(0, 0);
    expect(topLeft.r.toInt(), 255);
    expect(topLeft.b.toInt(), 0);
  });

  test('rotateQuarterPng 90° swaps width and height', () async {
    final Uint8List src = makeTwoTonePng(); // 60 × 40
    final Uint8List rotated = await svc.rotateQuarterPng(src, 1);
    final img.Image? out = img.decodePng(rotated);
    expect(out, isNotNull);
    expect(out!.width, 40);
    expect(out.height, 60);
  });

  test('rotateQuarterPng with 0 quarters is a no-op', () async {
    final Uint8List src = makeTwoTonePng();
    final Uint8List rotated = await svc.rotateQuarterPng(src, 0);
    // No-op should return the same bytes reference.
    expect(identical(src, rotated), isTrue);
  });

  test('floodFill selects only the same-coloured region', () async {
    final Uint8List src = makeTwoTonePng();
    // Seed inside the red region.
    final FloodMask m = await svc.floodFill(src, 5, 5, tolerance: 10);
    expect(m.width, 60);
    expect(m.height, 40);
    // Pixel at (5, 5) is selected.
    expect(m.bytes[5 * 60 + 5], 255);
    // Pixel at (45, 5) sits in the blue half — should not be selected.
    expect(m.bytes[5 * 60 + 45], 0);
  });

  test('intrinsicSize returns the PNG dimensions', () async {
    final Uint8List src = makeTwoTonePng();
    final Size size = await svc.intrinsicSize(src);
    expect(size.width, 60);
    expect(size.height, 40);
  });
}
