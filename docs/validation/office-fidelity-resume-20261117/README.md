# Office fidelity resume — 17 November 2026

This continuation resumes the saved `8106752e` source and completes new local
qualification after integrating later work. The working branch remains
`codex/office-fidelity-20261117`, with draft PR #101. No GitHub Actions, check,
or commit-status endpoints are queried or awaited. Checkpoint messages use
`[skip ci]`.

## Incoming scope, saved before implementation

The snapshot captured **232 named references / 155 distinct head commits**:

| Source | References |
| --- | ---: |
| Fork branches | 121 |
| Fork PR heads | 103 |
| Upstream branches | 4 |
| Upstream PR heads | 4 |

The fork observation completed at **17 November 2026, 15:03:11 Europe/Berlin**;
upstream completed concurrently. Synthetic PR merge refs are excluded. The
[exact observations](incoming/) preserve each ref, SHA, and observation time.
Across this and the three earlier observations, **245 reference/revision pairs
covering 167 commits** are retained, including superseded tips.

The integration adds main `3458c897`, ODT comment PR #103 and its original/vendor
history, Zotero landing PR #102, morphology qualification/license evidence, and
updated GECToR qualification tools/evidence. The ODT merge retains the repaired
note resolver and table/story behavior while adding the incoming comment
writer once. Duplicate older note helpers and duplicate comment loops were
excluded during conflict resolution. Incoming evidence remains intact.

The saved integration is **`fc44377279ced4589e637360e5f67501012e022c`**. Every
captured head is an ancestor. The Git tree was verified byte-for-byte against
the local integrated result before updating the remote branch with its expected
previous head. Later remote arrivals are outside this finite qualification
cutoff.

## Fidelity improvements

The [export guide](../../odf-export-fidelity.md) describes the exact mappings and
limits. The resumed changes address two independently reproduced defects:

- **Comment stories:** visible main-body anchors take precedence over hidden or
  auxiliary occurrences; recursive annotations and note expansion are bounded;
  ambiguous definitions do not silently bind to an arbitrary body. Author,
  initials, date text, formatting, line breaks, lists, links, and media are
  retained in valid ODF structures. A LibreOffice-specific hyperlink-text loss
  is repaired without adding text to the source model.
- **Presentation rotation:** text and picture frames rotate about the authored
  center with explicit affine transforms. Rotated tables use cell text frames
  because the tested consumer ignores native table rotation. Ordinary tables
  remain structural tables; rotated-table native editability is an explicit
  limit of the visual fallback.

The inherited paragraph spacing, merged/empty/ragged tables, headers/footers,
notes, slide transitions, conditional formatting, and logical PDF text work
remain in the integrated source and selected local validation scope.

## Reproducible local qualification

Activate genuine Flutter 3.47.8 / Dart 3.13.7 and the recorded unchanged workspace
lock, then use the existing [bounded-cohort harness](../office-fidelity-continuation-20261117/validate.py).
It runs engine, actual Flutter editor, Harper, and JavaScript/Node cohorts in
separate invocations. Engine/editor test batches use two workers and release
compiler temporary files between batches. Every output directory must be fresh.

The source closure, fixtures, SDK, full Flutter artifact directory including
fallback fonts, stock launcher internals, compiled Flutter tool, activated
dependencies, and exact lock are bound before and after each cohort. Authored
Dart is strictly formatted and analyzed; generated proofing data retains its
manifest-pinned bytes and remains in strict analysis. Runtime setup provenance
and readiness smoke results are saved [separately](runtime/); smoke results are
not final-cohort counts.

[generate_fixtures.py](generate_fixtures.py) requires a passed engine receipt for
the saved source, then combines test-generated packages with the supplementary
ODF fixtures in a fresh directory. [verify_consumers.py](verify_consumers.py)
checks the exact generated inventory against official OASIS schemas and fresh
LibreOffice/Poppler outputs. Independent receipt review reconstructs counts
from raw events rather than trusting runner summaries.

Final cohort counts and consumer receipts will be recorded after the saved
implementation checkpoint passes these gates. Historical interrupted or
pre-refresh runs are not counted as final results.

## Limits

These are selected cohorts and bounded fixtures, not a claim that the complete
repository test suite or every office document is qualified. The inherited
optional host-PDF early returns remain distinct from runner-reported skips.
GECToR's lightweight Python tooling tests do not requalify its model/native
backends. Valid ODF retention is distinct from consumer retention: the tested
LibreOffice conversion omits some annotation pictures/tabs and annotations in
auxiliary stories. Comment ranges and thread metadata, arbitrary imported
transforms, complete ODF round trips, and shared editor/headless shaping remain
outside this continuation.
