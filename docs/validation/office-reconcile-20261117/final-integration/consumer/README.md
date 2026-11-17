# Final independent ODT consumer qualification

Qualified canonical source: `6a32a919325d71c121c63e3879cfd1b28d64312e`.
Source tree: `a2f4cb57a6a99a0506546419cc904bf873b32bca`.

The final fresh run passed **33 of 33 fixtures**, including **132 of 132 XML parts** against the archived official OASIS ODF 1.3 schemas. Each fixture was exported by the canonical writer, opened by the recorded LibreOffice build, converted to PDF and DOCX, and checked with independent PDF text/geometry and reopened DOCX assertions. The previous 31 fixture specifications and their existing checkers are retained unchanged.

| Exact source | Consumer fixtures | ODF schema parts | Role |
| --- | ---: | ---: | --- |
| `48b6998bb47ffdf43e95025229dc5a5eab09ee9a` | 31 pass, 2 intended failures | 132 pass | Negative control for imported inline column breaks |
| `6a32a919325d71c121c63e3879cfd1b28d64312e` | 33 pass, 0 failures | 132 pass | Final accepted source |

These runs have different source attribution; their counts are not added together. All 401 source/harness inputs, 10,420 runtime inputs, source HEAD, and fixture inventory remained unchanged during each run. The packaging step independently rechecked both input maps and all 415 recorded output hashes per run.

## Raw DOCX controls

The two new fixtures begin as independently authored DOCX ZIPs, retained as `.source.docx` files. `WordDeserializer` imports each document. The generator requires exactly one run-child `WmlBreak.column` and no paragraph `columnBreakBefore` flags, so the tests exercise the original imported representation.

- **Leading inline break:** text before the break stays at the left-column origin, 36 pt; the destination and following paragraph start at the right-column origin, 212 pt. The negative source placed the destination at 36.1 pt.
- **Midparagraph inline break:** the bold first fragment retains the 12 pt first-line indent, starting at 48 pt; the italic continuation and following paragraph start at 212 pt. The negative source concatenated the fragments in the first column. Reopened DOCX assertions verify bold and italic formatting.

The PDF horizontal tolerance is 0.4 pt. The right-column origin is derived independently from a 400 pt page, 36 pt margins, two equal columns, and a 24 pt gap. Both fixtures verify the follower occurs below the destination; the leading fixture also verifies keep-together isolation. The exact vertical before/after margins and exhaustive multiline keep-together pagination are outside these checks.

The final raster images were also inspected directly. Their text is legible and unclipped, the expected column placement is visible, and the midparagraph bold/italic styles are preserved. See `visual-review.json` and the two PNG previews.

## Runtime and limits

The receipt records Dart 3.13.7, LibreOfficeDev `26.8.0.0.alpha0` at `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`, `pdftotext` 25.03.0, and `pdfinfo`/`pdftoppm` 26.05.0. These are local consumer checks on that pinned runtime. They do not establish live Microsoft Word or Zotero interoperability, every LibreOffice release, or complete manual application acceptance.

The scope retains sections, lists, paragraph decorations, styled footer PAGE fields, tabs, growing table rows, invalid table-property fallback, native section columns, and keep-together cache isolation. The separately archived 23 generic-field controls and their 92 schema checks are not counted as these 33 consumer fixtures.

## Evidence and reproduction

`consumer-evidence.tar.xz` contains the exact runner and original runner source, schemas, negative and accepted receipts, before/after input maps, original fixtures, conversion logs, reopened documents, PDF text/geometry, and raster outputs. Transient LibreOffice profiles, temporary directories, and Python caches are excluded. `consumer-evidence-index.json` records every member's size and SHA-256; every archived byte was read back and verified. The independent harness review records the unchanged prior scope and the actual negative failures, while the accepted receipt supplies final positive attribution.

Extract the archive into a working evidence directory. Prepare an immutable checkout at the exact source commit and a separate dependency-resolved workspace of that source using the final canonical qualification instructions. From the extracted directory, run:

```sh
python wave3-runner/verify_consumers.py \
  --output /absolute/path/to/new-consumer-run \
  --schemas "$PWD/schemas" \
  --dart /absolute/path/to/flutter/bin/cache/dart-sdk/bin/dart \
  --repo /absolute/path/to/resolved-6a32a919-workspace \
  --source-repo /absolute/path/to/immutable-6a32a919-checkout \
  --expected-head 6a32a919325d71c121c63e3879cfd1b28d64312e
```

Keep `runner-source` beside `wave3-runner`; the verifier authenticates both. The source and runtime maps document the resolved inputs, and the receipt records every command and return code. No GitHub Actions, workflows, check runs, or CI-status endpoints were queried or awaited.
