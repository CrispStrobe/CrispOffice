# Zotero local validation — 15 November 2026

The implementation was qualified at Quds commit
`9da9c638bfe3bf932a70b2268dc16ef783fc009a`, which includes canonical main
`c210315bee537776b556ae9885e907483b6df7bd` through PR #39. Later documentation
commits do not change the tested implementation. The receipt records source
hashes so this qualification can be checked independently of branch movement.

## Results

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

## Evidence and reproduction

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

## Important assertions

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

## Boundaries

No GitHub Actions jobs were awaited or used as evidence; remote checkpoints
carry `[skip ci]`. The implementation does not supply a full document-wide CSL
processor, Zotero's desktop HTTP citing transaction adapter, or active ODT
citation transfer. Native Microsoft Word/Zotero refresh acceptance and a full
native CrispCloud application build remain unverified. The feature's supported
formatting and preservation boundaries are described in
[`zotero-support.md`](zotero-support.md).
