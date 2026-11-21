# Final intake and bounded publication — 21 November 2026

This record accounts for **all 338 external heads captured at the initial
intake**, assessed against qualified product source
**`a6095c304ad2d6935f2ae6f8b74412038d19f142`**. At the final captured cutoff,
three branch heads had arrived or advanced afterward. They were preserved
separately and excluded from that qualified source.

**These are historical cutoff dispositions.** Remote `main` may advance after
this capture. Publication may supersede a disposition through a separately
recorded main reconciliation; the actual published ancestry and readback will
be recorded separately. This file makes no assertion that a later `main` lacks
these heads, and later reconciliation does not rewrite this frozen audit.

**The final raw source-coverage audit exits 1.** It records **341 external heads,
three uncovered heads and `all_external_covered: false`**. That result is
retained unchanged; this disposition is not a passing replacement for it and
does not claim that all final heads are integrated. See the
[raw final coverage](coverage.json), [captured snapshot](snapshot.json), and
[machine-readable disposition](disposition.json).

## Captured coverage

| Capture | External heads | Ancestors | Verified historical equivalents | Uncovered |
| --- | ---: | ---: | ---: | ---: |
| Initial, 08:15:28 Europe/Berlin (07:15:28 UTC) | 338 | 314 | 24 | 0 |
| Final refresh, 08:30:36 Europe/Berlin (07:30:36 UTC) | 341 | 314 | 24 | 3 |

The initial inventory comprises 46 fork branch heads, 288 PR heads and four
upstream branch heads. The final inventory comprises 48 fork branch heads,
289 PR heads and four upstream branch heads. Each snapshot separately contains
one checkpoint ref for this Zotero work; those checkpoint refs are not included
in the external-head totals.

The [initial coverage](../intake/coverage.json) proves inclusion against
`e2abbcda6d19f932bfbacc85e0dafd41a3c478f8`, which is an ancestor of the qualified
source. Its 24 historical-equivalence entries retain the independently verified
Git identities in that report. The original 338-head intake is therefore still
fully accounted for. The final capture is a later inventory, not an expansion
of the qualified runtime claim or a statement about subsequently published main.

## Work preserved separately

| Branch | Captured head | Readiness and captured-cutoff disposition |
| --- | --- | --- |
| `codex/word-vba-compatibility-20261121` | [`4b47520a`](https://github.com/CrispStrobe/quds_office_suite/commit/4b47520ae44dc545b898713d6e22370b66767acd) | New Word header/footer continuation. Its own work record identifies an implementation-in-progress checkpoint and withholds final acceptance. Preserved separately; excluded here. |
| `work/mail-sync-foundation-20261121` | [`45f0e503`](https://github.com/CrispStrobe/quds_office_suite/commit/45f0e5038e05e57f121554f976bf74e59af126f6) | Substantial synchronized-mail implementation, pending its own acceptance. Preserved separately; excluded here. |
| `fix/main-green-20261120` | [`9cfad392`](https://github.com/CrispStrobe/quds_office_suite/commit/9cfad3920f9afb3ca1620df429fa41e33f3db8e6) | New Mail duplicate-Close correction, not executed in this Zotero qualification. Preserved separately; excluded here. |

The Word and Mail branches were absent from the initial capture. The existing
`fix/main-green-20261120` branch advanced from the initially captured
`15271321a9f4550c1ab796a2cf9eaed910824574` to `9cfad392`. All three exact final
heads were verified in their captured remote-tracking refs. They were independently preserved in those captured remote refs; this record
does not move or rewrite any ref. Later branch advances do not change these frozen snapshot identities.

### Word header/footer continuation

The [work record at the captured head](https://github.com/CrispStrobe/quds_office_suite/blob/4b47520ae44dc545b898713d6e22370b66767acd/docs/validation/word-vba-compatibility-20261121/README.md)
states that final source hashes, executed acceptance commands, counts and
limitations remain to be supplied. Its earlier baseline tests explicitly do
not qualify the new implementation. The work adds header/footer source
selectors and independent-story guards, with new compiler/native tests and a
portable smoke source.

This branch also incorporates the early Mail synchronization runner
`d9d75300f7eec0eeecc8fdee05bc02fb6ad3db0b` through merge `558c3f4a`. That same
runner is an ancestor of the captured Mail branch. The overlapping Word/Mail
work requires its own coherent acceptance; it is not silently included in the
finished Zotero result.

### Mail synchronization foundation

The new Mail checkpoints add a bounded resumable synchronization runner, native
store schema v8, atomic checkpoints and mailbox observers, synchronized/offline
header browsing, and persistent account-identity wiring for IMAP, EWS, Gmail and
Microsoft 365. Six new test suites and two changed migration/reconciliation
suites are present. These are implemented features, but the unique commits do
not provide completed execution receipts or independent acceptance for them.

Native migrations, storage recovery, account/session identity, reconnects and
asynchronous UI shutdown need their own combined qualification. No new Mail
runtime tests were executed for this intake review, and the Zotero receipt is
not represented as acceptance of this new workflow.

### Mail duplicate-Close correction

The new `9cfad392` commit changes only
`packages/quds_office_editor/example/lib/studio_mail_native.dart`: eight
insertions and five deletions suppress the command-bar Close control while the
saved-message view supplies its own Close control. This is unrelated
post-intake Mail code. Its runtime behavior was not executed here, so it remains
separately preserved rather than being described as qualified by the Zotero
checks.

## Qualification and audit integrity

The [local qualification](../qualification.json) applies to source `a6095c30`
and its **2,978 recorded source/fixture inputs**, with canonical source-map
SHA-256 `b02b5b7f62c34bf37698d53e0cb614df93ac30d955ce0ad8b1cb1707f6f18916`.
It does not include any of the three deferred heads. Documentation and intake
records may be added while keeping that qualified product source unchanged.

Both original and final raw snapshots and coverage reports remain byte-for-byte
unchanged. Their SHA-256 identities are retained in `disposition.json`. The
[coverage auditor](../intake/audit_refs.py) returns 1 whenever its uncovered
external-ref list is nonempty; the final three uncovered entries and that
failure result are preserved without reclassification in the raw report.

No GitHub Actions, workflow/job, check or status endpoints were queried or
awaited for this intake or publication. The review used local Git history and
captured refs; no CI queue was used as an acceptance gate.
