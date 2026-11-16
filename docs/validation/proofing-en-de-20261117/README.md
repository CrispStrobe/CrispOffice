# English/German proofing continuation — 17 November 2026

**The full local integration gate passed** against source commit
`b9ac68fbbb33c7731a3241e4065f6dfb71e36a57`. The run completed on 17 November
2026 at 00:40 CET (16 November, 23:40 UTC). All **2,083 source inputs** and the
recorded runtime hashes stayed unchanged. Commands, full logs, input manifests,
and child receipts are retained in [integration/receipt.json](integration/receipt.json).

Work is saved incrementally on `codex/proofing-en-de-20261117` and proposed in
[draft PR #91](https://github.com/CrispStrobe/quds_office_suite/pull/91).
No GitHub Actions runs were queried, rerun, or waited for. The final checkpoint
adds documentation/evidence and retains the subsequently observed main commit
`f57d8f5debd8c27fe7cb9b9322c84fb284ff2c49`; its only content change is an ODT
frame-dimension documentation correction. The
[source-equivalence receipt](post-qualification-source-equivalence.json)
confirms that qualified implementation, tests, tools, data, and lock inputs
remain identical after that merge.

## What improved

### Shared source protection and hyphenation

`OfficeProofingTextRanges` supplies one source-coordinate implementation for
URLs, email addresses, and paired backtick regions. It preserves original
UTF-16 ranges, recognizes decomposed Unicode email domains, retains internal
URI apostrophes and balanced URL brackets, and leaves surrounding prose
punctuation available to the checker. Backtick pairing uses a bounded pass
over delimiter runs. An unmatched opener does not hide the rest of a document.

English and German hyphenation use the same protected ranges and word-boundary
rules. German gains identifier, contraction, supplementary-character, and join
control guards. Equivalent `de`, `de-DE`, and `de-1996` tags work across styled
runs; differing regional tags remain conservative. Umlaut normalization retains
grapheme-safe offsets into original text. Existing US and GB pattern/exception
behavior is preserved and tested on both VM and JavaScript.

### German spelling and vocabulary

The shipped dictionary is unchanged. Suggestion generation now combines
bounded orthographic substitutions, with at most 32 substitution states and
the existing shared 6,000-candidate / five-result limits. Every dictionary
correction still has to match an exact shipped form.

| Input or action | Improved behavior |
| --- | --- |
| `uebermaessig` | Suggests `übermäßig`. |
| `aeusserst`, `grosszuegig` | Suggests `äußerst`, `großzügig`. |
| `Abenteuerbuecher` | Suggests `Abenteuerbücher`, preserving the legitimate earlier `ue`. |
| Personal term `Qudsmarke` plus `Qudsmarke-Tür` | Accepts the explicitly hyphenated compound. |
| `Qudsmarke-Huas` | Can suggest `Qudsmarke-Haus`; an ignored token does not become a reusable compound component. |
| Sentence-initial correction | Preserves initial capitalization. |
| Vocabulary restore with language aliases | Unions equivalent entries instead of silently overwriting them. |

Unicode connector/digit-adjacent identifiers are excluded. Personal and
restored entries share normalization, and normalized-empty entries are rejected.
Regional/case restrictions still apply. This remains finite word-list spelling
with explicit compound support, without a claim of complete German morphology
or unrestricted compound segmentation.

### German grammar and review UI

Agreement checking expands from nine to **25 finite present-tense verb
families**. Subject contexts remain deliberately narrow. The eighth rule
category, `de.grammar.seit-seid`, recognizes selected predicative and temporal
contexts; it does not blindly replace every occurrence next to a time expression.

Regressions cover `Du gibt → Du gibst`, `Ihr seit hier → Ihr seid hier`, and
`Ich bin seid gestern hier → Ich bin seit gestern hier`. Valid nominal uses,
including Essen/Lesen/Lernen and nominal Du/Ich after declined or fused
determiners, have explicit negative controls. Independent review found seven
false positives; all seven were fixed before qualification. Ambiguous uppercase
noun/verb homographs trigger narrow abstention guards.

Grammar checks now work through authored soft hyphens while mapping findings
back to original UTF-16/grapheme ranges, including nonzero block origins and
preceding emoji. Friendly rule labels, correction, undo, ignore, and restore
behavior are tested in the editor. These are eight independently authored rule
categories, not a general German parser.

### English Harper

Harper findings are filtered against the same original-source protected ranges.
Code, URLs, and email remain untouched while surrounding prose is still
checked. Existing discretionary-hyphen projection and strict malformed-range
guards remain. Tests cover nonzero origins, emoji, internal soft hyphens,
protected text, and adjacent prose. Actual Linux native and shipped Wasm
execution exercise these paths, dialects, concurrency, ignore, disposal, and
availability behavior.

The compiled Dart web smoke runner had a stale expected count of eight despite
the expanded program. It now requires all **11** actual checks and correct
worker cleanup; the assertion was corrected without removing any check. The
failed attempt and successful qualification are both retained.

## Incoming history and remote checkpoints

The [initial inventory](reconciliation.json), recorded at 00:14:40 CET, covers
94 fork branches, 87 fork PRs, four upstream branches, and four upstream PRs:
**189 named references / 128 distinct heads**. All were ancestors of the
selected starting point `becfa07c1be62429a8bcf78910aa1ffb46248b1a`.

The [later fork inventory](reconciliation-late.json), pinned at 00:30:33 CET,
covers **98 branches and 89 PRs / 127 distinct heads**. Six newer external
heads were integrated: main `50b3694`, rendering `4d923ab`, Zotero `5adf034`,
and equivalent original conditional-DXF histories `5fb8762`, `31a2638`, and
`76c7087`. The two inventories together cover **135 distinct heads**;
[independent ancestry checks](independent-review.json) found every one to be an
ancestor of the qualified commit. This is a pinned inventory, not a claim
that other writers stopped advancing remote branches afterward.

The spreadsheet merge retains differential fill/font colors and `dxfId`
together with rule priority and `stopIfTrue`. A new regression checks those
properties through three isolate save/reopen cycles and a rank edit. Rendering
and Zotero incoming tests were added to the gate. The subsequently observed
documentation-only main `f57d8f5` was merged after qualification. No history
was discarded or force-pushed.

| Remote checkpoint | Purpose |
| --- | --- |
| `deb397062637cd3d6290096e825de8b168b4464e` | Shared protected ranges, hyphenation guards, initial receipts. |
| `4751fe8ece91ee7e36c47b1dc954ba26f8997cfc` | German spelling and vocabulary improvements. |
| `6cd0452855e5ba584f91f33cc9449dfc5be885ef` | Harper source protection, reviewed range fixes, expanded gates. |
| `a64e15adb58a429ff4816cf2d29dd52bc50294d8` | Reviewed grammar, editor regressions, smoke-count correction. |
| `b9ac68fbbb33c7731a3241e4065f6dfb71e36a57` | All six newer incoming histories and frozen source for the full local gate. |

The following documentation/evidence checkpoint is on the same branch. Each
checkpoint uses `[skip ci]` and a non-forced expected-head update.

## Fresh local validation

These groups overlap and must not be added into a repository-wide total.
No passing group below has a skipped test.

| Check | Result | Evidence |
| --- | --- | --- |
| Full strict engine, editor, example, and Harper analysis | Passed all four packages | [Integration receipt](integration/receipt.json) |
| Hyphenation, layout, serialization, PDF/export group | **258 passed** | [VM log](integration/engine-hyphenation/hyphenation-tests.log) |
| English/German hyphenation compiled JavaScript | **23 passed** | [Node log](integration/engine-hyphenation/hyphenation-javascript-tests.log) |
| Shared/German proofing, spelling, rules, vocabulary | **95 VM + 95 Node passed** | [German receipt](integration/german/receipt.json) |
| Standalone compiled German smoke checks | **10 passed** | [Smoke log](integration/german/javascript-smoke.log) |
| Exact German dictionary and DE/US/GB pattern regeneration | Passed | [German receipt](integration/german/receipt.json), [hyphenation receipt](integration/engine-hyphenation/hyphenation-validation.json) |
| Harper provider/source contracts in final integration | **27 passed**, reference probe passed | [Contract log](integration/harper-contract-tests.log) |
| Incoming ODS, conditional styles, rename, cmap, PDF, Zotero | **376 passed** | [Incoming log](integration/incoming-engine-tests.log) |
| Selected editor/widget suites | **304 passed** | [Editor log](integration/editor-tests.log) |
| Separate IME reattachment regression | **1 passed** | [IME log](integration/editor-ime-reattachment.log) |
| Release web build and Harper installation | Passed; **123 files**, 70,648,055 bytes hashed | [Build log](integration/example-web-build.log), [bundle manifest](integration/web-bundle-sha256.json.gz) |

Harper was built and qualified earlier in this same continuation. The full
gate verified its unchanged **36 source hashes**, **six distribution
artifacts**, and all nine command-log hashes before reusing that successful
receipt. This is recorded as matching-source receipt reuse, rather than a
second execution of the backend commands.

| Actual Harper qualification | Result |
| --- | --- |
| Rust release tests | **5 passed** |
| Dart VM suite with native backend enabled | **31 passed, zero skipped** |
| Compiled JavaScript provider/source contracts | **27 passed** |
| Shipped Wasm worker | **5 checks passed** |
| Compiled Dart → shipped Wasm transport | **11 passed; 3 workers created / 3 terminated** |
| License-policy / host-packaging unit tests | **3 / 2 passed** |

The 31 VM tests comprise 27 provider/source contracts and four native
transport/lifecycle tests. The persistent real native-worker test sends 13
requests; the suite count is not 31 independent engine grammar cases. See the
[Harper receipt](integration/harper/receipt.json) and
[build receipt](integration/harper/build-receipt.json).

## License and dependency continuity

The [independent review](license-continuity-review.json) verifies **103 existing
protected inputs and all 13 dependency manifests/toolchain specifications
unchanged** from the integrated starting point. All 17 German generated-file
SHA-256 pins and English source/generated-data pins match. No new dictionary,
pattern corpus, model, runtime dependency, or license selection was introduced.

German word-list and pattern inputs remain MIT; GB patterns remain MIT. US
patterns retain their individually reviewed `LicenseRef-Kuiken-permissive`
terms. The incoming change adds complete, byte-identical standalone original
US/GB notices and makes regeneration verify them. Existing notices remain.
Harper remains Apache-2.0 with the existing reviewed transitive selections.
The graph still has **226 packages**, with unchanged notices and the three
selected MPL-2.0 source archives (`colored 3.1.1`, `cssparser 0.38.0`, and
`dtoa-short 0.3.5`). The generated manifest and notice/source bundle are
byte-identical to the starting versions.

The accepted policy excludes GPL/AGPL/LGPL-only components, dictionaries, and
rule resources. MPL source-distribution obligations are retained; it is not
relabeled as a permissive license. This review establishes continuity of the
pinned inputs rather than a new legal certification of every inherited dependency.

## Runtime setup and reproduction

The restored runtime was Flutter **3.47.8**, Dart **3.13.7**, Rust **1.100.0**,
wasm-bindgen **0.2.130**, and Node **24.22.1**. The official Flutter archive and
all **162 pinned Pub archives** were SHA-256 verified. `flutter pub get
--offline --enforce-lockfile` and `cargo fetch --locked` passed. The original
workspace lock was restored without changing dependency constraints. Its exact
copy is [integration/pubspec.lock](integration/pubspec.lock). Setup provenance
is in [runtime-setup-receipt.json](runtime-setup-receipt.json),
[flutter-release.json](flutter-release.json), and
[pub-cache-receipt.json](pub-cache-receipt.json).

From a checkout with those toolchains and dependencies prepared, use fresh
output directories for every attempt:

```sh
python3 packages/quds_proofing_harper/tool/build.py --native --web

python3 packages/quds_proofing_harper/tool/verify.py \
  --dart /absolute/path/to/flutter/bin/cache/dart-sdk/bin/dart \
  --node /absolute/path/to/node \
  --build-output packages/quds_proofing_harper/build \
  --output /absolute/path/to/new-harper-evidence

python3 tools/proofing/verify_integration.py \
  --flutter /absolute/path/to/flutter/bin/flutter \
  --dart /absolute/path/to/flutter/bin/cache/dart-sdk/bin/dart \
  --node /absolute/path/to/node \
  --output /absolute/path/to/new-integration-evidence \
  --harper-build packages/quds_proofing_harper/build \
  --harper-receipt /absolute/path/to/new-harper-evidence/receipt.json \
  --build-web
```

The verifier requires committed relevant source inputs and checks before/after
source and runtime hashes. Supply `--german-wordlist` with the pinned upstream
file for offline regeneration; otherwise it downloads and verifies that exact
input. Recorded commands preserve their original absolute runtime paths, so
use local equivalents when reproducing.

## Explicit limits and retained failed attempts

- **Real browser acceptance is blocked.** Chromium 156 aborted before loading
  a page because this workspace disallowed its singleton socket (`EPERM`). The
  sandbox remained enabled. There were zero browser requests and zero browser
  acceptance checks. The [browser receipt](browser/receipt.json) retains the
  failure. `tools/proofing/browser_transport_smoke.mjs` reruns the compiled Dart
  smoke with real Worker/fetch/Wasm, loopback HTTP, and enforced CSP in a suitable
  environment. Node/Wasm results and the build do not establish browser/CSP acceptance.
- Native execution covers **Linux x86_64**. No Android/iOS device, Windows, or
  macOS native acceptance is claimed. Mobile spelling adapter protocol tests
  are included; actual device spelling remains a separate acceptance step.
- German grammar is finite and conservative. The experimental German model
  remains disabled, unchanged, and unevaluated in this turn.
- This is a focused integration set, not the complete repository suite. The
  successful web build retained a warning about absent Cupertino icon fonts;
  proofing packaging completed with verified assets.
- Independent merge review records incoming main's existing yellow-fill fallback
  for font-only spreadsheet differential styles. This was not introduced by the
  conflict resolution and is outside this proofing change; the
  [review receipt](independent-review.json) and
  [reproduction](review/conditional_merge_review.dart) retain the finding.

The initial hyphenation failure exposed a modifier-letter apostrophe case and
two incorrect expected offsets. The [failed log](hyphenation-initial-failed.log)
and passing checkpoints are retained. The
[Harper attempt](attempts/harper-stale-smoke-count/receipt.json) records the stale
smoke-count assertion before its fix. The browser's first temporary-directory
failure is under `browser/attempts/`. An analyzer wrapper race is retained in
`checkpoints/engine-analyze-checkpoint.log`; direct SDK invocation and the final
strict analyzer runs passed. Historical failures are not replaced by the final
successful receipts.

`EVIDENCE.json` inventories this report directory by SHA-256. Source, pinned
inputs, receipts, and commands are remotely saved to reproduce the generated
native/Wasm/web outputs. Generated SDK, cache, and release binaries are not
added to Git.
