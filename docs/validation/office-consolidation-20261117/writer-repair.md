# Table and tab export repairs

The captured PR #115 and #118 implementations introduced table borders/row
heights and paragraph tabs. The integrated baseline retained their fixtures,
then a new 37-case suite exposed style reuse, invalid XML and height semantics.

## Corrected behavior

- Paragraph style identity includes exactly the serialized valid tab stops.
  Adjacent paragraphs retain their own positions, alignments and leaders;
  equivalent serialized tabs reuse styles. Invalid-only lists add no empty
  override. Negative tab positions and authored ordering remain supported.
- Dot, hyphen and underscore leaders retain their characters through ODF
  `style:leader-text` instead of collapsing hyphen and underscore to one line.
- Row height is a minimum, matching the shared layout and DOCX serializer's
  `atLeast` semantics. Export now uses `style:min-row-height`. Nonfinite,
  negative and exponent-form dimensions are omitted; valid zero is supported.
- Table cell fills use the same strict six-digit hexadecimal validation as
  paragraph decoration, normalized before style identity and XML generation.
  Invalid fills are omitted without losing supported border flags or changing
  the input model.

The incoming writer fixture is unchanged. Its single `style:row-height`
expectation was corrected to `style:min-row-height` because the original
expectation contradicted the existing shared-model semantics. The recovered
PAGE, decoration and section behavior remains covered.

## Development controls

The initial new suite produced **30 failures, two XML errors and five passes**,
with zero skips. Its original source and raw events are archived. Formatting
later changed two test layouts only; the exact patch is retained.

After repair, **120 VM cases across six files pass**, including the new 37
cases and the existing PAGE, decoration and table tests. The **same 37 new
cases pass on Node**. These are development checks, not an additional unique
case total beyond the final frozen-source qualification.

The first successful runs exposed a test-title difference (`-1.0` on VM versus
`-1` on Node). Invalid-height case titles now use stable indices; assertions
and product source were unchanged. Both cohorts were rerun, and all 37 case
identities and outcomes now match exactly. The earlier successful attempts and
the title-only correction remain archived.

The initial direct analyzer command resolved a symlinked source outside its
package configuration and failed on missing imports. Its log is preserved as
a setup failure; the final qualification uses the normalized package graph and
requires strict analysis to pass. The three-file format check passes.

The baseline local commit `cba51fba67a81afa8e8abba83abd978fca7976a9` was published
as `78a92cfd15487eb36f92aa0fa2053da2b6ccbff1` with an identical Git tree. Source
hashes, test bytes and per-command before/after hashes bind the development
attempts independently of that publication identity.

See the indexed development archive under `development/`. Final qualification
and independent LibreOffice/schema checks are recorded separately.
