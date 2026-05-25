import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/image_processing_service.dart';

/// Full-screen modal editor that operates on a single layer's image bytes.
///
/// Tools work sequentially: the user picks crop, makes an edit, hits "Apply
/// crop"; that bakes the change into the working PNG and switches them back
/// to the toolbar. The Mask tab uses immediate-mode painting (each brush
/// stroke or wand fill is appended to an ordered op log). When the user taps
/// "Done" the final bytes are returned via [Navigator.pop]; Cancel discards
/// everything.
class ImageEditorScreen extends StatefulWidget {
  const ImageEditorScreen({
    super.key,
    required this.initialBytes,
    this.originalBytes,
  });

  /// Starting image (the layer's current bytes).
  final Uint8List initialBytes;

  /// The image the user originally imported (or null if unknown). Lets the
  /// "Reset" affordance restore the untouched source.
  final Uint8List? originalBytes;

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen>
    with SingleTickerProviderStateMixin {
  final ImageProcessingService _svc = const ImageProcessingService();

  late TabController _tabs;
  late Uint8List _working;
  ui.Image? _workingImage; // cached decode for fast painting
  bool _busy = false;

  // ---- crop tool state -------------------------------------------------
  Rect _cropFractional = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
  _CropAspect _cropAspect = _CropAspect.free;

  // ---- rotate tool state -----------------------------------------------
  double _freeRotateDeg = 0;

  // ---- mask tool state -------------------------------------------------
  // An ordered log of mask operations. Insertion order matters: a restore
  // stroke after an erase brings pixels back; an erase stroke after a
  // restore re-erases them. Undo/redo move ops between [_maskOps] and
  // [_maskRedo].
  final List<_MaskOp> _maskOps = <_MaskOp>[];
  final List<_MaskOp> _maskRedo = <_MaskOp>[];
  double _brushSize = 24; // pixel radius in image space
  int _wandTolerance = 60;
  _MaskTool _maskTool = _MaskTool.brushErase;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _working = widget.initialBytes;
    _decodeWorking();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _workingImage?.dispose();
    super.dispose();
  }

  Future<void> _decodeWorking() async {
    final ui.Image img = await _svc.decodeUiImage(_working);
    if (!mounted) {
      img.dispose();
      return;
    }
    setState(() {
      _workingImage?.dispose();
      _workingImage = img;
      // Reset per-tool state that depends on image dimensions.
      _maskOps.clear();
      _maskRedo.clear();
      _cropFractional = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
      _freeRotateDeg = 0;
    });
  }

  /// Run a heavy image op while pinning [_busy] = true. Waits one frame
  /// after flipping the flag so the "Processing…" overlay actually paints
  /// before the work starts; on failure, surfaces [errorLabel] in a snack.
  Future<void> _runBusy(
    String errorLabel,
    Future<Uint8List> Function() op,
  ) async {
    setState(() => _busy = true);
    await SchedulerBinding.instance.endOfFrame;
    try {
      _working = await op();
      await _decodeWorking();
    } catch (e) {
      _snack('$errorLabel: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- crop

  Future<void> _applyCrop() =>
      _runBusy('Could not crop', () => _svc.cropPng(_working, _cropFractional));

  // -------------------------------------------------------------- rotate

  Future<void> _rotate(int quarters) => _runBusy(
    'Could not rotate',
    () => _svc.rotateQuarterPng(_working, quarters),
  );

  Future<void> _applyFreeRotate() {
    if (_freeRotateDeg.abs() < 0.1) return Future<void>.value();
    return _runBusy(
      'Could not rotate',
      () => _svc.rotateAnyPng(_working, _freeRotateDeg),
    );
  }

  // ---------------------------------------------------------------- mask

  Future<void> _applyErasures() {
    if (_maskOps.isEmpty) return Future<void>.value();
    final List<Path> erase = <Path>[];
    final List<FloodMask> floods = <FloodMask>[];
    final List<Path> restore = <Path>[];
    // Order matters in the service too: we currently apply *all* erase
    // ops, then all restore ops — so any erase made after a restore in
    // the timeline is preserved, but any restore made after an erase
    // overrides the erase. That's the intent of the restore brush.
    for (final _MaskOp op in _maskOps) {
      switch (op) {
        case _EraseStroke():
          erase.add(op.path);
        case _RestoreStroke():
          restore.add(op.path);
        case _WandFlood():
          floods.add(op.mask);
      }
    }
    return _runBusy(
      'Could not apply erasures',
      () => _svc.applyErasures(
        _working,
        erasePaths: erase,
        floodMasks: floods,
        restorePaths: restore,
      ),
    );
  }

  void _appendMaskOp(_MaskOp op) {
    setState(() {
      _maskOps.add(op);
      _maskRedo.clear();
    });
  }

  void _undoMaskOp() {
    if (_maskOps.isEmpty) return;
    setState(() {
      _maskRedo.add(_maskOps.removeLast());
    });
  }

  void _redoMaskOp() {
    if (_maskRedo.isEmpty) return;
    setState(() {
      _maskOps.add(_maskRedo.removeLast());
    });
  }

  // ---------------------------------------------------------------- reset

  Future<void> _resetToOriginal() async {
    final Uint8List? orig = widget.originalBytes;
    if (orig == null) return;
    setState(() => _busy = true);
    try {
      _working = orig;
      await _decodeWorking();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- misc

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit image'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(null),
        ),
        actions: <Widget>[
          if (widget.originalBytes != null)
            IconButton(
              tooltip: 'Reset to original',
              onPressed: _busy ? null : _resetToOriginal,
              icon: const Icon(Icons.restart_alt),
            ),
          TextButton.icon(
            onPressed: _busy ? null : () => Navigator.of(context).pop(_working),
            icon: const Icon(Icons.check),
            label: const Text('Done'),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Tab>[
            Tab(icon: Icon(Icons.crop), text: 'Crop'),
            Tab(icon: Icon(Icons.rotate_right), text: 'Rotate'),
            Tab(icon: Icon(Icons.brush_outlined), text: 'Background'),
          ],
        ),
      ),
      body: _workingImage == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: <Widget>[
                Column(
                  children: <Widget>[
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: <Widget>[
                          _buildCropTab(),
                          _buildRotateTab(),
                          _buildMaskTab(),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_busy) const _ProcessingOverlay(),
              ],
            ),
    );
  }

  // ============================================================ crop tab

  Widget _buildCropTab() {
    final ui.Image image = _workingImage!;
    final double imageAspect = image.width / image.height;
    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _AspectFitImage(
                image: image,
                child: (Size displaySize) => _CropOverlay(
                  displaySize: displaySize,
                  rect: _cropFractional,
                  aspect: _cropAspect.ratio,
                  imageAspect: imageAspect,
                  onChange: (Rect r) => setState(() => _cropFractional = r),
                ),
              ),
            ),
          ),
        ),
        _cropAspectBar(),
        _bottomBar(
          children: <Widget>[
            Expanded(
              child: Text(
                _cropAspect == _CropAspect.free
                    ? 'Drag the handles to set the crop area.'
                    : 'Aspect locked to ${_cropAspect.label}. Drag any handle to resize.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _applyCrop,
              icon: const Icon(Icons.crop),
              label: const Text('Apply crop'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cropAspectBar() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text('Aspect'),
              ),
              for (final _CropAspect a in _CropAspect.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(a.label),
                    selected: _cropAspect == a,
                    onSelected: (_) => setState(() {
                      _cropAspect = a;
                      _cropFractional = _enforceAspectOnRect(
                        _cropFractional,
                        a.ratio,
                        _workingImage!.width / _workingImage!.height,
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ========================================================== rotate tab

  Widget _buildRotateTab() {
    final ui.Image image = _workingImage!;
    final double rad = _freeRotateDeg * math.pi / 180;
    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  // Pick the largest base image-size whose rotated bounding
                  // box still fits the available area. Without this the image
                  // would clip its own corners as the user spins past 0°.
                  final double imgAspect = image.width / image.height;
                  final double cosA = math.cos(rad).abs();
                  final double sinA = math.sin(rad).abs();
                  final double rotW = cosA + sinA / imgAspect;
                  final double rotH = sinA + cosA / imgAspect;
                  final double byW = constraints.maxWidth / rotW;
                  final double byH = constraints.maxHeight / rotH;
                  final double baseW = math.min(byW, byH);
                  final double baseH = baseW / imgAspect;
                  return Transform.rotate(
                    angle: rad,
                    child: SizedBox(
                      width: baseW,
                      height: baseH,
                      child: RawImage(image: image, fit: BoxFit.fill),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                const Text('Free rotate'),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    min: -180,
                    max: 180,
                    divisions: 360,
                    value: _freeRotateDeg,
                    label: '${_freeRotateDeg.toStringAsFixed(0)}°',
                    onChanged: _busy
                        ? null
                        : (double v) => setState(() => _freeRotateDeg = v),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${_freeRotateDeg.toStringAsFixed(0)}°',
                    textAlign: TextAlign.end,
                  ),
                ),
                TextButton(
                  onPressed: _busy || _freeRotateDeg == 0
                      ? null
                      : () => setState(() => _freeRotateDeg = 0),
                  child: const Text('Reset'),
                ),
                FilledButton.icon(
                  onPressed: _busy || _freeRotateDeg.abs() < 0.1
                      ? null
                      : _applyFreeRotate,
                  icon: const Icon(Icons.check),
                  label: const Text('Apply'),
                ),
              ],
            ),
          ),
        ),
        _bottomBar(
          children: <Widget>[
            const Spacer(),
            IconButton.outlined(
              tooltip: 'Rotate 90° counter-clockwise',
              onPressed: _busy ? null : () => _rotate(3),
              icon: const Icon(Icons.rotate_90_degrees_ccw),
            ),
            const SizedBox(width: 12),
            IconButton.outlined(
              tooltip: 'Rotate 180°',
              onPressed: _busy ? null : () => _rotate(2),
              icon: const Icon(Icons.flip_camera_android),
            ),
            const SizedBox(width: 12),
            IconButton.outlined(
              tooltip: 'Rotate 90° clockwise',
              onPressed: _busy ? null : () => _rotate(1),
              icon: const Icon(Icons.rotate_90_degrees_cw),
            ),
            const SizedBox(width: 12),
            Text(
              '90° quick rotates',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================ mask tab

  Widget _buildMaskTab() {
    final ui.Image image = _workingImage!;
    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _AspectFitImage(
                image: image,
                child: (Size displaySize) => _MaskEditorOverlay(
                  image: image,
                  displaySize: displaySize,
                  ops: _maskOps,
                  tool: _maskTool,
                  brushSize: _brushSize,
                  wandTolerance: _wandTolerance,
                  workingBytes: _working,
                  onAppendOp: _appendMaskOp,
                ),
              ),
            ),
          ),
        ),
        _maskToolbar(),
        _bottomBar(
          children: <Widget>[
            IconButton.outlined(
              tooltip: 'Undo',
              onPressed: _busy || _maskOps.isEmpty ? null : _undoMaskOp,
              icon: const Icon(Icons.undo),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Redo',
              onPressed: _busy || _maskRedo.isEmpty ? null : _redoMaskOp,
              icon: const Icon(Icons.redo),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy || _maskOps.isEmpty ? null : _applyErasures,
              icon: const Icon(Icons.layers_clear),
              label: const Text('Apply erasures'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _maskToolbar() {
    final bool showTolerance = _maskTool == _MaskTool.wand;
    final bool showBrush =
        _maskTool == _MaskTool.brushErase ||
        _maskTool == _MaskTool.brushRestore;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              SegmentedButton<_MaskTool>(
                showSelectedIcon: false,
                // Icon-only with tooltips so all five tools fit comfortably
                // on phone-width screens without wrapping the toolbar.
                segments: const <ButtonSegment<_MaskTool>>[
                  ButtonSegment<_MaskTool>(
                    value: _MaskTool.brushErase,
                    icon: Icon(Icons.brush),
                    tooltip: 'Erase brush',
                  ),
                  ButtonSegment<_MaskTool>(
                    value: _MaskTool.brushRestore,
                    icon: Icon(Icons.auto_fix_normal),
                    tooltip: 'Restore brush',
                  ),
                  ButtonSegment<_MaskTool>(
                    value: _MaskTool.wand,
                    icon: Icon(Icons.auto_fix_high),
                    tooltip: 'Magic wand',
                  ),
                  ButtonSegment<_MaskTool>(
                    value: _MaskTool.freeLasso,
                    icon: Icon(Icons.gesture),
                    tooltip: 'Free lasso',
                  ),
                  ButtonSegment<_MaskTool>(
                    value: _MaskTool.magneticLasso,
                    icon: Icon(Icons.timeline),
                    tooltip: 'Magnetic lasso',
                  ),
                ],
                selected: <_MaskTool>{_maskTool},
                onSelectionChanged: (Set<_MaskTool> s) =>
                    setState(() => _maskTool = s.first),
              ),
              const SizedBox(width: 16),
              if (showTolerance) ...<Widget>[
                const Text('Tolerance'),
                SizedBox(
                  width: 160,
                  child: Slider(
                    min: 5,
                    max: 200,
                    value: _wandTolerance.toDouble(),
                    onChanged: (double v) =>
                        setState(() => _wandTolerance = v.round()),
                  ),
                ),
                Text('$_wandTolerance'),
              ] else if (showBrush) ...<Widget>[
                const Text('Brush'),
                SizedBox(
                  width: 160,
                  child: Slider(
                    min: 4,
                    max: 160,
                    value: _brushSize,
                    onChanged: (double v) => setState(() => _brushSize = v),
                  ),
                ),
                Text('${_brushSize.round()}px'),
              ],
              const SizedBox(width: 24),
              Text(switch (_maskTool) {
                _MaskTool.brushErase => 'Drag to erase',
                _MaskTool.brushRestore => 'Drag to bring pixels back',
                _MaskTool.wand => 'Tap a region to erase',
                _MaskTool.freeLasso => 'Drag a freehand loop; release to erase',
                _MaskTool.magneticLasso =>
                  'Tap to drop anchors (snaps to edges); '
                      'click the start dot to close',
              }, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ bottom bar

  Widget _bottomBar({required List<Widget> children}) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: children),
      ),
    );
  }
}

// ============================================================ supporting types

/// Full-screen modal scrim shown while a crop/rotate/erasure runs. The work
/// itself executes on a background isolate, but the overlay also intercepts
/// pointer events so the user can't queue a second op mid-flight.
class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: AbsorbPointer(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Processing…',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _MaskTool { brushErase, brushRestore, wand, freeLasso, magneticLasso }

/// Sealed family of mask-editor operations, applied in insertion order.
sealed class _MaskOp {
  const _MaskOp();
}

class _EraseStroke extends _MaskOp {
  _EraseStroke(this.path);
  final Path path;
}

class _RestoreStroke extends _MaskOp {
  _RestoreStroke(this.path);
  final Path path;
}

class _WandFlood extends _MaskOp {
  _WandFlood(this.mask);
  final FloodMask mask;
}

/// Crop aspect-ratio presets. `null` for [_CropAspect.free] means the user
/// drags corners/edges freely; any other value locks `width/height`.
enum _CropAspect {
  free(null, 'Free'),
  square(1.0, '1:1'),
  portrait4x5(4 / 5, '4:5'),
  portrait9x16(9 / 16, '9:16'),
  landscape16x9(16 / 9, '16:9'),
  landscape4x3(4 / 3, '4:3'),
  portrait3x4(3 / 4, '3:4');

  const _CropAspect(this.ratio, this.label);
  final double? ratio;
  final String label;
}

/// Re-clamp [rect] (fractional, 0..1, in image-fractional space) so that its
/// rendered width/height honour [ratio]. `imageAspect = image.width/image.height`.
/// When [ratio] is null, the input is returned unchanged.
Rect _enforceAspectOnRect(Rect rect, double? ratio, double imageAspect) {
  if (ratio == null) return rect;
  // Desired w/h of the crop expressed in fractional units: target_w * iw /
  // (target_h * ih) == ratio  →  target_w / target_h == ratio / imageAspect.
  final double frac = ratio / imageAspect;
  // Decide whether to fit by width or height (pick the smaller resulting box
  // so we never expand past the bounds).
  final double byW = rect.width;
  final double byH = rect.height * frac;
  final double targetW = byW < byH ? byW : byH;
  final double targetH = targetW / frac;
  // Re-center on the current rect's centre, then clamp into 0..1.
  final double cx = rect.center.dx;
  final double cy = rect.center.dy;
  final double l = (cx - targetW / 2).clamp(0.0, 1.0 - targetW);
  final double t = (cy - targetH / 2).clamp(0.0, 1.0 - targetH);
  return Rect.fromLTWH(l, t, targetW, targetH);
}

// ============================================================ helpers

/// Lays out [image] inside the parent maintaining aspect ratio, and then
/// invokes [child] with the actual displayed size so overlays can position
/// themselves in display pixels (and convert events back to image pixels).
class _AspectFitImage extends StatelessWidget {
  const _AspectFitImage({required this.image, required this.child});

  final ui.Image image;
  final Widget Function(Size displaySize) child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double aspect = image.width / image.height;
        double w = constraints.maxWidth;
        double h = w / aspect;
        if (h > constraints.maxHeight) {
          h = constraints.maxHeight;
          w = h * aspect;
        }
        final Size disp = Size(w, h);
        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              RawImage(image: image, fit: BoxFit.fill),
              child(disp),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================ crop overlay

class _CropOverlay extends StatelessWidget {
  const _CropOverlay({
    required this.displaySize,
    required this.rect,
    required this.aspect,
    required this.imageAspect,
    required this.onChange,
  });

  final Size displaySize;
  final Rect rect; // fractional 0..1
  final double? aspect; // null = free
  final double imageAspect;
  final ValueChanged<Rect> onChange;

  Rect _displayRect() => Rect.fromLTWH(
    rect.left * displaySize.width,
    rect.top * displaySize.height,
    rect.width * displaySize.width,
    rect.height * displaySize.height,
  );

  void _move(Offset deltaPx) {
    final double dx = deltaPx.dx / displaySize.width;
    final double dy = deltaPx.dy / displaySize.height;
    final double nl = (rect.left + dx).clamp(0.0, 1.0 - rect.width);
    final double nt = (rect.top + dy).clamp(0.0, 1.0 - rect.height);
    onChange(Rect.fromLTWH(nl, nt, rect.width, rect.height));
  }

  /// Resize by dragging a handle. [dxSign]/[dySign] are -1, 0, or 1: -1 means
  /// the handle is on the LEFT/TOP (dragging adjusts left/top edge), +1 means
  /// RIGHT/BOTTOM, 0 means the handle only moves along the other axis (edge
  /// handle).
  void _resize(Offset deltaPx, int dxSign, int dySign) {
    final double dx = deltaPx.dx / displaySize.width;
    final double dy = deltaPx.dy / displaySize.height;
    double l = rect.left;
    double t = rect.top;
    double r = rect.right;
    double b = rect.bottom;
    if (dxSign < 0) {
      l = (l + dx).clamp(0.0, r - 0.05);
    } else if (dxSign > 0) {
      r = (r + dx).clamp(l + 0.05, 1.0);
    }
    if (dySign < 0) {
      t = (t + dy).clamp(0.0, b - 0.05);
    } else if (dySign > 0) {
      b = (b + dy).clamp(t + 0.05, 1.0);
    }
    Rect next = Rect.fromLTRB(l, t, r, b);
    if (aspect != null) {
      // Re-enforce the aspect ratio around the *fixed* opposite anchor.
      final double frac = aspect! / imageAspect;
      // Anchor = the corner/edge that did NOT move under the user's finger.
      final double anchorX = dxSign < 0 ? r : (dxSign > 0 ? l : (l + r) / 2);
      final double anchorY = dySign < 0 ? b : (dySign > 0 ? t : (t + b) / 2);
      // Choose new width/height matching the user's drag, then enforce ratio.
      double w = next.width;
      double h = next.height;
      if (dxSign != 0 && dySign != 0) {
        // Corner drag — match the dominant axis the user pushed harder.
        if (w / frac > h) {
          h = w / frac;
        } else {
          w = h * frac;
        }
      } else if (dxSign != 0) {
        h = w / frac;
      } else if (dySign != 0) {
        w = h * frac;
      }
      // Rebuild around the anchor.
      double newL = dxSign < 0
          ? anchorX - w
          : (dxSign > 0 ? anchorX : anchorX - w / 2);
      double newT = dySign < 0
          ? anchorY - h
          : (dySign > 0 ? anchorY : anchorY - h / 2);
      // Clamp into bounds; if clamping shrinks one axis we re-derive the other.
      if (newL < 0) {
        w += newL;
        newL = 0;
        h = w / frac;
      }
      if (newT < 0) {
        h += newT;
        newT = 0;
        w = h * frac;
      }
      if (newL + w > 1) {
        w = 1 - newL;
        h = w / frac;
      }
      if (newT + h > 1) {
        h = 1 - newT;
        w = h * frac;
      }
      next = Rect.fromLTWH(newL, newT, w, h);
    }
    onChange(next);
  }

  @override
  Widget build(BuildContext context) {
    final Rect r = _displayRect();
    final Color accent = Theme.of(context).colorScheme.primary;
    return Stack(
      children: <Widget>[
        // Dim everything outside the crop rect.
        IgnorePointer(
          child: CustomPaint(
            painter: _CropDimPainter(rect: r, color: Colors.black54),
            size: displaySize,
          ),
        ),
        // Move the crop rect by dragging its interior. Rule-of-thirds grid
        // overlay lives here too so it shifts with the rect.
        Positioned(
          left: r.left,
          top: r.top,
          width: r.width,
          height: r.height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (DragUpdateDetails d) => _move(d.delta),
            child: CustomPaint(painter: _CropFramePainter(color: accent)),
          ),
        ),
        // 4 edge handles (top/right/bottom/left midpoints).
        for (final ({int dxSign, int dySign}) edge
            in const <({int dxSign, int dySign})>[
              (dxSign: 0, dySign: -1),
              (dxSign: 1, dySign: 0),
              (dxSign: 0, dySign: 1),
              (dxSign: -1, dySign: 0),
            ])
          _edgeHandle(r, edge.dxSign, edge.dySign, accent),
        // 4 corner handles.
        for (final ({int dxSign, int dySign}) corner
            in const <({int dxSign, int dySign})>[
              (dxSign: -1, dySign: -1),
              (dxSign: 1, dySign: -1),
              (dxSign: -1, dySign: 1),
              (dxSign: 1, dySign: 1),
            ])
          _cornerHandle(r, corner.dxSign, corner.dySign, accent),
      ],
    );
  }

  Widget _cornerHandle(Rect r, int dxSign, int dySign, Color accent) {
    return Positioned(
      left: dxSign < 0 ? r.left - 10 : r.right - 10,
      top: dySign < 0 ? r.top - 10 : r.bottom - 10,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (DragUpdateDetails d) => _resize(d.delta, dxSign, dySign),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: accent, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _edgeHandle(Rect r, int dxSign, int dySign, Color accent) {
    const double size = 18;
    final bool horizontal = dySign == 0;
    final double left = dxSign < 0
        ? r.left - size / 2
        : (dxSign > 0 ? r.right - size / 2 : r.left + r.width / 2 - size / 2);
    final double top = dySign < 0
        ? r.top - size / 2
        : (dySign > 0 ? r.bottom - size / 2 : r.top + r.height / 2 - size / 2);
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (DragUpdateDetails d) => _resize(d.delta, dxSign, dySign),
        child: MouseRegion(
          cursor: horizontal
              ? SystemMouseCursors.resizeLeftRight
              : SystemMouseCursors.resizeUpDown,
          child: Container(
            width: horizontal ? size * 0.6 : size * 1.6,
            height: horizontal ? size * 1.6 : size * 0.6,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: accent, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropDimPainter extends CustomPainter {
  _CropDimPainter({required this.rect, required this.color});

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..color = color;
    final Path outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, p);
  }

  @override
  bool shouldRepaint(_CropDimPainter old) =>
      old.rect != rect || old.color != color;
}

/// Draws the crop rect's border + a rule-of-thirds grid inside it.
class _CropFramePainter extends CustomPainter {
  _CropFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Offset.zero & size, border);
    final Paint grid = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final double w3 = size.width / 3;
    final double h3 = size.height / 3;
    canvas.drawLine(Offset(w3, 0), Offset(w3, size.height), grid);
    canvas.drawLine(Offset(w3 * 2, 0), Offset(w3 * 2, size.height), grid);
    canvas.drawLine(Offset(0, h3), Offset(size.width, h3), grid);
    canvas.drawLine(Offset(0, h3 * 2), Offset(size.width, h3 * 2), grid);
  }

  @override
  bool shouldRepaint(_CropFramePainter old) => old.color != color;
}

// ============================================================ mask overlay

class _MaskEditorOverlay extends StatefulWidget {
  const _MaskEditorOverlay({
    required this.image,
    required this.displaySize,
    required this.ops,
    required this.tool,
    required this.brushSize,
    required this.wandTolerance,
    required this.workingBytes,
    required this.onAppendOp,
  });

  final ui.Image image;
  final Size displaySize;
  final List<_MaskOp> ops;
  final _MaskTool tool;
  final double brushSize;
  final int wandTolerance;
  final Uint8List workingBytes;
  final ValueChanged<_MaskOp> onAppendOp;

  @override
  State<_MaskEditorOverlay> createState() => _MaskEditorOverlayState();
}

class _MaskEditorOverlayState extends State<_MaskEditorOverlay> {
  // Currently in-progress brush path (image-pixel coords). Pushed onto the
  // op log as a brand-new op at pan start so the painter sees it live, then
  // gets its points appended in pan update.
  Path? _currentPath;
  // Triggers the painter to redraw without rebuilding any other widgets.
  final ValueNotifier<int> _repaintTick = ValueNotifier<int>(0);
  // Cached flood-mask images so we don't redecode them every frame.
  final Map<FloodMask, ui.Image> _maskImages = <FloodMask, ui.Image>{};
  // Magic-wand can take a few hundred ms; we lock the UI while it runs.
  bool _wandBusy = false;
  // Pointer position in display pixels — used to draw the brush cursor.
  Offset? _hover;
  // Decoded RGBA of [widget.workingBytes], cached so the wand BFS can run
  // without re-decoding the PNG on every tap. Invalidated when workingBytes
  // changes identity (which happens after each Apply erasures / crop / rotate).
  RawRgba? _rgbaCache;
  Uint8List? _rgbaCacheFor;

  final ImageProcessingService _svc = const ImageProcessingService();

  @override
  void dispose() {
    for (final ui.Image i in _maskImages.values) {
      i.dispose();
    }
    _maskImages.clear();
    _repaintTick.dispose();
    super.dispose();
  }

  Offset _displayToImage(Offset display) {
    final double sx = widget.image.width / widget.displaySize.width;
    final double sy = widget.image.height / widget.displaySize.height;
    return Offset(display.dx * sx, display.dy * sy);
  }

  bool get _isBrush =>
      widget.tool == _MaskTool.brushErase ||
      widget.tool == _MaskTool.brushRestore;

  bool get _isLasso =>
      widget.tool == _MaskTool.freeLasso ||
      widget.tool == _MaskTool.magneticLasso;

  // ============================================================ brush

  void _onPanStart(DragStartDetails d) {
    if (_isBrush) {
      _startBrushStroke(d);
    } else if (widget.tool == _MaskTool.freeLasso) {
      _startFreeLasso(d);
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_isBrush) {
      _updateBrushStroke(d);
    } else if (widget.tool == _MaskTool.freeLasso) {
      _updateFreeLasso(d);
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_isBrush) {
      _currentPath = null;
    } else if (widget.tool == _MaskTool.freeLasso) {
      _endFreeLasso();
    }
  }

  void _startBrushStroke(DragStartDetails d) {
    final Offset imgPt = _displayToImage(d.localPosition);
    final Path p = Path()
      ..addOval(Rect.fromCircle(center: imgPt, radius: widget.brushSize));
    _currentPath = p;
    final _MaskOp op = widget.tool == _MaskTool.brushErase
        ? _EraseStroke(p)
        : _RestoreStroke(p);
    widget.onAppendOp(op);
    _repaintTick.value++;
  }

  void _updateBrushStroke(DragUpdateDetails d) {
    if (_currentPath == null) return;
    final Offset imgPt = _displayToImage(d.localPosition);
    _currentPath!.addOval(
      Rect.fromCircle(center: imgPt, radius: widget.brushSize),
    );
    _hover = d.localPosition;
    _repaintTick.value++;
  }

  // ============================================================ tap

  Future<void> _onTap(TapDownDetails d) async {
    if (widget.tool == _MaskTool.wand) {
      await _runWandTap(d);
    } else if (widget.tool == _MaskTool.magneticLasso) {
      await _onMagneticLassoTap(d);
    }
  }

  Future<void> _runWandTap(TapDownDetails d) async {
    if (_wandBusy) return;
    final Offset imgPt = _displayToImage(d.localPosition);
    setState(() => _wandBusy = true);
    try {
      final RawRgba rgba = await _ensureRgba();
      final FloodMask m = await _svc.floodFillRgba(
        rgba,
        imgPt.dx.round(),
        imgPt.dy.round(),
        tolerance: widget.wandTolerance,
      );
      // Pre-decode the mask image so subsequent repaints are smooth.
      _maskImages[m] = await _maskToUi(m);
      widget.onAppendOp(_WandFlood(m));
      _repaintTick.value++;
    } finally {
      if (mounted) setState(() => _wandBusy = false);
    }
  }

  /// Ensure the cached RGBA buffer matches the current [widget.workingBytes].
  /// Shared by the wand and the magnetic lasso — the first one to need
  /// pixels pays for the decode, everyone else reuses the buffer.
  ///
  /// On web the decode goes through the browser's native PNG codec (in
  /// `decodeRawRgba`), so even the first call is fast.
  Future<RawRgba> _ensureRgba() async {
    if (identical(_rgbaCacheFor, widget.workingBytes) && _rgbaCache != null) {
      return _rgbaCache!;
    }
    final RawRgba r = await _svc.decodeRawRgba(widget.workingBytes);
    _rgbaCache = r;
    _rgbaCacheFor = widget.workingBytes;
    return r;
  }

  // ============================================================ lasso

  /// Image-pixel coordinates of the lasso polygon being assembled. Empty
  /// when no lasso is in progress. Free-lasso fills this during a pan;
  /// magnetic lasso appends one entry per tap (snapped to the nearest
  /// edge). Cleared when the polygon is committed or cancelled.
  final List<Offset> _lassoPoints = <Offset>[];
  // Cursor in display pixels for the magnetic lasso rubber-band preview.
  Offset? _lassoCursorDisplay;
  // Threshold (in display pixels) for the "click near start to close" check.
  static const double _lassoCloseThreshold = 14;

  bool get _lassoInProgress => _lassoPoints.isNotEmpty;

  void _startFreeLasso(DragStartDetails d) {
    final Offset imgPt = _displayToImage(d.localPosition);
    _lassoPoints
      ..clear()
      ..add(imgPt);
    _lassoCursorDisplay = d.localPosition;
    _repaintTick.value++;
  }

  void _updateFreeLasso(DragUpdateDetails d) {
    final Offset imgPt = _displayToImage(d.localPosition);
    // Throttle: only append if we've moved at least a pixel in image space —
    // millions of redundant points would slow the painter and balloon the
    // emitted Path with no visible benefit.
    if (_lassoPoints.isEmpty || (_lassoPoints.last - imgPt).distance >= 1.5) {
      _lassoPoints.add(imgPt);
    }
    _lassoCursorDisplay = d.localPosition;
    _repaintTick.value++;
  }

  void _endFreeLasso() {
    _commitLassoAsErase();
  }

  Future<void> _onMagneticLassoTap(TapDownDetails d) async {
    // Closing tap: click near the first anchor finalises the polygon (only
    // once there are enough points to form one — first click can't close).
    if (_lassoPoints.length >= 3) {
      final Offset firstDisp = _imageToDisplay(_lassoPoints.first);
      if ((firstDisp - d.localPosition).distance <= _lassoCloseThreshold) {
        _commitLassoAsErase();
        return;
      }
    }
    // Need pixels to snap-to-edge. The first magnetic-lasso tap on a fresh
    // image pays for one decode; subsequent taps are instant.
    final RawRgba rgba = await _ensureRgba();
    final Offset rawImg = _displayToImage(d.localPosition);
    final Offset snapped = _snapToEdge(rawImg, rgba);
    _lassoPoints.add(snapped);
    _lassoCursorDisplay = d.localPosition;
    _repaintTick.value++;
  }

  void _cancelLasso() {
    if (_lassoPoints.isEmpty) return;
    _lassoPoints.clear();
    _lassoCursorDisplay = null;
    _repaintTick.value++;
  }

  void _commitLassoAsErase() {
    if (_lassoPoints.length < 3) {
      _cancelLasso();
      return;
    }
    final Path path = Path()..moveTo(_lassoPoints[0].dx, _lassoPoints[0].dy);
    for (int i = 1; i < _lassoPoints.length; i++) {
      path.lineTo(_lassoPoints[i].dx, _lassoPoints[i].dy);
    }
    path.close();
    widget.onAppendOp(_EraseStroke(path));
    _lassoPoints.clear();
    _lassoCursorDisplay = null;
    _repaintTick.value++;
  }

  Offset _imageToDisplay(Offset image) {
    final double sx = widget.displaySize.width / widget.image.width;
    final double sy = widget.displaySize.height / widget.image.height;
    return Offset(image.dx * sx, image.dy * sy);
  }

  /// Within a small square window around [center] (in image pixels), return
  /// the pixel with the strongest Sobel edge magnitude. Cheap because the
  /// window is tiny — one snap is ~300 pixels × 8 lookups each, negligible
  /// even on web. Falls back to [center] if it's too close to the edge of
  /// the image for the 3×3 Sobel kernel.
  Offset _snapToEdge(Offset center, RawRgba rgba, {int radius = 10}) {
    final int w = rgba.width;
    final int h = rgba.height;
    if (w < 3 || h < 3) return center;
    final Uint8List p = rgba.bytes;
    final int cx = center.dx.round().clamp(1, w - 2);
    final int cy = center.dy.round().clamp(1, h - 2);
    final int x0 = math.max(1, cx - radius);
    final int y0 = math.max(1, cy - radius);
    final int x1 = math.min(w - 2, cx + radius);
    final int y1 = math.min(h - 2, cy + radius);
    int bestX = cx;
    int bestY = cy;
    int bestMag = -1;
    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        final int mag = _sobelMagnitude(p, w, x, y);
        if (mag > bestMag) {
          bestMag = mag;
          bestX = x;
          bestY = y;
        }
      }
    }
    return Offset(bestX.toDouble(), bestY.toDouble());
  }

  /// Sobel-3×3 gradient magnitude (|gx|+|gy|, no sqrt) of luminance at
  /// [(x, y)]. Caller guarantees 1 ≤ x ≤ w-2 and 1 ≤ y ≤ h-2.
  static int _sobelMagnitude(Uint8List p, int w, int x, int y) {
    // Luminance via ITU-R BT.601 weights, kept as integer math to stay fast.
    int lum(int xx, int yy) {
      final int off = (yy * w + xx) * 4;
      return (p[off] * 76 + p[off + 1] * 150 + p[off + 2] * 30) >> 8;
    }

    final int tl = lum(x - 1, y - 1);
    final int t = lum(x, y - 1);
    final int tr = lum(x + 1, y - 1);
    final int l = lum(x - 1, y);
    final int r = lum(x + 1, y);
    final int bl = lum(x - 1, y + 1);
    final int b = lum(x, y + 1);
    final int br = lum(x + 1, y + 1);
    final int gx = (tr + 2 * r + br) - (tl + 2 * l + bl);
    final int gy = (bl + 2 * b + br) - (tl + 2 * t + tr);
    return gx.abs() + gy.abs();
  }

  Future<ui.Image> _maskToUi(FloodMask m) async {
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

  @override
  Widget build(BuildContext context) {
    // Re-resolve the mask image cache: any WandFlood op that's been undone
    // or removed should drop its cached image. We keep ones that are still
    // referenced by the op log.
    final Set<FloodMask> live = <FloodMask>{
      for (final _MaskOp op in widget.ops)
        if (op is _WandFlood) op.mask,
    };
    _maskImages.removeWhere((FloodMask k, ui.Image v) {
      if (live.contains(k)) return false;
      v.dispose();
      return true;
    });

    return MouseRegion(
      onHover: (PointerHoverEvent e) {
        if (_isBrush) {
          _hover = e.localPosition;
          _repaintTick.value++;
        } else if (widget.tool == _MaskTool.magneticLasso && _lassoInProgress) {
          // Move the rubber-band preview so the user can see what segment
          // their next click would close off.
          _lassoCursorDisplay = e.localPosition;
          _repaintTick.value++;
        }
      },
      onExit: (_) {
        _hover = null;
        _repaintTick.value++;
      },
      cursor: _isBrush || _isLasso
          ? SystemMouseCursors.precise
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTapDown: _onTap,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            RepaintBoundary(
              child: CustomPaint(
                painter: _MaskCompositePainter(
                  image: widget.image,
                  ops: widget.ops,
                  maskImages: _maskImages,
                  hover: _hover,
                  brushRadiusPx: _isBrush
                      ? widget.brushSize *
                            (widget.displaySize.width / widget.image.width)
                      : 0,
                  brushAccent: widget.tool == _MaskTool.brushRestore
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.primary,
                  lassoPointsImage: _lassoPoints,
                  lassoCursorDisplay: _lassoCursorDisplay,
                  lassoRubberBand: widget.tool == _MaskTool.magneticLasso,
                  lassoCloseThreshold: _lassoCloseThreshold,
                  repaint: _repaintTick,
                ),
              ),
            ),
            if (_wandBusy) const Center(child: CircularProgressIndicator()),
            // In-progress lasso banner: point count + commit / cancel.
            // Lives inside the overlay so it can read the local lasso state
            // without lifting it up to the parent screen.
            if (_lassoInProgress)
              Positioned(
                top: 8,
                right: 8,
                child: _LassoBanner(
                  pointCount: _lassoPoints.length,
                  canClose: _lassoPoints.length >= 3,
                  showClose: widget.tool == _MaskTool.magneticLasso,
                  onCancel: () => setState(_cancelLasso),
                  onClose: () => setState(_commitLassoAsErase),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(_MaskEditorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching away from a lasso tool (or to a different tool entirely)
    // should discard any in-progress polygon — keeping it around would be
    // confusing and the gesture handlers wouldn't pick it up anyway.
    if (oldWidget.tool != widget.tool && _lassoInProgress) {
      _cancelLasso();
    }
  }
}

class _MaskCompositePainter extends CustomPainter {
  _MaskCompositePainter({
    required this.image,
    required this.ops,
    required this.maskImages,
    required this.hover,
    required this.brushRadiusPx,
    required this.brushAccent,
    required this.lassoPointsImage,
    required this.lassoCursorDisplay,
    required this.lassoRubberBand,
    required this.lassoCloseThreshold,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ui.Image image;
  final List<_MaskOp> ops;
  final Map<FloodMask, ui.Image> maskImages;
  final Offset? hover;
  final double brushRadiusPx;
  final Color brushAccent;
  // In-progress lasso polygon, in image-pixel coords. Empty when no lasso
  // is being drawn.
  final List<Offset> lassoPointsImage;
  // Cursor position in display pixels — used to draw the magnetic-lasso
  // rubber-band segment from the last anchor.
  final Offset? lassoCursorDisplay;
  // Whether to draw the rubber-band preview + start-anchor disc. True for
  // magnetic lasso (which is committed by clicks), false for free lasso
  // (committed on pan end).
  final bool lassoRubberBand;
  // Display-pixel radius of the "click here to close" target around the
  // starting anchor.
  final double lassoCloseThreshold;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect dst = Offset.zero & size;
    final double sx = size.width / image.width;
    final double sy = size.height / image.height;

    // Checkerboard so erased regions are visible against a transparent BG.
    _paintCheckerboard(canvas, dst);

    // Open a layer so dstOut erases only the image, not the checker.
    canvas.saveLayer(dst, Paint());
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint(),
    );
    final Paint erase = Paint()..blendMode = BlendMode.dstOut;
    final Paint restoreImg = Paint()..blendMode = BlendMode.dstOver;
    // Apply each op in order; paths are in image-pixel coords so we drive a
    // scaled sub-canvas to keep their math simple.
    for (final _MaskOp op in ops) {
      switch (op) {
        case _EraseStroke():
          canvas.save();
          canvas.scale(sx, sy);
          canvas.drawPath(op.path, erase);
          canvas.restore();
        case _RestoreStroke():
          canvas.save();
          canvas.scale(sx, sy);
          canvas.clipPath(op.path);
          canvas.scale(1 / sx, 1 / sy);
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            dst,
            restoreImg,
          );
          canvas.restore();
        case _WandFlood():
          final ui.Image? m = maskImages[op.mask];
          if (m == null) break;
          canvas.drawImageRect(
            m,
            Rect.fromLTWH(0, 0, m.width.toDouble(), m.height.toDouble()),
            dst,
            erase,
          );
      }
    }
    canvas.restore();

    // Brush cursor — drawn after restore so it sits on top of everything.
    if (hover != null && brushRadiusPx > 0) {
      final Paint outer = Paint()
        ..color = brushAccent.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final Paint inner = Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawCircle(hover!, brushRadiusPx, outer);
      canvas.drawCircle(hover!, brushRadiusPx - 1, inner);
    }

    // In-progress lasso polygon — drawn on top of the composite. Always in
    // display-pixel coords (we map each image-pixel anchor through sx/sy).
    if (lassoPointsImage.isNotEmpty) {
      final Path poly = Path()
        ..moveTo(lassoPointsImage[0].dx * sx, lassoPointsImage[0].dy * sy);
      for (int i = 1; i < lassoPointsImage.length; i++) {
        poly.lineTo(lassoPointsImage[i].dx * sx, lassoPointsImage[i].dy * sy);
      }
      final Paint stroke = Paint()
        ..color = brushAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawPath(poly, stroke);

      // Magnetic-lasso live preview: the rubber-band segment from the last
      // anchor to the current cursor, plus a hit target around the start
      // anchor so the user can see where to click to close.
      if (lassoRubberBand && lassoCursorDisplay != null) {
        final Offset lastDisp = Offset(
          lassoPointsImage.last.dx * sx,
          lassoPointsImage.last.dy * sy,
        );
        final Paint band = Paint()
          ..color = brushAccent.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawLine(lastDisp, lassoCursorDisplay!, band);
      }
      if (lassoRubberBand) {
        final Offset firstDisp = Offset(
          lassoPointsImage.first.dx * sx,
          lassoPointsImage.first.dy * sy,
        );
        // Hollow ring marking the close target, then a small filled dot for
        // the anchor itself.
        canvas.drawCircle(
          firstDisp,
          lassoCloseThreshold,
          Paint()
            ..color = brushAccent.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        canvas.drawCircle(firstDisp, 3.5, Paint()..color = brushAccent);
      }
    }
  }

  void _paintCheckerboard(Canvas canvas, Rect rect) {
    const double tile = 12;
    final Paint a = Paint()..color = const Color(0xFFE5E5E5);
    final Paint b = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(rect, b);
    bool toggle = false;
    for (double y = rect.top; y < rect.bottom; y += tile) {
      bool row = toggle;
      for (double x = rect.left; x < rect.right; x += tile) {
        if (row) {
          canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), a);
        }
        row = !row;
      }
      toggle = !toggle;
    }
  }

  @override
  bool shouldRepaint(_MaskCompositePainter old) {
    return !identical(old.image, image) ||
        !listEquals(old.ops, ops) ||
        old.hover != hover ||
        old.brushRadiusPx != brushRadiusPx ||
        old.brushAccent != brushAccent ||
        !identical(old.lassoPointsImage, lassoPointsImage) ||
        old.lassoPointsImage.length != lassoPointsImage.length ||
        old.lassoCursorDisplay != lassoCursorDisplay ||
        old.lassoRubberBand != lassoRubberBand ||
        old.lassoCloseThreshold != lassoCloseThreshold;
  }
}

/// Floating panel shown over the mask canvas while a lasso polygon is being
/// drawn. Surfaces the point count, a Cancel button (always), and a Close
/// button (magnetic lasso only — free lasso auto-closes on pan end).
class _LassoBanner extends StatelessWidget {
  const _LassoBanner({
    required this.pointCount,
    required this.canClose,
    required this.showClose,
    required this.onCancel,
    required this.onClose,
  });

  final int pointCount;
  final bool canClose;
  final bool showClose;
  final VoidCallback onCancel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      borderRadius: BorderRadius.circular(8),
      elevation: 3,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '$pointCount point${pointCount == 1 ? '' : 's'}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(width: 8),
            if (showClose)
              TextButton.icon(
                onPressed: canClose ? onClose : null,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Close'),
              ),
            TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
