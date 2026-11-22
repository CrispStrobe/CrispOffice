# Final engine qualification after main ab integration

Qualified on 2026-11-22T13:44:55.071307+00:00 with the unmodified pinned Flutter 3.47.8 / Dart 3.13.7 runtime and Node 24.22.3. No GitHub Actions were queried or awaited.

## Executed gates

| Cohort | Suites | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Word/VBA selectors, string intrinsics, Split, language and document regressions | 20 | 1,831 | 0 | 0 |
| Zotero/ODT, table borders/direction/padding/merges, revision, field and style regressions | 45 | 1,068 | 0 | 0 |
| **Substantive VM total** | **65** | **2,899** | **0** | **0** |

Both ordinary `dart test --reporter=json --concurrency=2` runs completed their complete reporter lifecycles. Counts exclude hidden loading/setup/teardown events. Every started test completed, every expected suite was observed, and no errors, skips, duplicate events or malformed records were accepted. The parser splits only LF bytes, preserving U+0085/U+2028/U+2029 inside JSON strings. The separate reporter-framing self-check contributes no product-test cases.

Pinned read-only `dart format --output=none --set-exit-if-changed` passed all 39 changed engine Dart paths before tests started. Strict `dart analyze --fatal-infos` subsequently passed the same 39 paths. All ten planned commands exited zero. The two new border suites and eleven additional table/ODT regression neighbors join the prior 52-suite scope; paths and exact commands are in `plan.json`.

## Source binding

Execution began from published checkpoint `800c3dfd56b169831222d53a02e2b7b83f4f1857`, tree `7c2a4a5a898c4c0ca8c1075e85c22e2b1468767f`. During execution root published Mail host changes as `8bbe6bcb9d22681a765e85c8fc4a80859221b042`, tree `629881455d2e077eca73fea410b181321105445c`. Those repository trees differ. Their captured engine/transitive/config inputs are identical, and every captured file remained unchanged before, after and at the later checkpoint. Engine lib/test/tool bytes also match incoming main `ab3457c98b6d9a0d1da8147db3048dfc50d174d3`.

The 1,421 captured inputs cover full engine and legacy-parser libraries; engine tests, helpers, fixtures, tools and macros; both package manifests and analysis configs; the root workspace manifest, lockfile, SDK pin and analysis config; and generated package configuration. The unchanged locked external package cache comes from the recorded verified-archive runtime setup. Mail host/editor source and tests are excluded and are not qualified by this engine run. See `scope-audit.json` and `source-binding.json`.

Before/after/current input-manifest SHA-256: `7efde2fa97ad094c16cc8f76df6ad9cdd4670133992cdcedeed9ee5dd4e7543f`.

All 2,899 counted cases executed on these exact engine inputs. No formatting normalization bridge is needed for this gate. Prior 2,594-case receipts and their earlier normalization proof are preserved as superseded evidence and add no current-source case credit.

## Portability

The Split corpus passed on the VM and compiled JavaScript under Node: 174 adapter cases across Word, Excel and PowerPoint. Its canonical receipt matched byte-for-byte.

The checked-in Word Split BAS passed for DOCX and DOCM on both runtimes, including its native, transaction, recording/replay, MCP, reopen and opaque-content assertions. Complete JSON values match after normalizing finite integral numeric encodings. Ordinary `jsonEncode` may emit a VM value as `0.0` and its JavaScript equivalent as `0`; raw byte identity is not claimed for that receipt. Strings, booleans, arrays, object values and numeric values remain compared. Raw and canonical outputs are retained. Portability executions are separate from the VM test total.

## Preserved and integrated behavior

The qualified union retains raw field-boundary revision history, the five marker/mixed-run regressions, all nine instruction-side style cases and full independent Refresh golden assertions. It adds bounded editable ODT table-border preservation and Word logical/physical side mapping, with direct regression coverage for styles, table direction, padding, merged owners, ordinary reader/writer behavior and Zotero geometry. Converter fixture bytes are unchanged. External converter/installed-plugin acceptance was not rerun by this engine gate; incoming external evidence remains separately source-bound.
