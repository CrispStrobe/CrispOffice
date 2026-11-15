# New worksheet comment ownership baseline

The exact observed canonical source is `4e8c8f80f206e93be8530a94da478e06c0f87608`, from app `3e9560c9b4bd617b5346bacd8b5039493f0f2dc1`. The saved baseline `55fe279284130d8691c9edcd3fe5ae68656a7037` adds four regression cases without changing production code.

All four tests fail as expected: valid orphan parts are deleted or overwritten when a new sheet is allocated; malformed unowned orphan parts cause a refusal after package mutation. These are diagnostic receipts, not passing acceptance. Existing source ownership is being inferred after assigning a new worksheet URI. The failing baseline was saved remotely at `7a7fd2fe776d5733ddb824315e0768d01d1cbabc` before any production correction.

## Evidence

- `failing-baseline/`: raw machine output, command, tool hashes, all source/resolution input snapshots and summary. Four failures, zero passes/skips; source, HEAD and resolution inputs stable.
- `review.json`, `source-binding.json`, `probe-results.json` and probe files: independent in-memory comparison against the preserved predecessor and exact incoming writer.
- `tools/`: exact recorder/parser used for the saved baseline.

The engine graph is derived from the settled host graph with canonical engine/parser roots and absolute cache roots. The recorded package config identifies every mapping. No package resolution, app changes, CI wait or later upstream refresh occurred. The direct test entrypoint avoids changing the workspace dependency graph.

The planned correction captures validated existing source ownership before mutation, never assigns an orphan to a newly allocated sheet, and retains a distinct empty authoritative comments part through reopen/add/clear. Subsequent commits will save the corrected source, focused runtime and strict analysis separately. Focused totals must not be added to host totals that run these suites again.

## Corrected source and focused runtime

Corrected source is saved at `47e44e0ae35adcc406eee2a2ae2118dd2a4a082a`. The only production delta captures validated existing worksheet ownership before mutation and carries that captured part into extras serialization. New worksheets receive a distinct authoritative empty comments part when needed to shield an unowned legacy part, preserving its original XML and relationships through reopen/add/clear. The incoming namespace, shared-owner and deletion behavior remains covered.

`corrected-focused/` records **28 passing tests across the namespace and schema suites**, no failures/errors/skips or missing/unexpected suites. Source, HEAD and resolution inputs stayed unchanged. The command ran against the remotely saved correction. The new fixture generator emits three repeated-save packages plus six valid/malformed orphan lifecycle packages for an independent host-side reader; this canonical runtime gate does not claim that separate reader has run. Strict selected-file analysis is pending at this checkpoint.
