# New worksheet comment ownership baseline

The exact observed canonical source is `4e8c8f80f206e93be8530a94da478e06c0f87608`, from app `3e9560c9b4bd617b5346bacd8b5039493f0f2dc1`. The saved baseline `55fe279284130d8691c9edcd3fe5ae68656a7037` adds four regression cases without changing production code.

All four tests fail as expected: valid orphan parts are deleted or overwritten when a new sheet is allocated; malformed unowned orphan parts cause a refusal after package mutation. These are diagnostic receipts, not passing acceptance. Existing source ownership is being inferred after assigning a new worksheet URI. The fix is still pending at this checkpoint.

## Evidence

- `failing-baseline/`: raw machine output, command, tool hashes, all source/resolution input snapshots and summary. Four failures, zero passes/skips; source, HEAD and resolution inputs stable.
- `review.json`, `source-binding.json`, `probe-results.json` and probe files: independent in-memory comparison against the preserved predecessor and exact incoming writer.
- `tools/`: exact recorder/parser used for the saved baseline.

The engine graph is derived from the settled host graph with canonical engine/parser roots and absolute cache roots. The recorded package config identifies every mapping. No package resolution, app changes, CI wait or later upstream refresh occurred. The direct test entrypoint avoids changing the workspace dependency graph.

The planned correction captures validated existing source ownership before mutation, never assigns an orphan to a newly allocated sheet, and retains a distinct empty authoritative comments part through reopen/add/clear. Subsequent commits will save the corrected source, focused runtime and strict analysis separately. Focused totals must not be added to host totals that run these suites again.
