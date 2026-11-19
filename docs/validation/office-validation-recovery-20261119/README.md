# Office validation recovery — 19 November 2026

## Prepared for a fresh source-bound qualification

Implementation repairs are saved at `58a7b3ff2966b2b972fd2f40fb8f7993fc425768`
on `codex/office-validation-recovery-20261119`, reviewed through
[PR #198](https://github.com/CrispStrobe/quds_office_suite/pull/198).
The complete local gate and independent acceptance audit are the next steps.
**No accepted final aggregate is claimed by this preparation checkpoint.**
GitHub Actions are neither queried nor awaited.

## History and reconciliation cutoff

The recovery began from main `0336116d` (PR #195), retaining the supplied
`4c25c045` checkpoint and every earlier evidence source identity. It integrated
language-ID `40c3351e` and its calibrated Studio frontier `a14ab774`, compact
Arabic morphology PR #196 at `555fc99f`, and EWS PR #197 at `f20b3c61`.
Later checkpoints preserve main `07b815a7` and PR #199 head `10715521` by
actual ancestry. Their original evidence remains attributed to its own source.

The original bounded capture has **230 actual references: 207 ancestors and
23 historical equivalents**, with all 14 historical proofs recomputed and no
unaccounted references. The later inventory has 233 references: 208 ancestors,
23 equivalents and two references to one post-cutoff draft. Draft PR #200 at
`b5eb7b81` adds substantial Gmail/Graph and OAuth functionality, overlaps Mail
setup and remains separate ongoing work. Its head was fetched and its observed
status retained; it is not part of this recovery's qualified source.

[Cutoff decisions](reconciliation-cutoff.json),
[original-capture ancestry audit](recovery-cutoff-ancestry-audit.json),
[later complete inventory](late-inventory-audit.json) and
[observed PR snapshots](latest-pr-review.json) preserve this distinction.
The later inventory audit deliberately reports the two non-integrated draft
references; they are not reclassified as historical equivalents.

## Repairs and retained behavior

- Mail adds failure followed by explicit mark-read retry and stale success/error
  while a replacement session owns a pending mark-read. Exact mailbox identity,
  SMTP acceptance/uncertainty and retained-draft safeguards remain preserved.
- The latest connection setup chooses TLS settings before authentication and
  validates account settings before connecting. Its unconditional fallback
  connection after a failure is removed. Credential loads respect form/session
  ownership; the shared store orders persistence operations, reports write/delete
  failures truthfully and keeps storage feedback separate from delivery receipts.
- Native CLD3 and Arabic morphology shut down through their owning workers so
  normal disposal releases models, buffers and the mapped database. Startup and
  partial-allocation paths retain cleanup ownership. A bounded forced shutdown
  remains the fallback for a nonresponsive worker.
- Classification validates batch bounds and candidates and suppresses stale
  results after disposal. Cache clearing cannot be undone by an old completion.
  Studio host and Word detection results check disposal and detector ownership
  after awaits; public host errors use fixed text.
- Both independent language-policy suites remain. Incoming calibrated defaults,
  five candidates, explicit-language precedence, per-script Word display and
  Apply detected language behavior are retained. PR #199's four Studio cases
  remain, with the obsolete raw-library-error expectation updated to fixed text.
- Thesaurus relation resolution rejects late results after reset, including
  optional-label failure paths. Proofing completeness follows the evidence in
  each paragraph report while retaining the incoming unsupported-row filtering.
- Compact Arabic ABI 2/proofing-bin and native foreground EWS retain their
  original histories and separately attributed evidence.

## Prepared qualification scope

The gate selects **150 native suite executions across 11 groups**, **24 Node
suite executions across 8 groups**, the complete Core/Store launcher (16 distinct
suite files), six required Python control families, strict analysis and
formatting of **147 Dart files**, whitespace, and real frontend/JavaScript
compilation of Mail and the language adapter. All 144 changed Dart files since
the gate base are included. Selected test runs must have zero failures or skips.

All 38 ordinary Studio suites are selected. EWS unsupported-platform behavior
runs only on Node; the original live morphology download case remains in a
separate optional suite. Other optional-backend and screenshot-only exclusions
remain explicit in the plans. The browser stages compile real import closures
and JavaScript; they do not execute a browser or Worker.

## Verified runtime preparation

The original pinned Flutter/Dart SDK and its 176 hosted archives were restored
and verified. The latest-main dependency change received a separate exact
extension of **18 new archives**, producing a union of **194** without replacing
an old archive. Offline enforced resolution and a real SQLite native smoke
passed. All **11,142** original retained inputs remain byte-identical; **1,002**
new package files match their archive bytes. Another **128** Pub metadata JSON
files are bound separately, including 17 inactive package names; these are not
installed dependencies or archive-derived package source.

Real pinned CLD3 and compact Arabic libraries, the CLD3 allocation fixture and
all four pinned morphology data artifacts are individually bound to source and
runtime receipts. The complete gate and independent auditor reject missing or
altered inputs. [Runtime extension and replay instructions](../office-mail-continuation-20261119/runtime-extension.md)
explain how to preserve the original restoration identity while reproducing the
new dependency graph.

## Preserved development evidence

| Separate archive | Indexed members | Regular files |
| --- | ---: | ---: |
| Initial development/preparation | 143 | 115 |
| Studio host/session follow-up | 26 | 25 |
| Integrated morphology/preflight | 76 | 63 |
| Latest thesaurus/status and PR #199 | 60 | 59 |
| Latest Mail/keychain | 23 | 22 |
| Runtime extension and final format preparation | 53 | 47 |

Each archive has complete membership, hashes, original-byte and metadata
comparisons, and deterministic reconstruction verification. Original failed or
skipped diagnostics and baseline reproductions remain unchanged. These counts
and development test results are **not** added together or presented as a
frozen-source aggregate result. See the individual READMEs in [development](development/).

## Evidence boundary

The previous `de24bdfc` Store receipt and logs were not recovered in this fresh
workspace, so its exact failure cause remains unknown. A fresh run establishes
only its own source and runtime result. No installed-platform keychain session,
live Exchange/IMAP/SMTP account, real browser Worker/Wasm execution, browser
persistence, external Word/LibreOffice round trip or independent linguistic
benchmark is claimed by this qualification. The new cloud-provider draft has
its own separate review and acceptance scope.
