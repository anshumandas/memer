import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'layer.dart';
import 'meme_config.dart';

/// Holds the live editing state for a single meme and notifies the UI when
/// anything changes. Built on the framework's [ChangeNotifier] so the app
/// needs no extra state-management dependency.
class MemeController extends ChangeNotifier {
  MemeController([MemeConfig? initial]) {
    if (initial != null) {
      _config = initial;
    } else {
      // Seed with a single background layer so the canvas is never empty.
      _config = MemeConfig(layers: <Layer>[BackgroundLayer(id: _nextId('bg'))]);
    }
  }

  late MemeConfig _config;
  MemeConfig get config => _config;

  String? _selectedLayerId;
  String? get selectedLayerId => _selectedLayerId;

  int _idCounter = 0;
  String _nextId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  /// The currently selected layer, or null when nothing is selected.
  Layer? get selectedLayer {
    if (_selectedLayerId == null) return null;
    for (final Layer l in _config.layers) {
      if (l.id == _selectedLayerId) return l;
    }
    return null;
  }

  // -------------------------------------------------------------- canvas

  void setAspect(CanvasAspect aspect) {
    if (_config.aspect == aspect) return;
    _config = _config.copyWith(aspect: aspect);
    notifyListeners();
  }

  // -------------------------------------------------------------- layers

  /// Adds [layer] above all existing layers. Returns its id.
  String addLayer(Layer layer) {
    _config = _config.copyWith(layers: <Layer>[..._config.layers, layer]);
    _selectedLayerId = layer.id;
    notifyListeners();
    return layer.id;
  }

  String addTextLayer({String? text}) {
    return addLayer(TextLayer(id: _nextId('text'), text: text ?? 'New text'));
  }

  String addHyperlinkLayer({String? url}) {
    return addLayer(
      HyperlinkLayer(
        id: _nextId('link'),
        url: url ?? 'https://example.com',
        position: const Offset(0.5, 0.92),
      ),
    );
  }

  String addImageLayer(Uint8List bytes, {Uint8List? originalBytes}) {
    return addLayer(
      ImageLayer(
        id: _nextId('image'),
        bytes: bytes,
        originalBytes: originalBytes ?? bytes,
      ),
    );
  }

  String addCalloutLayer({CalloutKind shape = CalloutKind.speechRound}) {
    // Stagger new bubbles a little so they don't pile up exactly on top of
    // each other.
    final int existing = _config.layers.whereType<CalloutLayer>().length;
    final double jitter = (existing % 5) * 0.06;
    return addLayer(
      CalloutLayer(
        id: _nextId('callout'),
        shape: shape,
        position: Offset(0.5, 0.35 + jitter).clamp01(),
      ),
    );
  }

  void removeLayer(String id) {
    final Layer? target = _findLayer(id);
    if (target == null) return;
    // The background layer is structural — never let the user delete it
    // (the inspector hides the delete affordance, but defend the model too).
    if (target is BackgroundLayer) return;
    _config = _config.copyWith(
      layers: _config.layers.where((Layer l) => l.id != id).toList(),
    );
    if (_selectedLayerId == id) _selectedLayerId = null;
    notifyListeners();
  }

  /// Replace [id] with the layer returned by [update]. Use this for any
  /// per-layer edit so the controller can also re-emit notifications.
  void updateLayer(String id, Layer Function(Layer) update) {
    _config = _config.copyWith(
      layers: _config.layers
          .map((Layer l) => l.id == id ? update(l) : l)
          .toList(),
    );
    notifyListeners();
  }

  /// Move [id] to a new fractional position, clamped onto the canvas. Used
  /// by the drag handler in the selection overlay.
  void moveLayer(String id, Offset fractionalPosition) {
    updateLayer(id, (Layer l) {
      return l.copyWithBase(position: fractionalPosition.clamp01());
    });
  }

  void resizeLayer(String id, Size fractionalSize) {
    updateLayer(id, (Layer l) {
      return l.copyWithBase(size: fractionalSize.clamp01());
    });
  }

  void rotateLayer(String id, double radians) {
    updateLayer(id, (Layer l) => l.copyWithBase(rotation: radians));
  }

  void setOpacity(String id, double opacity) {
    updateLayer(id, (Layer l) => l.copyWithBase(opacity: opacity.clamp(0, 1)));
  }

  void setVisible(String id, bool visible) {
    updateLayer(id, (Layer l) => l.copyWithBase(visible: visible));
  }

  void setLocked(String id, bool locked) {
    updateLayer(id, (Layer l) => l.copyWithBase(locked: locked));
  }

  void rename(String id, String name) {
    updateLayer(id, (Layer l) => l.copyWithBase(name: name));
  }

  /// Move the layer currently at [from] to index [to] (both indices into
  /// [config.layers]). Reordering is how the user changes z-order.
  ///
  /// The background layer is pinned at index 0; attempts to move it or to
  /// drop another layer below it are silently no-ops.
  void reorder(int from, int to) {
    if (from == to) return;
    final List<Layer> list = List<Layer>.of(_config.layers);
    if (from < 0 || from >= list.length) return;
    if (to < 0 || to > list.length) return;
    final Layer moved = list[from];
    if (moved is BackgroundLayer) return;
    // Refuse to drop anything below the background layer at slot 0.
    if (list.isNotEmpty && list.first is BackgroundLayer && to == 0) {
      to = 1;
    }
    list.removeAt(from);
    // After removeAt, the destination index shifts by 1 if we removed from
    // before it.
    final int insertAt = to > from ? to - 1 : to;
    list.insert(insertAt.clamp(0, list.length), moved);
    _config = _config.copyWith(layers: list);
    notifyListeners();
  }

  void selectLayer(String? id) {
    if (_selectedLayerId == id) return;
    _selectedLayerId = id;
    notifyListeners();
  }

  void clearSelection() => selectLayer(null);

  Layer? _findLayer(String id) {
    for (final Layer l in _config.layers) {
      if (l.id == id) return l;
    }
    return null;
  }
}
