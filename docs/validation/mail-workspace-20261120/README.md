# Mail foreground workspace — final accepted integration

This continuation delivers shared foreground mailbox navigation across native
IMAP/SMTP, Exchange EWS, Gmail and Microsoft 365, reconciles concurrent Office
main, and records local acceptance without waiting for hosted CI. **M04W and
full Outlook/Thunderbird/eM Client parity remain open.**

The qualified product source is remote checkpoint
`01290ceed6f9163023ce8f27bb74033f088b62e4`, tree
`413a8ebc8f66c5b95584710aab7d8bb6fcc431fc`. It preserves main
`860c807bfd1385899eed130abfb8940f95bda113` and the Mail implementation.
The subsequent main `33190e50cae486be362eedb5fa687dd9c82b0c51` adds exactly
two evidence documents and is also incorporated. Its product/configuration
trees are identical to `860c807b`. The final evidence descendant retains the
exact qualified product source on `work/mail-workspace-20261120`.

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

## Final accepted local selection

| Mail cohort | Suites | Passed | Qualification |
| --- | ---: | ---: | --- |
| Mail core VM | 6 | 54 | Exact unchanged transitive inputs |
| Mail transport VM | 19 | 402 | Exact unchanged transitive inputs |
| Mail transport Node boundary | 3 | 6 | Exact unchanged transitive inputs |
| Mail UI Flutter | 5 | 52 | Exact unchanged transitive inputs |
| Complete Studio Mail and saved-Mail selection | 30 | 707 | Fresh run on `01290cee` |
| **Mail total** | **63** | **1,221** | |

| Other accepted selection | Suites | Passed |
| --- | ---: | ---: |
| Reconciled Office engine | 12 | 217 |
| Reconciled Office editor / Flutter | 11 | 83 |
| **Office total** | **23** | **300** |
| spaCy distribution and grammar planner | 2 | 36 |
| Native app paths | 1 | 2 |
| Shared Studio theme | 1 | 2 |
| **Other integration total** | **4** | **40** |

The accepted selections contain **1,561 cases across 90 distinct suites**, with
**zero failures or skips**. No suite overlaps, hidden skips, duplicate completion
IDs, missing accepted case metadata, unexpected suites or unsuccessful runner
completions were found. Earlier failed, repeated and superseded runs are excluded.

Formatting and strict Mail analysis passed, including fresh Studio analysis
after main reconciliation. Strict analysis of 13 affected/relevant Office files
also passed. Whitespace checks cover changes relative to incoming main; an
inherited raw `.diff` artifact retains its original patch whitespace verbatim.

The [independent review](merged-01290cee/main-acceptance-review.json) recounts raw
events, exact suite selections, case records and output hashes. The
[fresh receipt](merged-01290cee/receipt.json) retains commands and results;
[main-office.md](main-office.md) provides the separate Office qualification.

## Source continuity and attribution

The final merged run captured **4,474 product/configuration inputs and seven
runtime/configuration pins**. Every before/after entry matches, and independent
review rehashed the current files. Its aggregate SHA-256 is
`591f7c12cb20ca70b08259300198a5a8cfb31e112aa2780bd6332e87e9785d93`.

The 514 core/transport/UI cases were accepted at `740f3e24`. Their resolved
local dependency closure contains **475 captured inputs** matching both the
accepted hashes and merged Git blobs/modes, without additions/removals. It
contains no Office package. The two native-path cases retain their test,
implementation and dependency inputs: nine entries. These sets contain 480
distinct repository inputs. All seven pins match. The
[continuity proof](main-mail-continuity.json) records exact paths and hashes.

Studio imports the changed Office source, so all **707 cases** were rerun after
reconciliation. The spaCy planner imports the engine barrel, so its **36 cases**
were also rerun. Two theme cases qualify incoming finite-button behavior. The
**300 Office cases replace** the overlapping 137/116-case stages. That gate
captures **2,204 unchanged inputs** and seven pins; 2,203 tracked inputs match
the published checkpoint, with local package configuration accounting for one.

The [initial stage](initial-acceptance.md) preserves the first Studio attempt:
706 passes and one stale assertion expecting **No messages** after an unmatched
query. The corrected test expects the distinct no-match notice, asserts that
the empty-folder notice is absent, and retains empty-sender/no-exception
coverage. Only the final successful 707-case Studio run is counted here.

Independent review also found that Python `splitlines()` split three valid JSON
test names containing Unicode separators. The runner now splits only at physical
LF and rejects missing case metadata. The rejected first attempt's artifacts
remain unchanged; every accepted final name/suite ID matches its raw events.
Office evidence retains negative controls and the preflight duplicate
`extGStates` argument found during reconciliation. That duplicate was corrected
before the published source and final gate. No product input changed during
either final Office or Studio run.

## Incoming work

The [initial reference audit](remote-refresh.md) captures 22 fork branches,
236 PR heads and four upstream heads. Upstream heads were already ancestors.
Historical ODS patches remain equivalent; ODT's 37 aggregate paths match its
accepted squash and the Office-union tree matches its landed squash.

Ready CrispOffice identity, Android grammar/workflow and recent PPTX work was
integrated with original ancestry. During final publication, concurrent main
itself incorporated the previously deferred VBA/Zotero feature heads, earlier
Mail work, fonts, geometry and shared Studio changes. That published main was
preserved and reconciled; affected acceptance selections were replaced.

The [main-advance audit](main-advance.md) supersedes the earlier deferred-head
dispositions. PR #227 and PR #236 are merged; the captured VBA and Zotero feature
heads are ancestors of main. Aggregate head
`b9e4f1d4bc691714f68e3685dbf729b09ccb0449` remains a retained non-ancestor with
three unique reconciliation merge commits. Their resolutions are not declared
tree-equivalent. No contributor branch was overwritten or deleted.

The `33190e50` evidence-only advance preserves other authors' native VPS and
portable reports with exact source/platform attribution, failed attempts and
follow-ups. Their overlapping counts are not added here. This continuation
queried or awaited **no GitHub Actions, workflow run, check or commit status**.

The identity change also needed a macOS migration correction: copying only
`quds_office_studio` omits Mail drafts/archive. The
[release guide](../../release/macos-signing.md) now includes bundle-specific
support directories and complete SQLite sidecars. Credentials require re-entry.
Paths were checked against host code and the pinned platform plugin; no new
installed macOS run is claimed.

## Reproduction and evidence

Execution used genuine **Flutter 3.47.8 / Dart 3.13.7**, the unchanged lockfile
and 195 archive-verified hosted packages. SQLite 3.54.1 and real FTS5 readiness
were verified. [Runtime provenance](runtime/README.md) records setup and hashes.
The seven pins are Dart, Flutter tester, Flutter tools snapshot, SQLite,
package configuration, package graph and the actual `package:test` entry point.
This proves those local inputs, not a completely hermetic operating system.

With the recorded runtime active, the final fresh host command was:

```bash
python3 docs/validation/mail-workspace-20261120/run_acceptance.py \
  --attempt merged-01290cee \
  --only format --only studio-analyze --only studio \
  --only incoming-spacy --only studio-theme
```

Use a new attempt name: evidence cannot be overwritten. Omitting `--only` runs
the complete current selection. Receipts retain exact arguments, directories,
durations, exit codes and output hashes. Flutter runs use
`--no-pub --concurrency=1`; VM/Node use the actual pinned test runner. The exact
23-suite Office commands and capture runner are in `main-office.md`.

JSONL, case lists and input manifests are gzip-compressed without changing
bytes. Each attempt's `compressed-evidence.json` maps original/stored filenames
and both hashes. Earlier stages remain under `final-740f3e24/` and
`studio-44abcfa1/`, with their original attribution.

One startup hit disk capacity before creating its directory; zero cases began.
[Cache preparation](cache-preparation.json) records removal of reproducible
caches and duplicate older validation working copies, retaining Git objects,
refs, current evidence and product source. Older validation folders remain
sparse locally; `git sparse-checkout disable` restores their working copies
when capacity permits. Accepted product inputs remained unchanged.

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

Next are repository-driven account/folder sessions, persistent account switching
and unified views with durable command recovery. Multiple/offline drafts,
server-side Drafts, visible queued outbox, undo-send/scheduling, account-wide
search, bulk rules, rich composition and Office/Calendar/People remain ordered
continuations.
