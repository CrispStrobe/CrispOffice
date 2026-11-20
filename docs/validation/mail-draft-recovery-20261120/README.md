# Mail draft recovery continuation — 20 November 2026

This increment connects the existing SQLite Mail store to native Studio
composition for SMTP, Exchange EWS, Gmail and Microsoft 365. It advances M07 in
the [existing implementation plan](../../roadmaps/mail/implementation-plan.md),
with the current user path and limits in [draft recovery](../../roadmaps/mail/draft-recovery.md).

## Delivered behavior

- One local draft per stable provider/endpoint/login/sender identity, recovered
  after closing Mail and reconnecting. Credentials and OAuth tokens do not enter
  the draft identity or stored payload.
- Lossless unfinished To/Cc/Bcc text, subject, plain body, reply headers and
  immutable attachment snapshots. Version-one stored payloads remain readable;
  the optional typed editor metadata uses version two without a database reset.
- Debounced autosave with visible progress/failure, latest-revision flush before
  close/send, retry and a confirmed unsaved-close escape during storage failure.
- Serialized revision/CAS writes and empty revision markers for explicit clears,
  preventing delayed writes from resurrecting a sent or discarded draft.
- A durable possible-submission marker before transport. Interrupted sends never
  resend automatically. Only a matching definite rejection can retire the new
  marker, retaining any earlier uncertainty. Accepted-send cleanup failure keeps
  guarded content and an explicit do-not-resend notice.
- Injected storage boundaries in native, EWS and cloud hosts, with stale-session
  callbacks prevented from publishing into a replacement account.

## Remote checkpoints and incoming work

All checkpoints are on `work/mail-draft-recovery-20261120` in
`CrispStrobe/quds_office_suite`. The branch is retained for recovery. No force push
or branch-protection change is part of the workflow.

| Checkpoint | Scope |
| --- | --- |
| `2cfeca15d197110a65a1cbe7601e763ee281fc9d` | Initial draft recovery contract and implementation order |
| `5b072494af4f142aa03654884856c5a9359dc968` | Typed editor persistence, native draft store and file-backed regressions |
| `191605e3cc06d5ac2efbb2d9f60b6b2bd07d7903` | Reconciled previously unmerged PowerPoint gradient/shadow/transparency work; original incoming parent `9c544ecc` retained |
| `81b0d7620bd7d57ee2d5fe878abbad85f0488a00` | Shared composer autosave, native/EWS/cloud recovery, confirmed-rejection handling and host regression tests |

The [incoming-work inventory](integration.md) records all fourteen captured
branches, upstream, patch-equivalent historical work and the active VBA PR.
Recent attachment and Zotero work were already in initial main `7501b604`.
The old PPTX branch contained real missing product changes; its integration
retains main's background ownership and repairs duplicate shadows, double
opacity, parser state leakage and unconnected PDF gradient rendering.

The focused Office runs belong to local source `6dbd12f7`, tree
`7946aa3a80e4cbf1f85a714928745d1242326ec9`; their evidence-only follow-up is
`ce2bfca9`. The remote checkpoint `191605e3`, tree
`8ac1138907efb42508186a389ae4babf26dd8289`, combines those exact Office files and
receipts with the earlier Mail foundation. The different aggregate trees are
intentional: the Office run is not relabeled as a test of the later Mail tree.
All eleven changed Office Dart files were preserved byte-for-byte during that
publication. See [the recorded Office gate](incoming-office/README.md).

Remote main subsequently advanced to `e06eb3a7`. Its Word/kerning work and full
gradient background changes are being reconciled separately before the final
merge. Draft PR #227 remained active and under qualification at the last capture
(`4b8ad781`); it is fetched and preserved, not treated as completed work.

## Local validation

[Local checkpoints](local-checks.md) record 1,073 pure VM, 13 Node boundary and
33 Mail reader widget executions with explicit source-scope limits and the
pinned runtime. They are development checkpoints, not a claim of final combined
source acceptance. The incoming Office gate records 114 engine and 29 Flutter
cases, all passing, plus strict changed-file analysis and formatting.

Focused later checks passed the sixteen file-backed draft persistence cases,
ten composer autosave cases, existing attachment composer regressions, and
native/EWS/cloud host recovery cases. The confirmed-rejection follow-up passed
82 selected cases (29 EWS, 37 cloud, 16 store); these overlap later aggregate
runs and must not be added as distinct tests. Initial failures caused by the
changed close lifecycle and old Cancel-button expectations were corrected and
rerun. The final recorded Mail selection is written under `final-mail/`.

Flutter 3.47.8 / Dart 3.13.7 and the enforced locked dependency graph are used.
GitHub Actions are neither queried nor awaited. Detailed commands, hashes and
native SQLite setup are in the linked checkpoint record.

## Acceptance boundary

This is native local draft recovery after reconnect, not a queued outbox,
multiple-draft manager, offline mailbox host, provider-side draft synchronization
or a complete mail-product parity claim. Existing send/envelope/MIME behavior is
retained. Live-provider delivery, installed Windows/macOS/mobile behavior and
actual browser persistence have not been established by these local fixtures.
The native database is unencrypted. Stored Bcc is local draft data; canonical
outgoing MIME continues to omit Bcc and use the separate transport envelope.

The next ordered work remains the repository-driven mailbox workspace, multiple
drafts/offline entry, visible queued outbox, then richer composition, organization
and Office/productivity integration. The [parity sequence](../../roadmaps/mail/README.md)
ties those increments to the existing M00–M14 plan.
