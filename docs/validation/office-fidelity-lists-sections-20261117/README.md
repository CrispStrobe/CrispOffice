# ODT lists and sections — 17 November 2026

Continuation of `8eb01db06c1457fa04ab3f3b8b2ef8fef791fb43` on
`codex/office-fidelity-20261117`, draft PR #101. Work is saved as incremental
remote checkpoints with `[skip ci]`. GitHub Actions, check, and commit-status
endpoints are neither queried nor awaited.

## Incoming histories

The [recorded snapshot](incoming/) contains 240 named references: 126 fork
branches, 106 fork PR heads, four upstream branches, and four upstream PR
heads. One branch moved between REST collection and Git fetch, so both exact
revisions are retained: 241 reference/revision pairs and 162 distinct heads.
The Git observation completed at 2026-11-17 14:49:26 UTC (15:49:26 Berlin).
Later arrivals are outside this finite snapshot.

Every captured head is an ancestor of integration checkpoint
`097475fbda96aa4a6497d92f28d10f1aa5f640b4`. It includes ODT sections PR #104,
nested lists PR #106, their original/vendor histories, morphology PR #105,
the optional GECToR provider/manual editor lane, and ODF annotation extraction.
The complete prior final consumer evidence remains byte-for-byte unchanged.
The conflict decisions and exact revisions are saved in `incoming/`.

## Implementation

The [export guide](../../odf-export-fidelity.md) defines the mappings and limits.
This continuation adds 40 list and 26 section regression cases:

- Repeated authored levels retain sibling relationships; mixed marker kinds,
  supported decimal starts/restarts, default child resets, and continuation
  preserve visible numbering without changing source paragraphs or native XML.
- Auxiliary and hidden list stories cannot consume visible body counters.
  Complex cached markers remain literal; unsupported native numbering semantics
  and full editable numbering round trips remain explicit limits.
- Section activation reaches lists, nested content controls, tables, pictures,
  frames, and empty sections. First-paragraph formatting remains direct.
- Odd/even first pages use a temporary parity master followed by the normal
  section master. Shared header annotations remain single definitions.
- Equivalent continuous sections avoid an extra page break. Image bytes and
  authored comment references determine story equivalence; empty equivalent
  continuous sections add no paragraph. Changed page styles use a page-boundary
  fallback. First/alternating headers and inherited native stories remain outside
  the bounded writer.

No new font or model binaries are committed. Incoming work adds the optional
GECToR workspace/package manifests; the existing dependency lock remains exact.
The one missing locked package was restored from its official archive after
checksum verification; [runtime/restoration.json](runtime/restoration.json)
records that restoration.

## Incoming-work qualification

The [incoming validation archive](incoming-validation/README.md) retains raw
events, source/runtime identities, the original failed static receipt, and its
bounded correction. All 86 archived files have been restored and hash-verified.

| Cohort | Passing executions | Explicit skips | Test files |
| --- | ---: | ---: | ---: |
| Optional GECToR VM | 97 | 1 | 8 |
| Engine integration VM | 78 | 0 | 5 |
| Actual Flutter editor | 119 | 0 | 6 |
| Node engine repetitions | 49 | 0 | 3 |
| **Dart/Flutter executions** | **343** | **1** | **22 file executions** |
| Ancillary Python checker tests | 65 | 0 | 2 modules |

The native-inference test is explicitly skipped without its pinned fixture
inputs; adapter tests do not establish native inference. Original GECToR tests
use `dart:io` fixture loaders, so no JavaScript GECToR suite is claimed.

The initial engine runtime tests passed, but strict gates found two missing
braces and a note-test formatting difference. The exact correction and
subsequent strict-gate requalification remain separate from that failed receipt.
Qualification binds the incoming source and the small corrected source;
final-source equivalence for the proofing files is assessed independently.

## Final ODF qualification

This implementation checkpoint preserves the completed source and preceding
evidence before final local qualification. `run_qualification.py` executes the
17-file VM and six-file Node ODF cohorts against an exact published commit,
with unchanged source/runtime/lock checks and raw-event coverage verification.
The final receipts and accepted results are added in the next evidence checkpoint.

`consumer/make_fixtures.dart` and `consumer/verify_consumers.py` define 23
independent consumer fixtures. The saved incoming-writer controls validated
80 XML parts but failed 19 of 20 semantic fixtures, demonstrating that schema
success alone missed the section and list defects. Original controls, checker
source, and failures are preserved in `consumer/evidence/baseline-097.tar.xz`.

Final consumer checks use official OASIS ODF 1.3 schemas, fresh LibreOffice
and Poppler output, exact page sizes/text placement, list marker/indentation
checks, parity, and the empty-continuous comparison. PDF conversion explicitly
sets `IsSkipEmptyPages=false` so automatic parity blanks remain measurable.
Source, runtime, dependency, and font inputs are bound before and after.

These are scoped regression and consumer checks. They do not requalify every
previous test cohort or claim complete Office round trips or universal shaping.
