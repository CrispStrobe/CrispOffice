# ODT column-boundary follow-up — 17 November 2026

The pasted ODT handoff was already published in PR #140. This session resumed from PR #143 at `947a6b572f3e95359b80d785e1a232e824fa723b`, fetched all 175 remote branch heads and all 143 PR heads, and captured them in `incoming-refs.json`. Main `2c47165d01d01cc883135a434ac9f6591ce6e770` is included.

PR #143 advanced while the first checkpoint was being saved. The further sheet-format and recovered-evidence commits through `83f8c380f9271b6bf34a300c3aedc19442cb61f1` were fetched and integrated. This continuation uses the dedicated remote branch `codex/odt-column-boundary-followup-20261117` so ongoing PR #143 writes do not compete. The separate native spaCy PR #139 remains separately owned, following the existing reconciliation decision.

## Source changes

A leading inline column break must remain separate from the paragraph that establishes a multi-column section. Previously only the first document section retained an empty source fragment. Later multi-column sections could combine the column and section/page boundaries on one paragraph, losing the column break to page/master precedence. The writer now retains that source fragment for any multi-column section start.

Eight marker controls demonstrate the loss on the pre-fix writer: later next-page, continuous, odd-page, and even-page sections, each with and without an explicit paragraph page-break flag. A standalone explicit-page control preserves native precedence away from a section boundary. Bookmark order, text, section ownership, and model immutability remain explicit assertions.

The exact older imported-DOCX control also contains a later two-column section and two authored column breaks. Rendering its unchanged raw DOCX confirms right-column placement on page two followed by a left-column continuation on page three. Its old coalescing assertion was stale and is corrected to preserve the empty source fragment plus both breaks. With final test bytes, the incoming writer fails these nine controls and passes the other twelve cases across the two boundary suites.

The initially saved candidate `e95cb0ce562a39c7d3cddebff248c43eefe6442b` also separated an explicit paragraph page break from a leading inline column break. Independent rendering of the actual WordSerializer DOCX showed left-column placement for that case, while the candidate ODT put it in the right column. That proposed behavior was withdrawn; the final change is limited to the four independently confirmed section cases. The intermediate five-failure structural run is not presented as five product defects.

A restored column-style test expected negative gaps to be exported, contrary to the existing writer and `odt_section_columns_test.dart` contract. Its assertion now preserves that existing conservative profile: omit the unsupported negative gap attribute while preserving count, visible text, source value, zero normalization, and style precision. This is a test reconciliation, not a new negative-gap behavior or a claim that the ODF grammar forbids signed lengths. ODF 1.3 section 19.233 and the official RNG declare `fo:column-gap` as `length`:

- https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html
- https://docs.oasis-open.org/office/OpenDocument/v1.3/os/schemas/OpenDocument-v1.3-schema-rng.html

## Local qualification

Fresh complete qualification now includes latest main `16e2477ff93f7a1ec5c6ed78491f2716ce4d1658`, which arrived during verification. Its ODF whitespace/extraction, German lexicon/demonstrative handling, and spreadsheet controls are merged without conflicts. The ODT writer remains byte-identical to `9b33bec05df4e08bde06c6768f1e6b5a4af59a1a`. A stale editor scenario is reconciled to the retained `de.grammar.verb-object-case` identifier while preserving correction, no-residual-finding, undo, and redo assertions. The runtime reproduces Flutter 3.47.8 / Dart 3.13.7, the locked 108-package dependency graph, and the exact native library/model hashes required by the existing runner. Historical passing results and interrupted runs are not counted as current results.

Intermediate candidate `e95cb0ce` passed all five strict-analysis scopes but stopped at the formatter before test cohorts ran. Its retained 40-consumer run passed 160 XML-part checks; those outcomes remain attributed to that intermediate source and do not qualify the narrowed final source. A first new-consumer attempt also recorded custom-paper normalization in the native DOCX reference; the final equal-geometry controls use standard Letter paper. Failed attempts and their original observations remain separate.

The subsequent `9b33bec0` broad attempt passed analysis, formatting, Python controls and both Zotero cohorts, then failed only the stale imported-DOCX assertion. The initial Node selection also included one VM-only fixture-export suite that reads `Platform.environment`; it is explicitly excluded from the portable selection and remains in the complete VM cohort. Both failed attempts are archived and excluded from final totals.

The 40 retained consumers pass against the unchanged product source. Four new repaired layouts pass direct ODT, DOCX-imported ODT, and actual native DOCX comparisons. A fifth bounded control verifies standalone page precedence and text/bookmarks; it records a preexisting final-section balancing difference for a follower rather than claiming full native layout equivalence. Its direct/imported ODT content and style XML are byte-identical to the incoming writer. Separate combined-section controls and the exact raw DOCX control confirm the test reconciliation.

The complete `622f58c8` engine and portable cohorts passed; its broad attempt stopped at the inherited editor rule-ID assertion. That attempt is preserved separately. The final selection is recomputed from the merged source, including new ODS whitespace and German release-context suites. Fresh consumer runs bind the newly merged source bytes; `consumer-source-bridge.json` retains the earlier historical bridge and explicitly records its supersession.

No GitHub Actions, workflow, check-run, or CI-status endpoints are queried or awaited. Source and completed evidence are saved incrementally to the remote follow-up branch.
