# Incoming frontier audit for Layout and theme integration

The refreshed VBA and mail tips can be merged by ancestry into the checkpointed
GUI branch. The newer mail tip adds validation records only. The newer VBA tip
adds one parser correction and two regression cases, and incorporates the earlier
GUI core checkpoint without changing any of its eleven editor source/test files.
Keep the later GUI work in the current branch and run the focused acceptance
selection below on the final merged source.

## Pinned revisions

| Revision | Exact commit |
| --- | --- |
| Starting integration baseline | `37ac6ea8a08225a42098c455deb5375837912eec` |
| Initial GUI core checkpoint | `4fd010fcae209b6ea033828d76908508b7327b9f` |
| Originally audited VBA tip | `ac9de9e000274718145659da0abc7c8cadb9e8c3` |
| Originally audited mail tip | `0c77b3488eb534868a7f98271ba2923d06759b8d` |
| Refreshed VBA tip | `ae4c8223d1814df4a500518c8b223831cbb0b51f` |
| Refreshed mail tip | `1a99845fe628c9e539d4bca7e7c586c5616da267` |

The original two tips share formatter commit
`358544a48466c942873a4718a87fa9d1c2be11f7`. The refreshed tips share the older
mail tip `0c77b3488eb534868a7f98271ba2923d06759b8d`; neither refreshed tip contains
the other. Both therefore need integration. Root's full remote capture at
`../remote-capture.json` records these branch tips and the corresponding PR head
refs, 209 for mail and 210 for VBA. The refresh audit records the exact capture
hash rather than implying an additional remote query.

## Independently checked changes

The original audit, preserved as `audit.json`, records the following:

- The eight Dart changes in the mail formatting commit exactly match the pinned
  formatter's output. Each baseline blob was fed through the formatter's stdin;
  the result was compared byte for byte without changing a working source file.
- The final original mail commit changes documentation and validation selection,
  with no product or test delta. It correctly removes a native SQLite test from
  the Node selection.
- Seventeen archive restoration product/test/tool paths already present in the
  starting baseline are byte-identical at both originally audited tips.
- Seven historically accepted branches were checked again: all 291 changed-path
  blob comparisons match their recorded accepted merge trees. Those accepted
  merges are ancestors of the current GUI branch. Existing equivalence evidence
  should be retained instead of replaying the historical branches.
- The functional VBA addition includes bounded arrays, source coordinates,
  `For Each`, and a 1,048,576 UTF-16-unit active-array string storage budget.

The separate `audit-refresh.json` binds that unchanged original report to the
newer tips and records these additional checks:

| Follow-up | Classification and result |
| --- | --- |
| Mail `0c77b3488` → `1a99845fe` | One commit, 415 changed paths, all documentation/validation evidence; no source or test change. |
| VBA evidence commit `edd350866` | 94 documentation/validation paths; no source or test change. |
| VBA parser fix `c3eaf57c8` | One compiler file and one test file. Procedure-local declared array names disambiguate indexed writes from bare helper calls with parenthesized comparison arguments. Two regression cases cover both forms. |
| VBA merge `ae4c8223d` | Incorporates GUI checkpoint `4fd010fca` and older mail tip `0c77b3488`. All eleven imported GUI core paths exactly match their GUI checkpoint. |
| Previously checked restoration and formatting | All seventeen restoration paths and all eight verified formatter outputs remain unchanged at both refreshed tips. |
| Prior reconciliation evidence | All three selected historical frontier evidence files remain byte-identical, and all seven accepted merge ancestries remain intact. |

The full refreshed VBA delta contains 101 documentation/evidence paths, nine
product paths, and four test paths. Eight of those product paths and three test
paths are the already tested GUI checkpoint; only the compiler and array test
file are new functional follow-up changes.

## Focused local acceptance after integration

`audit.json` contains ten runnable command arrays under `qualification.gates`,
including repository-relative working directories and exact local toolchain
paths. Run them serially on the final merged source and retain command output,
exit status, source identities, and test-event counts with the GUI receipts.
Do not wait on GitHub Actions.

| Gate | Selection and purpose |
| --- | --- |
| `vba-scoped-analysis` | Changed compiler, the three arrays suites, and array web smoke. |
| `vba-vm` | Eleven suites: three array, language/integration, three procedure, and three control-flow suites. They share the changed parser/runtime. This includes the two newest parser regressions. |
| `archive-scoped-analysis` | The seventeen restoration product/test/tool paths already integrated at the starting baseline. |
| `archive-native` | Six native suites: multi-origin transactions, restore, adversarial restore, repository, native archive, and export manifest. |
| `archive-portable` | Export manifest and declared browser boundary on Node. `archive_query_test.dart` imports native SQLite and belongs on the VM, so it is not part of this Node gate. |
| `archive-studio` | Three suites for restore interaction, genuine native restore, and narrow/localized portability layouts. |
| Array web compile and Node | `tool/macros/web_vba_arrays_smoke.dart`, including allocation/iteration bounds, source safety, MCP entry points, and nested-depth boundaries. |
| Control-flow web compile and Node | `tool/macros/web_vba_control_flow_smoke.dart`, protecting shared loop-work and evaluation behavior on the portable runtime. |

The Node smoke gates include explicit `required_json_true_fields` and
`coldDepthStress_contains` expectations. A zero process exit alone is not enough
to qualify the emitted JSON. No extra test files are needed just for the newer
tips; their parser regression is already in the selected arrays suite.

To inspect the exact runnable commands from the repository root:

```sh
python3 - <<'PY'
import json
from pathlib import Path
import shlex

report = Path('docs/validation/crispoffice-layout-theme-20261119/incoming/audit.json')
for gate in json.loads(report.read_text())['qualification']['gates']:
    print(gate['id'])
    print('  cwd:', gate['cwd'])
    print('  command:', shlex.join(gate['argv']))
PY
```

Use the current serial runner to execute those arrays. The inherited author
validation scripts assume another runtime/workspace and should not be launched
wholesale in this shared compiler session.

## Reproduction and limits

`audit_frontier.py` reproduces the original pinned-tip checks, including the
formatter replay. `audit_refresh.py` reproduces the follow-up classification and
hash comparisons against the saved original report and root's remote capture.
The refresh script writes only `audit-refresh.json`; it does not overwrite the
original report.

This audit ran Git reads, byte comparisons, and the pinned formatter. It did not
run a compiler or tests, merge, push, query GitHub Actions, or independently fetch
remote refs. Historical PR mappings come from preserved evidence; ancestry and
blob equality were independently checked locally. The inherited mail receipts
document their author's acceptance, while final merged-source qualification
belongs to the current local gate run.
