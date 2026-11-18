# Reconciled Office continuation — 18 November 2026

## Saved source and current status

The combined source is saved at `c08fdc703acd986850ce6d1c079a0576fd438046`
(tree `3458b14160759a44dc53f6cd18d40c2c27b2469c`) on
`codex/office-resume-20261118`. Local qualification is running against isolated,
fixed checkouts of that commit. This checkpoint is not final acceptance.

The source retains four incoming histories:

| Incoming work | Captured commit |
| --- | --- |
| Main, including merged PRs #147 and #149 | `4b2b4e78839d2997a583b7ab1346e2fa537a8ac4` |
| Lost-agent GECToR/Office continuation | `205e913ec1525b5e5157a6f6d7ff84c883217e48` |
| Later Office-union repairs | `16c7b0fb48c72527645678b76e25b5c5cb7b9c22` |
| Default-off native spaCy analysis, PR #139 | `e7c67f29b34f1c1909e51aa25997fc774bb8ac80` |

The incoming audit captures 340 external refs: 183 fork branches, 149 fork PR
heads, four upstream branches and four upstream PR heads. There are 222 distinct
heads. Of those refs, 316 are ancestors of the combined source, 22 have exact
whole-tree equivalence to included successors, and two point to the reviewed
field-continuation head whose remaining differences are later spreadsheet and
backlog changes. See `incoming/` for exact refs, comparison evidence and the
reproducible audit. The newly created continuation branch is excluded from
incoming counts.

## Integration decisions

- Retain late spreadsheet fixes for conditional-format child ordering, positional
  color import, threshold evaluation and save-cache invalidation.
- Use the GECToR continuation's common `SectionFrame` graphic style. This moves
  the unchanged style into common styles and preserves floating-frame bookmark
  ranges in independent DOCX conversion. Keep both branches' frame regressions;
  adapt the union test to the selected common-style structure while preserving
  its two-frame and bookmark assertions.
- Retain significant PAGE/NUMPAGES cached-whitespace regressions, header/footer
  schema ordering, comment ownership and frame paragraph anchors.
- Preserve the default-off spaCy package and explicitly invoked Studio analysis
  UI. It registers no grammar provider and does not alter deterministic proofing.
- Preserve the deliberate AOT/RML product removal. A compiled Dart executable
  used by measurement tooling is unrelated to the removed linguistic package.
- Keep historical reports and raw archives with their original source labels.
  Old results do not qualify the newly combined source.

## Local qualification plan

| Gate | Selection |
| --- | --- |
| Canonical Office/proofing gate | 222 files in six disjoint cohorts; five strict-analysis scopes; 165 formatting targets; Python controls including real ONNX/native fixture |
| Portable repetition | 17 files on Node; same case identities compared with VM outcomes |
| Studio smoke | Two retained example tests |
| Office consumers | 40 retained fixtures; five boundary fixtures; five frame/field fixtures; official schema and independent conversion/render checks |
| Additive spaCy integration | Package and UI contracts, strict analysis, browser capability, and frozen-model native widget gate |
| Native thread measurement | Serial 1/2/4/8-thread runs on distinct long passages, after other heavy jobs finish |

The exact official Flutter 3.47.8/Dart 3.13.7 archive and 162 hosted package
archives were hash verified. The combined workspace resolves 110 packages with
the historical lock unchanged. Native binary/model pins remain unchanged.

The saved 377-row, four-lane quality replay is retained at its original source
`8c98daf5`. Its 1,508 outcomes per source have been independently reconstructed.
The relevant proofing implementation, model tooling and corpora are identical in
the combined source; the workspace adds only the separate spaCy package. The
report records no loss of an exact correction or new changes to declared-clean
inputs, one deterministic improvement, and the existing limitations. This is
historical quality evidence with a source-equivalence audit, not new inference
on the combined checkpoint.

Every remote checkpoint uses a non-force expected-head update and an exact tree
comparison. No GitHub Actions, workflow, check-run or status endpoint is queried,
awaited or rerun. Checkpoint messages contain `[skip ci]`.
