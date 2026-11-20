# Final source reconciliation and incoming Word qualification

The frozen source cutoff is fully accounted for at published checkpoint
`4772d52492076241c39fdee0990c950c92367b1f` (tree
`69cc7f32a80346ade83ed02eacca0faa2e293974`). The
[accepted intake](intake-local-accepted.json) and its exact offline replay both
pass. This is a source-cutoff statement; a fresh main check is a separate
publication step.

## Frozen inventory

The [immutable manifest](intake-local-cutoff-refs.json) contains the completed
dedicated-ref capture. Its latest fetched ref timestamp is
`2026-11-20T20:57:12.305837+00:00`, and the manifest was recorded at
`2026-11-20T21:08:35.177505+00:00`. No branch or PR refs were fetched after
freezing this manifest.

| Captured refs | Actual ancestors | Historical equivalents | Total |
| --- | ---: | ---: | ---: |
| Fork branches | 29 | 9 | 38 |
| Fork PR heads | 260 | 14 | 274 |
| Upstream branches | 4 | 0 | 4 |
| Upstream PR heads | 4 | 0 | 4 |
| Total | 297 | 23 | **320** |

There are **zero uncovered cutoff refs** and **zero uncovered heads from the
initial API snapshot**. The 23 equivalent references resolve through 14
independently recomputed historical proofs: thirteen full-tree identities and
one exact match of all 37 changed ODT paths, including modes, types and object
IDs. Every accepted substitute is an ancestor of the target.

The [report](intake-local-accepted.md) includes the replay command and the
fixed-manifest capture command. The initial API capture, earlier local
captures, later failed snapshot and the two-uncovered-branch failure at
`65468fdf` remain separate historical evidence. They were not overwritten with
the final passing result.

## Reconciliation decisions

- Preserve `332d7b26` in history through `4d9cddee`, while retaining main's
  deletion of the temporary golden workflow. The reconciliation tree is exactly
  the original main tree; the proof checks both parents and the deletion.
- Retain main's official named-argument measurement checker, binary64 ratio
  evaluator and exact native-grid rules. Preserve the physical, independent
  unit-conversion and named-measurement examples under distinct canonical
  filenames.
- Preserve the large-scalar overflow regression from `8ca1958d`, all later
  Word evidence from main `b6657785`, and current formatting.
- Reconcile the captured Mail tip `3b753b02` into the accepted foreground Mail
  implementation. Mail execution/UI qualification is recorded by its dedicated
  reports; incoming historical Mail results are not substituted for those runs.
- Preserve the captured Word reconciliation `ba6b170c` through `e85faffb`.
  Its production parser is unchanged. Retain thirteen added compiler cases and
  one existing-tab/recording/save/replay integration case. Keep the newer Word
  validation README at its original path, the incoming checkpoint README under
  its separate name, all newer evidence and main's exact-unit citations.
- Preserve captured Zotero reconciliation `835b8019` through `4772d524`.
  Its parents and functionality were already represented. The
  [independent proof](intake-zotero-equivalence.md) checks all 112 Zotero package
  blobs and explicit Word naming equivalences. The merge adds only two
  historical intake documents and their two proof files; product and tests
  remain unchanged. No additional Zotero runtime run is claimed.

## Incoming Word acceptance

The broad final run passed **757 VM cases** across nine suites and **712 Node
cases** across five portable compiler suites. Strict formatting and analysis
were clean. The actual committed line-spacing, measurements and named
measurements BAS examples each passed on the VM and compiled JavaScript/Node,
with equal parsed JSON results.

The later captured Word regression additions were qualified by complete
reruns of the two affected named suites: **171 VM cases** and **160 Node
cases**, zero failures or skips. Only those two test inputs changed; the other
367 scoped inputs, including production code, all other suites, and all BAS
and portable drivers, remained identical. Replacing the old named-suite
results with those reruns gives **771 qualified VM cases** and **725 qualified
Node cases**. These are assembled cohorts, not one invocation; VM and Node
coverage overlaps.

The [combined cohort record](intake-local-word-combined-cohorts.json) lists
exact suite counts, old/new case names and source bindings. The
[published-source check](intake-local-accepted-word-source-binding.json)
independently reads every one of the 369 scoped inputs from immutable blobs in
`4772d524`; all hashes match the final accepted receipt.

The first expanded VM attempt had 749 passes and eight repeated fixture
failures. Each failed fixture placed `Dim result` after an executable
assignment and therefore tested declaration-order rejection before the
intended nonnumeric-Variant rejection. Moving that declaration above the
assignment retained the numeric-string input and original `vba_type_error`
expectation. Production code and expected behavior were unchanged. Formatting
failure and the later tool-context interruption are also preserved as
nonacceptance diagnostics in the [Word summary](intake-local-word-final.md).

All acceptance used the pinned Dart runtime and locked dependencies. These
records do not claim installed Microsoft Word, browser or WASM execution.
GitHub Actions, workflow runs, checks and status endpoints were never queried
or awaited.
