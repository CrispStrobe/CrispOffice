# German proofing continuation — final handoff, 17 November 2026

The continuation starts at `c98c75eae50ddabfa8eb9aa918ed1af9754b7923` on
`feat/german-gector-proofing`. Incoming work is integrated, the implementation is
saved incrementally, and local tests, native measurements and quality evaluation
are complete. No GitHub Actions were dispatched, polled or awaited.

**Qualified implementation:** `143bad2f69976c331ac98ea7b4adbaec430af916`.
Later checkpoints add evidence and this handoff; the qualified production and
test inputs remain byte-identical. Start with [final-validation.json](final-validation.json),
[native-results.json](native-results.json), [quality-results.json](quality-results.json)
and [local-validation.json](local-validation.json).

## Incoming work and remote checkpoints

The first snapshot captured 143 Quds branch tips and 118 PR heads. All were
integrated before the baseline quality run at
`43d43061ac33e2e3b336a79fb4b07b036bc617a8`.

The second fixed paginated snapshot spans **18:04:35–18:04:37 UTC (19:04 CET)**.
All **150 branch tips and 122 PR heads** are ancestors of
`06120cb042b3f26d3f345e922032c9d72f4f5bc2` and the final implementation. This
includes main through PR #122, the bounded German predicate scanner, the
reconciled Office work and the daemon-free AOT/Studio path. Exact main/feature/
vendor patch equivalence is recorded before retaining independently developed
histories. The sole second-pass ODP test conflict retains both the hyperlink
and chart-label assertions.

The cooperating audit covers 257 unchanged branch tips and 219 PRs across
CrispEmbed, onnx_runtime_dart and fastembed-rs at the first snapshot. These are
bounded inventories, not assertions about concurrent arrivals after their
cutoffs. No further live inventory was performed after the second snapshot.

- [Latest inventory](latest-incoming-snapshot.json), [final ancestry proof](final-ancestry.json)
  and [merge decisions](latest-integration-decisions.json).
- [Initial integration decisions](integration-decisions.json) and
  [cooperating audit](cooperating-ref-audit.json).
- [Remote checkpoint index](remote-checkpoints.json), through the evidence save
  preceding this final documentation commit. Each remote checkpoint was fetched
  back and its exact tree and ordered parents were verified; updates used an
  expected-head lease and no force.

## Implemented behavior

### Complete accusative verb-object contexts

The new independently ignorable `de.grammar.verb-object-case` rule offers the
article correction in `Sie hat ein roten Mantel.` and
`Ich sehe ein kleinen Hund.` Shared noun and adjective rules can also use the
established accusative context, including `Ich treffe einen Student.` →
`Ich treffe einen Studenten.`

The entire request must contain a matching pronoun and one of 16 reviewed
present-tense verbs, a modeled noun phrase, and actual final punctuation. Bounds
are six words and 512 UTF-16 units. All retained noun readings participate in
ambiguity vetoes. A valid fronted-object interpretation such as
`Sie sieht ein kleiner Hund.` stays unchanged. Incomplete, inverted, subordinate,
coordinated, auxiliary, protected and unresolved degree/morphology contexts
abstain; recognized unsafe verb frames cannot fall through to the old
nominative adjective guess. These are intentionally narrow rules.

### Participle ranking and finite dictionary coverage

Twenty authored overregularization pairs can prefer a dictionary-verified
irregular participle in a bounded pronoun-plus-`haben` context. Examples include
`gelest` → `gelesen`, `geschreibt` → `geschrieben`, and `gefindet` → `gefunden`.
The same candidate budget applies, and known words, ignored rules and personal
vocabulary retain their early acceptance. Context enters the suggestion-cache
key so ranking cannot leak into unrelated occurrences. Suggestions remain
reviewable; this preference does not recover intent in every ambiguous typo.

The first-party finite supplement adds exactly two previously missing accepted
forms: **Lernen** and **Schuppen**. The pinned 443,925 upstream forms and 9,451
Swiss additions are unchanged. Genitives `Lernens` and `Schuppens` were already
accepted. Incoming `Hof`, `Grüezi` and explicit direct-quotation capitalization
repairs are retained.

### Duplicate grammatical roles

The guarded model preserves adjacent homographs that can have distinct
pronoun/article roles, including `Wenn sie sie sehen, winken sie.` The guard
covers a finite set of 22 words and ambiguous longer runs. Ordinary duplicate
cleanup and the existing original-request-start exception remain; later segments
do not acquire original-start privileges. The pinned publisher configuration
and unguarded reference are unchanged.

### Optional request-local inference reuse

Reuse is **off by default** and requires `GectorDeterministicBackend`. A host may
set `GectorSegmentationOptions(inferenceReuse: GectorInferenceReuseOptions())`.
The default request cache holds at most 32 exact prepared inputs / 2,048 tokens.
It stores immutable validated raw tags, keyed by exact words, token IDs, masks
and first-subword indices. Every occurrence reruns guards, original-start
privilege checks, protection/vocabulary/grapheme validation and UTF-16 projection.

The cache is created after full admission and discarded after one complete
request. Saturation falls back to ordinary inference. Atomic rejection,
cancellation, cycle/pass limits, whole-request deadlines and initial token bounds
still apply. Actual native misses alone charge the forward-token budget; every
logical pass remains visible in decoder telemetry. See the package README for
the public API and resource limits.

### Office integration repairs

Paragraph styles now distinguish emitted tabs, `columnBreakBefore` and
`keepTogether`, preserving page-break precedence. Section column count/gap are
emitted on a `style:columns` child of `style:section-properties`, as required by
[ODF 1.3 Part 3, sections 17.11–17.12](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html).
Unrepresentable gap values are omitted; finite signed lengths and canonical zero
are retained. Incoming minimum row heights, authored leader glyphs, valid colors,
frame extraction and all independent section/decoration suites remain.

One earlier rounded-tab test assumed hyphen and underscore leaders serialized
identically. Incoming fidelity work correctly preserves those glyphs. The
rounded-position equivalence test now compares matching hyphen leaders, and a
separate regression requires distinct hyphen/underscore glyphs and styles. All
incoming document-writer assertions remain unchanged. Failed-before attempts,
including the test matcher correction, are preserved in `office-columns/`.

## Native results

All three modes run serially through the **same freshly built provider AOT**,
after all tests, analysis and compiler activity completed. The program SHA256 is
`04e236c1872ddad67beab2e2f266bee576206fea10ec2712c3872948a1cde17d`.
The separately built quality runner SHA256 is
`eef27c8f62ed6f98c5977be7e5607f31c9cc5949946fd2f3d787bcb594ec3188`.

All modes retain six exact frozen model fixes, ten supported clean controls,
and all eight original operational controls. Both segmented modes also pass
all six segmentation controls and both varied-paragraph probes. Original frozen
cases and structural probes are unchanged; varied probes are separate additions.

| Measurement | Single sequence | Segmented 64 | Segmented 64 + reuse |
| --- | ---: | ---: | ---: |
| Short-check median | 29.015 ms | 27.856 ms | 24.147 ms |
| Short-check p95 | 170.137 ms | 65.580 ms | 127.197 ms |
| Peak process memory | 364.93 MiB | 366.56 MiB | 387.24 MiB |
| Startup, including verification | 3.842 s | 3.284 s | 3.603 s |
| 256-token repeated probe p95 | 777.349 ms | 1,000.265 ms | 444.425 ms |
| 636-token repeated probe p95 | Exceeds sequence limit | 2,292.474 ms | 277.343 ms |
| 1,276-token repeated probe p95 | Exceeds sequence limit | 3,983.515 ms | 340.767 ms |
| 638-token varied probe p95 | Exceeds sequence limit | 2,016.871 ms | 1,881.744 ms |
| 1,279-token varied probe p95 | Exceeds sequence limit | 3,812.603 ms | 3,988.435 ms |

The four larger probes were measured only in segmented modes; their token
counts exceed the single-sequence capacity.

The mechanism is verified independently for every timed request:

| Paragraph | Logical passes | Native forwards without → with reuse | Reuse hits |
| --- | ---: | ---: | ---: |
| Repeated, 636 tokens | 11 | 11 → 2 | 9 |
| Repeated, 1,276 tokens | 22 | 22 → 2 | 20 |
| Varied, 638 tokens | 11 | 11 → 11 | 0 |
| Varied, 1,279 tokens | 21 | 21 → 21 | 0 |

Source coverage is checked against actual complete decoder passes, beyond the
planned partition flag. Reuse and uncached segmentation preserve the same
findings and corrected strings. The new varied probes are operational evidence;
no expected linguistic gold is invented for them.

These are local-host measurements with one warmup and three timed samples per
probe, in a fixed mode order. Per-probe p95 is the maximum of three samples.
Short-check and memory budgets pass, but **distinct long inputs still take
seconds**. No general long-input 500 ms claim or target-device acceptance follows.
All raw samples, counters and receipts are in `final-native-evidence.tar.xz`.

## Quality comparison

The comparison baseline is the immutable incoming integration at `43d43061`,
measured before these new repairs. The panels are reused synthetic regression
sets. They do not establish representative German accuracy or a fresh
prospective estimate. Projection uses the first listed replacement for
reproducibility; the application presents suggestions for review.

| de-DE panel | Errors / clean | Deterministic exact: before → final | Combined exact: before → final | Combined clean flagged: before → final |
| --- | ---: | ---: | ---: | ---: |
| Original | 18 / 10 | 8 → 10 | 10 → 12 | 0 → 0 |
| Development | 32 / 40 | 14 → 17 | 20 → 23 | 0 → 0 |
| Broader syntax | 20 / 34 | 10 → 11 | 13 → 14 | 4 → 0 |

No lane loses an existing exact fix. The final model-only counts remain 6, 12,
and 5; the actual combined merge gains 2, 6, and 3 exact fixes over final
deterministic checking. All de-DE clean cases are unchanged and unflagged in
all four final configurations. The syntax improvement removes three spelling
false alarms (`Schuppen`, and two `Lernen` contexts) and the model's erroneous
`sie sie` deletion. The eight regional rows remain separate; the model explicitly
reports unsupported for de-AT/de-CH, and deterministic/combined regional outputs
remain clean.

The pre-existing changed-nonexact syntax output remains visible:
`Er ist nach Hause gegangt.` projects to `Er ist nach Hause gebangt.` rather
than the expected `gegangen`. Extending safe participle ranking to `sein`
contexts remains open. The metadata-only syntax adapter changes `area` to
`category`; input, gold, locale, kind and row order are unchanged. The failed
original-schema admission ran no inference and is retained separately.

## Final local validation and independent audits

| Distinct cohort | Passed |
| --- | ---: |
| GECToR, including actual native dual-head fixture | 247 |
| Deterministic German | 752 |
| Shared report/service behavior | 46 |
| ODT/ODF | 438 |
| ODP | 51 |
| Editor proofing and manual checks | 139 |
| AOT contracts and process transport | 153 |
| Build/pack/evaluation tooling | 117 |
| Studio | 25 |
| **Total distinct** | **1,968** |

There are zero failures and zero skips. An additional **196 Node executions**
repeat already-counted cases. Five strict analysis suites pass. Independent
reconstruction verifies exact test identities, real native fixture execution,
670 tracked input files, all 11 workspace package roots and all 110 resolved
package-library fingerprints. Native/quality build audits bind 4,766 resolved
Dart source files, ten SDK inputs, actual AOT bytes, model/library identities,
source offsets, tokenization, cache counters, quality projections and merge
policy. The fixed publisher assets and original source corpora remain intact.

Individual development counts overlap and must not be added to this final total.
All failed attempts are preserved where captured. Early reuse-development
failures were visible only in tool output and have no reconstructed raw log;
`inference-reuse/reuse-local-report.json.gz` records that limitation. Final
source-bound replays and the full final gate are preserved.

Archive indexes provide exact byte lengths and SHA256 for every member. The
independent scripts and detailed reports are in the final audit archive. Native
logs preserve unavailable failure diagnostics as null, never invented zero
forwards. The producer's repeat-output stability flag is distinguished from
independent reconstruction of every retained finding and pass.

## Reproduction and next work

Use the retained SDK/native pack and qualified `.venv-ref` Python described in
`recovery/`. Runtime activation is
`/workspace/scratch/e5b34feae619/runtime-recovery/activate.sh`; all temporary
outputs must use fresh writable scratch paths because this host lacks `/tmp`.
The `run_native_modes.py`, `run_quality_panels.py`, `validate_final.py` and
`final_validation_suites.json` files preserve explicit commands and selections.
The AOT build helper is `tools/proofing/german_model/build_gector_aot.py` with
`provider` and `incremental-quality` targets. Finish all tests and compiles before
running native timings. Keep measured receipts and failed attempts immutable.

Prioritized remaining work:

1. Reduce native work for long paragraphs whose model inputs are distinct;
   repeated-input reuse provides no hits in that case.
2. Extend carefully bounded participle ranking to reviewed `sein` contexts and
   evaluate the retained `gegangt` failure without changing existing gold.
3. Broaden independently frozen sentence/paragraph quality evaluation, including
   false-positive controls for new noun, verb-object and duplicate-role cases.
4. Measure responsiveness on intended devices and qualify platform/distribution
   packaging. Segmentation/reuse remain explicit host options and model checking
   remains manual de-DE checking.
5. Run full ODF schema and desktop-consumer validation on the final source.
   Incoming Office consumer reports are preserved historical evidence; this
   continuation validates final XML structure/unit behavior, not final desktop
   rendering acceptance.
