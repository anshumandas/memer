# memer

A **client-only** Flutter app for making simple memes and posting them to your
social networks. There is **no backend server** — the app renders your meme on
the device and hands it to your operating system's native share sheet, so you
post through apps you're *already* logged into (Instagram, X, WhatsApp,
Facebook, Messages, email, …).

Project location: `C:/workspace/memer`.

## Features

- Solid **background colour** picker.
- Optional **background image** (loaded from disk/gallery, kept in memory).
- Classic **top / bottom captions** with an automatic contrasting outline.
- Optional **speech-bubble callouts** you can drag around, recolour, resize and
  point in any direction.
- One-tap **share** to any installed app via the native share sheet.
- **Save image…** to export a PNG to disk (or download it, on web).
- Runs on **Android, iOS, web, Windows, macOS and Linux** from one codebase.

## Why no direct "post to API" buttons by default?

This uses a **hybrid** approach:

- **Default path — share sheet (no backend).** The only way to post to the big
  networks *without* a server. Their APIs require OAuth flows whose token
  exchange uses a **client secret**, which can't be safely embedded in a
  client-only app, plus registered redirect URIs and app review.
- **Extension point — direct API posting.** `lib/services/social/` defines a
  `SocialPoster` interface. `ShareSheetPoster` is the working implementation;
  `DirectApiPoster` (with `XApiPoster` / `InstagramApiPoster` stubs) is where
  to add real API posting *if you ever add a small backend* to hold the secret
  and complete the OAuth exchange. Dropping in a finished implementation
  requires **zero UI changes**.

## Getting started

This package ships the application code (`lib/`, `test/`, `pubspec.yaml`) plus
the Claude Code harness (`CLAUDE.md`, `.claude/`). The machine-generated
platform folders (`android/`, `ios/`, `web/`, etc.) are not included — generate
them in one command:

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
      callout.dart                speech-bubble data model
      meme_config.dart            immutable snapshot of a meme
      meme_controller.dart        ChangeNotifier holding live edit state
    widgets/
      meme_canvas.dart            the composited meme (also the export source)
      meme_text.dart              outlined caption text
      callout_bubble.dart         speech bubble painter
      draggable_callout.dart      tap-to-select / drag-to-move wrapper
    screens/
      home_screen.dart            landing screen
      editor_screen.dart          the editor (preview + controls + share)
    services/
      image_export_service.dart   RepaintBoundary → PNG, + save
      media_picker_service.dart   pick a background image (all platforms)
      platform_saver_default.dart native "save as" dialog
      platform_saver_web.dart     web download (conditional import)
      social/
        social_poster.dart        SocialPoster interface + PostResult
        share_sheet_poster.dart   native share sheet (the default)
        direct_api_poster.dart    documented stub for API posting
  test/
    meme_controller_test.dart     unit tests for the models + controller
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

The on-screen preview lives inside a `RepaintBoundary`. When you share or save,
the app calls `RenderRepaintBoundary.toImage()` and encodes the result as PNG —
upscaled to ~1080px wide regardless of screen size, so the output is crisp and
identical to what you see. Because the *same* widget tree is used for preview
and export, it's truly WYSIWYG.

## Dependencies

| Package               | Why                                                        |
| --------------------- | ---------------------------------------------------------- |
| `share_plus`          | Native OS share sheet (post with your own logins).         |
| `file_selector`       | Cross-platform image picking and "save as" dialog.         |
| `flutter_colorpicker` | Pure-Dart colour picker that works on every platform.      |

## Platform notes

- **Web:** sharing uses the browser Web Share API where available; "Save"
  triggers a normal download. Image export uses the CanvasKit renderer.
- **Windows / Linux:** native file *sharing* support is limited; if the share
  sheet is unavailable the app tells you to use **Save image…** instead.
- **iOS/macOS:** you may need to add a usage description and enable the relevant
  entitlements for file access — `flutter create .` sets up sensible defaults.
