# Proofing continuation after the 9d90518 handoff

The source improvements are saved on `codex/proofing-20261116-resume` at
`731d3708513d00fde9ac32dcb32bac1d39631214`. Two incoming test-only lint fixes
are saved at the frozen source `8b93e866b4661d19f4bbad4e1069c0a609441ebb`.
**Final combined local qualification passed**, completing on 16 November 2026
at **16:08:26 UTC / 17:08:26 CET**. Subsequent commits contain documentation
and evidence only. No GitHub Actions, workflow, check-run or commit-status
endpoints were queried or waited for.

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

## Final combined verification

All final engine/editor groups ran against the exact frozen source
`8b93e866b4661d19f4bbad4e1069c0a609441ebb`, whose Git tree is
`834585ef6d66d995a633d6adf8e45a05628fe039`.

| Check | Result | Evidence |
| --- | --- | --- |
| Full engine, editor library plus 31 selected test files, and example-host analysis | All passed with `--fatal-infos` | [Editor/host receipt](editor/receipt.json) |
| Combined proofing, correction/history, navigation/input, shaping/rendering and Zotero editor suite | **347 passed**, no failures or skips | [Log](editor/editor-tests.log) |
| Separate canvas IME reattachment regression | **1 passed** | [Log](editor/editor-ime-reattachment.log) |
| Hyphenation, bidi, Word layout, DOCX/PDF and contextual shaping; 26 test files | **295 passed**, no failures or skips | [Engine report](engine/README.md) |
| Incoming ODS reader/writer, Zotero and comment/proofing styles; 22 test files | **503 passed**, no failures or skips | [Engine receipt](engine/receipt.json) |
| Harper provider contracts | **8 passed** | [Log](engine/harper-provider-tests.log) |
| Harper native lifecycle/availability guards | **3 passed, 1 real-library test skipped** | [Log](engine/harper-native-guards.log) |
| Example release web build | **Succeeded**; 117 files, 59,826,750 bytes | [Build log](editor/example-web-build.log) |

The editor run retained unchanged hashes for **2,049 source inputs**, **16
runtime/configuration inputs**, the workspace lock and package configuration.
The engine run independently retained unchanged hashes for **4,291 repository
inputs**, **8,097 resolved dependency source/configuration inputs** and **40
runtime/configuration inputs**. Both used the real **108-package workspace**,
and HEAD remained unchanged throughout each run. The complete compressed
manifests, command logs, exact runners and resolved locks accompany the receipts.
The [editor integrity receipt](editor/evidence-integrity.json) independently
rechecks retained command logs, manifests and runner digests.

The successful web build retains the existing nonfatal CupertinoIcons
font-asset warning. It establishes compilation and recorded output files;
it does not establish real-browser interaction, HTTP delivery or CSP behavior.

## Focused component evidence

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
development check; the final combined evidence above establishes the complete
selected suite against the committed source.

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
separately from the fresh run on `8b93e86`: the
[initial editor record](editor-initial-731d370/interrupted-attempt.json) and
[initial engine record](engine/initial-attempt-731d370/interruption.json)
make the interrupted boundary explicit. Neither is counted as a passing run.

## Reproduction

Keep the saved runners available outside a separate checkout of the exact
tested source `8b93e866b4661d19f4bbad4e1069c0a609441ebb`; the report files were
committed after that source. Resolve that checkout's actual Flutter workspace
with the retained runtime and lock, updating absolute package paths for the
chosen checkout. Set `PUB_CACHE` and `TMPDIR` to the prepared locations.
From this report directory, use new output directories:

```sh
python3 editor/verify_editor_final.py \
  --repo /path/to/checkout-at-8b93e86 \
  --flutter /path/to/runtime/flutter/bin/flutter \
  --dart /path/to/runtime/flutter/bin/cache/dart-sdk/bin/dart \
  --expected-source 8b93e866b4661d19f4bbad4e1069c0a609441ebb \
  --output /path/to/new-editor-validation

python3 engine/run-validation.py \
  --repo /path/to/checkout-at-8b93e86 \
  --runtime /path/to/runtime \
  --expected-source 8b93e866b4661d19f4bbad4e1069c0a609441ebb \
  --output /path/to/new-engine-validation
```

The editor runner stops on a failed stage. Creating `OUTPUT/STOP` asks it to
terminate only its active child process group and record the interrupted run.
The [new JavaScript probe](german/new_behavior_web_probe.dart) and
[its verifier](german/new_behavior_web_verify.py) retain the targeted web
acceptance cases separately from the existing ten-check smoke probe.

The [unchanged component comparison](unchanged-component-sources.json)
confirms that dictionary data, hyphenation inputs, the Harper package,
the model evaluation source and package manifests match the handoff. Their
unchanged generators/binaries were not rebuilt merely to repeat prior results.

## Boundaries

Local Flutter tests and a web build do not establish real-browser hosting,
HTTP/CSP delivery or visual end-user interaction. Mobile dictionary acceptance
and non-Linux native Harper loading remain separate platform work. This
continuation does not rebuild Harper native/Wasm binaries or rerun the German
model. Earlier source-specific evidence is preserved with its original scope.
