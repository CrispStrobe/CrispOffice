# Mail visible-selection organization — qualification record

Date: 22 November 2026. Branch: `work/mail-bulk-organization-20261122`.

**Qualified source:** `1249935e224e8a3c01ea76c6662dff9ded1a9096`  
**Source tree:** `7eeb47825d1755b247c1e77facd7abf49d7dab7a`

The final evidence commit adds documentation and evidence to this source. The
[qualification summary](qualification.json), [qualified-source intake](final-intake.json),
and [evidence index](evidence/mail-bulk-organization-evidence-index.json) bind the accepted gates,
source identities, commands, raw logs and limitations. The
[raw evidence archive](evidence/mail-bulk-organization-evidence.tar.gz) preserves
accepted and failed attempts. Repeated attempts are
retained but are not counted twice.

## Delivered boundary

Connected IMAP, EWS, Microsoft 365 and Gmail hosts expose supported
visible-selection Move/Delete through the existing durable sequential command
coordinator. Confirmation identifies count, account, exact source and observed
destination. Identities are frozen before awaits and rechecked afterward. The
journal records intent before dispatch, an applying marker before each provider
call, and per-message results before further dispatch. Stop-after-current,
uncertainty and close/reopen recovery retain evidence without automatic replay.

Gmail does not expose folder-style Move. IMAP Delete marks \Deleted without
expunging; EWS/Graph/Gmail retain their established trash semantics. Cached
views remain read-only. Shared list defaults preserve the existing four flag
commands; hosts explicitly opt into organization. Confirmation and action copy
cover English, German and Arabic, including narrow layouts and enlarged text.

See [the complete workflow and ordered continuation](../../roadmaps/mail/bulk-organization.md).
This increment does not close the full Outlook, Thunderbird or eM Client parity
roadmap. Connected multi-account navigation, explicit Archive, rules, broader
search/conversations, provider Drafts/Sent reconciliation and background work
remain subsequent boundaries.

## Accepted local gates

| Area | Accepted passing cases |
| --- | ---: |
| Mail core, identity, snapshots and command journal | 290 |
| IMAP/EWS transport and vendored COPYUID parser | 173 |
| SQLite store, move projection and migrations | 218 |
| Shared Mail UI | 139 |
| Connected provider and confirmation dialogs | 37 |
| Durable connected SQLite hosts | 81 |
| Incoming Word/VBA and preservation | 331 |
| **Total** | **1,269** |

The accepted results contain **zero failures and zero skipped cases**. The 257
widget cases include **78 new Mail regressions**: 18 shared-list cases, 37
provider/dialog cases and 23 durable bulk host cases. Five additional Word
preservation regressions close the incoming fixture defect described below.
These totals exclude runtime probes, allocator smoke checks, superseded failures
and duplicate reruns. Historical results imported from other branches are not
added to this total.

The durable host suite uses actual SQLite files and verifies persisted intent
and applying markers before provider dispatch, exact account/remote identity
translation, cancellation before confirmation, stale UID generations, revoked
capabilities, uncertainty in the middle of a batch, Stop, persistent receipt
failure, source-row projection and close/reopen recovery without replay. The
other 58 host cases preserve existing single-message organization, activity
checks and flag behavior. All 81 passed, with no late raw or JSON errors.

Changed Mail source/tests and the incoming arithmetic/preservation changes also
passed pinned formatting and strict analysis with fatal infos. Whitespace
checks passed. No dependency manifest, lockfile or database schema was changed
by this bulk continuation; the incoming identity work's schema 15 is retained.

### Runtime and attribution

Flutter **3.47.8 stable**, framework
`737ba8f885dc774b53b442759999a312c9461e4e`, and bundled Dart **3.13.7** were used.
The official archive was verified before extraction against published SHA-256
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
[Runtime provenance](runtime.json) and the
[dependency receipt](dependency-resolution.json) retain the checks. Workspace
`dart pub get --enforce-lockfile` with `FLUTTER_ROOT` exited 0. The root lockfile
remained byte-identical, SHA-256
`2231cacd6ab548da8f0d94020201a29f07f54a20c1682c0e8ae0079967b720eb`.

The exact native asset selected by locked `sqlite3` 3.9.1 was downloaded and
verified: SHA-256
`0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`.
Its runtime reports SQLite 3.54.1. No system SQLite substitution was used.

The [standalone ledger](standalone-final-suite-ledger.json) identifies 37 unique
suites and 1,008 accepted cases. Execution-time test-source hashes were captured
for its latest 363 cases. The earlier 645 have named test files and raw logs;
their ledger hashes were observed at finalization, not during execution. This
distinction is explicit. The separate COPYUID receipt records four cases and
unchanged hashes across 138 vendor source/test inputs. Widget receipts retain
source/output hashes and exact case counts.

## Environment adaptations and practical limits

The shared filesystem repeatedly reported zero available bytes. Ordinary and
source-mode test launchers initially failed creating temporary directories
before running cases. Only this task's reproducible extraction material, cache
examples/documentation and sparse checkout assets were reclaimed. No unrelated
work or dependency implementation was changed to conceal a failure.

Pure Dart gates used the pinned test package's supported standalone VM
Engine/Invoker with assertions enabled. Per-test setup, teardown and inline
metadata remain active. This route does not discover library annotations or
`dart_test.yaml`; selected suites were inspected for these requirements. The
VM-only host annotation was satisfied explicitly, and the JS-only EWS suite was
excluded from the claimed scope.

Widget gates used the original frontend server, patched Flutter SDK, original
`flutter_tester`, automated binding, assertions, test fonts and stock SDK
shaders. Bootstrap and compiled kernel were held in anonymous memory. Explicit
native-asset metadata selected the verified SQLite binary. The durable runner
also drained the real event loop for 250 ms after completion and rejected late
raw or JSON errors even after an apparent success event. Negative controls
verified that both forms of late failure produce a failing exit.

For persistence and CLI fixtures, a scoped allocator reused 13 existing empty
directory inodes because new directory allocation failed. Regular-file and
SQLite I/O remained real. Independent checks covered actual libc and Dart
directory operations and 20 WAL database close/reopen cycles. The allocator is
qualified only for quiescent test-owned teardown; it does not establish general
filesystem behavior or concurrent writers racing directory removal. All donor
directories were restored after validation completed.

These gates do not claim normal Flutter CLI orchestration, project asset
packaging, plugin/native-hook discovery, full application/platform builds,
browser persistence, JavaScript-only provider behavior or live-account
interoperability. Those remain explicit acceptance work. The evidence includes
commands and the execution helpers; ordinary SDK test commands can be used when
normal temporary storage is available.

## Initial failures and corrections retained

- Native strict analysis required explicit mounted checks across two async
  confirmation boundaries; both checks were added and analysis passed.
- The first direct Dart attempt omitted assertions, unlike the normal isolated
  test runner. Accepted standalone runs explicitly enable them.
- The first widget attempt lacked the standard ink-sparkle shader and exposed
  three tooltip-finder assumptions. Stock shaders were compiled with the pinned
  SDK, and disconnect tests now identify the intended IconButton. The initial
  console was not saved as a raw local log; its reconstruction is clearly
  labeled as reconstructed observations. Final raw passing logs are retained.
- Review corrected four persistent-failure fixtures. A single failed result
  write may still settle during journal finalization, so the intended uncertain
  recovery scenario now keeps result and finalization writes unavailable.
  All four passed against real SQLite after that correction.
- Two incoming grouped Word report cases initially failed a preservation
  assertion. The macro intentionally edits four cells, but its reused suffix
  fixture treated only three as selected. An explicit selected-cell count now
  permits four for that report while retaining the default of three. Five new
  guards detect neighboring-cell, paragraph-property, table-geometry, custom
  XML and inert VBA changes. All 14 existing suffix and 15 updated grouped
  integration cases passed, including actual CLI execution and protected output.

The initial ENOSPC attempts, Word assertion failures, exact mismatch diagnosis,
source diffs and accepted replacements remain in the evidence archive.

## Intake and incremental remote preservation

Initial main: `b38f2e38369855056eb9e23792f83fd1ab86ea24`.
The [initial intake](intake.json) and [review](intake-review.md) cover 414 fetched
references. At that point 388 were ancestors, 24 were verified exact equivalents
(15 unique alternative heads), and two required integration. The qualified-source capture
contains **417 references: 393 ancestors and the same 24 verified historical
equivalents**. All four upstream branch heads were rechecked and unchanged.
No unique incoming work remains unreviewed in that capture. The
[publication addendum](publication-addendum.json) records the later main
`c691191c3ff37f52bc78b203ebb1cb554e607d12` and suffix
`360673e0736e98d65d6c3cacef90bf842391288d`: only two additional historical
Word documentation blobs were new. They and their merge ancestry are retained;
qualified runtime source and tests remain unchanged.

The initial merge retains authoritative Mail move identities and Word cell
suffixes, both executable cache safeguards and both test families. Subsequent
intake preserves integer arithmetic, the published main merge, all late
qualification records and both late branch heads. The
[advanced-head review](late-advanced-heads-review.json) explains a multiple-base
merge: an incoming identity tree reused an older parent version. The current
bounded metadata scan, SQL limit, early budget exits and delivered-bulk roadmap
were retained while importing the new documents and genuine parent history.

| Remote checkpoint | Contents |
| --- | --- |
| `7ea871c890760f17dfa84efe2eec6cf467766153` | Initial identity and Word suffix integration |
| `abe1aaf260c55577aa017cb4b3ff163be459aff9` | Shared selection actions and tests |
| `ea820f8aa7eb8fab7740d6ff37a19056cdb0d76a` | Connected providers and confirmations |
| `ca335d575e61dab0ed40f35c6892533316cb1130` | Durable regressions and intake evidence |
| `06e43cec8c2bcaadd53a5979f6e75caa53bf6bb0` | Advanced suffix history/evidence |
| `c7cd2f2209d7b306cc0bce0dcfa91242b8e33369` | Advanced identity history and retained safeguards |
| `f25c62e38b422598873c3dc3bb638e746dfb53b9` | Then-current extended Word history |
| `f361ce24d632a89f231f74143e4f10cab8bf648d` | Lifecycle checks, formatting and progress record |
| `f6fcc21f9e6a05f45f8160a69b2b2707eda6d03c` | Incoming Word integer arithmetic |
| `aaf88978177425d8d26caedb385f91d0638bb01a` | 257 passing Mail widgets and published-main reconciliation |
| `1249935e224e8a3c01ea76c6662dff9ded1a9096` | Complete accepted source, Word guard correction and final late histories |

Checkpoints preserve progress; they do not imply all later gates had already
run. In particular, “qualified” in the f25 merge message described retained
incoming source while the new bulk runtime gates were still pending then.

Publication preserves merge ancestry and the working branch. The pull request
and remote commit history provide the final publication receipt. **GitHub
Actions, commit statuses and check queues were neither queried nor awaited.**
