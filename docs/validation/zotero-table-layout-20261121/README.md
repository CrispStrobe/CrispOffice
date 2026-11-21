# Zotero research-table margins and native ODT padding

This increment aligns native table layout with the uniform `cellMargin` already
stored in the Word model and DOCX. It extends editable Zotero ODT import/export
to preserve the same bounded padding, including nested and merged table owners.

## Remote intake

Work started from `aa861c28e336b17bcd4c259351164380cd6b1438`. All fork branches,
pull-request heads and upstream branches/PR heads were fetched before new code.
The outstanding Zotero continuations `c0ae75c226b13ae1ec4ab31238004d558ad01531`
and `a7f69313ed2e610f82242c31be8ad5387ae5cea0` were integrated, preserving both
sets of cache regressions and the separately attributed qualification records.
Their README conflict was resolved by retaining both records.

The combined tree was saved remotely as
`57c5729ab1aa1ea8c1e27a4c76b233060b843e11`. `intake-initial.json` captures the
exact ref snapshot; `verify_intake.py` rechecks ancestry and independently proves
the fourteen historical equivalents using exact Git trees or changed-path
mode/type/blob equality. Historical test counts retain their original source
attribution and are not fresh acceptance of this increment.

## Implementation contract

- Native measurement, text wrapping, row height, pagination and ruler fallback
  use each table's actual uniform margin. The existing model default remains
  4 pt; the old fixed 4.25 pt rendering inset is corrected.
- Nested tables retain independent margins. Picture height limits account for
  the sum of ancestor margins, including temporary tall-row engines and notes.
- Explicit editable Zotero ODT writes `fo:padding` on cell styles. The ordinary
  cached-result ODT path retains its existing formatting contract.
- Native ODT import resolves family defaults and named parent chains. A layer's
  shorthand resets its four sides; that layer's side attributes then override
  it. Only equal effective sides and a uniform margin across visible owners of
  one table are represented. Nested tables resolve separately.
- Covered-cell authored padding must agree with its merged owner. Positive
  borders, asymmetric or per-cell margins, unsupported row/column defaults,
  invalid lengths, exhausted cell widths and margins beyond native DOCX storage
  remain explicit refusals. LibreOffice's `border="none"` declarations are inert
  and accepted.

## Qualification

Fresh local and external-converter results are recorded by the completion
checkpoint. GitHub Actions are not the acceptance path and are neither queried
nor awaited. Installed Zotero-plugin sessions, Microsoft Word application
acceptance, supported-release LibreOffice testing and legacy Apache OpenOffice
compatibility remain separate from deterministic tests and the available
LibreOffice development-build file converter.

Active footnote separator geometry remains the next dedicated note-formatting
increment. It needs model, pagination, rendering and DOCX/ODT conversion work;
admitting its XML alone would not preserve the document faithfully.

## Primary format references

- [ODF 1.3 Part 3](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html),
  table styles, covered cells and padding attributes.
- [XSL 1.0 section 5.2](https://www.w3.org/TR/2001/REC-xsl-20011015/slice5.html#refine-shorthand),
  shorthand expansion and explicit-property precedence.
