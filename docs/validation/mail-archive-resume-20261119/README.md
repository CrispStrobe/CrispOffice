# Durable mail archive restoration — 2026-11-19

CrispOffice can resume restoration of an exported mail archive after cancellation
or process termination. Progress belongs to the destination archive and is
committed atomically with each original, search projection and complete source
provenance. Full source-verification reruns remain available.

## Continuation and current merge status

Publication resumed from `b2c05a0afa0ae606b061b13d5e50937c2a8eb1df` and
integrated main through `088d80905e3f76542dd9813e96584cd5c61454ff`, including
PR #214's bundled-model labels and PR #215's first-analysis verification.
The final source `9b8853667b68c7bebff050e52445b47ea0bbd188` passed a fresh
**50-case, three-file, four-command gate**, with zero failures/skips and an
independent current-input audit. The [continuation record](continuation/README.md)
records the exact four-file source/test delta, recovered full acceptance,
227-ref reconciliation, and final publication verification. Mail source/tests
remain unchanged. The original 2,243 executions below retain their original
source binding and are not added to the overlapping continuation counts.

## Original complete acceptance and publication

The complete mail acceptance run passed **1,138 test executions across 62 distinct
test files**, with **zero failures and zero skips**, on preserved source
`71053bf61521e093903d55cba890ef4beee039e1` (tree
`456cb5169f4359a8dcf4ec958445e918b367cac2`). All nine mail commands passed.
The before/after inventories agree for **4,493 source inputs, 9,298 dependency
inputs and 1,108 runtime files**. The root package manifest and lockfile remain
unchanged, and tests use the default packaged Linux SQLite native asset.

The complete combined acceptance and independent replay passed **2,243 test
executions and distinct case identities across 121 files and 11 test cohorts**,
with **zero failures and zero skips**. All **42 required commands** and all
**six JavaScript programs** passed. The independent audit found no discrepancies.
Incoming qualification additionally binds 4,494 source inputs, 9,298 dependencies,
1,118 runtime files and 13 executed harness/selection inputs. Historical author
evidence, interrupted runs, focused development passes and superseded v2 runs
contribute no accepted executions. GitHub Actions are neither queried nor awaited.

The original publication at `b2c05a0afa0ae606b061b13d5e50937c2a8eb1df`
verified that all accepted source inputs matched the candidate's Git blobs and
only validation documents had changed. The continuation additionally qualifies
the explicit latest-main delta. Final publication and merge identities are
recorded in [PR #212](https://github.com/CrispStrobe/quds_office_suite/pull/212)
and the continuation record.

- [Published source verification](publication-verification.json)
- [Combined acceptance receipt](acceptance.json)
- [Independent raw-event and identity audit](independent-audit.json)
- [Mail acceptance receipt](final/receipt.json)
- [Exact incoming acceptance inventory](incoming/acceptance-inventory.json)
- [Exact selection and strict-analysis targets](final/selection.json)
- [Executed acceptance harness](run-mail-validation.py)
- [Independent implementation review](independent-review.md)
- [Reconciliation and conflict decisions](integration-notes.md)
- [Reference inventory at integration cutoff](reconciliation-cutoff.json)
- [Remote source checkpoints](checkpoints.json)
- [Publication frontier and latest-main review](publication-frontier.md)

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
| Latest main ancestry, including language review/download management | `4a4ea1f0d8c990cc74ce8f7233545a8a9dc0887c` |
| App/runtime packaging fixes | `0e03878b028ec25ed3d84a790633433eafc3bede` |
| GUI / PR #211 | `ba51c40abc664758df3cfc846625bdeb81e3ac13` |
| VBA / PR #210 | `d8be43a408473da4b45059561dbc387f5b868d5b` |

The preserved integration-cutoff reconciliation accounts for **232 external references: 209 ancestors and 23
historical equivalents, with zero unaccounted references**, from 234 captured
refs after excluding this branch and PR. All 14 historical equivalence proofs
were freshly recomputed. Ancestry and content equivalence establish
incorporation; runtime qualification is recorded separately. The later main merge at `4a4ea1f0` adds exactly three validation documents to the integrated tree, with no product/test/harness changes. Later independent draft additions are reviewed explicitly in the publication-frontier record and are outside this accepted source.

The integration preserves the stronger combined slide raster/contrast and XML
round-trip tests. It retains the table-cell text-color parser repair, themed
Studio settings and explicit language-download flow. Bundled and downloaded
spaCy hosts now share verified optional NER status, and the download manager
reports model-only size when the runtime is bundled. Five focused regression
cases protect that cross-branch interaction.

## Complete validation results

| Area | Passed |
| --- | ---: |
| Mail core and MIME | 138 |
| Native archive and portable Node boundaries | 566 |
| Shared mail UI and Studio mail | 434 |
| Engine/macros/VBA and slide parsing | 650 |
| Incoming editor and Studio integration | 358 |
| spaCy package fixtures | 97 |
| **Total** | **2,243** |

All 24 captured mail UI images match the retained review hashes; the 12 new
resume, result, progress and forget-confirmation states were individually
reviewed across English, German and Arabic. Exact Linux ruler image comparisons
pass after the documented reference correction; selection and document pixels
remain unchanged. Strict analysis covers 81 mail/incoming targets, the engine,
16 editor and 24 Studio targets, and the spaCy library/tests. Formatting checks
cover all 71 changed Dart files plus the recorded incoming scopes. Static checks
verify shell/Python syntax, 13 licence notices, nine Studio mirrors and exact
originating notice bytes. Those checks add no behavioral cases.

The final publication inventory separately accounts for **234 external refs:
206 ancestors, 23 historical equivalents and five explicitly reviewed
post-cutoff refs, with zero unaccounted references**. The later GUI/VBA draft
head additions and bundled-NER follow-up are not represented as merged or tested
in this acceptance. Their exact heads, statuses and independent scope are in
[the publication-frontier record](publication-frontier.md).

### Mail validation detail

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

One editor command started during publication of a local documentation checkpoint. Its local and canonical GitHub commit share the exact complete tree and parent; the [raw commit and mapping](local-execution-commits/mapping.json) preserve that metadata identity. No source, test or runtime input differed.
