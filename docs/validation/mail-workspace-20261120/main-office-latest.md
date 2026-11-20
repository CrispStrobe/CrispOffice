# Office compatibility after the latest main integration

The next publication refresh found remote `main` at
`d040c15a07f652d01e75363031d0efdee6357bda`, containing published Word/PowerPoint
VBA extensions, native slide text-formatting and replacement APIs, revised PDF
text layout, and typing/proofing integration. That main was preserved and
merged into the Mail branch before further acceptance work.

The reconciled source was saved remotely as
**`1d26181b0161d88abe5977f9848ffd4cd99e6259`**, tree
`c78f112031e101baa294753b6eb003d751b1ed32`. The focused compatibility gate on
that source passed **188 test executions in 13 suites: 147 engine and 41
editor, with zero failures or skips**. Both underlying runners completed
successfully. No GitHub Actions, checks or status endpoints were queried or
awaited.

This is the current gate for the affected Office compatibility surface. The
[earlier 300-case gate](main-office.md) remains a historical receipt for its
original checkpoint. It was not rerun in full, carried forward as an unchanged
300-case total, or added to this count. The same applies to the preceding
137/116-case selections. Mail acceptance is reported separately.

## What the reconciliation preserves

There were three Office conflicts: `office_pdf_export.dart`,
`slide_serial.dart`, and `drawingml.dart`. The incoming main's PDF exporter
was retained byte-for-byte. Its native text model, VBA implementation,
automation operations and proofing APIs were also preserved without replacing
them with older branch implementations.

Across **all engine and editor `lib` files**, only two files differ from this
incoming main:

- `slide_serial.dart` has the default-center assignment for a radial path whose
  focus is omitted, plus its explanatory comment.
- `drawingml.dart` has the corresponding default-center assignment and comment
  for ordinary shapes.

These two small insertions retain the omitted-focus behavior qualified in the
earlier main reconciliation. Explicit off-center focus and unsupported path or
tile geometry still use the bounded fallback. The existing positive
omitted-focus regression remains in the 14-case radial test file.

Every other Office library blob is identical to incoming main, including the
whole-text formatting/replacement flags and imported replacement templates,
shared PDF line-layout path, PDF alpha resources, radial rendering,
installed-font changes, VBA APIs and typing/proofing scheduler. The full
five-line source diff and Git-object proof are retained in
`main-office-latest/incoming-main-product-diff.patch` and
`checkpoint-comparison.json`.

Strict analysis of the three reconciled files, incoming presentation model and
radial regression reports no issues. Formatting the three reconciled files
reported zero changes. No product or test source changed during or after the
accepted run.

## Selected compatibility gate

The repository-pinned Flutter **3.47.8** / Dart **3.13.7** and resolved dependency
lockfile were used. The engine cohort ran first, followed by the editor cohort
with exclusive use of the Flutter runner. The complete run lasted from
**2026-11-20 09:58:38 UTC to 09:59:06 UTC**.

| Package | Test file | Passed |
| --- | --- | ---: |
| Engine | `slide_radial_opacity_test.dart` | 14 |
| Engine | `office_pdf_export_test.dart` | 27 |
| Engine | `slide_import_fidelity_test.dart` | 52 |
| Engine | `slide_normal_autofit_test.dart` | 16 |
| Engine | `slide_gradient_merge_test.dart` | 6 |
| Engine | `slide_background_publication_test.dart` | 3 |
| Engine | `office_macro_slide_format_test.dart` | 19 |
| Engine | `office_vba_powerpoint_integration_test.dart` | 7 |
| Engine | `office_pdf_alpha_integration_test.dart` | 3 |
| **Engine subtotal** | **9 files** | **147** |
| Editor | `slide_render_fidelity_test.dart` | 14 |
| Editor | `slide_incoming_pptx_regression_test.dart` | 17 |
| Editor | `slide_normal_autofit_test.dart` | 5 |
| Editor | `word_typing_proofing_schedule_test.dart` | 5 |
| **Editor subtotal** | **4 files** | **41** |
| **Total** | **13 files** | **188** |

The selection covers the actual parser/PDF conflicts and existing import,
radial, alpha and autofit regressions, plus native formatting and PowerPoint
macro integration. The five typing/proofing cases cover the newly shared
scheduler used by Word-based editing, including Mail composition. Unrelated
font/orientation suites and the entire VBA/Zotero projects were not added to
this bounded gate.

## Case identity and receipt correction

The first receipt postprocessor rejected repeated display names even though
both test processes had already passed. The incoming native-format suite
intentionally generates separate cases for an empty group shape and a group
containing a child shape. Its title uses only the first XML tag, so both cases
are displayed as `strict Office shape collection refuses <p:grpSp> before a target`.

Those two cases have distinct runner IDs **158** and **163** in the engine
cohort. Each completed successfully exactly once. All **147 engine** and
**41 editor** completion identities are distinct. The accepted receipt counts
cases by their suite and runner test ID; a shared human-readable label is
reported as a diagnostic rather than mistaken for a repeated completion.

The original postprocessing rejection and original counter are preserved as
`summary-initial-counter.json` and `run-initial-counter.py`. The corrected
counter reparsed the same verified raw events; **no tests were rerun and no
product or test source was changed**. `summary.json` records the correction,
both identities, the two parameter fixtures, and the successful runner exit
codes and terminal events.

## Source, runtime and evidence binding

All **2,214 captured inputs** remained byte-identical before and after the
cohorts. The inventory includes every engine/editor library, asset and test
file, plus the root/package dependency and runtime configuration files listed
by the runner. All seven runtime/configuration pins were also unchanged: Dart,
Flutter tester, Flutter tools snapshot, native SQLite, package configuration,
package graph and the pinned Dart test entry point.

Independent Git-object comparison confirms that **2,213 tracked inputs** match
the published checkpoint `1d26181b0161d88abe5977f9848ffd4cd99e6259` exactly.
The remaining input is the resolved local package configuration, recorded by
SHA-256 without representing it as a tracked file. The comparison also verifies
that incoming main `d040c15a07f652d01e75363031d0efdee6357bda` is an ancestor
and that the two parser insertions are the only Office library differences.

The `main-office-latest/` evidence contains the exact selection and runner,
analysis command/result, original and corrected counting receipts, raw engine
and editor event streams compressed without loss, stderr files, before/after
SHA-256 inventories, the checkpoint comparison and the incoming-main source
diff. Decompressed event bytes match the stdout hashes in the receipts.

The full test commands and working directories are recorded in `summary.json`.
The engine invokes the pinned `test-1.31.1` entry directly with
`--reporter=json --concurrency=2`; the editor uses
`flutter test --no-pub --concurrency=1 --reporter=json`. The receipt runner
accepts the expected full checkpoint as its only argument and refuses a
different checked-out source. A later documentation-only publication can be
bound by exact input comparison without changing the original run's identity.

This gate establishes local behavior for the selected integration risks. It
does not claim installed Windows/macOS/mobile qualification, native PowerPoint
comparison, or complete VBA, Office or Mail parity.
