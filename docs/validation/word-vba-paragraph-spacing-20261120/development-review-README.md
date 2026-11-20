# Word line-spacing development diagnostics and independent source review

This archive preserves development history. Its development streams provide
**no publication acceptance**. Do not sum their case counts, reuse an older
`accepted` flag as final-source qualification, or add these attempts to the
complete regression total. Initial failures, partially completed fail-fast
runs, corrected attempts and subsequent smoke results remain separate files.

The one accepted body of evidence included alongside those diagnostics is the
independent source review of commit
`0201b549d0dc3f601c50e36255d557034cb01699`, tree
`86531c002a6b1d6e748849f7370a87072a5fa768`.
Its final VM replay passed **56 supplemental expectations** against ten reviewed
source inputs and 38 explicitly recorded runtime/probe inputs. These are
separate from the parent regression and contribute **zero** cases to that
regression total. The authoritative review report and before/after receipt
are retained at `intake-review/source-review.json`, `source-review.md`, and
`source-review-probes-final.json`; the exact runner and probe sources are also
included. The initial and intermediate probe logs remain diagnostic evidence.

## Contents and interpretation

- All five compiler development attempts, including raw stdout reporter
  streams and stderr, retain their original filenames.
- Native initial/corrected/final development runs, the early related regression
  slice, preset-guard regression/review, and property-packet guard runs are
  retained independently. A filename containing `final` does not promote a
  development run into the final complete regression gate.
- All three integration development attempts and their summaries are retained.
  The first exposed a reserved identifier in the example; the later streams
  contain the corrected example and subsequent review-driven scenarios.
- Both portable development directories include commands, exact BAS bytes,
  manifests, summaries, raw VM/compiler/Node output, runner/helper snapshots,
  compiled JavaScript, source maps, and dependency manifests. The first had
  semantically equal JSON with different integral-number spelling; the second
  achieved byte equality. Both explicitly remain unqualified development runs.
- The setup smoke and source/runtime receipts establish how local verification
  became available. They are not additional feature-acceptance cases.
- Concurrency and runner-help diagnostics record environment investigation and
  carry no product-compatibility acceptance claim.

`attempts.json` summarizes each original Dart reporter stream independently,
including hidden loading failures, visible completions, skipped cases and the
terminal reporter status. It deliberately has no combined passing total.
Historical diagnostic streams without a complete before/after receipt are not
silently assigned the final review's source binding. The retained probe source
is the source independently bound by the final supplemental replay; initial
diagnostic runs may predate later probe additions.

The complete 75-file regression gate and the accepted final portable/static
archive are separate deliverables. They are not copied while running and no
current gate helper, runner, runtime input or tracked repository file is edited
by this packaging operation. No GitHub Actions, workflow or status endpoints
were queried or awaited for these activities.

Every included file has an exact size and SHA-256 in the member index. Both
portable JavaScript artifacts and source maps fit in this compact archive, so
no requested generated output was omitted. Tar metadata is normalized for
deterministic reconstruction; extraction does not run any script.
