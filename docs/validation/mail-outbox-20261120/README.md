# Durable foreground Outbox — local qualification

The source at **`ce9ff1c8b155c03a0e2707d6fc8b41b52e611a93`** is qualified by the completed
local gates below. This continuation adds a visible native Outbox for SMTP, EWS,
Gmail and Microsoft 365 after the reply/forward handoff at
`c3df77d01ea9df4846e18131e69160d858f174ac`. Account management remains a separately
owned lane. GitHub Actions were neither used nor awaited.

## Delivered behavior

- Production Compose **Send** durably freezes a message before invoking its
  provider. **Queue in Outbox** freezes it without sending. Both use the existing
  account-scoped SQLite owner and atomic draft-revision handoff.
- Frozen MIME, Message-ID, Date, boundaries, attachment bytes and the complete
  transport envelope survive retries and reconnects. Bcc remains in the envelope
  and is excluded from composer MIME headers.
- The visible Outbox exposes saved subjects, sender, recipients, attempt count
  and states, with explicit send/retry, safe cancellation and confirmed removal
  of eligible terminal local records. Labels and feedback cover English, German
  and Arabic.
- A durable attempt marker precedes each provider call. Interrupted or otherwise
  ambiguous acceptance becomes uncertain. Every uncertain retry requires fresh
  acknowledgement; a later rejection cannot erase an older possible acceptance.
- Opening, refreshing, reconnecting and recovering never send queued mail.
  Stable account checks and current-session guards protect provider invocation.

The [workflow and contracts](../../roadmaps/mail/outbox.md) describe exact
transitions, native/provider boundaries, quotas and follow-up work. The
[independent review](review.md) records the source identities and review findings.

## Completed qualification

| Final cohort | Distinct cases | Test files | Result |
| --- | ---: | ---: | --- |
| Core state machine and SQLite store | 172 | 13 | Passed |
| Native SMTP/submission library | 72 | 11 | Passed |
| Incoming Word layout/cache reconciliation | 20 | 3 | Passed |
| Combined Studio Mail workflows | 610 | 25 | Passed |
| **Combined distinct total** | **874** | **52** | **Passed** |

Every accepted test process exited zero and had one successful terminal machine event,
with zero failed, skipped, errored, incomplete or protocol-invalid cases. Strict
event audits exclude framework loading pseudo-tests and reject hidden failures;
case identities are checked for duplication. The exact commands, individual case
names and original JSONL/stderr bytes are retained in the evidence archive.

The original Studio audit rejected three existing unsafe-filename case names
because Python `str.splitlines()` also treats U+0085, U+2028 and U+2029 as line
breaks. Those characters are valid inside JSON strings; the original reporter
records were correctly LF-framed. The original failed audit summary and driver
exit 1 remain preserved. A separate strict LF-framing re-audit of the unchanged
bytes admitted all 610 cases with every event-integrity rule intact. The
repository auditor was corrected and separately regression-tested against legal
Unicode separators and genuinely malformed records: **48 Python test methods
passed**, counted separately from the 874 product/integration cases. The newly
added regressions fail with the old framing and pass after the fix; both original
results are preserved. No product test, log byte,
failure or skip was removed to obtain acceptance; no product rerun was necessary.

The Studio cohort covers the five new Outbox suites and existing compose, draft
autosave/storage, native/EWS/cloud hosts, attachments, forwarding, replies,
recipients, threading, operations, lifecycle, sessions, workspace navigation,
accounts, account catalog and selected-store integration. An independent check
requires the exact 25 expected suite paths, not only a matching file count.

All **24 changed Dart files** passed `dart format --output=none
--set-exit-if-changed` with zero changes and `dart analyze --fatal-infos
--fatal-warnings` with no issues. This includes 21 Outbox implementation/test/helper
files and three incoming Word files. `git diff --check` also passed. The checked
source did not change during these commands.

Focused successful runs (34 native draft/Outbox adapter cases, 18 submission
cases, 15 dialog/native/EWS cases and four cloud cases) are overlapping supporting
evidence. They are **not added** to the final total. Failed development harness
attempts, probes and their partial passes are retained and excluded from
acceptance; see the archived inventory and development notes.

## Runtime and source identity

The runtime is the repository-pinned **Flutter 3.47.8 / Dart 3.13.7**. The official
SDK archive checksum and all 135 hosted package archive checksums were verified;
`dart pub get --offline --enforce-lockfile` succeeded. Dependency manifests and
the lockfile were unchanged. The setup receipt contains the original archive
URLs, versions, hashes and command results. No package or SQLite implementation
was substituted for testing.

- Official SDK archive SHA-256:
  `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
- Actual SQLite native binary SHA-256:
  `0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`.
- Pure-Dart source fingerprint (640 files):
  `9efc8714efdbb28673f1aeb8858b587f2acb4f6e30719469230d4abc5498e318`.
- Studio source fingerprint (2,638 files):
  `fd798ee88f8c7da5050a40775392f0f977780d545f0c65faa90f6ebb959122fe`.
- Qualified Git tree: `49d07c3b264ed4b47cf3eb0999ac3f8c5c2ae01f`.

Before/after source manifests agree for every accepted cohort. Each of their
2647 distinct source inputs was also compared with the
actual Git blob in the source checkpoint. Product and test inputs also match the
final working file. The sole later change among manifested inputs is
`tools/mail/check_store.py`, the separately qualified JSONL auditor correction;
its original hash remains preserved. Its regression test is also included in
publication. The earlier
pure-Dart gate records its then-current dirty HEAD as context; its exact relevant
file hashes, not that contextual HEAD, bind the result to this checkpoint.
The time-specific earlier UI helper supplement is preserved but is superseded by
the complete Studio source manifest for final UI qualification.

Runtime manifests inventory selected SDK binaries, configurations, launchers and
dependency evidence; they do not claim a complete transitive runtime-file closure.
The actual Flutter-generated native-assets map, loaded SQLite binary and engine
frontend snapshot were additionally captured during the Studio run and verified
unchanged afterward. The timing of that supplement is explicitly recorded.

The native adapter suites use real file-backed SQLite and exercise reopen,
revision conflict, ownership and recovery. Widget host suites use the production
repository/adapter with synchronous in-memory SQLite and controlled provider
fakes. Bounded fake-clock pumping handles Drift operations and teardown without
changing production behavior. SMTP suites additionally exercise their recorded
local transport fixtures. No live-provider or installed-platform claim follows
from these results.

## Visual review

The compact 700 × 660 fixture was rendered with bundled Tajawal and MaterialIcons
fonts. English, German and Arabic completed without layout exceptions; manual
inspection confirmed readable controls, fitted text and Arabic RTL layout.
These are actual widget fixture captures, not an installed desktop application:
[English](visuals/outbox-en.png), [German](visuals/outbox-de.png),
[Arabic](visuals/outbox-ar.png).

## Intake and incremental remote preservation

The [initial inventory](intake-initial.json) captured 26 branch heads and the 50
most recently updated PRs before implementation. The
[initial dispositions](intake-dispositions.md) distinguish already incorporated
history, completed unpublished work and active owner continuations. The
[final inventory](intake-final.json) and [final reconciliation](intake-final.md)
record the later live refs and independently deleted branch names.

Two completed incoming continuations were reconciled before implementation:
performance evidence at `baf6d1bc53b611e9fb37082ca69c409e5f8d6381` and the Word
frame-cache correction at `c9cbeb1248d6b5f088d1084a8c113a743aa7a77f`. The latter
clears stale paragraph breaks after frame/full-layout changes and is qualified
by the 20-case Word cohort. Later main
`b42eca1db058f0def247b86c2f15dea90c11b4e8` published performance PR #247;
reconciliation added its ancestry with zero source changes.

Active account, Zotero and VBA continuations remain with their owners. Their
already incorporated history remains intact. No owner branch was force-updated
or deleted by this work.

| Remote checkpoint | Preserved increment |
| --- | --- |
| `d64d62b502bc5e09409ffc2d5eb75e93d3ae921f` | Scope and initial intake |
| `c824caafce175ee37cff67fe778396779ce76b6a` | Completed incoming reconciliation |
| `68ccdc377b4402ad1767e8739cac8cf306443b8a` | Core/store and foreground Outbox implementation |
| `bda00b32911bcab4e748851d89af0dbdfc886d39` | Cleanup safeguards, initial tests and contracts |
| `ce9ff1c8b155c03a0e2707d6fc8b41b52e611a93` | Frozen final source, provider/UI fixtures and latest main ancestry |
| `ee849a13a1b8164ef52203422daf10531a0c9fb2` | Final intake and separately qualified JSONL auditor correction |

These checkpoints are saved on `work/mail-outbox-20261120` using ordinary
non-forced updates. Later publication commits contain the separately qualified
auditor correction, documentation and evidence; the qualified product source
remains the checkpoint above. The PR merge
and remote-main readback are reported in the PR and task completion record.

## Evidence files

- [Machine acceptance summary](acceptance.json): final counts, audits, source
  checkpoint and archive checksums.
- [Archive member manifest](evidence-manifest.json): SHA-256 and size of every
  preserved original file and each archive.
- [Accepted runs and provenance](evidence/accepted-runs.tar.gz): original final
  commands/events/stderr, strict audits, before/after source/runtime manifests,
  selected runtime supplements, SDK/dependency receipt, reproducible drivers,
  full run inventory and development notes.
- [Development and overlapping supporting runs](evidence/development-and-supporting-runs.tar.gz):
  original rejected/diagnostic/overlapping logs, never used to inflate acceptance.

To inspect the records, extract the archives into a local directory. Their member
paths are relative to the original validation runtime; exact original commands
retain absolute paths as provenance. Re-running in another checkout requires
adjusting that root and using the recorded pinned dependencies.

## Remaining release and parity work

The Outbox is native, local and foreground-only. Reconnect the same scoped account
to open it after restart. It does not provide an offline account browser,
background send, scheduling, undo-send, arbitrary imported/binary MIME, an Outbox
body preview/editor, server Drafts or message recall. Acceptance by the sending
service is not final delivery, and uncertain retries can create duplicates.

The next bounded increment is reviewable preview/export, edit-copy and explicit
resolution of uncertain records without resending, followed by undo-send and
scheduling. Provider-specific Sent reconciliation, detailed SMTP recipient
outcomes, rich HTML authoring, signatures/templates, multiple drafts and
live-provider/installed-platform qualification remain open in the
[ordered parity roadmap](../../roadmaps/mail/README.md).
