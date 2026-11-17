# Zotero integration and local qualification — 17 November 2026

The combined canonical implementation is **`b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc`**,
tree **`642436fb32d73cb73706a4dd1c1fce32d0f2fb8b`**. It retains the recovered
Zotero optimizations, all work in the fixed incoming inventory, and destination
main through **`fb3d3a4d275f0be7161c13a4763fcd6cac3e2c13`**, including ODT footnotes
and endnotes. Every accepted qualification below is bound to its exact source;
later evidence commits do not alter the implementation.

This continuation recovered the remotely saved source and ran fresh local
qualification. The earlier continuation notes reported a final combined run whose
terminal evidence was absent from the recovered checkpoint. Those unpublished
counts are not adopted here. Earlier source, historical reports, failed attempts
and their original attribution are preserved.

## Delivered behavior

The 50 audited Zotero source, example, test and fixture paths retain their exact
recovered Git blobs and file modes. The 576 engine/editor Zotero regressions
passed in the broad run. The preserved implementation provides:

- Citation-source deduplication across late and transitive URI aliases, while
  keeping distinct libraries/profiles separate and preserving the first available
  embedded CSL snapshot.
- Parsed-field reuse in the document tab, including the existing regression
  for one full field scan in the 1,000-citation case.
- Shared online backoff across reconnects, credential/library changes and dialog
  reopening, with independent desktop-client pause state.
- Bounded, staged metadata refresh: no more than 50 item keys per request,
  validation of returned results and the edit target, and one atomic undoable
  document update.

The combined Office source also retains the captured proofing and rendering
work, bounded spreadsheet formula evaluation, conditional-format style
serialization and durable sheet-rename undo. Newer main's ODT/ODP writers,
ordered lists, ODP transitions, ODF tables, merged/covered cells, paragraph
properties, headers/footers and note export are integrated without dropping
those changes.

The ODT writer keeps visible cached citation/bibliography results while omitting
hidden field instructions. It preserves spaces, tabs and line breaks through
body, list, table and note paths. The final note probes explicitly exercise
footnotes/endnotes containing Zotero fields, list groups and merged table
stories. Canonical extraction excludes covered-cell stories from visible text
while retaining them in the document package. The host's separate reader fixes
and consumer checks are documented in the companion
[CrispCloud report](https://github.com/CrispStrobe/CrispCloud/tree/codex/zotero-recovery-20261116/docs/validation/zotero-landing-20261117).

## Accepted local qualification

| Stage | Exact source | Accepted test results | Report |
| --- | --- | --- | --- |
| Broad combined source | `837d06edbde08a2465e99cbbb15927ee4c87d8ac` | **2,576 substantive passes** across 144 disjoint files | [Full run](canonical-full-run.md) |
| Ordered ODT lists | `2ae8bf3420bd20ec33115c96a44a38a0d3a78df0` | **26 passes**, three files | [List amendment](odt-list-amendment.md) |
| ODF fidelity and extraction | `f510060e35d580cbc361985a123927705c92ddc4` | **156 passes**, 12 files | [ODF amendment](odf-amendment.md) |
| Destination-main footnotes/endnotes | `b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc` | **114 source passes plus two supplemental probes** | [Note amendment](note-amendment.md) |

The later stages repeat earlier suites. Their counts are **not summed as unique
tests**, and the broad-run total is not represented as a complete rerun on a
later commit. Each bounded stage qualifies the specific subsequent source delta
and its relevant interactions, with exact unchanged-input proofs for the rest.

The broad run passed all nine required commands: three strict analyses covering
123 selected Dart targets, formatting of 81 changed/recovered targets, and five
disjoint test cohorts. The cohorts are 390 engine Zotero, 186 editor Zotero,
1,586 substantive engine-integration, 385 editor-integration and 29 Harper
adapter tests. Its 2,578 raw success events include exactly two unavailable
private-PDF fixture early-return cases; those two are excluded from the
substantive count. Required font fixtures were present and fingerprinted.

The ODF amendment analyzes/formats all 12 changed Dart source/test/tool paths.
The new morphology scripts pass Python syntax, CLI-help and 256-case corpus
JSON validation; this tooling check makes no new grammar-runtime quality claim.
The final note amendment changes only the engine README, ODT writer and writer
test relative to the previously qualified source. Its strict analysis/formatting,
eight selected source suites and two separate note probes all passed, with no
failures, skips or fixture exclusions. All 3,332 source inputs outside that
three-file delta remain identical to the previous qualified source.

## Integrity and independent review

Every accepted run records command arguments, working directories, times,
exit codes, raw log hashes and exact source identities. Before/after maps bind
source, dependency, runtime, workspace, system and harness inputs. All maps
remained stable, source blobs and modes match Git, and the original analyzer
configuration was restored. The final note stage uses the same complete runtime,
external dependency and system maps as the accepted full and ODF stages.

The runtime is the genuine official Flutter 3.47.8 / Dart 3.13.7 toolchain. SDK,
engine and compiler identities, binary hashes, unchanged tool/workspace locks,
lock-enforced setup and offline-resolution receipts are included in the evidence.
No production library or executed test is replaced with a stub.

Independent reviews recomputed the terminal events, suite identities, log
hashes, source blobs/modes and integrity conditions:

- [Broad execution review](independent-full-review.json).
- [Ordered-list review](odt-amendment-independent-review.json).
- [ODF execution review](final-canonical-independent-review.json) and
  [source review](final-canonical-static-review.json).
- [Note execution review](note-independent-review.json) and
  [source/merge review](note-source-independent-review.json).

## Incoming work and landing

The fixed inventory accounts for **220 Quds refs**: 214 ancestors and six exact
whole-tree aliases to integrated ancestors, with zero outstanding. See the
[timestamped inclusion audit](quds-final-ref-audit.json). The final source is a
descendant of that audited integration and preserves all original captured heads.

The original recovery PR #85 was merged at its earlier head by concurrent work.
This follow-up preserves its ancestry and adds the remaining captured work and
fresh evidence. The subsequent destination-main inspection identified only the
ODT note writer/test and documentation delta. A normal two-parent merge combines
saved recovery/evidence `d95701cffb7bd6ca9085d073c2297373932f374e` with destination
main `fb3d3a4d275f0be7161c13a4763fcd6cac3e2c13`. The source/merge review records both
parents and the exact three-file delta. This is a bounded inventory, not a claim
about future concurrent branches.

The companion host uses the guarded canonical pin, preserves its standalone
parser and host-specific source, and retains incoming release metadata/evidence
with the original authors' attribution. Source checkpoints were saved remotely
before qualification. Publication uses expected-head checks and never rewrites
remote history.

## Complete evidence and reproduction

| Package | Complete archive | Verified member/archive index |
| --- | --- | --- |
| Broad accepted run | [canonical-evidence.tar.xz](canonical-evidence.tar.xz) | [canonical-index.json](canonical-index.json) |
| Ordered-list amendment | [odt-list-evidence.tar.xz](odt-list-evidence.tar.xz) | [odt-list-index.json](odt-list-index.json) |
| ODF amendment | [odf-evidence.tar.xz](odf-evidence.tar.xz) | [odf-index.json](odf-index.json) |
| Note amendment | [note-evidence.tar.xz](note-evidence.tar.xz) | [note-index.json](note-index.json) |

Every archive was read back completely and each member's hash rechecked against
the closed source file. The packages include raw logs, full receipts, maps,
exact runners, supplemental probes, locks and reproduction instructions. The
[runtime setup archive](runtime-setup.tar.gz) and
[source/setup checkpoint](source-setup-checkpoint.tar.gz) preserve recovery
provenance. SDK/cache binaries are omitted; the runtime README documents how to
restore the genuine versions. Use separate replay-output directories so original
evidence is not overwritten.

[Earlier failed preflights](checkpoints/README.md) remain intact. The first
format attempt found four inherited Zotero test-format mismatches, proven
byte/mode-identical to the captured main. The accepted formatting scope covers
the actual changed/recovered targets; all 123 analysis targets and 144 test
files remained in scope. The second attempt exposed a harness relative-path
comparison error after 390 engine tests. The path-normalization correction and
fresh complete rerun are recorded; those failed-attempt tests are not counted
again. [Checkpoint history](checkpoint-history.md) preserves interim reports.

## Scope

The accepted evidence covers focused local engine/editor behavior, the Harper
adapter and separately documented host consumers. It does not establish a full
application build, complete viewer/export-dialog acceptance, native/Wasm Harper
acceptance, live Zotero accounts/desktop behavior, or Word/LibreOffice
interoperability. Mocked network/protocol boundaries retain the existing tests'
original scope. Incoming TestFlight/release evidence is preserved as authored
and is not reattributed to this continuation.

**No GitHub Actions, workflow, check-run or CI-status endpoints were queried or
awaited.** All qualification was local, and checkpoint commits use `[skip ci]`.
