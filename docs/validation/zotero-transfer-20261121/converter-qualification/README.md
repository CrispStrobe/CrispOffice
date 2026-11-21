# Zotero transfer: native converter qualification

The frozen product at `9228cb58e960ed9a6c0e91f2531e539c58689364` passed the
direct DOCX baseline and both independent LibreOffice file-conversion routes.
The converter was **LibreOfficeDev 26.8.0.0.alpha0**, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. All 357 engine/tool/manifest source
inputs were identical before and after the replay.

| Route | Native conversion | Quds import and reopen result |
| --- | --- | --- |
| Quds transfer DOCX | Direct baseline | Five active citations and one bibliography |
| Quds transfer DOCX → ODT → DOCX | Two real LibreOffice conversions | Five active citations and one bibliography |
| Quds transfer ODT → DOCX | One real LibreOffice conversion | Five active citations and one bibliography |

The source fixture exercises touching body citations, a table citation, a
footnote, an endnote, and a multiparagraph bibliography. It includes German,
Arabic, emoji, citation locators and item URIs, unknown metadata, an ordinary
hyperlink, an image, authored note prose, and surrounding formatting. The
acceptance tool checks those values, restores citation and bibliography
formatting through controlled callback responses, writes a new DOCX, and
checks the six active fields after reopening. Footnotes and endnotes are
separate stories; the converter's index 1 for the first note of each kind is
expected.

## Scope

This is evidence of real file conversion and Quds' controlled import/format
callback handling. **No running Zotero client or native Zotero plugin was used
in this replay.** It does not qualify a Microsoft Word plugin session, other
LibreOffice releases, direct native ODT reference-mark ingestion, or every
possible word-processor document structure. The fixture uses synthetic
bibliographic data.

`frozen-replay/receipt.json` is the source-bound result. Its `files` map gives
SHA-256 digests for the exact generated, converted, and restored documents,
source manifests, commands, and raw step output. `commands.json` preserves
the actual argument vectors and exit status. Paths in those receipts record
the execution location; the corresponding artifacts are retained here under
the same relative names. The private LibreOffice profile is omitted because
it is runtime state, not a test input or result.

## Reproduce

Use the repository's locked package dependencies, a compatible Dart runtime,
and an installed LibreOffice executable. The output directory must not
already exist. Point `--dart` at the Dart VM executable directly if other
Flutter tooling shares the SDK directory.

```sh
python docs/validation/zotero-transfer-20261121/converter-qualification/replay.py \
  --repository /path/to/quds_office_suite \
  --dart /path/to/dart-sdk/bin/dart \
  --package-config /path/to/workspace/.dart_tool/package_config.json \
  --soffice /path/to/soffice \
  --output /path/to/new-replay-directory
```

The replay script invokes
`packages/quds_office_engine/tool/zotero/transfer_acceptance.dart`, performs
three native conversions, and verifies the direct baseline and both returned
DOCX files. Every subprocess is bounded to 180 seconds. A failed step exits
without issuing an acceptance receipt.

## Defects exposed during qualification

The retained `pre-fix-diagnostic-artifacts.tar.gz` contains the original
experiments and their SHA-256 manifest. These are diagnostic evidence from
before the final freeze, not additional final acceptance runs.

1. Two adjacent same-target ODT hyperlink elements caused this converter to
   drop the linked tail of the second citation at an Arabic-script boundary.
   The entire text remained visible, but the carrier range was incomplete.
   Direct styling did not resolve the issue. Emitting one continuous
   hyperlink containing the differently styled spans retained both complete
   citation packets. The ODT writer now groups that range while keeping
   distinct links and structural boundaries separate.
2. A DOCX bibliography paragraph referenced the built-in `Bibliography`
   style without a corresponding definition. This converter added a literal
   `X` outside the bibliography hyperlink. Removing the undefined reference
   or defining the style eliminated it; changing the reference to another
   undefined style did not. The built-in style catalog now defines the
   referenced style using the existing selective style emission path,
   preserving imported or authored custom definitions.

Neither failure was handled by discarding metadata, stripping arbitrary
characters, or accepting a partial carrier. The corrected files pass the
same strict import checks in the frozen replay.
