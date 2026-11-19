# Resumed document review — 18 November 2026

**Final qualification: PASSED.** This record covers the continuation
after the earlier disk-exhaustion checkpoint. The final local run is bound to
source commit `a7512e94da8208123aa2df5f5c2c0354d079ddc7` and tree `0817e6573070fe1e30f63615956e801b1605f992`.
The committed plan ran **77 suites**, completing **1,244 passing
Dart/Flutter cases, 0 failures and 0 skips**. GitHub Actions
was neither queried nor awaited.

## What the editor now does

Footnotes and endnotes can be reviewed in the editable **Notes** field. Spelling,
grammar and style findings have red, blue and amber wavy underlines. Nearby
correction, Ignore once and dictionary controls keep the current text selection
and return typing focus to the note. Checking, paused checking and incomplete
or unavailable coverage remain visible. **F7** requests an explicit check,
including configured manual providers; **Alt+F7 / Alt+Shift+F7** navigate findings.
**Review changes** opens the persistent Changes pane.

This continuation also closes several ownership and history gaps:

- Notes keyboard **Ctrl+Z**, **Ctrl+Shift+Z**, **Ctrl+Y**, and the platform's
  Command-based text Undo/Redo use document history. Typed text and a subsequent
  correction remain separate history steps. Redo cannot replace new typing
  with the abandoned redo branch after Undo.
- **Language and checking** applies to the actual Notes selection or current
  editable paragraph, including multiline and reversed selections. The hidden
  native reference separator and unrelated body text retain their settings.
  Pending typing must commit before these settings change.
- Opening, closing or repositioning Writing during a window resize preserves
  the Notes field and selection. Stale actions, document switches, protected or
  selection-only editing, and active IME composition retain their safety guards.
- Recording already-applied typing into Undo history preserves a settled check,
  including a manual check with no findings, without another provider call.
  Actual source/configuration changes invalidate the affected results; manual
  coverage after an edit still requires an explicit check.
- Header/footer editing, language controls, caret placement and review navigation
  distinguish the rendered default, first-page and even-page stories. Editing
  backgrounds paint beneath text, and selection highlighting stays in its story.

The [review guide](../../../document-review.md) describes the complete workflow.
Two navigation boundaries remain explicit: a stored alternate header/footer
disabled by page settings or absent from all laid-out pages stays reviewable in
the pane; nested Notes table/frame paragraphs outside the flat Notes field stay
in Writing/Changes. Navigation neither substitutes another story/body paragraph
nor changes page settings to expose one. Supported Notes ranges account for
hidden separators, paragraph boundaries and UTF-16 offsets.

## Incoming work was integrated first

The final bounded snapshot combines the full API refresh at
**18 November, 22:29:41–22:29:43 CET** with the subsequently fetched Mail
branch/PR head at **22:33:28 CET**. It contains **391 references and 253 distinct heads**: 212 fork branches, 175 PR heads and four upstream
branches. All captured references are accounted for: 363 by ancestry and 28 by
14 independently reverified historical equivalents. This is a capture cutoff,
not a claim about branches that advanced afterward. Integration proof is separate
from runtime qualification.

| Incoming continuation | Integrated head |
| --- | --- |
| Mail reader and durable store | `086e15b7c059edd09cc77dea721f489b5ef97fa9` |
| Zotero note insertion/navigation | `8fa115e8358e305872fd14e757f9133fa9c1540d` |
| Thesaurus and compact review | `0ea205e0ee35bb43635960a0edafd42dc4c16e8d` |

The [capture summary](reconciliation/summary.json) and
[integration verification against the tested source](integration-verification.json)
preserve the heads, cutoff, classifications and exact verification inputs.
Implementation and integration checkpoints were saved incrementally on the
remote continuation branch.

## Validation outcomes

| Check | First frozen run | Final frozen run |
| --- | --- | --- |
| Source | `1aa37e564d615807b74c5f9c2d662488c669ad17` | `a7512e94da8208123aa2df5f5c2c0354d079ddc7` |
| Completed Dart/Flutter cases | **1,243 passed; 1 failed; 0 skipped** | **1,244 passed; 0 failed; 0 skipped** |
| Planned suites | 77 | 77 |
| Strict analysis / formatting | Both passed | Passed / Passed |
| Whitespace gate | Failed on imported raw logs and verbatim notices | Passed; exact preserved inputs bound |
| Source/runtime stability | Before/after identities unchanged | Source, HEAD, index and runtime unchanged |
| Overall acceptance | **Failed** | **PASSED** |

The first run's single test failure was `narrow RTL pane retains citation
selection` in `word_zotero_notes_pane_test.dart`. Its log records a tap at
`(160, 655)` outside a `320 × 640` viewport at increased text scale. Without
focus, the field correctly declined to publish a programmatically assigned
selection. The fixture now scrolls the actual field into view, asserts that it
is hit-testable, taps it, and asserts focus before selecting text. The existing
citation assertion remains intact; the missed-tap warning was not suppressed.

The whitespace gate separately rejected six incoming raw logs and five verbatim
license notices. Their original bytes are retained. The plan now enumerates
those 11 exact paths plus four preserved raw recovery/preflight patches, each
with its Git blob identity. The runner validates all 15 before excluding their
whitespace diagnostics. It has no blanket patch or log exclusion. These files
remain bound source inputs; changed blobs, product paths and authored
code/configuration extensions cannot be excepted. Other changes retain ordinary
whitespace checks.

The [plan](../test-plan.json) covers nine engine suites, 49 editor suites, nine
Studio suites, one Mail core suite, seven native Mail-store suites, one Node
problem-handling suite and one Mail-reader UI suite. Python runner/tool checks
and the native smoke are recorded separately and do not inflate Dart/Flutter
case totals. Final screenshot inspection: **Passed for all three real-font captures**.

## Runtime provenance and reproduction

The reconstructed restorer's original **VM-only path was executed** on this
continuation: the complete official Flutter **3.47.8** / Dart **3.13.7** archive
and selected executables were hash-verified, 176 pinned hosted archives were
verified, and 130 workspace packages resolved with offline lock enforcement.
The Dart-to-JavaScript compiler was subsequently retained from a **separate,
fully hash-verified official SDK stream**, recorded as a compiler supplement.
That supplement is not presented as part of the original extraction.

The committed native smoke was then executed by absolute filename through
`dart run`; its log reports a successful in-memory SQLite/FTS5 round trip.
The imported `bind_test_inputs` helper was also executed against that runtime.
It binds four actual inputs: the generated native-assets mapping, copied
SQLite library, original cached hook library used by child `dart run` fixtures,
and resolved Node executable. SQLite must match the pinned Linux asset SHA-256;
Node records its hash and version. Original restore commands/archive fields and the later binding
provenance remain distinct.

Dart test groups use the locked, retained `package:test` entrypoint directly,
avoiding the observed `dart test` startup stall. VM kernel tests consume the
bound native-assets mapping; the Node group uses the verified compiler and
recorded Node runtime. Run all test groups serially at concurrency one.

The [runtime instructions](../runtime/README.md) now describe a fresh combined
`--node-tests` restoration that prepares these prerequisites. **That complete
fresh combined restoration has not been executed.** Executing its native smoke
and imported binding helper against the existing runtime does not establish
that the full download/bootstrap path was rerun.

## Evidence publication and qualification scope

[evidence.tar.xz](evidence.tar.xz) contains the final run, failed first run,
development checks, original reporter logs, completed-case inventories, command
results, and source/runtime manifests. [evidence-index.json](evidence-index.json)
records every uncompressed file hash plus the archive hash. The final runtime
receipt, original restore logs, separate compiler supplement, and smoke output
are included. The rejected first run retains its recorded receipt hash and
before/after manifests; its earlier runtime receipt bytes were superseded by
the later explicit binding. The authoritative final result is
[verification.json](verification.json); the separate 56 Python cases are in
[python-verification.json](python-verification.json).

The three inspected captures use real text and icon fonts:
[desktop Notes](screenshots/notes-inline-desktop.png),
[narrow RTL Notes at enlarged text scale](screenshots/notes-inline-arabic-narrow.png),
and [even-page header selection](screenshots/header-even-review.png).

Qualification belongs to the frozen source named above. Later publication
commits add documentation and evidence. The [publication record](publication-scope.json) verifies that
implementation, tests, the plan and executed tooling are unchanged; it does not
relabel the run as if it executed on the later documentation commit.

The selected local tests and rendered fixtures qualify the stated behaviors
within their scope. They do not establish complete native/web application
builds, actual browser interaction, physical keyboard/IME behavior, optional
provider-service quality, or live Mail/Zotero-account interoperability. The Node
problem-handling test is not a browser UI test. Earlier smoke counts and older
batch totals are not added to this run's acceptance result.
