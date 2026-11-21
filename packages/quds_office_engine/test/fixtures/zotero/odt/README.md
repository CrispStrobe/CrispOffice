# LibreOffice converter input for native ODT import

`native-prose.odt` is the original, unmodified output of **LibreOfficeDev
26.8.0.0.alpha0**, build `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`.
The prior Zotero import milestone produced it by converting the included
`native-prose.docx` with the installed headless converter and an isolated
profile. Both files were recovered byte for byte from that milestone's
`loader-development.zip` evidence archive.

| File | SHA-256 |
| --- | --- |
| `native-prose.odt` | `9fd4e0d23bf9cd2be0248bd5e9cfb496dfe512ec1226c456f324f2171705e1bd` |
| `native-prose.docx` | `2572f8964c08b4f9bf9087ed0a8e68c54d4b9899797c37d30bd42c7800c37d74` |

The input is Quds-authored synthetic prose: two paragraphs containing bold,
italic, Arabic text and supplementary Unicode. The ODT retains the converter's
complete style XML, including unused styles and active defaults. In particular,
the native complex-script default is **10 pt**, while the Latin runs are
**11 pt**. The original file contains no Zotero fields, macros or external links.

Producer attribution belongs to The Document Foundation's LibreOffice project.
No LibreOffice executable or third-party implementation is distributed here.
The fixture text was authored for this repository; its conversion provenance
does not establish installed Zotero-plugin interoperability.

The [original converter receipt][receipt] records the exact command, producer,
input/output and XML hashes, and the previous intentional import refusal.
The [earlier milestone record][record] explains that boundary. This fixture has
not been simplified to remove properties that the importer previously refused.

`odt_libreoffice_fixture_test.dart` verifies the whole-file digest and imports
the untouched ODT before asserting repeated DOCX reopen behavior. Its paired
Zotero scenario is **explicitly synthetic**: the test injects canonical native
reference marks, a bibliography section and preference properties into copies
of this fixture. It preserves `styles.xml` and the complete `content.xml` prefix
before `office:body` byte for byte. The test then edits a citation, performs a
staged HTTP callback refresh, and checks field ownership and metadata across
DOCX saves. These injected fields were not emitted by an installed Zotero plugin.

The same test file mutates separate in-memory copies to activate CJK typography,
the native default tab grid, a page grid and footnote separator. Those controls
must refuse when their layout semantics are not represented. Neither the source
fixtures nor their styles are modified by the test run. The synthetic footnote
control changes only that copy's zero-based footnote counter to the currently
supported one-based value so the test reaches the separator-specific refusal.

[receipt]: https://github.com/CrispStrobe/quds_office_suite/blob/01517de8886ef7bd24947894be5dc823d0328869/docs/validation/zotero-rich-odt-20261121/converter-development.json
[record]: https://github.com/CrispStrobe/quds_office_suite/blob/01517de8886ef7bd24947894be5dc823d0328869/docs/validation/zotero-rich-odt-20261121/README.md#actual-libreoffice-converter-boundary
