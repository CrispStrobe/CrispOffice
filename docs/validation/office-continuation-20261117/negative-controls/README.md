# Historical negative controls

These records preserve tests run against the integrated pre-repair source at
`becfa07c1be62429a8bcf78910aa1ffb46248b1a`. They demonstrate existing failures;
they are separate from the passing final qualification. No tests were rerun
while collecting this bundle. No GitHub Actions, checks, or statuses were used.

| Run | Exact saved test variant | Real tests | Assertion failures | Passes | Runtime errors / skips |
| --- | --- | ---: | ---: | ---: | ---: |
| PDF | Historical two-file, ac295d4b-era snapshot | 33 | 30 | 3 | 0 / 0 |
| cmap | Earlier safe-probe snapshot | 45 | 41 | 4 | 0 / 0 |
| Sheet | Original conditional-fidelity snapshot | 28 | 17 | 11 | 0 / 0 |

Counts exclude hidden loader results. Each row describes its own source and test
variant. Do not add these overlapping historical runs to final passing cohorts
or describe their failures as current failures.

## PDF: original 33-case snapshots

`pdf/test_sources/` preserves the exact two test files and their fixture helper
used by the recorded run. The reader suite had 16 cases (13 failures, 3 passes);
the logical-export suite had 17 cases (17 failures). All 30 failures were test
assertions. The original runner, command receipt, JSON event log, input map,
baseline package routing, and production-blob binding are retained.

The saved source binding records 294 production/manifest blobs matching the
baseline commit. All 298 recorded inputs were hash-checked again at collection
without execution. The two existing font fixtures are identified by hashes in
the binding; no font binary is copied into this bundle.

The original binding's `test_copies_match_current` field describes the time of
that historical binding. It is **not a claim about the final test files**.
After this baseline run, independent Poppler inspection found that the
logical-export test's `_expectUnchangedPainting` control helper constructed a
malformed direct inline stream. The final helper was repaired using
`extractPages` and reopen assertions; its whole-file SHA-256 is now
`30e15e5f6ff1f3b2b1c6729db728fbc12c55475a6f27674dd72ab7ed1ee7097d`.
The 17 main logical-source regressions remained unchanged, but the historical
whole-file snapshot differs. This bundle retains the original bytes and makes
no claim that the old painting control or any preliminary zero-pixel comparison
qualified rendering. Current-at-collection hashes are recorded separately in
`manifest.json`.

## cmap: 45 safe probes, not the final 55

`cmap/baseline-test.dart` is the original 45-case test source, SHA-256
`a6610e10d9004192f87271aeff996f0d6e952a18e7647ff7305e0ab04766c271`.
Its recorded parser hash
`5e6d0ec9bba6e5c0be8d6763c6773a4b2e2afa136e3787b915ad2b7742b062d6`
matches the parser at the baseline commit. The evidence binds that parser and
test snapshot; no complete cmap-run workspace manifest was retained.

The final 55-case file adds ten probes. In particular, a uint32-sized range and
a full scalar-space range were withheld from the old parser because its eager
expansion could run excessively. Their later coverage is not presented as an
old-source negative control. `cmap/invocation.json` lists all ten additions and
labels the command as **reconstructed from the author's report and log**:
there was no retained original launcher script or command receipt. The original
JSON log and two-input SHA-256 map remain unchanged.

## Sheet: original 28 cases

`sheet/baseline-regression-used.dart` preserves the exact original source,
SHA-256 `434a147258840f1faeeb68a8dbca562cba63cbc20037d94d95475a99f8fc8af7`.
It covers lost rank/formula2 edits, XML boolean spellings, reversible formula2
renames, concurrent-reference guards, and no-edit preservation. It predates
the later expression, page-layout, priority/stopIfTrue, and native-DXF cases.
Do not substitute the expanded final test file when interpreting this log.

The original receipt records the command and three production input hashes.
Its legacy `results.success` value of 12 includes one hidden loader result;
`canonical_results.success` is the corrected 11. Both fields are preserved
byte-for-byte. The manifest and verifier recompute 28 real cases: 17 assertion
failures and 11 passes. No original standalone launcher script was retained.

## Storage and verification

Logs and maps use gzip level 9, `mtime=0`, and no embedded filename. The manifest
records the original path, raw size/SHA-256, stored size/SHA-256, and compression
for each artifact. Original test sources and the retained PDF runner are plain
text. The manifest excludes itself from its artifact list.

Run `python3 verify.py` from this directory to rehash stored/decompressed data,
validate source-snapshot bindings, and recount the existing JSON logs. This
does not execute tests. `package_evidence.py` is the collection script created
for this bundle; it is not a historical test launcher and requires the original
scratch evidence to repeat collection.

## Separate English generator verification

`english-generator/` records a fresh execution of the incoming generator's
existing `--check` command. It verifies the pinned English pattern output and
verbatim original notice files without writing generated assets. The command,
timestamps, exact generator source, stdout/stderr, and before/after input hashes
are retained. This is a read-only generation check, not a negative-control test
run or an additional passing-test cohort.
