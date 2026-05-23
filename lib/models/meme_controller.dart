import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'callout.dart';
import 'meme_config.dart';

/// Holds the live editing state for a single meme and notifies the UI when
/// anything changes. Deliberately uses the built-in [ChangeNotifier] so the
/// app needs no extra state-management dependency.
class MemeController extends ChangeNotifier {
  MemeController([MemeConfig? initial])
      : _config = initial ?? const MemeConfig();

  MemeConfig _config;
  MemeConfig get config => _config;

  /// The currently selected callout (the one whose handles/editing controls
  /// are shown). `null` when nothing is selected.
  String? _selectedCalloutId;
  String? get selectedCalloutId => _selectedCalloutId;

  int _calloutCounter = 0;

  Callout? get selectedCallout {
    if (_selectedCalloutId == null) return null;
    for (final Callout c in _config.callouts) {
      if (c.id == _selectedCalloutId) return c;
    }
    return null;
  }

  // ---- background -------------------------------------------------------

  void setBackgroundColor(Color color) {
    _config = _config.copyWith(backgroundColor: color);
    notifyListeners();
  }

  void setBackgroundImage(Uint8List bytes) {
    _config = _config.copyWith(backgroundImage: bytes);
    notifyListeners();
  }

  void clearBackgroundImage() {
    _config = _config.copyWith(clearBackgroundImage: true);
    notifyListeners();
  }

  // ---- meme captions ----------------------------------------------------

  void setTopText(String value) {
    _config = _config.copyWith(topText: value);
    notifyListeners();
  }

  void setBottomText(String value) {
    _config = _config.copyWith(bottomText: value);
    notifyListeners();
  }

  void setMemeTextColor(Color color) {
    _config = _config.copyWith(memeTextColor: color);
    notifyListeners();
  }

  // ---- header / footnote / link ----------------------------------------

  void setHeaderText(String value) {
    _config = _config.copyWith(headerText: value);
    notifyListeners();
  }

  void setHeaderAlign(MemeTextAlign align) {
    _config = _config.copyWith(headerAlign: align);
    notifyListeners();
  }

  void setFootnoteText(String value) {
    _config = _config.copyWith(footnoteText: value);
    notifyListeners();
  }

  void setFootnoteAlign(MemeTextAlign align) {
    _config = _config.copyWith(footnoteAlign: align);
    notifyListeners();
  }

  void setLinkUrl(String value) {
    _config = _config.copyWith(linkUrl: value);
    notifyListeners();
  }

  void setLinkLabel(String value) {
    _config = _config.copyWith(linkLabel: value);
    notifyListeners();
  }

  void setLinkAlign(MemeTextAlign align) {
    _config = _config.copyWith(linkAlign: align);
    notifyListeners();
  }

  // ---- callouts ---------------------------------------------------------

  /// Adds a new callout near the centre and selects it. Returns its id.
  String addCallout() {
    final String id =
        'callout_${DateTime.now().microsecondsSinceEpoch}_${_calloutCounter++}';
    // Stagger new bubbles a little so they don't stack exactly on top of
    // each other.
    final double jitter = (_config.callouts.length % 5) * 0.06;
    final Callout callout = Callout(
      id: id,
      position: Offset(0.5, 0.35 + jitter).clamp01(),
    );
    _config = _config.copyWith(
      callouts: <Callout>[..._config.callouts, callout],
    );
    _selectedCalloutId = id;
    notifyListeners();
    return id;
  }

  void removeCallout(String id) {
    _config = _config.copyWith(
      callouts: _config.callouts.where((Callout c) => c.id != id).toList(),
    );
    if (_selectedCalloutId == id) _selectedCalloutId = null;
    notifyListeners();
  }

  void updateCallout(String id, Callout Function(Callout) update) {
    _config = _config.copyWith(
      callouts: _config.callouts
          .map((Callout c) => c.id == id ? update(c) : c)
          .toList(),
    );
    notifyListeners();
  }

  /// Convenience used by the drag handler — moves a callout to a new
  /// fractional position, clamped onto the canvas.
  void moveCallout(String id, Offset fractionalPosition) {
    updateCallout(
      id,
      (Callout c) => c.copyWith(position: fractionalPosition).clampedToCanvas(),
    );
  }

  void selectCallout(String? id) {
    if (_selectedCalloutId == id) return;
    _selectedCalloutId = id;
    notifyListeners();
  }

  void clearSelection() => selectCallout(null);
}

extension on Offset {
  /// Clamp both components into the 0..1 range.
  Offset clamp01() => Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));
}
