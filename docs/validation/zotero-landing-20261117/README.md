# Zotero integration landing — 17 November 2026

Source and setup checkpoint; final local qualification is in progress.

The frozen implementation is Quds `837d06edbde08a2465e99cbbb15927ee4c87d8ac`
and CrispCloud `96c514eb98f7ba596a385c8f60496bc6c5994307`.
Both source checkpoints are saved on `codex/zotero-recovery-20261116`.
The host pins the exact canonical implementation and verifies 2,554 managed
files: 697 canonical files and the unchanged 1,857-file standalone parser.

All 206 captured canonical refs (198 fork and eight upstream) are ancestors
of the canonical implementation. All 290 host refs are accounted for: 214
ancestors and 76 exact whole-tree aliases to integrated ancestors. No
captured incoming ref remains outstanding. The snapshots retain timestamps
and identities; this is a bounded inventory, not a claim about future work.

The final source amendment changes six production files and four tests relative
to canonical `554eddc179856b648a83fa2b49f395071e8a7e71`. It combines German
agreement/context improvements with bounded formula evaluation, conditional
style serialization, and rename undo across saves. The existing 50 audited
Zotero paths retain their exact Git blobs and modes. Newer responsive spelling,
ODT citation hiding/whitespace behavior and strict-lint corrections are retained.

The attached prior-session notes reported a completed larger validation run,
but its terminal evidence was not present at the recovered remote checkpoints.
Those unverified counts are not adopted here. Fresh source-qualified canonical
and host checks are being run. The preserved baseline host guard and 28 Python
tests passed before the final sync; those baseline results do not qualify the
new source. Earlier failed runs and historical reports remain intact.

`source-setup-checkpoint.tar.gz` contains frozen inventories, inclusion and
preservation audits, guarded sync receipts, the prepared validation runners,
fixture preflight, baseline host checks and available setup provenance.
`checkpoint-index.json` binds every archived member and the archive itself.
No final test count or merge completion is claimed by this interim checkpoint.

All checks are local. No GitHub Actions, workflow, CI-status, wait or rerun
endpoint is used. Test source checkouts remain frozen while this evidence is
published from a separate worktree.
