# memer

Client-only Flutter meme maker. **No backend, no secrets** (Phase 1).
Layer-based editor: a meme is a z-ordered list of `Layer`s — background,
text, hyperlinks, images and callout bubbles — composited inside a
`RepaintBoundary` and shared as PNG via the OS share sheet (`share_plus`).
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

A meme is `MemeConfig { CanvasAspect aspect, List<Layer> layers }`. Layer is
a sealed family with five variants:

| Layer            | What it stores                                                       |
| ---------------- | -------------------------------------------------------------------- |
| `BackgroundLayer` | solid colour (always pinned at index 0; non-deletable)              |
| `TextLayer`       | text, font, size, colour, bold, italic, align, optional outline     |
| `HyperlinkLayer`  | URL + display label + same text styling (underlined; copy-link UI)  |
| `ImageLayer`      | `bytes` + `originalBytes` (re-edit source — wiring lands in Phase 2)|
| `CalloutLayer`    | shape (`CalloutKind`), text, fill/border/text colours, tail target  |

- `models/layer.dart` — sealed `Layer` hierarchy + `CalloutKind` + clamps.
- `models/meme_config.dart` — `MemeConfig` + `CanvasAspect` enum.
- `models/meme_controller.dart` — layer add/remove/reorder/update + selection.
- `widgets/meme_canvas.dart` — iterates `config.layers`, positions each in
  fractional space, rotates/opacities them. Wrapped in `RepaintBoundary` and
  reused as the export source (preview == output).
- `widgets/layer_renderers/` — one renderer per layer kind.
- `widgets/selection_overlay.dart` — `LayerSelectionOverlay`: tap-to-select,
  drag-to-move, corner-resize, rotate handle, callout tail-target drag. Lives
  *outside* the `RepaintBoundary` so handles never appear in the exported PNG.
- `widgets/layers_panel.dart` — reorderable z-order list, add-layer menu,
  per-row visibility/lock/delete.
- `widgets/inspector_panel.dart` — sub-inspectors per layer kind.
- `services/image_export_service.dart` — `RepaintBoundary`→PNG; conditional
  import (`platform_saver_default.dart` / `platform_saver_web.dart`).
- `services/image_processing_service.dart` — pure-Dart crop, 90° rotate,
  flood-fill (magic wand) and bake-erasures into a transparent PNG. Built
  on the `image` package; runs on every platform.
- `services/social/` — `SocialPoster` interface; `ShareSheetPoster` (default,
  no backend); `DirectApiPoster` stub (real impls land in Phase 3).
- `screens/` — `editor_screen.dart` (3-pane: layers | canvas | inspector),
  `image_editor_screen.dart` (Phase-2 modal: crop / rotate / background-mask),
  `home_screen.dart` (landing).

## Conventions

- All layer geometry (`position`, `size`, `tailTarget`) is FRACTIONAL (0..1
  of the canvas) so it maps identically to the upscaled export at any size.
- Text `fontSize` is fractional too — it's multiplied by the canvas height.
- Z-order is `layers[0]` = bottom; the layers panel reverses for display
  (Photoshop-style top-of-list = top-of-stack).
- Background layer is structural: the controller refuses to delete it or
  reorder anything below it. `BackgroundLayer.copyWithBase` ignores
  geometric edits — it's always full-bleed.
- Use `Color.withValues(alpha: x)` (not the deprecated `withOpacity`) and
  `Color.toARGB32()` (not the deprecated `Color.value`). Flutter floor is
  3.27 — both APIs are available.
- Platform code stays behind conditional imports (`if (dart.library.html)`);
  never import `dart:io` or `dart:html` in shared code.
- Posters must NOT throw — return a `PostResult`.
- Prefer relative imports inside `lib/`; `package:memer/...` only in tests.

## Roadmap

- **Phase 1 (shipped).** Layer engine, all 5 layer kinds, canvas +
  interactive overlay, layers + inspector panels, OS share sheet posting,
  PNG save/export.
- **Phase 2 (shipped).** Image tools (`ImageEditorScreen`): crop with a
  draggable rect + 4 corner handles, 90° rotations (CW / CCW / 180°), and
  a manual background-removal painter (brush + magic-wand). Wand uses
  `ImageProcessingService.floodFill` (BFS, 4-connected, RGB tolerance);
  brush strokes accumulate as `Path`s in image-pixel coordinates and are
  baked into a transparent PNG via `applyErasures` (drawn with
  `BlendMode.dstOut` so the underlying image pixels become transparent).
  Free rotation at arbitrary angles continues to live on the canvas via
  the rotate handle — image-editor rotation is just the 90° quick path.
- **Phase 3.** BYO-credentials social posting — `flutter_secure_storage` for
  accounts/tokens, `flutter_web_auth_2` for OAuth, settings screen with a
  "paste your client ID" field per network. X gets a full implementation;
  Meta networks (IG, FB, Threads, LinkedIn) are scaffolded — they need a
  business-reviewed app, which the user must register themselves.

## Guardrails

- No backend, no embedded API keys/secrets (Phase 1 + 2). Phase 3 stores
  user-supplied OAuth tokens in `flutter_secure_storage` only.
- Keep it cross-platform: nothing that only builds on one target.
