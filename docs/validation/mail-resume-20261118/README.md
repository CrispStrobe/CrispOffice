# Mail continuation after workspace recovery — 18 November 2026

This continuation restores the remote M05 checkpoint into a fresh workspace,
reconciles incoming Office work before new implementation, and qualifies locally.
GitHub Actions are not queried, awaited, or rerun. Remote checkpoints use
`[skip ci]` and non-forced expected-head updates.

## Recovery boundary

The new workspace started with about 59 GiB available. The previous checkout,
disposable worktree, and unsaved raw logs are absent. Their historical recovered
summaries remain unchanged; no new evidence is presented as those missing logs.
The saved tree at `514c341d985e01bbc38f8ec4a1f5708e2b7fc8f3` was restored with Git.

## Incoming reconciliation completed first

The [captured inventory](incoming/capture.json), [reproducible audit](incoming/audit_refs.py),
and [result](incoming/audit.json) account for all captured external refs:

| Source | Ancestors | Reverified historical equivalents | Unaccounted |
| --- | ---: | ---: | ---: |
| Fork branches (excluding this branch) | 197 | 14 | 0 |
| Pull request heads (excluding #172) | 160 | 14 | 0 |
| Original upstream branches | 4 | 0 | 0 |

Nine newly observed commits were integrated. They include PR #175's inline Notes
review and exact header/footer navigation, PR #173's IME reconnection and Zotero
ordering/guard fixes, and PR #174's thesaurus acceptance evidence. Main was
already included. Historical equivalents were checked against complete Git
trees, exact change records, or all changed-path tree entries as appropriate.
This is a bounded capture, not a claim that remote branches stop advancing.

The merges were automatic. The combined `office_controller.dart` and
`word_zotero_dialog.dart` retain both incoming feature sets. Raw recovery patch
files were preserved byte-for-byte; their blank patch-context lines are not
source whitespace defects.

| Remote checkpoint | Purpose |
| --- | --- |
| `093242ade211fde18ddcde3ddf309fdb2a68fa0c` | Notes review/header navigation integration |
| `bbdcdc7c799b1d1feb7d3a3c18b9cebee615c2b1` | Latest Zotero/thesaurus/main follow-ups; all captured heads accounted for |

Each published tree was compared to the local merge tree, fetched back, and
used as the local branch's next parent. Git transport permits reads in this
workspace; authenticated GitHub connector writes save commits and refs.

## Qualification repairs

The 18 saved runner fixtures executed successfully. Independent adversarial
review then reproduced acceptance of a failed/skipped hidden loader and malformed
records without an opening object brace. The parser now accepts only explicit
native build/link-hook progress around complete JSON objects, rejects malformed
or non-object records, and requires every hidden completion to succeed without
skipping. Hidden cases remain outside substantive test totals.

The expanded 29-fixture suite also verifies the complete runner: a nonzero
process exit, including SIGKILL, cannot be overridden by successful events, and
exit zero cannot override incomplete or invalid events. These controls pass.
The pending native-platform test formatting repair is applied. Incoming recovered
Office files also receive formatting and strict analysis before qualification.

## Current gates

The restored official Flutter 3.47.8 / Dart 3.13.7 archive and 176 locked hosted
archives are verified. The workspace lock is unchanged. The default SQLite
3.54.1 native binary and FTS5 preparation probe are verified separately from
product regression counts.

Full Mail and integrated Office qualification are pending this checkpoint.
Actual browser rendering/persistence, mobile/device qualification, live mail
accounts and SMTP remain separate open acceptance gates. The existing M05
historical BLOCKED receipt is not rewritten as a new passing result.

M06 native transport foundation is being developed in an isolated checkout so
its unfinished changes cannot alter the M05/Office qualification inputs.
