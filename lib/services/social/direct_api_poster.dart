import 'package:flutter/foundation.dart';

import 'social_poster.dart';

/// EXTENSION POINT — direct, programmatic posting to a specific network's API.
///
/// This is intentionally a *stub*. Read this before wiring anything up:
///
/// Almost every major network (Instagram/Threads, X, Facebook, TikTok,
/// LinkedIn, Reddit) requires an OAuth 2.0 flow whose token exchange uses a
/// **client secret**. A secret cannot be safely embedded in a client-only app
/// — anyone can decompile the binary or read the JS bundle and steal it. The
/// providers also require a registered redirect URI and, usually, app review.
///
/// In other words: true "post directly via API" needs a small backend (even
/// just a serverless function) to (a) hold the client secret and (b) complete
/// the OAuth token exchange. That contradicts the no-backend goal, which is
/// exactly why [ShareSheetPoster] is the default.
///
/// If you DO add a backend later, implement [DirectApiPoster] per network:
///   1. Run the OAuth flow (e.g. with `flutter_web_auth_2`) to get an access
///      token; have your backend perform the secret-bearing token exchange.
///   2. Securely cache the token (e.g. `flutter_secure_storage`).
///   3. Upload [imageBytes] to the network's media endpoint, then create the
///      post, using the token in the Authorization header.
///   4. Return an appropriate [PostResult].
///
/// Because this class also satisfies [SocialPoster], you can drop a working
/// implementation into the editor's poster list with zero UI changes.
abstract class DirectApiPoster implements SocialPoster {
  const DirectApiPoster();

  /// Where a developer can register an app for this network.
  String get developerPortalUrl;

  @override
  Future<PostResult> post({
    required Uint8List imageBytes,
    required String caption,
  }) async {
    debugPrint(
      '[$id] Direct API posting is not implemented in this client-only app. '
      'It requires OAuth + a client secret, which needs a backend. '
      'Register an app at $developerPortalUrl and implement post() here, '
      'or use the share sheet instead.',
    );
    return PostResult(
      PostOutcome.failed,
      message:
          'Direct posting to $label needs a backend (OAuth). '
          'Use "Share to apps…" for now.',
    );
  }
}

/// Example concrete stub. Copy this shape for each network you support once a
/// backend is available.
class XApiPoster extends DirectApiPoster {
  const XApiPoster();

  @override
  String get id => 'x_api';

  @override
  String get label => 'X (Twitter)';

  @override
  String get developerPortalUrl => 'https://developer.x.com';
}

class InstagramApiPoster extends DirectApiPoster {
  const InstagramApiPoster();

  @override
  String get id => 'instagram_api';

  @override
  String get label => 'Instagram';

  @override
  String get developerPortalUrl => 'https://developers.facebook.com';
}
