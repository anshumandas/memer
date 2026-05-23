import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'social_poster.dart';

/// The default, backend-free poster.
///
/// It hands the rendered PNG to the operating system's native share sheet.
/// The user then chooses Instagram, X, Facebook, WhatsApp, Messages, email —
/// whatever they have installed — and posts using accounts they are *already*
/// logged into. No OAuth, no API keys, no server.
///
/// Platform notes:
///  * Android / iOS: full native share sheet.
///  * Web: uses the browser Web Share API (level 2) where available.
///  * macOS: native sharing service.
///  * Windows / Linux: share support is limited; callers should offer
///    "Save image…" as a fallback (see [PostOutcome.failed] handling).
class ShareSheetPoster implements SocialPoster {
  const ShareSheetPoster();

  @override
  String get id => 'share_sheet';

  @override
  String get label => 'Share to apps…';

  @override
  Future<PostResult> post({
    required Uint8List imageBytes,
    required String caption,
  }) async {
    try {
      final XFile file = XFile.fromData(
        imageBytes,
        mimeType: 'image/png',
        name: 'meme.png',
      );

      final ShareResult result = await Share.shareXFiles(
        <XFile>[file],
        text: caption.trim().isEmpty ? null : caption,
      );

      switch (result.status) {
        case ShareResultStatus.success:
          return const PostResult(PostOutcome.shared, message: 'Shared!');
        case ShareResultStatus.dismissed:
          return const PostResult(
            PostOutcome.cancelled,
            message: 'Sharing cancelled.',
          );
        case ShareResultStatus.unavailable:
          return const PostResult(
            PostOutcome.failed,
            message: 'The share sheet is not available on this platform. '
                'Try "Save image…" instead.',
          );
      }
    } catch (e) {
      return PostResult(
        PostOutcome.failed,
        message: 'Could not open the share sheet ($e). '
            'Try "Save image…" instead.',
      );
    }
  }
}
