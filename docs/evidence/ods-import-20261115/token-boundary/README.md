# ODS formula token-boundary correction

Local saved source: `24804dc92dcadd81ec574fa3c38d38e8216cf6c1`.
Tree: `f56b2fbcf1961101de36472906f2c92a6f820735`.
Parent: `a83b2464ea081f70a69aaf3dfa746c269f9f993c`.

Only the ODS reader and its tests changed. The reader now applies the original
ASCII word-boundary rule before removing the supported COM.MICROSOFT. and
ORG.OPENOFFICE. function prefixes. Embedded namespace text inside an unknown
or custom identifier remains unchanged. Quoted literal and sheet-reference
handling is retained; recognized function prefixes still translate normally.

The two new prefix-specific tests each exercise seven forms and verify both
imported and reopened XLSX formulas and cached values. Forms include a custom
identifier that would otherwise become the recognized SUM function, letter and
underscore boundaries, recognized prefixes after delimiters, string literals
and quoted sheet references.

## Regression and acceptance evidence

Both new boundary tests failed against the unchanged parent reader:
`XCOM.MICROSOFT.SUM(1;2)` and `XORG.OPENOFFICE.SUM(1;2)` each became `XSUM(1,2)`.
The raw failures, source/test hashes, and exact baseline regression-test file
are retained. The candidate adds one additional SUM-collision case after that
baseline run; the retained baseline test hash matches its receipt exactly.

Fresh qualification on the clean saved candidate passed:

- ODS reader: **29/29**.
- Existing legacy spreadsheet reader: **6/6**.
- Existing spreadsheet wrap fidelity: **7/7**.
- Total: **42/42**, no failures, errors or skips.
- Focused strict analysis of the reader, test and PDF export source:
  **no issues**.
- Both source-bound recorder gates confirm unchanged before/after source,
  resolution and tool inputs.

The strict machine-event summary records the engine cwd as its reported suite
base. Raw logs remain unchanged. All 52 earlier canonical receipt files remain
intact in their prior locations; this pack is an additional checkpoint.

## Remote source identity

The complete tested tree is saved remotely at `07842b7a116e64c75ed7e0945a6f74a9f4bdfccd`.
`remote-save-receipt.json` verifies tree identity, parent, both changed blobs
and modes, and unchanged prior 52 receipt files. Local tested HEAD is unchanged.
