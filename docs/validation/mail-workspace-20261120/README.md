# Mail workspace — final integration and qualification

This continuation delivers shared foreground mailbox navigation across native
IMAP/SMTP, Exchange EWS, Gmail and Microsoft 365, reconciles concurrent Office
main, and records scoped local qualification without waiting for hosted CI. **M04W and
full Outlook/Thunderbird/eM Client parity remain open.**

The reconciled product source is remote checkpoint
`1d26181b0161d88abe5977f9848ffd4cd99e6259`, tree
`c78f112031e101baa294753b6eb003d751b1ed32`. It preserves incoming main
`d040c15a07f652d01e75363031d0efdee6357bda`, including the latest Word/PowerPoint
VBA and proofing integration. Across all engine/editor libraries, only five
added lines in two parsers differ from that main: they preserve the default
center for a radial fill whose focus is omitted. Every other Office library
blob is identical to incoming main. The final evidence descendant retains this
exact reconciled product source on `work/mail-workspace-20261120`.

**Latest combined Studio qualification is blocked by the environment.** Its
full run encountered ENOSPC while creating temporary directories and is rejected.
The earlier complete Mail gate passed 1,221 cases on the preceding integration;
the latest source retains exact-input proofs for 514 Mail cases and two native
path cases, and passes the separate 188-case Office compatibility gate. These
scopes are distinguished below; this report does not claim a fresh 1,221-case
pass on the latest combined source.

## Delivered Mail behavior

- A reusable virtualized `MailMessageList` supplies loaded subject/sender search,
  combined Unread/Flagged filters, visible/loaded counts, distinct empty/no-match
  states and explicit pagination across all four hosts.
- Arrow keys and Home/End move focus independently of opened-message selection.
  Enter/Space or a click opens a row. Filtering, scrolling and moving focus
  perform no provider operation.
- Stable identities preserve selection across appends and compact reader/Back
  transitions. Account/folder changes reset scope; hidden compact lists cannot
  receive keyboard focus. English, German and Arabic strings explain the scope.
- Production IMAP browses descending UIDs through a separate scoped cursor with
  a fixed initial ceiling. Requests load up to 50 headers; hosts stop at 1,000
  loaded messages and reduce the final request to remaining capacity. Later
  arrivals appear after Refresh. This is UID order, not sender Date order.
- Large/sparse discovery respects existing UID-count, line and response budgets.
  Empty windows can retain an older continuation. No unbounded gap scan,
  sequence-number identity or raised global quota is introduced. Load more
  remains available when no loaded row matches the filters.
- Malformed, repeated, cyclic or mismatched continuations are rejected before
  adoption. Read failures retain accepted rows and expose retry or Refresh
  according to the typed outcome.
- IMAP exposes confirmed read/unread and flag/unflag controls. Every host
  preserves independently unknown read/flag observations. Stale callbacks cannot
  update replaced sessions; uncertain IMAP writes require Refresh before more
  mutation/paging and never automatically retry.

The [foreground contract](../../roadmaps/mail/mailbox-workspace.md) contains
the user path, API boundary, limits and failure policy. The
[roadmap](../../roadmaps/mail/README.md) records this completed prerequisite
inside the larger account-aware workspace milestone.

## Local qualification and its limits

| Selection on latest source `1d26181b` | Suites | Passed | Qualification |
| --- | ---: | ---: | --- |
| Mail core VM | 6 | 54 | Exact unchanged transitive inputs |
| Mail transport VM | 19 | 402 | Exact unchanged transitive inputs |
| Mail transport Node boundary | 3 | 6 | Exact unchanged transitive inputs |
| Mail UI Flutter | 5 | 52 | Exact unchanged transitive inputs |
| **Carried Mail foundation** | **33** | **514** | No changed dependency input |
| Native app paths | 1 | 2 | Exact unchanged inputs |
| Latest Office engine compatibility | 9 | 147 | Fresh run on `1d26181b` |
| Latest Office editor / Flutter compatibility | 4 | 41 | Fresh run on `1d26181b` |
| **Fresh Office compatibility** | **13** | **188** | Zero failures/skips |

The [preceding integration report](reconciled-acceptance-01290cee.md) records the
complete **1,221-case Mail gate at `01290cee`**: the same 514 unchanged cases plus
a fresh **707-case Studio Mail/saved-Mail run across all 30 selected files**.
It also records 36 spaCy planner/distribution cases and two Studio theme cases.
Those Studio, planner and theme cases are historical after the latest shared
Office/proofing changes. They are neither counted again nor attributed to the
latest combined source through an unchanged-input claim.

The latest complete Studio attempt loaded all 30 selected suite paths but
failed on temporary-directory allocation. It recorded 67 successful completion
events and 44 non-success completions, including load failures and cascading
setup errors. **The entire cohort is rejected, with zero accepted cases from
that attempt.** The planned fresh spaCy and theme selections did not run.

Formatting and strict Mail analysis passed, including Studio analysis on the
latest source before the environment failure. Strict analysis of the reconciled
Office files and relevant model/regression inputs also passed. The 188-case
Office gate is focused compatibility evidence, not a claim that the entire
Office, VBA or Zotero corpus was rerun. Historical overlapping Office totals
are not added to it. Whitespace checks cover changes relative to incoming main;
raw diff artifacts retain their original bytes.

The [latest independent review](final-latest-review.json) verifies the failed
raw attempt, current source/pins and the precisely scoped carry proofs. It
records an environment-blocked combined Studio verdict, not global acceptance.
The [latest Studio receipt](latest-1d26181b/receipt.json) retains the exact failed
commands and results; [main-office-latest.md](main-office-latest.md) records the
separate successful Office qualification.

## Source continuity and attribution

The latest Studio attempt captured **4,488 product/configuration inputs and seven
runtime/configuration pins**. Every before/after entry matches, and independent
review rehashed the current files. Its aggregate SHA-256 is
`6de30424a78efe050209b9da2701f537922663500761b26d4feb8c79037292ed`.

The 514 core/transport/UI cases were accepted at `740f3e24`. Their resolved
local dependency closure contains **475 captured inputs** matching both the
accepted hashes and latest Git blobs/modes, without additions/removals. It
contains no Office package. The two native-path cases retain their test,
implementation and dependency inputs: nine entries. These sets contain 480
distinct repository inputs. All seven pins match. The
[continuity proof](main-mail-continuity-1d26181b.json) records exact paths and
hashes. Only this exact-input carry is attributed to the latest Mail source;
the historical 707-case Studio result has a changed shared dependency closure.

Studio imports changed Office source, so its previous 707-case result cannot
be carried forward by an exact-input proof after this reconciliation. The same
applies to the spaCy planner, which imports the engine barrel, and the shared
theme tests. The attempted full Studio replacement remains blocked as recorded.
The **188 Office executions** cover actual parser/PDF conflicts, import,
radial, alpha and autofit regressions, native formatting/PowerPoint integration,
and five typing/proofing scheduler cases. Its **2,214 captured inputs** and seven
pins were unchanged; 2,213 repository inputs match the checkpoint, with local
package configuration accounting for one.

The earlier integration stage's [300-case Office gate](main-office.md)
remains attributed to `01290cee`. Its full Office selection was not rerun or
carried forward as 300 unchanged cases after `d040c15a`. That total, the preceding
137/116-case Office stages and the incoming contributors' own test totals are
not added to this report.

## Retained failed attempts and receipt corrections

The [initial stage](initial-acceptance.md) preserves the first Studio attempt:
706 passes and one stale assertion expecting **No messages** after an unmatched
query. The corrected test expects the distinct no-match notice, asserts that
the empty-folder notice is absent, and retains empty-sender/no-exception
coverage. The successful 707-case selection belongs to the preceding integration report.

Independent review also found that Python `splitlines()` split three valid JSON
test names containing Unicode separators. The runner now splits only at physical
LF and rejects missing case metadata. The rejected first attempt's artifacts
remain unchanged; accepted historical name/suite IDs match their raw events.

The first latest-source Studio attempt, [latest-1d26181b](latest-1d26181b/receipt.json),
hit filesystem exhaustion while creating a test directory. It recorded 67
successful case completions and 44 non-success completions, including loading
failures and cascading setup errors. The entire cohort was rejected. Its raw
events, error traces and unchanged source/pin manifests remain preserved. The
planned retry was not started after pinned Dart and Python probes continued
to reject directory creation. No successful events from the rejected cohort
are added to an accepted current-source total.

The latest Office processes passed before their first receipt postprocessor
rejected two distinct parameter fixtures with the same display name. Their
runner IDs are 158 and 163, and each completed exactly once. The corrected
counter uses suite/test identities and reparsed the same raw events. Both the
original rejection and corrected receipt remain in the evidence. No product
edit or rerun was involved. The accepted Office completions have no duplicate IDs, missing metadata,
unexpected suites, skips or unsuccessful runner termination.

## Incoming work

The [initial reference audit](remote-refresh.md) captures 22 fork branches,
236 PR heads and four upstream heads. Upstream heads were already ancestors.
Historical ODS patches remain equivalent; ODT's 37 aggregate paths match its
accepted squash and the Office-union tree matches its landed squash.

Ready CrispOffice identity, Android grammar/workflow and recent PPTX work was
integrated with original ancestry. Concurrent main subsequently incorporated
previously deferred VBA/Zotero work, earlier Mail checkpoints, fonts, geometry
and shared Studio changes. The [first advance](main-advance.md) and
[latest main audit](final-main-advance.md) retain exact identities and dispositions.
All previously deferred feature heads captured by these audits, including the
`b9e4f1d4` aggregate branch, are now ancestors of captured main. The historical
reports' earlier deferred/non-ancestor dispositions are superseded. No contributor
branch was overwritten or deleted.

The latest main also preserves the Word/PowerPoint VBA extensions, native
formatting/replacement APIs, PDF text layout and typing/proofing work. Main's
PDF exporter and every Office library other than the two default-focus parser
insertions remain byte-identical. The incoming authors' macro/PDF/portable
receipts keep their own source and platform attribution; their overlapping
counts are not added here. Incoming proofing workflow source does not establish
a completed typing benchmark or measured performance improvement.

This continuation queried or awaited **no GitHub Actions, workflow run, check
or commit status**. Local acceptance and exact source evidence were used.

The identity change also needed a macOS migration correction: copying only
`quds_office_studio` omits Mail drafts/archive. The
[release guide](../../release/macos-signing.md) includes bundle-specific support
directories and complete SQLite sidecars. Credentials require re-entry. Paths
were checked against host code and the pinned platform plugin; no installed
macOS run is claimed.

## Reproduction and runtime

Execution used genuine **Flutter 3.47.8 / Dart 3.13.7**, the unchanged lockfile
and 195 archive-verified hosted packages. SQLite 3.54.1 and real FTS5 readiness
were verified. [Runtime provenance](runtime/README.md) records setup and hashes.
The seven pins are Dart, Flutter tester, Flutter tools snapshot, SQLite,
package configuration, package graph and the actual `package:test` entry point.
They establish the recorded local inputs, not a completely hermetic operating
system.

When temporary-directory creation is available again, repeat the complete
combined host selection using a new attempt name:

```bash
python3 docs/validation/mail-workspace-20261120/run_acceptance.py \
  --attempt new-environment-studio \
  --only format --only studio-analyze --only studio \
  --only incoming-spacy --only studio-theme
```

Use a new attempt name: evidence cannot be overwritten. Omitting `--only` runs
the complete current Mail runner selection. Receipts retain exact arguments,
directories, durations, exit codes and output hashes. Flutter uses
`--no-pub --concurrency=1`; VM/Node use the actual pinned test runner. The exact
13-suite Office commands and capture runner are in `main-office-latest.md`.

Large Mail-runner event streams, case lists and input manifests are gzip-compressed
without changing their bytes. Each compressed Mail attempt's
`compressed-evidence.json` maps original/stored filenames and both hashes. The
separate Office evidence retains compressed raw event streams, uncompressed
manifests, and hashes in its own summary receipts. Earlier stages retain their
original source attribution.

[Initial cache preparation](cache-preparation.json) and the later
[capacity recovery](runtime/capacity-recovery.md) record the exact cleanup and
remaining failure. Reproducible files accounting for 820,625,408 allocated bytes
were removed; a verified remote-recoverable blob-cache rewrite reduced its pack
by another 267,591,967 bytes. Hard links mean the allocated-file sum is not a
claimed increase in global free space. All refs, indexed entries, 23,242 Git
metadata objects, seven runtime pins and 6,706 retained dependency/compiler
files remained identical. No product-file hash changed.

A 1 GiB regular-file allocation/write/fsync probe succeeded, but both Python
and pinned Dart still failed to create temporary directories with ENOSPC under
multiple existing workspace parents. The final capture reports zero available
bytes, 3,292,729,344 free block bytes and 3,274,378 free inodes. These observations
do not establish an underlying storage-policy cause. The file-write probe does
not qualify directory allocation or turn the failed Studio attempt into a pass.
No privilege, mount or outside-workspace workaround was attempted. Further
repeated full runs were not started against this demonstrated environment block.

Older validation working copies remain sparse locally and their omitted blob
cache remains recoverable from the remote. Current evidence, product source and
runtime inputs used by the accepted gates are preserved. Browser/Wasm/DevTools
work would first require restoration of the recorded auxiliary cache resources.

## Publication and remaining work

[Checkpoint identities](checkpoints.json) record the remote saves. Every remote
tree was compared with the committed local tree; incoming source ancestry is
retained. The final evidence commit changes documentation only. Publication
rechecks main, merges the expected PR head and verifies the resulting tree.
The work branch remains available.

Local gates establish protocol-fixture, host, model and rendering behavior.
Live-provider interoperability, installed Windows/macOS/mobile acceptance,
browser execution and assistive-technology qualification remain separate.
Local drafts retain the existing native, unencrypted, one-per-account boundary.
Loaded-row search and foreground pagination do not implement account-wide
server search, persistent multi-account sessions or a unified inbox.

Next are repository-driven account/folder sessions, persistent account switching
and unified views with durable command recovery. Multiple/offline drafts,
server-side Drafts, visible queued outbox, undo-send/scheduling, account-wide
search, bulk rules, rich composition and Office/Calendar/People remain ordered
continuations.
