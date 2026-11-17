# ODT column-boundary follow-up — 17 November 2026

The pasted ODT handoff was already published in PR #140. This session resumed from PR #143 at `947a6b572f3e95359b80d785e1a232e824fa723b`, fetched all 175 remote branch heads and all 143 PR heads, and captured them in `incoming-refs.json`. Main `2c47165d01d01cc883135a434ac9f6591ce6e770` is included.

PR #143 advanced while the first checkpoint was being saved. The further sheet-format and recovered-evidence commits through `83f8c380f9271b6bf34a300c3aedc19442cb61f1` were fetched and integrated. This continuation uses the dedicated remote branch `codex/odt-column-boundary-followup-20261117` so ongoing PR #143 writes do not compete. The separate native spaCy PR #139 remains separately owned, following the existing reconciliation decision.

## Source changes

A leading inline column break must remain separate from the paragraph that establishes a section or explicit page break. Previously only the first document section retained an empty source fragment. Later multi-column sections could combine the column and section/page boundaries on one paragraph, losing the column break to page/master precedence. The writer now retains that source fragment for any multi-column section start and for an explicit paragraph page break.

Five new controls demonstrate the loss on the pre-fix writer: later next-page, continuous, odd-page, and even-page sections, plus an explicit paragraph page break. The existing imported-DOCX control now expects the distinct source fragment and checks model identity and flags. Bookmark order, text, section ownership, and later column breaks remain explicit assertions.

A restored column-style test expected negative gaps to be exported, contrary to the existing writer and `odt_section_columns_test.dart` contract. Its assertion now preserves that existing conservative profile: omit the unsupported negative gap attribute while preserving count, visible text, source value, zero normalization, and style precision. This is a test reconciliation, not a new negative-gap behavior or a claim that the ODF grammar forbids signed lengths. ODF 1.3 section 19.233 and the official RNG declare `fo:column-gap` as `length`:

- https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html
- https://docs.oasis-open.org/office/OpenDocument/v1.3/os/schemas/OpenDocument-v1.3-schema-rng.html

## Local qualification

Fresh qualification is pending the saved source checkpoint. The runtime reproduces Flutter 3.47.8 / Dart 3.13.7, the locked 108-package dependency graph, and the exact native library/model hashes required by the existing runner. Historical passing results and interrupted runs are not counted as current results.

The five failing pre-fix controls and initial focused attempts are retained separately. Final results will include the selected local test cohorts, strict analysis and formatting, Python controls, portable field checks, and independent ODF consumers where executed.

No GitHub Actions, workflow, check-run, or CI-status endpoints are queried or awaited. Source and completed evidence are saved incrementally to the remote follow-up branch.
