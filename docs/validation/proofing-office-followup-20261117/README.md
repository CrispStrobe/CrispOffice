# Proofing integration reuse and Office export follow-up

17 November 2026. Runtime freeze:
`2de01b5774b75ddad858fc61bda3b356570cbf38`.

## Retain our work; exclude the problematic backend

The [reuse map](../../roadmaps/proofing-adapter-reuse.md) preserves the user's
clarification. Our manual-provider, review, lifecycle, cancellation, source-safety
and undo work remains reusable. Additional Quds-authored adapter/UI source and
tests remain at the immutable historical feature revision; this follow-up does
not restore AOT/RML/nlp_base, dictionaries, transports or runtime registration.
The native spaCy implementation is assigned to a separate session. Its owner
retains control of the new model contract, analysis types and native ABI.

## Concrete Office repairs

A leading ODT table of contents now passes its pending section to the first
paragraph actually emitted, including cached, generated, titleless and title-only
contents. Empty contents leave activation for the next visible block. The export
preserves page geometry and odd/even master selection without a trailing blank
anchor or changes to the source model. Eleven focused section regressions were
committed before the repair; nine failed on the original implementation.

The broad regression run exposed 21 pre-existing integration failures. The
bounded inline-field implementation authored at `898c4c07` had been displaced
while its stronger regression suite remained. It is now restored and adapted to
the newer column-break emitter. Complete, simple PAGE/NUMPAGES packets preserve
their cached display, style and hyperlink; malformed, locked, nested,
unsupported and multi-run fields retain their visible content. Independent
stories own their field depth. No cached run is silently suppressed.

Bookmark ends do not choose between competing active starts, and malformed IDs
do not abort export. An old test assumed all TOCs were unexported; its fixture
now explicitly suppresses its title to test that same omitted-content case.
A separate new test verifies visible TOC-title bookmark ranges. A new field test
checks that cache fallback retains an authored inline column break.

## Incoming source preserved

The Quds baseline includes main through `d790bca4`, including the newer ODF story,
header-media/bookmark and first/even header/footer work. The host baseline is
`73ebbfe6`, including its production ODF visibility, cell-story and cell-limit
workflows. The host's chart-to-table fallback was brought into canonical Quds,
with the incoming column-schema/tab-cache regression files. The stronger
canonical hyphen/underscore leader distinction is retained.

The host manifest named `f87533cd`, but three recorded files differed from that
revision. Every current recorded hash was verified; all three differences were
reviewed. The chart behavior is preserved, duplicate smoke assertions are not
needed, and the stronger tab regression is kept. New previously unmanaged host
regressions were admitted only when byte-identical to the canonical candidate.
The guarded reconciliation deletes no files and pins 2,624 files. It preserves
the standalone parser boundary and unrelated host source changes.

## Local results

- 1,558 engine proofing/ODT/ODS/ODP/ODF tests pass after the field/bookmark repair.
- The final incoming chart/column/tab delta passes its 24 scoped tests; these
  overlap the broad suite and must not be summed as additional unique tests.
- 97 editor manual-proofing/session/correction/dialog tests pass.
- 147 native CrispCloud tests pass, including actual export-menu workflows,
  ODF limits and hidden-story handling, annotation privacy, license attribution,
  manual review, correction and undo paths.
- Engine analysis is clean. Nine sync-guard tests, the tracked 2,624-file source
  fidelity gate and crypto/export-policy input checks pass.

## Actual LibreOffice rendering

The retained synthetic ODT was imported and rendered to PDF by installed
LibreOffice **26.8.2.2 AARCH64** on macOS. Independent `pdfinfo` / `pdftotext`
checks verify two pages: first-section text stays on page one, contents starts on
page two, and page two is 600.009 by 399.997 points (within 0.1 point of the
requested 600 by 400). Native fields render as `Page 1 of 2`, while a locked field
retains its authored `23` instead of becoming a live page number. This is a real
external-reader check, not a mock or an assertion against our own serializer.
It is not GUI-click, mobile, or TestFlight qualification.

[The live export fixture](live_export.dart) reproduces the model using the Quds
package configuration. For example, from a resolved repository workspace:

```sh
dart --packages=.dart_tool/package_config.json \
  docs/validation/proofing-office-followup-20261117/live_export.dart \
  /path/to/new-output.odt
soffice -env:UserInstallation=file:///path/to/separate-profile \
  --headless --convert-to pdf --outdir /path/to/output /path/to/new-output.odt
pdfinfo -f 1 -l 2 -box /path/to/output/new-output.pdf
pdftotext -layout /path/to/output/new-output.pdf -
```

The [evidence index](evidence/index.json) binds synthetic artifacts, source
snapshots, commands, initial failures, final logs, reconciliation and rendering
receipts. Original failures are retained and are not counted as passing checks.
No model, Python environment, AOT runtime, third-party dictionary or native
library is added. No CI status/Actions endpoint was queried or awaited.
