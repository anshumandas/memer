# memer

A **client-only** Flutter app for making memes by stacking layers and posting
them to your social networks. There is **no backend server** — the app
renders your meme on the device and hands the PNG to your operating system's
native share sheet, so you post through apps you're *already* logged into
(Instagram, X, WhatsApp, Facebook, Messages, email, …).

Project location: `C:/workspace/memer`.

## What you can do

- **Start from scratch** or **pick a template.** A built-in gallery ships
  with classic meme layouts (Drake, Distracted Boyfriend, Two Buttons,
  Expanding Brain, Change My Mind, Side-by-side, Speech Bubble, Wojak
  Yelling, Quote Card, Top/Bottom) and greetings cards (Birthday,
  Anniversary, Thank You, Congratulations, Get Well Soon, Season's
  Greetings, Wedding Invite). A wizard prompts you for each text caption
  and image slot with a live preview, then drops you into the full editor.
- Stack any combination of:
  - **Background colour** layer (always at the bottom).
  - **Text** layers (font, size, colour, bold, italics, optional outline).
  - **Hyperlink** layers (underlined text + "copy link" button — the URL
    is also appended to the share caption since PNGs can't carry live links).
  - **Image** layers — drag-resize / free-rotate live on the main canvas.
    A dedicated **image editor** modal (Edit image…) adds:
    - **Crop** with a draggable rect + 4 corner handles.
    - **90°** quick rotations (CW / CCW / 180°). Free rotation at arbitrary
      angles stays on the main canvas via the rotate handle.
    - **Manual background-removal painter** — brush + magic-wand flood-fill,
      baked into a transparent PNG.
    - **AI tab (optional, BYO key)** — one-shot background removal and
      prompt-free object inpainting via the Hugging Face Inference API.
      Token is stored on-device in `flutter_secure_storage`; nothing leaves
      the device until you've explicitly consented and pasted a token.
  - **Callout bubble** layers in six shapes (round-speech, sharp-speech,
    thought-cloud, rectangle, oval, scallop). Drag the small handle to
    re-aim the tail.
- Drag any layer around. Use corner handles to resize, the top handle to
  rotate, and the opacity slider in the inspector for transparency.
- Reorder z-order by dragging rows in the Layers panel. Toggle visibility
  and lock per layer.
- Pick a canvas aspect ratio (1:1, 4:5, 9:16, 16:9, 3:4).
- **Save image…** to export a PNG (or download it, on web).
- One-tap **share** to any installed app via the native share sheet.
- Runs on **Android, iOS, web, Windows, macOS and Linux** from one codebase.

## AI image tools (opt-in)

The image editor has an **AI tab** powered by your own Hugging Face
Inference API token:

- **Remove background** — sends the layer image to a segmentation model
  (default `briaai/RMBG-1.4`) and returns a transparent-background PNG.
- **Erase object** — paint over what you want gone; the masked region is
  sent to an inpainting model (default `stabilityai/stable-diffusion-2-inpainting`)
  along with a "background, no object" prompt, and the model fills it in.

The first time you tap an AI button, an onboarding sheet explains exactly
what bytes leave the device, what the API does with them, and asks for
explicit consent before you paste a token. Both the consent flag and the
token live in [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage)
(Keychain on iOS/macOS, Keystore on Android, DPAPI on Windows, libsecret on
Linux, SubtleCrypto-backed IndexedDB on web). You can change the model
names or disconnect at any time from the AI settings screen.

## Roadmap

- **Phase 2 (shipped).** Image editor with crop, 90° rotate, and a manual
  remove-background painter (brush + magic-wand). Original bytes are
  preserved so the editor's "Reset to original" can restore the untouched
  source on demand.
- **Templates (shipped).** Bundled `assets/templates/*.json` — classic
  meme layouts + greetings cards. The gallery uses tiny live renders as
  thumbnails so what you see is exactly what you start from.
- **AI mode (shipped, opt-in).** BYO Hugging Face token enables one-shot
  background removal and object inpainting from inside the image editor.
- **Phase 3 — multi-account posting.** Connect X, Instagram, Facebook,
  Threads and LinkedIn accounts. OAuth tokens live in
  `flutter_secure_storage` on-device. CLAUDE.md forbids embedding secrets,
  so you bring your own developer credentials per network — paste a client
  ID once in Settings and you're connected. Share screen then lets you tick
  multiple accounts and post in parallel.

## Why no direct "post to API" buttons today?

This uses a **hybrid** approach:

- **Default path — share sheet (no backend).** The only way to post to the
  big networks *without* a server. Their APIs require OAuth flows whose
  token exchange uses a **client secret**, which can't be safely embedded
  in a client-only app, plus registered redirect URIs and app review.
- **Extension point — direct API posting.** `lib/services/social/` defines
  a `SocialPoster` interface. `ShareSheetPoster` is the working
  implementation; `DirectApiPoster` (with `XApiPoster` / `InstagramApiPoster`
  stubs) is where Phase 3 will plug in real posters. Because they satisfy
  the same interface, the UI doesn't change.

## Getting started

This package ships the application code (`lib/`, `test/`, `pubspec.yaml`,
`assets/templates/`) plus the Claude Code harness (`CLAUDE.md`, `.claude/`).
The machine-generated platform folders (`android/`, `ios/`, `web/`, etc.)
are not included — generate them in one command:

```bash
cd C:/workspace/memer

# 1. Generate the platform runner folders for every target you want.
flutter create .

# 2. Fetch dependencies.
flutter pub get

# 3. Run it.
flutter run                 # on a connected device/emulator
flutter run -d chrome       # in the browser
flutter run -d windows      # or macos / linux
```

> `flutter create .` only adds the missing platform folders — it will **not**
> overwrite `lib/`, `pubspec.yaml`, your tests, `CLAUDE.md`, or `.claude/`.

### Run the tests

```bash
flutter test
```

## Project structure

```
memer/
  CLAUDE.md                       project memory for Claude Code
  .claude/
    settings.json                 permissions + format-on-edit hook
    commands/                     /test, /analyze, /review slash commands
  pubspec.yaml
  analysis_options.yaml
  assets/
    templates/                    bundled meme + greetings templates (JSON)
  lib/
    main.dart                     app entry point
    app.dart                      MaterialApp + theming
    theme/app_theme.dart          Material 3 theme
    models/
      layer.dart                  sealed Layer family + CalloutKind + clamps
      meme_config.dart            immutable snapshot { aspect, layers }
      meme_controller.dart        layer ops, selection, ChangeNotifier
      meme_template.dart          JSON-backed templates + LayerTemplate slots
    widgets/
      meme_canvas.dart            composites every layer (also the export source)
      selection_overlay.dart      tap/drag/resize/rotate/tail handles
      layers_panel.dart           reorderable z-order list + add-layer menu
      inspector_panel.dart        per-layer-kind sub-inspectors
      ai_onboarding_sheet.dart    AI consent + token-entry bottom sheet
      layer_renderers/
        background_renderer.dart
        text_renderer.dart
        hyperlink_renderer.dart
        image_renderer.dart
        callout_renderer.dart    bubble + dynamic tail painter
    screens/
      home_screen.dart            landing (Create / Templates / AI settings)
      editor_screen.dart          3-pane editor (layers | canvas | inspector)
      template_gallery_screen.dart grid of bundled templates with live previews
      template_wizard_screen.dart  fill slot text/images, then open in editor
      image_editor_screen.dart    modal: crop / rotate / manual mask / AI tab
      ai_settings_screen.dart     token + consent + model overrides
    services/
      image_export_service.dart   RepaintBoundary → PNG, + save
      image_processing_service.dart cross-platform crop / rotate / flood-fill
      image_processor_default.dart native impl (ui.Canvas + engine PNG)
      image_processor_web.dart      web impl (HTMLCanvasElement.toBlob)
      media_picker_service.dart   pick an image (all platforms)
      template_service.dart       loads bundled templates + placeholder PNG
      platform_saver_default.dart native "save as" dialog
      platform_saver_web.dart     web download (conditional import)
      ai/
        ai_settings.dart          token + consent in flutter_secure_storage
        huggingface_ai_service.dart HF Inference client (bg-removal, inpaint)
      social/
        social_poster.dart        SocialPoster interface + PostResult
        share_sheet_poster.dart   native share sheet (the default)
        direct_api_poster.dart    documented stub for API posting (Phase 3)
  test/
    meme_controller_test.dart     unit tests for the layer model + controller
    image_processing_service_test.dart tests for crop / rotate / flood-fill
    widget_test.dart              smoke test
```

## Working on memer with Claude Code

The repo is set up for [Claude Code](https://docs.claude.com/en/docs/claude-code):

- **`CLAUDE.md`** — a short, high-signal brief (stack, commands, architecture,
  conventions, guardrails) loaded automatically as context.
- **`.claude/settings.json`** — pre-approves `flutter`/`dart`/`git` commands so
  you aren't prompted for each one, denies reads of secrets/keystores, and runs
  `dart format` after every edit (assumes a bash-compatible shell; on Windows
  use Git Bash).
- **Slash commands** (`.claude/commands/`):
  - `/test` — run the test suite and summarize failures.
  - `/analyze` — `flutter analyze` + formatting check.
  - `/review [focus]` — review uncommitted changes against project conventions.

## How the export works

The on-screen preview lives inside a `RepaintBoundary`. When you share or
save, the app calls `RenderRepaintBoundary.toImage()` and encodes the result
as PNG — upscaled to ~1080px wide regardless of screen size, so the output
is crisp and identical to what you see. Because the *same* widget tree is
used for preview and export — and the selection handles are deliberately
*outside* the boundary — it's truly WYSIWYG.

The image editor's crop / rotate / encode pipeline is platform-split
(`image_processor_default.dart` / `image_processor_web.dart`): native
targets use `ui.Canvas` and the engine's PNG encoder (which runs on engine
threads); web routes through `HTMLCanvasElement.toBlob`, because
CanvasKit's `toByteData(format: png)` actually runs synchronously on the JS
main thread and would freeze the browser for any sizable image.

## Dependencies

| Package                 | Why                                                          |
| ----------------------- | ------------------------------------------------------------ |
| `share_plus`            | Native OS share sheet (post with your own logins).           |
| `file_selector`         | Cross-platform image picking and "save as" dialog.           |
| `flutter_colorpicker`   | Pure-Dart colour picker that works on every platform.        |
| `url_launcher`          | Open URLs from the inspector preview.                        |
| `image`                 | Pure-Dart crop / rotate / flood-fill helpers.                |
| `web`                   | Browser DOM APIs for the web PNG-encode path and saver.      |
| `http`                  | HTTP client for the optional Hugging Face Inference API.     |
| `flutter_secure_storage`| Stores the user-supplied HF token (and Phase-3 OAuth tokens).|

## Platform notes

- **Web:** sharing uses the browser Web Share API where available; "Save"
  triggers a normal download. Image export uses the CanvasKit renderer.
  Image-editor PNG encoding goes through `HTMLCanvasElement.toBlob` (a
  browser worker) so multi-megapixel encodes don't freeze the tab.
- **Windows / Linux:** native file *sharing* support is limited; if the
  share sheet is unavailable the app tells you to use **Save image…**
  instead.
- **iOS/macOS:** you may need to add a usage description and enable the
  relevant entitlements for file access — `flutter create .` sets up
  sensible defaults.
