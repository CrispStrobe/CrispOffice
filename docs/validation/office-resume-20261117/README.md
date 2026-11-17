# Office integration resume — final qualification, 17 November 2026

The combined canonical source is qualified at
[`def52d84f3c3c5ce22c44d2620ecfa08d77780a7`](https://github.com/CrispStrobe/quds_office_suite/commit/def52d84f3c3c5ce22c44d2620ecfa08d77780a7),
with **3,280 substantive Dart/Flutter passes across 179 test files and 107
separately counted Python passes**. The synchronized CrispCloud host passed
**90 main Flutter cases, six writer probes and 28 Python controls**, with no
host skips or failures. These are fresh results from the final source pins;
earlier accepted runs and negative controls are preserved separately.

This final checkpoint changes documentation only. The
[source-equivalence receipt](docs-finalization-equivalence.json) records that
every non-documentation path, Git mode and blob remains identical to qualified
`def52d84`. The working branch is `codex/office-qualified-resume-20261117`;
review continues in [canonical PR #116](https://github.com/CrispStrobe/quds_office_suite/pull/116)
and [host PR #238](https://github.com/CrispStrobe/CrispCloud/pull/238).

## Final measured scope

| Canonical cohort | Test files | Raw successes | Substantive passes | Skips |
| --- | ---: | ---: | ---: | ---: |
| Engine Office, ODF and proofing integration | 96 | 2,088 | 2,086 | 0 |
| Flutter editor integration | 37 | 396 | 396 | 0 |
| Engine Zotero | 19 | 390 | 390 | 0 |
| Flutter editor Zotero | 13 | 186 | 186 | 0 |
| Harper contracts | 3 | 29 | 29 | 0 |
| GECToR contracts | 11 | 193 | 193 | 1 |
| **Total** | **179** | **3,282** | **3,280** | **1** |

The two raw-success exclusions are inherited private-PDF cases that return before
assertions when their fixture is unavailable. The GECToR native dual-head case
is explicitly skipped because its four pinned model/library inputs are absent.
The separate Python run has 107 passes and one explicitly skipped tiny ONNX
converter case. Neither skipped case is counted as a pass.

All five strict analysis scopes passed: engine, editor, Harper, GECToR and the
incoming diagnostic ONNX Dart helper. All 76 selected Dart formatting targets
passed with language version 3.12. The Python ONNX bridge passed a syntax/AST
check without being imported or executed; this is separate from test coverage.
The final canonical run took place from 16:35:05 to 16:38:11 UTC.

The [full final report](qualified-def52d84/canonical-qualified-def52d84.md),
[summary](qualified-def52d84/canonical-qualified-def52d84-summary.json),
[independent raw-log review](qualified-def52d84/canonical-qualified-def52d84-review.json)
and [direct positive-coverage proof](qualified-def52d84/canonical-qualified-def52d84-positive-coverage.json)
record exact commands, identities, suite sets, exclusions and limits. All started
test IDs completed, all loaded suites match the plan and no unexpected skip or
load failure was accepted.

### Synchronized host result

The final host run used
[`511361a4623e6ddf787b5cccfaed4ba14ae1899f`](https://github.com/CrispStrobe/CrispCloud/commit/511361a4623e6ddf787b5cccfaed4ba14ae1899f),
pinned to canonical `def52d84`. Its 11 gates passed. The
[independent host review](host-final-qualification-review.json) recounted
90 main Flutter cases, six supplemental writer cases and 28 unique successful
Python cases: **124 substantive passes, no skips or failures**. The prior
80 Dart and 28 Python cases remain; the current scope adds eight annotation
cases, two document-service cases and the six supplemental probes.

The first host attempt remains failed in the host evidence. Two supplemental
note probes had assumed direct-child notes and structural note tables, although
both old and current canonical contracts use styled note spans and visible
paragraphs for note-table export. Their narrow corrections preserve exact
whitespace, field caches, namespaces, note identities and model ownership. A
separate authored XML fixture retains the raw hidden-note import checks. All six
probe cases remain. The generated formatter scope now excludes only exact
manifest-authenticated byte output while retaining every vendor analysis target.
The actual host fatal-info lint was fixed with one `const` keyword in canonical
source and both final qualifications were then rerun.

## Input integrity and limits

Canonical before/after maps match for all 3,448 non-evidence source paths,
5,099 resolved dependency files, 13 runtime artifacts, 118 workspace paths and
links, six system-fixture entries and eight harness inputs. Source blobs and
modes match the frozen commit, HEAD remained fixed and the temporary analyzer
graph was restored. The host review separately verifies 3,829 source inputs,
6,020 dependency inputs, six captured runtime inputs and the supplemental probe
hashes, along with graph restoration and the exact published host HEAD.

The recorded toolchain is Flutter 3.47.8 / Dart 3.13.7. The external canonical
workspace resolved 109 packages offline with the unchanged enforced lock hash
`344190a0224b9e6dcc2161cbfb1be3b7a9569a3a03a809f42801d99f9052e130`.
The manifests, package graphs, executable hashes and executed setup are retained
inside each accepted archive.

This qualification covers the recorded local source and contract suites. It
does not claim real-model inference or model-quality acceptance, availability
of the absent native GECToR fixture, Wasm acceptance, a complete application
build, full viewer/export-dialog acceptance, or live Zotero/Word/LibreOffice
interoperability. Earlier imported native/model and consumer evidence retains
its original source and runtime attribution.

Generated lexical and morphology outputs match their committed manifests.
The first-party German supplement adds exactly `Grüezi`, `Hof` and `grüezi`,
with no removals. The unchanged morphology manifest still records the lexical
inputs of its original generation. No Unicode-source regeneration or refreshed
morphology provenance is claimed.

## Regression controls and final-source positives

| Control | Old-source result | Corrected control result | Final `def52d84` coverage |
| --- | --- | --- | --- |
| Hidden annotation extraction | 6 matcher failures, 1 specific hidden-content output-limit exception, 4 passes | 11 passes | All 11 case names pass |
| Comment/note ownership | 2 matcher failures | 2 passes | Both case names pass |
| Paragraph decoration cache | 2 matcher failures | 2 passes | Both case names pass |

All 15 controlled cases pass freshly in the final broad run. Note and decoration
test bytes are identical to the controls. The annotation file differs only by
extracting the same 4,096-character fixture expression into a local variable;
its assertions and other case bodies are unchanged. These cases are already
included in the 3,280 count.

The annotation runner's original overstrict wrapper rejection is retained. A
separate verifier accepts only the documented hidden-annotation output-limit
exception alongside the six matcher failures; the tests were not rerun or
relaxed to disguise it. Two earlier decoration-control setup failures are also
retained and excluded from substantive coverage.

The original [annotation/note archive](canonical-controls-evidence.tar.xz) and
[index](canonical-controls-evidence-index.json), and the
[decoration-cache archive](cache-control-evidence.tar.xz) and
[index](cache-control-evidence-index.json), remain byte-identical. Their indexes
explicitly record the archive root prefixes. Full old/new source bindings,
exact tests, runner scripts, stdout/stderr and input hashes remain available.

The current positive proof also includes 12 frame-extraction cases, 14 section
integration cases, six lexical-gap cases, 18 quotation cases, the two preceding
section suites with 26 and 14 cases, and 12 ODT writer cases. All three section
suites remain executable. The incoming table writer test is byte-exact to its
observed main checkpoint, including all five added test lines.

## Bounded source reconciliation

The original continuation was `555eb728ce3ea872cb5ceb3e5fd2104b21f932aa`.
The [incoming inventory](incoming-inventory.json) captures 289 remote refs
observed from 15:37:31 to 15:37:41 UTC: 132 fork branches, 109 fork PR heads,
21 fork tag refs, four upstream branches, four upstream PR heads and 19 upstream
tag refs. The [final ref audit](final-ref-audit.json) accounts for every captured
ref through ancestry or exact whole-tree witnesses. Later inputs are the bounded,
explicitly observed commits below; no continuously refreshed inventory is claimed.

| Published checkpoint | Source and preservation decision |
| --- | --- |
| `9d057dfd` | Fast-forward through captured GECToR/morphology source and save the incoming inventory. |
| `a499549e` | Merge fidelity source, retain bookmark/link behavior and preserve all preceding section cases. See [fidelity reconciliation](fidelity-merge.json). |
| `b32dee6f` | Integrate captured main and vendor ancestry, retain hyperlink/SMIL assertions and preserve vendor evidence differences. See [main/vendor reconciliation](main-and-vendor-merge.json). |
| `104b239c` | Preserve the failed first formatting preflight and correct four test files without production changes. |
| `cc394ee2` | Merge exactly observed main `7cf48a2f`, preserve PAGE fields and decorations, and correct the decoration-cache identity. See [destination amendment](destination-main-amendment.json). |
| `4c49b043` | Reconcile concurrent `f29373cf` and observed main `2eb080e7` on an isolated branch, retaining both histories, all evidence and the cache fix. See [concurrent reconciliation](concurrent-source-reconciliation.json). |
| `def52d84` | Add the single constant-marker keyword required by the host's strict lint gate, then repeat both qualifications. See [lint correction](host-const-lint-correction.json). |

The shared branch advanced concurrently during publication. Its expected-head
update correctly refused to overwrite that work. The candidate moved to the
isolated branch, and the exact observed concurrent head was merged before the
final freeze. Concurrent source adds structured ODF frame tables and visibility
guards, an empty body for explicitly zero-section documents, quotation casing
and the three lexical forms. The later observed main adds table borders and row
heights. Original writer/test snapshots and exact combination patches are kept
alongside the reconciliation receipts.

The [post-const equivalence proof](qualified-def52d84/canonical-post-const-equivalence.json)
shows the sole product difference from the earlier accepted `4c49b043` is that
one keyword. All 179 test files, runner bytes and the complete selection plan
apart from its source SHA are unchanged. Both accepted runs keep their own
source-specific archives and totals; their passes are not combined.

## Evidence, readback and reproduction

| Accepted source | Evidence |
| --- | --- |
| Final `def52d84` | [Report](qualified-def52d84/canonical-qualified-def52d84.md), [summary](qualified-def52d84/canonical-qualified-def52d84-summary.json), [archive](qualified-def52d84/canonical-qualified-def52d84.tar.xz), [index](qualified-def52d84/canonical-qualified-def52d84-index.json). |
| Earlier `4c49b043` | [Report](qualified-4c49b043/canonical-qualified-4c49b043.md), [summary](qualified-4c49b043/canonical-qualified-4c49b043-summary.json), [archive](qualified-4c49b043/canonical-qualified-4c49b043.tar.xz), [index](qualified-4c49b043/canonical-qualified-4c49b043-index.json). |

Each accepted archive contains 129 members, including 22 executed setup inputs
and receipts. The final archive is 886,556 bytes with SHA-256
`a58a73166a36d36223e7cc215dd6b32caa27e5e6d268fe1b91d0b2323f6f9a5b`;
the preceding archive is 887,836 bytes with SHA-256
`384c9a9405f40e0b3a668b0afad3d8a414da60a539352f32e14fd24c019c433e`.
All members were read back with exact hash/size comparisons. The
[shared readback report](canonical-delivery-readback.json) also verifies the
three retained preflight/control archives at both recorded source commits and
the original failed preflight at published `104b239c`. The
[delivery manifest](canonical-delivery-files.json) binds the copied artifacts.

The original failed formatting preflight remains under
[office-continuation/resumption](../office-continuation-20261117/resumption/).
It records successful analyses and the formatting failure, with zero product
tests. The four-test correction and its AST/token-equivalence proof remain
unchanged. Failed setup, wrapper and reviewer attempts are retained under their
original attribution.

For reproduction, restore the pinned SDK/cache and locked external workspace
from each archive's `setup/` records. Both accepted-source directories have the
executed `run_qualification.py` and `python_controls.py` side by side. For the
final source:

```sh
python3 qualified-def52d84/run_qualification.py \
  --repo /path/to/clean/quds \
  --source-commit def52d84f3c3c5ce22c44d2620ecfa08d77780a7 \
  --flutter-root /path/to/pinned/flutter-sdk \
  --workspace /path/to/locked/external-workspace \
  --output /path/to/new/evidence-directory
```

Use `--plan-only` to inspect selection. Every execution requires a fresh output
directory. The archived independent reviewers can recount saved logs without
running product tests. [The delivery verifier](verify-canonical-deliveries.py)
can read back both archives and their exact retained Git objects.

No GitHub Actions, CI-status or workflow endpoint was queried, awaited or rerun.
Remote branch updates checked their expected head, and every checkpoint message
includes `[skip ci]`.
