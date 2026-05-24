import 'package:flutter/material.dart';

import 'editor_screen.dart';

/// Simple landing screen with a call to action.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(
                    Icons.layers_outlined,
                    size: 52,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Meme Maker',
                  style: text.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Stack layers — background, text, hyperlinks, images and '
                  'callout bubbles — drag them around, set opacity, and export '
                  'as a PNG or share to any app on your device. Everything '
                  'happens on-device.',
                  style:
                      text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EditorScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.brush_outlined),
                  label: const Text('Create a meme'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
