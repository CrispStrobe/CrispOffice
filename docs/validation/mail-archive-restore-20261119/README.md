# Portable mail archive restoration

Scope date: 2026-11-19. Repository: `CrispStrobe/quds_office_suite`.

This increment restores CrispOffice bulk EML exports with their original
source/folder/source-message provenance. It builds on PR #205 and integrates the
current GUI, VBA control-flow and macOS branch frontier before new mail work.

## Implementation

- Read-only manifest inspection and a deliberate Studio preview/start workflow.
- Cross-profile restoration into the existing destination archive owner.
- Exact length and SHA-256 checks before MIME parsing, plus verification that
  the parser retained those original bytes.
- Atomic storage of an original, index and every recorded provenance entry.
- Idempotent reruns with distinct saved, duplicate, failed and origins-added
  counts; bounded failure details and content-free progress diagnostics.
- Cancellation and source-change checks that retain confirmed earlier work.
- Bounded manifest/input handling and observed symlink/ancestor rejection.
- English, German and Arabic controls, with narrow/RTL layout coverage.

The workflow and default limits are documented in the
[archive guide](../../roadmaps/mail/archive-search.md).

## Reconciliation

The starting `main` was `0c29b5d8a0a92148dcd95f3282b4d43c462be20d`.
The integrated frontier was `df7f4b4c8df63cbcf80d9087d06707d166a2c678`,
which contains the current heads of PR #206, PR #207 and the macOS integration
branch. [reconciliation.json](reconciliation.json) records the 235-reference
snapshot: 24 fork branches, all 207 PR heads and four upstream branch heads.
There are 212 fresh ancestor checks and 23 unchanged historical-equivalence
references using 14 previously recorded exact-SHA proofs. The reuse of those
historical proofs, including unavailable original PR-only commits, is explicit.

The [final reconciliation refresh](reconciliation-final-refresh.json) includes
the completed publication of PRs #206, #207 and #208 through incoming `main`
`cf59efa99232a3fd26cf21ce7f2382402e576f9b`. The refresh accounts for **225 external
references: 202 ancestors, 23 unchanged historical-equivalence references and
zero unaccounted references**. It excludes this increment's own branch. Eleven
subsequently deleted branch heads were already ancestors and remain preserved
in history. The late incoming delta contains seven commits and 77 validation
documentation paths; it changes no product, test or configuration input.

## Accepted local qualification

**1,640 test executions passed, zero failed and zero skipped**, across **90
distinct test files and 10 cohorts**. All **22 required commands** passed:
10 test commands and 12 analysis, formatting, whitespace, JavaScript or shell
syntax commands. The [combined acceptance receipt](acceptance.json) derives
these totals from the [final mail receipt](final/receipt.json) and
[incoming-work receipt](incoming/summary.json). No GitHub Actions result or wait
contributes to acceptance, as requested by the repository owner.

| Accepted cohort | Passed |
| --- | ---: |
| Mail core | 54 |
| MIME parsing and portable import | 84 |
| Native mail store, search, export, import and restoration | 508 |
| Portable store manifest and declared browser boundary on Node | 9 |
| Shared mail UI | 33 |
| Studio mail workflows | 388 |
| Engine macros, VBA procedures and bounded control flow | 269 |
| Incoming engine branding, ODS/revision fidelity and structural atomicity | 216 |
| Editor PDF save/surface and Review controller/dialog | 52 |
| Studio desktop menus, ribbon preferences/customization and File lifecycle | 27 |
| **Total** | **1,640** |

The final mail run uses committed source
`0c77b3488eb534868a7f98271ba2923d06759b8d` (tree
`8e21cf2370f18ee6f02836cb6b465799a6512004`). Its before/after inventories match
for **4,441 source inputs, 9,298 dependency inputs and 1,108 runtime files**.
The root package manifest and lockfile remain unchanged. Qualification uses
the packaged SQLite 3.54.1 native asset with FTS5 and SHA-256
`0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`;
there is no temporary native-library override or dependency resolution during
the accepted runs.

Incoming checks began at formatted checkpoint
`358544a48466c942873a4718a87fa9d1c2be11f7`. Their relevant product/test, example
fixture, executed-harness, dependency and SDK identities match the final source.
The intervening commit only corrects the validation selection and updates
documentation. The [incoming report](incoming/README.md) retains exact command
arrays, per-case results and raw logs.

Strict analysis passes for 82 targets. Canonical formatting passes for all 72
changed Dart files since the previous milestone. Eight inherited GUI/branding
sample files needed the pinned formatter; [format-reconciliation.json](format-reconciliation.json)
proves each resulting file is exactly the formatter output for its previous
bytes. Incoming checks were rerun after those changes. Four genuine JavaScript
builds run in Node and assert their full expected outputs: macros, VBA,
procedures and control flow. The macOS build script passes `bash -n`.

The new regression fixtures cover atomic provenance rollback, corruption,
missing originals, changed manifests, codec substitution, symlink replacement,
overlap exclusion, cancellation around commit, different-profile round trips,
and a real importer `SIGKILL` followed by owner recovery and repeat restoration.
Studio also exercises the genuine MIME codec and native SQLite after the old
source archive database has been removed.

The [independent audit](independent-audit.json) replays the machine-reporter
events without trusting the acceptance totals, checks case and file coverage,
verifies raw-log hashes, rehashes the bound inputs and compares the published
screenshots with the accepted-run output. The audit script is preserved in
[audit-mail-validation.py](audit-mail-validation.py).

### Visual review

Twelve captures come from actual Flutter widget rendering with synthetic local
archive fixtures. English, German and Arabic restore previews/results were
inspected, including the narrow Arabic layout and explicitly ordered UTC date.
These are the exact accepted-run PNGs, copied unchanged into [screenshots/](screenshots/).

| Preview | Result |
| --- | --- |
| [English](screenshots/archive-restore-preview-en.png) | [English](screenshots/archive-restore-result-en.png) |
| [German](screenshots/archive-restore-preview-de.png) | [German](screenshots/archive-restore-result-de.png) |
| [Arabic, narrow RTL](screenshots/archive-restore-preview-ar.png) | [Arabic](screenshots/archive-restore-result-ar.png) |

### Evidence and reproduction

[run-mail-validation.py](run-mail-validation.py) records the complete accepted
selection in [final/selection.json](final/selection.json), exact argument arrays,
stdout/stderr, per-test cases and compressed input inventories. Runtime setup,
checksums and readiness logs are under [runtime/](runtime/). With that runtime
available, invoke the runner with `--repo`, a fresh `--output` directory and
`--expect-head` set to the source commit above. Incoming commands and their
reproduction instructions are in [incoming/README.md](incoming/README.md).

[Earlier attempts](attempts.md) remain separately available. The first broad
format preflight executed no tests. The next attempt included a native-only
SQLite query suite in the Node selection and also observed temporary VBA CLI
fixtures from a concurrent check; that attempt is excluded in full. The
corrected final mail run began after those incoming fixture processes ended.
Independent adversarial fixture corrections and superseded incoming runs are
also retained, with no duplicate contribution to accepted counts. Test totals
count a case separately when deliberately executed on VM and Node; file totals
deduplicate paths. Previous milestone totals are never reused.

## Publication

The implementation, tests, harness and accepted evidence were saved incrementally
to `codex/mail-archive-restore-20261119` with expected-head, non-forced updates.
Evidence checkpoint `1a99845fe628c9e539d4bca7e7c586c5616da267` has tree
`50a2e5a00cb30f81036fa29311c3fcf6bc24da35`, verified against the local staged
tree before publication. The [publication check](publication-check.json) rehashes
all 4,441 accepted source inputs and checks their published Git blobs, incoming
main ancestry and unchanged audit/receipt identities. The final checkpoint adds
only publication documentation. [verify-publication.py](verify-publication.py)
can repeat the check against the final PR head or merge commit.

The [bounded publication-frontier review](publication-frontier.json) records
two newer, independent draft PRs: #210 (VBA arrays/For Each) and #211 (Layout and
theme). They began substantive development after this milestone's product
freeze and were still undergoing qualification at the recorded cutoff. Neither
is a prerequisite for archive restoration. They remain separate work; the
accepted GUI/VBA/macOS frontier through `cf59efa9` is included in this milestone.
The remote main and final PR head are checked again immediately before merging
PR #209, and the resulting merge tree is compared with the publication tree.

## Boundaries

This restores exported messages and provenance. It does not restore a complete
archive database, saved searches, source-profile settings, credentials or a
provider mailbox. New originals receive the destination's current archive date;
existing originals keep their dates and verified projections. Attachment text
uses the existing opt-in bounded extractor.

The manifest is unsigned: hashes detect corruption and observed changes, not
authenticity. Portable filesystem checks do not atomically exclude hostile
path replacement between operating-system calls and do not create a filesystem
snapshot. Reruns begin at the start and deduplicate; there is no durable import
cursor or unattended scheduler. Process-interruption checks do not qualify all
power-loss, device, operating-system or installed-application scenarios.

Qualification covers Linux native SQLite, synthetic/loopback mail and Flutter
widgets plus the declared Node library boundary. It does not claim live-account
interoperability, an installed Windows/macOS/mobile build, AppKit behavior,
signing, a complete provider-transport rerun or full-repository acceptance.
PST/MSG ingestion, PDF/Office attachment extraction, recursive provider
collection, provider-mailbox restore, durable cursors, scheduling and enterprise
ACL/retention/legal-hold/audit/backup/key controls remain explicit roadmap work.
