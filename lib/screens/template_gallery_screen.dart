import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/meme_config.dart';
import '../models/meme_controller.dart';
import '../models/meme_template.dart';
import '../services/template_service.dart';
import '../widgets/meme_canvas.dart';
import 'template_wizard_screen.dart';

/// Grid of bundled templates. Each card is a tiny live render of the
/// template using its default placeholder content, so the user can see what
/// they're about to start from.
class TemplateGalleryScreen extends StatefulWidget {
  const TemplateGalleryScreen({super.key});

  @override
  State<TemplateGalleryScreen> createState() => _TemplateGalleryScreenState();
}

class _TemplateGalleryScreenState extends State<TemplateGalleryScreen> {
  late final Future<List<MemeTemplate>> _futureTemplates;
  late final Uint8List _placeholder;

  @override
  void initState() {
    super.initState();
    _placeholder = TemplateService.instance.placeholderImage();
    _futureTemplates = TemplateService.instance.loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a template')),
      body: FutureBuilder<List<MemeTemplate>>(
        future: _futureTemplates,
        builder:
            (BuildContext context, AsyncSnapshot<List<MemeTemplate>> snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final List<MemeTemplate> templates =
                  snap.data ?? <MemeTemplate>[];
              if (templates.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No templates available.\n'
                      'Add JSON files to assets/templates/ and rerun '
                      "'flutter pub get'.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  // Aim for ~220px-wide cards.
                  final int cols = (constraints.maxWidth / 240).floor().clamp(
                    1,
                    5,
                  );
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: templates.length,
                    itemBuilder: (BuildContext context, int i) {
                      return _TemplateCard(
                        template: templates[i],
                        placeholderImage: _placeholder,
                      );
                    },
                  );
                },
              );
            },
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.placeholderImage});

  final MemeTemplate template;
  final Uint8List placeholderImage;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    // Build a non-interactive controller for the thumbnail. Each card creates
    // its own, kept alive only as long as the card is on screen.
    final MemeController controller = MemeController(
      template.instantiate(placeholderImageBytes: placeholderImage),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TemplateWizardScreen(template: template),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Container(
                color: scheme.surfaceContainerHighest,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(8),
                child: AspectRatio(
                  aspectRatio: template.aspect.ratio,
                  child: IgnorePointer(
                    child: MemeCanvas(controller: controller),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      template.name,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      template.category,
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                template.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
