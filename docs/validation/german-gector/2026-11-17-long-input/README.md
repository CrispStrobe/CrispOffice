# German proofing continuation: bounded long inputs — 17 November 2026

Starting remote checkpoint: `d2e50c3a298679fed873d045a4b2d07663b37246` on
`feat/german-gector-proofing`. The user requested all incoming work first,
incremental remote checkpoints, and local validation without waiting for
GitHub Actions. No Actions job is dispatched, polled or awaited by this work.

## Incoming integration

`incoming-snapshot.json` records the GitHub branch and recent PR inventory;
`fetched-refs.json` records all fetched Quds branch and PR-head refs. Only the
morphology, Office-fidelity and Office-continuation tips were missing from the
starting checkpoint. All older fetched Quds refs were already ancestors.
The cooperating audit retains all 257 branch refs and finds no new work in
CrispEmbed, onnx_runtime_dart or fastembed-rs relative to the prior inventory.

First merge: morphology `f986fd031e4f984200c392e844ad83ae1ef5eb24` (PR #105).
This retains its source-bound local evidence and strict-analysis brace fix.
The roadmap conflict combines the implemented guard/native descriptions with
the newer 6/18 GECToR result; historical 5/18 morphology measurements retain
their own source identity. `docs/PROOFING.md` now distinguishes those reports.

The first checkpoint saved the incoming merge before retesting; the completed
integration and local results are recorded below.

Second merge: Office continuation `555eb728ce3ea872cb5ceb3e5fd2104b21f932aa`.
The section tests adopt its interpolation lint fixes. The annotation fixture
keeps the already-equivalent local `annotationText` variable, so both branches'
4,096-character byte-budget assertion is preserved without an unused variable.
The incoming initial-analysis-failure receipt is retained unchanged.

Third merge: Office fidelity `4ca30ec3ba9e2a1c2288d78bb83d2a3ce3678e0d`
(PR #101), including the previously deferred `097475fb` integration. The list
writer compares authored levels and preserves per-item bullet/number styles.
Its first-paragraph style stays applied once across nested lists. Existing
section activation and bookmark/link tests are retained; older section-style
code from the incoming merge does not replace the newer integrated behavior.
Duplicate Unreleased changelog bullets from earlier integrations are collapsed.
The new 13-case list-fidelity suite is retained for combined local validation.

## Integrated source validation

The complete incoming implementation is `145a0c04fa79a04fd903d196b2d6559b7e195b93`.
`integrated-ancestry.json` verifies every fetched Quds branch and PR-head tip as
an ancestor of that commit. The morphology, Office-continuation and
Office-fidelity merges were each saved remotely and read back before proceeding.

| Local cohort | Passed |
| --- | ---: |
| ODT/ODF, including authored-list and covered-cell/export-text controls | 191 |
| Deterministic German grammar | 268 |
| Editor proofing and manual/F7 | 97 |
| Total distinct tests | 556 |

Focused strict Dart analysis of four changed engine files also passed.
The retained `integration-summary.json` and compressed logs/receipts bind the
commands, source maps, runtime, duration and exit statuses. Receipt/log names
in that index refer to their original validation directory; here the same
bytes are stored with the `integration-` prefix. Engine/editor source maps
and package configuration were unchanged throughout each run.

The expanded ODT cohort is broader than the previous 148-test cohort; it is not
an arithmetic continuation of that historical test count. No visual desktop
word-processor export or intended-device qualification is claimed.

## Opt-in sentence segmentation implementation

The guarded decoder now accepts `GectorDecodeOptions(segmentation:
GectorSegmentationOptions())`. Default single-sequence behavior and the frozen
reference path remain unchanged. The planner preserves complete original-source
slices, prefers 64-token sentence groups, admits an intact sentence up to 512
and rejects over-limit/ambiguous text explicitly. Default request limits are
32 segments, 4,096 initial model tokens and 20,480 actual forward tokens over all
passes, alongside the existing source ceiling and whole-request deadline.

Later segments cannot acquire original-start insertions or case-differing
adjacent-duplicate privileges. Each segment's edits are rebased directly, with
no fresh paragraph diff. Cycles, pass limits, backend failure and cancellation
cannot publish an earlier segment's partial suggestions. Global protected,
personal and grapheme checks remain in the provider.

The first implementation checkpoint passes 174 package tests, including the
real pinned native fixture, and whole-package strict analysis. This includes
51 planner tests, 15 new decoder tests, and 5 new worker/provider regressions.
`implementation-tests.json` binds the observed result to its post-run source
map and retained logs. The runner also passes 7 CLI admission controls and the
existing 45 Python tooling tests. These unit/control results precede the fresh
complete native AOT measurements and do not claim long-paragraph model quality.

## Bounded planner review fix

Review found repeated full copies of an unmatched-delimiter stack while scanning
possible sentence boundaries. The planner now checks closing depth in place.
A new 30,999-unit adversarial input with 16,000 unmatched openers and 3,000
sentence-like terminators is rejected intact at the hard token limit. All 52
planner tests and focused analysis pass. This bounds delimiter scanning without
changing source partition semantics or relaxing the model limit.

`pre-review-aot-build.json` preserves the successful source-sealed build of
`fa3b67675d7f0f567fc88551fe6e4b87deea5065` before this review fix. No inference
result is attributed to that earlier binary. Final native runs will rebuild the
reviewed integrated source using fresh output and receipt paths.

## Second incoming snapshot

A fresh inventory at 2026-11-17 15:32:37 UTC found 130 Quds branch tips, including
new morphology and Office-fidelity heads and merged PR #108 for ODP text-shape
hyperlinks. `latest-refs-observation.json` and `latest-pr-observation.json`
record this fixed snapshot. The following integration precedes final native
measurements; those measurements will not claim to cover later moving refs.

Morphology `7808a8711c91d721e8bb2b7034349008be80895b` adds the shared production
policy for deterministic/manual report merging, a prospectively frozen 76-case
synthetic German challenge and a separate incremental-quality runner. The merge
retains this branch's segmentation options and native-runner controls, combines
the historical roadmap descriptions, and preserves the incoming tooling and
corpus unchanged. New report-merge, quality-tool and manual/F7 tests will run
against the final combined source.

Office fidelity `28fb08e61682913184e2a3c089bd5290a665c78e` supplies the newer
section activation, odd/even entry masters, continuous-page-style comparison,
numbering continuation/restart and auxiliary-story isolation, plus physical RTL
indents. The merged writer uses that implementation and retains the existing
bookmark, file-link and anchor-link behavior. The note and comment state classes,
inline rendering and note-table text handling match the receiving branch;
comment block rendering additionally gains the incoming isolated list story.

Both independently developed section suites remain. The prior suite is now
`odt_section_integration_test.dart`; it checks section ownership and geometry
rather than obsolete style IDs or extra anchor paragraphs that the newer table
activation eliminates. List-style lookup covers both default styles in
`styles.xml` and automatic styles in `content.xml`. For an explicitly empty
`sections: []` model, the existing empty body invariant wins: default master and
page geometry are exported without adding an authored body paragraph or
mutating the model. The incoming empty-document test retains its master and
nonmutation assertions with this reconciled body expectation. The first merge
run's three expectation failures are retained alongside the corrected run.

The incoming Office consumer archives include failed attempts and explicitly
leave final-source consumer qualification pending. Their presence and passing
Dart tests must not be read as completed desktop-consumer validation.

The reconciled Office merge passes all 208 tests in its ten-file ODT cohort
and strict analysis of the writer and both section suites. The updated Python
build, comparator and pack tooling passes all 51 tests. Logs retain the initial
merge expectation failures; the final full-source validation is recorded below
when complete.

Merged PR #108 through main `4af75017a9b7df726c1f80741809f5bccdb70f4c`.
Its six-line text-shape hyperlink implementation combines cleanly with the
existing ODP transform logic. The test conflict retains the newer SMIL
transition assertions and adds the incoming hyperlink assertion; it does not
restore the superseded transition attributes. The first octopus merge attempt
was rejected by Git because of this test conflict and left no partial merge;
the normal main merge was then resolved explicitly.

The feature `3ec638bd7de5cb6648774abbf14da1c315f5e418` and vendor
`0585fac1a56c3dc5c3d728962794299ddfe50bbb` tips carry the identical eight-line
ODP hyperlink patch already integrated from main. `odp-incoming-equivalence.json`
records identical patch hashes and changed-file blobs for all three tips;
feature and main also have identical complete trees. A history-only merge keeps
both equivalent branch tips as ancestors without replacing the receiving
branch's newer Office behavior. These are the final missing tips in the fixed
130-branch snapshot.

## Preserved broader-cohort failure before frame extraction fix

At `c89e7eedda4473eae98953e61d9244d0125f440f`, all 130 captured branch tips and
108 fetched PR heads are ancestors (`second-integrated-ancestry.json`). The
broader ODT/ODF cohort exposed one real integration failure: a frame inside the
new section-owning paragraph was extracted as an empty string instead of its
whitespace-preserving text. The existing assertion is not relaxed. This run
had 249 passing ODT/ODF tests and one failure; 35 ODP and 268 German tests passed.
All three source maps were stable. `pre-frame-fix-attempt.json` indexes the
retained failed attempt and compressed source-bound logs/receipts.

The two `pre-frame-fix-*-build.json` receipts describe successful builds with
stable source, dependency and SDK seals. Neither resulting binary was used for
inference. Native measurements will rebuild the corrected source into fresh
paths; these successful earlier builds do not qualify the later fix.

## Frame extraction integration repair

The shared ODF decoder now discovers each owned text box once and retains frame
paragraphs separately from the enclosing paragraph's own inline text. The
extractor preserves frame-contained tables as tables; frames within a consumed
cell remain part of that cell's text. Empty frame anchors disappear only when
visible paragraph blocks replace them. Ordinary blank and explicit-whitespace
paragraphs remain, and annotation/note/covered-cell/ruby annotation stories stay
excluded. Bounded search uses the same cumulative UTF-8 budget and now excludes
note-only stories in its fallback as well.

The original failing whitespace assertion and the ODT writer are unchanged.
Nine new cases cover the newly exercised traversal, table, hidden-story and
budget paths. The focused 51 tests and all 259 ODT/ODF tests pass; strict analysis
is clean. A separate read-only review found no remaining correctness defect.
`odf-frame-resolution.json` records the commands, source and log hashes and
review. Initial failure evidence remains available above.

`resolved-inputs.json` indexes byte-exact compressed copies of the resolved
lockfile and package configuration used here. Restore the lock to reproduce
package choices, but regenerate the configuration on another host because its
paths describe this workspace. SDK and every resolved package library are
additionally sealed by the AOT build receipts.

## Final integrated source and local regressions

Implementation source: `d092d50a844b5cfcc31bb6c39220704b4ff11cf5`.
All nine final suites have identical before/after maps for 1,312 tracked inputs
and resolved package configuration, with this same start/end commit. The
retained summary and compressed receipts/logs cover:

| Cohort | Passed |
| --- | ---: |
| GECToR package, including the pinned real native fixture | 194 |
| Deterministic German grammar | 268 |
| Shared deterministic/manual report merge | 20 |
| Editor proofing and manual/F7 | 97 |
| ODT/ODF including frame extraction | 259 |
| ODP hyperlinks, transforms and transitions | 35 |
| Python build, pack and strict comparison tooling | 51 |
| Total distinct tests | 924 |

There are no skipped tests in the six final Dart/Flutter cohorts. Three strict
analysis suites also pass. The 51 Python tests were executed at `8801031a`;
`tooling-source-recheck.json` verifies that every recorded tooling, corpus and
baseline input remains byte-identical at the final implementation. They are not
claimed as a second test execution. The original summary names raw files in its
run directory; saved copies here use the `final-` prefix and gzip compression.

`provider-build.json` and `incremental-quality-build.json` are fresh successful
AOT builds after the frame repair. They seal 63 and 68 selected source files,
respectively, plus all 109 resolved package libraries and the SDK. Runtime
receipts below must match their source maps and compiled/runtime pins; a build
alone is not an inference result. `pack-verification.json` verifies all 23 files
and the unchanged 86,356,331-byte development pack.

## Native segmentation results

Both modes ran serially through the same fresh compiled provider runner after
all test/compiler activity finished. The native receipts match the build's
selected source map and actual AOT/runtime pins. Both strict frozen comparators
pass. All 30 frozen case statuses, corrected strings and findings exactly match
the previous continuation: 6/18 exact fixes, 10/10 supported clean cases unchanged,
and two Swiss controls explicitly unsupported. The original eight controls and
all six additional segmentation controls pass.

| Measurement | Single sequence | Sentence segments, target 64 |
| --- | ---: | ---: |
| Short-check median | 21.269 ms | 24.761 ms |
| Short-check p95 | 74.229 ms | 73.321 ms |
| Peak process RSS | 342.50 MiB | 294.55 MiB |
| Verified startup | 3.354 s | 3.235 s |
| 126-token structural p95 | 369.684 ms | 416.366 ms |
| 256-token structural p95 | 607.917 ms | 724.617 ms |
| 636-token structural p95 | Outside single-sequence capacity | 2,179.809 ms |
| 1,276-token structural p95 | Outside single-sequence capacity | 3,804.643 ms |

The two new long probes use 11/22 segments and 646/1,297 actual initial model
tokens, respectively, including per-segment specials and normalization. Their
logical original-source counts are 636/1,276, and every original UTF-16 code
unit is covered. The known late `geht` correction after a long prefix and emoji
lands exactly at document offsets 2543–2547; protected code remains unchanged.
Late oversized content, request-token, segment-count and source-length limits
fail the whole request without partial findings.

These measurements demonstrate bounded coverage beyond 512 tokens, **not a
long-input speedup**. The 256-token probe is slower in this run with target64,
and all longer probes exceed 500 ms. Short-check and memory budgets pass.
Segmentation remains a host opt-in; its sentence heuristic and within-call
native cancellation limits remain. The long texts are repeated clean sentences,
not a representative paragraph-quality evaluation. Each structural timing has
three measured samples after a warmup; this is one local-host observation.
`native-results.json` provides the compact index and source checks. Complete
receipts and logs are compressed with byte hashes retained in that index.

## First prospective incremental-quality measurement

The separate quality runner was built from the same final implementation and
run once per case in default single-sequence mode. Its selected-source maps,
actual AOT/runtime pins and corpus hashes match the fresh quality build. The
76-row corpus is byte-identical to its earlier remote freeze `60c550b4`; neither
inputs nor rules were changed after inspecting these outputs. Both the original
30-row and prospective 76-row runs complete with every expected status contract
and stable before/after source maps.

Results below use only de-DE quality rows; the four prospective regional
controls are separate and the model returns unsupported for all of them.

| Lane | Exact fixes / 32 prospective errors | Changed clean / 40 | Flagged clean / 40 |
| --- | ---: | ---: | ---: |
| Writing rules only | 14 | 0 | 0 |
| Deterministic spelling + writing | 14 | 1 | 1 |
| Guarded model only | 12 | 0 | 0 |
| Combined, production manual/F7 merge | 19 | 1 | 1 |

The model adds five exact combined fixes, loses no deterministic exact fixes,
and adds no changed or flagged clean cases in this panel. Six model proposals
are accepted and six overlap proposals are suppressed. A sixth model-only exact
fix becomes a nonexact combined projection because spelling independently
changes `im Hof` to `im Hofe`. The same existing spelling suggestion changes its
already-correct clean counterpart. `Hofe` is a grammatical dative alternative;
this is still an unnecessary suggestion on correct input and an exact-target
mismatch, not proof that the resulting sentence is ungrammatical.

On the original panel, deterministic checking fixes 7/18 and the combined
projection fixes 9/18, adding `verb-ihr` and `das-relative` without losing a
deterministic fix. The model-only result remains 6/18. Existing deterministic
clean changes include lowercasing `Das` after a German opening quotation mark;
the regional Swiss-name case remains separate from de-DE scoring. These are
retained findings for follow-up, not silently removed from the corpus.

The projection uses the first replacement in provider/result order and never
chooses alternatives from the expected answer. It is not automatic correction
behavior. The panel is authored, synthetic and deliberately selected; it does
not establish general precision/recall, training-data exclusion, regional model
support, long-paragraph quality or default-provider readiness. `quality-results.json`
indexes all locale-separated counts, changed-clean examples and source checks;
complete findings, alternatives, accepted/suppressed proposals and per-case
statuses remain in the compressed raw receipts. No performance conclusion is
drawn from this one-check-per-case quality runner.
