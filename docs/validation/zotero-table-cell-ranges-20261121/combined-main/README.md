# Qualification on combined Word, Mail and Zotero main

## Result

Frozen checkpoint `5289b90a83ce9042a4f4cfb73ba8115fe501513a`, Git tree
`15165a1c510f68de244f36286c3268d8cd8b43ed`, incorporates:

- The preserved Zotero implementation and complete original qualification.
- Main `4a1eaa69e7a068e354bdd851ec9b0323b89ae300`, including PR #290's screenshots
  and PR #291's qualified Mail synchronization and captured Word VBA work.
- The captured Mail Close-control fix
  `9cfad3920f9afb3ca1620df429fa41e33f3db8e6`.
- One meaningful saved-Mail regression that finds Close across the entire
  localized dialog, exercises saved/account views, and verifies dismissal and
  reader disposal.

All **151 executed cases in six original suites passed**. Process exits were
zero, each process had exactly one successful terminal event, every started
case completed exactly once, and there were no skips, error events, raw runtime
error messages or stderr bytes. Strict analysis of the combined Close fix and
new test found no issues; both Dart files were already formatted.

| Original suite | Passed cases | Relationship to earlier evidence |
| --- | ---: | --- |
| Word table grid addressing | 22 | Repeated from the original 2,551-case population |
| Word bookmark fidelity | 17 | Repeated from the original population |
| Studio Zotero transport | 18 | Repeated from the original population |
| Studio Zotero shortcuts | 15 | Repeated from the original population |
| Studio saved Mail | 15 | Includes the one newly added global Close regression |
| Studio Mail workspace | 64 | Also overlaps incoming Mail qualification |
| **Total actual executions** | **151** | **72 repeated original cases + 79 Mail cases** |

The [supplemental receipt](supplemental-qualification.json) matches the exact
72 repeated suite/name identities against the original 2,551. Loading and
setup/teardown events are excluded. These 151 executions are not added as 151
new unique cases, and no distinct grand total across incoming archives is
claimed. The original 121-case Node execution and 21 independent development
probes retain their separate scopes.

## Why these repeats cover the incoming dependency changes

The original [qualification](../qualification.json) executed 119 original
suites on `a6095c30`. All 119 test files and all Zotero implementation files
remain byte-identical in the combined source. Incoming Word VBA and Mail work
changes other files, so the full source map is not represented as unchanged.

The [dependency impact review](impact-review.md) resolves repository imports,
exports, parts and conditional alternatives. It identifies **116 unchanged
selected-suite dependency closures** and exactly three affected suites: the
table-grid and bookmark suites reach the changed Word operation dispatcher,
and the Studio shortcuts suite builds the shared workspace that reaches Mail.
The supplemental run repeats those suites and the companion Studio transport
suite, preserving the existing two-suite Studio cohort.

The two Node Zotero suites have unchanged relevant dependency closures. Their
broad 356-input capture includes two changed automation files, and a new guard
file exists; neither is reached by these tests. The 121 Node successes remain
applicable through that explicit scope mapping. No new Node run is claimed.

The replay script and [independent acceptance](final-combined-independent-review.md)
retain the dependency analysis and its limitations alongside the raw execution
evidence. The impact report deliberately records a pending repeat plan; the
independent acceptance joins that plan to the completed runtime receipts.
The current selected
source map has **2,994 inputs**: the 2,978 original paths plus 16 additions,
with no removals. Of the original paths, 16 changed and 2,962 remain identical;
the added saved-Mail regression is one of those changed paths. The exact
identities are recorded in [impact-review.json](impact-review.json).

## Source and runtime binding

All 2,994 current recorded source, test, fixture, manifest and lock inputs match
the frozen Git commit before execution, including blob identities and executable
modes. Every cohort and run-level before/after map is identical. The canonical
source-map SHA-256 is
`86723cbca9b7f6eb17f3be8223e1bd20c09cec46ca68a9efa82bb498fe646cc4`.
Recorded environment files also remain unchanged.

The original 159-member evidence archive and its accepted/rejected historical
records remain unchanged. This supplemental archive separately retains the
new streams, process receipts, source maps, selection, runner, overlap auditor,
dependency-impact review, incoming-evidence audit and final checks. Each
archive member has an indexed SHA-256 and size.

Verify the [evidence archive](evidence.tar.xz), its [member index](evidence-index.json)
and the combined source from the repository root:

```bash
python3 docs/validation/zotero-table-cell-ranges-20261121/verify_evidence.py \
  --repo . \
  --bundle docs/validation/zotero-table-cell-ranges-20261121/combined-main
```

Use `--archive-only` to inspect this evidence after future source changes. The
original strict verifier without `--bundle` remains tied to its original
2,978-input source map; the screenshot-only applicability checker remains tied
to checkpoint `b45703af`. Neither historical checker is relabeled as an
identical-source result for the newer combined source.

## Reconciliation of all captured incoming heads

The [initial replay](intake-initial-replay.json) covers all **338** original
external heads. The [later replay](intake-final-replay.json) covers all **341**
heads from the later captured inventory: **317 ancestors, 24 verified historical
equivalents, zero uncovered**. It recomputes the same complete-tree and
complete-changed-path equivalence proofs against the combined commit.

Word `4b47520a`, Mail `45f0e503`, and Close fix `9cfad392` are now actual
ancestors. This supersedes their earlier cutoff deferrals. The earlier raw
341-head audit and its exit-1 result are retained unchanged as historical
evidence, rather than being rewritten to hide the subsequent reconciliation.
The two later main PRs are incorporated by their actual main ancestry as well.

These are exact captured inventories in a concurrently active repository; they
do not assert that no remote branch can advance afterward. Original PR #289
was closed when PR #291 incorporated its implementation head. The final
reconciliation PR records remote main readback, merge ancestry and tree identity.

## Incoming Mail and Word qualification

The [independent incoming-evidence audit](incoming-mail-independent-audit.json)
confirms the published main tree matches its qualified branch tree. It verifies
all 40 indexed files and their receipt hashes, raw JSON populations, source
bindings and documented screenshot-gate exception.

Incoming evidence records 1,768 Mail cases and 798 Word/Zotero executions.
These remain their own historical populations. The JSON store and host streams
support full event audits; other incoming expanded logs provide less detailed
event evidence, and separately empty stderr is not claimed where no separate
stderr artifact was retained. The fresh 151-case combined-source run above
has its own complete JSON and stderr records.

## Remaining boundaries

This qualifies the scoped Zotero extension and its integration with captured
Office changes. It does not establish a new installed Word/LibreOffice/Zotero
plugin acceptance run, direct active ODT import, or live Mail account behavior.
The [Zotero roadmap](../../../roadmaps/zotero/word-processor-parity.md) retains
the next implementation and host-acceptance milestones. No GitHub Actions,
workflow/check/status queue was queried or awaited.
