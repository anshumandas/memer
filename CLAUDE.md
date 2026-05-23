# memer

Client-only Flutter meme maker. **No backend, no secrets.** Renders a meme
(background colour, top/bottom text, optional image, draggable speech-bubble
callouts) and shares the PNG via the OS share sheet (`share_plus`).
Targets Android, iOS, web, Windows, macOS, Linux.

## Commands

- Run: `flutter run` (`-d chrome` | `-d windows` | `-d macos` | `-d linux`)
- Test: `flutter test`
- Analyze: `flutter analyze`
- Format: `dart format .`
- First-time / new platforms: `flutter create .` then `flutter pub get`

## Architecture

State = one `MemeController` (`ChangeNotifier`) wrapping an immutable
`MemeConfig`. UI rebuilds via `ListenableBuilder`. No other state-mgmt dep.

- `models/` — `MemeConfig` (immutable snapshot), `Callout`, `MemeController`.
- `widgets/meme_canvas.dart` — the meme; wrapped in `RepaintBoundary` and reused
  as the export source, so preview == output (WYSIWYG).
- `services/image_export_service.dart` — `RepaintBoundary`→PNG; saving uses a
  conditional import (`platform_saver_default.dart` / `platform_saver_web.dart`).
- `services/social/` — `SocialPoster` interface; `ShareSheetPoster` (default,
  no backend); `DirectApiPoster` stub (API posting needs a backend).
- `screens/` — `editor_screen.dart` (editor), `home_screen.dart` (landing).

## Conventions

- Callout positions are FRACTIONAL (0..1 of the canvas) so they map identically
  to the upscaled export at any size.
- Use `withOpacity`, not `withValues` — SDK floor is 3.19.
- Platform code stays behind conditional imports (`if (dart.library.html)`);
  never import `dart:io` or `dart:html` in shared code.
- Posters must NOT throw — return a `PostResult`.
- Prefer relative imports inside `lib/`; `package:memer/...` only in tests.

## Guardrails

- Do not add a backend or embed API keys/secrets. Direct-API posting stays a
  documented stub unless a server is introduced (`direct_api_poster.dart`).
- Keep it cross-platform: nothing that only builds on one target.
