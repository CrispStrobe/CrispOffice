# Mail membership recovery — local qualification

This increment adds **Check current location** to connected Mail activity for
uncertain Move/Delete receipts. It saves exact provider evidence without
replaying an operation, rewriting its historical outcome, or clearing its
cleanup protection. See the [feature contract and ordered continuation](../../roadmaps/mail/membership-recovery.md).

The implementation and integration corrections are preserved through source
checkpoint `ae07e54aebf2af0fb9d5838c0eff5c8928ca2942`. The final publication adds
this report and retained evidence. Test receipts bind actual source bytes before
and after each command; they do not rely on HEAD staying fixed while checkpoints
are published. GitHub Actions, workflow runs and status endpoints were not
queried or awaited. Local execution is the acceptance gate.

## Intake and history preservation

Initial main was `b13a170cdb5fd42b9a0f2c77d97c996caf5d0d7f`, including Mail
PR #363, Word #362 and Zotero #364. All 27 initial fork branch tips, four
upstream branch tips and 101 inspected recent PR heads were contained in that
baseline. Neither repository had an open PR at initial intake. The original
snapshot is preserved in [intake.json](intake.json).

The publication capture includes 30 fork branches and four upstream branches.
Two Office branches advanced while Mail was implemented. Their captured histories
were merged normally, retaining both sides of changelog conflicts:

| Captured work | Final included tip | Integration |
| --- | --- | --- |
| Word VBA table-cell prefixes, named Text arguments and portable String constants | `258ae2a5d73bccd293b4b423918fc3d7646e9bc4` | Native/compiler coverage, VM/Node agreement and late assertion checks |
| Zotero Roman note exchange and strict native-numbering guards | `89789360590b6dd0af0a378bfc257a3c4a18fc9c` | Engine/editor/Studio regression cohorts and an independently found XML exception fix |

All 34 captured branch tips and all 101 recent PR heads are ancestors of the
reconciled history. [final-intake.json](final-intake.json) records exact refs,
ancestry and merge checkpoints. This is an explicit branch snapshot; other
branches may continue independently afterward. Remote main is checked again
immediately before normal PR publication. No history was force-pushed, no
protections were changed, and no old superseded implementation was reapplied
without ancestry review.

During publication, main advanced through Word PRs #365 and #366 to
`8589e6f99baf4c2732f60a96ca68d44e6dea9935`. Merge checkpoint
`3fdcaf1e476be4f928aec3359e013302888ee889` preserves those histories and nine
validation/documentation artifacts; executable inputs are unchanged. The final
intake therefore records 103 PR heads including those two publication PRs.

Zotero PR #367 subsequently merged to main at
`253c7d2861bb65ccb6b844a8c4d162dabbce9ae5`. Merge checkpoint
`d85b1937fafd3f3583d01472a1eccded1726a5a6` preserves its completed evidence.
The only additional executable-file delta removes four redundant null assertions
from two Mail test helpers; production source and the guarded XML fix are
unchanged. A new 277-case host run and focused helper analysis/format checks
qualify those final bytes. The [publication supplement](publication-acceptance.json)
is the final composite acceptance record; earlier bundles remain immutable.
The intake now contains 104 recorded PR heads.

## Implemented behavior

- An optional `MailMembershipObserver` reports current membership independently
  of existing flag recovery. Exact identities, bounded metadata and well-formed
  UTF-16 are validated before persistence.
- Native IMAP verifies the original UIDVALIDITY and exact UID with metadata-only
  BODY.PEEK access. Gmail returns the explicit complete label set. Microsoft 365
  uses immutable message IDs and actual parent/Deleted Items folder IDs. EWS
  reads the original ID's parent when that identity remains available.
- Message absence is never inferred from a loaded list, an unknown cloud 404,
  a profile failure, or a Deleted Items lookup failure. Unknown IMAP/EWS moved
  identities do not establish a destination or historical success.
- Schema 14 stores one bounded latest observation per uncertain membership
  item, with a timestamp and journal revision. Transactional writes enforce
  account, repository owner, identical lease, exact identity, revision,
  persisted observation epoch and current-view guards. Failed writes and stale
  or cancelled work cannot publish new evidence.
- English, German and Arabic activity views expose explicit repeatable checks,
  Stop checking, timestamped evidence and uncertainty explanations. Merely
  opening cached history performs no provider work.
- Original receipts, uncertainty counts and cleanup protection remain intact.
  Cached browsing/sync memberships, bodies, flags, drafts, Outbox, archives and
  cursors keep their earlier observations until explicit refresh or sync.

## Mail acceptance

The accepted cohort contains **3,036 substantive test executions**, with zero
accepted failures, skips, runner errors or incomplete cases. These are execution
counts across native Dart/Flutter and Node, not a claim that the same behavior
executed on two platforms represents two distinct features.

| Accepted cohort | Passed | Scope |
| --- | ---: | --- |
| Complete Mail core, native Dart | 574 | Identity, policy, operation and new observation contracts |
| Complete Mail store, native Dart/SQLite | 1,061 | Migration, quota, rollback, reopen and native subprocess/crash fixtures |
| Native provider/transport cohort | 338 | IMAP, cloud, EWS, exact membership and existing provider regressions |
| Connected Mail host and activity UI | 277 | Six complete suites on the final integrated production source |
| Complete Mail core, Node | 574 | Actual dart2js execution |
| Cloud and unsupported JavaScript transport suites, Node | 160 | Actual Node execution; optional unsupported ports remain explicit |
| Portable store suites, Node | 52 | Codec, platform configuration, browser problem and archive manifest logic |
| **Total** | **3,036** | Final accepted executions; repeated diagnostic runs are excluded |

The [publication acceptance record](publication-acceptance.json) identifies the
final composite receipts and source/runtime applicability. It reuses the
unchanged native/Node cohorts and replaces only the counted host run. The
[original machine record](mail-acceptance.json) retains its earlier exact source
snapshot, commands and hashes without rewriting history.
Core native/Node tests contain two distinct parameter cases sharing one display
label; their different inputs and execution IDs are retained. The aggregate
counts completed executions and discloses that label collision.

Strict analysis of complete Mail core/store/transport passed. All **46** changed
Mail Dart files passed formatting with zero edits. The host's focused analyzer
log is retained with its original source-binding qualification. Publication
host tests also compile and execute the final integrated imports.

The final host run produces 12 screenshots. Compact English, German and Arabic
membership views were inspected at 390 × 844 logical pixels with 1.6 text scale;
exact identifiers, check times, uncertainty text and controls remain readable.
The screenshot comparison and visual-review receipts retain actual image hashes.

## Incoming Office integration and corrections

The captured Word implementation passed **1,564** native automation, shared
compiler, conformance and integration cases across 24 suites, plus strict
analysis. Its 78-case prefix corpus and 32-case paragraph corpus agree between
Dart VM and Node. The actual BAS example also agrees across runtimes, including
six operations, one revision, repeated DOCX/DOCM reopen, preserved unrelated
parts/VBA and late rollback. Those broad results remain tied to their recorded
captured source. The three Word suites changed by the final incoming commits
additionally pass **160** substantive tests against the final integrated source;
they verify the
stronger permission assertions and formatted test changes without rerunning
unaffected compiler and corpus work.

The final Zotero integration passes **417** substantive cases: 395 engine cases
across 12 suites, 14 editor cases and eight Studio export/save cases. Strict
analysis includes all changed native-numbering/parser production files and the
new regression suites. These checks preserve Roman note numbering, uncited-note
sequence accounting, citation ownership, ordinary DOCX save, source immutability,
unsupported-format refusal and native malformed-XML handling.

Integration review found three obsolete tests that rejected newly supported
Roman numbering. They now retain explicit alphabetic-format refusal and add
six positive configuration/lifecycle cases. Independent review also found that
`XmlPullReader` throws `XmlParseException`, while two numbering helpers caught
only `FormatException`. The narrow fix catches both known parse exceptions,
retains cached label fallback, and makes editable export refuse malformed
settings predictably. Mismatched-tag and unterminated-tag cases verify fallback,
absent exact automatic metadata, controlled refusal and unchanged source.

The [integration acceptance record](integration-acceptance.json) distinguishes
captured-source Word results, final changed-Word results, final Zotero results
and earlier diagnostics. Counts from overlapping or repeated cohorts are not
summed as unique tests.

The final Zotero Studio receipt excludes both changed Mail-only helpers and
remains fully applicable: all its recorded source inputs still match. The
publication supplement audits actual receipt membership instead of assuming
that unrelated test-support files affect every Studio invocation.

## Runtime, evidence and replay

Qualification uses the verified pinned Flutter **3.47.8**, Dart **3.13.7** and
Node **24.22.3** runtime. The official Flutter archive SHA-256 and 204 dependency
archive digests were checked. Offline dependency restoration used
`--enforce-lockfile`; the repository lockfile is unchanged:

`2231cacd6ab548da8f0d94020201a29f07f54a20c1682c0e8ae0079967b720eb`

The native Dart store run uses the actual native-asset hook mapping so subprocess
fixtures exercise SQLite through the normal native path. Direct recorded Dart
runner invocations avoid the ordinary `dart test` launcher's setup stall.

| Evidence | Contents |
| --- | --- |
| [mail-evidence.tar.gz](mail-evidence.tar.gz) | Mail raw JSONL/text logs, original receipts, source/runtime maps, runtime provenance, replay helpers and screenshots |
| [mail-evidence-manifest.json](mail-evidence-manifest.json) | Mail archive inventory, per-file hashes and packaging audit |
| [integration-evidence.tar.gz](integration-evidence.tar.gz) | Incoming Word/Zotero logs, receipts, source maps, runner scripts and retained diagnostics |
| [integration-evidence-manifest.json](integration-evidence-manifest.json) | Integration archive inventory and hashes |
| [publication-evidence.tar.gz](publication-evidence.tar.gz) | Post-main host logs, source/runtime snapshots and helper analysis; identical PNGs are referenced by digest |
| [publication-evidence-manifest.json](publication-evidence-manifest.json) | Final supplement inventory and hashes |

Original receipts and logs are retained without rewriting failures into passes.
Diagnostics include initial test-helper/import/legacy-schema-fixture corrections,
provider cancellation-fixture setup mistakes, the mixed-source initial Node run,
obsolete Roman guard expectations, and an isolated compiler/loader failure
under concurrent load. Subsequent source-bound runs resolve those failures.
Flutter's exact `test.startedProcess` daemon notifications are classified
separately from test events; all errors, skips, completions and terminal events
remain accounted for. Filesystem modification times are not used to prove run
chronology or source binding.

The archives omit SDK/package downloads and reproducible compiled build outputs;
the manifests and original command receipts explain retained inputs and outputs.
They contain no live-provider credentials. Protocol fixtures use local/fake
providers and do not depend on GitHub Actions.

## Boundaries and next milestone

This is current-state evidence, not causal proof that an earlier Move/Delete
succeeded. Missing original identities remain unavailable; they are never
matched heuristically to another message. No cache projection or mutation replay
is introduced. Live accounts, installed platform releases, browser persistence,
hardware power loss and installed Word/LibreOffice/Zotero interaction are outside
this local qualification.

The next Mail milestone is authoritative identity-transition capture (IMAP
COPYUID and EWS returned IDs) plus exact atomic source/destination cache
reconciliation. Durable bulk organization follows, then connected multi-account
navigation, richer search/conversations/rules and the remaining authoring,
Calendar/People and installed-provider work. The ordered roadmap remains the
[Mail parity continuation](../../roadmaps/mail/membership-recovery.md).
