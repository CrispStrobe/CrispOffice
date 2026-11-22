# Zotero research-note formatting — 22 November 2026

## Goal and starting state

Continue the native Zotero Word/LibreOffice parity roadmap by preserving the
paragraph direction, indentation, alignment and inline colors that Zotero
exports with research notes. Existing citation fields, detached completion,
selection ownership, undo/redo and DOCX persistence remain acceptance criteria.
This increment implements the bounded formatting contract below, with local
source qualification and preserved actual converter evidence. It does not
claim complete installed Word/LibreOffice Zotero-plugin parity.

Work starts at remote main `3f3cb8508663dde917e913867908dbfd6c3efcf0`.
All 37 captured fork branch heads, 100 most recently updated PR heads and four
upstream branch heads are ancestors of that commit. No PR was open. A fresh
check also found `codex/word-vba-string-search-20261122`, initially at the same
main commit. The intake audit is retained in `intake.json` and will be refreshed
before final publication to preserve concurrent work.

## Execution method

1. Preserve an initial checkpoint on `codex/zotero-note-formatting-20261122`.
2. Implement the bounded canonical note-formatting contract from pinned Zotero
   note-editor sources, with focused engine and editor regressions.
3. Run local checks with the repository-pinned Flutter/Dart runtime and locked
   dependencies. Record exact commands, counts and any remaining limitations.
4. Reconcile new remote commits, preserve incremental checkpoints and merge the
   qualified result into remote main without waiting for GitHub Actions.

Installed Zotero, Word and LibreOffice plugin acceptance remains a separate
requirement; controlled protocol tests and file round trips do not establish it.

## Implemented contract

Canonical paragraph/heading `dir`, `data-indent` and `text-align` now map to
native properties. The redundant 40 CSS px compatibility padding is counted
once at 30 pt per level. Explicit alignment is independent of reading order;
absent direction stays automatic. Formatting follows the final paragraph
owners through merged cells and composes after heading/list/quote styles.
Structured insertion protects the unselected surrounding paragraphs.

Opaque exported foreground/background colors use opt-in note parsing, keeping
ordinary CSL formatting unchanged. Arbitrary RGB highlights persist through
native Word run shading. Authored highlights paint opaquely in the canvas,
matching PDF and export semantics. Heading styling preserves explicit colors.

The controller distinguishes authored empty-paragraph direction from its own
automatic language-following state. Native directions survive relayout,
typing, undo/redo and DOCX reopening; ordinary blank paragraphs still follow
the selected interface language until the user sets their direction.

Actual LibreOffice conversion exposed a shared DOCX physical/logical mapping
defect. Paragraph indentation and alignment are translated using effective
direction, including inherited styles and sparse property edits. Explicit
first-line/hanging resets remain effective after reopening. RTL ruler handles
use the same physical margins as layout during later editing.

The support details and parity roadmap document the accepted forms and
remaining boundaries. In particular, directional lists, RTL child paragraphs
inside lists, indent levels above seven, alpha/dynamic colors and arbitrary
layout CSS remain guarded. Installed-plugin acceptance is still open.

## Remote checkpoints

| Checkpoint | Commit |
| --- | --- |
| Intake audit and execution plan | `e84fc1d6c872d450dc485f1b981562792fbd082f` |
| Paragraph/color implementation and regression cases | `7b9d50259f9d6bb9b39678ec4afced644e88c38b` |
| Direction lifecycle, exact highlight rendering and support contract | `aac3dda7a052c18f6f5bcc5e84a8d7c8cea8af95` |
| Qualified incoming Word history | `5429be3c19cb8f74f8f7fca8178a29ecc9416b36` |
| Published Word/main qualification | `50895a7b9670058e27d3f081626defac9ea1aebc` |
| Completed Mail and latest main ancestry | `168297fea2df1f49cb1362f8ac21002edd222ac4` |
| Original converter failures, independent probes and pinned runtime | `5d79e934c5400594410bb6dfcb347d279fe0c335` |
| Reviewed RTL IO, sparse styles, ruler and final test runner | `d68df6d625d7f81163c502ed46dcfd97a806e95a` |
| Latest main/Mail publication and exact formatter normalization | `6f74d11b857deaa43981e8a7eb72157cd6bd518e` |

The first late intake identified new Word substring-assignment work and an
unfinished Mail Archive checkpoint. The Word head
`19a63d4455540bd797e546ab82ec14db128abea0` passed its four new suites and seven
shared language suites in an independent checkout before integration. Its
original ancestry and author evidence are retained. Final integrated checks
will report their own counts separately from development/isolated runs.

Mail head `9d8758e55` was initially unfinished. Its completed successor adds
the missing switch handling and qualified provider, journal and UI behavior.
Independent checks at `a61f7c07` found two outdated test assumptions; author
checkpoint `a886d7d7` fixes both and adds native INBOX-alias duplicate handling.
Reconciled Mail `8280277c` retains identical Mail source and incorporates our
existing Zotero checkpoint, Word and main `4621326a`. Main `4621326a` is an
ancestry-only merge with the same tree as Word publication `05bb203e`.
All these heads are ancestors of our saved `168297fe` checkpoint.

The exact late-ref audits are `late-intake-1.json` and `late-intake-2.json`.
The latter retains the initial failures and successful corrected-head reruns:
37 selected migration/journal cases, 15 native Archive cases and 276 affected
Studio cases. Earlier overlapping checks and the interrupted full-store attempt
are reported separately; they are not summed into a final acceptance total.

The final capture at 11:06 UTC contains **42 fork branch heads and the 100 most
recently updated PR heads and merge commits**. Every captured head is an
ancestor of `6f74d11b`; `final-intake.json` records the individual checks.
It includes Mail publication PR #379 / main `b510b2dc` and the documentation-only
Word text-selector intake `091be781`. The initial four upstream heads remain
covered by the starting audit; no claim is made about uncaptured future work.

## Final local qualification

The five behavioral cohorts ran on the clean, fixed source
`d68df6d625d7f81163c502ed46dcfd97a806e95a`. Each retained all 3,778 captured
source/configuration/fixture hashes unchanged from start to finish. Counts
exclude hidden loader events and do not add repeated development runs.

| Cohort | Test files | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Engine: notes, colors, paragraph IO, styles, native persistence and affected VBA layout | 42 | 1,197 | 0 | 0 |
| Editor: transactions, rendered colors, direction, ruler, selections and undo | 17 | 345 | 0 | 0 |
| Studio: Zotero transport, shortcuts and editable ODT export | 3 | 45 | 0 | 0 |
| Incoming Word substring/shared language behavior | 11 | 934 | 0 | 0 |
| Incoming Mail Studio integration | 3 | 276 | 0 | 0 |
| **Total** | **76** | **2,797** | **0** | **0** |

All five processes exited successfully with completed reporters, no errors,
and no unfinished tests. The Mail cohort used a command-scoped preload of the
installed SQLite library; its exact library hash and environment are retained.
The SDK is the repository-pinned **Flutter 3.47.8 / Dart 3.13.7**, obtained from
the hash-verified official archive. All 204 hosted dependency archives were
verified and resolved offline with the lockfile enforced. All 23 tracked
manifests/pins stayed unchanged.

Strict analysis passed across all 70 changed Dart files, including incoming
Word/Mail code and tools. The first read-only format gate accurately recorded
two formatting flags in the candidate. Latest remote main already
contained those exact normalizations: executing the same official Dart
formatter on both tested files produced byte-for-byte identical incoming
files. `6f74d11b` adds only these formatter outputs to executable paths; all
other changes from the tested source are documentation/evidence and ancestry.
The retained normalization proof and final strict analysis/format receipts
close that gate without relabeling the earlier failure.

The broader Linux Word fidelity golden remains a separately retained
diagnostic, not a passing gate. Initial main already differed in 3,378 pixels
on this runtime. The authored-highlight correction changed exactly 1,522
additional pixels; only that justified highlight region was updated. The
post-update diagnostic retained the same original 3,378 differing pixels.
New exact-color rendering and existing dark-document checks pass in the final
editor cohort. Generic/macOS goldens and full-suite qualification are not
claimed here.

## Actual LibreOffice conversion

The converter is **LibreOfficeDev 26.8.0.0.alpha0**, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. This is an identified development
build, not installed Zotero-plugin or supported-release acceptance.

The same real citing-session fixture inserts formatted notes into the body,
an authored footnote and a table cell. It includes explicit LTR/RTL, headings,
an empty paragraph, 30/60/90 pt indentation, opaque RGB foreground/background,
two active citations and preferences. Both formats pass through two actual
save cycles per story. Fixture/checker files and expected snapshots are
identical before and after the IO correction. The final run's 22,035 source,
dependency, generator and runtime hashes also stayed unchanged.

| Observation | Result after the correction |
| --- | --- |
| Actual converter save operations | 12/12 succeeded |
| Independent XML content, scoped paragraph formatting, colors, fields and preferences | 18/18 passed, versus 9/18 before the fix |
| Original native DOCX and ODT strict reopen | 6/6 passed |
| All original/converted DOCX native content, scoped formatting and metadata | 9/9 matched; editability is reported separately |
| LibreOffice-saved DOCX strict native result | Six differences, solely the existing citation-editability guards |
| LibreOffice-saved ODT native reopen | Six refusals from existing outline-style guards |

Independent rendered geometry confirms the correction. The centered RTL test
run moved from x=312.581 pt to x=282.581 pt in DOCX, matching the ODT position
x=282.599 pt within **0.018 pt**. The second DOCX save cycle retains that
position. The empty explicitly LTR paragraph now retains right alignment when
LibreOffice uses `jc=end`.

Strict failing routes remain in the raw results. LibreOffice adds formatting
to field instruction/separator/end boundary runs; the existing opaque-metadata
guard then makes both citations noneditable. Their valid metadata, balanced
boundaries and ownership remain intact. ODT cycle one is refused for numbered
or positioned outlines; cycle two is refused for `loext:num-list-format`.
Neither guard was relaxed to manufacture a passing result. Scoped semantic
preservation is not complete typography, pagination or editable-plugin parity.

## Evidence and reproduction

- `qualification.json` summarizes final counts, source attribution and limits.
- `evidence/local-checks.tar.xz` retains raw reporters, per-case records,
  before/after hashes, exact commands, initial failures, independent reviews,
  normalization proof and golden diagnostic images. `local-checks-index.json`
  gives each member's SHA-256.
- The before/after converter archives retain all original and saved files,
  checker source, strict native failures and rendered PDFs. Separate direction
  and first-line archives preserve the additional specification/consumer probes.
- `evidence/converter-after-fix-summary.json` and the adjacent readable converter
  records expose component results without unpacking the archives.
- `evidence/artifacts.json` records archive sizes and SHA-256 values.

With the pinned Flutter SDK on PATH and the existing locked workspace package
configuration resolved, run each cohort through the committed runner:

```sh
python3 docs/validation/zotero-note-formatting-20261122/run_checks.py \
  --cohort engine --output /absolute/evidence-directory
```

Repeat with `editor`, `studio`, `incoming-word` and `incoming-mail`. The runner
uses the resolved test CLI for pure Dart and `flutter test --no-pub` for Flutter,
captures exact commands and source hashes, and neither installs dependencies
nor queries GitHub Actions. Converter archives retain their separate exact
commands and environment. No GitHub Actions result was queried or awaited.

## Next parity work

1. Qualify bounded, benign formatting on citation field boundaries before
   widening the opaque-field editing guard; require successful native edits,
   actual Zotero Refresh and repeated application saves on the retained files.
2. Extend or explicitly normalize the observed LibreOffice outline forms,
   retaining the original failed ODT routes and their metadata/format assertions.
3. Extend directional list markers, higher historical indent levels and richer
   note styling only with native ownership, editing, rendering and file tests.
4. Run the complete workflow with installed Zotero and Word/LibreOffice plugins
   on supported release hosts, recording exact versions, source and artifacts.

Primary contract sources are the pinned Zotero note-editor schema/styles and
Zotero export conversion linked from the parity roadmap. The direction mapping
is supported by ECMA-376 Part 4 §§14.3.1.2 and 14.11.2, plus the retained real
converter probes. The [parity roadmap](../../roadmaps/zotero/word-processor-parity.md)
and [support details](../../zotero-support-details.md#paragraph-layout-and-colors-in-research-notes)
keep this bounded increment separate from full application parity.
