---
description: Static analysis + formatting check
allowed-tools: Bash(flutter analyze:*), Bash(dart format:*)
---
Run `flutter analyze`, then `dart format --output=none --set-exit-if-changed .` to find unformatted files. Report problems grouped by severity (error/warning/lint) with concise fixes. Do not change code unless asked.
