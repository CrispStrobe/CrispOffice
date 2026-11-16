# Live native Zotero acceptance — 16 November 2026

Two live acceptance scenarios passed against **official Zotero 10.0.8** in an isolated Linux profile and data directory. They used the actual Quds client, citing driver, Word adapter, and Quds Studio native HTTP transport. No account was connected and all three sources were synthetic. The desktop application was closed after the checks.

## Observed results

| Scenario | Native operations and checked result |
| --- | --- |
| Local catalog | Probe; browse three local items; search for Alpha; list the single synthetic collection and its three members; verify persistent local citation URIs and CSL source snapshots. |
| Document refresh | Run the real desktop HTTP citing transaction over three footnote citations and a bibliography; choose the installed Chicago subsequent-ibid style, German (Germany), and footnotes in Zotero's native Document Preferences; verify the source stays unchanged until staged application; save and reopen DOCX. |

The reopened document contains:

1. `Anna Beispiel, Synthetic Native Acceptance Alpha (Acceptance Test Publisher, 2024), 12.`
2. `Ebd.`
3. `Ebd., 34.`

The title in the first citation is italic; the surrounding text and the two repeated-source citations are roman. The bibliography was regenerated and its title remains italic. `results/docx-format-verification.json` records the actual DOCX runs. The native adapter emitted its expected review warning that bibliography hanging indents, paragraph spacing, and tab stops are simplified. The test fixture accepted that known limitation when applying the staged result.

The native preferences returned by Zotero were preserved as XML in DOCX with style ID `http://www.zotero.org/styles/chicago-notes-bibliography-subsequent-ibid`, locale `de-DE`, and footnote placement. The script began with a hand-built preference record; Zotero opened its native preferences dialog, where the style/language/placement were selected. This was therefore an interactive native style-selection and refresh acceptance run, not a claim of unattended processing.

These are two acceptance scenarios, reported separately from the unit/widget test totals. This does not exercise a full compiled Quds or CrispCloud desktop application, the Quds catalog dialog visually, the native citation picker insertion/edit workflow, private libraries, keychain behavior, or opening the exported file in Microsoft Word or LibreOffice.

## Source and runtime identity

`native-setup-receipt.json` records the official binary URL and SHA256, version/build ID, isolated paths and profile preferences, fixture/style hashes, script hashes, output hashes, and Dart/Flutter runtime hashes. The official archive is not committed.

At **05:17:47 UTC**, while the refresh was active, the observed Quds HEAD was `63512fa554a0c8b81e1f8984ef171cf8bf275631`. Eight native integration source files were hashed at that time: the Zotero client/models/citing driver, Word Zotero model/preferences/citing adapter, and Studio transport/native IO implementation. Every captured hash matches saved commit `35829317dc6d946244c96b2bf179f349853f1939` byte for byte. The only production file changed between those commits was `word_layout.dart`; `git diff --ignore-space-at-eol --numstat` reports no change for that file.

Dart **3.13.7**, supplied by official Flutter **3.47.8**, executed the scripts from source using the genuine locked Studio harness. No persisted compiled kernel or complete compile-input fingerprint was captured. The eight source hashes and commit comparison establish the measured integration scope; they are not an assertion of exact final application-kernel identity. The recorded Studio manifest, lockfile, and package configuration are in `runtime/`; their paths retain the original environment. The toolchain reconstruction is documented in the parent directory's `setup/` evidence.

## Reproduction

The files in `scripts/` are the exact executed originals, including their recorded paths. `prepare-replay.py` rebases copies into a fresh `zotero-native-acceptance` sibling directory under a workspace containing the Quds checkout as `quds_office_suite` and the reconstructed toolchain as `zotero-toolchain`. It fails if that acceptance directory already exists, protecting the recorded run.

```sh
python3 prepare-replay.py --workspace /path/to/workspace
```

Download and verify the official Linux archive using the URL and SHA256 in `native-setup-receipt.json`; extract it so the launcher resolves `zotero-native-acceptance/binary/Zotero_linux-x86_64/zotero`. Download the pinned CSL file into the acceptance directory from:

`https://raw.githubusercontent.com/citation-style-language/styles/d16ba6427ca3c5dada6578a6f7a0f98bd3ea03b3/chicago-notes-bibliography-subsequent-ibid.csl`

Its SHA256 is `39c868e65da74bff51f5be6cbaefc39f809841ab81758a378b883ef767eb500a`. The CSL style is maintained by the Citation Style Language project and licensed under CC BY-SA 3.0, as declared in the source.

Run `bash launch-isolated.sh` in a native Linux desktop terminal. The launcher supplies both `-profile` and `-datadir` explicitly and requests import of `synthetic-sources.bib`. Accept that synthetic import. Install the pinned CSL with Zotero Settings → Cite → Add from File. Do not connect an account.

Run `bash probe-native.sh`, `bash run-catalog-live.sh`, and `bash run-refresh-live.sh` in another native terminal from the acceptance directory. When Document Preferences appears, select Chicago Manual of Style 18th edition (notes and bibliography, subsequent ibid.), Deutsch (Deutschland), and Footnotes; confirm. The runner has a 90-second per-request bound. A different fresh profile will generate different synthetic item keys and local profile URIs; the catalog script discovers them and the refresh script consumes that result.

The cloud command executor and native desktop used separate loopback namespaces in this workspace. A successful native terminal request was required; a direct executor request could not reach the running desktop's `localhost:23119`. No proxy or remote Zotero service was used. Scripts write results to the shared acceptance directory.

## Evidence files

- `results/` contains readable catalog, refresh, and DOCX-format checks.
- `fixtures/native-before.docx` and `fixtures/native-refreshed.docx` are the actual synthetic pre/post documents, not a reconstructed approximation.
- `raw-logs/refresh-protocol.jsonl.gz` preserves every sent/received native citing command and adapter response. It contains only synthetic fixture data.
- Other raw logs preserve the catalog response/headers, native startup diagnostics, and success output. The earlier catalog setup attempt used the engine graph instead of the Studio graph and failed to resolve `http`; it is retained as setup history, not counted as a product failure.
- `raw-log-integrity.json` records original and compressed SHA256 values. Gzip encoding preserves original bytes, including HTTP CRLF and tool output whitespace.

No GitHub Actions were queried, polled, awaited, or rerun.
