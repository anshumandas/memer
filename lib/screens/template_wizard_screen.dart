import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/meme_config.dart';
import '../models/meme_controller.dart';
import '../models/meme_template.dart';
import '../services/media_picker_service.dart';
import '../services/template_service.dart';
import '../widgets/meme_canvas.dart';
import 'editor_screen.dart';

/// Single-page wizard that lets the user fill in a template's editable
/// content (text + image slots) with a live preview alongside.
///
/// On "Open in editor" we hand the materialised [MemeConfig] off to the
/// regular [EditorScreen] so the user keeps every standard tool (drag,
/// resize, restyle, add/remove layers) after the wizard.
class TemplateWizardScreen extends StatefulWidget {
  const TemplateWizardScreen({super.key, required this.template});

  final MemeTemplate template;

  @override
  State<TemplateWizardScreen> createState() => _TemplateWizardScreenState();
}

class _TemplateWizardScreenState extends State<TemplateWizardScreen> {
  late final Uint8List _placeholder;

  /// Live values keyed by [LayerTemplate.id].
  final Map<String, String> _texts = <String, String>{};
  final Map<String, Uint8List> _images = <String, Uint8List>{};

  /// One controller per editable text input so cursor / IME state survives
  /// preview rebuilds. Disposed in [dispose].
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};

  /// The single MemeController that backs the live preview. Re-materialised
  /// whenever a slot changes by replacing its config wholesale.
  late MemeController _preview;

  @override
  void initState() {
    super.initState();
    _placeholder = TemplateService.instance.placeholderImage();

    // Seed defaults from the template.
    for (final LayerTemplate l in widget.template.editableLayers) {
      final String defaultText = _defaultTextFor(l);
      _texts[l.id] = defaultText;
      _textControllers[l.id] = TextEditingController(text: defaultText);
    }

    _preview = MemeController(_materialise());
  }

  @override
  void dispose() {
    for (final TextEditingController c in _textControllers.values) {
      c.dispose();
    }
    _preview.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- helpers

  String _defaultTextFor(LayerTemplate l) {
    switch (l) {
      case TextLayerTemplate():
        return l.text;
      case CalloutLayerTemplate():
        return l.text;
      case HyperlinkLayerTemplate():
        // "label|url" round-trips both via a single text field.
        if (l.label.isNotEmpty || l.url.isNotEmpty) {
          return '${l.label}|${l.url}';
        }
        return '';
      case BackgroundLayerTemplate():
      case ImageLayerTemplate():
        return '';
    }
  }

  MemeConfig _materialise() {
    return widget.template.instantiate(
      textValues: Map<String, String>.unmodifiable(_texts),
      imageValues: Map<String, Uint8List>.unmodifiable(_images),
      placeholderImageBytes: _placeholder,
    );
  }

  void _refreshPreview() {
    // Build a fresh config and stomp it into the preview controller. Cheap —
    // a meme is at most a handful of layers.
    final MemeConfig next = _materialise();
    _preview = MemeController(next);
    setState(() {});
  }

  Future<void> _pickImage(String slotId) async {
    const MediaPickerService picker = MediaPickerService();
    final Uint8List? bytes = await picker.pickImageBytes();
    if (bytes == null) return;
    _images[slotId] = bytes;
    _refreshPreview();
  }

  void _clearImage(String slotId) {
    _images.remove(slotId);
    _refreshPreview();
  }

  void _openInEditor() {
    final MemeConfig config = _materialise();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(initialConfig: config),
      ),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.template.name),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _openInEditor,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Open in editor'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool wide = constraints.maxWidth >= 900;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(flex: 5, child: _buildPreview()),
                const VerticalDivider(width: 1),
                SizedBox(width: 380, child: _buildForm(context)),
              ],
            );
          }
          // Narrow: stack preview on top, form below.
          return Column(
            children: <Widget>[
              SizedBox(height: 280, child: _buildPreview()),
              const Divider(height: 1),
              Expanded(child: _buildForm(context)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
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
              child: AspectRatio(
                aspectRatio: widget.template.aspect.ratio,
                child: IgnorePointer(child: MemeCanvas(controller: _preview)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final List<LayerTemplate> textFields = widget.template.editableLayers;
    final List<ImageLayerTemplate> imageSlots = widget.template.imageSlots;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: <Widget>[
        Text(
          widget.template.description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (textFields.isNotEmpty) ...<Widget>[
          Text('Captions', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final LayerTemplate l in textFields) _textInputFor(l),
          const SizedBox(height: 16),
        ],
        if (imageSlots.isNotEmpty) ...<Widget>[
          Text('Images', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final ImageLayerTemplate slot in imageSlots) _imageSlotFor(slot),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _openInEditor,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Open in editor'),
        ),
      ],
    );
  }

  Widget _textInputFor(LayerTemplate l) {
    // Hyperlinks get two fields (label + URL); everything else gets one
    // multi-line text field.
    if (l is HyperlinkLayerTemplate) {
      final TextEditingController c = _textControllers[l.id]!;
      // Split current value into label / url parts.
      final String raw = c.text;
      final List<String> parts = raw.contains('|')
          ? raw.split('|')
          : <String>['', raw];
      final String currentLabel = parts.first;
      final String currentUrl = parts.sublist(1).join('|');
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.promptLabel ?? 'Link',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Display text',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: currentLabel),
              onChanged: (String v) {
                final String combined = '$v|$currentUrl';
                c.value = TextEditingValue(text: combined);
                _texts[l.id] = combined;
                _refreshPreview();
              },
            ),
            const SizedBox(height: 6),
            TextField(
              decoration: const InputDecoration(
                labelText: 'URL',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: currentUrl),
              onChanged: (String v) {
                final String combined = '$currentLabel|$v';
                c.value = TextEditingValue(text: combined);
                _texts[l.id] = combined;
                _refreshPreview();
              },
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _textControllers[l.id],
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: l.promptLabel ?? 'Text',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (String v) {
          _texts[l.id] = v;
          _refreshPreview();
        },
      ),
    );
  }

  Widget _imageSlotFor(ImageLayerTemplate slot) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Uint8List? picked = _images[slot.id];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            slot.promptLabel ?? 'Image',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 56,
                  height: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      picked ?? _placeholder,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    picked == null
                        ? 'No image selected (placeholder shown)'
                        : 'Image selected',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (picked != null)
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () => _clearImage(slot.id),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                TextButton.icon(
                  onPressed: () => _pickImage(slot.id),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(picked == null ? 'Pick' : 'Replace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
