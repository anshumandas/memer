import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../models/callout.dart';
import '../models/meme_config.dart';
import '../models/meme_controller.dart';
import '../services/image_export_service.dart';
import '../services/media_picker_service.dart';
import '../services/social/direct_api_poster.dart';
import '../services/social/share_sheet_poster.dart';
import '../services/social/social_poster.dart';
import '../widgets/meme_canvas.dart';

/// The main editing experience: live preview on one side, controls on the
/// other (stacked on narrow screens).
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final MemeController _controller = MemeController();
  final GlobalKey _repaintKey = GlobalKey();

  final ImageExportService _exporter = const ImageExportService();
  final MediaPickerService _picker = const MediaPickerService();

  final TextEditingController _topController = TextEditingController();
  final TextEditingController _bottomController = TextEditingController();
  final TextEditingController _calloutController = TextEditingController();
  final TextEditingController _headerController = TextEditingController();
  final TextEditingController _footnoteController = TextEditingController();
  final TextEditingController _linkUrlController = TextEditingController();
  final TextEditingController _linkLabelController = TextEditingController();

  String? _lastSelectedId;
  bool _busy = false;

  /// The available destinations. The first is the real, backend-free path;
  /// the others are documented stubs demonstrating the extension point.
  static const List<SocialPoster> _posters = <SocialPoster>[
    ShareSheetPoster(),
    XApiPoster(),
    InstagramApiPoster(),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncFromController);
    _controller.dispose();
    _topController.dispose();
    _bottomController.dispose();
    _calloutController.dispose();
    _headerController.dispose();
    _footnoteController.dispose();
    _linkUrlController.dispose();
    _linkLabelController.dispose();
    super.dispose();
  }

  /// Keeps the callout text field in sync when the selection changes, without
  /// fighting the user's cursor while they type.
  void _syncFromController() {
    final String? id = _controller.selectedCalloutId;
    if (id != _lastSelectedId) {
      _lastSelectedId = id;
      _calloutController.text = _controller.selectedCallout?.text ?? '';
    }
    _syncIfDifferent(_topController, _controller.config.topText);
    _syncIfDifferent(_bottomController, _controller.config.bottomText);
    _syncIfDifferent(_headerController, _controller.config.headerText);
    _syncIfDifferent(_footnoteController, _controller.config.footnoteText);
    _syncIfDifferent(_linkUrlController, _controller.config.linkUrl);
    _syncIfDifferent(_linkLabelController, _controller.config.linkLabel);
  }

  /// Only writes to a [TextEditingController] when the value really differs,
  /// to avoid stomping the cursor while the user types.
  void _syncIfDifferent(TextEditingController c, String value) {
    if (c.text != value) c.text = value;
  }

  // -------------------------------------------------------------- actions

  Future<void> _pickBackgroundImage() async {
    final Uint8List? bytes = await _picker.pickImageBytes();
    if (bytes != null) _controller.setBackgroundImage(bytes);
  }

  Future<void> _post(SocialPoster poster) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Hide the selection outline so it isn't baked into the export.
      _controller.clearSelection();
      await WidgetsBinding.instance.endOfFrame;

      final Uint8List bytes = await _exporter.capturePng(_repaintKey);
      final PostResult result =
          await poster.post(imageBytes: bytes, caption: _composeCaption());
      _showSnack(result.message ?? (result.isSuccess ? 'Done!' : 'Failed.'));
    } catch (e) {
      _showSnack('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveToDisk() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _controller.clearSelection();
      await WidgetsBinding.instance.endOfFrame;

      final Uint8List bytes = await _exporter.capturePng(_repaintKey);
      final String? path = await _exporter.savePngToDisk(bytes);
      _showSnack(path == null ? 'Save cancelled.' : 'Saved to $path');
    } catch (e) {
      _showSnack('Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _composeCaption() {
    final List<String> parts = <String>[
      _controller.config.headerText.trim(),
      _controller.config.topText.trim(),
      _controller.config.bottomText.trim(),
      _controller.config.footnoteText.trim(),
      // Append the link so it survives the share (PNGs can't carry a live
      // hyperlink, but most share targets make URLs in the caption clickable).
      _controller.config.linkUrl.trim(),
    ].where((String s) => s.isNotEmpty).toList();
    return parts.join(' ');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Color?> _showColorPicker(Color initial) {
    Color picked = initial;
    return showDialog<Color>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pick a colour'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: initial,
              onColorChanged: (Color c) => picked = c,
              enableAlpha: false,
              labelTypes: const <ColorLabelType>[],
              pickerAreaHeightPercent: 0.7,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(picked),
              child: const Text('Select'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Save image',
            onPressed: _busy ? null : _saveToDisk,
            icon: const Icon(Icons.download_outlined),
          ),
          PopupMenuButton<SocialPoster>(
            tooltip: 'Post to…',
            icon: const Icon(Icons.send_outlined),
            enabled: !_busy,
            onSelected: _post,
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<SocialPoster>>[
              for (final SocialPoster p in _posters)
                PopupMenuItem<SocialPoster>(value: p, child: Text(p.label)),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool wide = constraints.maxWidth >= 820;
          final Widget canvas = _buildCanvasArea();
          final Widget controls = _buildControls();

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(flex: 5, child: Center(child: canvas)),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(child: controls),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            child: Column(
              children: <Widget>[
                Padding(padding: const EdgeInsets.all(16), child: canvas),
                controls,
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildShareBar(),
    );
  }

  Widget _buildCanvasArea() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 460),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _controller.clearSelection,
              child: ListenableBuilder(
                listenable: _controller,
                builder: (BuildContext context, _) => MemeCanvas(
                  controller: _controller,
                  repaintKey: _repaintKey,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShareBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _post(const ShareSheetPoster()),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share),
                label: Text(_busy ? 'Working…' : 'Share to apps…'),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _saveToDisk,
              icon: const Icon(Icons.save_alt),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _section('Captions', <Widget>[
                TextField(
                  controller: _topController,
                  decoration: const InputDecoration(
                    labelText: 'Top text',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: _controller.setTopText,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bottomController,
                  decoration: const InputDecoration(
                    labelText: 'Bottom text',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: _controller.setBottomText,
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Text('Text colour',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const Spacer(),
                    _swatch(
                      _controller.config.memeTextColor,
                      () async {
                        final Color? c = await _showColorPicker(
                            _controller.config.memeTextColor);
                        if (c != null) _controller.setMemeTextColor(c);
                      },
                    ),
                  ],
                ),
              ]),
              _section('Header & footnote', <Widget>[
                TextField(
                  controller: _headerController,
                  decoration: const InputDecoration(
                    labelText: 'Header (small, top)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: _controller.setHeaderText,
                ),
                const SizedBox(height: 8),
                _alignRow(
                  current: _controller.config.headerAlign,
                  onChanged: _controller.setHeaderAlign,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _footnoteController,
                  decoration: const InputDecoration(
                    labelText: 'Footnote (small, bottom)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: _controller.setFootnoteText,
                ),
                const SizedBox(height: 8),
                _alignRow(
                  current: _controller.config.footnoteAlign,
                  onChanged: _controller.setFootnoteAlign,
                ),
              ]),
              _section('Hyperlink', <Widget>[
                TextField(
                  controller: _linkUrlController,
                  decoration: const InputDecoration(
                    labelText: 'URL (e.g. https://example.com)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: _controller.setLinkUrl,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _linkLabelController,
                  decoration: const InputDecoration(
                    labelText: 'Display label (optional)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: _controller.setLinkLabel,
                ),
                const SizedBox(height: 8),
                _alignRow(
                  current: _controller.config.linkAlign,
                  onChanged: _controller.setLinkAlign,
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap the link in the preview to open it. Exported PNGs can’t '
                  'carry a live link, so the URL is also added to the share caption.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ]),
              _section('Background', <Widget>[
                Row(
                  children: <Widget>[
                    Text('Colour',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const Spacer(),
                    _swatch(
                      _controller.config.backgroundColor,
                      () async {
                        final Color? c = await _showColorPicker(
                            _controller.config.backgroundColor);
                        if (c != null) _controller.setBackgroundColor(c);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickBackgroundImage,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(_controller.config.hasBackgroundImage
                            ? 'Replace image'
                            : 'Add image'),
                      ),
                    ),
                    if (_controller.config.hasBackgroundImage) ...<Widget>[
                      const SizedBox(width: 12),
                      IconButton.outlined(
                        tooltip: 'Remove image',
                        onPressed: _controller.clearBackgroundImage,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ],
                ),
              ]),
              _section('Speech bubbles', <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _controller.addCallout(),
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('Add bubble'),
                  ),
                ),
                const SizedBox(height: 4),
                _buildCalloutInspector(),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCalloutInspector() {
    final Callout? c = _controller.selectedCallout;
    if (c == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Tap a bubble on the meme to edit it, or drag it to reposition.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _calloutController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Bubble text',
                border: OutlineInputBorder(),
              ),
              onChanged: (String v) => _controller.updateCallout(
                c.id,
                (Callout cc) => cc.copyWith(text: v),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Text('Tail'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<CalloutTail>(
                    isExpanded: true,
                    value: c.tail,
                    onChanged: (CalloutTail? t) {
                      if (t != null) {
                        _controller.updateCallout(
                          c.id,
                          (Callout cc) => cc.copyWith(tail: t),
                        );
                      }
                    },
                    items: const <DropdownMenuItem<CalloutTail>>[
                      DropdownMenuItem<CalloutTail>(
                        value: CalloutTail.bottomLeft,
                        child: Text('Bottom-left'),
                      ),
                      DropdownMenuItem<CalloutTail>(
                        value: CalloutTail.bottomRight,
                        child: Text('Bottom-right'),
                      ),
                      DropdownMenuItem<CalloutTail>(
                        value: CalloutTail.topLeft,
                        child: Text('Top-left'),
                      ),
                      DropdownMenuItem<CalloutTail>(
                        value: CalloutTail.topRight,
                        child: Text('Top-right'),
                      ),
                      DropdownMenuItem<CalloutTail>(
                        value: CalloutTail.none,
                        child: Text('No tail'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                const Text('Size'),
                Expanded(
                  child: Slider(
                    min: 10,
                    max: 40,
                    value: c.fontSize.clamp(10.0, 40.0),
                    onChanged: (double v) => _controller.updateCallout(
                      c.id,
                      (Callout cc) => cc.copyWith(fontSize: v),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: <Widget>[
                const Text('Bubble'),
                const SizedBox(width: 8),
                _swatch(c.bubbleColor, () async {
                  final Color? col = await _showColorPicker(c.bubbleColor);
                  if (col != null) {
                    _controller.updateCallout(
                      c.id,
                      (Callout cc) => cc.copyWith(bubbleColor: col),
                    );
                  }
                }),
                const SizedBox(width: 20),
                const Text('Text'),
                const SizedBox(width: 8),
                _swatch(c.textColor, () async {
                  final Color? col = await _showColorPicker(c.textColor);
                  if (col != null) {
                    _controller.updateCallout(
                      c.id,
                      (Callout cc) => cc.copyWith(textColor: col),
                    );
                  }
                }),
                const Spacer(),
                IconButton(
                  tooltip: 'Delete bubble',
                  onPressed: () => _controller.removeCallout(c.id),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _alignRow({
    required MemeTextAlign current,
    required ValueChanged<MemeTextAlign> onChanged,
  }) {
    return Row(
      children: <Widget>[
        Text('Align', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: 12),
        SegmentedButton<MemeTextAlign>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<MemeTextAlign>>[
            ButtonSegment<MemeTextAlign>(
              value: MemeTextAlign.left,
              icon: Icon(Icons.format_align_left),
            ),
            ButtonSegment<MemeTextAlign>(
              value: MemeTextAlign.center,
              icon: Icon(Icons.format_align_center),
            ),
            ButtonSegment<MemeTextAlign>(
              value: MemeTextAlign.right,
              icon: Icon(Icons.format_align_right),
            ),
          ],
          selected: <MemeTextAlign>{current},
          onSelectionChanged: (Set<MemeTextAlign> s) => onChanged(s.first),
        ),
      ],
    );
  }

  Widget _swatch(Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black.withOpacity(0.2)),
        ),
      ),
    );
  }
}
