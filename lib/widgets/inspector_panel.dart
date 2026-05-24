import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../models/layer.dart';
import '../models/meme_controller.dart';
import '../screens/image_editor_screen.dart';
import '../services/media_picker_service.dart';

/// Right-hand panel that shows controls for the currently selected layer.
/// Each layer kind has its own sub-inspector; an empty placeholder is shown
/// when nothing is selected.
class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key, required this.controller});

  final MemeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final Layer? layer = controller.selectedLayer;
    if (layer == null) {
      return const _Empty(
        message:
            'Select a layer (tap it on the canvas or in the layers panel) to '
            'see its controls here.',
      );
    }
    final Widget body;
    switch (layer) {
      case BackgroundLayer():
        body = _BackgroundInspector(controller: controller, layer: layer);
      case TextLayer():
        body = _TextInspector(controller: controller, layer: layer);
      case HyperlinkLayer():
        body = _HyperlinkInspector(controller: controller, layer: layer);
      case ImageLayer():
        body = _ImageInspector(controller: controller, layer: layer);
      case CalloutLayer():
        body = _CalloutInspector(controller: controller, layer: layer);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _LayerHeader(controller: controller, layer: layer),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _LayerHeader extends StatelessWidget {
  const _LayerHeader({required this.controller, required this.layer});

  final MemeController controller;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: TextEditingController(text: layer.name),
              decoration: const InputDecoration(
                labelText: 'Layer name',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (String v) => controller.rename(layer.id, v),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Text('Opacity'),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 1,
                    value: layer.opacity.clamp(0.0, 1.0),
                    onChanged: (double v) => controller.setOpacity(layer.id, v),
                  ),
                ),
                Text('${(layer.opacity * 100).round()}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================ background

class _BackgroundInspector extends StatelessWidget {
  const _BackgroundInspector({required this.controller, required this.layer});
  final MemeController controller;
  final BackgroundLayer layer;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Background',
      child: Row(
        children: <Widget>[
          const Text('Colour'),
          const Spacer(),
          _Swatch(
            color: layer.color,
            onTap: () async {
              final Color? c = await _pickColor(context, layer.color);
              if (c != null) {
                controller.updateLayer(
                  layer.id,
                  (Layer l) => (l as BackgroundLayer).copyWith(color: c),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================ text

class _TextInspector extends StatefulWidget {
  const _TextInspector({required this.controller, required this.layer});
  final MemeController controller;
  final TextLayer layer;

  @override
  State<_TextInspector> createState() => _TextInspectorState();
}

class _TextInspectorState extends State<_TextInspector> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.layer.text);
  }

  @override
  void didUpdateWidget(covariant _TextInspector old) {
    super.didUpdateWidget(old);
    if (old.layer.id != widget.layer.id && _text.text != widget.layer.text) {
      _text.text = widget.layer.text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _patch(TextLayer Function(TextLayer) f) {
    widget.controller
        .updateLayer(widget.layer.id, (Layer l) => f(l as TextLayer));
  }

  @override
  Widget build(BuildContext context) {
    final TextLayer l = widget.layer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Section(
          title: 'Text',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _text,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Content',
                  border: OutlineInputBorder(),
                ),
                onChanged: (String v) =>
                    _patch((TextLayer t) => t.copyWith(text: v)),
              ),
              const SizedBox(height: 12),
              _FontDropdown(
                value: l.fontFamily,
                onChanged: (String v) =>
                    _patch((TextLayer t) => t.copyWith(fontFamily: v)),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  const Text('Size'),
                  Expanded(
                    child: Slider(
                      min: 0.02,
                      max: 0.25,
                      value: l.fontSize.clamp(0.02, 0.25),
                      onChanged: (double v) =>
                          _patch((TextLayer t) => t.copyWith(fontSize: v)),
                    ),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  const Text('Colour'),
                  const SizedBox(width: 12),
                  _Swatch(
                    color: l.color,
                    onTap: () async {
                      final Color? c = await _pickColor(context, l.color);
                      if (c != null) {
                        _patch((TextLayer t) => t.copyWith(color: c));
                      }
                    },
                  ),
                  const Spacer(),
                  IconButton.outlined(
                    tooltip: 'Bold',
                    onPressed: () =>
                        _patch((TextLayer t) => t.copyWith(bold: !t.bold)),
                    isSelected: l.bold,
                    icon: const Icon(Icons.format_bold),
                  ),
                  const SizedBox(width: 4),
                  IconButton.outlined(
                    tooltip: 'Italic',
                    onPressed: () =>
                        _patch((TextLayer t) => t.copyWith(italic: !t.italic)),
                    isSelected: l.italic,
                    icon: const Icon(Icons.format_italic),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AlignSegmented(
                value: l.align,
                onChanged: (LayerTextAlign a) =>
                    _patch((TextLayer t) => t.copyWith(align: a)),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Outlined (impact-style)'),
                value: l.outlined,
                onChanged: (bool v) =>
                    _patch((TextLayer t) => t.copyWith(outlined: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================ hyperlink

class _HyperlinkInspector extends StatefulWidget {
  const _HyperlinkInspector({required this.controller, required this.layer});
  final MemeController controller;
  final HyperlinkLayer layer;

  @override
  State<_HyperlinkInspector> createState() => _HyperlinkInspectorState();
}

class _HyperlinkInspectorState extends State<_HyperlinkInspector> {
  late final TextEditingController _url;
  late final TextEditingController _label;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.layer.url);
    _label = TextEditingController(text: widget.layer.label);
  }

  @override
  void didUpdateWidget(covariant _HyperlinkInspector old) {
    super.didUpdateWidget(old);
    if (old.layer.id != widget.layer.id) {
      _url.text = widget.layer.url;
      _label.text = widget.layer.label;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _label.dispose();
    super.dispose();
  }

  void _patch(HyperlinkLayer Function(HyperlinkLayer) f) {
    widget.controller
        .updateLayer(widget.layer.id, (Layer l) => f(l as HyperlinkLayer));
  }

  @override
  Widget build(BuildContext context) {
    final HyperlinkLayer l = widget.layer;
    return _Section(
      title: 'Hyperlink',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'URL',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (String v) =>
                _patch((HyperlinkLayer h) => h.copyWith(url: v)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              labelText: 'Display label (optional)',
              border: OutlineInputBorder(),
            ),
            onChanged: (String v) =>
                _patch((HyperlinkLayer h) => h.copyWith(label: v)),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: l.url.trim().isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: l.url.trim()),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(content: Text('Link copied')),
                          );
                      },
                icon: const Icon(Icons.copy),
                label: const Text('Copy link'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FontDropdown(
            value: l.fontFamily,
            onChanged: (String v) =>
                _patch((HyperlinkLayer h) => h.copyWith(fontFamily: v)),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Text('Size'),
              Expanded(
                child: Slider(
                  min: 0.02,
                  max: 0.12,
                  value: l.fontSize.clamp(0.02, 0.12),
                  onChanged: (double v) =>
                      _patch((HyperlinkLayer h) => h.copyWith(fontSize: v)),
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              const Text('Colour'),
              const SizedBox(width: 12),
              _Swatch(
                color: l.color,
                onTap: () async {
                  final Color? c = await _pickColor(context, l.color);
                  if (c != null) {
                    _patch((HyperlinkLayer h) => h.copyWith(color: c));
                  }
                },
              ),
              const Spacer(),
              IconButton.outlined(
                tooltip: 'Bold',
                onPressed: () =>
                    _patch((HyperlinkLayer h) => h.copyWith(bold: !h.bold)),
                isSelected: l.bold,
                icon: const Icon(Icons.format_bold),
              ),
              const SizedBox(width: 4),
              IconButton.outlined(
                tooltip: 'Italic',
                onPressed: () =>
                    _patch((HyperlinkLayer h) => h.copyWith(italic: !h.italic)),
                isSelected: l.italic,
                icon: const Icon(Icons.format_italic),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AlignSegmented(
            value: l.align,
            onChanged: (LayerTextAlign a) =>
                _patch((HyperlinkLayer h) => h.copyWith(align: a)),
          ),
          const SizedBox(height: 6),
          Text(
            'PNGs can\'t carry a clickable link, so the URL is also appended '
            'to the share caption when you post.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ============================================================ image

class _ImageInspector extends StatelessWidget {
  const _ImageInspector({required this.controller, required this.layer});
  final MemeController controller;
  final ImageLayer layer;

  Future<void> _replace(BuildContext context) async {
    const MediaPickerService picker = MediaPickerService();
    final Uint8List? bytes = await picker.pickImageBytes();
    if (bytes == null) return;
    controller.updateLayer(
      layer.id,
      (Layer l) => (l as ImageLayer).copyWith(
        bytes: bytes,
        originalBytes: bytes,
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    final Uint8List? edited = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
        fullscreenDialog: true,
        builder: (_) => ImageEditorScreen(
          initialBytes: layer.bytes,
          originalBytes: layer.originalBytes,
        ),
      ),
    );
    if (edited == null) return;
    controller.updateLayer(
      layer.id,
      // Preserve originalBytes so the user can keep using "Reset to original"
      // across multiple editor sessions.
      (Layer l) => (l as ImageLayer).copyWith(bytes: edited),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Image',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openEditor(context),
                  icon: const Icon(Icons.tune),
                  label: const Text('Edit image…'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _replace(context),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Replace'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Editor offers crop, 90° rotate, and a manual remove-background '
            'painter (brush + magic-wand). Drag corners on the main canvas to '
            'resize; use the rotate handle for free rotation.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ============================================================ callout

class _CalloutInspector extends StatefulWidget {
  const _CalloutInspector({required this.controller, required this.layer});
  final MemeController controller;
  final CalloutLayer layer;

  @override
  State<_CalloutInspector> createState() => _CalloutInspectorState();
}

class _CalloutInspectorState extends State<_CalloutInspector> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.layer.text);
  }

  @override
  void didUpdateWidget(covariant _CalloutInspector old) {
    super.didUpdateWidget(old);
    if (old.layer.id != widget.layer.id) _text.text = widget.layer.text;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _patch(CalloutLayer Function(CalloutLayer) f) {
    widget.controller
        .updateLayer(widget.layer.id, (Layer l) => f(l as CalloutLayer));
  }

  @override
  Widget build(BuildContext context) {
    final CalloutLayer l = widget.layer;
    return _Section(
      title: 'Callout bubble',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final CalloutKind k in CalloutKind.values)
                ChoiceChip(
                  label: Text(_labelFor(k)),
                  selected: l.shape == k,
                  onSelected: (bool s) {
                    if (s) _patch((CalloutLayer c) => c.copyWith(shape: k));
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Bubble text',
              border: OutlineInputBorder(),
            ),
            onChanged: (String v) =>
                _patch((CalloutLayer c) => c.copyWith(text: v)),
          ),
          const SizedBox(height: 12),
          _FontDropdown(
            value: l.fontFamily,
            onChanged: (String v) =>
                _patch((CalloutLayer c) => c.copyWith(fontFamily: v)),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const Text('Text size'),
              Expanded(
                child: Slider(
                  min: 0.02,
                  max: 0.15,
                  value: l.fontSize.clamp(0.02, 0.15),
                  onChanged: (double v) =>
                      _patch((CalloutLayer c) => c.copyWith(fontSize: v)),
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              const Text('Fill'),
              const SizedBox(width: 8),
              _Swatch(
                color: l.fillColor,
                onTap: () async {
                  final Color? c = await _pickColor(context, l.fillColor);
                  if (c != null) {
                    _patch((CalloutLayer cc) => cc.copyWith(fillColor: c));
                  }
                },
              ),
              const SizedBox(width: 20),
              const Text('Border'),
              const SizedBox(width: 8),
              _Swatch(
                color: l.borderColor,
                onTap: () async {
                  final Color? c = await _pickColor(context, l.borderColor);
                  if (c != null) {
                    _patch((CalloutLayer cc) => cc.copyWith(borderColor: c));
                  }
                },
              ),
              const SizedBox(width: 20),
              const Text('Text'),
              const SizedBox(width: 8),
              _Swatch(
                color: l.textColor,
                onTap: () async {
                  final Color? c = await _pickColor(context, l.textColor);
                  if (c != null) {
                    _patch((CalloutLayer cc) => cc.copyWith(textColor: c));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Text('Border width'),
              Expanded(
                child: Slider(
                  min: 0,
                  max: 6,
                  value: l.borderWidth.clamp(0.0, 6.0),
                  onChanged: (double v) =>
                      _patch((CalloutLayer c) => c.copyWith(borderWidth: v)),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show tail'),
            subtitle: const Text(
                'Drag the small circle on the canvas to point the tail.'),
            value: l.showTail,
            onChanged: (bool v) =>
                _patch((CalloutLayer c) => c.copyWith(showTail: v)),
          ),
        ],
      ),
    );
  }

  String _labelFor(CalloutKind k) {
    switch (k) {
      case CalloutKind.speechRound:
        return 'Speech (round)';
      case CalloutKind.speechSharp:
        return 'Speech (sharp)';
      case CalloutKind.thoughtCloud:
        return 'Thought cloud';
      case CalloutKind.rectangle:
        return 'Rectangle';
      case CalloutKind.oval:
        return 'Oval';
      case CalloutKind.scallop:
        return 'Scallop';
    }
  }
}

// ============================================================ shared bits

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.onTap});
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black.withOpacity(0.25)),
        ),
      ),
    );
  }
}

class _FontDropdown extends StatelessWidget {
  const _FontDropdown({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: kAvailableFonts.contains(value) ? value : kAvailableFonts.first,
      decoration: const InputDecoration(
        labelText: 'Font',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: <DropdownMenuItem<String>>[
        for (final String f in kAvailableFonts)
          DropdownMenuItem<String>(
            value: f,
            child: Text(f, style: TextStyle(fontFamily: f)),
          ),
      ],
      onChanged: (String? v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _AlignSegmented extends StatelessWidget {
  const _AlignSegmented({required this.value, required this.onChanged});
  final LayerTextAlign value;
  final ValueChanged<LayerTextAlign> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<LayerTextAlign>(
      showSelectedIcon: false,
      segments: const <ButtonSegment<LayerTextAlign>>[
        ButtonSegment<LayerTextAlign>(
          value: LayerTextAlign.left,
          icon: Icon(Icons.format_align_left),
        ),
        ButtonSegment<LayerTextAlign>(
          value: LayerTextAlign.center,
          icon: Icon(Icons.format_align_center),
        ),
        ButtonSegment<LayerTextAlign>(
          value: LayerTextAlign.right,
          icon: Icon(Icons.format_align_right),
        ),
      ],
      selected: <LayerTextAlign>{value},
      onSelectionChanged: (Set<LayerTextAlign> s) => onChanged(s.first),
    );
  }
}

Future<Color?> _pickColor(BuildContext context, Color initial) {
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
            enableAlpha: true,
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
