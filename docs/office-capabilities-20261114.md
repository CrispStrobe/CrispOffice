# Office capability continuation — 14 November 2026

Work is saved incrementally in both Quds Office and CrispCloud on
`codex/office-recovery-20261114-notes-sorting`. This branch retains the recovered
work and the newer main integration. It was separated from the shared recovery
branch after another writer advanced that branch during publication.

## Changes and user-visible behavior

| Area | Change | Acceptance |
| --- | --- | --- |
| Presentation notes | Speaker-note changes now create an undo command and advance the document revision. Equal text is a no-op, and history remains attached to the original slide. | Notes-only edits become dirty; direct/asynchronous saves, clearing notes, undo/redo after navigation, read-only modes, and an edit during upload are covered. |
| Spreadsheet sorting | Sorting now records history, commits pending valid input, and marks the workbook modified. Its history captures the original worksheet and retains cell identities. | Sort-only saves, cross-sheet undo/redo, earlier/later cell edits, pending input, short selections, and read-only modes are covered. Rejected input stops sorting without losing the draft. |
| Spreadsheet cell state | Sort and grid snapshots copy cell locks and modeled PDF borders. | Distinct values move with sorted cells; undo/redo retains them, and an unlocked cell stays editable on a protected sheet. |
| Imported spreadsheet fills | Independent native workbooks now exercise preservation and explicit replacement through three saves. | Eight required outputs enter the normal inventory, schema and render gates; both first saves must match separately authored references. |
| CrispCloud slide prompts | Delete and notes prompts retain their original controller, slide and revision. Save and Close preserves a newer open modal draft. | Actual host navigation, upload, cancellation and stale-prompt tests are recorded in the companion app report. |

The lock and border change preserves the existing in-memory editing and PDF
properties. It does not add serialization of those scalar properties to XLSX.
Native OOXML style preservation remains a separate existing mechanism. The new
fill fixtures verify saved-file fidelity; they do not add gradient painting to
Quds' renderer.

## Source and verification

The final implementation and acceptance-gate source is
`f531c98d4a4e05146a9b89dfd5570cc43ba5537c`. Subsequent evidence and documentation
commits do not change that measured source. The
[suite receipt](evidence/office-capabilities-20261114/suite/validation.json)
binds the logs, dependency resolution, source hashes and exact saved bytes.

| Executed check | Result |
| --- | --- |
| Engine fidelity cohort | 1,265 Dart tests passed |
| Fidelity tooling controls | 440 Python tests passed |
| Full editor suite, including reviewed goldens | 561 passed; one existing optional local-PDF comparison skipped |
| Both package analyzers | No issues, with fatal infos enabled |
| Required output inventories | 358 engine files and 29 editor files verified |
| Editor semantic oracles | Corpus, bookmarks, content controls and bookmark-copy checks passed |
| OpenXML SDK 3.3.0 | Zero errors in all 358 engine and 29 editor outputs |

The new regression files were also run unchanged against the starting source
`79d001522c6550a21b01f2c033fb293c372d3208`. Both engine cases and eleven editor
cases fail there; five editor controls still pass. The fixed implementation
passes all eighteen directly comparable cases. The
[control receipt](evidence/office-capabilities-20261114/controls/suite-controls-validation.json)
preserves both source identities, exact test hashes and 420-input manifests.
A separate rejected-input sort probe passes without needing another code change.

The original six unexecuted fill-history tests now pass as part of both the
focused run and the full editor suite. The previous workspace-storage blocker
is therefore resolved for that gate. A separate
[fill receipt](evidence/office-capabilities-20261114/fill/validation.json)
records the independent native-render acceptance on immutable saved bytes.

## Evidence boundaries

The engine fidelity cohort is the declared preservation gate, not every engine
test. No new engine line-coverage percentage is claimed. The single editor skip
is the existing optional local-PDF comparison, and no visual golden was updated.

Local runtime: Flutter 3.47.8, Dart 3.13.7, Linux x64. The OpenXML validator was
compiled unchanged with official .NET 8.0.428 Roslyn, .NET 8.0.34 reference
assemblies and OpenXML 3.3.0 because the SDK CLI's NuGet migration mutex is not
available in this sandbox. Its negative self-tests passed before positive files
were accepted. Native rendering is separately scoped to the exact recorded
LibreOffice version and inputs. Physical-device/live-provider journeys,
authentic signed Office files and browser execution remain separate acceptance
work; earlier results are not relabeled as fresh runs.
