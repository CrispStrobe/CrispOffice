# Initial Mail acceptance before concurrent main reconciliation

This is the historical accepted stage at `44abcfa1`, saved before main advanced
to `860c807b`. The [main advance audit](main-advance.md) supersedes its earlier
branch dispositions. The current [publication report](README.md) records final
combined-source acceptance. Raw evidence below retains its original attribution.

This increment delivers shared foreground mailbox navigation across native
IMAP/SMTP, Exchange EWS, Gmail and Microsoft 365. It also reconciles the ready
incoming app-identity, Android grammar/workflow and PowerPoint work while
preserving the original incoming branch ancestry. M04W and complete desktop
Mail-client parity remain open.

The accepted source is remote checkpoint
`44abcfa10367c8cf586ad3cf826feb3cb1de6dab`, tree
`a80b7b1a13d58276205c1669fe4c1fa7cb2c9b94`. The final evidence commit is its
documentation-only descendant on `work/mail-workspace-20261120`. No GitHub
Actions, workflow runs, checks or commit-status endpoint was queried or awaited.

## Delivered behavior

- One reusable, virtualized `MailMessageList` supplies loaded subject/sender
  search, conjunctive Unread and Flagged filters, visible/loaded counts,
  distinct empty/no-match states and explicit pagination in all four hosts.
- Keyboard arrows and Home/End move focus independently of opened-message
  selection. Enter/Space or a click explicitly opens a row. Filtering, scrolling
  and moving focus perform no provider request.
- Stable identities preserve selection through appended pages and compact
  reader/Back transitions. Account/folder changes reset list scope; hidden
  compact lists cannot receive keyboard focus. English, German and Arabic
  strings describe the loaded-only search and finite limits.
- Production IMAP browsing uses a separate descending-UID cursor, fixes its
  initial upper UID boundary and loads up to 50 headers per explicit request.
  Large and sparse folders respect the existing UID-count, line and aggregate
  response budgets. Empty numeric windows can retain an older continuation;
  no unbounded background scan or sequence-number fallback is introduced.
- Hosts stop at 1,000 loaded messages and reduce the last request to the
  remaining capacity. Invalid, repeated, cyclic or mismatched continuations
  are rejected before page adoption. Read failures retain accepted rows and
  expose explicit retry or Refresh according to the typed failure.
- IMAP adds confirmed read/unread and flag/unflag controls. Every host preserves
  independently unknown read/flag observations. Stale callbacks cannot update
  a replaced account/session; uncertain IMAP writes require Refresh before
  further mutation or pagination and never automatically retry.

The [user path and implementation contract](../../roadmaps/mail/mailbox-workspace.md)
describe these limits and the optional browser/action ports. The
[ordered roadmap](../../roadmaps/mail/README.md) now records this completed
foreground prerequisite separately from the full account-aware workspace.

## Accepted local selection

The **accepted Mail set contains 1,221 passing cases, zero failures and zero
skips**, across 63 selected test files. Accepted counts below do not include
repeated development runs or the rejected original Studio cohort.

| Mail cohort | Selected files | Passed | Accepted source/run |
| --- | ---: | ---: | --- |
| Mail core VM | 6 | 54 | `740f3e24`, unchanged inputs carried forward |
| Mail transport VM | 19 | 402 | `740f3e24`, unchanged inputs carried forward |
| Mail transport Node boundary | 3 | 6 | `740f3e24`, unchanged inputs carried forward |
| Mail UI Flutter | 5 | 52 | `740f3e24`, unchanged inputs carried forward |
| Complete Studio Mail and saved-Mail selection | 30 | 707 | Fresh run at `44abcfa1` |
| **Mail total** | **63** | **1,221** | |

The same fresh follow-up also passed two incoming-work selections:

| Additional selection | Files | Passed |
| --- | ---: | ---: |
| spaCy distribution and grammar planner | 2 | 36 |
| Studio native paths | 1 | 2 |
| **Additional total** | **3** | **38** |

Formatting and strict analysis of core, transport, UI and changed Studio Mail
files passed. The corrected Studio test is included in the fresh formatting
and strict-analysis pass. All selected suites loaded; no unexpected suite,
hidden skip, duplicate completion ID or missing accepted case metadata was
found. Every accepted command returned zero and a successful final test event.

The [independent acceptance review](studio-44abcfa1/acceptance-review.json)
recounts raw events, verifies exact suite selections and output hashes, and
records the composite 1,259-case Mail-plus-additional selection without
conflating it with the separate Office gate.

### First attempt and correction

The [first receipt](final-740f3e24/receipt.json) at `740f3e24` passes all 514
non-Studio Mail cases. Its Studio command completes all 707 cases with **706
passes and one failed assertion** in `studio_mail_test.dart`: the pre-existing
empty-sender search test expects the old generic **No messages** label after
an unmatched query. The new shared list correctly uses its distinct no-match
state. That entire original Studio cohort is excluded from the accepted set.

The correction imports the workspace strings, expects the localized no-match
notice, asserts that the empty-folder notice is absent, and retains the original
empty-sender/no-exception coverage. No product implementation changed. The full
30-file Studio selection was then rerun, producing the accepted **707 passes**
in the [fresh receipt](studio-44abcfa1/receipt.json).

Independent review also found an evidence-parser defect: Python `splitlines()`
split three valid JSON test names containing literal Unicode separators. The
first Studio case artifact consequently has three missing names/suite IDs,
although its completion counts and retained raw events are intact. The runner
now splits JSONL only at physical LF characters and rejects missing visible
case metadata. The fresh accepted case list preserves every name and suite ID.
The old artifacts are retained as observed, rather than silently rewritten.

### Why the other 514 cases carry forward

Both attempts captured **4,437 product/configuration inputs** and **seven pinned
runtime/configuration files**. Each attempt's before and after manifests match
exactly. Between attempts, the only changed captured input is
`packages/quds_office_editor/example/test/studio_mail_test.dart`. The other
**4,436 entries** and all seven pins are identical. That Studio test is not an
input to the accepted core, transport or UI suites. The evidence runner change
is separately identified by its recorded SHA-256 and source commit.

The independent review rehashed every current captured file and every pin,
reconciled the 514 carried cases directly from raw output, and checked the
complete fresh Studio cohort. This qualifies the combined accepted selection
without repeating or adding the old 706 Studio successes. The previous turn's
1,245-case draft/store gate and this turn's 130-case development transport run
are not added to this total.

| Attempt | Aggregate input SHA-256 |
| --- | --- |
| `final-740f3e24` | `84a9b892c8999fb2d15175ed91db029262649d8b07e43833609db1f3711e406b` |
| `studio-44abcfa1` | `e0967bc40a7aa5b5f1a204d922162ce93799eb5d466f1c4351d9eaa70ce42630` |

## Runtime and reproduction

Execution used genuine pinned **Flutter 3.47.8 / Dart 3.13.7**, the unchanged
workspace lockfile and 195 archive-verified hosted packages. SQLite 3.54.1 and
real FTS5 readiness were verified. The [runtime evidence](runtime/README.md)
retains exact artifact hashes, package provenance, setup commands and the
development transport logs. No dependency or test implementation was patched
to bypass a failure.

The seven separately pinned files are the Dart executable, Flutter tester,
Flutter tools snapshot, SQLite native library, package configuration, package
graph and actual `package:test` entry point. This is an exact local continuity
check of those files, not a claim of a completely hermetic operating system.

With the recorded runtime environment active, the actual acceptance commands
from the repository root were:

```bash
python3 docs/validation/mail-workspace-20261120/run_acceptance.py \
  --attempt final-740f3e24

python3 docs/validation/mail-workspace-20261120/run_acceptance.py \
  --attempt studio-44abcfa1 \
  --only format --only studio-analyze --only studio \
  --only incoming-spacy --only studio-paths
```

Use a new attempt name to reproduce; the runner refuses to overwrite evidence.
Running the current corrected source without `--only` executes the complete
selection. VM tests use the real pinned `package:test` entry point; three
JS-only transport files run separately on Node. Flutter commands use
`--no-pub --concurrency=1`. The selection files and receipts retain exact
arguments, working directories, durations, results and stdout/stderr hashes.

Raw JSONL events, per-case lists and input manifests are stored as gzip without
changing their bytes. Each attempt's `compressed-evidence.json` maps the original
filenames recorded in its receipt to stored filenames and both hashes. Decompress
before comparing a receipt's original stdout hash or replaying a manifest check.

The first startup could not create an evidence directory because the shared
filesystem was full; **zero tests started** in that startup. Reproducible test
caches were cleared. Older validation working copies were subsequently made
sparse while retaining all Git objects, references, current evidence and
product source. [Cache preparation](cache-preparation.json) and
[cache cleanup](test-cache-cleanup.json) record the exact scope. The accepted
inputs remained unchanged during execution. `git sparse-checkout disable`
restores the historical working copies when filesystem capacity permits.

## Incoming work and Office qualification

The [reference audit](remote-refresh.md) records **22 fork branches, 236 PR
heads and four upstream heads** at its capture. All four upstream heads were
already ancestors. Historical ODS changes remain patch-equivalent, ODT's 37
aggregate paths match the accepted squash, and the Office union tree matches
its landed squash. Their changes are preserved without replaying them over
later repairs.

Ready work was integrated with original ancestry: CrispOffice identity PR #234,
Android grammar/workflow PR #236 and its later toolchain correction, newer main,
and the recent PPTX autofit, radial-fill and opacity changes. The latest
[PR/main metadata check](prepublication-pr-check.json) found no additional
ready open PR and confirmed that PR #227 remains draft.

The initial Office reconciliation repaired autofit persistence and consistent
Flutter/PDF text measurement. The later incoming gradient/alpha changes required
additional repairs for reachable radial parsing, save/copy/background behavior,
Flutter/PDF geometry, exported PDF graphics-state resources and picture/border
opacity isolation. Centered circle gradients with default fill tiles are the
supported radial scope; unsupported path geometry retains the explicit fallback.

The [final Office gate](incoming-office-followup.md) passes **137 cases**:
98 engine and 39 editor, with zero failures/skips. This **replaces** the
overlapping earlier 116-case Office selection. All 1,494 captured Office inputs
matched during execution, and the [publication comparison](office-publication-comparison.json)
verifies the exact 1,493 repository files plus local package configuration
against published source. The same new engine probes fail eight cases against
the incoming uncorrected source and pass all 14 after repair; those controls
are not extra acceptance cases.

The captured draft VBA PR and three other active VBA/Zotero branch heads retain
explicit work-in-progress/final-qualification markers. They were fetched and
preserved separately; exact heads and evidence are in the audit. No contributor
branch was overwritten or deleted.

The app identity change also required a concrete migration-document correction:
the old `quds_office_studio` support directory alone does not include macOS Mail
drafts/archive. [The release guide](../../release/macos-signing.md) now includes
the bundle-specific support directories and complete SQLite sidecars. Credentials
must be re-entered under the new app identity. These paths were checked against
host code and the pinned platform plugin; this is not a new installed macOS run.

## Publication and remaining scope

[Checkpoint identities](checkpoints.json) record seven incremental remote source
saves before the final evidence commit. Each published tree was checked against
the committed local tree; new incoming parent frontiers were retained. The
evidence descendant changes documentation only. Final publication must recheck
main, merge through the expected PR head, and compare the resulting tree and
product inputs with the qualified source. The work branch is retained.

The local gates establish source, protocol-fixture, host and rendering behavior.
Live-provider interoperability, installed Windows/macOS/mobile acceptance,
browser execution and native assistive-technology qualification remain separate.
The local draft store retains its previously documented native, unencrypted,
one-draft-per-account boundary.

The next workspace increment is repository-driven account/folder sessions and
persistent account switching, followed by unified views and durable command
reconciliation. Multiple/offline drafts, provider-side Drafts synchronization,
a visible queued outbox, undo-send/scheduling, full-account search, bulk rules,
rich composition and deeper Office/Calendar/People workflows remain ordered
continuations. This foreground foundation does not close M04W or full parity.
