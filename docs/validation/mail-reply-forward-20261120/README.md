# Mail reply and forwarding qualification — 2026-11-20

## Accepted scope

This increment adds safe text quotations for HTML-only messages and an explicit
**Forward with attachments** action across native IMAP/SMTP and the shared
EWS/Gmail/Microsoft 365 Studio hosts. Plain-text preference, bounded reply
threading, Bcc privacy, durable draft recovery and uncertain-submission
acknowledgement retain their existing contracts. The separate account lane
retains ownership of account catalogs and provider sessions.

See the [workflow and limits](../../roadmaps/mail/reply-forward.md). This record
qualifies the implementation and local tests below; it does not claim full
desktop-mail parity or live-provider/installed-platform certification.

## Source and integration

| Checkpoint | Identity / result |
| --- | --- |
| Initial published integration | `f7bf155337b0ba77dc20c6be548ef38ac06c5c65` |
| Qualified Mail source | `4df7a148f156d9a697028994f14b171877d1d47c` |
| Qualified Mail tree | `4c13111ca189109e8f3ddf05e8f4012c3d03adab` |
| Main at initial Mail qualification | `7e740a53d3fea4b6bd734537e89888b641a8b735` |
| Feature parent of final integration | `b2b7ec91e513b1773a8bd26775cde4fd87b738f8` |
| Final combined product source | `081f337475b76e0b13a513fb95bc3c9ef766f6f4` |
| Final combined product tree | `4d1d20bdd3145ee692d9bd4d09476a1954b51e0d` |
| Latest incorporated main | `a652a205e6daf6b4b8e3baec04db1c1b52fabd0d` |
| Publication | [PR #248](https://github.com/CrispStrobe/quds_office_suite/pull/248) |

The [initial intake](intake.json) captures all 19 observed remote branch heads.
The initial base already included captured main, the latest then-published
Downloads work and account identity/ownership guards. Historical ODS/Office
heads whose contents were already incorporated were checked for equivalence
instead of being reapplied over newer files.

Before qualification, the feature was reconciled with the newer combined Mail
main, including credential storage, account/chrome updates and its enforced
dependency lock. Native `git merge-tree --write-tree` produced a clean merge.
The published integration tree matches that result exactly. A mode/type/blob
audit of 18,597 paths found no lost one-sided changes and no altered shared
paths; `git diff --check` was clean. The overlapping native production file
retains main's credential/storage/chrome implementation plus the feature's two
MIME-status arguments. Shared native/EWS tests preserve both sides' distinct
cases. See [integration.json](integration.json).

Receipt/report-only commits do not change product source. Later source
integrations are distinguished explicitly below.
The complete 648-test Mail qualification is bound to the source above and the
source/blob/lock manifest in [runtime-results.json](runtime-results.json).
Additional checks on the final combined Office source are recorded below.

### Latest-main refresh and post-merge correction

The [final intake](final-intake.json) captures 26 remote heads and current PR
dispositions. While local tests ran, main advanced to `a652a205`, incorporating
Word incremental layout, VBA, Zotero, Downloads and packaging work. All Mail
sources, tests and roadmap files already matched the qualified feature by mode,
type and blob. A direct recursive Git-tree audit found exactly 70 incoming main
paths and three feature-only validation files, with no source or mode collision.

Commit `f475589e` preserves that main tree wholesale, overlays the three unique
evidence files and retains both parents. Commit `081f3374` additionally merges
the isolated `e6737bc6` license-loader correction. The latter changes only
`studio_licenses.dart`, loading and decoding the bundled font-license bytes
without depending on a compute isolate under widget-test fake clocks. Its
preimage matched all qualified/incoming sources.

The final environment verified 36 saved Mail source/test/dependency manifest
entries unchanged from `4df7a14`, including the enforced root lockfile. The
bounded final checks below exercise Compose/native Mail with the newer Word
dependencies and directly test the license registry.

Original Downloads PR #242 and remembered-accounts PR #243 are included.
The remaining account, Word, VBA and Zotero branch tips are active
continuations; their already incorporated main content is preserved, while
unfinished work remains with its owners. No ready unmerged Mail/Downloads PR
was omitted.

## Actual local qualification

Runtime: Flutter **3.47.8**, Dart **3.13.7**, Linux Flutter VM/tester. The official
SDK archive and required runtime binaries were hash-verified; the final source
lockfile was installed with `dart pub get --offline --enforce-lockfile`.
Package archives, native SQLite and the genuine repository-declared test assets
were verified. No source stubs or dependency-version substitutions were used.

Final `dart format --output=none --set-exit-if-changed` checked all 12 authored
Dart files and reported **0 changed**. Direct
`dart analyze --fatal-infos <file>` passed for all 12 files, including every
changed production file and authored test file, with **no issues**.

| Qualification group on `4df7a14` | Passed | Failures / skips |
| --- | ---: | --- |
| Mail UI (all 7 suites) | 85 | 0 / 0 |
| Reply / reply all | 43 | 0 / 0 |
| Explicit attachment forwarding | 10 | 0 / 0 |
| Attachment admission and snapshots | 49 | 0 / 0 |
| Native IMAP/SMTP host | 81 | 0 / 0 |
| EWS host | 61 | 0 / 0 |
| Gmail / Microsoft 365 hosts | 57 | 0 / 0 |
| Account catalog, stores, credentials and selected-store integration | 111 | 0 / 0 |
| Compose and attachment composition/loading | 48 | 0 / 0 |
| Draft autosave and durable storage | 26 | 0 / 0 |
| Recipients and threading | 55 | 0 / 0 |
| Session and lifecycle | 22 | 0 / 0 |

**648 tests passed across 27 unique test files**, using 21 complete successful
commands, with zero failures or skips. Selected paths are not repeated in that
total; the per-file manifest and Git blobs are in the receipt. The earlier
`d6de5ef` pass and incomplete runs do not enter this acceptance total.

### Final combined-source checks

On `081f337475b76e0b13a513fb95bc3c9ef766f6f4`, license-loader formatting and
strict analysis passed. Three complete successful test commands produced:

| Final combined-source check | Passed | Failures / skips |
| --- | ---: | --- |
| Direct Hunspell and Arabic morphology license-registry widget fixtures | 2 | 0 / 0 |
| Mail Compose with the updated editor dependencies | 24 | 0 / 0 |
| Native Mail host, including reply/forward/send/recovery | 81 | 0 / 0 |

These **107 passing tests** are a separate integration gate; the 105 repeated
Mail checks are not added to the distinct 648-test qualification total.
The two license fixtures traverse the actual registered font-license entry;
the Downloads link callback alone would not exercise the corrected loader.
See [integration-runtime-results.json](integration-runtime-results.json) for
the exact source, unchanged manifests, filters, commands and results. No
product source was modified during qualification.

Each final test command ran sequentially with these options:

```sh
flutter test --no-pub --reporter=json --concurrency=1 --no-track-widget-creation <selected-tests>
```

The receipt records the exact working directory, selected files, command,
source identity, duration, exit code, completion event, per-run counts and log
hashes. Widget-creation tracking was disabled to reduce compiler overhead;
product assertions were not changed. Commands used bounded process-group
timeouts, and completion plus zero failures was required for acceptance.

Machine evidence is preserved in:

- [runtime-results.json](runtime-results.json) and
  [final-machine-logs.tar.gz](final-machine-logs.tar.gz) for the 648-test Mail
  gate. Archive SHA-256:
  `62dd55ab32df25a8a54af41b48ae76daec802b1778977288c866fefec5ed2584`.
- [integration-runtime-results.json](integration-runtime-results.json) and
  [integration-machine-logs.tar.gz](integration-machine-logs.tar.gz) for the
  final 107-test gate. Archive SHA-256:
  `322e1916fac9e31356b8fd15a36087c36a8294c0c83c1f16191bedc86779aaae`.
- [initial-machine-logs.tar.gz](initial-machine-logs.tar.gz) for the historical
  interrupted attempts.

### Earlier attempts and recovery

The initial clone exhausted local storage and prevented sandbox startup. A
persistent sparse-checkout validation environment restored access to the pinned
toolchain. Earlier qualification on `d6de5ef` passed 83 mail UI tests, while a
combined Studio run timed out after partial progress. These are retained as
history and are not acceptance evidence for the final integrated source.

Initial attempts on the final source also failed to complete: the isolated EWS
process received SIGKILL, and a UI compiler exited unexpectedly. A runner exit
code alone was not treated as a pass when its test completion event was absent.
Resource exhaustion was inferred from these symptoms; cgroup counters were
unavailable, so the cause was not conclusively measured.

Unused SDK artifacts and abandoned generated output were hashed and reclaimed,
required runtime binaries remained unchanged, and the final sequential retry
used the command flags above. The receipt preserves the interrupted runs as
well as the accepted final results.

GitHub Actions were neither used nor awaited. The user explicitly requested
continuing without the starved CI queue; remote checkpoints use `[skip ci]`.

## Review and boundaries

Independent review of the final product source found no remaining blocker.
The status guide was tightened to distinguish the body-only privacy boundary
from forward attribution: forwards intentionally include From/Date/Subject.
Strict MIME-status admission applies to HTML fallback; prior plain-text quoting
behavior remains unchanged.

Covered behaviors include inert HTML fallback; explicit empty plain bodies;
no body fallback to Bcc, envelope displays or attachment names; malformed and
over-budget HTML refusal; Unicode-safe 8,000-scalar quotation; all-or-none
attachment preflight; ten-file/10 MiB limits; immutable exact-byte snapshots;
complete attachment-only messages; inline parts attached as ordinary files;
new-thread forwarding; retained drafts; recovery; uncertain-send acknowledgement;
and provider capability gating.

The tests exercise local models, MIME serialization and host workflows with
controlled/fake providers. They do not establish live SMTP/EWS/Gmail/Graph
delivery, installed keychain behavior, Apple distribution, browser compilation
or the full Office regression suite. Unsupported outgoing container types
(including `message/rfc822`) remain refused. Rich HTML authoring, preserved inline
layout, signatures/templates, multiple drafts and server Drafts synchronization
remain open.

## Incremental remote preservation

Source, tests, integration and evidence were pushed in separate checkpoints to
`work/mail-reply-forward-20261120`; the shared projection, host tests,
reconciliation and validation branches retain their supporting commits.
Updates used normal non-forced ref changes. The normal PR merge preserves
their ancestry and the concurrently integrated main.

Continue the [ordered parity roadmap](../../roadmaps/mail/README.md).
The next independent reliability increment is a visible durable outbox:
freeze MIME and envelope together, expose queued/uncertain outcomes, recover
after restart, and make retry/cancel explicit before undo-send or scheduling.
