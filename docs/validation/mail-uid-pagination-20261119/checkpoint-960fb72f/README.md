# First frozen UID discovery checkpoint — PASS, followed by a concurrency repair

Source `960fb72fe904da92c41126b44fa65257931c6d65`, tree
`2effd3b4cb816ef29d485d90099364219a22005d`, passed all planned gates
on 19 November 2026. This is preserved historical acceptance for that source.
The subsequent incoming `0669ac11` repairs cursor-token reuse across completed
and repeated sweeps; the combined source requires fresh qualification. The
earlier passing tests did not detect that concurrency defect.

| Gate | Passing executions |
| --- | ---: |
| Core/store VM and Node | 250 |
| Native transport, TLS, fork protocols, MIME and UI | 694 |
| Additional Node | 56 |
| **Total** | **1,000** |

The independent [raw-event audit](audit.json) identifies **868 distinct
suite/name scenarios across 79 test files**; 132 executions repeat scenarios
on VM and Node. All 93 hidden loader events are excluded. There are zero failed,
skipped, unfinished, duplicate same-platform or missing-suite cases.
**90 Python controls** pass separately: 20 shared runner, 16 runtime restoration,
12 AyaSpell offline and 42 Mail runner controls.

All 5,044 bound source inputs match their Git objects; all source/runtime
snapshots are unchanged. The audit checks 11,142 retained runtime files, four
additional native/Node inputs and 11,156 total runtime/configuration records.
Strict analysis, formatting, offline lock enforcement and browser entry/worker
compilation pass. Compilation and Node do not qualify actual browser storage.

[complete-results.tar.xz](complete-results.tar.xz) retains all 85 original
output files, including raw logs, generated browser JavaScript, receipts and
source/runtime snapshots. Its [index](complete-results.tar.index.json) binds
every member. [development.tar.xz](development.tar.xz) separately retains
13 author/setup/repair observations, including failed attempts; these are never
added to accepted counts. The case inventory is compressed losslessly as
[cases.json.gz](cases.json.gz); its uncompressed digest is recorded in the audit.

The published-source audit accounts for all 417 preflight refs through ancestry
or 14 freshly reverified historical equivalences. All 4,632 non-Mail package/app
entries still match the reconciled initial baseline at this checkpoint. Later
Arabic/Hunspell changes arrived after this qualification and are separate work.

No GitHub Actions workflow, job, status, dispatch or rerun was used. Runtime
qualification is Linux VM/Flutter and Node; external Mail accounts, OAuth hosts,
other operating systems and actual browser persistence remain outside scope.
