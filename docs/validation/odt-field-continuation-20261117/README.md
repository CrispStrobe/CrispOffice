# ODT field continuation and publication recovery — 17 November 2026

**Published product source:** [`5afff4b86523250c93d949eb6c010e49d9fabd82`](https://github.com/CrispStrobe/quds_office_suite/commit/5afff4b86523250c93d949eb6c010e49d9fabd82).
**Qualification baseline:** `e3a38789359adaa33b2da1345c952fa1c2d8aebb`.
**Branch:** `codex/odt-field-continuation-20261117`.

This continuation repairs two remaining ways that page-field caches could be
lost between DOCX import and ODT export. The published source has exactly the
same tree as the source reviewed and approved before the execution workspace
was reset. This report preserves the source recovery and fresh local
qualification performed for publication.

## Recovery and source identity

The preceding handoff's field amendment had already been published at product
revision `898c4c07` and sealed at `867df7f2`.
[PR #114 was deliberately closed](https://github.com/CrispStrobe/quds_office_suite/pull/114#issuecomment-6958249784)
after its work was reconciled through
[PR #129](https://github.com/CrispStrobe/quds_office_suite/pull/129), which also
removed AOT/RML. This continuation retains that deliberate removal and starts
from the later qualification baseline above.

The additional field repair was initially saved locally as `7147ae607`, with a
documentation/evidence commit `1064fc333`. Automatic approval review blocked
the first push. After the user explicitly approved publication, the execution
workspace had reset: the local clone, unpublished documentation commit and
raw logs were no longer available.

The four approved source/test files were recovered byte-for-byte from the
recorded patches and checked against their recorded hashes. Their tree, parent,
message and original author/committer data reproduced the exact original source
commit hash. The preserved [original commit payload](recovered-original-source.commit)
and [source-recovery record](source-recovery.json) make this independently
checkable. No lost test log or documentation commit was reconstructed.

Git CLI authentication was unavailable, so the recovered source tree was
published through the GitHub connector with fresh commit metadata. The
published commit `5afff4b8` and recovered original source `7147ae607` both point
to tree **`3080e51ec487a97c08696d119dbef97a442a2e67`**. This changes publication
metadata, not product behavior.

The [recovery audit](recovery-audit.json) verifies that identity and all
**205 members** of the already-published historical archives: 167 preceding
recovery members and 38 field-amendment members. Both archives retain their
original bytes, indexes and hashes. That archive audit is distinct from the
fresh execution receipts below.

## Defects and bounded repairs

### Paragraph PAGE instructions

The ODT paragraph path previously recognized a PAGE instruction by its field
kind alone. It could replace a cached Roman numeral, padded number or another
unsupported format with an ordinary live page number, including when the
compatibility `pageNumberField` flag was set.

Paragraph detection now shares the bounded grammar used by inline PAGE/NUMPAGES
conversion. It accepts `PAGE`, optionally with `\* MERGEFORMAT`, ignoring case
and surrounding whitespace. An explicit unsupported instruction retains its
ordinary cached runs, formatting and links. Tests cover styled linked header
and footer caches, following text, unchanged source runs and supported live
PAGE controls. Paragraph-level NUMPAGES conversion is not added.

### Imported field packets

DOCX import could collapse a whole-paragraph field before the ODT writer saw
its boundary metadata. PAGE collapse could erase a numeric cache even when
the original field was locked or used an unsupported formatting switch. Missing,
duplicate or misordered separators could also enter that compatibility model.

The importer now requires instruction content before exactly one separator and
no visible content before that separator. Boundary metadata must fit the
supported empty Word field-boundary form. Locked fields, unsupported attributes
or child data, formatted instruction runs and unsupported metadata retain their
boundary packets and visible caches. An exact PAGE-instruction check runs
before numeric-cache suppression. Complete plain PAGE and PAGE/MERGEFORMAT
remain live; ordinary complete DATE fields keep the established paragraph model.
The existing early TOC path and Zotero handling remain intact.

Direct DOCX-to-ODT regressions check the imported cache, exported visible
content, following paragraphs and cached text on DOCX save. Most supported
cache-preservation cases also exercise a DOCX save/reopen cycle. Deliberately
malformed duplicate-separator, misordered, pre-separator-text and unterminated
packets are not claimed to retain their malformed structure through a second
DOCX import.

## Fresh local qualification

| Check | Result | Receipt |
| --- | --- | --- |
| Both final regression files with original product files | **24 assertion failures; 31 passing controls** | [recovered-baseline](evidence/recovered-baseline.json) |
| Affected ODT and Word field/TOC/revision/bookmark cohort, Dart VM | **620 passed across 40 files** | [recovered-vm](evidence/recovered-vm.json) |
| Portable field, column, section, TOC and revision cohort, JavaScript/Node | **165 passed across 9 files** | [recovered-node](evidence/recovered-node.json) |
| Strict analysis of the two changed source files and two changed test files | **No issues** | [recovered-analysis](evidence/recovered-analysis.json) |

The negative control uses the final two regression files with the original
writer and deserializer temporarily restored from `e3a38789`. Its receipt's
`head` names the published commit because HEAD itself was not moved; the
recorded before/after source hashes identify the actual original files used.
The baseline has 55 tests: 34 paragraph and 21 imported-field cases. The same
test bytes participate in the positive runs.

The [fresh verification](verification.json) recounts raw test events, compares
the accepted before/after inputs and binds positive source hashes to the
published product. It identifies the focused 78-test subset within the broader
cohorts: 34 paragraph, 21 imported-field and 23 existing inline-field cases.
The test groups overlap and must not be added as unique tests. The
[logging harness](run_logged.py) preserves actual commands, compressed raw
stdout/stderr and source manifests; the [evidence index](evidence-index.json)
records delivered file sizes and hashes.

These are fresh execution records. The prior turn's unpublished raw logs,
including its preliminary test-helper and command-line attempts, were lost.
Their former reported results are not presented as retained artifacts in this
publication.

## Reconstructed runtime

The [runtime record](runtime.json) identifies Dart **3.13.7** and Node
**24.22.1**. Their executable hashes match the binaries used before the reset.
A minimal engine/parser workspace resolves the unchanged package declarations
without requiring the Flutter application workspace. The generated package
configuration targets the actual qualified engine and legacy parser source.
Tracked project pubspecs and analysis settings are unchanged.

The [test workspace manifest](test-workspace-pubspec.yaml),
[resolved lock](resolved-pubspec.lock) and [package configuration](package-config.json)
record this environment. The recovered test, analyzer and related dependency
versions are pinned in the runtime record. Direct test-runner commands avoid
an unrelated Flutter workspace dependency resolution. The execution receipts
retain the commands and configuration hashes actually used.

## Scope and documentation

The product/test delta contains exactly four paths:

- `packages/quds_office_engine/lib/src/word/serial/odt_document_writer.dart`
- `packages/quds_office_engine/lib/src/word/serial/word_deserializer.dart`
- `packages/quds_office_engine/test/odt_page_field_fidelity_test.dart`
- `packages/quds_office_engine/test/odt_imported_field_fidelity_test.dart`

The recovery audit verifies unchanged proofing, GECToR, Harper, editor, Studio,
tooling and project-configuration source objects against the qualification
baseline. AOT remains absent. The
[ODF capability guide](../../odf-export-fidelity.md) describes existing columns,
explicit first/even stories and bounded inline/paragraph field conversion;
the obsolete historical AOT link now points to an immutable source revision.

Unsupported field forms retain their cached content. General native Word field
conversion and complete reconstruction of Word header activation/inheritance
remain outside this work. Fresh checks cover local Dart VM, compiled JavaScript
and source analysis. They introduce no new language-quality, performance,
target-device or external Office-consumer rendering claim.
