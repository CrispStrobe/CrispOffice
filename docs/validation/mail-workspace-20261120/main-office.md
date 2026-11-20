# Office qualification after the concurrent main merge

The final publication refresh found remote `main` at
`860c807bfd1385899eed130abfb8940f95bda113`. Its already-published changes
include the VBA/Zotero work that earlier refresh reports had correctly kept
separate while it was in progress, plus newer slide geometry, background
ownership, autofit and installed-font work. This reconciliation preserves that
published main and combines the Office rendering corrections from the Mail
branch. Earlier pending-work dispositions describe their captured refresh;
they are not the current disposition of code already landed in this main.

The combined source was saved remotely as
**`01290ceed6f9163023ce8f27bb74033f088b62e4`**, tree
`413a8ebc8f66c5b95584710aab7d8bb6fcc431fc`, before the gate below ran.
The result is **300 passing cases in 23 selected suites, with no failures or
skips**. These selections replace the overlapping historical 137-case and
116-case Office gates. They are not added to those totals or to Mail totals.
No GitHub Actions, check or status endpoint was queried or awaited.

## Merge decisions and scope

Five files required manual conflict reconciliation: the Flutter slide renderer,
PDF picture painter and canvas, slide serializer, and DrawingML shape parser.
The automatically merged PDF exporter and presentation model were also
reviewed. The combined implementation retains:

- Main's depth/namespace-scoped gradient ownership, background provenance and
  ownership rules, direct-master edits, geometric presets and clipping, and
  strict finite autofit model. A valid zero font scale still preserves authored
  text and paints no glyphs; fixed-point leading remains independent of
  percentage line-spacing reduction.
- Main's installed-font registration and alias handling, system-font
  discovery/validation, and Word paint-family mapping. The selected font suites
  exercise these changes in the local Flutter runtime.
- Our centered radial rendering with a circle circumscribing the shape bounds,
  scoped picture alpha, canonical PDF graphics-state resources, and shared
  measurement/painting line-advance calculation. The incoming PDF text-state
  close before an alpha operator and shadow/border save/restore behavior remain.

The radial parser now also preserves main's supported **omitted circle focus**
as the default center. Explicit off-center focus, rectangular/shape paths and
custom fill tiles retain the documented solid fallback. Shape and background
parsers apply those decisions only at the relevant namespace and XML depth.
The radial regression file has a positive omitted-focus case in place of its
earlier fallback expectation. The historical follow-up report's missing-focus
limitation therefore no longer describes this combined source.

The circumscribed radial geometry follows the Microsoft Open Specifications
team's [geometry explanation](https://learn.microsoft.com/en-us/answers/questions/2248059/non-preset-a-tilerect-behaves-strange-in-case-of-g)
and the [focus-rectangle definition](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.filltorectangle?view=openxml-3.0.1).
PDF still uses the bounded 72-ring approximation. Full path geometry, Office's
special gamma interpolation and exact custom-path bounds remain outside this
increment.

The first preflight analysis caught an automatic-merge defect: both branches
had inserted the same `extGStates` named argument into `_PageSink.finish` at
different positions. The duplicate was removed before the checkpoint and
accepted tests. The initial diagnostic is retained in
`main-office/analysis-automerge-duplicate.txt`; final strict analysis of the 13
listed source/test targets reports no issues in `main-office/analysis.txt`.
No product changes were necessary during or after the accepted test run.

This is a focused rendering/model/font gate. The already-landed macro and
Zotero projects were preserved, not requalified in their entirety. The
checkpoint comparison includes byte-for-byte preservation checks for their
compiler, note, note-image and Word-deserializer sources, alongside the three
incoming font/Word-paint sources listed in that receipt.

## Accepted selection

The repository-pinned Flutter **3.47.8** / Dart **3.13.7** and retained dependency
lockfile were used. The engine cohort ran first; the editor cohort had exclusive
use of the Flutter runner. The complete gate ran from
**2026-11-20 09:42:08 UTC to 09:43:03 UTC**.

| Package | Test file | Passed |
| --- | --- | ---: |
| Engine | `slide_import_fidelity_test.dart` | 52 |
| Engine | `office_pdf_export_test.dart` | 27 |
| Engine | `slide_gradient_merge_test.dart` | 6 |
| Engine | `slide_radial_opacity_test.dart` | 14 |
| Engine | `slide_normal_autofit_test.dart` | 16 |
| Engine | `pdf_picture_opacity_test.dart` | 3 |
| Engine | `slide_gradient_publication_test.dart` | 24 |
| Engine | `slide_background_publication_test.dart` | 3 |
| Engine | `slide_geometric_presets_test.dart` | 11 |
| Engine | `slide_picture_background_test.dart` | 32 |
| Engine | `style_cascade_test.dart` | 11 |
| Engine | `slide_transform_orientation_test.dart` | 18 |
| **Engine subtotal** | **12 files** | **217** |
| Editor | `slide_render_fidelity_test.dart` | 14 |
| Editor | `slide_incoming_pptx_regression_test.dart` | 17 |
| Editor | `slide_transform_orientation_test.dart` | 8 |
| Editor | `installed_host_fonts_test.dart` | 8 |
| Editor | `office_system_fonts_test.dart` | 7 |
| Editor | `host_fonts_test.dart` | 6 |
| Editor | `paint_font_fallback_test.dart` | 2 |
| Editor | `slide_normal_autofit_test.dart` | 5 |
| Editor | `office_slide_effects_test.dart` | 9 |
| Editor | `slide_background_publication_test.dart` | 4 |
| Editor | `slide_geometric_presets_test.dart` | 3 |
| **Editor subtotal** | **11 files** | **83** |
| **Total** | **23 files** | **300** |

Both processes exited zero and emitted a successful final runner event. Counts
exclude hidden loading events and include no skipped cases. Each visible case
is mapped through its runner suite ID to the actual selected source file; no
duplicate `(suite, case name)` pair occurs.

## Exact input binding and evidence

All **2,204 captured Office inputs** remained byte-identical between the start
and end of the gate. This inventory covers every file under engine/editor
`lib`, `assets` and `test`, together with the root/package dependency and runtime
configuration files listed in `run.py`. All seven captured runtime/configuration
pins were unchanged as well: Dart, Flutter tester, Flutter tools snapshot,
native SQLite, package configuration, package graph and the pinned Dart test
entry point.

An independent Git-object comparison bound **2,203 tracked inputs** to the
published checkpoint `01290ceed6f9163023ce8f27bb74033f088b62e4`, with zero
mismatches. The remaining input is the resolved local package configuration,
whose SHA-256 is recorded in both the source and runtime inventories. It is not
misrepresented as a tracked repository file.

The `main-office/` evidence contains:

- `selection.json`: the exact 23 selected paths.
- `run.py`: the runner, including the required checkpoint, sequential cohort
  commands, input capture, counting rules and acceptance conditions.
- `summary.json`: exact commands, working directories, timings, case names,
  per-suite counts, exit codes, final runner events and raw stdout/stderr hashes.
- `engine.jsonl.gz`, `editor.jsonl.gz`, and their stderr files: losslessly
  compressed raw event streams; decompressed bytes were verified against the
  recorded SHA-256 hashes before redundant uncompressed copies were removed.
- `inputs-before.json`, `inputs-after.json`: complete SHA-256 input/runtime
  inventories, with empty change lists recorded in `summary.json`.
- `checkpoint-comparison.json`: the Git-object comparison and selected
  unchanged-main source checks.
- The initial and corrected analysis logs described above.

For reproduction, use the pinned runtime and resolved dependency cache, with
the engine test runner entry from `test-1.31.1`. The exact argument vectors are
in `summary.json`; `selection.json` supplies the file lists. Engine tests use
the direct pinned `package:test` entry with `--reporter=json --concurrency=2`;
editor tests use `flutter test --no-pub --concurrency=1 --reporter=json`. The
receipt runner deliberately checks its original source checkpoint, so later
documentation-only publication commits require either a checkout of that
source with the retained runner/evidence copied in, or an explicit new receipt
for the later checkpoint.

This gate establishes the selected behavior in local model, PDF and Flutter
tests. It does not claim installed Windows/macOS/mobile qualification, a native
PowerPoint comparison, or complete Office or Mail parity.
