# First-use catalog insertion through real Zotero

**Passed:** a document without Zotero preferences acquired its native style, opened the native citation picker with a linked catalog source and page locator selected, inserted one footnote through the same staged Word session, and retained the result after DOCX save/reopen.

This is an additional live acceptance scenario. The earlier catalog/refresh evidence and its integrity manifest are unchanged.

## Successful sequence

1. The actual Quds local catalog client queried the isolated Zotero library for `Synthetic Native Acceptance Alpha` and received its CSL snapshot and persistent local URI.
2. A fresh `WmlDocument` contained only `Before After`, with the insertion offset after `Before `. It had no fields, notes, or native document style.
3. The actual citing client ran `setDocPrefs`. Zotero displayed its native preferences dialog with the installed Chicago subsequent-ibid style, German Germany, and footnotes; those settings were confirmed.
4. The original document was still unchanged. `WordZoteroCitingSession.continueWithCitation` seeded the selected source and page `12` in the **same session**.
5. The citing client ran `addEditCitation`. The real native picker displayed the seeded Alpha source and `p. 12`. Its checkmark was clicked to accept the displayed source and locator.
6. The command completed, `hasAcceptedSeedCitation` was true, and the original document remained unchanged until the harness called `apply` once.
7. The saved and reopened DOCX contained one footnote citation, its persistent source URI, page `12`, and the German native style preferences. No formatting review warnings occurred.

The final citation is:

`Anna Beispiel, Synthetic Native Acceptance Alpha (Acceptance Test Publisher, 2024), 12.`

The source title is italic. `docx-verification.json` also verifies the exact body sequence: `Before `, footnote reference `1`, `After`. `result.json` records assertions from the actual adapter run; `raw-logs/protocol.jsonl.gz` preserves both complete native command exchanges.

## Bounded initial attempt

The first attempt opened the correct native preferences and seeded picker but tried to change page `12` to `34` through Zotero's utility popup. This environment's routed keyboard input did not update that field; a clipboard attempt timed out as well. The picker was not accepted before the harness's explicit **120-second** request bound expired. The driver reported no applied document changes. That attempt is preserved under `attempt-1-locator-edit/` and is **not counted as a pass**.

After closing and reopening the same isolated Zotero profile, one bounded retry accepted the already-displayed source and page `12` directly. This verifies locator acceptance and persistence. It does not claim successful native popup locator editing. The earlier native refresh scenario separately verifies changed-page processing and `Ebd., 34.`.

## Reproducible source and runtime identity

The successful run used source commit **`72691877bd9bafab761e655c13d0c9a0936b55bb`** with no tracked source modifications. Before compilation, the harness captured SHA256 values for **455 production Dart/manifest files**, its scripts, the genuine Studio graph's manifest/lock/package configuration, and the actual Dart binary. The complete snapshot is `source-before.json.gz`.

The harness was compiled once to a Dart kernel and then the native terminal executed that exact file. Its SHA256 was recorded before execution and checked afterward:

`4a1a9f915df18bbe5587100827377fb8b303a068fe2d0c3684462b97dae02bb6`

The kernel is 27,437,408 bytes. It is not committed; the exact executed script and compilation command are retained. All 455 captured production/manifest inputs were unchanged after native execution. See `receipt.json` for the complete source/runtime/kernel identity and isolated-profile details. Official Zotero **10.0.8** and Dart **3.13.7** from Flutter **3.47.8** were used, with the same pinned CSL and isolated synthetic profile as the parent acceptance run.

## Reproduction

Use the parent README to prepare the isolated profile, three synthetic sources, pinned CSL, and genuine Studio dependency graph. The scripts preserve their original workspace paths. Place rebased copies under `zotero-native-acceptance/first-insertion` beside the Quds checkout; preserve the directory relationship used by the relative Studio import.

Compile before launching the native scenario:

```sh
source /workspace/scratch/7b8555dd0115/zotero-toolchain/env.sh
"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" compile kernel \
  --packages=/workspace/scratch/7b8555dd0115/zotero-toolchain/harness/quds_office_studio/.dart_tool/package_config.json \
  /workspace/scratch/7b8555dd0115/zotero-native-acceptance/first-insertion/first-insertion.dart \
  -o /workspace/scratch/7b8555dd0115/zotero-native-acceptance/first-insertion/first-insertion.dill
```

From a native desktop terminal, run `bash start-existing-isolated.sh`. It uses explicit profile/data paths and deliberately omits the import flag, avoiding duplicate fixture imports. In a second native terminal run `bash run-first-insertion.sh`. Confirm the pinned German footnote preferences, then confirm the picker with the Alpha source and page `12` already selected. The scripts use the actual Studio native transport, actual citing client, and actual Word session. No account is needed.

Both native attempts ran only against the synthetic profile. Zotero was closed cleanly after the successful run. Full Flutter app UI/build, the editor undo UI, private-account workflows, and native locator-popup editing are outside this successful acceptance scope. Widget/controller tests separately cover the editor's transaction and cancellation behavior.

The original and compressed hashes of all gzip files are in `compressed-integrity.json`; all preserved artifacts have hashes in this directory's `artifact-integrity.json`. No GitHub Actions were queried or awaited.
