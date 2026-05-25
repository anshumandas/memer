import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ai/ai_settings.dart';

/// Full-screen bottom sheet shown the first time the user taps an AI button
/// (and also reachable from the AI settings screen). The user MUST:
///   1. read the disclosure (what leaves the device, where it goes), and
///   2. either paste a Hugging Face Inference token or cancel.
///
/// The two-step structure exists so we never have a token saved without
/// recorded consent — both are written atomically via [AiSettings.setConsented]
/// and [AiSettings.writeToken] only after the user taps "Save and continue".
///
/// Returns true iff the user completed the flow.
class AiOnboardingSheet extends StatefulWidget {
  const AiOnboardingSheet({super.key, required this.settings});

  final AiSettings settings;

  static Future<bool> show(BuildContext context, AiSettings settings) async {
    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => AiOnboardingSheet(settings: settings),
    );
    return ok == true;
  }

  @override
  State<AiOnboardingSheet> createState() => _AiOnboardingSheetState();
}

class _AiOnboardingSheetState extends State<AiOnboardingSheet> {
  final TextEditingController _tokenCtl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final String? existing = await widget.settings.readToken();
    if (existing != null && mounted) {
      _tokenCtl.text = existing;
    }
  }

  @override
  void dispose() {
    _tokenCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String token = _tokenCtl.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Paste your Hugging Face token to continue.');
      return;
    }
    if (!token.startsWith('hf_')) {
      setState(
        () => _error =
            'Tokens start with "hf_". Double-check you copied the whole string.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await widget.settings.setConsented(true);
    await widget.settings.writeToken(token);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _openUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final ColorScheme scheme = theme.colorScheme;
    // Sit just above the soft keyboard when the user is typing the token.
    final EdgeInsets viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Icon(Icons.auto_awesome, color: scheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Turn on AI image tools',
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Background removal and object erase need a cloud model. '
                'Memer does NOT ship its own server — you connect your own '
                'free Hugging Face account.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 20),
              const _DisclosureCard(
                icon: Icons.cloud_upload_outlined,
                title: 'What leaves your device',
                body:
                    'When you tap an AI button, the image you are editing '
                    '(and, for object erase, the mask you painted) is sent '
                    'over HTTPS to Hugging Face. Nothing is uploaded until '
                    'you tap that button.',
              ),
              const SizedBox(height: 10),
              _DisclosureCard(
                icon: Icons.dns_outlined,
                title: 'Who processes it',
                body:
                    'Hugging Face, Inc. runs the model and returns the '
                    'result. They state inference inputs are not used to '
                    'train models, but review their privacy policy yourself '
                    'before sending anything sensitive.',
                trailing: TextButton(
                  onPressed: () => _openUrl('https://huggingface.co/privacy'),
                  child: const Text('Privacy policy'),
                ),
              ),
              const SizedBox(height: 10),
              const _DisclosureCard(
                icon: Icons.lock_outline,
                title: 'Where your token lives',
                body:
                    'Your token is stored only on this device, in the OS '
                    'secure store (Keychain on iOS/macOS, Keystore on '
                    'Android, DPAPI on Windows). You can clear it any time '
                    'from AI settings.',
              ),
              const SizedBox(height: 20),
              Text(
                'Get a free token',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              RichText(
                text: TextSpan(
                  style: text.bodyMedium?.copyWith(color: scheme.onSurface),
                  children: <InlineSpan>[
                    const TextSpan(text: '1. Create a free account at '),
                    _link(
                      scheme,
                      'huggingface.co/join',
                      'https://huggingface.co/join',
                    ),
                    const TextSpan(text: '.\n2. Open '),
                    _link(
                      scheme,
                      'Settings → Access Tokens',
                      'https://huggingface.co/settings/tokens',
                    ),
                    const TextSpan(text: '.\n3. Create a token with the '),
                    const TextSpan(
                      text: '"Make calls to inference providers"',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const TextSpan(text: ' permission.\n4. Paste it below.'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _tokenCtl,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'Hugging Face token',
                  hintText: 'hf_…',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show token' : 'Hide token',
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Save and continue'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InlineSpan _link(ColorScheme scheme, String label, String url) {
    return TextSpan(
      text: label,
      style: TextStyle(
        color: scheme.primary,
        decoration: TextDecoration.underline,
      ),
      recognizer: TapGestureRecognizer()..onTap = () => _openUrl(url),
    );
  }
}

class _DisclosureCard extends StatelessWidget {
  const _DisclosureCard({
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: scheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(body, style: text.bodySmall),
                if (trailing != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Align(alignment: Alignment.centerLeft, child: trailing!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
