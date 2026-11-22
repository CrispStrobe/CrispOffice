# Zotero converter interoperability — 22 November 2026

## Outcome and scope

This increment closes two reproducible gaps from the previous research-note
formatting work: retained LibreOffice DOCX files kept their citation data but
could not be edited natively, and the matching ODT files could not reopen in
the native reader. The exact retained body, footnote and table-cell cases now
have native editing and persistence regressions. Final local qualification
passed 4,694 visible tests across 130 distinct suites, with no failures or skips.
Strict analysis and formatting checks also pass for all 46 changed Dart files.
The exact source transition, counts and evidence are recorded below.

This is one bounded step toward the
[Word/LibreOffice parity roadmap](../../roadmaps/zotero/word-processor-parity.md).
It does not establish unrestricted converter compatibility or installed Zotero,
Microsoft Word, LibreOffice, or historical OpenOffice plugin acceptance.

## Implementation

### DOCX fields

LibreOffice writes ordinary character formatting on field instruction,
separator and end runs, and can add empty formatted runs before the separator.
The native classifier now admits a limited set of direct font, bold/italic,
capitalization, direction, RGB/automatic color, size, kerning and language
properties. Identical repeated properties are preserved; conflicting values,
style inheritance, hidden text, foreign markup and unknown properties remain
opaque. One complete XML root, bounded length/depth, supported attributes and
complete field structure are required before editing.

Citation code/cache updates, rich results, metadata-only updates and
multi-paragraph bibliography changes retain the admitted envelope's order and
properties. Empty code runs participate in exclusive ownership and stale-handle
checks. Native unlink removes the field envelope while keeping visible content;
delete remains a different operation.

Formatting revisions remain in the existing revision model. Original revision
markup on instruction/marker runs stays opaque. A copied provenance marker on
imported empty ordinary runs keeps paragraph-only typing/replacement guards
consistent with native Zotero guards after revision extraction and style
resolution. Accept/reject and undo retain their revision semantics. Existing
ambiguous or incomplete revision persistence refusals remain unchanged; this
work does not claim that every revision-bearing field can be saved.

### ODT input

The reader accepts the exact inert heading declaration observed in the retained
files: explicit empty numbering, an optional matching single-level `%N%`
placeholder, and either no positioning child or the exact empty label-alignment
shape with `label-followed-by="nothing"`. Numbered or multi-level outlines,
visible affixes, margins, tabs, other positioning and foreign structure remain
unsupported.

The character-style reader also accepts `loext:char-shading-value="0"` only
when the same declaration supplies an explicit supported background color or
transparent reset. RGB highlights and transparent overrides persist. Nonzero
patterns and a shading-only declaration remain unsupported. The possible
inheritance interaction of a shading-only declaration is an inference from
LibreOffice's compound background representation, not converter-tested behavior.

### Editor transactions

The retained converter files exercise controlled native Refresh from original
field contexts. Changes remain detached until application, stale completion
refuses after a fresh user edit, and one undo/redo restores the complete native
document and writing selection. Assertions cover active payloads, preferences,
note/table ownership, citation order, paragraph direction/alignment/indents,
headings, unrelated text and colors. These checks are separate from an installed
Zotero process driving the same protocol.

## Fixture provenance and coverage

The 21 fixture files are unchanged members of the previous converter archive:

- Source checkpoint: `b91fba039e123d3db767bc5178de59922a163e74`.
- Archive: `docs/validation/zotero-note-formatting-20261122/evidence/converter-after-fix.tar.xz`.
- Archive SHA-256: `5892777fc9ce6d25378b7abcc0a8504db0e44ea639e401c95fb9299e14986578`.
- Converter recorded by that work: LibreOfficeDev `26.8.0.0.alpha0`, build
  `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`.

The [fixture manifest](../../../packages/quds_office_engine/test/fixtures/zotero/converter/manifest.json)
records original archive member names, lengths and hashes. The original expected
snapshots are reused, including citation editability, active metadata and story
ownership. Numeric geometry comparison allows 0.02 pt for format precision;
this is not a claim of identical pagination or complete typography fidelity.

Both converter cycles are covered for body, footnote and table-cell DOCX and
ODT files. The native engine checks reopen, citation/cache updates, rich Refresh,
unlink/delete and repeated supported saves. Editor transaction checks use the
second converter cycle across all six format/story combinations. DOCX inputs
retain editability through native DOCX saves; ODT inputs pass native DOCX and
editable ODT save/reopen routes. The converted DOCX table-cell-to-ODT route still
encounters the existing visible-table-border refusal, which remains an explicit
negative expectation. No new LibreOffice conversion process ran in this turn.

## Intake and preservation

Initial main was `659b81462224a40f50975cfbfca39f636538b836`. The initial intake
fetched all 380 PR heads and checked all 43 fork branches, four canonical
upstream branches, and the 100 most recently updated PR heads and merge commits.
No recent PR was open. Two outstanding fork tips were integrated before Zotero
implementation:

- `5949a298444cec06632a28858c75670541a914a9`: Word Variant substring and named selectors.
- `622d9fda2a6564638af153de887adea922bc26f8`: connected Mail account navigation.

The second bounded intake checked 46 fork branches, four upstream branches and
100 recent PRs. It incorporated Word PR #381's main merge and the newer Word
Split, Mail account-store and Mail recovery work. All five additional heads are
ancestors of `373b7fe9bcb9c282fb6fe0bfbc7832a87faf2baa`; that ancestry is retained
by the integration checkpoint. See [initial-intake.json](initial-intake.json)
and [late-intake.json](late-intake.json) for captured refs and ancestry results.

Remote checkpoints on `codex/zotero-converter-parity-20261122` preserve progress:

| Checkpoint | Purpose |
| --- | --- |
| `550abcef192899461f0350e4731d37f45b8f6433` | Initial intake histories and acceptance plan |
| `90cce1f7711111e92f6d01708539bfaa56b4a08d` | Inert ODT outlines and original fixtures |
| `2d19bb8daf76d8305e47f136c92060b5cd5da019` | Exact paired clear shading and native ODT Refresh checks |
| `58011672bf8a3bec22ef5766c7416789203992ad` | In-progress DOCX envelope implementation and regressions |
| `8f2e943bf5aa1dd157e72f7ec47d0f7c2ccd5dd4` | Late Word/Mail ancestry, editor transactions and support contract |
| `81e9da16f9672530d4b39e9cf6cfec979af12830` | Reviewed Zotero guards, incoming Mail race correction and frozen functional-test source |
| `307b1aa8965c9e8a9338bee289a6dac5055b4bff` | Sole formatter normalization; final static-check source |

These are ordinary forward branch updates with expected-head checks. Source
ancestry and candidate tree equality are checked after remote publication.
GitHub Actions are not awaited, and no workflows or repository protections are
modified. The final publication uses an ordinary merge into remote main.

## Local validation and reproduction

The pinned runtime is Flutter `3.47.8` / Dart `3.13.7`. The official SDK archive
and all downloaded Pub archives were hash-verified. Workspace dependency
resolution used `--offline --enforce-lockfile`; the tracked manifests and
lockfile remain unchanged. The final runner records commands, source commits,
raw reporters, distinct visible cases and before/after hashes of 3,826 selected
materialized source, fixture, manifest and package-configuration inputs. The
selection covers the extensions listed in the runner; it is not a complete
compiled-input closure. Source commits and verified runtime/dependency archives
provide the additional provenance.

Run `run_checks.py` with the pinned SDK and locked dependencies active:

```sh
python3 docs/validation/zotero-converter-parity-20261122/run_checks.py --cohort engine --output /absolute/evidence/path
python3 docs/validation/zotero-converter-parity-20261122/run_checks.py --cohort editor --output /absolute/evidence/path
python3 docs/validation/zotero-converter-parity-20261122/run_checks.py --cohort studio --output /absolute/evidence/path
python3 docs/validation/zotero-converter-parity-20261122/run_checks.py --cohort incoming-word --output /absolute/evidence/path
python3 docs/validation/zotero-converter-parity-20261122/run_checks.py --cohort incoming-mail --output /absolute/evidence/path
python3 docs/validation/zotero-converter-parity-20261122/run_checks.py --cohort incoming-store --output /absolute/evidence/path
```

The store cohort may use `--sqlite-library /absolute/path/to/libsqlite3.so` for
a command-local preload of real installed SQLite; the receipt records its hash.
No fake database is substituted. Acceptance requires successful exit/reporting,
positive visible passes, no failures/skips/errors/unfinished cases, empty stderr
and unchanged captured inputs. This is focused local qualification, not the
full repository suite or a GitHub Actions result.

### Accepted results

| Cohort | Suites | Visible passes | Failures / skips |
| --- | ---: | ---: | ---: |
| Zotero and preservation engine | 66 | 2,013 | 0 / 0 |
| Editor and native transactions | 29 | 643 | 0 / 0 |
| Studio transport, open/export and shortcuts | 4 | 48 | 0 / 0 |
| Incoming Word and shared VBA regressions | 25 | 1,836 | 0 / 0 |
| Incoming Mail navigation | 5 | 133 | 0 / 0 |
| Real SQLite selected-record transactions | 1 | 21 | 0 / 0 |
| **Distinct final union** | **130** | **4,694** | **0 / 0** |

All six accepted functional cohorts ran against
`81e9da16f9672530d4b39e9cf6cfec979af12830` with identical captured input maps
before and after each run. Each ended normally with exit zero, one successful
reporter completion, no error/unfinished records and empty stderr. Hidden loader
records, earlier development runs and repeat attempts are excluded from these
counts.

The subsequent pinned Dart formatter wrapped one constructor call in the
incoming Mail navigation file and added an optional trailing comma. The before
and after files have identical canonical syntax trees and no parser diagnostics;
the original patch and reproducible proof are retained. No other program source
changed after the functional runs. Final strict analysis, format and diff checks
ran on `307b1aa8965c9e8a9338bee289a6dac5055b4bff` and passed. SDK pins, tracked
package manifests and lockfiles are unchanged from the intake baseline.

An initial highly concurrent attempt produced a compiler exit and a timed-out
editor opening test. The affected root-owned processes were interrupted; the
same functional source passed when the Flutter cohorts ran sequentially. Their
raw failures and startup-lock diagnostics remain in the evidence and are not
accepted results. The first completed static run's formatting failure is also
retained. No product assertion or timeout was relaxed to obtain acceptance.

See [qualification.json](qualification.json) for source/tree identities, exact
counts, runtime provenance, source-normalization proof and artifact hashes. The
[local evidence archive](local-evidence.tar.xz) contains raw reporters, cases,
commands, captured input maps, static logs, initial and late incoming bundles,
ODT/DOCX development failures and independent fixture/guard review. Its
[evidence index](evidence-index.json) hashes every member.

- Archive bytes: 609,396; members: 136.
- Archive SHA-256: `bab4eeacc34f18dc3e3622c1b817b6f853e170434f385553808ebabecad1df72`.
- Root lockfile SHA-256: `2231cacd6ab548da8f0d94020201a29f07f54a20c1682c0e8ae0079967b720eb`.

### Incoming integration corrections

The initial Mail regression failures exposed fixture/event-loop mismatches:
reconnect fixtures now implement the production catalog capability, asynchronous
stream cancellation receives a real event-loop turn, and invalid stored port
forms reach the route validator without test-helper normalization. The late
incoming route contract requires explicit IMAP socket ports; its positive
fixtures now follow that contract while invalid/noncanonical cases remain.

The late Mail branch also introduced an atomic selected-record API that neither
connection host called. An unconditional final write could recreate a shortcut
forgotten during reconnect, or overwrite a revised selected record. Native IMAP
and the shared EWS/Gmail/Graph host now refresh the selected snapshot atomically
before adopting the candidate draft owner. Eight deterministic removal/revision
regressions failed before this correction and pass afterward. Fresh connection
registration, legacy directory metadata, rejected-owner release and explicit
close/retry recovery remain covered. This correction is separate from the
Zotero feature increment but required a consistent combined main.


## Remaining parity work

1. Run installed Zotero and Microsoft Word/supported-release LibreOffice plugin
   workflows on identified application/OS/plugin versions, including edit,
   Refresh, style changes, bibliography, unlink and cross-processor transfer.
2. Extend ordinary visited/unvisited hyperlink-style and continued-list ODT
   support only with independent converter cases and preservation assertions.
3. Add separately modeled visible table borders and richer outline/shading
   semantics before expanding those import routes.

The implementation keeps the original source recoverable when a structure falls
outside the supported contract. The broader roadmap remains the authoritative
record of capabilities already delivered and acceptance still outstanding.
