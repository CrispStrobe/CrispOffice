# Proofing continuation after the 9d90518 handoff

The source improvements are saved on `codex/proofing-20261116-resume` at
`731d3708513d00fde9ac32dcb32bac1d39631214`. Two incoming test-only lint fixes
are saved at the frozen source `8b93e866b4661d19f4bbad4e1069c0a609441ebb`.
Final combined local qualification
is in progress. No GitHub Actions, workflow, check-run or commit-status
endpoints are required or queried.

## Incoming histories

The initial [remote inventory](remote-inventory.json) captured **64 branches
and 68 pull requests** at **2026-11-16 15:39:54 UTC / 16:39:54 CET**. Explicit
empty second pages establish the bounded inventory. The integrated checkpoint
`e9bb38e93726f6b5eab5688aee125bc182c05ed7` retains four parents:

- The complete `9d90518` proofing handoff.
- `c9fc24c`, including contextual shaping/wrapping, renderer, focus/direction,
  font notices and the ODS writer feature/vendor histories.
- `91f82b8`, current main and the Office workflow qualification record.
- `ec94795`, the incoming ODS conditional-format/validation writer.

All **64 observed branch heads and all 68 PR heads** are actual ancestors of
the integration, including PR heads whose branches no longer exist. See the
[individual ancestry checks](ancestry-verification.json). The only merge
conflict was in the engine changelog; both sets of entries were retained.
This includes newly merged PRs #67 and #68, and the already integrated open
Zotero PR #63. The cutoff bounds this work while other branches continue.

All **228 files** in the handoff's `docs/validation/proofing-20261116` tree
remain byte-for-byte unchanged, including compressed archives containing
earlier manifests and logs. The [integrity receipt](handoff-evidence-integrity.json)
compares every original Git blob ID.

## New behavior

- German agreement checks require the complete subject/verb context to be
  outside protected URLs, email addresses and code. A URL ending in `/ich`
  cannot govern a following `bist` in prose.
- URL protection recognizes uppercase HTTP(S)/WWW prefixes. Surrounding
  brackets and typographic quotes remain available to balance checks, while
  balanced parentheses in a URL and IPv6 host brackets remain protected.
- Swiss uppercase sharp-s spellings receive the expected uppercase `SS`
  suggestions, for example `STRAẞE` to `STRASSE` and `GRÜẞE` to `GRÜSSE`.
- Invisible ZERO WIDTH SPACE opportunities and WORD JOINER/zero-width
  no-break constraints survive removal of nonpainting controls. Batch,
  prepared, emergency and contextually remeasured wrapping retain original
  source offsets and consume the original text without inserting glyphs.
- The review dialog labels invisible replacements, such as **Insert space**
  and **Use space**, while applying the original literal replacement.
- **Ignored checks** lets users restore individual ignored words in their
  original language, restore a rule, or review ignored occurrences again.
  This works without changing document text, undo history, personal words,
  other languages' ignored words or the current document language.

No dictionary, hyphenation pattern, dependency manifest, external corpus or
model setting changed. The seven-rule German checker remains conservative;
the experimental model remains disabled and evaluation-only.

## Component evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Full German/shared proofing suite | 54 tests passed | [Receipt](german/receipt.json) |
| Proofing strict analysis | Passed with `--fatal-infos` | [Log](german/analyze.log) |
| Compiled JavaScript probe under Node | 10 checks passed | [Log](german/javascript-smoke.log) |
| New URL/Swiss behavior compiled to JavaScript | 20 targeted checks passed | [Receipt](german/new-behavior-web-receipt.json) |
| Invisible controls plus related line-break/hyphenation tests | 70 tests passed | [Receipt](line-controls/line-breaker-validation.json) |
| Same new controls tests on the integrated baseline | 13 failed; 3 negative controls passed | [Baseline log](line-controls/line-breaker-baseline.log) |
| Focused session and review dialog suite | 49 tests passed | [Log](editor-focused/focused-tests.log) |

Groups overlap and must not be added into a repository-wide total. Component
runs retain exact commands, complete logs and source hashes. The
[source binding](component-source-binding.json) confirms the committed German
inputs match the successful component receipt. The focused editor run is a
development check; final combined source-bound evidence is recorded separately.

The [runtime setup archive](runtime-setup.tar.gz) retains the official Flutter
3.47.8/Dart 3.13.7 SDK digest, pinned package archive checks, 108-package offline
workspace resolution, helper scripts, lock/configuration and setup logs.
The direct Dart executable avoids concurrent Flutter launcher stamp updates.

The editor development logs preserve a launcher race, a new test's incorrect
model accessor and a fake-async test wait. Those were harness issues: the
accessor uses `inlines.whereType<WmlRun>()`, and widget tests schedule checks
before advancing their fake clock. Failed/interrupted attempts are retained
alongside the subsequent passing focused run.

The first combined analysis also found an unused local binding in the incoming
ODS writer test and an unnecessary import in the incoming input-ownership test.
The narrow fixes retain the cell initialization and all assertions. The first
combined attempt was interrupted before completion; its logs are retained
separately from the fresh run on `8b93e86`.

## Boundaries

Local Flutter tests and a web build do not establish real-browser hosting,
HTTP/CSP delivery or visual end-user interaction. Mobile dictionary acceptance
and non-Linux native Harper loading remain separate platform work. This
continuation does not rebuild Harper native/Wasm binaries or rerun the German
model. Earlier source-specific evidence is preserved with its original scope.
