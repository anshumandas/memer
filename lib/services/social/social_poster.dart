import 'dart:typed_data';

/// What happened when we tried to post a meme.
enum PostOutcome { shared, savedToDisk, cancelled, failed }

/// Result of a post attempt, surfaced to the UI as a snackbar.
class PostResult {
  const PostResult(this.outcome, {this.message, this.savedPath});

  final PostOutcome outcome;
  final String? message;
  final String? savedPath;

  bool get isSuccess =>
      outcome == PostOutcome.shared || outcome == PostOutcome.savedToDisk;
}

/// A destination a meme can be posted to.
///
/// This abstraction is the extension point for the "hybrid" approach: the
/// app ships with [ShareSheetPoster] (no backend, uses the user's own apps),
/// and you can later add API-based posters (see `direct_api_poster.dart`)
/// without changing any UI code.
abstract class SocialPoster {
  /// Stable identifier, handy for analytics or persistence.
  String get id;

  /// Human-readable label shown on the button / menu item.
  String get label;

  /// Push [imageBytes] (a PNG) out to the destination, optionally with a
  /// [caption]. Implementations must never throw — they report problems via
  /// the returned [PostResult].
  Future<PostResult> post({
    required Uint8List imageBytes,
    required String caption,
  });
}
