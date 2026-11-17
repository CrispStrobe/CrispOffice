# PDF text-string decoding

PDF metadata and marked-content replacement text use a shared decoder in
`packages/quds_office_engine/lib/src/pdf/file/text/pdf_text_string.dart`.
`PdfCosString.asText` and inline `ActualText` both delegate to this decoder, so
the same bytes have the same meaning in a document title, an inline property
dictionary, and a named indirect property dictionary.

## Encoding selection

The decoder selects an encoding from a complete leading byte-order marker:

| Leading bytes | Interpretation |
| --- | --- |
| `FE FF` | UTF-16 big endian; consume the initial marker |
| `EF BB BF` | PDF 2.0 UTF-8; consume the initial marker |
| Anything else, including incomplete markers | PDFDocEncoding |

PDFDocEncoding includes eight accent characters at `18`–`1F`, the punctuation,
ligature and letter mappings at `80`–`9E`, and the euro sign at `A0`. These values
are not interchangeable with Latin-1 or WinAnsi. The mappings follow
[ISO 32000-1:2008, clause 7.9.2.2 and Annex D, Table D.2](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf).
The [PDF Association's ISO 32000-2 errata](https://pdf-issues.pdfa.org/32000-2-2020/clauseAnnexD.html)
also clarify that `8A` represents the minus sign, U+2212.

UTF-8 with its required leading marker is defined by PDF 2.0; see the
[PDF Association's description and examples](https://pdfa.org/understanding-utf-8-in-pdf-2-0/)
and [the ISO 32000-2 syntax errata](https://pdf-issues.pdfa.org/32000-2-2020/clause07.html).
Selection is local to each string. This reader accepts a recognized marker
without enforcing the file version; it does not change the writer's output
version or claim support for all PDF 2.0 features.

## Compatibility and malformed input

The implementation uses an explicit recovery policy:

- Unassigned PDFDocEncoding positions `7F`, `9F` and `AD` produce U+FFFD.
- C0 bytes `00`–`17` retain their previous code points, including NUL and the
  controls that Annex D marks undefined. This is a compatibility decision.
- A valid UTF-16 surrogate pair produces its supplementary Unicode scalar.
  Each unpaired surrogate and an odd final byte produce U+FFFD. A following
  valid character or surrogate pair is retained.
- Malformed UTF-8 uses Dart's replacement decoding. A second or embedded BOM
  and Unicode NUL remain content.
- UTF-16 little endian and UTF-8 without a marker are not inferred.

The decoder preserves the source byte buffer. It does not normalize text or
interpret Unicode language escape sequences. Literal-string escaping and
hexadecimal parsing remain the responsibility of the existing PDF parsers.

## Rendering boundary and tests

Strings shown by `Tj` and `TJ` are font character codes; they continue through
the existing font, encoding and ToUnicode path. Decoding `ActualText` changes
replacement text used for extraction and search, while ordinary marked-content
painting and selection geometry continue to use the displayed glyphs.

`pdf_text_string_encoding_test.dart` checks every PDFDocEncoding byte position,
Unicode markers and supplementary characters, malformed sequences, mixed
encodings in one page, and literal/hexadecimal strings in inline and named
indirect properties. It also compares the drawing operations and selection
bounds with a control PDF. These checks establish decoding and drawing-command
invariance; they do not establish new font coverage or external renderer parity.
