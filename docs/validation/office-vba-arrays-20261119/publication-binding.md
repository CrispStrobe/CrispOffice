# Publication source and evidence binding

The combined audit passed against published commit **`4b26bfaa81e1f0bef7d63ddd6a28fccc05fa88fd`**, Git tree `505c450c283196d0c8e1a6c09ab5f62eafa7896d`.

It independently verified **2,792 unique repository input paths** against both their current working bytes and the actual blobs in that Git tree. All **287 retained artifact files across eight manifests** also match their SHA-256 records and published Git blobs. The manifests themselves were checked against Git. There were no unresolved source or artifact mismatches.

The complete machine-readable result is [publication-binding.json](publication-binding.json). The reproducible auditor is [publication-binding.py](publication-binding.py). It reads Git objects with `git ls-tree` and `git cat-file --batch`, checks the original input snapshots and artifact manifests, and derives test counts directly from the retained JSON reporter streams.

## Accepted checks and counting

| Accepted cohort | Distinct passing cases | Evidence |
| --- | ---: | --- |
| Macro and native command selection | 614 | `engine-publication/` |
| Focused DrawingML slide/import/text fidelity | 33 | `independent-review/slide-table-color/` |
| Native mail store | 508 | `incoming-mail/` |
| Editor layout and theme selection | 213 | `incoming-layout-theme-accepted/` |
| Studio layout, dialogs, menus, and review selection | 116 | `incoming-layout-theme-accepted/` |
| Repeated Studio mail restore and portability selection | 18 | `incoming-layout-theme-accepted/` |
| **Total** | **1,502** | **Zero failed or skipped cases** |

Counts use unique repository test-file/name pairs. Earlier runs, development retries, and the historical Studio run do not increase the total. The 18 repeated Studio cases are counted once.

The current macro and GUI cohorts ran against frozen source commit `61bb3ee42a385c5ffaffa44047693a6f378a8424`; their source bytes match the publication commit above. The macro run retained 856 unchanged repository inputs and unchanged resolved dependency inputs. It also passed whole-engine `dart analyze --fatal-infos`, formatting, whitespace checks, and all five `-O1` JavaScript compilations followed by separate fresh-Node runs with actual success assertions. Those five programs are additional checks, not additional unit-test cases.

The accepted GUI run retained 2,495 unchanged inputs, including 2,312 repository paths, and passed both strict analysis commands. The focused slide correction passed strict scoped analysis and formatting. Native mail core and store analysis also passed.

Input equality establishes which source was present for these selected checks. It does not imply behavioral coverage of every captured file. This report does not claim that every repository test, native macOS UI behavior, or Microsoft Office interoperability was exercised. GitHub Actions were not queried or used for acceptance.

## Superseded evidence and explicit differences

The earlier successful `engine-final/` macro run remains intact. All 856 original input hashes were verified against its tested commit. Two paths subsequently changed: `drawingml.dart` and `slide_test.dart`. The full `engine-publication/` run qualifies their current versions. The focused evidence retains the two failing regressions against the exact original DrawingML parser and their passing results after a parser-only change.

The earlier successful `incoming-studio/` run also remains intact. Its 2,014 recorded repository source paths were verified against their original Git blobs. Twelve of those paths changed later; each current version is present in the accepted GUI snapshot, with the engine changes also covered by the current macro cohort. All 18 historical Studio cases passed again.

Both failed GUI attempts remain at their original paths. The initial attempt had eight editor fixture failures. The expanded attempt had one dark-slide pixel assertion failure and a strict-analysis failure for missing braces. The auditor requires every formerly failing editor case and every formerly failing command to pass in `incoming-layout-theme-accepted/`; all passed.

The native mail package binding records 87 files. Of these, 85 remain byte-identical to the tested frontier. The only later package changes are `packages/quds_mail_store/README.md` and `CHANGELOG.md`, which document the existing restore API, provenance behavior, scope, and qualification links. The report records both old and current hashes and labels these two paths as documentation review, not newly tested runtime code. No mail implementation, test, tool, or dependency change is hidden by this exception.

Across the current accepted cohorts, 466 repository paths occur in more than one evidence set. Every shared hash agrees. Historical differences are recorded explicitly rather than substituted into the original receipts.

## Reproduce the binding

From the repository root, with the retained evidence available:

```sh
python3 docs/validation/office-vba-arrays-20261119/publication-binding.py \
  --repo . \
  --head 4b26bfaa81e1f0bef7d63ddd6a28fccc05fa88fd \
  --gui-evidence docs/validation/office-vba-arrays-20261119/incoming-layout-theme-accepted \
  --output /tmp/quds-publication-binding.json
```

This reruns the evidence/source audit, not the test suites. It fails on a changed accepted source, an artifact hash mismatch, a failed accepted command, or an unrequalified earlier failure. Later source changes require a new binding and appropriate qualification; an evidence-only publication does not change the tested source bytes.
