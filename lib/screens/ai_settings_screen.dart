import 'package:flutter/material.dart';

import '../services/ai/ai_settings.dart';
import '../widgets/ai_onboarding_sheet.dart';

/// Manage the optional GenAI feature: connection status, token, and the
/// two model names (background-removal + inpainting).
///
/// Reachable from the home screen's gear icon. Editing the token re-runs
/// the onboarding sheet so the user always re-sees the disclosure when
/// connecting; the model overrides are a power-user affordance for when
/// the defaults are down or the user wants a stronger model.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final AiSettings _settings = AiSettings();

  bool _loading = true;
  bool _hasToken = false;
  bool _consented = false;
  String _bgModel = AiSettings.defaultBgModel;
  String _inpaintModel = AiSettings.defaultInpaintModel;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final String? token = await _settings.readToken();
    final bool consent = await _settings.hasConsented();
    final String bg = await _settings.bgModel();
    final String inp = await _settings.inpaintModel();
    if (!mounted) return;
    setState(() {
      _hasToken = token != null && token.isNotEmpty;
      _consented = consent;
      _bgModel = bg;
      _inpaintModel = inp;
      _loading = false;
    });
  }

  Future<void> _connect() async {
    final bool ok = await AiOnboardingSheet.show(context, _settings);
    if (ok) await _refresh();
  }

  Future<void> _disconnect() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Disconnect AI?'),
        content: const Text(
          'This deletes your Hugging Face token from this device. You can '
          'reconnect any time.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _settings.clearToken();
      await _settings.setConsented(false);
      await _refresh();
    }
  }

  Future<void> _editModel({
    required String title,
    required String current,
    required String defaultValue,
    required Future<void> Function(String) onSave,
  }) async {
    final TextEditingController ctl = TextEditingController(text: current);
    final String? next = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: ctl,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Hugging Face model id',
                hintText: 'owner/model-name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Default: $defaultValue',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(defaultValue),
            child: const Text('Reset to default'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (next != null) {
      await onSave(next);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI image tools')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: <Widget>[
                _StatusCard(
                  connected: _hasToken && _consented,
                  onConnect: _connect,
                  onDisconnect: _disconnect,
                ),
                const SizedBox(height: 8),
                const ListTile(
                  leading: Icon(Icons.privacy_tip_outlined),
                  title: Text('What happens to my images?'),
                  subtitle: Text(
                    'When you tap an AI button, the image (and mask, for '
                    'object erase) is sent to Hugging Face over HTTPS. '
                    'Nothing is uploaded automatically.',
                  ),
                  isThreeLine: true,
                ),
                const Divider(height: 24),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Models',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Background removal model'),
                  subtitle: Text(_bgModel),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editModel(
                    title: 'Background removal model',
                    current: _bgModel,
                    defaultValue: AiSettings.defaultBgModel,
                    onSave: _settings.setBgModel,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_fix_high_outlined),
                  title: const Text('Object erase (inpainting) model'),
                  subtitle: Text(_inpaintModel),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editModel(
                    title: 'Object erase model',
                    current: _inpaintModel,
                    defaultValue: AiSettings.defaultInpaintModel,
                    onSave: _settings.setInpaintModel,
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.connected,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: connected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(
              connected ? Icons.check_circle : Icons.cloud_off,
              color: connected ? scheme.onPrimaryContainer : scheme.outline,
              size: 32,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    connected
                        ? 'Connected to Hugging Face'
                        : 'AI tools are off',
                    style: text.titleMedium?.copyWith(
                      color: connected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    connected
                        ? 'Background remove and object erase are ready to '
                              'use in the image editor.'
                        : 'Connect your free Hugging Face account to unlock '
                              'background remove and object erase.',
                    style: text.bodySmall?.copyWith(
                      color: connected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: connected
                        ? OutlinedButton.icon(
                            onPressed: onDisconnect,
                            icon: const Icon(Icons.link_off),
                            label: const Text('Disconnect'),
                          )
                        : FilledButton.icon(
                            onPressed: onConnect,
                            icon: const Icon(Icons.link),
                            label: const Text('Connect'),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
