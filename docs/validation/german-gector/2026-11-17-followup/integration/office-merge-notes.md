# Captured Office integration notes

Initial GitHub snapshot was observed at 2026-11-17T19:20:37Z and contains 162 unique branch heads and 132 unique PR heads. The starting feature head is `088705198d38811fde869707bc9711e20524d5f0`; the captured main head is `081af8a55338c713ba8b350f2519f2021d9caee3`. These observations do not cover later arrivals.

## Source intent

- PR #129 deliberately removes the AOT/RML package and app integrations after integration. Older branch ancestry must not restore removed AOT source. Historical evidence remains attributable to its original source.
- PR #123 and PR #128 were closed unmerged. PR #123 is ancestral to later qualified Office histories; its source is not a replacement for current proofing/Office source.
- PR #132 explicitly brings non-AOT extraction/story/header-media/bookmark repairs from the fidelity work in PR #128. Main also has newer fields, columns, TOC, proofing and ODP behavior that broad checkout of the older branch would discard.

## First merge resolution

- `office_search_text.dart`, `office_text_extractor.dart`, `odf_text.dart`, and `odt_document_writer.dart` use the exact captured incoming stage-3 source. This preserves tracked-change exclusions, story ownership, header/footer visuals, newer TOC/fields, normalized run colors, current paragraph style identity, minimum row heights and section columns. Negative column gaps follow the incoming omission behavior and existing incoming tests.
- `odt_tab_stop_fidelity_test.dart` combines the incoming rounded-position and leader-glyph assertions with the feature branch's independently named glyph regression.
- `odt_table_tab_fidelity_test.dart` keeps incoming source. The earlier feature branch's independent table/tab suite is preserved verbatim as `odt_table_tab_gector_fidelity_test.dart`.
- Original stage-2 and stage-3 versions are retained under `office-merge-inputs/` with SHA-256 and size records. No git index writes were performed by the audit agent.

## Pending qualification findings

Static inspection identified a likely inline-field regression: main contains stateful `pendingFieldElement` conversion while retaining older tests that require complete bounded PAGE/NUMPAGES packets, locked/malformed/nested fallback and unchanged cached text. This is not yet a measured failure. Commit `898c4c07` contains the earlier bounded functions `_writeParagraphInlines`, `_simpleInlineField` and `_plainFieldBoundary`, which can be restored with the newer column-splitting callback.

Main also keeps `_OdtBookmarks` and `WordBookmarks.pairedEnds`, but routes output through a newer mutable ID map. Existing bookmark tests should determine whether the story-paired implementation must be restored. No regression is claimed before running the exact tests.

No CI workflow, check, action, or status endpoint was requested, polled, dispatched, or awaited.
