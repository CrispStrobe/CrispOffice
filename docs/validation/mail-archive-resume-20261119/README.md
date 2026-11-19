# Durable mail archive restoration — 2026-11-19

CrispOffice can resume restoration of an exported mail archive after cancellation
or process termination. Progress belongs to the destination archive and is
committed atomically with each original, search projection and complete source
provenance. Full source-verification reruns remain available.

## Acceptance and publication status

The complete mail acceptance run passed **1,138 test executions across 62 distinct
test files**, with **zero failures and zero skips**, on preserved source
`ec6d527e9aaf207e131217ec24c65cd9ae409433` (tree
`5f37164d8a382baaf02425654c102494e2af72d3`). All nine mail commands passed.
The before/after inventories agree for **4,493 source inputs, 9,298 dependency
inputs and 1,108 runtime files**. The root package manifest and lockfile remain
unchanged, and tests use the default packaged Linux SQLite native asset.

The combined incoming-work qualification and independent audit are still in
progress at this evidence checkpoint. Their final receipt replaces this status
before publication to main. Historical author evidence and development passes
are excluded from the fresh acceptance totals. GitHub Actions are neither
queried nor awaited.

- [Mail acceptance receipt](final/receipt.json)
- [Exact selection and strict-analysis targets](final/selection.json)
- [Executed acceptance harness](run-mail-validation.py)
- [Independent implementation review](independent-review.md)
- [Reconciliation and conflict decisions](integration-notes.md)
- [Reference inventory](reconciliation-final.json)
- [Remote source checkpoints](checkpoints.json)

## Delivered behavior

| Area | Behavior |
| --- | --- |
| Durable progress | SQLite schema version two adds bounded jobs and per-message receipts. Each receipt shares the transaction and cancellation/fault barrier with original bytes, the verified search projection and all manifest provenance. |
| Resume after interruption | Reopening the same destination and selecting the same manifest exposes committed counts and bytes. Resume verifies destination content, metadata, FTS and expected provenance before confirming an earlier item. Source EML is read and parsed only for unfinished work. |
| Sparse failures | A failed middle item is retried while confirmed later items resume. Missing provenance causes ordinary verified import to repair it; corrupt destination content never becomes a successful skip. |
| Source movement | Progress is bound to decoded UTF-8 manifest text, with an optional BOM ignored, and the destination archive. Moving an unchanged export preserves progress. A changed manifest rejects a stale preview. |
| Full reruns | The API defaults to full source verification. Clearing **Resume unfinished work** checks every selected source EML again and deduplicates retained originals and provenance. |
| Progress management | **Restore progress** lists saved selections. **Forget progress** confirms and deletes only the selected job and receipts; originals, origins, archive dates and search data remain intact. Cleanup remains available after lowering write quotas. |
| Reporting | New saves, duplicates, failures, added origins and current verified bytes remain separate from resumed messages, resumed bytes and persisted indexing warnings. Failure details and observer diagnostics remain bounded. |
| Studio | English, German and Arabic previews, resume confirmation, cancellation, progress management, narrow layouts, right-to-left rendering and 160% text scaling. |

### Using it

1. In native **Mail archive**, select **Restore exported archive** and choose an
   export directory.
2. Review the manifest selection and saved progress. When progress exists,
   **Resume unfinished work** starts selected.
3. Choose **Resume restore**. Confirmed destination items do not require their
   old source EML copies; unfinished originals and the manifest must be present.
4. Clear the resume option to verify every source file again.
5. Use **Restore progress → Forget progress** when a saved selection is no
   longer needed. Forgetting progress does not delete archived mail.

Resume confirms retained destination data. It does not certify skipped source
copies or replace existing projections when attachment-indexing preferences
change. Preview counts are advisory and never authorize skipping an item.

### Limits and compatibility

The existing selection defaults remain 10,000 originals, 1 GiB total original
bytes, 32 MiB per original, a 16 MiB manifest, 20,000 provenance entries and 50
retained failure details. Destination quotas also apply.

Progress defaults to **64 jobs and 100,000 receipts** across the destination.
Logical quota accounting charges 192 bytes per job and 256 bytes per receipt;
these are deterministic charges, not measurements of SQLite disk usage.
Reaching a quota rolls back the current message and receipt together; earlier
commits remain. Progress is never silently evicted.

Version-one archives migrate additively. Unknown future schemas are refused.
Existing archive dates and retained projections are preserved. Completion
observers retain the established `MailArchiveOperation.archive` diagnostic, so
post-commit cancellation remains compatible with existing callers.

The [archive guide](../../roadmaps/mail/archive-search.md) describes the public
API, verification boundaries, quota behavior and remaining roadmap.

## Reconciled incoming work

The source contains the previous restore milestone at `caf378f4`, the current
main language-review and explicit-download changes, the latest VBA arrays and
`For Each` work, the GUI/theme/ruler work, and the macOS runtime-bundling branch.
The final source incorporates these exact later heads:

| Stream | Incorporated head |
| --- | --- |
| Main language review/download management | `9f41e0427734d815b19149eba5eabef202f78ba6` |
| App/runtime packaging fixes | `0e03878b028ec25ed3d84a790633433eafc3bede` |
| GUI / PR #211 | `ba51c40abc664758df3cfc846625bdeb81e3ac13` |
| VBA / PR #210 | `d8be43a408473da4b45059561dbc387f5b868d5b` |

Reconciliation accounts for **232 external references: 209 ancestors and 23
historical equivalents, with zero unaccounted references**, from 234 captured
refs after excluding this branch and PR. All 14 historical equivalence proofs
were freshly recomputed. Ancestry and content equivalence establish
incorporation; runtime qualification is recorded separately.

The integration preserves the stronger combined slide raster/contrast and XML
round-trip tests. It retains the table-cell text-color parser repair, themed
Studio settings and explicit language-download flow. Bundled and downloaded
spaCy hosts now share verified optional NER status, and the download manager
reports model-only size when the runtime is bundled. Five focused regression
cases protect that cross-branch interaction.

## Mail validation detail

| Cohort | Passed |
| --- | ---: |
| Mail core | 54 |
| MIME | 84 |
| Native mail store | 557 |
| Portable store/manifest Node boundaries | 9 |
| Shared mail UI | 33 |
| Studio mail | 401 |
| **Mail total** | **1,138** |

Coverage includes version-one migration, transaction rollback, cancellation
around commit, an actual SIGKILL followed by recovery and resume with a confirmed
source file removed, sparse failures, manifest changes, corrupt destination
originals/projections/indexes, provenance repair, moved exports, separate
profiles, job/receipt/byte quotas, cleanup under tighter quotas, overlapping
operations, disposal, observers and localized UI states.

The strict mail gate analyzes all mail packages and changed incoming Dart
sources and formats all 71 changed Dart files. Four exact whitespace exceptions
preserve three raw patch captures and one imported licence-source notice; their
bytes remain recorded. No production Dart file is excluded.

Raw events, command exit codes and complete input manifests are retained under
[final](final). Earlier preflight and interrupted attempts are retained under
[superseded](superseded/attempts.json) with zero accepted contributions. Focused
development and UI-author runs are preserved separately and are not added to
the complete mail totals.

## Qualification boundary and remaining work

This qualifies Linux native SQLite, synthetic and loopback fixtures, declared
Node boundaries, and Flutter widgets. The macOS packaging work receives syntax
and licence-integrity checks; installed macOS/Windows/mobile applications,
signing, native model loading and real-account interoperability remain separate
qualification work.

The manifest remains unsigned: hashes detect corruption and observed changes,
not sender or export authenticity. Portable filesystem checks do not exclude
every hostile path replacement between operating-system calls. Tests of
process termination do not establish behavior under every power-loss or device
failure.

Restoration covers exported originals and provenance. It does not restore a
provider mailbox, account settings, credentials, saved searches or an entire
archive database. Durable cursors for generic file/directory and provider
collection, scheduling, recursive account traversal, PST/MSG ingestion,
PDF/Office attachment extraction, provider-mailbox restoration and enterprise
ACL, retention, legal-hold, audit, backup and key-management controls remain
separate roadmap items.
