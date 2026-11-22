# Zotero selected-field context — 22 November 2026

## Delivered milestone

Native Zotero `Field.select` now presents the original citation, bibliography or
note source while Zotero asks a manual-edit or repair question. The engine exposes
typed, validated source ranges; the canvas paints a temporary highlight; and the
native prompt shows the selected text and its body/footnote/endnote location.
Multipart bibliography context is supported. Generated note labels are excluded.

The presentation preserves the writing caret and backward selection, active Notes
target, focus and undo history. It reveals offscreen source text on both axes and
clamps to the canvas extent. Cleanup restores the prior viewport only if the user
has not subsequently scrolled, zoomed, changed the document or changed the active
host. Pending insertions and imported transfer clones expose status without
pretending their detached data is live source text. Completion, cancellation,
errors, disposal and stale host state clear the temporary presentation. All eight
native alert-button return codes retain their existing meanings.

The regular workspace bounds long instructions and source context so the cancel
control remains usable in a short window at enlarged text sizes. The direct
command prompt and the regular workspace both exercise long bibliography context.

## Intake and remote history

The initial baseline was remote main
`2eecf9aec2c7d1f979064448b911b516d3f56c73`. The [initial intake](intake.md)
and [inventory](intake.json) checked all 21 then-current fork branches, four
upstream branches and 30 recently updated closed pull requests. All captured
heads and merged PR commits were already ancestors of that baseline; there were
no open PRs to incorporate at that point.

Remote main advanced during implementation. The [incoming audit](incoming/README.md)
records Word PR #359 at main `191ed89b23696c5634689bb90b87119c761f0c85`
and Mail head `29fc72a0a7cffa7cfed2abdac2a3f82d2ff17f95`. Mail was
independently qualified in a detached checkout: 191 tests passed across eight
suites and all seven changed production/test files analyzed cleanly, with no
source fixes. Its own work record still describes a checkpoint; the new
[qualification](incoming/qualification/README.md) supplies fresh execution evidence.
Integration preserves both histories and both packages' changelog entries.

Incremental checkpoints are saved to `codex/zotero-field-context-20261122`:

| Commit | Saved work |
| --- | --- |
| `3b7687ff52d6b8d22383985a662edf80bdb2c927` | Reconciled initial intake and bounded milestone plan |
| `9c8816b26b34a8e046cd2e3a3a5254b90d945029` | Typed engine context, 15 new tests and engine evidence |
| `a83700c69c2ec6d134b780a16a363839425101ae` | Body/table/note highlights and nine raster regressions |
| `e8cc579563f9c2d9a8922ed47bc8fe310f1ed0af` | Transaction/controller/prompt integration and local evidence |

Each remote update checks the expected branch head, uses a normal forward ref
update and verifies the published tree against the local snapshot. No force push,
GitHub Actions wait or hosted-run result is part of acceptance. Later fix,
integration and qualification commits follow these checkpoints on the same branch.

## Local validation

The [runtime record](runtime/README.md) identifies the verified Flutter 3.47.8 /
Dart 3.13.7 toolchain, unchanged dependency manifests and locked resolution. Tests
run locally with `CI=true` and the installed cache. That environment flag also
avoids Flutter's cloud-metadata bot detection; no cloud-metadata access was used.

| Gate | Accepted checkpoint result | Evidence |
| --- | --- | --- |
| Engine context, native session, transfer, writing position and Add Note | 154 passed, including 15 new context cases | [engine](checks/engine/validation.json) |
| Canvas highlight raster/geometry | 9 passed | [render](checks/render/receipt.json) |
| Controller and transaction | 105 passed, including 31 context cases and five canvas-backed viewport regressions | [controller](checks/controller/final-validation.json) |
| Native prompts | 21 passed, including both short-workspace cancellation paths | [dialog](checks/dialog/README.md) |
| Incoming Mail exact head | 191 passed across eight suites; analysis clean | [Mail](incoming/qualification/summary.json) |

Counts from attempts and reruns must not be added together. Earlier receipts name
the source hashes they exercised; final integrated-source receipts will additionally qualify the combined source
and add focused host and Word coverage.
Failed development attempts remain recorded as diagnostics, not passing evidence.
Review uncovered and fixed high-zoom horizontal reveal, bottom-page viewport
clamping, first-paint note measurement and short-workspace instruction overflow.

## Limits and next milestone

This increment completes selected-field context; it does not establish complete
Word/LibreOffice parity. Tests use the native protocol/session and simulated
transport. No installed Zotero, Microsoft Word or LibreOffice acceptance session
was performed. Structural recovery of malformed citation fields remains the next
native implementation milestone: identify the owning source safely, offer a
reviewable repair/unlink decision, and preserve cancellation, one-step undo and
DOCX/ODT persistence. The [parity roadmap](../../roadmaps/zotero/word-processor-parity.md)
and [integration guide](../../zotero-support.md) describe the boundaries and API.

The current Zotero comparison target is Word and LibreOffice. Modern Zotero does
not support Apache OpenOffice; a legacy OpenOffice acceptance target needs exact
application and Zotero/plugin versions.

## Upstream references

- [HTTP citing protocol](https://www.zotero.org/support/dev/client_coding/http_integration_protocol)
- [Word processor plugin usage](https://www.zotero.org/support/word_processor_plugin_usage)
- [Word processor plugin troubleshooting and compatibility](https://www.zotero.org/support/word_processor_plugin_troubleshooting)
