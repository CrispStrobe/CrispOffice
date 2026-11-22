# Mail identity reconciliation — implementation and local qualification

## Outcome and verification boundary

This increment implements authoritative IMAP/EWS move identities, durable saved acknowledgements, conservative atomic cache reconciliation and stale-writer fences. The feature contract is [identity-transitions.md](../../roadmaps/mail/identity-transitions.md). Source was saved incrementally on `codex/mail-identity-reconciliation-20261122` and reconciled with the subsequently published Word/Zotero history.

**Mail core, storage, transport and vendored parser qualification covers 3,405 case occurrences after repeated supplement executions are removed. The final combined Studio gate is incomplete because shared-disk exhaustion prevented temporary database creation. The complete raw Mail evidence bundle could not be exported.** These limitations are part of the publication record; neither failed host attempt is represented as a passing run.

The [qualification summary](qualification-summary.json) records the completed checks, source attribution, failed diagnostics and export boundary. [Reconciliation](reconciliation.json) records captured references and the exact source retained. GitHub Actions, status queues and check queues were neither queried nor awaited, and no required checks or branch protections were changed.

## Implemented behavior

- Native IMAP preserves one exact COPYUID source/destination pairing and destination UIDVALIDITY. The parser retains tagged/untagged and case-insensitive evidence without hiding duplicate responses. Malformed, conflicting, oversized or mismatched mappings remain uncertain.
- Native EWS requests replacement IDs and verifies the exact returned identity in its destination parent. Missing supported evidence retains the existing generic acknowledgement without inventing a replacement.
- Optional typed receipt and repository-snapshot ports preserve existing providers, custom hosts and unit-result mutation APIs. Studio rebinds identities to the stable account and uses the existing canonical cached-message key.
- Schema15 persists move evidence alongside the durable command journal and restores it after restart. A lost acknowledgement is never recovered by replaying a possibly completed command.
- Eligible projection updates exact source/destination membership and both retained browse revisions, while preserving capture times, coverage flags, provider cursor bytes and existing destination metadata. Both browse views must exist before projection; sync-only or otherwise unfenced coverage requires refresh.
- A required nested savepoint isolates optional cache growth. Cache-only quota failure preserves the admitted acknowledgement with `cacheProjected=false`; receipt quota and other transaction failures remain atomic.
- Persisted move revisions fence both existing-cursor and first-ever null-cursor sync requests. Aggregate metadata includes the retained destination folder label, and backwards clock movement cannot commit an unreadable receipt.
- English, German and Arabic activity views expose saved acknowledgement time and whether cache entries were updated or require refresh.

Source message bytes remain owned by the original identity. A new destination identity is header-only until its body is read; existing destination bytes are preserved. Graph/Gmail-specific transition receipts, copy/purge semantics and full desktop-client parity are outside this increment.

## Branch intake and incremental preservation

The [initial intake](intake.json) starts at main `b2bba1638924237435460e4238d4bd98c407fc3a`. All 29 other fork heads and all 4 upstream heads were already ancestors; both repositories had no open PRs, and the latest 100 updated fork PRs were merged. No old branch work needed to be reapplied.

| Checkpoint | Purpose |
| --- | --- |
| `9b381055f6052d67215c190fc0c9adec832ef366` | Initial intake and implementation plan |
| `5ecbd68b5ad1869b20b4b6e711a5200842abae34` | Receipt pipeline and transactional reconciliation work |
| `9b3b6378dc3f80040e1e2a0ab206600ac5a528bc` | Complete identity receipts, sync fencing and Studio integration |
| `3e2c546208d4c54ce8b6f1b89b47d4c75ade98f9` | Reconciled accepted Zotero main with both histories retained |
| `0c7f0a256a8aa7f00ba6128f212463d4675b40cb` | Clock rollback guards and schema fixtures |
| `8da0e8385794e4ec0af10cd4fbd4d489f98acb01` | Browse CAS, quota savepoint, snapshot consistency and parser style |
| `03595b1fe2addbcd3c52a0024d84c6275a10213a` | Folder-label budget and 14 incoming projection safety cases |
| `06b4e747c09851048d0b72a958e9114f7c83cc52` | Concurrent Word suffix ancestry and the qualified Mail source |

Late published main `8326f191067dac1a3befab81361c5829fee9a35d` adds Word arithmetic and preserves Word suffix evidence. Integration retains that published engine and Office history. The only differing Mail executable file is resolved to the exact locally qualified projection blob `244bca9cae70b23d923cc45714b3d57783aca4a8`; all other Mail production/test inputs and the editor/vendor trees match. The root manifests and lockfile are unchanged.

The new `work/mail-bulk-organization-20261122` branch appeared after the initial 30-head intake. Its later `f25c62e3` UI work is separate concurrent development and is not qualified by this identity milestone.

## Accepted local qualification

| Scope | Qualified case occurrences | Basis |
| --- | ---: | --- |
| Core, native Dart | 629 | 614 broad + 85 final snapshot/coordinator/runner; 70 overlap |
| Core, actual Node | 629 | 614 broad + 85 final snapshot/coordinator/runner; 70 overlap |
| Store, native SQLite | 1,118 | 1,104 complete native + 118 final safety/sync/view/migration; 104 overlap |
| Store, actual Node | 46 | Portable store cohort |
| Transport, native Dart | 574 | Complete 22-suite cohort plus 10 repeated final store-integration cases |
| Transport, actual Node | 208 | Eight portable/unsupported-platform suites, with reviewed shared-source deltas |
| Vendored IMAP parser/response | 201 | Broad 16-suite cohort plus 26 repeated affected style/parser cases |
| **Total** | **3,405** | Repeated supplements, provisioning smoke tests, diagnostics and historical Office runs excluded |

An independent LF-framed event reparse verified all 12 accepted test cohorts, matched their receipts and found zero failures, errors, skips, incomplete cases or protocol errors. Before/after source and runtime snapshots were unchanged within every accepted run.

There are 3,403 distinct `(runtime, suite path, full test name)` keys. Two legitimate parameterized core cases share one display name on each runtime, producing 3,405 case occurrences. This is not a claim of 3,405 distinct test names.

Qualification composes broad runs with reviewed, bounded source deltas. The final core stamp-consistency guard is covered by 85 native and 85 Node cases. The store's sole later production delta is the retained folder-label budget, covered by 118 cases. Vendor changes after its broad run are style-only and covered by 26 affected cases. This does not claim a fresh complete run of every suite at the final Git commit.

Final core, transport, store and changed-vendor strict analysis passed; final store formatting passed. Store browser entry and worker JavaScript compilation passed at the full-store snapshot before the one-line folder-label guard. Actual Node execution and compilation do not qualify browser storage runtime.

## Studio verification and export limits

Initial host regressions and localized activity screenshots passed development checks, but complete before/after bindings were not captured for those early runs. They are excluded from the final acceptance totals.

The combined 11-suite Studio attempt failed with ENOSPC while creating temporary databases. A serial retry also encountered shared-disk exhaustion after capacity had been reclaimed. Both raw failed runs and their unchanged source/runtime snapshots remain diagnostic evidence; partial successes are not an accepted host gate.

Further exhaustion prevented the sandbox launcher itself from starting. The automatic approval policy rejected an unsandboxed cleanup of disposable checkpoint copies because sandbox escalation is disabled. That attempt removed no files and changed no permissions.

The complete raw Mail archive was **not created or uploaded**. Accepted receipts, JSON event logs, source/runtime manifests, screenshots and the prepared packager remain in the task workspace. This remote summary preserves the verified results and limitations, while the source checkpoints are already durable in GitHub. Complete artifact-copy/hash audit and raw export remain to be done when capacity is available.

The remaining host gate includes move-identity, journal/dialog/host, loader, bulk-provider, EWS/cloud, mailbox-store, sync-host and cached-host suites. Run these in small batches with adequate free space. The two most direct feature checks are:

```sh
cd packages/quds_office_editor/example
flutter test --no-pub --concurrency=1 \
  test/studio_mail_move_identity_test.dart \
  test/studio_mail_journal_dialog_test.dart
```

## Concurrent Office qualification

[Incoming review](incoming-qualification-review.json) keeps historical acceptance separate from this task's Mail totals:

- Zotero: 898 historical cases across 33 suites, archive/index and exact input hashes independently checked; 91 converter artifact hashes and 7 successful commands verified. These are not newly rerun cases.
- Word suffix: 7,235 historical occurrences / 7,214 named keys across 141 complete suites independently audited against its earlier compiler, with actual suffix VM/Node output comparison. Failed monolithic portions were replaced only by complete clean suite reruns. The later arithmetic compiler means that entire historical cohort is not source-identical qualification of final main.
- Word arithmetic: the published summary reports 687 arithmetic/numeric/Variant cases and 1,258 Mail cases, with source hashes independently matched. Its raw archive was not uploaded, so those totals are author-reported historical results. Broader regression, corrected grouped-document/corpus, portable comparisons, Flutter and final engine analysis remain explicitly incomplete in its own record.

No incoming Office counts are added to 3,405. No installed Microsoft Office, live provider or stable-platform release claim is made.

## Runtime

Official Flutter 3.47.8 / Dart 3.13.7 and Node 24.22.3 were used. The SDK archive SHA-256 was verified as `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`; 204 dependency archives were verified during locked restoration. The unchanged root lockfile SHA-256 is `2231cacd6ab548da8f0d94020201a29f07f54a20c1682c0e8ae0079967b720eb`.

Native SQLite used the actual hook-generated mapping and library, SHA-256 `0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`. Pure Dart tests used the resolved locked package:test 1.31.1 entry; portable cases ran on actual Node.

## Ordered continuation

Finish the blocked host/export checks, then reconcile the concurrent durable bulk move/archive/delete work against this receipt contract. Continue connected multi-account navigation, body search and cross-folder conversations, categories/rules, richer composition, provider Drafts/Sent reconciliation and live/platform qualification. Track Outlook variants separately and retain provider-specific folder/label/delete semantics throughout.
