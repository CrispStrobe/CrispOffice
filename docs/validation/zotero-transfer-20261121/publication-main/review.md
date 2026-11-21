# Publication-main supplemental review

Merged `290dfa43e3bcf410d9bf1bd8194c997c4ee613ae` into `1cad8c01f455e63a6af483d68010073dfe0c1ed8` as `24165f5ca6aff2d2a0c371ea473d82eba1e10f16`. The retained Git records
show the exact parent identities, incoming history and file deltas. This review
does not query or wait for GitHub Actions.

The product delta is confined to the editor proofing scheduler. It skips
automatic passes with no applicable provider, avoids caching empty provider
selections, and suppresses listener notifications when a local pass changes no
painted mark. Two focused scheduling cases accompany those changes. The Studio
benchmark now forwards provider categories. Two native SQLite fixture setup
operations use `tester.runAsync` so real isolate/file I/O can complete. No engine
source changed during this merge. Documentation conflicts were resolved by the
integrator, preserving the incoming scheduling explanation and the transfer,
ODT and Word qualification notes.

All three completed engine cohorts retained a deliberately broad 1,967-file
snapshot. Exactly 1,966 still match; the sole difference is
`packages/quds_office_editor/lib/src/proofing/word_proofing.dart`. That full-snapshot difference is preserved. The narrow
exception is bound to its exact old/new SHA256 values and to a reviewed
inventory of 915 unchanged engine and legacy-parser Dart
files, including library, tests, tools, conditional import/export URIs and both
local package manifests. The standalone verifier checks the inventory against
the checkout and rejects additional differences or editor/Flutter imports.
Some engine tests read font assets from the editor package; those data paths
are not compiled editor dependencies and no font asset changed in this merge.

The portable VM/JavaScript scope remains exactly 1,580/1,580 inputs and the
actual LibreOffice converter replay remains exactly 357/357 inputs. Their
original receipts and timestamps are retained; they were not relabeled as new
executions. The six editor cohorts and their aggregate, plus the clean
189-case Studio scope, are explicitly superseded because their tested inputs
changed. Replacement editor/Studio runs are pending when this bundle is sealed.
The new all-60-changed-Dart source gate is accepted at the merge revision and
replaces the historical 59- and 60-file source gates without changing their
archive bytes. This supplemental review adds no product test executions.
