# Zotero native ODT continuation — intake checkpoint

## Status

**Implementation and final merge are blocked by the local execution environment.**
This checkpoint contains a remote-reference audit and a source-grounded
[implementation contract](../../roadmaps/zotero/native-odt-input.md).
It adds no application code or tests, does not claim new Zotero capability,
and must not be represented as a qualified native ODT implementation.

The user authorized incremental remote saves, intake of recent branches/PRs,
and eventual consistent merge to remote main, without waiting for GitHub Actions.
The working branch is `codex/zotero-native-odt-20261121`.

## Frozen intake

Captured target: `1ef5f7f88705e05bb2ebd2f5b639460dab52c3d0`, tree
`6167ba3499df3f06ec531e7a8c7143dda58c9143`.

[intake.json](intake.json) records all **353 references** in this snapshot:
51 fork branches, 298 PR heads and four upstream branches. The PR collection
was read through pages containing 100, 100, 98 and zero entries. No PR was open
in the snapshot. The new checkpoint branch was created afterward and is
excluded from those counts.

Every captured fork branch was freshly compared against the captured main.
Older unchanged PR/upstream heads inherit exact-SHA dispositions from the
[prior committed intake](../zotero-nested-tables-20261121/intake-final.json).
Its target `ed30a633a96960552d4fab11bd6e3226ee73ca14` was freshly verified as an
ancestor of the captured main. This distinction is explicit in the JSON;
inherited audit results are not new local Git executions.

| Disposition | References |
| --- | ---: |
| Freshly verified ancestors | 73 |
| Captured main itself | 1 |
| Ancestors from the preserved prior audit | 253 |
| Historical equivalents from the preserved prior audit | 24 |
| New branch heads requiring reconciliation and execution | 2 |
| Total | 353 |

These are reference counts; several references point to the same commit.
The intake is **not fully integrated**. A closed PR does not prove that later
updates to its source branch are already in main.

## Outstanding incoming work

| Branch | Captured head | Actual difference from current main |
| --- | --- | --- |
| `perf/wrap-chrome-20261121` | `8716057f80c4c18b72c5a43a708beefd70bc7588` | Adds the first three keystrokes' listener-call diagnostics and the coalescing setting to the typing benchmark report. The main and branch file blobs differ. |
| `fix/main-green-20261120` | `0e14940e0e1521c7eb143f83f0abc18b8f65e1c9` | Three unmerged commits: CLI test migrations, a main merge, and a WIP shared CLI kernel cache. The diff includes ten test migrations, the shared helper, and seven generated temporary test files. |

The WIP cache needs local concurrency, failure and lifetime qualification.
Its key derives from file paths, sizes and timestamps, so review whether SDK,
dependency and content changes can incorrectly reuse a kernel. Lock expiry,
publication, teardown and cache cleanup also need executable coverage.
These are review requirements, not reported runtime failures.

Both source branches remain intact. They have not been force-updated,
deleted, marked integrated with an ancestry-only merge, or overwritten.
The generated files are retained on their original branch pending a reviewed
integration decision.

## Source finding and next implementation

The fork already contains the native Zotero HTTP workflow, citation/metadata
editing, document-wide CSL refresh, bibliography formatting, research note and
annotation insertion, nested tables, and transfer carriers, with earlier
source-specific qualification. Those are baseline features, not additions
made by this checkpoint.

The next native-ODT milestone requires more than reference-mark recognition:
the tree has ODF text extraction and ODT output but no rich ODT input reader.
The new contract therefore separates:

1. A read-only native Zotero mark/preference inventory with exact ownership,
   explicit findings and deterministic parser tests.
2. Rich ODT-to-Word import with validated field ranges, metadata conversion and
   editor transaction/publication behavior.
3. Actual Zotero/Word/LibreOffice plugin acceptance with identified versions
   and synthetic files.

Ordinary ODT export continues to expose cached citation results. The existing
transfer carrier and normal Word/HTTP field-type validation remain separate.
See the contract for exact source paths, pinned upstream code and test cases.

## Execution blocker and what was actually checked

The first shell inventory succeeded, but subsequent local commands failed
before command execution with:

```text
bwrap: Can't create file /workspace/scratch/763782a14a6d/.git: No space left on device
```

A workspace probe could not be written by the patch tool. Repeating a minimal
command, changing working directory, disabling login-shell startup and using a
PTY did not restore execution. No repository was cloned, and no Dart/Flutter
compiler, analyzer or test could start.

A read-only disk check outside the failing sandbox was also rejected by the
automatic approval policy because `sandbox_approval=false` and escalated
permissions cannot be requested in this environment. No permission or sandbox
setting was changed to bypass that refusal.

**New executable tests: zero.** No historical test total is counted as a new
run. No full-parity or installed-host claim is made.

Checks possible remotely:

- Exact GitHub source/branch/PR inspection and fresh branch comparisons.
- Consistency checks over the captured intake JSON in the orchestration runtime.
- Static source review, including the documented ODT-export contract.
- Byte-for-byte readback of the initial committed intake.
- Expected-head, non-forced publication of incremental branch checkpoints.

GitHub Actions, workflow runs and check statuses were neither queried nor
awaited. The runtime blocker is local, not the Actions queue.

## Remote checkpoints

1. `54f287b893ea704816c6cd8de8421996b5b2d1fb` — frozen intake and explicit blocker.
   Published with the captured main as its parent; the 108,073-character JSON
   was read back unchanged.
2. The following documentation commit contains this work record, the detailed
   implementation contract and a correction to the parity roadmap's ODT
   prerequisite. Its exact SHA is available in this file's commit history.

No application, dependency, workflow or test file is changed by this
checkpoint. Merge the eventual tested implementation after the environment
is repaired and the two incoming branches are reconciled. Do not substitute
this documentation checkpoint for the requested feature delivery.
