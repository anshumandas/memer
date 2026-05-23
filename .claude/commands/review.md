---
description: Review uncommitted changes against memer's conventions
argument-hint: [optional focus, e.g. "callouts" or "export"]
---
Review the current uncommitted changes: !`git diff`

Focus: $ARGUMENTS

Check against project rules:
- state flows through `MemeController`; UI reads it via `ListenableBuilder`
- callout positions stay FRACTIONAL (0..1)
- no `dart:io` / `dart:html` in shared code (only behind conditional imports)
- posters return `PostResult` and never throw
- export path stays WYSIWYG (same widget used for preview and PNG)
- `withOpacity` used (not `withValues`)

Report concise, actionable findings only.
