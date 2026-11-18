# Zotero Word-like workflow continuation — 18 November 2026

The implementation is saved on `codex/zotero-wordlike-20261118` in [PR #168](https://github.com/CrispStrobe/quds_office_suite/pull/168). This package records **1,047 passing local tests**, strict analysis and formatting, incoming-work reconciliation, runtime provenance, and the repairs made before the final passing runs.

The final tested application source is [`d82d25cc1c89a9a8923601090796f797bcda763f`](https://github.com/CrispStrobe/quds_office_suite/commit/d82d25cc1c89a9a8923601090796f797bcda763f). The later commit containing this evidence changes documentation only. No GitHub Actions were queried, awaited, dispatched, rerun, or used as evidence.

## What changed

| Workflow | Result |
| --- | --- |
| Native Zotero commands | Studio's native desktop **Insert → References** menu opens Add/Edit citation, Bibliography, Refresh citations, or Citation style directly. The requested command starts once when the dialog opens. |
| Edit the citation at the caret | The workspace selects its Document tab when the body caret is inside a citation or bibliography. A selection contained in one citation edits that field. Field ends remain exclusive. Explicit current-field tools support local editing and native Zotero editing. |
| Citation source search | The connected-library picker retains selections across queries and 25-result pages. A review dialog can inspect, reorder, and remove selected sources, including selections outside the current results. Cancellation preserves the prior selection. |
| Keyboard operation | Search starts focused. Down enters the results; Up/Down move between results; Enter or Space toggles a result; Up from the first result returns to search. Navigation works with lazy scrolling, narrow doubled-text layouts, and RTL. Requests remain explicit. |
| Unlink all citations | Document → **Unlink all citations…** confirms the number of citation/bibliography fields, then converts them to ordinary document content as one undoable operation. Content, formatting, notes, and reusable document preferences are preserved. |
| Safe document operations | Bulk unlink rejects unsafe or incomplete packets before changing any field. Checks cover locked, nested, malformed, opaque, or preserved native Zotero instructions, protected content, pending revisions in affected paragraphs, read-only state, and Track changes. Stale confirmations are rejected. |
| Native note field lookup | The integration engine recognizes existing Zotero fields in anchored footnotes and endnotes when the integration caret targets that paragraph. Unsupported or unanchored locations remain guarded. |
| Large documents | Opening a caret-aware Zotero workspace performs one field inventory scan, including the existing 1,000-citation case. Later edits still use fresh inventories. |

The prior PR #168 connected-library search and custom-format cache fixes remain included. Its previously unexecuted regressions were exercised in this continuation. See the [user and integration guide](../../zotero-support.md) for behavior and host APIs.

### Note editor boundary

The Notes pane uses a separate text editor. This change does **not** connect that pane's caret to the ribbon's native citation command. Existing note citations can be selected explicitly in the Zotero Document field list and edited with **Edit in Zotero…**. The engine's note-caret recognition and the Notes pane UI are distinct pieces of integration.

## Incoming work and remote checkpoints

Before feature work, the fork's **207 branch heads**, **168 PR heads**, and upstream's **four branch heads** were fetched and reconciled. The initial inventory contains 351 ancestor refs and 28 refs pointing to 14 historical equivalent heads. Equivalence was checked through fresh patch comparisons, matching trees, or matching changed files, as appropriate. See [incoming.json](incoming.json).

The first new merge incorporated review receipt head `97c7ddae`. A later bounded refresh found new inline comment suggestions and text-level proofing controls on review head `a77d67d04dfe4e1d61bc3dae5c96d5d9d3a4f1f4`. They were merged before the final editor/Studio gates. The incoming-only delta changed five implementation Dart files, three test Dart files, and supporting evidence; it did not change engine, dependency, or Zotero implementation files. [late-integration.json](late-integration.json) records the changed refs and merge.

The source checkpoints were saved remotely in this order:

| Checkpoint | Purpose |
| --- | --- |
| `8677c59b` | Reconcile the latest review receipt files. |
| `5e918a8d` | Recognize native Zotero fields at anchored note carets. |
| `3b15d1c3` | Review selected sources across connected-library searches. |
| `81720ff1` | Direct native commands, keyboard selection, and atomic unlinking. |
| `04415170` | Restore one initial field scan and repair search-test frame timing. |
| `1657771b` | Repair baseline note-test controller lifecycle cleanup. |
| `86b9c03c` | Merge the incoming inline-comment and proofing-control work. |
| `d82d25cc` | Qualify inherited proofing language and format integrated tests. |

Each update was a fast-forward guarded by the expected remote head. The remote tree was checked against the local committed tree. Earlier checkpoints, including the user's `b2597485` starting point, remain in history. [checkpoints.json](checkpoints.json) records the full hashes. The containing documentation commit is the final evidence checkpoint.

## Final local validation

| Gate | Result | Binding |
| --- | --- | --- |
| Engine: 24 Zotero/note-numbering test files | **476 passed** | Executed at `81720ff1`; engine, local dependencies, and root configuration are unchanged at `d82d25cc`. |
| Editor: 39 Zotero, notes, proofing, and review test files | **526 passed** | Executed at `d82d25cc`. |
| Studio: four transport, widget, comment, and review test files | **45 passed** | Executed at `d82d25cc`. |
| Strict Dart analysis | **20 changed Dart files, no issues** | `dart analyze --fatal-infos`. |
| Dart formatting | **20 files, zero changes** | `--output=none --set-exit-if-changed`. |
| Git whitespace | **Passed** | Changes from `b2597485` through final application source. |
| Source fingerprint verification | **1,400 files matched** | Engine/editor tracked files plus root SDK, package, and analysis configuration. |

**1,047 is the sum of the three disjoint test gates.** Focused reruns and the earlier historical 626-test qualification are not added to that number. This is a targeted regression gate, not a run of every test in the repository.

The engine gate was not rerun after editor-only changes. Its unchanged inputs were checked against the later source, including all local dependency packages and relevant root configuration. The editor and Studio runs were repeated on the exact final application commit. Source hashes, workspace lock, package configuration, and executable hashes were verified after the gates.

The runtime was Flutter **3.47.8**, framework revision `737ba8f885dc774b53b442759999a312c9461e4e`, and Dart **3.13.7**, matching `.fvmrc`. Workspace resolution used the recorded lock with `--enforce-lockfile` and resolved 110 packages without changing the lock. No tracked SDK or dependency change was needed. See [runtime.json](runtime.json), [source-binding.json](source-binding.json), and [results.json](results.json).

### Failures investigated and repaired

- **Field-scan regression:** Adding a caret-aware default initially caused repeated field scans. The first document build now reuses its initial inventory; the existing performance assertions pass. The focused 15-test result and the original broad failure log are retained.
- **Prior PR search fixture:** The previously unexecuted connected-search test tapped Search before a frame reflected the typed query. It now pumps that frame and asserts the button is enabled and hit-testable. The isolated test and full 49-test file passed; production search behavior did not need a workaround.
- **Note fixture lifecycle:** Three tests left a 400 ms proofing timer pending. An isolated, clean `b2597485` checkout reproduced all three failures (eight passes, three failures) using its own workspace package roots. Unmounting the widget and disposing its externally owned controller before returning repairs the fixture; the 11-test focused run passed. Behavior assertions were retained. The baseline binding, logs, and exact repair patch are included.
- **Incoming inherited-language assertion:** The newly merged proofing test expected an inherited `de-DE` language to be stamped into a direct run override. It now verifies the saved document default, the absence of a direct override, the reopened effective language, and live inheritance when the default changes to `fr-FR`. Explicit proofing enablement remains asserted. The focused 28-test file and final editor gate passed. No production change was required for this failure.
- **SDK wrapper startup race:** Two concurrent wrapper launches collided on `engine.stamp.tmp.17` before any tests started. Final gates call the pinned Dart executable and Flutter tools snapshot directly. The replay recipe also runs gates sequentially. The startup-failure logs remain included.

Original failing broad logs, intermediate repair runs, and final successful logs are kept in [logs/](logs/). Earlier failure logs and a patch containing significant whitespace are stored losslessly as gzip files; the log index records their original names and hashes. Earlier source snapshots are labeled separately; they do not replace the final source binding.

## Reproduce locally

Install and bootstrap the `.fvmrc` Flutter version from the official Flutter repository or the project's usual SDK manager. Set `FLUTTER_ROOT` to that SDK and complete its normal version/precache setup before resolving the workspace. From a clean checkout of this evidence commit:

```bash
export PATH="$FLUTTER_ROOT/bin:$PATH"
cp docs/validation/zotero-wordlike-continuation-20261118/workspace-pubspec.lock.txt pubspec.lock
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" pub get --enforce-lockfile
python3 docs/validation/zotero-wordlike-continuation-20261118/run_local.py \
  --repo . --output /tmp/zotero-wordlike-local-results
```

[run_local.py](run_local.py) is a syntax-checked replay recipe for the same selected suites and analysis/format gates. The historical runs were invoked directly; their expanded command arguments and logs are recorded in `results.json`. The recipe rejects tracked changes at entry, checks the SDK version and recorded lock, records source/runtime hashes, checks that they and HEAD remain stable, and emits its own `results.json`. It does not start GitHub Actions.

All files in this evidence directory, excluding `manifest.json` itself, are SHA-256 indexed by [manifest.json](manifest.json).

## Acceptance limits

The tests exercise local models, controller behavior, widget interactions, and mock native transport. This continuation did not run a live Zotero desktop/account session, reopen the resulting documents in Word or LibreOffice, or build a native application bundle. These results therefore do not establish full interoperability or complete plugin parity. The explicit Notes-pane boundary above also remains.
