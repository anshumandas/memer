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
          constraints: const BoxConstraints(maxWidth: 480),
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
                    Icons.add_reaction_outlined,
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
                  'Pick a background colour, drop in text and speech bubbles, '
                  'add a photo if you like — then share it to any app on your '
                  'device. Everything happens on-device; no account, no server.',
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
