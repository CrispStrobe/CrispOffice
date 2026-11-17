# Office consumer recovery after the workspace reset

Status: source corrections recovered remotely; final consumer and test qualification remains open.

The execution environment first returned ENOSPC while starting the first test after the nonleading-frame correction, then rejected process creation. A successful call from `/` showed that the earlier workspace and retained runtime directory were absent after the environment reset. The pending source and tests had already been reconstructed from executed edit commands, uploaded through the GitHub connector, and read back exactly.

## What is preserved

- The parent-managed remote checkpoint preceding these consumer corrections, including the earlier Office source and archived 693-case run. The later 694-case run was observed to pass, but its raw addendum is not known to have been preserved remotely; it must not be described as a durable archived pass.
- The corrected writer as an exact replay of the six executed edits onto the verified `50b5569a` writer. Both local writer-format commands had reported zero changes.
- The four header-order regression cases and the nonleading-frame regression as their exact submitted pre-format test source. Formatting changed their local presentation before the reset; post-format bytes were not available for readback. The recovered tests retain the submitted logic and should be formatted again.
- `emergency-recovery.json` records the base and resulting blob identities, exact writer replacements, known preliminary observations, consumer/schema identities, limitations and remaining commands.

Recovered Git blobs:

| Path | Blob |
| --- | --- |
| `packages/quds_office_engine/lib/src/word/serial/odt_document_writer.dart` | `2d53d45d564e8eeaef66fc03cc2b0820efe752da` |
| `packages/quds_office_engine/test/odt_header_variant_order_test.dart` | `0a44c34570039c775500615bcd5a3c71bc8ac7af` |
| `packages/quds_office_engine/test/odt_section_fidelity_test.dart` | `35000d56868465c48413c6afb2e8b0767e637d3d` |
| `emergency-recovery.json` | `95aa3a4c4ebe48685e685660d2c116f8e4120960` |

These four blobs were fetched back and compared with their reconstructed content. The parent owns branch and commit updates.

## What was not recovered

The raw 694-case addendum is not known to have been preserved remotely. The newly generated five-fixture consumer run was not yet archived remotely. Its original ODT/PDF/DOCX files, extracted XML and PDF coordinates, full consumer commands, source seals, original before-repair snapshots, four frame A/B packages, and newly generated raw header/frame test streams were in the lost workspace.

The emergency note preserves observations already returned by tools. It is not a substitute for those raw artifacts. New runs must have their own source identities, timestamps and evidence; they must not be labeled as the lost run.

## Observed results before the reset

The earlier writer generated five representative ODTs. The preliminary consumer summary reported four of five semantic checks passing and nineteen of twenty XML parts accepted by Jing. All five converted in the installed LibreOffice build. These are preliminary observations, not final acceptance of the corrected writer.

The header-variant fixture rendered the expected first/even/default header/footer text across three pages, but its styles.xml violated the ODF 1.3 ordered master-page grammar. All four added structural cases failed before the ordering correction; the new/header/document-writer focused suites then reported 31 passing cases.

The bookmark fixture retained the frame and its paired bookmark in source XML, but LibreOffice omitted that later frame from both PDF and reopened DOCX. Scratch A/B conversions returned:

| Variant | Frame text visible |
| --- | --- |
| Repacked control | No |
| Height changed from 35 to 80 pt | No |
| Explicit page number added | No |
| Existing page-relative paragraph-anchor representation | Yes |

The corresponding frame regression failed before the correction. After extending the existing section-leading frame anchor to later frames, formatting passed, but the first test attempt failed creating its temporary directory because the filesystem was full. No post-frame test, schema or consumer pass was obtained.

The native-field fixture's actual PDF values for PAGE, NUMPAGES, DATE, TIME and TITLE were observed in LiberationSans-Bold and color #123456. Source caches and links were preserved and the reopened DOCX contained native field instructions and hyperlinks. LibreOffice refreshes field values; its DOCX export placed the source formatting on field-begin runs while result runs carried defaults. This does not establish complete DOCX-round-trip formatting fidelity.

## Required completion

1. Materialize and format the recovered source and tests in the restored checkout.
2. Re-run the targeted header/frame regressions and strict analysis.
3. Re-run the previous bounded Office selection plus the five added cases, with source/test hashes before and after. The expected selection is 50 files and 699 cases; these numbers are expectations, not completed results.
4. Reconstruct the same five bounded final-writer fixtures with a newly identified harness: native fields including linked/styled NUMPAGES and source caches; malformed-field fallback; three-page first/even headers; body/table/header/frame/TOC bookmark ranges; and an empty native PAGE preceding a hard column break.
5. Validate each generated package's content.xml, styles.xml, meta.xml and manifest using the pinned OASIS schema and Jing, then run the installed LibreOffice consumer and verify the semantic/PDF checks. Preserve source, schema and consumer identities and limits.
6. Archive and readback-verify the new complete evidence before the parent commits and pushes it.

No GitHub Actions waits or polling are required. Native performance timing must remain separate from active consumer/test jobs.
