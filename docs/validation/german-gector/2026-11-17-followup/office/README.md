# Office integration regression evidence

## Accepted local result

The final Office cohort passes **693 substantive tests across 49 files**, with zero failures and zero skips. The selected files cover ODT/ODF export and extraction, bookmark behavior, ODS story import and the ODP writer. `broad.jsonl` is the raw Dart event stream; `broad-inputs.json` records the command, engine working directory, start/end times and SHA-256 of every engine library plus each selected test. Those inputs were unchanged throughout the accepted run. `analysis.log` records strict analysis with no issues.

The 68-case earlier focused pass overlaps this broad cohort and must not be added to it. Four format-switch fallback controls were added after that focused pass and are included in the accepted broad cohort.

## Preserved failed attempts

- The four-suite baseline on integration source `28dabf1015f394f9413224e3625a7addd13ecab3` had 17 successful and 21 unsuccessful substantive cases: 18 assertion failures and three errors. `failed-before.jsonl`, `failed-before-inputs.json` and `incoming_odt_document_writer.dart` retain the exact observations and source. Some expectations needed reconciliation as described below; the 21 are not all independent production defects.
- `intermediate-restoration.jsonl` retains the first narrow restoration against all newly recovered tests, including the conflicts between earlier native-empty-field and newer cached-field expectations.
- `broad-wrong-cwd.jsonl` and its input seal retain the broad launch from the repository root. Relative fixture paths require the engine package working directory; that launch produced 18 fixture errors plus the negative-gap expectation conflict. The accepted broad launch uses the engine directory and does not omit those tests.

## Production repair

The writer recovers the complete-packet scanner and source-boundary validation from commit `898c4c07`, adapts it to current hard-column splitting, and preserves first/even header variants from PR #133 and the story/header-media work from PR #132. Safe complete, balanced, nonnested PAGE/NUMPAGES/DATE/TIME/TITLE packets preserve their single cached run, styling, hyperlink and comment ownership. Only plain instructions or the reviewed MERGEFORMAT switch convert; formatting switches, malformed/locked/source-rich packets, nested/cross-paragraph packets, atomic results, multiple runs and significant whitespace retain the authored cached form. A complete packet with no cached run uses a private temporary run without changing the model. Empty generated fields count as content before a following column break.

Persistent field-result suppression is removed. Cross-paragraph field depth only prevents unsafe nested conversion, while independent stories reset that guard. It never suppresses visible cached runs.

Bookmark pairing uses complete, unambiguous pairs in the paragraphs the ODT writer actually emits. Ordinary cells remain in the body story; covered cells, frames, headers, footers, notes and comments own independent endpoint maps. The recovered malformed-ID name reservation from `07926acb` prevents a malformed duplicate start from lending its name to an otherwise valid ID pair. No source marker is mutated.

## Reconciled test contracts

All five previously absent independent test files from `07926acb` and `814f165c` were recovered. The three `07926acb` originals and their hashes are retained in `imported-originals/` and `imported-test-provenance.json`.

1. The historical complex-field suite expected native empty fields and a NUMPAGES fallback for styling/hyperlinks. The newer integrated inline-field suite expects cached text and native styling/hyperlinks. Final tests preserve cached display text inside native fields. Newer plain DATE/TIME/TITLE support is retained with strict packet and switch guards; the older unsupported-name loop now tests unsupported formatting switches rather than those newly supported plain names.
2. The native NUMPAGES wrapper restriction was traced to disagreement between validators. The official ODF prose permits page-count in spans/links with character data. The pinned official RNG accepts those exact inputs in Jing, while lxml/libxml2 rejects nested page-count variants. Tests now follow the standard and independent validator rather than encoding that lxml-specific result. All original observations are retained.
3. An older bookmark test assumed every TOC title was omitted. PR #127 now exports TOC title/entry caches. Its omission test explicitly supplies an empty title setting, and a companion test verifies a visible TOC title's bookmark range into following text.
4. A prior column test expected negative gaps to serialize. The selected newer incoming writer and its independent suite omit negative gaps. The earlier assertion now requires omission while retaining rounding, negative-zero normalization and source-model immutability assertions. The production negative-gap behavior is unchanged from incoming main.

## Independent schema comparison

`field-schema-probes.json` contains all 30 minimal input documents, schema SHA-256 and lxml observations, plus eight Jing comparisons. Lxml accepts 26/30 and rejects the four nested page-count variants; Jing accepts all eight representative comparisons, including those four. This is a bounded schema comparison, not yet a full final-document or desktop-consumer qualification.

The schema is the unchanged official `OpenDocument-v1.3-schema.rng`, SHA-256 `40bad03efdbb02825230d357da0aa6ac679934c5bf56c6281752c0c24d58e4e6`. Jing is version 20241231 from `https://repo.maven.apache.org/maven2/org/relaxng/jing/20241231/jing-20241231.jar`; its checksum is in the probe report. The binary is not included in this evidence archive.

Jing's default DTD-compatibility ID/IDREF checks reject unrelated constructs in the ODF schema before validating documents. The recorded `-i` invocation disables only those checks while retaining the complete RelaxNG content grammar. Both the initial rejection and the successful configured invocation are recorded.

Authoritative schema/prose sources:

- https://docs.oasis-open.org/office/OpenDocument/v1.3/os/schemas/OpenDocument-v1.3-schema.rng
- https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html (sections 6.1.7, 6.1.8 and 7.5.18.2)

## Reproduction

Activate the recovered runtime, run the exact `broad-inputs.json` command from its engine working directory, and compare raw test identities/results. For the first baseline, restore the saved incoming writer into an isolated checkout and run the four test files recorded in `failed-before-inputs.json` from the engine package.

The native field fixture hook is `ODT_FIELD_FIXTURE_DIRECTORY` on `test/odt_complex_field_fidelity_test.dart`. It can emit actual ODTs from the current implementation for independent schema/consumer follow-up. Existing tests and archive paths do not claim those follow-up results before execution.

No GitHub Actions, workflow, check-run or CI status endpoint was requested, dispatched, polled or awaited.
