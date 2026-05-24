import 'package:flutter/material.dart';

import 'layer.dart';

/// Supported canvas aspect ratios. The canvas is always defined as a width
/// fraction over a height fraction (e.g. 4:5 means height = width * 5/4).
///
/// Keeping a small enum (rather than free-form numbers) lets the layer
/// preview thumbnails and export targets share one source of truth.
enum CanvasAspect { square, portrait4x5, story9x16, landscape16x9, photo3x4 }

extension CanvasAspectX on CanvasAspect {
  double get ratio {
    // width / height
    switch (this) {
      case CanvasAspect.square:
        return 1.0;
      case CanvasAspect.portrait4x5:
        return 4 / 5;
      case CanvasAspect.story9x16:
        return 9 / 16;
      case CanvasAspect.landscape16x9:
        return 16 / 9;
      case CanvasAspect.photo3x4:
        return 3 / 4;
    }
  }

  String get label {
    switch (this) {
      case CanvasAspect.square:
        return '1:1';
      case CanvasAspect.portrait4x5:
        return '4:5';
      case CanvasAspect.story9x16:
        return '9:16';
      case CanvasAspect.landscape16x9:
        return '16:9';
      case CanvasAspect.photo3x4:
        return '3:4';
    }
  }
}

/// Immutable snapshot of a meme: an ordered list of [Layer]s plus the
/// canvas's aspect ratio.
///
/// Kept separate from the controller so it is trivially unit-testable and
/// could later be serialised to disk / JSON without touching UI code.
@immutable
class MemeConfig {
  const MemeConfig({
    this.aspect = CanvasAspect.square,
    this.layers = const <Layer>[],
  });

  /// The output canvas shape.
  final CanvasAspect aspect;

  /// Z-ordered list of layers; index 0 is the bottom layer (always the
  /// [BackgroundLayer] by convention — the controller enforces this).
  final List<Layer> layers;

  /// Returns the background layer, or null if none exists yet.
  BackgroundLayer? get background {
    for (final Layer l in layers) {
      if (l is BackgroundLayer) return l;
    }
    return null;
  }

  MemeConfig copyWith({CanvasAspect? aspect, List<Layer>? layers}) {
    return MemeConfig(
      aspect: aspect ?? this.aspect,
      layers: layers ?? this.layers,
    );
  }
}
