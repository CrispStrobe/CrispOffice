# Newer-main delta qualification

The committed implementation and plan files in this directory accompany the
reviewed Hunspell disposal repair. Freeze their source commit before running. The driver refuses an uncommitted
plan, missing fixture or changed source. The shared runner remains unchanged.

This gate reports only its own exact-source results. The prior **1,372 application
executions and 90 Python controls** retain source
`0669ac119da05f5eb777c8cfdbce32e0261df647`; none contributes to this delta's count.

The frozen selection has ten native suite/platform executions, five Node
suite/platform executions, 26 strict analysis/format targets, all 17 AyaSpell
bundle controls with verbose identities, and a browser transport compilation.
Native Hunspell uses the real compiled library, eight pinned dictionary files,
an independent lifecycle-counter library and the enabled live-download test.
No case-name filters or skip allowance are used.

The direct Dart offline resolver avoids Flutter's source-migration behavior.
Its receipt compares the integrator's preserved pre-resolution bytes with the
original gate fingerprint and requires all 131 prior mappings to stay exact,
with only the local Hunspell package added for 132 names. The original runtime
bootstrap receipt remains unchanged and explicitly historical. Runtime and
fixture hashes are frozen after resolution and checked again after execution.

Whitespace checks use incoming main `b655b8a37fddc874bd42a453c371eed6253e82d8`.
The three inherited upstream license files are bound by exact incoming identities;
no exclusions or whitespace edits are applied. Strict Dart coverage is checked
against both that main and the original qualified `0669` source. Static entitlement
checks verify the macOS network-client and user-selected-file capabilities;
these checks do not establish a macOS build or launch.

```bash
python3 docs/validation/office-main-sync-20261119/main-delta/run-delta-validation.py \
  --repo /workspace/scratch/79e6ad9e4046/quds_office_suite \
  --head NEW_COMMITTED_SOURCE \
  --runtime /workspace/scratch/79e6ad9e4046/quds-runtime \
  --fixture-root /workspace/scratch/79e6ad9e4046/hunspell-review \
  --pre-resolution /workspace/scratch/79e6ad9e4046/main-delta/pre-resolution \
  --prior-gate /workspace/scratch/79e6ad9e4046/final-integration-checks \
  --prior-audit /workspace/scratch/79e6ad9e4046/audit-review/final-0669ac11-accepted/independent-summary.json \
  --output /workspace/scratch/79e6ad9e4046/main-delta/final-checks \
  --command-timeout 600
```

The shared reporter parser provides execution receipts, and a separate independent
audit must recount the raw events, confirm the current frozen source and validate
the original-to-current workspace receipt before publication. Development RED/GREEN
probes from the native reviewer remain separate and are not added to this gate.
