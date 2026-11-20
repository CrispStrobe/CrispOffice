# Zotero research materials — 20 November 2026

**Qualified product source:** `f0122cb5bff5b6cf6a6f69f043545dabc2930791`, on
`codex/zotero-research-materials-20261120`,
[PR #223](https://github.com/CrispStrobe/quds_office_suite/pull/223).

**2,886 distinct local application tests passed across 135 files.**
All 55 changed Dart targets pass strict analysis and formatting.
The accepted runs have zero failed/skipped cases, error events, unfinished
tests, duplicate case identities, or layout/tap diagnostics. Exact suite
coverage and unchanged input fingerprints are required for every cohort.

The primary qualification ran **2,884 tests in 134 files**
at the product source above. A later merge of current main is qualified at
`d1b8f9be24f08b2e4de7292c8727eddbd77bbf55`:
every one of the 3,994 previously recorded source inputs
is byte-identical, and the only added source-inventory paths are a two-case
Word macro regression file and fixture `.gitattributes`. Those two new cases
pass separately, and fresh strict analysis/formatting covers all 55 final Dart
targets. [The publication audit](post-main/audit.json) records this distinction;
the totals do not imply that all 135 files existed at the earlier commit.

## User-facing Zotero capability

In **Library → Reference details → Notes and attachments…**, inspect the
connected reference's direct child notes and attachment metadata in pages of
25. Notes have bounded, inert plain-text previews and **Copy note text**.
Attachment details expose the supplied title, filename, MIME type, storage
mode and URL, with **Copy details**; an attachment's own note can also be
previewed and copied. The [usage guide](../../zotero-support.md#read-research-notes-and-inspect-attachments)
describes the complete workflow and its boundaries.

Browsing preserves reference selection, unfinished search/tag input, document
content and undo history, including read-only documents. Ordinary reference
details still use cached metadata; child requests are explicit. Failed pages
keep usable prior results and an explicit retry. A reported library-version
change while paging requires a reload from the first page. Closing a view or
changing its connection discards late results; copy actions check their
connection before dispatch.

The engine validates the entire child page: exact parent and library,
distinct valid keys, supported kinds, version consistency, typed optional
fields, Unicode, pagination and size limits. Each note is bounded to 1 MiB of
UTF-8 and a child response to 8 MiB. Desktop browsing requires the exact
database identity carried by the parent response, available with Zotero 10+;
headerless older snapshots explain why the action is unavailable.

The note preview is a separate bounded tokenizer. It preserves paragraph and
line boundaries, table-cell separation, list structure, preformatted whitespace,
scientific comparisons and Unicode. It decodes entities once, hides active or
embedded content, loads no resources and refuses malformed or excessive markup
per note. Derived list titles are bounded independently of the full copied
text. URLs stay selectable text; this increment does not download or launch
attachment files, inspect annotations, or write data to Zotero.

The **88 new Zotero regression cases** are included once in the totals:
40 engine child/provenance cases, 23 note-preview cases, 15 child-dialog cases,
and 10 full-workspace integration cases.

## Reconciled incoming work

The initial fork main was `a452efdadc9000c51a8e5e9ba2f16405d4979e2e`.
It already contained previous Zotero PR #218, VBA PR #219, macOS spaCy PR #220,
and the latest then-current native DOCX review changes. Initial reconciliation
covered 12 fork branches and all 220 PR heads before feature implementation.

The final bounded branch/open-PR intake was captured at
**20 November 2026, 05:33:26 Europe/Berlin (04:33:26 UTC)**. It includes
15 fork branch heads and 223 recorded PR heads, of which #223 is this work's
own PR and 222 belong to other work. Closed PR identities and the actual
upstream's four branches/four PR heads retain the earlier 04:19:16 UTC capture.
All captured work is included through ancestry or 14 retained, independently
verified historical equivalence proofs. The nine historical branch heads
reuse those explicit proofs; they are not silently discarded.

Recent original heads retained in the merge history include:

| Work | Captured head | Included behavior |
| --- | --- | --- |
| Main at the branch cutoff | `b5b32d247cd9ba9803b35175db8d60c8deeeac47` | Empty-run DOCX revision safeguard and its native acceptance records |
| PPTX integration | `9e647ae5cfbd494b51fe0928b57ed10c9a7a986a` | Inherited decorations, symbol/emoji fallback, arrows, numeric order and flipped connectors |
| VBA strings, PR #222 | `6b94e195ec4871d47c4ee0ffb81bcfe6ab8d7c74` | String intrinsics, conformance corpus, UTF-16 write guard, transactional examples and connector preservation |
| Mail attachments, PR #221 | `f832ed301760deab86d9d6096b88cbe546c3a2b8` | Immutable attachment drafts, bounded/cancellable reads, provider MIME submission and overlapping rendering repairs |

The final Mail head already contains the listed VBA and main heads. Its merge
retains both branches' rendering regressions and the new Zotero implementation.
Conflict resolutions preserve master-only visibility (`showMasterSp`), visible
layout decorations, explicitly resolved empty decoration lists, background
ownership, rich-run overrides, numeric text order through wrapping and blank
lines, and once-only PDF font fitting. Connector direction survives import,
save, edits, clipboard operations, morphs and complete slide duplication.
An identical moved ownership regression is retained once; distinct tests from
both sides remain.

[final-reconciliation.json](final-reconciliation.json) records every captured
head and disposition. [final-remote-snapshot.json](final-remote-snapshot.json)
records the inventory and precise capture bounds. Later remote-tracking head
changes are reported separately; the audit does not pretend they belonged to
the bounded capture. Publication also preserves later main
`fe076d22a1b25d27c34b861fa5b0b2a32833b33e`: the PR #222 merge, its qualification
records, two additional Word macro guard cases, and native-fixture line-ending
attributes. This adds no application code beyond the qualified product source.
The separate publication audit proves unchanged prior inputs and records the
added tests without rewriting captured identities.

## Accepted local validation

| Cohort | Passed | Files |
| --- | ---: | ---: |
| [engine-zotero](accepted-engine-zotero/receipt.json) — Zotero engine | 642 | 29 |
| [editor-zotero](accepted-editor-zotero/receipt.json) — Zotero editor | 632 | 43 |
| [engine-rendering](accepted-engine-rendering/receipt.json) — Rendering engine and PDF | 191 | 11 |
| [editor-rendering](accepted-editor-rendering/receipt.json) — Rendering editor | 101 | 9 |
| [engine-vba](accepted-engine-vba/receipt.json) — VBA and shared macros, genuine VM/CLI | 743 | 21 |
| [mail-host](accepted-mail-host/receipt.json) — Mail Studio host | 318 | 11 |
| [mail-mime](accepted-mail-mime/receipt.json) — Mail MIME/SMTP | 115 | 6 |
| [mail-transport](accepted-mail-transport/receipt.json) — Mail cloud/EWS transport | 113 | 2 |
| [engine-docx](accepted-engine-docx/receipt.json) — DOCX revision engine | 23 | 1 |
| [editor-docx](accepted-editor-docx/receipt.json) — DOCX review editor | 6 | 1 |
| [word-revision-guard](post-main/accepted-word-revision-guard/receipt.json) — Added main Word macro guards | 2 | 1 |
| **Distinct total** | **2,886** | **135** |

Each `accepted-<cohort>/` directory contains a receipt, compressed raw JSON event
stream and stderr, the exact source/dependency/runtime input inventory, and the
before/after comparison. The [summary](summary.json) lists all accepted receipts
and totals. The independent audit recounts the raw events, verifies artifact
hashes, exact suite coverage, distinct case identities and source bindings.
Loader and setup/teardown events are excluded from the test count, but failures
in those events still reject acceptance. Development runs and repeated passes
are not added to these totals.

The genuine cached Dart VM runs engine, VBA CLI, MIME and provider tests.
Flutter runs widget/controller tests with `--no-pub` and concurrency one.
VBA CLI subprocesses therefore launch the real Dart executable rather than
`flutter_tester`. Application test timeouts are recorded in each receipt.

The same **69-case VBA corpus** also runs on the genuine VM and compiled
JavaScript under Node; canonical output receipts are byte-compared. These 69
cases are already represented in the unit-test total and are not counted again.
Python's standard-library email parser also independently checks one synthetic
multipart message from the actual Studio MIME builder. Its 30 assertions cover
Unicode filename/body content, binary payload and recipient/header boundaries.
These supplemental checks send no mail and claim no live provider acceptance.

The official Flutter 3.47.8 / Dart 3.13.7 runtime and unchanged locked dependency
graph are documented in [runtime.json](runtime.json) and `runtime-setup.tar.gz`.
Source inventories cover the tracked libraries, tests/fixtures, binaries,
tools, declared assets and macro examples of the 21 resolved workspace
packages, plus manifests, locks and analysis settings. Resolved external
dependencies and runtime files are recorded before and after each run.
Rendering receipts include the relevant actual host fonts. The supplemental
SDK inventory states its own capture time and does not retroactively claim to
precede an earlier run.

## Diagnostic history

The archived development evidence retains failed attempts and their corrections.
An early slide round-trip test exposed the missing distinction between resolved
empty decorations and legacy global-master fallback; the model, copy and
serializer paths were corrected. Incoming master-visibility tests clarified
that hiding the master preserves layout shapes. Independent review also fixed
leading explicit note breaks and bounded derived note titles.

The initial UI fixtures were corrected for serializer namespace materialization,
the per-save core modified timestamp, and settling a desktop focus transition;
production document mutation checks remain in place. Three incoming Dart files
needed formatting before qualification. The complete 1,274-case Zotero pass at
`0aac0e0a` is retained as prepublication evidence, separately from the final
combined-source pass after the connector integration.

All ten primary cohorts pass on the reconciled source, and the later two-case
main guard passes separately. The independent audit initially split three
valid Mail test names at Unicode NEL/line/paragraph separators; its reader
was corrected to use physical LF records, then recounted the unchanged raw
events. The rejected auditor attempt and correction remain archived.
Historical attempts remain in the indexed development and prepublication
archives under `diagnostics/`; they do not contribute additional test cases.

## Reproduce

Use the recorded source commit and the official runtime identified in
`runtime.json`, and resolve the repository's locked dependencies. Export
`FLUTTER_ROOT` and `PUB_CACHE`.
From this directory, inspect a selection before running it:

```bash
python3 run_validation.py engine-zotero --repo /path/to/quds_office_suite --list
python3 run_validation.py engine-zotero --repo /path/to/quds_office_suite \
  --output /path/to/fresh/evidence/engine-zotero \
  --expected-head f0122cb5bff5b6cf6a6f69f043545dabc2930791
```

Repeat for the other nine primary cohorts in the table at the primary source
commit. At the later publication source, reproduce the added two-case file with:

```bash
python3 run_revision_guard.py --repo /path/to/quds_office_suite \
  --output /path/to/fresh/evidence/word-revision-guard \
  --expected-head d1b8f9be24f08b2e4de7292c8727eddbd77bbf55
```

Output directories must be new. The runners record exact commands and refuse
uncommitted product inputs. They never resolve packages, modify source or
contact GitHub.
The supplemental `evidence.tar.gz` archive preserves the portable-corpus and independent-MIME scripts, exact commands, compiled JavaScript and synthetic message bytes.

To re-audit the immutable captured heads after fetching their Git objects and
the corresponding branch/PR refs:

```bash
python3 audit_final_refs.py --repo /path/to/quds_office_suite \
  --evidence . --head f0122cb5bff5b6cf6a6f69f043545dabc2930791 --tested-head f0122cb5bff5b6cf6a6f69f043545dabc2930791 \
  --output /path/to/fresh/final-reconciliation.json
```

## Publication and acceptance boundary

Work is saved incrementally to the retained remote branch with non-forced
expected-head updates. GitHub Actions, workflow-run, check and commit-status
endpoints are **neither queried nor awaited**. A normal merge preserves the
original recent heads and all saved checkpoints.

Acceptance covers local model/controller/widget behavior, document serializers,
actual VBA CLI subprocesses and controlled transports. This work adds no new
installed-app, live Zotero-account, live Mail-provider, or actual Word/
LibreOffice interoperability acceptance run. Historical native DOCX evidence
is preserved with its original source and runtime attribution.
