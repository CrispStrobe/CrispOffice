# Zotero validation — 15 November 2026

## Native citing continuation: current executed results

Native desktop controls now use Zotero's picker, document style preferences and
complete CSL processor. The staged adapter handles inline/footnote/endnote
citations, document-wide refresh, bibliographies, native preference storage,
result review and one-step undo/redo.

At canonical code commit `55d46a0fb5f7392dab1a604bc3c15126bd3e380d`, after
reconciling incoming main through PR #46:

| Local check | Result |
| --- | ---: |
| Zotero/Word engine and related import cohort | 380 passed |
| Shared Flutter controller/formatter/dialog cohort | 117 passed |
| Actual Studio native transport | 16 passed |
| Incoming ODS/conditional-affix integration cohort | 80 passed |
| **Canonical selected tests** | **593 passed** |
| Engine, editor and Studio strict analyzers | Clean |
| 27 changed Dart targets, formatter check | Clean |
| Incremental diff whitespace check | Clean |

All 1,558 recorded source/dependency-input hashes, HEAD and harness inputs stayed
unchanged. Runtime: official Flutter 3.47.8 / Dart 3.13.7, with genuine locked
dependencies and unchanged production constraints. The final documentation
commits retain the tested implementation.

See [current evidence and reproduction](validation/zotero-citing-20261115/README.md),
[the exact receipt](validation/zotero-citing-20261115/final/receipt.json), and
[the implementation review](validation/zotero-citing-20261115/REVIEW.md). The
real-processor fixtures cover German *Ebd.*, numeric renumbering and APA
disambiguation; protocol/UI transcripts remain deterministic local tests.
CrispCloud's companion evidence records its host transport and vendor guards.

Full native builds, live Zotero/private-account access, OS-keychain acceptance
and native Word refresh remain unverified. Mixed inline styling and bibliography
layout remain simplified with review; Quds note preview numbering follows stored
IDs; ODT active-citation transfer remains absent. Native source and style controls
are implemented, so the older sections' statements that those are absent describe
only their historical source revisions. No GitHub Actions were used.

## Earlier rich formatting continuation: historical executed results

The implementation now preserves linked multi-run simple fields, numeric
citation caches and unchanged rich citation results, and adds reviewed rich
bibliographies with supported Word character formatting.

At canonical code commit `b09537fb34dd711118ae6df5872184b6e813d2df`:

| Local check | Result |
| --- | ---: |
| Engine/client/parser/Word import and related regressions | 232 passed |
| Shared Flutter controller/formatter/dialog regressions | 81 passed |
| **Combined selected tests** | **313 passed** |
| Changed engine and editor analyzers with `--fatal-infos` | Clean |
| All 11 changed Dart files, formatter check | Clean |
| Incremental Git diff, whitespace check | Clean |

The final run verified unchanged tracked library/test source fingerprints.
The preceding source was separately qualified with 171 baseline passes,
including all **39 previously unexecuted cases**. Those baseline counts are not
added again to the final total. This continuation adds **63 new cases**.

See [the current evidence and reproduction guide](validation/zotero-rich-text-20261115/README.md),
[exact final receipt](validation/zotero-rich-text-20261115/final/receipt.json),
and [implementation review](validation/zotero-rich-text-20261115/REVIEW.md).
Official Flutter 3.47.8 / Dart 3.13.7 and genuinely resolved, enforced Pub
lockfiles were used. Repository dependency manifests were not relaxed.

CrispCloud records its separate 23 actual host service/transport/ribbon tests
and normal Python vendor guards in its companion validation guide. No GitHub
Actions were polled, awaited or rerun; remote checkpoints use `[skip ci]`.

Full native builds, live desktop/private-account access, real OS-keychain
acceptance and native Word/Zotero refresh remain unverified. Full document-wide
CSL processing, the native picker/HTTP citing adapter, active ODT transfer,
small-caps/layout rendering and new mixed-format inline citation generation
remain outside this increment.

## Earlier local identity continuation: historical source review

This continuation adds identity-checked desktop operations for unsynced
`users/local/<localUserKey>/items/<itemKey>` references. It also checks numeric
reference identities before connected document operations and prevents
two-phase desktop exports from accepting a database or library-version change.

**No Dart/Flutter tests, analyzer, formatter or full application builds were
executed in this continuation.** The execution service returned
`No usable execution environment is available` during setup attempts.
No GitHub Actions were awaited, polled, rerun or used as validation.

Fresh checks are repository/source checks: exact-context integration of recent
main changes, remote checkpoint/head verification, source review of the new
code/tests, and CrispCloud's managed-source comparison to its pinned canonical
Quds source. These checks do not establish that the Dart code compiles or
that the widget regressions pass.

New regression cases cover URI/route separation, colliding item keys in
different local profiles, wrong or missing returned identities, alias
normalization, zero network calls for incompatible requests, exact selection
completeness, server/database and library-version changes, and preservation of
original DOCX identities. The existing online and desktop tests remain in place.

### Run locally

Use the repository's Flutter/Dart toolchain and resolve the workspace dependencies
before running the tests. The shared packages are used by both hosts:

```sh
flutter pub get
cd packages/quds_office_engine
dart test test/zotero_client_test.dart test/zotero_identity_client_test.dart test/word_zotero_test.dart
dart test test/ods_sheet_reader_test.dart test/word_content_control_fidelity_test.dart
cd ../quds_office_editor
flutter test test/word_zotero_format_test.dart test/word_zotero_dialog_test.dart test/word_zotero_controller_test.dart
cd ../..
```

Run the repository analyzers/format check on the changed sources as well.
For host acceptance, build a native Quds Studio or CrispCloud application, then
use an unsynced Zotero library with the local API enabled. Exercise insertion,
individual preview, basic refresh, bibliography and reference export; save and
reopen the DOCX. Check that a different database with a colliding item key
refuses refresh/export and leaves the document unchanged. Check source
switching, a delayed response after caret/document changes, and an older Zotero
client without the database header. Native Word/Zotero refresh acceptance
remains outstanding.

The current evidence is under
[validation/zotero-local-identity-20261115](validation/zotero-local-identity-20261115/).
The following older results retain their original source hashes and do not
count as current test passes.

## Earlier desktop continuation: historical results

The new desktop API work is saved at Quds code commit
`1cc4d251ebeb3e0cce205805e9183396da0c0df4` and CrispCloud code commit
`3c4cd0e24ab36f4fd88363cbc8521455bda811c6`. Subsequent audit/documentation or
source-pin commits can retain these exact tested source hashes.

| Fresh check | Result | Scope |
| --- | ---: | --- |
| Complete canonical Zotero client test file | 34 passed | 19 existing and 15 desktop protocol/identity regressions |
| Actual production CrispCloud HTTP boundary | 16 passed | 8 existing and 8 new transport tests, using original test-group/helpers |
| Focused Dart analysis with `--fatal-infos` | Clean | Client/models, pure host transport and the two focused test files |
| Changed Flutter/Studio Dart parsing | Formatter succeeded | Syntax only; not Flutter type analysis or widget execution |

**50 focused tests ran in this continuation.** Its source snapshots are
byte-identical to the production client/models/test and new pure transport
file. The host harness retains the transport tests verbatim and substitutes
`package:test` imports for Flutter imports; it does not substitute production
implementations or dependency stubs.

The runtime was official Dart 3.13.7, with genuine Pub resolution (`test` 1.33.0,
`http` 1.6.0). The workspace was nearly full and full repository clones failed.
An official SDK subset enabled genuine frontend compilation, VM execution with
assertions and static analysis. Exact installed-file hashes, CRC32 checks,
commands, manifests/lockfiles, original logs and reproduction scripts are under
[validation/zotero-desktop-20261115](validation/zotero-desktop-20261115/), starting
with [SETUP.md](validation/zotero-desktop-20261115/SETUP.md) and the
[validation receipt](validation/zotero-desktop-20261115/validation-receipt.json).
GitHub saves used content-addressed trees and expected-head ref updates.

New shared dialog and CSL import regressions are committed, including local
credential isolation, numeric/unsynced/offline identities, source switching and
a 320 × 640 desktop connection/error case. These Flutter cases **were not run**
in this continuation. Full native builds, the complete application/provider
graph, other host credential/controller/ribbon cases, live Zotero desktop and
private-account connectivity, OS keychain acceptance, and native Word/Zotero
refresh acceptance remain unverified. The earlier counts below are historical
results for their recorded sources, not fresh qualification of the new UI.

No GitHub Actions were awaited. Checkpoints carry `[skip ci]`.

## Earlier Web API increment: historical results

The following evidence belongs to the earlier implementation and is retained
with its original source identity and limits.

The implementation was qualified at Quds commit
`9da9c638bfe3bf932a70b2268dc16ef783fc009a`, which includes canonical main
`c210315bee537776b556ae9885e907483b6df7bd` through PR #39. Later documentation
commits do not change the tested implementation. The receipt records source
hashes so this qualification can be checked independently of branch movement.

### Results

| Check | Result | Scope |
| --- | --- | --- |
| Pure Dart engine/client/field regression cohort | 66 passed | API protocol, Zotero fields, existing inline fields, cross-paragraph fields and bibliography preservation |
| Shared Flutter suite | 43 passed | 11 controller, 24 formatter and 8 dialog tests |
| ODS reader regression after latest-main integration | 78 passed | Separate integration check for the file involved in CrispCloud's vendor merge |
| Targeted analyzer | Clean with `--fatal-infos` | New/touched Zotero implementation and test surfaces listed in the receipt |

CrispCloud independently passed 15 host service/ribbon tests against this exact
shared source. Across both repositories that is **124 focused Office/Zotero
tests plus 78 ODS integration regressions**. These counts do not represent a
full workspace, full spreadsheet suite, native application build, or desktop
Zotero acceptance run.

### Evidence and reproduction

The source hashes, exact commands, dependency setup, resolved manifests and
lockfiles, and final logs are retained under
[`validation/zotero-20261115`](validation/zotero-20261115/). The
[branch/PR audit](validation/zotero-20261115/branch-audit.json) records the
reviewed ancestry, patch-equivalent squash heads, and concurrent distinct work.

The runtime was official **Flutter 3.47.8 / Dart 3.13.7** on Linux. The SDK
archive was SHA-256 verified. Tests compiled unchanged canonical `lib` and
`test` sources through scratch package symlinks with a genuine Pub-resolved
dependency graph. Workspace-only resolution declarations were adjusted in the
scratch manifests; canonical dependency manifests and lockfiles were not
relaxed for these checks. Analysis used that resolved graph. This setup avoids
claiming that unrelated native/plugin dependencies or the entire workspace
were built in this environment.

The commands and setup note in the evidence directory describe the actual
qualified harness. Run them with the recorded Flutter SDK after restoring the
package paths for your checkout. The engine cohort comprises:

- `test/zotero_client_test.dart`
- `test/word_zotero_test.dart`
- `test/word_field_span_test.dart`
- `test/inline_field_fidelity_test.dart`
- `test/word_bibliography_fidelity_test.dart`

The shared Flutter cohort comprises:

- `test/word_zotero_controller_test.dart`
- `test/word_zotero_format_test.dart`
- `test/word_zotero_dialog_test.dart`

`test/ods_sheet_reader_test.dart` was run separately after incorporating current
main. Its 78 tests are kept separate from the feature cohort.

### Important assertions

The tests cover preservation of unknown native-field JSON, cached text,
embedded CSL snapshots, and imported Zotero preferences. They exercise guarded
field updates/unlinking, story ownership, undo/redo, dirty/save revisions,
atomic refresh and rollback, rich/locked/nested/cross-paragraph refusal, and
tracked-revision guards.

The actual dialog tests exercise offline import and insertion, cancellation,
search/pagination through the transport boundary, stale document/caret
refusal, and the complete **320 × 640** import/composer flow. Unchecking
Remember removes the stored key without requiring Connect. Saved DOCX ZIP
entries contain no API key. Imported bibliography additions, omissions and
custom entries remain unchanged when updating would lose them.

The Web API contract was also checked against Zotero's public sample library:
CSL export envelopes, inline CSL snapshots, source identity, bibliography
responses and CORS/pagination headers. Automated tests use deterministic
responses and do not require a private account or embed real credentials.

### Boundaries

No GitHub Actions jobs were awaited or used as evidence; remote checkpoints
carry `[skip ci]`. The implementation does not supply a full document-wide CSL
processor, Zotero's desktop HTTP citing transaction adapter, or active ODT
citation transfer. Native Microsoft Word/Zotero refresh acceptance and a full
native CrispCloud application build remain unverified. The feature's supported
formatting and preservation boundaries are described in
[`zotero-support.md`](zotero-support.md).
