import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/image_processing_service.dart';

/// Which Phase-2 image tool is currently active.
enum ImageTool { crop, rotate, mask }

/// Full-screen modal editor that operates on a single layer's image bytes.
///
/// Tools work sequentially: the user picks crop, makes an edit, hits "Apply
/// crop"; that bakes the change into the working PNG and switches them back
/// to the toolbar. The Mask tab uses immediate-mode painting (each brush
/// stroke updates state right away). When the user taps "Done" the final
/// bytes are returned via [Navigator.pop]; Cancel discards everything.
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

  // ---- mask tool state -------------------------------------------------
  // Brush strokes accumulated in *image-pixel* coordinates so they map
  // unambiguously to the source image regardless of the display canvas size.
  final List<Path> _erasePaths = <Path>[];
  final List<FloodMask> _floodMasks = <FloodMask>[];
  double _brushSize = 24; // pixel radius in image space
  int _wandTolerance = 60;
  _MaskTool _maskTool = _MaskTool.brush;

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
      _erasePaths.clear();
      _floodMasks.clear();
      _cropFractional = const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9);
    });
  }

  // ---------------------------------------------------------------- crop

  Future<void> _applyCrop() async {
    setState(() => _busy = true);
    try {
      final Uint8List next = await _svc.cropPng(_working, _cropFractional);
      _working = next;
      await _decodeWorking();
    } catch (e) {
      _snack('Could not crop: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------------------------------------------------- rotate

  Future<void> _rotate(int quarters) async {
    setState(() => _busy = true);
    try {
      final Uint8List next = await _svc.rotateQuarterPng(_working, quarters);
      _working = next;
      await _decodeWorking();
    } catch (e) {
      _snack('Could not rotate: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- mask

  Future<void> _applyErasures() async {
    if (_erasePaths.isEmpty && _floodMasks.isEmpty) return;
    setState(() => _busy = true);
    try {
      final Uint8List next = await _svc.applyErasures(
        _working,
        erasePaths: List<Path>.of(_erasePaths),
        floodMasks: List<FloodMask>.of(_floodMasks),
      );
      _working = next;
      await _decodeWorking();
    } catch (e) {
      _snack('Could not apply erasures: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _undoLastMaskOp() {
    setState(() {
      if (_floodMasks.isNotEmpty) {
        _floodMasks.removeLast();
      } else if (_erasePaths.isNotEmpty) {
        _erasePaths.removeLast();
      }
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
          : Column(
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
    );
  }

  // ============================================================ crop tab

  Widget _buildCropTab() {
    final ui.Image image = _workingImage!;
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
                  onChange: (Rect r) => setState(() => _cropFractional = r),
                ),
              ),
            ),
          ),
        ),
        _bottomBar(
          children: <Widget>[
            Expanded(
              child: Text(
                'Drag the corners to set the crop area.',
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

  // ========================================================== rotate tab

  Widget _buildRotateTab() {
    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _AspectFitImage(
                image: _workingImage!,
                child: (_) => const SizedBox.expand(),
              ),
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
              'Free rotation\nfrom the canvas',
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
                  erasePaths: _erasePaths,
                  floodMasks: _floodMasks,
                  tool: _maskTool,
                  brushSize: _brushSize,
                  wandTolerance: _wandTolerance,
                  workingBytes: _working,
                  onStrokeStart: (Path p) {
                    setState(() => _erasePaths.add(p));
                  },
                  onStrokeUpdate: () {
                    // The path mutates in place; the overlay's painter
                    // listens to a notifier so the canvas repaints without
                    // a full setState here.
                  },
                  onStrokeEnd: () {},
                  onFloodMask: (FloodMask m) {
                    setState(() => _floodMasks.add(m));
                  },
                ),
              ),
            ),
          ),
        ),
        _maskToolbar(),
        _bottomBar(
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _busy || (_erasePaths.isEmpty && _floodMasks.isEmpty)
                  ? null
                  : _undoLastMaskOp,
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy || (_erasePaths.isEmpty && _floodMasks.isEmpty)
                  ? null
                  : _applyErasures,
              icon: const Icon(Icons.layers_clear),
              label: const Text('Apply erasures'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _maskToolbar() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            SegmentedButton<_MaskTool>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<_MaskTool>>[
                ButtonSegment<_MaskTool>(
                  value: _MaskTool.brush,
                  icon: Icon(Icons.brush),
                  label: Text('Brush'),
                ),
                ButtonSegment<_MaskTool>(
                  value: _MaskTool.wand,
                  icon: Icon(Icons.auto_fix_high),
                  label: Text('Wand'),
                ),
              ],
              selected: <_MaskTool>{_maskTool},
              onSelectionChanged: (Set<_MaskTool> s) =>
                  setState(() => _maskTool = s.first),
            ),
            const SizedBox(width: 16),
            if (_maskTool == _MaskTool.brush) ...<Widget>[
              const Text('Brush'),
              SizedBox(
                width: 160,
                child: Slider(
                  min: 4,
                  max: 96,
                  value: _brushSize,
                  onChanged: (double v) => setState(() => _brushSize = v),
                ),
              ),
              Text('${_brushSize.round()}px'),
            ] else ...<Widget>[
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
            ],
            const Spacer(),
            Text(
              _maskTool == _MaskTool.brush
                  ? 'Drag to erase'
                  : 'Tap a region to erase',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
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

enum _MaskTool { brush, wand }

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
    required this.onChange,
  });

  final Size displaySize;
  final Rect rect; // fractional 0..1
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

  void _resize(Offset deltaPx, double dxSign, double dySign) {
    final double dx = deltaPx.dx / displaySize.width;
    final double dy = deltaPx.dy / displaySize.height;
    double l = rect.left;
    double t = rect.top;
    double r = rect.right;
    double b = rect.bottom;
    if (dxSign < 0) {
      l = (l + dx).clamp(0.0, r - 0.05);
    } else {
      r = (r + dx).clamp(l + 0.05, 1.0);
    }
    if (dySign < 0) {
      t = (t + dy).clamp(0.0, b - 0.05);
    } else {
      b = (b + dy).clamp(t + 0.05, 1.0);
    }
    onChange(Rect.fromLTRB(l, t, r, b));
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
        // Move the crop rect by dragging its interior.
        Positioned(
          left: r.left,
          top: r.top,
          width: r.width,
          height: r.height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (DragUpdateDetails d) => _move(d.delta),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: accent, width: 2),
              ),
            ),
          ),
        ),
        // 4 corner handles.
        for (final ({double dxSign, double dySign}) corner
            in const <({double dxSign, double dySign})>[
              (dxSign: -1, dySign: -1),
              (dxSign: 1, dySign: -1),
              (dxSign: -1, dySign: 1),
              (dxSign: 1, dySign: 1),
            ])
          Positioned(
            left: corner.dxSign < 0 ? r.left - 10 : r.right - 10,
            top: corner.dySign < 0 ? r.top - 10 : r.bottom - 10,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (DragUpdateDetails d) =>
                  _resize(d.delta, corner.dxSign, corner.dySign),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: accent, width: 2),
                ),
              ),
            ),
          ),
      ],
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

// ============================================================ mask overlay

class _MaskEditorOverlay extends StatefulWidget {
  const _MaskEditorOverlay({
    required this.image,
    required this.displaySize,
    required this.erasePaths,
    required this.floodMasks,
    required this.tool,
    required this.brushSize,
    required this.wandTolerance,
    required this.workingBytes,
    required this.onStrokeStart,
    required this.onStrokeUpdate,
    required this.onStrokeEnd,
    required this.onFloodMask,
  });

  final ui.Image image;
  final Size displaySize;
  final List<Path> erasePaths;
  final List<FloodMask> floodMasks;
  final _MaskTool tool;
  final double brushSize;
  final int wandTolerance;
  final Uint8List workingBytes;
  final ValueChanged<Path> onStrokeStart;
  final VoidCallback onStrokeUpdate;
  final VoidCallback onStrokeEnd;
  final ValueChanged<FloodMask> onFloodMask;

  @override
  State<_MaskEditorOverlay> createState() => _MaskEditorOverlayState();
}

class _MaskEditorOverlayState extends State<_MaskEditorOverlay> {
  Path? _currentPath;
  // Triggers the painter to redraw without rebuilding any other widgets.
  final ValueNotifier<int> _repaintTick = ValueNotifier<int>(0);
  // Cached flood-mask images so we don't redecode them every frame.
  final Map<FloodMask, ui.Image> _maskImages = <FloodMask, ui.Image>{};
  // Magic-wand can take a few hundred ms; we lock the UI while it runs.
  bool _wandBusy = false;

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

  void _onPanStart(DragStartDetails d) {
    if (widget.tool != _MaskTool.brush) return;
    final Offset imgPt = _displayToImage(d.localPosition);
    final Path p = Path()
      ..addOval(Rect.fromCircle(center: imgPt, radius: widget.brushSize));
    _currentPath = p;
    widget.onStrokeStart(p);
    _repaintTick.value++;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (widget.tool != _MaskTool.brush || _currentPath == null) return;
    final Offset imgPt = _displayToImage(d.localPosition);
    _currentPath!.addOval(
      Rect.fromCircle(center: imgPt, radius: widget.brushSize),
    );
    widget.onStrokeUpdate();
    _repaintTick.value++;
  }

  void _onPanEnd(DragEndDetails _) {
    _currentPath = null;
    widget.onStrokeEnd();
  }

  Future<void> _onTap(TapDownDetails d) async {
    if (widget.tool != _MaskTool.wand || _wandBusy) return;
    final Offset imgPt = _displayToImage(d.localPosition);
    setState(() => _wandBusy = true);
    try {
      final FloodMask m = await _svc.floodFill(
        widget.workingBytes,
        imgPt.dx.round(),
        imgPt.dy.round(),
        tolerance: widget.wandTolerance,
      );
      widget.onFloodMask(m);
      // Pre-decode the mask image so subsequent repaints are smooth.
      _maskImages[m] = await _maskToUi(m);
      _repaintTick.value++;
    } finally {
      if (mounted) setState(() => _wandBusy = false);
    }
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
    return GestureDetector(
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
                erasePaths: widget.erasePaths,
                floodMaskImages: <ui.Image>[
                  for (final FloodMask m in widget.floodMasks)
                    if (_maskImages[m] != null) _maskImages[m]!,
                ],
                repaint: _repaintTick,
              ),
            ),
          ),
          if (_wandBusy) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

class _MaskCompositePainter extends CustomPainter {
  _MaskCompositePainter({
    required this.image,
    required this.erasePaths,
    required this.floodMaskImages,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ui.Image image;
  final List<Path> erasePaths;
  final List<ui.Image> floodMaskImages;

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
    // Paths are in image-pixel coords — scale down to display pixels.
    canvas.save();
    canvas.scale(sx, sy);
    for (final Path p in erasePaths) {
      canvas.drawPath(p, erase);
    }
    canvas.restore();
    for (final ui.Image m in floodMaskImages) {
      canvas.drawImageRect(
        m,
        Rect.fromLTWH(0, 0, m.width.toDouble(), m.height.toDouble()),
        dst,
        erase,
      );
    }
    canvas.restore();
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
    // We rely on the `repaint` Listenable; deep-compare is unnecessary.
    return !identical(old.image, image) ||
        !listEquals(old.floodMaskImages, floodMaskImages);
  }
}
