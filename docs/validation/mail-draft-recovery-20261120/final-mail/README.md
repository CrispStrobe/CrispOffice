# Final mail acceptance evidence

## Combined source acceptance 793dae7d

**The combined Mail and Office source is locally accepted with 1,245 successful
test executions represented, no failed or skipped cases, and no changing inputs
during either accepted run.** All 29 Studio mail suites were rerun after the
Office integration. The unchanged core/store results retain their original
source receipt and are carried forward through a separate input comparison.
GitHub Actions were not consulted or awaited.

- Combined source commit: `793dae7de10848b5a1ec0762e0fc4b55b70296f3`.
- Combined source Git tree: `59fc3e06df00a73e53c46f4f2591231c19eef06a`.
- The Studio rerun captured **4,424 product files and seven pinned
  runtime/configuration inputs** before and after execution.
- Its aggregate input SHA-256 remained
  `90c40feb38c37e022471f06912f517881b31a80c289047ef0cf3a70f72619fdc`.
- `accepted=true`, `source_unchanged=true`, `changed_inputs=[]`; HEAD remained
  the combined source commit throughout the rerun.

| Cohort | Suites | Passed | Qualification |
| --- | ---: | ---: | --- |
| core | 6 | 54 | Original frozen-source run; verified unchanged inputs |
| store | 23 | 562 | Original frozen-source run; verified unchanged inputs |
| store-node | 1 | 3 | Original frozen-source run; verified unchanged inputs |
| Studio mail | 29 | 626 | Fresh run on the combined source |
| **Combined accepted set** | **59** | **1,245** | **0 failed, 0 skipped** |

The [core/store reuse proof](reused-core-store-inputs.json) verifies all **96**
relevant core/store/root source, test, fixture and manifest inputs, all **seven**
pinned runtime/configuration inputs, and the unchanged declared resolution of
**60** transitive packages. All five mail package Git trees are also unchanged
between the two source commits. The proof is bound to the completed combined
receipt and its matching after-execution manifest. The original core/store/Node
receipts remain attributed to `81b0d762`; they are not relabeled as a new run.
The dependency proof records the identical locked resolution and verified
initial archive provenance, rather than a new byte manifest of every installed
hosted dependency file.

The Office merge changed Word dependencies used by the composer, so the complete
Studio selection was rerun against those changes. Its 626 cases **replace** the
earlier Studio contribution in the combined count. Earlier development checks
and repeated Studio executions are not added again. The original strict analysis
and formatting gates below retain their recorded source scope.

- [Combined Studio receipt](combined-793dae7d/receipt.json)
- [Combined selection](combined-793dae7d/selection.json)
- [Combined input hashes before](combined-793dae7d/inputs-before.json) and
  [after](combined-793dae7d/inputs-after.json)
- [Combined Studio raw events](combined-793dae7d/studio.jsonl)
- [Core/store result reuse proof](reused-core-store-inputs.json)

The executed follow-up command, from the repository root with the pinned
environment loaded, was:

```sh
python3 docs/validation/mail-draft-recovery-20261120/final-mail/run_final_mail.py \
  --attempt combined-793dae7d --only studio
```

## Source checkpoint 81b0d762

**All eight local gates passed, with 1,245 successful test
executions and no failed or skipped cases.** This run qualifies the mail source
checkpoint before the subsequent Office integration. GitHub Actions were not
consulted or awaited.

- Source commit: `81b0d7620bd7d57ee2d5fe878abbad85f0488a00`.
- Source Git tree: `9b0e35289863dc5256288ea957449313824eaee4`.
- End-of-run HEAD: `bbc114d4aee1d54564edb4c6f333830d5a8fdeea`; documentation changed during the run,
  while all captured product and pinned inputs remained unchanged.
- The before/after comparison covers **4,419 tracked or
  unignored product files and seven pinned runtime/configuration inputs**.
  The manifest covers source, tests and assets under `packages` and
  `third_party`, excluding documentation, build and tool-cache directories.
- Aggregate input SHA-256, identical before and after:
  `03d71807d092f02d28e3f5343bfc2d4e2690dea83d9da7fc75450d42f3c886c8`.
- `accepted=true`, `source_unchanged=true`, `changed_inputs=[]`.

The input count describes the fingerprint scope; it is not a claim that every
captured product file has independent test coverage.

| Cohort | Selected/loaded suites | Passed | Failed | Skipped | Raw runner events |
| --- | ---: | ---: | ---: | ---: | --- |
| core | 6 | 54 | 0 | 0 | [core.jsonl](checkpoint-81b0d762/core.jsonl) |
| store | 23 | 562 | 0 | 0 | [store.jsonl](checkpoint-81b0d762/store.jsonl) |
| store-node | 1 | 3 | 0 | 0 | [store-node.jsonl](checkpoint-81b0d762/store-node.jsonl) |
| studio | 29 | 626 | 0 | 0 | [studio.jsonl](checkpoint-81b0d762/studio.jsonl) |
| **Total** | **59** | **1,245** | **0** | **0** | |

Core and store VM tests cover their complete supported test directories.
`browser_problem_test.dart` declares `@TestOn('node')`; it was excluded from the
VM selection and passed separately under Node. The full Studio selection is all
**29** `studio_mail*_test.dart` and `studio_saved_mail_test.dart` files. These run
on the Flutter VM; a file testing browser-facing widgets does not imply a live
browser execution. POSIX crash/recovery cases ran on Linux, so their conditional
Windows skips were inactive.

The successful static gates were:

- Exact formatting check on 21 changed mail Dart files
  (`dart format --output=none --set-exit-if-changed`).
- Strict full-package analysis of mail core and mail store.
- Strict analysis of 17 changed Studio mail
  library, test and support files.

All static gates exited 0. Formatting changed no source. The receipt contains
exact commands, working directories, exit codes, durations and output hashes.

## Inspect or repeat the evidence

- [Receipt](checkpoint-81b0d762/receipt.json)
- [Exact selection](checkpoint-81b0d762/selection.json)
- [Input hashes before execution](checkpoint-81b0d762/inputs-before.json)
- [Input hashes after execution](checkpoint-81b0d762/inputs-after.json)
- [Runner](run_final_mail.py)

Each test cohort retains its raw JSON lines, stderr, and a separate list of real
application case results. Counts use unique test IDs and exclude hidden loading
entries, skipped tests and duplicate completion events. Acceptance also requires
an exit code of zero, a successful final runner event, no error events, and exact
agreement between selected and loaded suite paths. Missing suites cannot silently
pass the gate.

The runner uses the real pinned `package:test` entry point with the workspace's
generated locked package configuration. Flutter uses `test --no-pub`. Runtime
versions, official SDK/dependency hashes and SQLite initialization are described
in [local checks](../local-checks.md). Earlier development checkpoint executions
are not added to this final run's total.

After sourcing the session's pinned runtime environment, reproduce all gates
from the repository root with a new attempt name:

```sh
python3 docs/validation/mail-draft-recovery-20261120/final-mail/run_final_mail.py \
  --attempt another-source-checkpoint
```

An attempt directory is never overwritten. A focused integration follow-up can
use `--only studio`; it records another complete before/after input manifest and
runs the same 29-file Studio selection. Its repeated Studio cases must replace,
rather than be added to, the earlier Studio contribution when reporting a
combined accepted set.

These are synthetic provider, loopback protocol, real local SQLite and widget
checks. They do not claim live mailbox/provider qualification or an installed
macOS/Windows application run.
