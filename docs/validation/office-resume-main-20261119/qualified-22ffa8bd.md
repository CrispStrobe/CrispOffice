# Office continuation and main reconciliation — 19 November 2026

## Result and qualified source

The supplied continuation is reconciled with current main and all implementation
heads in the fixed reference capture. The work is delivered through
[PR #192](https://github.com/CrispStrobe/quds_office_suite/pull/192), with incremental
remote checkpoints preserving the integration and its evidence.

The final qualification executed on remote source
[`22ffa8bdcc11e5e10eb37f2326f832066f609a08`](https://github.com/CrispStrobe/quds_office_suite/commit/22ffa8bdcc11e5e10eb37f2326f832066f609a08),
tree `f538a4fbe7f32fb778f34849d2added580202dfe`. The baseline is
`b070e228a749e22cc8ce2098029a76ab5fb8eccb`. Publication adds reports and evidence;
exact source continuity is checked before merging and again against remote main.

**Fresh results: 1,564 successful Dart/Flutter test
executions, 960 distinct case identities (test file plus test name),
and 21 separate Python controls.** There are no failed, skipped or unfinished
cases in the accepted reporters. No historical, development, rejected or
superseded run contributes to these totals.

## Captured histories

The supplied unfinished handoff at `a4b73fe40387d62c27477bb640f14a2694d031d8`
was already an ancestor of the captured main. Its earlier evidence remains
attributed to that source. This continuation retains main's functional
IMAP/SMTP Studio client, Arabic T1/T2 rules and native morphology integration.

The final bounded capture ended at **11:18:49 UTC / 12:18:49 CET on
19 November 2026**. It contains **465 actual source references**:

| Reference category | Count |
| --- | ---: |
| Fork branches | 231 |
| Fork pull-request heads | 193 |
| Fork tags | 17 |
| Upstream branches | 4 |
| Upstream pull-request heads | 4 |
| Upstream tags | 16 |

The [actual integrated graph audit](final/reference-audit-final-integrated.json)
accounts for **437 ancestors and 28 historical equivalents**, with zero
unaccounted references. All 14 exact equivalence proofs were recomputed using
complete-tree identity or the complete changed-path mode/type/blob set at a
retained ancestor. Of 477 raw advertisements, two HEAD aliases, seven peeled-tag
rows and three GitHub-generated PR merge previews are excluded from source counts.
Later unmerged branch activity is outside this fixed capture; remote main is
checked before the final merge.

These five captured implementation heads are retained through normal merges:

| Captured branch | Head |
| --- | --- |
| `codex/office-main-integration-20261119` | `c63558c0b3bc713361771cc29b0d89ecf2fa09a7` |
| `codex/office-main-sync-20261119` | `1b6d280b6ed41a1e01736a88f6d02431057c8611` |
| `codex/office-mail-continuation-20261119` | `3119a4598e61f061e7b7633ea4a352d841332b9e` |
| `codex/office-continuation-20261119` | `e80beb2ed2fe70397a5a8fff5c9e908b04862f78` |
| `codex/office-finish-20261119` | `2abf5d264e5065772fc4ca05c7cab6d34256ab9d` |

The first concurrent Mail checkpoint described planned saved-reader work. The
later two supplied the actual reader implementations. Integration was based on
those exact trees and their meaningful tests.

## Integrated behavior

### Mail

The account-free saved `.eml` reader is restored beside the session-only network
client. `StudioSavedMessageDialog` is the shared implementation;
`StudioSavedMailDialog` remains a compatibility name. The visible localized
Open message action reaches that reader, and both incoming test suites remain
runnable. The [legacy test record](review/legacy-saved-mail-test.md) explains how
all five historical reader cases were restored while preserving current network
reader disposal and pending-response tests.

Connection setup captures its credentials, guards pending-client identity,
excludes nonselectable INBOX entries, and ignores stale completion after
reconnect or dismissal. Reader replacement retires the old controller after
its widget detaches. Incoming and outgoing transports can be aborted
independently of high-level disconnect.

SMTP submission finishes before the Sent-copy append begins. The transaction
preserves the submission error and stack it receives and never appends a Sent
copy after submission failure. Errors reported by filing or cleanup after a
confirmed submission produce `MailSendPostSubmissionException`; Studio displays
Message sent with the applicable warning. It does not retry the submission.

Independent review also found that the inherited SMTP abort closed the socket
without completing its pending command. The repair fails that command before
socket shutdown, releasing a send and the disconnect queued behind its outgoing
lock. The [regression receipt](review/smtp-abort-development.json) records an
expected timeout with the baseline implementation and a pass with the same
new harness after repair. It explicitly distinguishes the new harness from an
unchanged historical source tree. The final formatted test is included in the
accepted frozen gate.

### Word and proofing

The Word controller retains its existing two-slot language command by default.
Hosts can explicitly select `activeLanguageOnly: true` to update or clear only
the slots used by the selected fragment. Pure normal-script text uses `w:val`,
Arabic/Hebrew text uses `w:bidi`, and an unmarked mixed fragment can use both.
Explicit complex-script formatting retains precedence. Inspection clips each
run to the actual selected text and reports mixed languages when appropriate.
Low-level reset defaults remain unchanged. Tests cover inactive metadata,
unselected text, live inheritance, undo/redo, no-op history and DOCX save/reopen.

The integration also preserves these fixes:

- Combining maddah and hamza retain spelling meaning during Arabic phrase
  comparison; UTF-16 mappings and Unicode token/identifier boundaries remain
  accurate. Main's newer rule tables and morphology wiring are retained.
- Distinct findings from the same provider remain separate during cross-provider
  deduplication. Word runs with different complex-script metadata do not coalesce.
- A cancellation requested by the last dictionary-download progress callback is
  honored before committing the installation.
- Review distinguishes scheduled, checking, paused, unchecked, partial and
  completed coverage. Localized controls remain reachable at 390 pixels with
  1.4 text scaling, with coverage around the 820-pixel layout transition.
- Studio Settings, Notes, comments and Zotero fixtures use the current public
  settings flow. The previously missed Zotero helper call is corrected.

The AyaSpell builder's bundling/upload logic and pinned upstream source
identities are preserved. Its generated card wording and corresponding
assertions reflect the integrated host behavior.

## Fresh qualification

The committed [native plan](native-plan.json) selects 47 suites:

| Native/VM group | Suites | Successful cases |
| --- | ---: | ---: |
| Engine: Arabic, proofing and Word | 13 | 645 |
| Word editor language controls | 3 | 55 |
| Hunspell cancellation and synthetic native lifecycle | 6 | 38 |
| Mail submission, SMTP state, framing and connection lifecycle | 6 | 46 |
| Studio Mail, Review, Settings, Notes, comments, Zotero and PDF | 19 | 176 |
| **Native/VM total** | **47** | **960** |

The [Node plan](node-plan.json) runs nine portable engine suites and passes
**604 executions**. All 604
Node case identities repeat native cases; they increase execution count without
inflating distinct-case count. Across platforms there are
**56 suite-platform runs and
47 distinct suite paths**.

Strict `dart analyze --fatal-infos --fatal-warnings` and format checks cover all
**49 changed Dart paths**, including the vendored Mail/SMTP source and tests.
Whitespace checks pass. The independent audit verifies complete raw event
streams, terminal success, exact planned suite coverage, loading/setup/teardown
outcomes, diagnostic exclusions and unique case identities within each run.

The separate Python gate passes **17 AyaSpell builder controls and four
Hunspell packaging controls**. Its independent audit derives case names from
the committed test ASTs and checks them against verbose raw logs. It verifies
all 15 control-source inputs and the Python executable hash; individual standard
library files are not separately fingerprinted.

The native gate binds 5,177 source and
11,171 runtime records; the Node gate binds
5,177 source and 11,166 runtime
records. Before/after manifests, Git HEAD, the index and tracked worktree remain
unchanged. The independent audit rechecks Git object identities and live hashes,
including shared runtime inputs across the two phases.

Runtime preparation verifies the official Flutter 3.47.8 / Dart 3.13.7 archive,
176 hosted package archives, locked workspace resolution and a real SQLite/FTS5
smoke test. Three separately compiled C ABI libraries exercise native ownership
and lifecycle counters. They are synthetic fixtures, not real dictionaries.
Node execution and VM tests of web-host code do not establish browser acceptance.

## Evidence and preserved attempts

The [final archive](final/evidence.tar.xz) contains raw and compressed reporters,
stderr, case/error inventories, source/runtime manifests, Python logs and the
independent audits. Its [member index](final/evidence.index.json) records
74 members, 903,816 archive bytes and SHA-256
`be3782668570ffa4736dea7d114bb085af79b1ec5a6037a3c8507f103a92e0d4`. Every member is reopened and checked for exact name, size
and digest.

- [Final archive integrity audit](final/archive-independent-audit.json)
- [Final native/Node audit](final/independent-audit.json)
- [Final Python audit](final/python-independent-audit.json)
- [Historical artifact preservation](final/evidence-preservation.json)
- [Saved historical qualification audit](review/saved-evidence-independent-audit.json)
- [Preparation archive audit](review/preparation-archives-independent-audit.json)

All 118 non-README validation files from the original two incoming deltas remain
exact. The historical integrity review verifies ten archives and 828 members;
preparation review verifies another two archives and 92 members. The original
1,285-execution / 979-distinct-case host run and 1,026-execution /
634-distinct-case sync run retain their original sources, `9833831a` and
`5c18db77`. They are not added to this qualification.

The [rejected `409258f9` attempt](attempt-409258f9/README.md) retains its 797
visible successes and the excluded loading failure caused by the obsolete
Zotero helper. The [superseded `79e7772` gate](superseded-79e7772/README.md)
passed 928 selected native cases and 21 Python controls before the SMTP abort
gap was identified. Neither contributes to final-source totals. The
[development archive](review/development-evidence.index.json) also preserves
focused attempts, the corrected RawTooltip fixture and the SMTP red/green
comparison; those runs are diagnostic evidence only.

## Acceptance boundaries

This continuation establishes the selected local integration gates and exact
source/evidence preservation. Actual offline browser behavior, persistent browser
storage/Web Locks/quota, installed-platform Studio/IME behavior, live external
Mail accounts, Zotero/Word/LibreOffice interoperability and independent linguistic
review retain their separate acceptance requirements.

The Studio client remains session-only. The durable repository-driven mailbox
workspace, persistent credential-vault hosts and queued/reconciled SMTP sending
remain separate roadmap work. No real user mail or external account credentials
were used by these controls.

No GitHub Actions queue, run, job or status was queried, dispatched or awaited.
Local source-bound evidence is the qualification for this continuation.
