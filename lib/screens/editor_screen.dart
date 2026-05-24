import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/layer.dart';
import '../models/meme_config.dart';
import '../models/meme_controller.dart';
import '../services/image_export_service.dart';
import '../services/social/direct_api_poster.dart';
import '../services/social/share_sheet_poster.dart';
import '../services/social/social_poster.dart';
import '../widgets/inspector_panel.dart';
import '../widgets/layers_panel.dart';
import '../widgets/meme_canvas.dart';
import '../widgets/selection_overlay.dart';

/// The main editing experience. Three logical panes:
///
///   1. **Layers** — the z-ordered list of layers (with add / reorder / etc.)
///   2. **Canvas** — the meme preview plus the interactive selection overlay
///   3. **Inspector** — controls for the currently selected layer
///
/// On wide screens all three sit side-by-side. On narrow screens the layers
/// and inspector become tabs in a bottom sheet, keeping the canvas in focus.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final MemeController _controller = MemeController();
  final GlobalKey _repaintKey = GlobalKey();

  final ImageExportService _exporter = const ImageExportService();

  bool _busy = false;

  /// Available "post to" destinations. The first is the real, backend-free
  /// path; the others are documented stubs (replaced with concrete posters
  /// in Phase 3).
  static const List<SocialPoster> _posters = <SocialPoster>[
    ShareSheetPoster(),
    XApiPoster(),
    InstagramApiPoster(),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- actions

  Future<void> _share(SocialPoster poster) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Hide selection chrome so it's not baked into the export.
      _controller.clearSelection();
      await WidgetsBinding.instance.endOfFrame;

      final Uint8List bytes = await _exporter.capturePng(_repaintKey);
      final PostResult result = await poster.post(
        imageBytes: bytes,
        caption: _composeCaption(),
      );
      _snack(result.message ?? (result.isSuccess ? 'Done!' : 'Failed.'));
    } catch (e) {
      _snack('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _controller.clearSelection();
      await WidgetsBinding.instance.endOfFrame;

      final Uint8List bytes = await _exporter.capturePng(_repaintKey);
      final String? path = await _exporter.savePngToDisk(bytes);
      _snack(path == null ? 'Save cancelled.' : 'Saved to $path');
    } catch (e) {
      _snack('Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Caption sent alongside the image: every text-bearing layer's content
  /// joined with spaces, plus the URL of every hyperlink layer (because PNGs
  /// can't carry a clickable link — appending it ensures the URL travels
  /// with the share even when stripped from the visible image).
  String _composeCaption() {
    final List<String> parts = <String>[];
    for (final Layer l in _controller.config.layers) {
      if (!l.visible) continue;
      switch (l) {
        case TextLayer():
          if (l.text.trim().isNotEmpty) parts.add(l.text.trim());
        case CalloutLayer():
          if (l.text.trim().isNotEmpty) parts.add(l.text.trim());
        case HyperlinkLayer():
          if (l.url.trim().isNotEmpty) parts.add(l.url.trim());
        case BackgroundLayer():
        case ImageLayer():
          break;
      }
    }
    return parts.join(' ');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    // No outer ListenableBuilder here: each panel listens independently so a
    // layer drag rebuilds only the canvas + overlay (and the inspector, when
    // it's showing the moving layer), not the whole scaffold.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor'),
        actions: <Widget>[
          _AspectMenu(controller: _controller),
          IconButton(
            tooltip: 'Save image',
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.download_outlined),
          ),
          PopupMenuButton<SocialPoster>(
            tooltip: 'Post to…',
            icon: const Icon(Icons.send_outlined),
            enabled: !_busy,
            onSelected: _share,
            itemBuilder: (BuildContext _) => <PopupMenuEntry<SocialPoster>>[
              for (final SocialPoster p in _posters)
                PopupMenuItem<SocialPoster>(value: p, child: Text(p.label)),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool wide = constraints.maxWidth >= 980;
          if (wide) return _buildWide(context);
          return _buildNarrow(context);
        },
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(width: 260, child: LayersPanel(controller: _controller)),
        const VerticalDivider(width: 1),
        Expanded(child: _buildCanvasArea()),
        const VerticalDivider(width: 1),
        SizedBox(width: 340, child: InspectorPanel(controller: _controller)),
      ],
    );
  }

  Widget _buildNarrow(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          Expanded(flex: 5, child: _buildCanvasArea()),
          const Divider(height: 1),
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              tabs: <Tab>[
                Tab(icon: Icon(Icons.layers_outlined), text: 'Layers'),
                Tab(icon: Icon(Icons.tune), text: 'Inspector'),
              ],
            ),
          ),
          SizedBox(
            height: 340,
            child: TabBarView(
              children: <Widget>[
                LayersPanel(controller: _controller),
                InspectorPanel(controller: _controller),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasArea() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: <Widget>[
                  MemeCanvas(controller: _controller, repaintKey: _repaintKey),
                  Positioned.fill(
                    child: LayerSelectionOverlay(controller: _controller),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AspectMenu extends StatelessWidget {
  const _AspectMenu({required this.controller});
  final MemeController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CanvasAspect>(
      tooltip: 'Canvas size',
      icon: const Icon(Icons.aspect_ratio),
      onSelected: controller.setAspect,
      itemBuilder: (BuildContext _) => <PopupMenuEntry<CanvasAspect>>[
        for (final CanvasAspect a in CanvasAspect.values)
          CheckedPopupMenuItem<CanvasAspect>(
            value: a,
            checked: controller.config.aspect == a,
            child: Text(a.label),
          ),
      ],
    );
  }
}
