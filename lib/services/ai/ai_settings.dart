import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// User-controlled settings for the optional GenAI image tools.
///
/// Stores a single Hugging Face Inference API token plus a per-device
/// "consent given" flag. Both live in [FlutterSecureStorage] — the OS
/// keystore on every native target; SubtleCrypto-backed IndexedDB on web.
/// Nothing leaves the device unless the user has both (a) consented and
/// (b) supplied a token.
///
/// The class is intentionally tiny and dependency-free so callers can
/// build it on demand; in tests, swap in a custom [FlutterSecureStorage]
/// via the [storage] constructor argument.
class AiSettings {
  AiSettings({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  static const String _kToken = 'memer.ai.hf_token';
  static const String _kConsent = 'memer.ai.consent_v1';
  static const String _kBgModel = 'memer.ai.bg_model';
  static const String _kInpaintModel = 'memer.ai.inpaint_model';

  /// Default models used by [HuggingFaceAiService]. Exposed here so the
  /// settings screen can show them and so the user can override per-model
  /// without code changes (some HF models become unavailable; users can
  /// pivot to a working one without us shipping a release).
  static const String defaultBgModel = 'briaai/RMBG-1.4';
  static const String defaultInpaintModel =
      'stabilityai/stable-diffusion-2-inpainting';

  Future<String?> readToken() => _safeRead(_kToken);

  Future<void> writeToken(String token) async {
    final String trimmed = token.trim();
    if (trimmed.isEmpty) {
      await _safeDelete(_kToken);
      return;
    }
    await _safeWrite(_kToken, trimmed);
  }

  Future<void> clearToken() => _safeDelete(_kToken);

  Future<bool> hasConsented() async => (await _safeRead(_kConsent)) == '1';

  Future<void> setConsented(bool consented) async {
    if (consented) {
      await _safeWrite(_kConsent, '1');
    } else {
      await _safeDelete(_kConsent);
    }
  }

  Future<String> bgModel() async =>
      (await _safeRead(_kBgModel)) ?? defaultBgModel;

  Future<void> setBgModel(String model) async {
    final String trimmed = model.trim();
    if (trimmed.isEmpty || trimmed == defaultBgModel) {
      await _safeDelete(_kBgModel);
      return;
    }
    await _safeWrite(_kBgModel, trimmed);
  }

  Future<String> inpaintModel() async =>
      (await _safeRead(_kInpaintModel)) ?? defaultInpaintModel;

  Future<void> setInpaintModel(String model) async {
    final String trimmed = model.trim();
    if (trimmed.isEmpty || trimmed == defaultInpaintModel) {
      await _safeDelete(_kInpaintModel);
      return;
    }
    await _safeWrite(_kInpaintModel, trimmed);
  }

  /// True iff the user has both consented AND configured a token.
  Future<bool> get isReady async {
    if (!await hasConsented()) return false;
    final String? t = await readToken();
    return t != null && t.isNotEmpty;
  }

  // The flutter_secure_storage plugin can throw PlatformExceptions when a
  // device's keystore is locked or unavailable (e.g. fresh-install Android
  // emulator, web in private mode). We treat any failure as "no value" so a
  // broken keystore degrades gracefully — the user can re-enter their token.
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e, st) {
      debugPrint('AiSettings.read($key) failed: $e\n$st');
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e, st) {
      debugPrint('AiSettings.write($key) failed: $e\n$st');
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e, st) {
      debugPrint('AiSettings.delete($key) failed: $e\n$st');
    }
  }
}
