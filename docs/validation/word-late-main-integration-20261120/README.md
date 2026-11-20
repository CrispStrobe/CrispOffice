# Word late-main bridge qualification — 2026-11-20

The narrow Word bridge is accepted at published commit
`52eace9e151cff88c5908a049b0a51ade4c20b00`, tree `a86b3c847e981c8eec2ad71d781afb7d1887985d`.
All **71 cases passed**, with no failures or skips. Whole-engine analysis with
fatal infos and the agreed seven-file read-only format check also passed.
The [fresh receipt](qualification.json) records exact commands, case populations,
raw output hashes and unchanged source/runtime seals; the
[accepted summary](accepted-summary.json) preserves the source attribution of
the incoming results separately.

## What changed after the c623 checkpoint

Only two engine/editor production files differ from `c62338c6`:
`word_layout.dart` and `word_deserializer.dart`. Both are byte-identical to
incoming main `5e7e4d24284954603a0a5951699bea870ad1955f` and the selected incoming
execution source. The VBA compiler, macro fixtures and canonical BAS examples
remain unchanged. This checkpoint contains the Word changes independently of
the remaining Mail reconciliation, allowing the bounded Word check to finish
without waiting for that separate work.

The layout change recognizes a repeated reference to the same `WmlVisual`
node within one header/footer collection as one occurrence. It still preserves
distinct authored nodes that share an image asset or position. It also shares
the existing body-frame-prefix filtering between continuation and content-bottom
calculation. The deserializer updates imported paragraph baselines only when
table fallback spacing actually changes and an imported baseline already exists.
That preserves the distinction between an import default and an authored edit.

Two incoming suites add 15 header-visual and 14 table-import regression cases.
Their exact-source incoming executions are retained. Our additional independent
identity/style assertions and the canonical contained-text fixture are freshly
checked against the integrated libraries.

## Fresh bridge

| Suite | Passing cases | Purpose |
| --- | ---: | --- |
| `word_header_picture_identity_test.dart` | 13 | Distinct nodes, shared assets, placements and native header/footer roundtrips |
| `word_styles_layout_test.dart` | 17 | Existing style/layout behavior plus explicit color and bold-off precedence |
| `word_contained_text_wrap_test.dart` | 41 | Exact text/glyph containment and repeated native direct/isolate save/reopen behavior |

The 71 identities match the corresponding cases in the c623 receipt exactly.
They are superseding executions of existing assertions against changed Word
production, not 71 new logical test cases. The 31.2-point inner-content fixture
and all exact glyph, fit and roundtrip assertions remain unchanged.

The whole engine analyzer reports no issues with `--fatal-infos`. Formatting
was checked without writes for the two production files, these three suites,
and the two new incoming regression suites. The fresh engine runtime is
Dart 3.14.1 with the pinned package:test runner and dependency configuration.
All 2,859 captured source inputs, runtime inputs,
HEAD and clean-tree boundaries remained unchanged. The seven selected file
hashes were also compared directly with immutable Git objects at the published
source. No dependency resolution, SDK/cache change, CI wait or product edit
occurred during this gate.

## Incoming evidence retained with its original source/runtime

The [incoming audit](incoming-retention-audit.json) verifies all 271 members of
`docs/validation/mail-bulk-flags-20261120/late-evidence.tar.gz`, paired source
seals, raw case events, successful exits, and direct bindings to available
Git objects at incoming execution `44f3f61fa7d812971e973f1763ac8e04eb39785a`
and main `5e7e4d24284954603a0a5951699bea870ad1955f`.

| Incoming scope | Retained result | Counting boundary |
| --- | --- | --- |
| Combined Word VM | 929 passing cases | Exact selected source |
| Additional focused Word VM | 188 passing cases | Excludes incoming style15 and contained41 variants, which this bridge replaces |
| Word VM union | 1,055 unique passing cases | 929 + 188 minus 62 shared identities |
| Word Node/dart2js | 787 passing rechecks | Overlaps VM; not additional logical cases |
| Affected Zotero VM | 165 passing cases | Exact relevant inputs; overlaps earlier acceptance |
| Affected Zotero Node | 117 passing rechecks | Separate platform evidence, not added to VM |
| Editor follow-up | 362 passes and eight declared exclusions | Nine Zotero suites plus incremental-layout and two proofing suites |
| Font loader | 9 passing cases | Includes actual lowercase filename-alias fixtures |

The incoming editor source manifests are broader than those test dependencies.
Mail host differences are explicitly excluded where the editor/Zotero code
does not reference them. The incoming 16-case Studio receipt is recorded but
is **not adopted as exact-current evidence**, because Studio can load the
changed Mail paths. Mail retains its own source-specific qualification.

The two actual BAS measurement/named-measurement VM and Node driver pairs are
verified in the incoming audit. Their input and driver hashes, commands and
result comparisons remain in that evidence. No new BAS execution is claimed
for this 71-case bridge.

The incoming archive remains at its original repository path and is not
duplicated here. Its SHA-256 is
`1ab839ebdeb86599af507d623f98d224620fdd533ff870118a58a8134e8711b8` (4,736,442 bytes).
The audit gives its source commit and exact location, so it remains retrievable
from immutable incoming Git history even in a checkpoint containing only the
Word product delta.

## Relationship to the prior accepted reports

The [c623 Word/Zotero report](../word-final-integration-20261120/README.md)
retains its original result and source seals, including its 663 fresh macro,
223 native, 96 editor-layout, 188 Zotero-engine and 143 Zotero-editor cases.
Those earlier cohorts are **not described as rerun at this later checkpoint**.
The earlier 3,598-case macro corpus also keeps its own source attribution;
the compiler and macro/example files are unchanged. VM, Node, native and editor
counts overlap, so this report supplies no grand total across them.

The eight editor editing-equivalence exclusions remain the exact
`no paragraphs to edit` cases recorded in the c623 report and this incoming
audit. They were not changed into passes. The fresh 71-case bridge itself has
zero skipped cases.

## Reproducibility and limits

The original archive-only verifier passed. Its broader historical Git verifier
could not read an unrelated old promisor object
`df576aa4e32c8c151446309ea1c72dab11d84f06` while checking baseline ancestry.
No fetch was attempted. The independent audit instead directly verified every
selected receipt against the available incoming execution/main objects; the
missing unrelated object is not treated as a successful historical verifier
run. The raw verifier result and independent audit are preserved.

Tracked reference fixtures are bound by immutable peer/main/c623 Git equivalence,
not relabeled as additional historical per-file before/after execution seals.
Incoming runs retain their archived runtime attribution. Node evidence is not
a browser/WASM run, and no installed Microsoft Word/Zotero host or live provider
session was exercised by this gate.

The [deterministic archive](local-qualification.tar.gz) contains the exact fresh
runner, raw outputs, case identities, source/runtime seals, the incoming audit
and auditor, and configuration provenance. It excludes SDKs, caches and build
outputs. [The manifest](receipt-manifest.json) records all member hashes/sizes.
Reproduction uses the commands and working directories in `qualification.json`;
paths and immutable source arguments must be explicitly remapped when running
outside the original workspace. These records must not be overwritten.
