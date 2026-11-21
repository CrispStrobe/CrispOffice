# Word VBA shading and text construction — work checkpoint

The task starts from fork `main` at
`4970f71f983535d045ce263e86835b499db4fda9`. All 35 other fork branch heads,
all four upstream heads and the latest 100 PR heads (#233–332) are already
ancestors of that commit. There were no open PRs at intake. Exact observed
refs and comparison receipts are retained in [remote-intake.json](remote-intake.json);
[intake.json](intake.json) is the compact audit.

Work is saved incrementally on `codex/word-vba-format-controls-20261121`.
GitHub Actions are not awaited; local execution is the validation gate.

## Planned scope

- Typed `Shading` on an explicitly selected paragraph or paragraph Range,
  with `BackgroundPatternColor` and `BackgroundPatternColorIndex` writes.
- Guarded native solid paragraph backgrounds, preserving unrelated source
  properties and explicit automatic/background inheritance overrides.
- Shared source-known `Space`, `String`, `ChrW` and `AscW` construction,
  including applicable `$` String forms, exact bounds and resource limits.
- Compiler, native document, transaction and portable VM/JavaScript checks.

This checkpoint records intake and scope only; it is not a completed feature
or qualification claim. Final results will replace this status before merge.
The pinned Dart 3.13.7 runtime and all 56 locked engine dependencies are
available locally without changing tracked dependency manifests.
