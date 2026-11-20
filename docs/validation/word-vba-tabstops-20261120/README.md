# Word VBA custom tab stops

## Result

The Word adapter supports typed `TabStops` selectors, aliases, required `ByVal`
helper arguments, `With`, named/optional `Add` arguments and `ClearAll`.
Positions use exact 0.05-point increments from -1584 through 1584 points.
Four alignments and four leaders are supported. The native editing path
preserves unrelated direct and inherited stops, writes positional clear records,
and retains the existing replace-all behavior of `paragraphFormat.tabs`.

The implementation also fixes inherited-stop replacement and refuses ambiguous
native source, including custom tabs hidden in markup-compatibility alternatives.
Default-tab interval settings, indentation, unrelated XML and opaque VBA package
bytes remain preserved. See the [exact source contract](../../VBA_WORD_MACROS.md#custom-paragraph-tab-stops)
and the executable [BAS example](../../../packages/quds_office_engine/example/macros/word_tabstops.bas).

## Completed local qualification

The final local gate passed **2,114 test cases in 59 unique files, with zero
failures and zero skips**. It covers every one of the 42 `office_vba_*` test files
plus 17 native-operation, style, fidelity, preservation and ODT regression files.
The new tests contribute 85 compiler cases, 40 native cases and 10 integrated
execution cases to that same total; they are not counted twice.

| Check | Result | Evidence |
| --- | --- | --- |
| Frozen-source regression gate | 2,114 passing cases, 59 files, zero failures/skips | [Summary and case counts](regression.json), [raw evidence archive](regression-evidence.tar.xz) |
| Whole engine strict analysis | `dart analyze --fatal-infos packages/quds_office_engine`; no issues | [Analysis receipt](analysis.json) |
| Formatting of all changed Dart files | 9 files, zero changes | [Formatting receipt](format.json) |
| Actual BAS on Dart VM and compiled JavaScript | Matching canonical and raw JSON; seven operations, native save/reopen, boundary precision, named evaluation order, six refusals and late-failure rollback | [Portable receipt](portable.json), [semantic result](portable-result.json), [raw logs](portable-logs.json.gz) |
| Dependency identity | Dart 3.13.7; all 56 shared hosted versions match the repository lockfile | [Runtime record](environment.json) |

All accepted regression cases ran against source checkpoint
`b5410b107a83f213e27c1476e766551b3f6cd6a4`, tree
`4ac401fd0cd2de3fe5f305bf605f20fdc728d3f2`. The archive binds all **1,110 recorded
repository input files** to exact Git mode/type/blob identities and SHA-256
content hashes. Before/after manifests match throughout the run. SDK and package
identities are recorded separately in the runtime record.

The first two complete test batches were retained when the remaining batches
moved to two bounded serial runners. Every file appears in exactly one accepted
batch. The collector independently checked case start/completion pairing, suite
declared counts, successful final events and raw-log hashes. Hidden loading/setup
events are excluded. Case identities include the file, full test name and
occurrence ordinal, so repeated test names are counted correctly. The original
third-batch startup was stopped before Dart ran and contributes no accepted cases.

The archived [partial checkpoint](partial-regression.json) saved the first 881
completed cases during execution. It is a subset of the final result, not an
additional pass count. [Development evidence](development-evidence.json) preserves
superseded attempts, rejected empty JavaScript output and the before/after
markup-compatibility review probe; those attempts also do not inflate the final
count.

## Reproduction and scope

The archive includes the exact file selection, commands, raw JSON reporter logs,
per-batch receipts, source manifests, runner scripts, controlled handoff record,
isolated dependency manifests and an independent evidence review. Paths in those
historical scripts identify the validation environment used for this run.

In a checkout with the repository dependencies resolved, the same test selection
can be run from the repository root with:

```sh
python3 - <<'PYTHON'
import json
import subprocess
from pathlib import Path

root = Path.cwd()
record = json.loads((root / 'docs/validation/word-vba-tabstops-20261120/regression.json').read_text())
for group in record['groups']:
    subprocess.run([
        'dart', 'test', '--compiler', 'source', '--concurrency=1',
        '--timeout=4x', '--fail-fast',
        *['test/' + name for name in group['files']],
    ], cwd=root / 'packages/quds_office_engine', check=True)
PYTHON
```

This qualifies the bounded pure Dart Word/Office implementation. It is not a
claim of complete VBA or COM compatibility, execution of embedded VBA projects,
or comparison against an installed Microsoft Word host. Live `TabStop` objects,
collection reads/indexing/enumeration and arbitrary Word ranges remain outside
this increment. Table inheritance follows Quds's existing whole-table,
horizontal-band and first-row layers; other conditional table regions remain
unmodeled and their native definitions are preserved. See the source contract
for precise `ClearAll` limits.

The incoming Mail, Flutter, credential-store, Zotero and provider workflows retain
their own source-specific validation records. This engine gate does not qualify
those product runtimes. GitHub Actions was neither queried nor awaited.

The [source reconciliation record](reconciliation.md) documents the original and
refreshed branch/PR inventories, later incoming changes and inclusion proofs.
The initial capture below remains preserved as historical evidence.

## Initial source intake

This increment starts from remote checkpoint `49d0fe9966edff96e2cbda7e483a9ba8a689219a`, tree `0417c5d9c881cb7835c840419812cb909968ac48`. It preserves both integration parents:

- `d8ee0c9a6b61b925ac27750e04124a82d82b8b33`: recent Mail drafts/accounts, Word/PowerPoint VBA, Zotero and completed main work.
- `aedb870e32ffd1842ddd40329bd2e12995281a1b`: subsequent Mail EWS regression coverage for composing local drafts while provider capabilities are read-only.

The locally constructed integration commit `01f69b2bbcf716ec5d2fcf4137092377c794d10e` and the published checkpoint have identical tree and parent identities. GitHub recreated the commit for authenticated publication; the audit below is bound to the published checkpoint.

## Captured source inventory

[Machine-readable intake](intake.json) records every captured branch and PR head, upstream heads, ancestry results and independently recomputed historical equivalence checks.

| Inventory | Ancestral heads | Historical equivalents | Uncovered |
| --- | ---: | ---: | ---: |
| 18 fork branches | 9 | 9 | 0 |
| 252 PR heads | 238 | 14 | 0 |
| 4 upstream branches | 4 | 0 | 0 |

All 14 historical equivalence proofs were recomputed from Git objects. Thirteen historical and accepted commit pairs have identical full trees. The ODT continuation pair has identical mode, type and blob identity across all 37 originally changed paths. Every accepted equivalent is an ancestor of the published checkpoint. Those older branches therefore contribute no missing source changes that require another merge.

The captured open PRs were #249 (Zotero research tables), #251 (Mail accounts) and #252 (Word/PowerPoint VBA expansion). Their exact captured heads are ancestors of the published checkpoint. Source inclusion does not imply that those PRs were separately closed or merged through the GitHub PR interface.

### Fork branch heads

| Branch | Captured head |
| --- | --- |
| `codex/odt-field-continuation-20261117` | `c34945761e7991f5fe49037d79529acdd260b31c` |
| `codex/word-powerpoint-vba-expansion-20261120` | `0f6239396ff3328473a5f57c280b982d57e33a08` |
| `codex/zotero-research-tables-20261120` | `93dc987cf993787bd613018b3028e7ad60d5472a` |
| `docs/ods-color-scale` | `58fdddfbcf198a8c0e38e32f6fcc9d6604e95283` |
| `docs/ods-data-bar` | `69d14f84cabd3931b7640c1654b401c89faba766` |
| `feat/ods-color-scale` | `74ce9ffb816c70c0d2ae50b91ec52a614f26d688` |
| `feat/ods-data-bar` | `0a53b8a70128870f3e1df6d18cdb177bb64290ee` |
| `feat/ods-dynamic-validation-links` | `68a0db23408e4c95d6d283219504c79aea33a6fe` |
| `feat/ods-icon-sets` | `005c708e9f747cb46cf02e12c869b0a2f85ac824` |
| `feat/ods-time-period-conditions` | `7ef09f2408f467c65427700e65907531ecb26acb` |
| `fix/mail-credential-stores-chrome-20261120` | `a652a205e6daf6b4b8e3baec04db1c1b52fabd0d` |
| `integrate/office-union-148` | `3abf8f43b0e79c10271bbd046f391e462b8fe6b9` |
| `integrate/recent-pptx` | `4f5c153774ab7492430c2b68653c54e0c08dc2ad` |
| `main` | `13be50464d1b43e9f2100fb9ccc12f8fe22eb55e` |
| `work/mail-accounts-20261120` | `c20b41d9c7eed574c02e49f1fd96789843aec2e6` |
| `work/mail-multiple-drafts-20261120` | `aedb870e32ffd1842ddd40329bd2e12995281a1b` |
| `work/mail-outbox-20261120` | `9443612b024114c424ba2f8146e04050d6e049b0` |
| `work/mail-outbox-management-20261120` | `d8ee0c9a6b61b925ac27750e04124a82d82b8b33` |

The new `codex/word-vba-ranges-20261120` checkpoint branch was created after this initial 18-branch capture; it is not included in that count. The captured main head is `13be50464d1b43e9f2100fb9ccc12f8fe22eb55e`.

### Upstream heads

The upstream repository is `MohammedAsaadAsaad/quds_office_suite`.

| Branch | Captured head |
| --- | --- |
| `ci/flutter-workspace` | `aca2f66941832bd0b19b436baeab1656a1b7de98` |
| `cursor/class-certificates-2db8` | `f45099688e7a3f67a1302efdb442830d052f2240` |
| `cursor/cloud-agent-1790580069020-0rk1h` | `9930be8df44ffe117fb22778c514eea0ee73ce21` |
| `main` | `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba` |

## Scope of the initial intake

The initial intake section records source/history inclusion at checkpoint
`49d0fe9966edff96e2cbda7e483a9ba8a689219a`. Later reconciliation is recorded
separately and the completed execution results above are bound to their own
qualified source. Inclusion of a captured PR's source does not require changing
that PR's separate GitHub interface state.
