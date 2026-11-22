# Final integrated engine qualification

Qualified on 2026-11-22T12:35:38.271295+00:00 with the pinned Flutter 3.47.8 / Dart 3.13.7 runtime and Node 24.22.3. No GitHub Actions were queried or awaited.

The frozen local baseline `e6b5c23e3d0dfee29fb86fe1a5f6132b3f34de3d` and canonical remote checkpoint `3e57fda4de6317c4a547f69220d7ed83802fd19f` share tree `f410d8165bc8af58df6f1154905878ea4b63875b`. Later documentation-only publication can retain these results when source inputs remain byte-identical.

## Executed gates

| Cohort | Suites | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Word/VBA selectors, string intrinsics, Split, direct language and document regressions | 20 | 1,831 | 0 | 0 |
| Zotero/ODT, revision, field, run-edit and style regressions | 32 | 754 | 0 | 0 |
| **Substantive VM total** | **52** | **2,585** | **0** | **0** |

Both ordinary `dart test --reporter=json --concurrency=2` runs completed their reporter lifecycles. Hidden loading/setup/teardown events are excluded. The case inventories list every counted case and suite. Earlier runs and debugging checks are superseded for this total and are not added again.

Strict `dart analyze --fatal-infos` and read-only `dart format --output=none --set-exit-if-changed` passed all 32 changed engine Dart paths, selected from the initial intake main `659b81462224a40f50975cfbfca39f636538b836` to this baseline.

## Portability

The unchanged Split corpus ran on the VM and compiled JavaScript under Node: 174 adapter cases across Word, Excel and PowerPoint. Its canonical receipt matched byte-for-byte.

The checked-in Word Split BAS ran on the VM and under Node for both DOCX and DOCM. Both executions passed their internal native, transaction, recording/replay, MCP, reopen and opaque-content checks. Their complete canonical JSON receipts match after normalizing finite integral numeric encodings. Ordinary `jsonEncode` prints values such as `0.0` on the VM and `0` in JavaScript; raw byte identity is not claimed for this receipt. Strings, booleans, arrays, object values and numeric values remain compared. Raw outputs and both canonical outputs are retained. These portability executions are recorded separately from the VM test total.

## Source invariance and repair history

All 1,415 captured engine/legacy-parser source, test, fixture, tool, macro and manifest inputs matched before and after every gate. The generated package configuration was captured too. Before/after manifest SHA-256: `974370de30188c3b43f3b35346a2c03236f1889a76e359d416b82032134ced01`. All ten commands exited zero; their exact argv, cwd, timestamps and output hashes are in `qualification.json` and the reproducible plan/runner.

The incoming Zotero cohort initially exposed six Refresh snapshot-contract failures and one opaque formatting-history loss. Explicit expected citation-text changes now preserve all original fixture formatting and metadata assertions. Native field markers retain complete raw run properties without synthetic empty text revisions; real empty code-run revisions retain the incoming provenance guard, copying and accept/reject behavior. Both sets of regression cases survived the final main merge, including five additional marker/mixed-run cases. No committed converter fixture bytes were changed. Original failure evidence and repair notes remain in sibling `final-engine` and `zotero-repair` directories.

This qualification executes local engine code and checked-in converter fixtures. Installed Office/LibreOffice/plugin interactions and editor Flutter controller/Studio suites are separate gates. A historical Mail carry-forward audit separately confirms 2,722 cases across 124 suites against unchanged core/store/transport/shared-UI inputs; it creates no new test executions.
