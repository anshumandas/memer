import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Distinguishes between user-recoverable errors (bad token, rate limit,
/// model offline) and unexpected ones. The image editor maps these onto
/// snack-bar copy the user can act on.
enum AiErrorKind {
  noToken,
  unauthorized,
  rateLimited,
  modelUnavailable,
  network,
  badInput,
  unknown,
}

class AiException implements Exception {
  AiException(this.kind, this.message);
  final AiErrorKind kind;
  final String message;
  @override
  String toString() => 'AiException($kind): $message';
}

/// Thin wrapper over the Hugging Face Inference API for the two operations
/// the image editor exposes.
///
/// **Background removal** ([removeBackground]) — POSTs the raw image bytes
/// to the configured segmentation model (default `briaai/RMBG-1.4`). The
/// model returns either:
///  * a PNG with a transparent background (RMBG-style models), which we
///    return as-is, OR
///  * a JSON array of `{label, mask}` segments. In that case we treat the
///    largest non-background mask as the foreground alpha and composite
///    that against the source image.
///
/// **Object erase** ([eraseObject]) — POSTs JSON with base64 image + mask
/// + a "background, no object" prompt to the configured inpainting model
/// (default `stabilityai/stable-diffusion-2-inpainting`). The model fills
/// the masked region; result quality depends on the model the user picks.
///
/// Both methods:
/// * retry once on HTTP 503 (model loading), waiting up to the server's
///   reported `estimated_time` (capped at 30s);
/// * translate transport errors into [AiException]s so the caller can show
///   actionable copy.
class HuggingFaceAiService {
  HuggingFaceAiService({
    required this.token,
    this.bgModel = 'briaai/RMBG-1.4',
    this.inpaintModel = 'stabilityai/stable-diffusion-2-inpainting',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String token;
  final String bgModel;
  final String inpaintModel;
  final http.Client _client;

  static const String _base = 'https://api-inference.huggingface.co/models/';
  static const Duration _maxColdStart = Duration(seconds: 30);

  void dispose() => _client.close();

  /// Strip the background from [imageBytes]. Returns a PNG.
  Future<Uint8List> removeBackground(Uint8List imageBytes) async {
    if (token.isEmpty) {
      throw AiException(AiErrorKind.noToken, 'No Hugging Face token set.');
    }
    final Uri url = Uri.parse('$_base$bgModel');
    final http.Response res = await _postWithColdRetry(
      url,
      headers: <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/octet-stream',
        'Accept': 'image/png',
      },
      body: imageBytes,
    );
    final String contentType = res.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.startsWith('image/')) {
      return res.bodyBytes;
    }
    // Some segmentation models return a JSON array of masks. We pick the
    // largest non-"background" segment, treat its mask as the foreground
    // alpha, and composite that against the source image.
    if (contentType.contains('json')) {
      return _compositeForegroundFromJson(res.bodyBytes, imageBytes);
    }
    throw AiException(
      AiErrorKind.unknown,
      'Unexpected response from $bgModel '
      '(${res.statusCode}, $contentType).',
    );
  }

  /// Erase pixels under [maskBytes] from [imageBytes] using the configured
  /// inpainting model. Both [imageBytes] and [maskBytes] must be PNGs of
  /// identical dimensions; the mask should be white where the object lives
  /// and black elsewhere (Stable Diffusion inpainting convention).
  Future<Uint8List> eraseObject(
    Uint8List imageBytes,
    Uint8List maskBytes, {
    String prompt = 'background, clean, seamless, no object',
    String negativePrompt = 'object, person, text, watermark',
    int steps = 25,
    double guidance = 7.5,
  }) async {
    if (token.isEmpty) {
      throw AiException(AiErrorKind.noToken, 'No Hugging Face token set.');
    }
    final Uri url = Uri.parse('$_base$inpaintModel');
    final Map<String, dynamic> body = <String, dynamic>{
      'inputs': prompt,
      'parameters': <String, dynamic>{
        'image': base64Encode(imageBytes),
        'mask_image': base64Encode(maskBytes),
        'negative_prompt': negativePrompt,
        'num_inference_steps': steps,
        'guidance_scale': guidance,
      },
    };
    final http.Response res = await _postWithColdRetry(
      url,
      headers: <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'image/png',
      },
      body: utf8.encode(jsonEncode(body)),
    );
    final String contentType = res.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.startsWith('image/')) {
      return res.bodyBytes;
    }
    throw AiException(
      AiErrorKind.unknown,
      'Unexpected response from $inpaintModel '
      '(${res.statusCode}, $contentType).',
    );
  }

  /// Sends [body] and, if the server replies "model is loading" (503 with
  /// an `estimated_time` in the JSON), waits and retries exactly once.
  /// Translates the final outcome into either a successful [http.Response]
  /// or an [AiException].
  Future<http.Response> _postWithColdRetry(
    Uri url, {
    required Map<String, String> headers,
    required List<int> body,
  }) async {
    http.Response res;
    try {
      res = await _client.post(url, headers: headers, body: body);
    } catch (e) {
      throw AiException(AiErrorKind.network, 'Network error: $e');
    }
    if (res.statusCode == 503) {
      final Duration wait = _parseColdStart(res.body);
      debugPrint('HF model warming up, retrying in ${wait.inSeconds}s');
      await Future<void>.delayed(wait);
      try {
        res = await _client.post(url, headers: headers, body: body);
      } catch (e) {
        throw AiException(AiErrorKind.network, 'Network error: $e');
      }
    }
    if (res.statusCode == 200) return res;
    throw _toException(res);
  }

  Duration _parseColdStart(String body) {
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final dynamic eta = decoded['estimated_time'];
        if (eta is num) {
          final int s = eta.ceil().clamp(1, _maxColdStart.inSeconds);
          return Duration(seconds: s);
        }
      }
    } catch (_) {}
    return const Duration(seconds: 8);
  }

  AiException _toException(http.Response res) {
    String message = 'HTTP ${res.statusCode}';
    try {
      final dynamic decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] is String) {
        message = '${decoded['error']}';
      }
    } catch (_) {
      if (res.body.isNotEmpty && res.body.length < 200) {
        message = res.body;
      }
    }
    switch (res.statusCode) {
      case 400:
      case 422:
        return AiException(AiErrorKind.badInput, message);
      case 401:
      case 403:
        return AiException(
          AiErrorKind.unauthorized,
          'Hugging Face rejected the token. Check that it has '
          '"Inference" permission. ($message)',
        );
      case 429:
        return AiException(
          AiErrorKind.rateLimited,
          'Free-tier rate limit hit. Wait a minute and try again, or '
          'upgrade your Hugging Face account. ($message)',
        );
      case 503:
        return AiException(
          AiErrorKind.modelUnavailable,
          'Model is still loading. Try again in a moment. ($message)',
        );
      default:
        return AiException(AiErrorKind.unknown, message);
    }
  }

  /// Some segmentation models return a JSON list of `{label, mask}` items,
  /// where `mask` is a base64-encoded PNG. We pick the largest non-background
  /// segment and composite the original image against it as alpha — yielding
  /// a transparent-background PNG equivalent to what RMBG returns directly.
  Future<Uint8List> _compositeForegroundFromJson(
    List<int> jsonBytes,
    Uint8List sourceBytes,
  ) async {
    final dynamic decoded = jsonDecode(utf8.decode(jsonBytes));
    if (decoded is! List || decoded.isEmpty) {
      throw AiException(
        AiErrorKind.unknown,
        'Segmentation model returned no segments.',
      );
    }
    Map<String, dynamic>? best;
    int bestSize = -1;
    for (final dynamic item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final String label = (item['label'] as String? ?? '').toLowerCase();
      if (label == 'background' || label == 'bg') continue;
      final String? maskB64 = item['mask'] as String?;
      if (maskB64 == null) continue;
      // Encoded-size as a cheap proxy for "largest segment".
      if (maskB64.length > bestSize) {
        bestSize = maskB64.length;
        best = item;
      }
    }
    if (best == null) {
      throw AiException(
        AiErrorKind.unknown,
        'Segmentation model returned only the background.',
      );
    }
    final Uint8List maskBytes = base64Decode(best['mask'] as String);
    return _compositeAlpha(sourceBytes, maskBytes);
  }

  /// Composites [sourceBytes] (RGB image) against [maskBytes] (single-channel
  /// PNG, white = foreground) and returns a transparent-background PNG.
  Uint8List _compositeAlpha(Uint8List sourceBytes, Uint8List maskBytes) {
    final img.Image? source = img.decodeImage(sourceBytes);
    final img.Image? rawMask = img.decodeImage(maskBytes);
    if (source == null || rawMask == null) {
      throw AiException(AiErrorKind.unknown, 'Could not decode mask result.');
    }
    final img.Image mask =
        (rawMask.width == source.width && rawMask.height == source.height)
        ? rawMask
        : img.copyResize(rawMask, width: source.width, height: source.height);
    for (int y = 0; y < source.height; y++) {
      for (int x = 0; x < source.width; x++) {
        final img.Pixel mp = mask.getPixel(x, y);
        final img.Pixel sp = source.getPixel(x, y);
        sp.a = mp.r;
      }
    }
    return Uint8List.fromList(img.encodePng(source));
  }
}
