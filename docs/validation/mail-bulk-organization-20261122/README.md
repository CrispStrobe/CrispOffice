# Mail visible-selection organization — work and validation record

Date: 22 November 2026. Branch: `work/mail-bulk-organization-20261122`.

## Implemented boundary

Connected IMAP, EWS, Microsoft 365 and Gmail hosts expose supported
visible-selection Move/Delete through the durable sequential command coordinator.
Confirmation identifies count, account, exact source and observed destination.
Identities are frozen before awaits and rechecked afterward. The journal records
intent, applying markers and per-message results, retaining stop-after-current
and restart uncertainty without replay. Gmail does not expose folder-style Move;
IMAP Delete sets `\Deleted` without expunging. Cached views remain read-only.

See [the workflow and next increments](../../roadmaps/mail/bulk-organization.md).
This is a bounded step toward desktop mail-client parity, not a release or
live-provider interoperability certification.

## Intake and incremental preservation

Initial main: `b38f2e38369855056eb9e23792f83fd1ab86ea24`.
The [initial intake](intake.json) and [review](intake-review.md) cover all 414
fetched references, including 369 pull-request heads and ten archive refs.
388 were ancestors, 24 were verified exact equivalents (15 unique heads), and
two required integration: authoritative mail identities and Word cell suffixes.
No open pull requests existed at that first inspection.

The initial merge retained both branches' executable safeguards and tests:
clock rollback checks, bounded destination metadata scans and display-name
quota accounting, future schema rejection and updated migration fixtures.
The [advanced-head review](advanced-heads-review.md) records subsequent intake.
All refreshed heads are reconciled before final publication.

| Remote checkpoint | Contents |
| --- | --- |
| `7ea871c890760f17dfa84efe2eec6cf467766153` | Initial mail identity and Word suffix integration |
| `abe1aaf260c55577aa017cb4b3ff163be459aff9` | Capability-controlled shared selection actions and tests |
| `ea820f8aa7eb8fab7740d6ff37a19056cdb0d76a` | Connected provider hosts and localized confirmations |
| `ca335d575e61dab0ed40f35c6892533316cb1130` | Durable host, provider and dialog regressions; intake |
| `06e43cec8c2bcaadd53a5979f6e75caa53bf6bb0` | Advanced Word suffix evidence and fixture cleanup |
| `c7cd2f2209d7b306cc0bce0dcfa91242b8e33369` | Advanced identity history with integrated safeguards |
| `f25c62e38b422598873c3dc3bb638e746dfb53b9` | Then-current extended Word integration history |

These checkpoints preserve source and history, not completed runtime claims.
The last merge message's word “qualified” refers to retained incoming source;
the new bulk mail runtime checks were still pending then.

## Runtime and checks

The pinned Flutter 3.47.8 stable archive was verified against published SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
Framework: `737ba8f885dc774b53b442759999a312c9461e4e`; Dart: 3.13.7.
See [runtime provenance](runtime.json). Version output, real Dart analysis and
execution, and the `flutter_tester` executable were checked. Workspace
`dart pub get --enforce-lockfile` with `FLUTTER_ROOT` exited 0. The root lockfile
remained byte-identical; [dependency receipt](dependency-resolution.json).

Strict analysis passed for all new/changed host, shared-list, localization and
test paths. Native-host analysis first found two missing explicit `mounted`
checks across awaits; both were corrected and the gate passed on rerun.
Formatting was reapplied after resolution so the workspace language version
controls it consistently. No manifest or lockfile was changed.

At this checkpoint the focused core suite passed **145/145** real tests using
the pinned test package's supported standalone execution with `--enable-asserts`.
Word suffix macro/conformance checks passed **153/153**. The CLI integration
suite executed zero cases because its setup could not create a temporary
directory (`ENOSPC`). Further widget, transport and persistence checks are in
progress; the completed record will identify actual execution and limitations.
Test source alone is not a passing-test claim.

## Environment and scope limits

The shared filesystem repeatedly reported zero available bytes. Conventional
and source-mode test launchers failed creating temporary directories before
executing tests. Only this task's reproducible SDK extraction material,
dependency examples/docs, sparse assets and excluded promisor blob caches were
reclaimed. No unrelated work or dependency implementation was changed.

Standalone execution uses the real pinned test Engine/Invoker and assertions,
but lacks the conventional runner's per-file process isolation and file-level
annotation handling. Selected VM suites were checked for those annotations.
Persistence and CLI fixtures still need writable temporary directories.
Any direct widget-engine execution is documented separately from the Flutter
CLI path. The minimal SDK does not qualify installed-platform packaging,
browser builds, live providers or asset packaging.

GitHub Actions were neither polled nor awaited. Local gates that actually ran,
their failures and the explicit remaining limits determine this record.
