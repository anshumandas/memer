# memer

Client-only Flutter meme maker. **No backend, no embedded secrets.**
A meme is a z-ordered list of `Layer`s composited in a `RepaintBoundary`
and exported/shared as PNG. Targets Android, iOS, web, Windows, macOS, Linux.

## Commands

- Run: `flutter run` (`-d chrome` | `-d windows` | `-d macos` | `-d linux`)
- Test: `flutter test`  /  Analyze: `flutter analyze`  /  Format: `dart format .`
- First-time / new platforms: `flutter create .` then `flutter pub get`

## Architecture

State = one `MemeController` (`ChangeNotifier`) wrapping immutable
`MemeConfig { CanvasAspect, List<Layer> }`. UI rebuilds via `ListenableBuilder`.
No other state-mgmt dep.

`Layer` is sealed — 5 variants:

| Layer             | Stores                                                              |
| ----------------- | ------------------------------------------------------------------- |
| `BackgroundLayer` | solid colour; pinned at index 0; non-deletable                      |
| `TextLayer`       | text, font, size, colour, bold/italic, align, optional outline      |
| `HyperlinkLayer`  | URL + label + text styling (URL appended to share caption)          |
| `ImageLayer`      | `bytes` + `originalBytes` (re-edit source)                          |
| `CalloutLayer`    | `CalloutKind` shape, text, fill/border/text colours, tail target    |

### Key files

- `models/layer.dart`, `meme_config.dart`, `meme_controller.dart` — model + state.
- `models/meme_template.dart` — JSON-backed `MemeTemplate` + `LayerTemplate`
  family. Templates declare text/image **slots** the wizard fills in (no
  embedded binary image data).
- `widgets/meme_canvas.dart` — composites layers; wrapped in `RepaintBoundary`,
  reused as the export source (preview == output).
- `widgets/selection_overlay.dart` — drag/resize/rotate/tail-target handles,
  rendered **outside** the boundary so they're never in the PNG.
- `widgets/layers_panel.dart`, `widgets/inspector_panel.dart` — z-order list +
  per-layer sub-inspectors.
- `widgets/layer_renderers/` — one renderer per layer kind.
- `screens/home_screen.dart` — landing (Create / Templates / AI settings).
- `screens/editor_screen.dart` — 3-pane editor.
- `screens/template_gallery_screen.dart` + `template_wizard_screen.dart` —
  pick a template, fill slots with a live preview, hand off to editor.
- `screens/image_editor_screen.dart` — modal: crop, 90° rotate, manual
  background-removal painter (brush + magic-wand) + an **AI tab**
  (BYO Hugging Face token: bg-removal + inpainting object-erase).
- `screens/ai_settings_screen.dart` + `widgets/ai_onboarding_sheet.dart` —
  consent + token entry; model overrides.
- `services/image_export_service.dart` — `RepaintBoundary` → PNG.
- `services/image_processing_service.dart` — crop / rotate / flood-fill /
  bake erasures. **Platform-split** via conditional import: the default
  impl drives `ui.Canvas` + the engine PNG encoder; the web sibling uses
  `HTMLCanvasElement.toBlob` because CanvasKit's `toByteData(png)` is
  sync-on-main despite returning a Future.
- `services/template_service.dart` — loads `assets/templates/*.json`,
  builds the checkered placeholder PNG for empty image slots.
- `services/ai/ai_settings.dart` — token + consent in `flutter_secure_storage`.
- `services/ai/huggingface_ai_service.dart` — HF Inference client (default
  `briaai/RMBG-1.4` + `stabilityai/stable-diffusion-2-inpainting`); 503
  cold-start retry; typed `AiException`.
- `services/social/` — `SocialPoster` interface; `ShareSheetPoster` (default).
  `DirectApiPoster` is a Phase-3 stub.
- `services/platform_saver_{default,web}.dart` — conditional-import save.

## Conventions

- All layer geometry (`position`, `size`, `tailTarget`) is **fractional**
  (0..1 of canvas). Text `fontSize` is fractional too. Maps identically to
  any export size.
- Z-order: `layers[0]` = bottom. Layers panel reverses for display
  (Photoshop-style top-of-list = top-of-stack).
- Background layer is structural: controller refuses to delete it or
  reorder anything below it; `BackgroundLayer.copyWithBase` ignores
  geometric edits (always full-bleed).
- Templates never embed binary image data — they declare slots the user
  fills at instantiation. Keeps JSON small, copyright-clean, diffable.
- Use `Color.withValues(alpha: x)` (not `withOpacity`) and
  `Color.toARGB32()` (not `Color.value`). Flutter floor is 3.27.
- Platform code behind conditional imports (`if (dart.library.html)`);
  never import `dart:io` or `dart:html` in shared code.
- Posters must NOT throw — return a `PostResult`.
- Prefer relative imports inside `lib/`; `package:memer/...` only in tests.

## Guardrails

- No backend. No embedded API keys/secrets, ever.
- AI feature is **BYO Hugging Face token** — stored in
  `flutter_secure_storage`, gated on explicit consent. Nothing leaves the
  device unless both are set. Phase-3 social posting follows the same
  BYO-credentials pattern.
- Keep it cross-platform: nothing that only builds on one target.

## Roadmap

- **Phase 1 (shipped).** Layer engine, 5 layer kinds, canvas + overlay,
  layers + inspector panels, share sheet, PNG export.
- **Phase 2 (shipped).** Image editor: crop, 90° rotate, manual
  background-removal painter (brush + magic-wand flood fill).
- **Templates (shipped).** Bundled `assets/templates/*.json` — classic meme
  layouts + greetings cards; gallery + wizard hand off to editor.
- **AI mode (shipped, opt-in).** BYO HF token; image-editor AI tab adds
  one-shot background removal and prompt-free object inpainting.
- **Phase 3.** BYO-credentials social posting — `flutter_web_auth_2` OAuth,
  per-network "paste your client ID" settings, parallel share-screen
  posting. X first; Meta networks (IG / FB / Threads / LinkedIn) scaffolded.
