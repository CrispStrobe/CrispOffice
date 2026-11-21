# Native ODT Zotero inventory: implementation and qualification

This continuation implements the read-only inventory prerequisite specified by
the [native ODT input contract](../../roadmaps/zotero/native-odt-input.md).
`OdfZotero.inspect` and its diagnostic CLI now recognize native citation
ReferenceMarks, bibliography TextSections and document preferences while
retaining their original data and structural ownership. They do not publish
an editable ODT document or start a Zotero session.

## Delivered behavior

- The public engine API inspects the actual ODT ZIP package, checks its MIME
  type, and reads namespace-qualified `content.xml`, optional `styles.xml` and
  optional `meta.xml` with explicit cumulative limits.
- Canonical Zotero names retain their complete native identity, logical field
  code and terminal random suffix. Existing bounded metadata codecs preserve
  supported unknown citation data. Legacy or malformed names remain findings.
- Every endpoint retains the package part, prefix-independent element path,
  story identity and structural owner chain. Endpoints inside a paragraph also
  retain its identity and UTF-16 offset; section boundary endpoints can have
  null paragraph coordinates. Bibliography paragraph ranges retain their own
  exact paragraph coordinates and cached visible text.
- Body, note and cell owners remain distinct. Duplicate, missing, crossed,
  nested, cross-story, repeated, protected, linked and unsupported ownership
  cannot become an eligible field by matching visible text.
- Numbered `ZOTERO_PREF_*` and `CSL_PREF_*` properties retain the original
  preference string, chunks and unrelated metadata. Numeric ordering, empty
  cleanup chunks and ODF's default string type are covered. Conflicting or
  malformed families are reported explicitly.
- The reader bounds archive/XML size, elements, depth, endpoints, paragraphs,
  field names, decoded/cached text, preference collection, range work and range
  objects. Empty or nested sections cannot evade the work/allocation limits.
  Exhaustion rejects the inspection instead of returning partial success.

`isValid` concerns canonical name/metadata validity. `isImportCandidate` also
requires an unambiguous supported physical range. Neither property establishes
rich ODF formatting support or active editing. The JSON result explicitly says
`editable: false`. Ordinary ODT export and normal Word/HTTP Zotero callbacks
retain their existing behavior.

From `packages/quds_office_engine`:

```bash
dart run tool/zotero/odt_inventory.dart /path/to/document.odt
```

The CLI reads the input and emits the inventory as JSON. A malformed package
returns exit code 65 with no success JSON. The input bytes remain unchanged.

## Remote intake and preservation

The initial intake captured main at
`f50c4f23392ccb0ac9f486541ffae6a65a691b99`, all 24 advertised fork branches,
the 100 most recently updated pull requests, and four upstream heads.
Twenty-three fork heads and all upstream heads were already ancestors. All
100 captured PRs were merged; historical nonancestor PR heads have their
inherited equivalence dispositions in [intake-initial.json](intake-initial.json).

The outstanding Word text branch at
`2714483aafe059065b00dac23032023f9ddf7aac` was merged while preserving current
main's Mail UI/localization and both independent Boolean test cohorts. The
incoming Word source, fixtures, example and tests retain their original
ancestry. Main subsequently advanced to
`64ebfc1bbc1daf9d3e9fc8a03ff8bf95f9973e04`; that reconciliation includes the
two Boolean cohorts in separate files and provenance-only fixture corrections.
The final engine gate ran after this incoming main was integrated.

The late intake also captured the new Mail cache branch at
`833ddd05ff8cdecb202d6db414e66b91f2332544`. Its nine-path additive cache-search
change was independently reviewed and integrated without conflicts. The
recorded cutoff is bounded; it is not a claim about future active branch heads.
[intake-final.json](intake-final.json) records the final intake and disposition.

A subsequent [discovery snapshot](premerge-discovery.json) found main unchanged
and three concurrent heads created or advanced after those cutoffs: Touch ID
PR #302 (`38b0dae0`), wrap-chrome performance (`d76c705b`) and further Mail cache
work (`4ecf9850`). Those later heads remain on their original remote branches
for their own review and qualification. They are not counted as integrated by
this bounded intake, and no branch was deleted or rewritten.

All checkpoints were saved on
[`codex/zotero-odt-inventory-20261121`](https://github.com/CrispStrobe/quds_office_suite/tree/codex/zotero-odt-inventory-20261121)
using non-forced updates with an expected previous head. The branch is retained.

| Checkpoint | Purpose |
| --- | --- |
| [`465ded3282`](https://github.com/CrispStrobe/quds_office_suite/commit/465ded3282ce03c636a9f0c17547fa5b94634de4) | Reconcile the initially outstanding Word branch and preserve both test cohorts. |
| [`0ad43b78ef`](https://github.com/CrispStrobe/quds_office_suite/commit/0ad43b78ef43d26bc2c97b8b75ad58ca20914617) | Preserve the first executable native ODT inventory and regressions. |
| [`60e212b0d6`](https://github.com/CrispStrobe/quds_office_suite/commit/60e212b0d62f55054a1e77e5b8721564656eaf57) | Preserve reviewed ownership/resource fixes, portable acceptance driver and documentation. |
| [`aa72fa6b52`](https://github.com/CrispStrobe/quds_office_suite/commit/aa72fa6b52c58168d943181e1201ab5ef8ef321b) | Reconcile updated main while retaining the Zotero implementation. |
| [`ce4eca72da`](https://github.com/CrispStrobe/quds_office_suite/commit/ce4eca72da1698f1b1ce9d2d494f345dbad32827) | Preserve the frozen incoming Mail cache branch and its ancestry. |

The commit containing this record adds the final evidence and a documentation
unit correction. Its source manifest binds the executed checks to the exact
qualified implementation; evidence-only changes do not alter that source.

## Executed local qualification

Runtime: repository-pinned Flutter **3.47.8**
(`737ba8f885dc774b53b442759999a312c9461e4e`), Dart **3.13.7**, locked workspace
dependencies. Dependency resolution used `flutter pub get --enforce-lockfile`;
`pubspec.yaml` and `pubspec.lock` were unchanged. GitHub Actions were neither
queried nor awaited.

| Gate | Observed result |
| --- | --- |
| Final engine regression: 98 selected Zotero, ODF/ODT and incoming Word text test files | **2,297 passed; 0 failed; 0 skipped.** All 627 captured inputs unchanged before/after. |
| New native ODT inventory cases, included in that final total | **149:** 38 mark/section cases, 60 preferences, 38 ownership/adversarial cases, 13 resource/unsupported-owner cases. |
| Final aggregate static gate: public entry point, three production files, four test files and two tools | `dart analyze --fatal-infos`: no issues. Formatting: 10 files, zero changes. All ten inputs unchanged. |
| Native ODT portable acceptance | Dart VM and compiled JavaScript/Node receipts byte-identical. Four fields, seven paragraphs and five preference chunks; Unicode, ownership and malformed/budget guards passed. |
| Read-only diagnostic CLI | Valid fixture exit 0 and exact API inventory; malformed fixture exit 65 and no success JSON. Both input files unchanged. |
| Reconciled Mail Boolean cohorts | **73 passed:** 26 original cases and 47 independent regression cases; no failures or skips. |
| Frozen incoming Mail cache repository and related local mailbox/sync suites | **110 passed** across five files; no failures or skips. |
| Frozen incoming Mail host cached-search, mailbox-store and mailbox-session suites | **58 passed** across three files; no failures or skips. Scoped store/host analysis clean; six formatted files unchanged. All 217 captured inputs unchanged. |

The 149 new cases are a subset of 2,297, not an additional total. Focused
development runs and the initial 336-case Word/Mail baseline overlap these
checks. Their original receipts are retained without inflating the final count.

The first broad run had 2,284 passing cases, but production resource fixes were
being completed during its source-capture interval. That run is retained under
`odt-validation/pre-resource-run/` as development evidence. The final 2,297-case
run includes all 13 new resource cases and has unchanged input manifests.

The original Flutter host-test startup was rejected by automatic approval
review citing possible cloud metadata access; it produced no qualifying host
test result. Local SDK review identified Flutter's pre-run Azure bot detector
as a matching request path. The rejected process was not resumed. A fresh host
gate ran in a new user/network namespace with only loopback and no external
route, with `BOT=true`, `CI=true`, `FLUTTER_SUPPRESS_ANALYTICS=true`,
`--no-version-check` and `--no-pub`. Namespace evidence was captured before and
after. This removed the offending startup path and confined the entire check.
The saved blocked-execution record remains separate from the successful
isolated results. The incoming Mail code independently reviewed here adds
local database behavior, with no network or credential-acquisition changes.

## Evidence and reproduction

- [results.json](results.json): machine-readable final engine counts, per-suite
  inventory counts, portable/CLI receipts, runtime and static results.
- [qualified-source-sha256.json](qualified-source-sha256.json): the engine
  regression inputs and new public API/test/tool hashes.
- [local-validation.zip](local-validation.zip): raw logs, exact commands,
  before/after manifests, acceptance receipts, synthetic native/malformed ODT
  fixtures and local runner scripts. Generated JavaScript files are omitted;
  compile commands and captured compiler, VM and Node stdout receipts and
  hashes are retained.
- [evidence-sha256.json](evidence-sha256.json): archive and member hashes. The
  archive was reopened, CRC-checked and each extracted member hash verified.
- [intake-initial.json](intake-initial.json) and
  [intake-final.json](intake-final.json): captured refs, incoming-history
  decisions and relevant qualification limits.
- [premerge-discovery.json](premerge-discovery.json): subsequent concurrent work
  observed after the frozen integration cutoff, with explicit dispositions.

To run the four focused parser suites from `packages/quds_office_engine`:

```bash
dart test \
  test/odf_zotero_reference_marks_test.dart \
  test/odf_zotero_preferences_test.dart \
  test/odf_zotero_ownership_test.dart \
  test/odf_zotero_resource_test.dart
```

The deterministic acceptance driver is
`tool/zotero/odt_inventory_acceptance.dart`. Run it with Dart, compile that same
file with `dart compile js -O1`, then run the emitted script using Node with
`globalThis.self = globalThis`. Compare the two complete stdout receipts.
The archived commands show the exact package configuration used here.

## Remaining parity work

The fixtures follow the pinned
[Zotero LibreOffice integration storage contract](https://github.com/zotero/zotero-libreoffice-integration/commit/0a31b434371eb21a1297c5bce8ca4978cb9ab425).
They are synthetic, not files captured from an installed Office/Zotero session.
No new live Zotero, Word, LibreOffice or legacy Apache OpenOffice acceptance is
claimed by these local results.

The next implementation is a bounded rich ODT-to-`WmlDocument` reader. It must
preserve paragraph/run formatting, notes, lists, tables and resource ownership
before converting inventory identities into active fields. Then qualify DOCX
save/reopen, citation editing, style conversion and bibliography refresh using
actual plugin-produced documents. Publish editable ODT loading only through
the existing detached staging, stale-document and single-transaction guards.

The earlier DOCX → ODT → DOCX continued-list converter finding remains open.
The [parity roadmap](../../roadmaps/zotero/word-processor-parity.md) retains
that finding and the other rendering, structural and installed-host gates.

## Subsequent Mail integration

The later Mail continuation preserved this complete record and its evidence,
and incorporated the Touch ID and typing-benchmark heads observed after the
Zotero cutoff above. Credential enrollment/cleanup and unlock error recovery
were corrected before publication. The combined Mail/credential source at
`62e9f1af15f2cb00ee67a339cdc6dea48d882aab` passed 178 focused Studio tests and
407 Mail core tests, with unchanged source and dependency fingerprints.

The [Mail continuation record](../mail-unified-cache-20261121/README.md)
records the later intake, corrections and final source bindings. Its
[independent ODT qualification](../mail-unified-cache-20261121/zotero-independent-qualification.md)
records a separate 149-case inventory run and VM/Node acceptance. Those
inventory cases overlap the engine counts above and are not additional unique
coverage. This appendix does not change the original record's captured cutoff
or recast inherited results as newly executed Mail tests.
