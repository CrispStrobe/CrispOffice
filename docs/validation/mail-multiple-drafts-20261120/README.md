# Mail multiple-draft continuation — 20 November 2026

This record accompanies [multiple-drafts.md](../../roadmaps/mail/multiple-drafts.md).
The work branch is `work/mail-multiple-drafts-20261120`. Source was saved to
GitHub incrementally. Qualification used the pinned local runtime and did not
wait for GitHub Actions.

## Intake and source checkpoints

The [initial audit](intake.json), [reconciliation audit](final-incoming-audit.json)
and [bounded premerge snapshot](premerge-intake-audit.json) record the fork and
upstream heads, open PRs, and content-equivalence proofs for historical branches.
The new work retains normal commit ancestry from the incoming Office/VBA,
Outbox, remembered-account and Zotero branches. Historical branches whose
content was already integrated were checked rather than reapplied.

| Remote checkpoint | Contents |
| --- | --- |
| `d4787143856f83ca80a1928f86ce010a64822268` | Initial integrated Office/VBA, Outbox, account and Zotero intake |
| `7f98f5fbad00e34abafabf1e901a27102c30acd7` | Durable draft catalog, repository and host storage |
| `3506fceabff4a377576f3ba935342a1059751a1c` | Draft chooser, independent composition and offline entry |
| `e7ed2efd4e661ef244a21dd2836525c8e1531b7e` | Reconciled incoming heads and both-host recovery qualification |
| `aedb870e32ffd1842ddd40329bd2e12995281a1b` | Final captured Zotero evidence and read-only EWS regression correction |

The final tested-source checkpoint is recorded in [acceptance.json](acceptance.json).
The later evidence-only checkpoint does not alter product source. Every remote
checkpoint tree was compared against the local committed tree before an
expected-head, non-force branch update. No workflow or branch-rule change was
used.

The final captured incoming tips were main `13be5046`, Outbox `9443612b`,
remembered accounts `c20b41d9`, Office/VBA `0f623939`, and Zotero `93dc987c`.
Open PRs #249, #251 and #252 pointed to those included heads. The last Zotero
commit added only engine qualification evidence. All four upstream branch heads
were already ancestors. See the audit files for full hashes and snapshot times.

## Local qualification

| Scope | Result |
| --- | --- |
| Exact integrated intake: full core, MIME and transport, plus three affected document-layout suites | 579 passed (60 + 84 + 402 + 33) |
| Full native store, including catalog, corruption, quotas, Outbox transfer and actual process-kill recovery | 596 passed |
| Existing Node codec/platform/browser-error cohort | 46 passed |
| Complete shared `quds_mail_ui` suite | 96 passed |
| Broad Studio mail, saved-mail and credential cohort: all 47 selected files | Initially 962 passed, 2 failed; original failed receipt retained |
| Full corrected EWS file | 61 passed |
| Full corrected saved-mail file | 14 passed |
| Strict analysis and formatting of all 19 changed Dart files | Passed |
| Store strict analysis; browser entry and worker compilation | Passed |
| Incoming store evidence-checker Python suite | 48 passed |

The accepted Studio coverage uses the unchanged passing files from the broad
run and the two complete corrected-file reruns. It covers all 964 selected
Studio test cases, with no skipped or excluded cases. This is a composed
acceptance result, not a claim that the original broad run passed. Focused
catalog, chooser, offline, Outbox and 13-case host-recovery cohorts overlap these
suites and are not added again as unique tests.

The runtime was repository-pinned Flutter 3.47.8 / Dart 3.13.7 with enforced
locked dependencies. The official SDK archive and 202 hosted package archives
were hash-verified. Native storage used the unchanged sqlite3 3.9.1 package
build hook and its pinned SQLite 3.54.1 artifact with FTS5 enabled. No dependency
lock changes or system-library substitution were used.

## Findings and corrections

- A missing native-assets manifest caused ten SQLite setup failures in the
  first isolated transport run. Preparing the unchanged locked hook resolved
  them; the complete 402-test rerun passed without source changes.
- The new corruption fixture initially changed blob length and reached SQLite's
  CHECK before the intended hash check. Equal-length corruption fixed the
  fixture before the successful complete store run. A later indentation-only
  change is recorded separately in source-continuity evidence.
- Narrow localized draft-list navigation overflowed. Controls now wrap; the
  English, German and Arabic layouts are included in the passing Studio cohort.
- If a host read failed after closing the chooser, its old snapshot could
  otherwise overwrite a newly selected draft or recreate a deleted draft.
  Hosts now adopt the chosen snapshot directly or retire an unreadable owner.
  Both-host tests cover these paths, ownership checks and A → B → A callbacks.
- The old read-only EWS test expected Compose to be disabled. It now verifies
  that local editing opens while Send, Queue, reply and mutation restrictions
  remain enforced. The full EWS file passed after the assertion was updated.
- The saved-mail close assertion failed on both the initial intake and the new
  tree. Its fixed 350 ms wait ended during the pinned Flutter page-route reverse
  transition. The corrected test uses a bounded wait based on the configured
  transition, retaining removal and active-sheet-controller assertions. The
  failed first correction and the successful full-file rerun are both retained.
- Final formatting found one indentation-only line in the draft-dialog test.
  It was corrected; the accepted static check passed. No product source changed
  during these final test corrections.

## Evidence and reproducibility

[acceptance.json](acceptance.json) identifies the source checkpoint, accepted
receipts, hash continuity, the two corrected test files, formatting-only deltas,
and limits. [evidence-index.json](evidence-index.json) provides the SHA-256 and
size of every preserved member in [evidence.tar.gz](evidence.tar.gz). The archive
contains actual JSON runner events, command/exit receipts, original unsuccessful
attempts, diagnostics, static checks, and runtime provenance.

Archive paths retain their location relative to the original workspace root.
For example, an original receipt path beginning
`/workspace/scratch/b56a923051a9/validation/` maps to `validation/` inside the
archive. Original receipts are preserved unchanged; absolute execution paths
are provenance, not required locations for a new checkout. The independent
review is also available as [review.json](review.json).

The accepted receipts carry commands and source/test hashes. On an environment
with the pinned SDK and locked dependencies, use the listed package working
directories and commands, adjusting only the workspace/SDK paths. Native store
and transport tests require the locked sqlite3 native build hook. The native
suite's real process-kill tests must not be replaced with graceful shutdown.

## Remaining boundaries

Offline entry is limited to remembered IMAP explicit-server/preset records whose
exact account identity is reproducible. EWS/cloud and incomplete historical
autodiscovery records still require connection. Draft selection is session
state; other saved messages remain available through Drafts after restart.
New admission is limited to 100 active drafts per account, while existing larger
catalogs remain pageable and editable.

This is local draft storage under the existing unencrypted native-store policy.
It does not implement server Drafts synchronization or an offline inbox. The
saved indicator confirms a completed write; edits that have not completed saving
can still be lost. Node and browser compilation do not qualify actual browser
IndexedDB/OPFS catalog execution. No production credentials, real delivery,
installed-platform package, or full Office-suite qualification is claimed.

The ordered next work is verified offline identity/session metadata for the
remaining accounts, repository-driven mailbox streams and durable commands,
unified/offline inbox and provider-side drafts, then richer composition and
Outbox review/undo/scheduling. The wider roadmap retains search/conversations,
rules, Calendar/People and installed/live-provider gates. This increment advances
recoverable composition; it does not complete M04W, all M07 or desktop-client
parity.
