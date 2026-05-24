import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memer/models/layer.dart';
import 'package:memer/models/meme_config.dart';
import 'package:memer/models/meme_controller.dart';

void main() {
  group('MemeConfig defaults', () {
    test('controller seeds with a single background layer', () {
      final MemeController c = MemeController();
      expect(c.config.layers, hasLength(1));
      expect(c.config.layers.single, isA<BackgroundLayer>());
      expect(c.config.aspect, CanvasAspect.square);
    });

    test('aspect ratio mapping is correct', () {
      expect(CanvasAspect.square.ratio, closeTo(1.0, 1e-9));
      expect(CanvasAspect.portrait4x5.ratio, closeTo(0.8, 1e-9));
      expect(CanvasAspect.story9x16.ratio, closeTo(9 / 16, 1e-9));
    });
  });

  group('Layer copyWith', () {
    test('TextLayer copyWith preserves id and overrides fields', () {
      const TextLayer layer = TextLayer(id: 'a', text: 'hi');
      final TextLayer updated = layer.copyWith(text: 'bye', bold: false);
      expect(updated.id, 'a');
      expect(updated.text, 'bye');
      expect(updated.bold, isFalse);
    });

    test('BackgroundLayer.copyWithBase ignores position/size/rotation', () {
      const BackgroundLayer bg = BackgroundLayer(id: 'bg');
      final BackgroundLayer moved = bg.copyWithBase(
        position: const Offset(0.1, 0.1),
        size: const Size(0.3, 0.3),
        rotation: 1.0,
      );
      // Background is always full-bleed regardless of geometric edits.
      expect(moved.position, bg.position);
      expect(moved.size, bg.size);
      expect(moved.rotation, bg.rotation);
    });

    test(
      'CalloutLayer.shape uses CalloutKind, not the string discriminator',
      () {
        const CalloutLayer cl = CalloutLayer(
          id: 'c',
          shape: CalloutKind.thoughtCloud,
        );
        expect(cl.shape, CalloutKind.thoughtCloud);
        expect(cl.kind, 'callout'); // Layer-level string discriminator.
      },
    );
  });

  group('OffsetClamp / SizeClamp', () {
    test('clamp01 clamps both axes', () {
      const Offset out = Offset(2, -1);
      final Offset clamped = out.clamp01();
      expect(clamped.dx, 1.0);
      expect(clamped.dy, 0.0);
    });

    test('SizeClamp enforces a minimum side', () {
      const Size tiny = Size(0.001, 0.001);
      final Size clamped = tiny.clamp01();
      expect(clamped.width, greaterThan(0));
      expect(clamped.height, greaterThan(0));
    });
  });

  group('MemeController layer ops', () {
    test('addTextLayer appends and selects', () {
      final MemeController c = MemeController();
      final String id = c.addTextLayer(text: 'hello');
      expect(c.config.layers, hasLength(2)); // background + text
      expect(c.selectedLayerId, id);
      expect(c.selectedLayer, isA<TextLayer>());
    });

    test('removeLayer removes non-background and clears selection', () {
      final MemeController c = MemeController();
      final String id = c.addCalloutLayer();
      c.removeLayer(id);
      expect(c.config.layers.whereType<CalloutLayer>(), isEmpty);
      expect(c.selectedLayerId, isNull);
    });

    test('removeLayer refuses to delete the background', () {
      final MemeController c = MemeController();
      final BackgroundLayer bg = c.config.layers.first as BackgroundLayer;
      c.removeLayer(bg.id);
      expect(c.config.layers, contains(bg));
    });

    test('moveLayer clamps to the canvas', () {
      final MemeController c = MemeController();
      final String id = c.addCalloutLayer();
      c.moveLayer(id, const Offset(5, 5));
      expect(c.selectedLayer!.position.dx, 1.0);
      expect(c.selectedLayer!.position.dy, 1.0);
    });

    test('reorder respects the background pin', () {
      final MemeController c = MemeController();
      final String t1 = c.addTextLayer(text: 'a'); // layers = [bg, t1]
      c.addTextLayer(text: 'b'); // layers = [bg, t1, t2]
      // Try to send the background layer above everything — should be a no-op.
      c.reorder(0, 2);
      expect(c.config.layers.first, isA<BackgroundLayer>());
      // Move t1 (index 1) past t2 to the top — ReorderableListView semantics
      // mean "drop at index after the last item" = length (3 here).
      c.reorder(1, 3);
      expect(c.config.layers.last.id, t1);
    });

    test('setOpacity / setVisible / setLocked round-trip', () {
      final MemeController c = MemeController();
      final String id = c.addTextLayer();
      c.setOpacity(id, 0.5);
      c.setVisible(id, false);
      c.setLocked(id, true);
      final Layer l = c.config.layers.firstWhere((Layer x) => x.id == id);
      expect(l.opacity, 0.5);
      expect(l.visible, isFalse);
      expect(l.locked, isTrue);
    });

    test('notifies listeners when state changes', () {
      final MemeController c = MemeController();
      int n = 0;
      c.addListener(() => n++);
      c.addTextLayer(text: 'x');
      c.setAspect(CanvasAspect.story9x16);
      expect(n, 2);
    });

    test('image layer stores bytes', () {
      final MemeController c = MemeController();
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final String id = c.addImageLayer(bytes);
      final ImageLayer img =
          c.config.layers.firstWhere((Layer l) => l.id == id) as ImageLayer;
      expect(img.bytes, bytes);
      expect(img.originalBytes, bytes);
    });
  });

  group('HyperlinkLayer', () {
    test('displayText falls back to URL when label is blank', () {
      const HyperlinkLayer l = HyperlinkLayer(
        id: 'h',
        url: 'https://example.com',
      );
      expect(l.displayText, 'https://example.com');
    });

    test('displayText uses label when present', () {
      const HyperlinkLayer l = HyperlinkLayer(
        id: 'h',
        url: 'https://example.com',
        label: 'docs',
      );
      expect(l.displayText, 'docs');
    });
  });
}
