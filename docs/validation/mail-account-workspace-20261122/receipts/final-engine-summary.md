# Final engine qualification after latest-main integration

Qualified on 2026-11-22T13:13:34.279838+00:00 using unmodified pinned Flutter 3.47.8 / Dart 3.13.7 and Node 24.22.3. No GitHub Actions were queried or awaited.

## Accepted gates and counts

| Cohort | Suites | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Word/VBA selectors, string intrinsics, Split, language and document regressions | 20 | 1,831 | 0 | 0 |
| Zotero/ODT, revision, field, run-edit and style regressions | 32 | 763 | 0 | 0 |
| **Substantive VM total counted once** | **52** | **2,594** | **0** | **0** |

The original ordinary `dart test --reporter=json --concurrency=2` runs completed their reporter lifecycles. Hidden loading/setup/teardown events are excluded. Original reporters, case inventories and manifests remain untouched in `../final-b4-engine`. Strict analysis with `dart analyze --fatal-infos` passed the 32 changed engine Dart paths on the same original inputs. The 32-path pinned read-only formatting check then passed on the normalized source.

The combined `qualification.json` links the original VM/analysis runs, the explicit normalization proof, and the seven remaining commands in `remaining-qualification.json`. No VM tests or analyzer runs were repeated for formatting. The earlier format failure and parser-proof setup diagnostics add no test cases.

## Exact source boundary

The original VM/analysis source was local `b63245a4851f4efd79cf85802cb27ee252d140cd`, canonical remote `415265e46c7679531adbe97211d064146a26561a`, tree `55996dbcf8671c6228bae62ec7c23dd67c3cda09`.

The normalized source is local `128a49df722662c904335f6dbbc2e8990a1266db`, canonical remote `7c2f6e744b3489460035bbbb358d46e22e58ce20`, identical tree `fe9761f081cf89038ed69fbcddfbf3de08d1daca`. All 1,415 captured inputs were unchanged during each execution stage. Exactly one test file changed between stages: `packages/quds_office_engine/test/word_zotero_boundary_formatting_test.dart`. Production source, fixtures, dependencies, and every other captured input were byte-identical across the stages.

The pinned formatter folds the `refreshedCitations` map from three lines to one and removes its optional trailing comma. The locked analyzer 13.3.0 parsed both exact inputs with zero diagnostics. Recursive ASTs and AST-rendered source match exactly. The raw token inventories intentionally differ by that single comma; every remaining token and comment matches. Raw token identity is not claimed. The exact before/after files, canonical structures, proof script, and hashes are retained in `normalization-bridge.json` and `ast-normalization.json`.

- Original test SHA-256: `2cc714acf52507067c2fccd465dc07a89dc3d5c85a264e6056ccfd941fbddda1`.
- Normalized test SHA-256: `4c2f3551bfacf153f582a3f31dc654ee2916b53e191cfd5600af6320891108a9`.
- Original before/after manifest SHA-256: `92b0e9e0be6590bd2e66f225f750318c9eaa6ae28dd2abdb42d63872d13f5da8`.
- Normalized before/after manifest SHA-256: `77e16026009f74ec57a1fb64cc6d92fe6b4a6146bed3d0dc0b364a1e1c6ed2aa`.

## Portability

The unchanged Split corpus passed on the VM and compiled JavaScript under Node: 174 adapter cases across Word, Excel and PowerPoint, with byte-identical canonical receipts.

The Word Split BAS passed its internal document, transaction, recording/replay, MCP, reopen and opaque-content checks for DOCX and DOCM on both runtimes. The complete JSON values match after normalizing finite integral numeric encodings. Ordinary `jsonEncode` emits some VM values as `0.0` and JavaScript values as `0`; raw byte identity is not claimed for this receipt. Strings, booleans, arrays, object values and numeric values remain compared. These portability executions are separate from the 2,594 VM test count.

## Integrated engine behavior

The qualified union preserves raw Zotero field-boundary formatting revisions across saves while ordinary text revisions remain reviewable, retains the five marker/mixed-run regressions, and adds all nine incoming instruction-side style exclusion cases. Empty instruction runs remain metadata: refresh and unlink use cached-result or surrounding visible text styles. Converter Refresh uses independent original golden snapshots with only explicit citation cache replacements; all structural and formatting assertions remain. Original converter fixture bytes are unchanged.
