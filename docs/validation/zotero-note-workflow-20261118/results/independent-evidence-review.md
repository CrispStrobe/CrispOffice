# Independent final evidence audit

**Result: passed; no count, overlap or source-binding discrepancy found.**

This read-only audit checked the evidence in `qualification/artifact` against the frozen application commit `ff1518517dd9f67e214ff56fe7eef06349f5223a` (tree `9a2014756626b256509df78d5ca0efedcd3c967a`). Later documentation-only commits do not change this binding. No tests, remote fetches or GitHub Actions queries were run for the audit.

## Test counts

| Gate | Disjoint test files | Passed cases verified |
|---|---:|---:|
| Engine Zotero/notes | 29 | 549 |
| Editor | 52 | 737 |
| Studio | 7 | 107 |
| spaCy providers | 6 | 67 |
| Thesaurus provider | 1 | 24 |
| Python thesaurus compiler | 1 | 5 |
| **Total** | **96** | **1,489** |

The compressed raw JSON streams contain exactly 1,393 visible passing cases, with unique `(file, test name)` identities. Every started event has a completion, identifiers are unique within each gate, and the streams contain no skipped cases, error events or visible failures. Each stream ends successfully. Actual suite paths equal both the planned and invoked file sets. All six gate file sets are disjoint.

Provider logs independently confirm 67, 24 and 5 passing cases, successful exits, and the SHA-256 values recorded in the provider summary. The spaCy expanded concurrent reporter repeats some currently active test labels as progress advances; its terminal total confirms the count, while it does not enumerate every individual case name as the main JSON streams do.

The four new Zotero files contribute **41 + 33 + 13 + 11 = 98** cases. They occur once in their relevant gate and are already included in 1,489. Historical/development runs and pack-integrity files are not added to the test count. These results match `qualification.json`, both gate summaries, and the README table.

## Source and runtime binding

The main manifest contains **1,432** paths and the provider manifest **1,613**. They share **573** paths, giving **2,472 distinct files**. Every recorded hash in that union matches the corresponding Git blob at the frozen application commit; no shared path has conflicting hashes. The two manifest totals are correctly presented separately in the report.

Main source/runtime snapshots are identical before and after the main gates. Provider source snapshots and provider runtime snapshots are likewise unchanged. The archived dependency lock matches the main snapshot. The frozen commit and tree agree across the qualification and source evidence.

The pack report separately verifies **518 English + 519 German = 1,037 files**. These integrity checks do not increase the 1,489 test total.

## Claim boundaries

The evidence establishes targeted local models, controllers, widgets and controlled protocol/provider fixtures at the recorded source. It does not establish live Zotero/account interoperability, a newly installed full application build, external language-model inference, or real Word/LibreOffice reopening. The report retains these limitations.

Machine-readable details are in `final-evidence-count-review.json`.
