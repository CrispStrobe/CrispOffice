# Captured arrival reconciliation

The initial continuation inventory remains frozen. This separate receipt reconciles the three exact external heads captured after that cutoff:

| Workstream | Captured head | Actual common base with the continuation |
| --- | --- | --- |
| Office fidelity | `685b341333dc260db0734658d67798a72b33868c` | `8106752eb410a6c2f66ff03c3fa983123760058d` |
| Morphology | `010d07fc81a1c87f6a2aae7915c9c020928b9465` | `8106752eb410a6c2f66ff03c3fa983123760058d` |
| GECToR | `9f1ca6441e723646769d4b01211cb5f14edee1d7` | `8106752eb410a6c2f66ff03c3fa983123760058d` |

[Shared observations](arrival-observation.json) contain the later ref/PR inventory. [The checkpoint plan](arrival-reconciliation-plan.json) records all three-way blob and mode classifications before source integration. [The integration receipt](arrival-integration.json) records every incoming disposition and all preserved evidence variants.

## Source resolution

The reviewed writer remains exactly `abae52f0d08b0cbe66c5c86c97f0f28e36de60aa`. Incoming office/GECToR comment code differs only by the already retained note guard and relocation of an otherwise identical comment registry. Morphology independently added the same executable guard; its explanatory comment and registry placement differ. The integration keeps the guard once.

The incoming 39-line same-paragraph before/after-comment regression is preserved verbatim alongside the two existing footnote/endnote cases and all earlier tests. Removing the incoming addition reproduces the current test exactly; removing the prior continuation additions reproduces the incoming test exactly. The resulting test blob is `fab22f0897d49e528ead09cdaed1f5f2b701c547`.

Eleven unique incoming documentation/evidence files are copied at their exact blob/mode identities. Six differing evidence variants are archived verbatim under [arrivals](arrivals), with source URLs, commits, original paths and destination paths in the integration receipt. Original relative links inside archived Markdown are intentionally retained; the provenance URLs resolve each original file at its source commit.

## Validation scope

This work compares full source content and untruncated Git trees and verifies remote readbacks. It does not execute Dart/Flutter tests, formatting, analysis, or application acceptance, and does not query or await Actions or CI/status endpoints. Incoming runtime archives and receipts retain their original source and author attribution; they do not qualify the combined continuation tree. The initial inventory, reviewed annotation changes, Zotero paths, and prior preservation evidence remain unchanged.
