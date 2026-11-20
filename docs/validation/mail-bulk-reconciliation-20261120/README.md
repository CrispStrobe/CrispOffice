# Mail bulk branch reconciliation — qualified source

**Accepted: 1,056 distinct passing cases across 50 suites, with no failed or
skipped cases.** The accepted set contains 1,024 retained cases and 32 cases
rerun after the cached-host test was formatted. It is bound to source commit
`cf25a0a3d80ee18d2550161af182bacc4e49d18f`, tree
`0780f20f27df62004404496d8e5c529c4bdccd87`.
[Accepted union](accepted-union.json) · [case identities](accepted-test-cases.json).

This is a local qualification. No GitHub Actions result was queried or awaited.
The documentation commit containing this record may be newer than the tested
source commit; it is not represented as another execution of the gates.

## Captured incoming work

| Source | Captured commit |
| --- | --- |
| Frozen Word starting checkpoint | `cb5909fefe6dd41db0f9c38207db83166072dcaf` |
| Published Word evidence checkpoint | `467dcaffe016b9e647f944b59af473b13e3ae7f6` |
| Bulk actions branch | `9109fcc645d0d95fbe7a7568ddf1e0ebc07bc384` |
| Bulk flags branch | `fcc7bd27f7df6200ac7d3174f6e21097f931cca0` |
| Mail branches' common ancestor | `b01cb23dc1b7bc94b691d68a2507b61dc6d48d7a` |
| Later captured main, including Word/layout and editor-font changes | `e975cec13b289fe067ef406cd3044701ecc44744` |
| Complete Mail execution checkpoint | `cdd98460c2eed261719c660351f11adc962e2ca5` |
| Final corrected source checkpoint | `cf25a0a3d80ee18d2550161af182bacc4e49d18f` |

The fixed incoming heads are ancestors of the final source checkpoint. The
[ancestry record](incoming-heads.json) preserves the local Git commands and
results. Later feature pushes are outside this captured scope.

## Resolution and resulting behavior

The flags branch contributes mutation-boundary evidence in `MailProblem` and
the native IMAP, EWS, cloud and unsupported providers, together with localized
progress and individual message outcomes. The actions branch contributes strict
plan/provider validation, the single-use coordinator, compatibility with
immutable record/action adapters, and independent cancellation, reconnect,
disposal, keyboard and accessibility regressions.

There is one execution loop. `MailBulkFlagRunner` adapts provider results into
the same coordinator used by `MailBulkFlagCoordinator`, preserving original
problem objects and ordered immutable results. Only explicit evidence that no
mutation occurred permits a definite failure classification. Both APIs stop
further dispatch after uncertain results, definite cancellation or stale-scope
failures, a retired scope, or a stop request. Progress observers cannot erase
results, trigger replay, or permit more work after retiring the scope. An
in-flight provider acknowledgment is retained; the host separately checks
whether it may publish that result into its current view.

The shared UI uses `selectionRevision`, `bulkEnabled` and a host-owned
`bulkStatus`. Accepting an action consumes the immutable popup snapshot and
checked selection. Escape clears the selection, stop remains accessible while
ordinary work is busy, and notice/error accessibility nodes remain separate.
Mounted, disconnect and revision guards reject stale publication.

Native hosts accept explicit bulk adapters and the earlier combination of
immutable remote records plus action adapters. The legacy combination preserves
the frozen account, mailbox and record identities, passes a copied mailbox, and
conservatively classifies every invoked failure as uncertain. Adapters without
immutable remote identity evidence remain read-only for bulk operations.

Both independent test families remain present: the coordinator and runner core
suites; the two Mail UI selection/callback suites; and the original native/EWS
host regressions alongside the evidence-aware provider and loader coverage.
Stable operation IDs retain the original `plan:index` form. The source and
complete case identities are bound by the receipts below.

### Capability boundaries

- Bulk operations cover marking selected loaded messages read/unread and
  setting/removing flags in a foreground host session.
- A stop request prevents later dispatch; it does not undo a mutation already
  acknowledged by the provider. Uncertain results are not automatically replayed.
- This change does not promise a durable command journal, offline replay,
  background execution, or persistent-cache updates.
- Tests use synthetic records, controlled provider boundaries and local loopback
  fixtures. They do not certify a live mailbox, tenant, credential flow or server.
- The editor's `office_system_fonts_io.dart` received strict static analysis.
  This record makes no platform-specific system-font discovery claim.

## Accepted test coverage

| Scope | Suites | Accepted cases | Execution |
| --- | ---: | ---: | --- |
| Complete Mail core tests | 10 | 155 | Dart VM |
| Transport VM suites | 19 | 411 | Dart VM, including native/store and loopback cases |
| Three JS-only unsupported transport suites | 3 | 6 | Actual `package:test` on Node/dart2js |
| Complete Mail UI tests | 10 | 155 | Flutter VM |
| Seven affected Studio host/provider/loader/cached/visual suites | 7 | 324 | Flutter VM; includes the 32-case corrective rerun |
| Separate localized Mail UI visual harness | 1 | 5 | Flutter VM |
| **Accepted logical total** | **50** | **1,056** | Each case counted once |

The seven Studio files are `studio_mail_workspace_test.dart`,
`studio_mail_ews_test.dart`, `studio_mail_bulk_provider_test.dart`,
`studio_mail_message_loader_test.dart`, `studio_mail_cloud_test.dart`,
`studio_mail_cached_mail_test.dart`, and `studio_mail_bulk_visual_test.dart`.
The separate harness is `quds_mail_ui/tool/bulk_flags_visual_test.dart`.
All selected suites loaded, all test groups reported terminal success, and no
reporter errors were accepted. The three `@TestOn('js')` transport files ran on
Node instead of being counted as skipped VM coverage.
[Original command receipt](original-qualification.json) ·
[corrective command receipt](qualification.json).

### Strict analysis, formatting and seals

- Whole Mail core and transport analysis passed in the original run.
- UI `lib`, `test` and `tool`, all five changed Studio libraries plus the seven
  selected Studio test files, and the editor font-I/O file passed the direct
  pinned Dart analyzer with `--fatal-infos --fatal-warnings` in the corrective run.
- All 28 changed Mail/Studio Dart files passed the read-only formatting check.
- Each run sealed 5,827 tracked source files and 6,188 configured dependency
  files before and after execution. Source, dependency and runtime seals match.
- Configuration checks verified all 21 canonical workspace/path roots,
  135 exact hosted lock/archive pins, and eight Flutter SDK package roots.
- The final worktree readback was clean and remained at the declared source
  head. No tracked dependency manifest or lockfile was changed by qualification.

Receipts preserve exact arguments, working directories, environment paths,
stdout/stderr hashes, case identities and input manifests. Configuration,
compiler, test-runner and native-library inputs remain identical between runs;
the qualification driver changed to support the focused rerun and use the direct
analyzer. [Retention proof](accepted-union.json).

## Original diagnostics and corrective qualification

**The original aggregate is still recorded as failed.** Its 1,056 test cases all
passed, but its read-only formatter found one noncanonical assertion layout.
Three `flutter analyze` commands also failed before source analysis because the
selectively extracted SDK omitted its `dev/` directory. These are preserved
startup diagnostics, not passing analyzer results. A simultaneous Word CLI test
temporarily owned an untracked `arguments-cli-*` directory; all tracked source
hashes were unchanged.

The cached-host assertion was formatted with the exact previously captured
formatter output. The final checkpoint also contains a separate Word-only test
fixture geometry correction in `word_contained_text_wrap_test.dart`. No product
source changed between the two Mail receipts.

The corrective run executed all 32 cached-host cases, all 28 format checks, and
the three missing strict analyzer scopes. Every command passed. The original
32 cached-host identities exactly match their replacements. The other 1,024
case identities are retained only after verifying their unchanged inputs.

The unrelated Word fixture is outside the 50 selected Mail entries and their
831 reachable local Dart sources. The only filesystem enumeration in that graph
is the bounded Mail archive walker, which accepts EML/MBOX input and skips other
extensions. The Word test is neither imported nor consumed.
The [fixture audit](nonmail-fixture-audit.json) binds the review and source hashes
to the final checkpoint.

Development attempts are historical records, excluded from the accepted
arithmetic. The archive retains the earlier 154-pass/one-failure UI run, its
corrected focused run, earlier analyzer output, overlapping host/core runs, and
the empty stalled `dart test` startup log. None is added to 1,056.

## Rendered visual evidence

The archive contains **20 original PNGs**: five localized UI-harness images and
15 Studio images covering selected, action-menu and working states. English,
German and Arabic portrait layouts and German/Arabic compact layouts use real
bundled fonts at 1.4 text scale.

All 20 images were reviewed. One reviewer inspected the nine Studio portraits;
an independent reviewer inspected all five UI images and six compact Studio
states. No blocking problem was found in the reconciled bulk controls, Arabic
glyph shaping, localized action menus, stop controls or overflow behavior.
Intentional ellipsis and bounded scrolling remain visible. The review also
records an existing Latin-address punctuation behavior inside RTL rows without
claiming it was changed. [Visual review](visual-review.json) ·
[PNG hashes](screenshots.json).

## Runtime and evidence package

The recorded runtime is Linux x64, Flutter **3.47.8**, Dart **3.13.7**,
`package:test` **1.31.1**, and Node **24.22.3**. The official Flutter archive
SHA-256 is
`baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2`.
Setup verified 202 hosted archives across Flutter tooling and the workspace;
135 of those hosted packages are used by the final workspace configuration.
Offline workspace resolution enforced the lockfile.

The standard pinned SQLite build hook produced the Linux x64 library with
SHA-256 `0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`.
A real in-memory FTS5 create/insert/query probe passed and reported SQLite
3.54.1. SDK, dependency, configuration, test-runner and SQLite provenance are
retained under `runtime-provenance/` in the archive. The original setup and
compile logs are preserved; the kernel's startup and subsequent actual test
executions establish its readiness.

[mail-bulk-qualification.tar.xz](mail-bulk-qualification.tar.xz) contains the
original and corrective receipts, raw logs, case identities, before/after
manifests, all PNGs, development diagnostics, exact executed scripts, and runtime
provenance. It excludes SDK binaries, caches, compiled kernels, native binaries
and JavaScript build outputs. Members have normalized ownership, modes and
timestamps. The packager verifies every member hash and confirms that rebuilding
from the same input bytes produces the same archive hash.
[Archive/member manifest](archive-manifest.json) · [SHA256SUMS](SHA256SUMS).

## Reproduction

The scripts require Python with PyYAML, Git, Node on `PATH` (recorded version
24.22.3), and Linux x64. Runtime setup downloads the pinned official SDK and
hash-verified Pub archives, then resolves Flutter tooling and the fresh workspace
offline with `--enforce-lockfile`. It creates runtime files and ignored workspace
configuration. Use fresh runtime and output directories.

From the repository root of a checkout containing the captured commit, enter
this evidence directory so the companion scripts and checksum files resolve,
then create a separate worktree:

```bash
cd docs/validation/mail-bulk-reconciliation-20261120

git worktree add --detach /absolute/path/mail-repro \
  cf25a0a3d80ee18d2550161af182bacc4e49d18f

python3 reproduce_flutter_runtime.py \
  --repo /absolute/path/mail-repro \
  --runtime /absolute/path/mail-runtime

python3 qualify_mail_reconciled.py \
  --repo /absolute/path/mail-repro \
  --runtime /absolute/path/mail-runtime \
  --out /absolute/path/mail-validation \
  --expected-head cf25a0a3d80ee18d2550161af182bacc4e49d18f \
  --format-base 467dcaffe016b9e647f944b59af473b13e3ae7f6
```

The default qualifier executes the complete 50-suite scope, Node checks,
localized visual harnesses, formatting and strict analysis. It redirects PNGs
outside the source tree. Pure Dart gates use the genuine pinned `package:test`
runner; Flutter gates use `flutter test --no-pub`. Static analysis uses the
pinned SDK's Dart analyzer directly, so it does not require the omitted Flutter
development directories. The reproduction helper combines already exercised
setup steps into a portable script; it was syntax-checked rather than used for a
redundant second SDK download. A fresh full run is distinct from this record's
retained-plus-corrective history.

To inspect and recheck archived retention arithmetic without rerunning tests:

```bash
sha256sum -c SHA256SUMS
mkdir mail-evidence
tar -xJf mail-bulk-qualification.tar.xz -C mail-evidence
python3 verify_mail_retention.py \
  --baseline mail-evidence/original-attempt \
  --final mail-evidence/corrective \
  --nonmail-fixture-audit nonmail-fixture-audit.json
```

This last command checks saved records, hashes and case identities. It does not
claim to execute product tests again. Separate Word/native records govern the
Word changes in the shared source tree; this Mail result does not replace them.
