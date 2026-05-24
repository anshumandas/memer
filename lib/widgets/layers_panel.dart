import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/layer.dart';
import '../models/meme_controller.dart';
import '../services/media_picker_service.dart';

/// Vertical strip showing every layer in z-order (top of list = top of stack),
/// with controls to toggle visibility / lock, change opacity, rename, delete,
/// and reorder via drag.
class LayersPanel extends StatelessWidget {
  const LayersPanel({super.key, required this.controller});

  final MemeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // Reverse so the visually top layer appears at the top of the list — the
    // model stores bottom-first, but users expect Photoshop-style ordering.
    final List<Layer> visualOrder = controller.config.layers.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: <Widget>[
              Text('Layers', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              _AddLayerButton(controller: controller),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: visualOrder.length,
            onReorder: (int oldIdx, int newIdx) {
              // Translate visual (reversed) indices back to model indices.
              final int len = visualOrder.length;
              final int modelFrom = len - 1 - oldIdx;
              // ReorderableListView gives us the slot *after* removal, so when
              // dragging downward in the visual list we end up one off.
              int adjustedNew = newIdx;
              if (newIdx > oldIdx) adjustedNew -= 1;
              final int modelTo = len - 1 - adjustedNew;
              controller.reorder(modelFrom, modelTo);
            },
            itemBuilder: (BuildContext context, int i) {
              final Layer layer = visualOrder[i];
              final bool isSelected = controller.selectedLayerId == layer.id;
              return _LayerRow(
                key: ValueKey<String>(layer.id),
                controller: controller,
                layer: layer,
                selected: isSelected,
                accent: scheme.primary,
                dragIndex: i,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    super.key,
    required this.controller,
    required this.layer,
    required this.selected,
    required this.accent,
    required this.dragIndex,
  });

  final MemeController controller;
  final Layer layer;
  final bool selected;
  final Color accent;
  final int dragIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: selected ? accent.withOpacity(0.12) : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: selected ? accent : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: InkWell(
        onTap: () => controller.selectLayer(layer.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: <Widget>[
              ReorderableDragStartListener(
                index: dragIndex,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.drag_indicator, size: 18),
                ),
              ),
              _kindIcon(layer),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      layer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      _previewFor(layer),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: layer.visible ? 'Hide' : 'Show',
                onPressed: () =>
                    controller.setVisible(layer.id, !layer.visible),
                icon: Icon(
                  layer.visible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: layer.locked ? 'Unlock' : 'Lock',
                onPressed: () => controller.setLocked(layer.id, !layer.locked),
                icon: Icon(
                  layer.locked ? Icons.lock_outline : Icons.lock_open_outlined,
                  size: 18,
                ),
              ),
              if (layer is! BackgroundLayer)
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => controller.removeLayer(layer.id),
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindIcon(Layer l) {
    final IconData icon;
    switch (l) {
      case BackgroundLayer():
        icon = Icons.format_color_fill;
      case TextLayer():
        icon = Icons.text_fields;
      case HyperlinkLayer():
        icon = Icons.link;
      case ImageLayer():
        icon = Icons.image_outlined;
      case CalloutLayer():
        icon = Icons.chat_bubble_outline;
    }
    return Icon(icon, size: 18);
  }

  String _previewFor(Layer l) {
    switch (l) {
      case BackgroundLayer():
        return '#${l.color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
      case TextLayer():
        return l.text.isEmpty ? '(empty)' : l.text;
      case HyperlinkLayer():
        return l.url.isEmpty ? '(no URL)' : l.url;
      case ImageLayer():
        return '${(l.size.width * 100).round()}% × ${(l.size.height * 100).round()}%';
      case CalloutLayer():
        return l.text.isEmpty ? '(empty)' : l.text;
    }
  }
}

class _AddLayerButton extends StatelessWidget {
  const _AddLayerButton({required this.controller});

  final MemeController controller;

  Future<void> _pickImage(BuildContext context) async {
    const MediaPickerService picker = MediaPickerService();
    final Uint8List? bytes = await picker.pickImageBytes();
    if (bytes != null) controller.addImageLayer(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Add layer',
      icon: const Icon(Icons.add),
      itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'text',
          child: ListTile(
            leading: Icon(Icons.text_fields),
            title: Text('Text'),
            dense: true,
          ),
        ),
        PopupMenuItem<String>(
          value: 'hyperlink',
          child: ListTile(
            leading: Icon(Icons.link),
            title: Text('Hyperlink'),
            dense: true,
          ),
        ),
        PopupMenuItem<String>(
          value: 'image',
          child: ListTile(
            leading: Icon(Icons.image_outlined),
            title: Text('Image'),
            dense: true,
          ),
        ),
        PopupMenuItem<String>(
          value: 'callout',
          child: ListTile(
            leading: Icon(Icons.chat_bubble_outline),
            title: Text('Callout bubble'),
            dense: true,
          ),
        ),
      ],
      onSelected: (String v) {
        switch (v) {
          case 'text':
            controller.addTextLayer();
          case 'hyperlink':
            controller.addHyperlinkLayer();
          case 'image':
            _pickImage(context);
          case 'callout':
            controller.addCalloutLayer();
        }
      },
    );
  }
}
