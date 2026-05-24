# memer

A **client-only** Flutter app for making memes by stacking layers and posting
them to your social networks. There is **no backend server** today — the app
renders your meme on the device and hands the PNG to your operating system's
native share sheet, so you post through apps you're *already* logged into
(Instagram, X, WhatsApp, Facebook, Messages, email, …).

Project location: `C:/workspace/memer`.

## What you can do

- Start from a solid **background colour** layer.
- Stack any combination of:
  - **Text** layers (font, size, colour, bold, italics, optional outline).
  - **Hyperlink** layers (underlined text + a "copy link" button — the URL
    is also appended to the share caption since PNGs can't carry live links).
  - **Image** layers — drag-resize / free-rotate live on the main canvas;
    a dedicated **image editor** modal (Edit image…) adds crop, 90°
    quick-rotate, and a manual **remove-background painter** with a brush
    and a magic-wand flood-fill tool.
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

## Roadmap

- **Phase 2 (shipped).** Image editor with crop, 90° rotate, and a manual
  remove-background painter (brush + magic-wand). The original bytes are
  preserved so the editor's "Reset to original" can restore the untouched
  source on demand.
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

This package ships the application code (`lib/`, `test/`, `pubspec.yaml`)
plus the Claude Code harness (`CLAUDE.md`, `.claude/`). The machine-generated
platform folders (`android/`, `ios/`, `web/`, etc.) are not included —
generate them in one command:

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
  lib/
    main.dart                     app entry point
    app.dart                      MaterialApp + theming
    theme/app_theme.dart          Material 3 theme
    models/
      layer.dart                  sealed Layer family + CalloutKind + clamps
      meme_config.dart            immutable snapshot { aspect, layers }
      meme_controller.dart        layer ops, selection, ChangeNotifier
    widgets/
      meme_canvas.dart            composites every layer (also the export source)
      selection_overlay.dart      tap/drag/resize/rotate/tail handles
      layers_panel.dart           reorderable z-order list + add-layer menu
      inspector_panel.dart        per-layer-kind sub-inspectors
      layer_renderers/
        background_renderer.dart
        text_renderer.dart
        hyperlink_renderer.dart
        image_renderer.dart
        callout_renderer.dart    bubble + dynamic tail painter
    screens/
      home_screen.dart            landing screen
      editor_screen.dart          3-pane editor (layers | canvas | inspector)
      image_editor_screen.dart    modal: crop / rotate / background-mask
    services/
      image_export_service.dart   RepaintBoundary → PNG, + save
      image_processing_service.dart pure-Dart crop / rotate / flood-fill / mask
      media_picker_service.dart   pick an image (all platforms)
      platform_saver_default.dart native "save as" dialog
      platform_saver_web.dart     web download (conditional import)
      social/
        social_poster.dart        SocialPoster interface + PostResult
        share_sheet_poster.dart   native share sheet (the default)
        direct_api_poster.dart    documented stub for API posting
  test/
    meme_controller_test.dart     unit tests for the layer model + controller
    image_processing_service_test.dart tests for crop / rotate / flood-fill
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

## Dependencies

| Package               | Why                                                        |
| --------------------- | ---------------------------------------------------------- |
| `share_plus`          | Native OS share sheet (post with your own logins).         |
| `file_selector`       | Cross-platform image picking and "save as" dialog.         |
| `flutter_colorpicker` | Pure-Dart colour picker that works on every platform.      |
| `url_launcher`        | Open URLs from the inspector preview.                      |
| `image`               | Pure-Dart crop / rotate / flood-fill for the image editor. |

## Platform notes

- **Web:** sharing uses the browser Web Share API where available; "Save"
  triggers a normal download. Image export uses the CanvasKit renderer.
- **Windows / Linux:** native file *sharing* support is limited; if the
  share sheet is unavailable the app tells you to use **Save image…**
  instead.
- **iOS/macOS:** you may need to add a usage description and enable the
  relevant entitlements for file access — `flutter create .` sets up
  sensible defaults.
