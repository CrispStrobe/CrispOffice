# Mail header search: incoming source audit

Status: **PASS** at `bea51077b93ac7e7cab94b96778d8639892166f2`.

Captured 30 fork branches, 267 fork PR heads, 4 upstream branches and 4 upstream PR heads. Uncovered references: **0**. The complete compact ref inventory is in `intake.json`.

All 14 historical replacements were independently recomputed from Git objects: 13 complete-tree identities and the exact 37 changed ODT paths. File modes, types and object IDs agree, and every replacement is a target ancestor. These older branches therefore need no replay.

The captured recent fork work includes Word paragraph spacing/controls, macro CLI process cleanup, macOS deployment requirements, Arabic web-worker packaging/parity checks and the App Store submission draft. Capturing draft documentation does not submit an app or resolve owner decisions.

## Replay and refresh

From the repository root:

```sh
python3 docs/validation/mail-header-search-20261120/verify_intake.py
```

For a later capture, first fetch the fork/upstream branch and PR namespaces, then pass `--capture --target <commit>`. The checker only writes its report files, never Git refs. Unknown references fail the audit. This checks source inclusion, not runtime behavior; incoming validation is not claimed as a new run. GitHub Actions, workflow runs and status endpoints were neither queried nor awaited.
