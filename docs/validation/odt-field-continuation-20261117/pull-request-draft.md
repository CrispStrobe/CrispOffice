# Preserve cached page fields through DOCX import and ODT export

## Why

Paragraph PAGE conversion could discard an authored Roman numeral or padded
page number when its instruction used an unsupported formatting switch. DOCX
import could also collapse locked or malformed field packets and erase numeric
caches before the ODT writer's existing conservative checks saw them.

## Changes

- Use the bounded PAGE/NUMPAGES instruction parser for ODT paragraph PAGE
  detection. Explicit unsupported instructions keep their visible cached runs,
  including when the compatibility page-number flag is set.
- Validate packet ordering and boundary metadata before the importer collapses
  a paragraph field. Preserve locks, unsupported metadata, malformed packets and
  unsupported PAGE switches before numeric-cache suppression.
- Add direct DOCX-to-ODT cache-preservation regressions and extend paragraph
  tests for unsupported formatting, styled header/footer caches and supported
  live PAGE controls.
- Refresh the ODF capability guide and pin the obsolete historical AOT README
  link without restoring the removed package.

## Validation

Qualified product source: `5afff4b86523250c93d949eb6c010e49d9fabd82`, based on
`e3a38789359adaa33b2da1345c952fa1c2d8aebb`.

The approved source and tests were recovered after the execution workspace was
reset between preparation and permission to push. Their content hashes match
the previously reviewed files. The previous unpublished raw logs were lost;
this publication records fresh local verification rather than reconstructing
those logs.

- Final regression files reproduce **24 failures** on the
  unchanged baseline. The same files pass after repair.
- The fresh VM run includes all **78 focused field tests**: 34 paragraph,
  21 imported-field and 23 inline-field cases.
- **620 affected tests pass on Dart VM**.
- **165 portable tests pass on Node**.
- Strict analysis: **No issues**.

The cohorts overlap; these counts are not additive. Full receipts, recovery
bindings and scope limits are in the
[continuation report](https://github.com/CrispStrobe/quds_office_suite/blob/codex/odt-field-continuation-20261117/docs/validation/odt-field-continuation-20261117/README.md).

## Scope

Supported simple PAGE fields remain live; unsupported field forms retain their
authored visible caches. Paragraph-level NUMPAGES support and general editable
Word field conversion are not added. The malformed-packet tests do not claim
that a second DOCX import preserves every malformed structure. Proofing,
GECToR, Harper, editor and Studio code are unchanged, and AOT/RML remains
removed. No new language-quality or external-reader rendering claim is made.
