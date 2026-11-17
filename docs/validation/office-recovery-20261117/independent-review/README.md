# Independent final evidence audit

**Accepted.** The independent verifier finished at 2026-11-17 16:28:36 UTC with
no discrepancies and no pending evidence. This audit concerns frozen product
commit `966196f386ec1776c836664b3eb7c93e8e92605c`, tree
`4287330a433e915d58ca779adfacb75942c6ab04`.

`verify_final.py` reconstructs outcomes from raw Dart/Flutter JSON events and
Python unittest output. It independently reads saved ODT, reopened DOCX, PDF
bounding-box/text output, and raster artifacts. It does not import either
qualification/consumer harness implementation, execute product tests, invoke
LibreOffice, or contact GitHub CI. The machine-readable result is `audit.json`.
Its 38,305 audit checks are evidence-integrity checks, not additional product
test passes.

## Raw qualification outcomes

| Cohort | Files | Raw successes | Substantive successes | Skips |
| --- | ---: | ---: | ---: | ---: |
| Engine Zotero | 19 | 390 | 390 | 0 |
| Editor Zotero | 13 | 186 | 186 | 0 |
| Engine integration | 97 | 2,128 | 2,126 | 0 |
| Editor integration | 37 | 396 | 396 | 0 |
| Harper contract | 3 | 29 | 29 | 0 |
| GECToR contract | 11 | 193 | 193 | 1 |
| **Primary total** | **180** | **3,322** | **3,320** | **1** |
| Node repetitions | 14 | 282 | 282 | 0 |

Every raw test start has exactly one completion; suite IDs and test IDs are
unique, every selected file is represented, and no unexpected suite appears.
All seven streams end with a successful runner terminal event and contain zero
error events or substantive failure/error results. Their reconstructed case
ledgers and counts agree with the recorded summaries. All four strict analyzers
report no issues and the formatter reports zero changed files.

The original plan was read from its preserved, hash-verified archive. All
**174 original primary files remain selected**. Exactly six new engine suites
raise the disjoint primary scope to 180: frame extraction, PAGE field fidelity,
paragraph decoration, section integration, German lexical gaps, and German
spelling quotes. The 282 Node outcomes match the corresponding VM per-file,
per-case, per-outcome multiset exactly. They are repeated executions, not new
unique primary coverage.

The two raw-success private-PDF cases are excluded from substantive totals:
`TrueType subsets without cmap get ToUnicode cmap for the host` and
`JPEG with DCT SMask attaches softMaskJpeg for the host`. The guarded private PDF
is absent. The single Dart skip is the declared native dual-head model/library
fixture case; none of its four pinned fixture environment variables were
provided. Python independently reconstructs **107 successful controls and one
declared optional real-quantizer skip**, across 108 selected cases. These results
do not establish real native model inference or real quantizer acceptance.

## Source and execution identity

Before/after maps are identical and the verifier independently rehashed current
inputs: **3,449 frozen non-documentation source entries**, **5,099 dependency
files**, **14 runtime entries**, **118 workspace entries**, **6 system entries**,
and **9 harness entries**. The system map includes the explicitly absent private
PDF. Source inventory, Git blob identities, file modes and contents match the
frozen commit. The workspace lock matches the preserved committed lock. The
Python executable and 431 NumPy input hashes also match their preserved maps.
The final receipt records the frozen HEAD unchanged and analyzer configuration
restored. Current HEAD at this audit was still the frozen commit.

## Saved consumer artifacts

The independent artifact audit reproduces **26/26 fixture passes** and
**104/104 OASIS ODF 1.3 XML-part validations**. It verifies all fixture identities,
ODT/DOCX ZIP integrity, saved PDF page dimensions, expected word positions,
ordering, list markers, applicable indentation/layout/edge checks, reopened
section types and frame geometry. It independently resolves DOCX paragraph/run
styles for the two recovery fixtures, verifies live PAGE instructions and the
full suffix with actual PDF page numbers 1 and 2, and checks the expected raster
fill/footer colors. This is an artifact audit; it does not claim a separate
visual review or another LibreOffice conversion run.

All **395 consumer source inputs**, **10,420 runtime inputs**, and **329 recorded
output hashes** match current bytes; before/after input maps and generated
fixture inventory agree. All 86 recorded consumer commands exited successfully.
The consumer aggregate equals the independently assessed individual outcomes.

## Archive integrity

| Archive | Independently verified members | SHA-256 |
| --- | ---: | --- |
| `consumer/evidence/final-966196f3.tar.xz` | 344 | `9a4ff35ab6dd4dbfeee9964284360ec09c3919a28bb551296b3a5f18e7e33520` |
| `qualification/evidence/qualification-966196f3.tar.xz` | 103 | `5f7e3b60530bc8070684f6aa1bd23957a3e1d86629c8ca6f30097e2ab29411a2` |

Both archives have exact, duplicate-free indexed member sets with matching
member lengths and SHA-256 hashes. Qualification member modes also agree with
the index; all 91 raw qualification files are present and byte-identical to the
audited run. Consumer run members match audited raw artifacts, with the two
outer runner logs mapped explicitly and the archived visual-review supplement
matched to its repository copy.

This audit qualifies the frozen source and its bounded plan only. It does not
extend qualification to branches or PR commits arriving after the integration
cutoff, and it does not turn the declared optional-fixture exclusions into
accepted coverage.

## Reconstructing the audit

The preserved verifier retains the original execution paths in its top-level
constants. Restore the two evidence archives and the recorded runtime/cache,
then adapt those environment locations for a new checkout. It verifies saved
artifacts and current input bytes; it does not rerun application tests or office
conversions. The recorded verifier hash binds the exact script used here.
