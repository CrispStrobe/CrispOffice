# Local runtime and transport development evidence

This directory retains reproducible runtime provenance and the completed
bounded-browsing development cohort: **130 passed, zero failed, zero skipped**.
GitHub Actions, workflow runs and commit-status endpoints were not consulted.

This is a **working-source development record**, not the final combined-source
acceptance gate. The 130-case command did not capture product inputs before and
after execution. Its raw events and exit result establish what ran and passed;
they do not establish a frozen complete repository tree. The final acceptance
runner and its separate source manifests remain the publication gate. Repeated
or overlapping test executions must not be added together.

## Transport results and exact command

The [structured result](transport-development.json) records all 130 substantive
case names, the exact command and working directory, selected and loaded suite
paths, the observed zero exit code, and the successful final runner event.
Hidden loading cases and repeated completion events are excluded.

| Selected suite | Passed |
| --- | ---: |
| `native_browse_test.dart` | 29 |
| `native_provider_test.dart` | 69 |
| `uid_discovery_test.dart` | 27 |
| `cursor_test.dart` | 5 |
| **Total** | **130** |

The command was executed from
`/workspace/scratch/8e9460dcd580/quds_office_suite` after loading the pinned
runtime environment:

```bash
source /workspace/scratch/8e9460dcd580/runtime/env.sh

dart --packages=/workspace/scratch/8e9460dcd580/quds_office_suite/.dart_tool/package_config.json \
  "$PUB_CACHE/hosted/pub.dev/test-1.31.1/bin/test.dart" \
  --reporter=json \
  packages/quds_mail_transport/test/native_browse_test.dart \
  packages/quds_mail_transport/test/native_provider_test.dart \
  packages/quds_mail_transport/test/uid_discovery_test.dart \
  packages/quds_mail_transport/test/cursor_test.dart
```

This invokes the actual pinned `package:test` entry point with the generated
locked workspace package configuration. No product or test source was copied or
patched to make the runner work.

[Raw JSON events](logs/native-browse-window-qualified.jsonl.gz) are compressed
without changing their original bytes. The uncompressed log contains 59,480
bytes and has SHA-256
`b4361f68f56e84031a490126238a51da05a589ed44fb37ab3779092fa5b06ef6`.
The retained [stderr](logs/native-browse-window-qualified.stderr) is empty.

The regression selection covers an actual 10,001-message dense mailbox; 8,000
high 32-bit UIDs subject to the 64 KiB protocol-line budget; independent line
and aggregate response constraints; unknown, invalid and misleading SELECT
counts; generation and cursor isolation; sparse and expunged ranges; confirmed
mutations; cancellation; and preservation of the separate ascending APIs.
These controlled fixtures exercise the actual protocol command and response
parsers. They are not live-mailbox or installed-application qualification.

### Bounded discovery contract

Newest-first browsing performs one SEARCH and at most one header FETCH per
page. A positive observed mailbox count within the effective discovery budget
permits a whole-range search, preserving efficient sparse-mailbox browsing.
Otherwise it searches a bounded UID tail. The effective bound considers the
configured UID-count limit, protocol-line capacity and conservative headroom in
the connection's aggregate response budget.

The original hard resource limits remain authoritative. SEARCH uses at most
half the aggregate budget, with framing slack, retaining headroom for control
traffic and headers. This estimate does not guarantee that atypically large
control replies or headers fit; the original quota rejects them explicitly.

An empty sparse window can have a continuation to an older unexamined range.
Callers preserve that cursor and request another page explicitly. There is no
background loop through numeric gaps. Large sparse mailboxes beyond the
count-based optimization can require several empty pages and remain subject to
host page and retained-message limits. The first page fixes its upper UID
boundary; later arrivals appear on Refresh.

## Runtime identity

The [bootstrap receipt](runtime.json), [readiness receipt](readiness.json) and
[current runtime pins](current-runtime-pins.json) record the actual local
runtime. All current pinned file hashes matched the initial readiness hashes
when this evidence was prepared.

| Runtime input | Verified value |
| --- | --- |
| Flutter release | `3.47.8`, stable |
| Framework revision | `737ba8f885dc774b53b442759999a312c9461e4e` |
| Engine revision | `cf636b1dfb818dd6a3ff16e390e93b1a036969c8` |
| Dart | `3.13.7` |
| Official Linux archive size | 1,581,444,364 bytes |
| Official archive SHA-256 | `baf7dcc5a3dbba60fe863bf493a6cf203195621f7786eaa5a1bba02cd0d87dd2` |
| Dart executable SHA-256 | `01e869e4af277734b02ab8898b870c6b00c9bec61bbcf9c923cd14de7ed85fbb` |
| Flutter tester SHA-256 | `800f4ca182df7dd2fb46a42dea5d76277b9dbc5e8cd2915e02bcbc978681b45f` |
| Hosted archives verified against locks | 195 |
| Resolved workspace package entries | 157 |
| Workspace lock SHA-256 | `df9ff88b4df699b2420954d0ddc0dd7a1c40dbca8d9e3af3f25bec7e66700e7e` |

The [exact executed bootstrap script](bootstrap_runtime.executed.py) streams the
[official archive](https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.8-stable.tar.xz),
verifies its complete SHA-256, and extracts the selected genuine runtime files.
It retains the full genuine Dart SDK, Linux test engine, Flutter packages and
SDK Git metadata. The SDK's `dev` and `examples` directories were subsequently
restored from the archive's bundled Git HEAD and verified against that HEAD;
this preparation is recorded in `readiness.json`.

The script contains the original workspace path. To reproduce in a fresh
workspace, adapt its `ROOT` constant to the new sibling runtime directory and
keep the checkout at `ROOT.parent / 'quds_office_suite'`. The installer expects
a fresh target and preserves the root lockfile. It does not support overlaying
an already populated cache as an implicit retry.

[Pub archive provenance](pub-cache-receipt.json) records every exact package
version, download URL, byte count and verified archive digest. Flutter tools
and the workspace both resolved with `pub get --offline --enforce-lockfile`.
The root manifest and lockfile remained unchanged. The
[executed environment file](env.executed.sh) contains only the local runtime,
cache and temporary paths plus analytics-suppression switches; it contains no
account credentials or tokens.

Raw setup output is retained as
[Flutter tools dependency resolution](logs/flutter-tools-pub-get.txt),
[workspace dependency resolution](logs/workspace-pub-get.txt), and
[Flutter version](logs/flutter-version.txt).

## Native SQLite readiness

The [SQLite provenance record](sqlite-provenance.json) connects the verified
`sqlite3 3.9.1` Pub archive, its unmodified default build hook and the native
Linux x64 library. The configured download URL is derived from that pinned
hook, not presented as a separately captured HTTP request log.

- SQLite reports **3.54.1**.
- Library SHA-256 is
  `0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`,
  matching the pinned hook's expected artifact hash.
- The [exact readiness probe](sqlite_probe.dart) opened a real in-memory
  database, created an FTS5 table, inserted `ready`, and confirmed that the
  matching query returned exactly one expected row.
- [Raw probe output](logs/sqlite-readiness.txt) and exit code zero are retained.

The probe ran using `dart run build/runtime-preparation/sqlite_probe.dart` from
`packages/quds_mail_store`, allowing the standard native build hook to register
its library. SQLite readiness supports the broader Studio/store environment;
it is not an additional case counted in the 130 transport total.

## Analysis and formatting

[Static-analysis records](static-analysis.json) preserve the strict fatal-info
commands and original output. The four-file bounded-window follow-up returned
“No issues found!” for the changed core port, native provider, browsing tests
and fixture. The earlier six-file analysis additionally covered the cursor and
Studio adapter/tests; it is retained under its original pre-follow-up scope.

The [read-only formatting check](format-check.json) ran during evidence
preparation on seven changed Dart files with:

```text
dart format --output=none --set-exit-if-changed <the seven recorded paths>
```

It exited zero and reported seven files checked, zero changed. The receipt
contains the exact command and identical before/after hashes for each selected
file. This later formatting check does not retrospectively bind the earlier
test run to a frozen complete source tree.

## Reproducible disk recovery

When the executor ran short of disk, only reproducible runtime storage was
reduced. No product or evidence files were deleted.

- [SDK history reduction](sdk-history-reduction.json) reclaimed 278,301,045
  bytes through a local depth-one clone. The exact release commit, tree, tag,
  stable-channel metadata, working source and executable bytes were preserved.
  The [executed script](reduce_sdk_history.executed.py) records the operation.
- [SDK deduplication](sdk-deduplication.json) and
  [dependency deduplication](dependency-deduplication.json) reclaimed another
  59,458,816 bytes by hardlinking only byte-identical files with identical modes.
  All original file paths and bytes remain present.

The receipts preserve original workspace paths for traceability. They contain
runtime metadata and synthetic test names, not live account details. No SDK,
Pub cache, SQLite binary, private mailbox data or credential material is included
in this directory.
