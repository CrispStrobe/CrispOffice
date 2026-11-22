# Zotero research-table margins and native ODT padding

This increment makes native table layout use the uniform margins already stored
in the Word model and DOCX. Explicit editable Zotero ODT import/export preserves
the same bounded padding, including independent nested tables and merged owners.
It also reconciles every ref in the captured Office intake and qualifies the
combined source locally.

**Qualification: 4,635 distinct passing cases across 239 suites, with no
failures, errors or skips.** The fresh converter fixture retains nine active
fields through two actual LibreOffice saves and an intervening DOCX/ODT cycle.
GitHub Actions, checks and status queues were neither queried nor awaited.

The complete tested source and references are retained at
[`d1125df123c68ff4bedcc0d163e6d4fb06bb0e18`](https://github.com/CrispStrobe/quds_office_suite/commit/d1125df123c68ff4bedcc0d163e6d4fb06bb0e18),
tree `eba5a73fb140a33425d1a3a6a5b45615cee39040`.
Later main integration includes separately qualified Mail, shortcut and Word
VBA changes. Their exact applicability is recorded in
[the incoming-source continuity audit](main-source-continuity-52e72ca0.json).
[The host-ownership follow-up](../zotero-host-ownership-20261121/README.md)
adds fresh focused dialog and Studio qualification on its own recorded source.
The 4,635 cases and converter saves above remain attributed to D112.
Publication: [PR #342](https://github.com/CrispStrobe/quds_office_suite/pull/342).

## Delivered behavior

- Native measurement, wrapping, row heights, pagination and ruler fallback use
  each table's actual margin, including zero. The model default remains 4 pt;
  the renderer's previous fixed 4.25 pt inset is corrected.
- Nested tables retain independent margins. Picture height budgets use the sum
  of enclosing margins, including temporary tall-row engines and note tables.
  The enclosing budget is restored after nested work or a layout failure.
- Explicit editable Zotero ODT writes uniform `fo:padding` on cell styles.
  Native import resolves family defaults and named parent chains. Each layer's
  shorthand sets four sides before its explicit sides override them.
- Visible owners in one table must have equal effective sides and one shared
  margin. Authored or inherited covered-cell padding must match its merged
  owner; an absent declaration adds no override. Nested tables resolve separately.
- Export validates the actual serialized geometry with exact integer
  hundredths of a point. Exact exhaustion, decimal-offset cancellation and
  margins that exhaust a cell only after rounding are refused before bytes
  are returned. Merged cells are checked against their complete span.
- Uniquely defined, body-referenced image-only endnotes render without requiring
  textual content. The new path excludes orphan, duplicate and frame-only
  references.
- The incoming Word-position safeguard refuses editable ODT export of
  unsupported absolute baseline shifts, including inherited run, paragraph-mark
  and note-marker values. Explicit zero overrides and supported semantic
  superscript/subscript remain accepted.

Ordinary cached-result ODT export retains its existing formatting contract.
Editable padding output is part of the explicit Zotero export path.

## Format and layout limits

The model represents one uniform scalar margin per table. Effective asymmetry,
per-cell differences, unsupported row/column default-cell styles, hidden covered
content and unsupported visible borders remain refusals. LibreOffice's explicit
`border="none"` declarations are inert and accepted.

Margins must be finite, nonnegative, no greater than 32,767 DOCX twentieths of a
point (1,638.35 pt), and leave positive cell content width. ODT output rounds
lengths to 0.01 pt; DOCX margins round to 0.05 pt. Arbitrary fractional input
therefore does not have an exact-geometry guarantee across formats. Native
layout can scale a table to its page or containing cell and refuses a final
scaled width exhausted by the margins.

## Remote intake and incremental saves

Work began at `aa861c28e336b17bcd4c259351164380cd6b1438`. All fork branches,
pull-request heads and upstream branches/PR heads were fetched before new code.
The first snapshot contains **392 refs: 378 ancestors and 14 independently
verified historical equivalents**, with no outstanding captured work after
integration. The outstanding Zotero continuations `c0ae75c2...` and `a7f69313...`
were integrated while retaining both qualification histories and cache tests.

The expanded publication snapshot contains **396 refs**. Its four outstanding
aliases referred to three newer tips. These were reviewed and incorporated:

| Incoming tip | Integration and validation |
| --- | --- |
| `4b33109aa85e077e2798265efa045d640e6ead4e` | Zotero absolute-position export safeguard and retained continuation records; fresh guard and ODT regressions |
| `2acf7473838a42b208b90c177fe0bc5d0f1c8252` | Bounded numeric VBA support; independently verified source-bound archive and 6,019 earlier cases, plus 204 fresh numeric cases in this qualification |
| `1360ead9e080fcf884ccac6cbc87bd6a58efdb5b` | Bounded saved-mail refresh; fresh 108-case local qualification, including all 32 new cases |

Accepted main `511df2a0...` and its paragraph/frame caches are included. Final
accounting for the bounded snapshot is **382 ancestors, 14 verified historical
equivalents and zero outstanding refs**. Thirteen equivalences compare complete
Git trees; the remaining historical PR compares all 37 changed paths by mode,
type and blob. Later work arriving after a captured snapshot is not silently
included in that snapshot's count.

`intake-initial.json`, `intake-publication-before-integration.json`,
`intake-final.json` and `verify_intake.py` retain the exact refs and replayable
proofs. All incoming commits remain reachable through merge parents. README
conflicts consolidate the duplicate completion paragraph while retaining both
original qualification records; changelog conflicts retain every distinct entry.

| Remote checkpoint | Preserved work |
| --- | --- |
| `57c5729ab1aa1ea8c1e27a4c76b233060b843e11` | Initial branch/PR intake and both Zotero continuations |
| `f6236ff5588441a24f9c8cc9c1dd4370d77eaddb` | Native table margins, editable padding, fixture and focused tests |
| `e255713a43fbd1f0e10adf3345350b6aec98add1` | Current main caches and export/endnote guards |
| `49ee5a474f00a7995c813d6060b763e1b9bdb41a` | Exact decimal geometry guard and demonstrated regression |
| `42d684bae0de8170313c6db4fa14e0fef8ba59e6` | Reviewed visual references, provenance and current-facing docs |
| `dd7d728e3dedcf7995586217431063f3bbed01a0` | All three newer captured Office branches |
| `d1125df123c68ff4bedcc0d163e6d4fb06bb0e18` | Final qualified compact-search test and baseline-position documentation |

Each remote update uses an expected-head lease and an exact local/remote Git-tree
comparison. No force update or branch-protection change is involved.

## Fresh local qualification

| Cohort | Suites | Passing cases |
| --- | ---: | ---: |
| Engine Zotero, including the incoming position guard | 55 | 1,456 |
| Other ODT regressions | 58 | 1,080 |
| Word tables, layout and notes | 42 | 621 |
| Word/PDF export | 8 | 77 |
| Incoming numeric VBA | 3 | 204 |
| Zotero/ODT editor | 53 | 963 |
| Zotero/ODT Studio | 4 | 41 |
| Table, ruler, selection and rendering editor | 10 | 85 |
| Incoming Mail refresh/search | 6 | 108 |
| **Total** | **239** | **4,635** |

All selected production/test Dart files (**29 files**) pass formatting and
fatal-info analysis; whitespace checks pass. The pinned runtime is Flutter
3.47.8 / Dart 3.13.7. Locked dependency resolution leaves the workspace lockfile
unchanged. Engine tests use the official `package:test` entry point through the
retained `engine-test` wrapper; Flutter tests use `flutter test --no-pub`.

All accepted runs have before/after source hashes. The consolidated index binds
**1,527 tracked inputs** to the exact remote source checkpoint. The generated
package graph and runtime inputs are separately hashed. The final publication
contains the previously qualified compact-list test overlay, so every accepted
source/test/reference hash can be checked against a retained Git object.

The final count excludes hidden loader/setup successes, repeated checks,
interrupted attempts, the initial failing diagnostics and historical branch
qualification. The verifier independently replays accepted event logs and
reports 4,635 distinct case instances, 239 distinct suites and zero repeated
accepted executions. Same-name parameter instances retain their occurrence
identity.

## Actual LibreOffice file acceptance

The `table-padding` fixture contains three outer tables with 0, 6 and 12 pt
margins, three independently padded nested tables with 3 pt margins, merged
cells and nine active citations. The fresh six-command acceptance sequence is:

1. Create the fixture and reopen it natively.
2. Save the untouched file through LibreOffice.
3. Reopen and compare the complete model, metadata and field ownership.
4. Save/reopen DOCX, then reexport and reopen editable ODT.
5. Save that ODT through LibreOffice again.
6. Reopen and compare with the original expectations.

All six commands exit zero. Source/input hashes remain unchanged; fields retain
text, formatting, citation metadata, editability and structural ownership. The
position-aware oracle records native baseline formatting as well as table margins.
Original, saved and intermediate ODT/DOCX bytes are retained in the archive.

Converter: **LibreOfficeDev 26.8.0.0.alpha0**, build
`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`. This is actual file-converter evidence.
It does not exercise the renderer or an installed Zotero-plugin session. Native
layout, pictures and PDF behavior have their separate local regression cohorts.

## Visual review and excluded attempts

Seven of 63 PNG references changed after visual review: four table-grid cases,
one nested-content case and the two Linux selection-color variants. All 56 other
references remain byte-identical. Content, merged structure, pictures and
selection coverage are retained. Exact pixel comparison remains enabled.
`golden-review.json` records old/new hashes, changed pixels and reviewed bounds;
the selection provenance file also retains previously stale metadata hashes.

The initial Mail run passed 106 cases and failed two compact German/Arabic tests.
Usable scrollable viewports were confirmed visually. The first lazy row was not
yet built, so the test now scrolls until it appears before running every existing
bidi, clipping, geometry and hit-test assertion. No production change was needed;
the complete 108-case mail cohort passed afterward.

A new decimal-offset case first demonstrated the export failure on the preceding
checkpoint, then passed after exact arithmetic replaced floating subtraction.
Early converter/profile diagnostics, expected pre-refresh golden mismatches,
scratch ENOSPC interruptions and source-changing qualification attempts are not
accepted results. Relevant failed logs, receipts and visual diagnostics are
retained separately from the accepted-log list. Final engine batches contain at
most 12 suites and clean their private temporary compiler files.

## Verify the evidence

`engine-evidence.tar.xz` retains the engine events, source binding, runtime
provenance and complete converter artifacts. `editor-evidence.tar.xz` retains
editor/Studio/Mail events, static checks, visual review and excluded diagnostics.
`index.json` records exact archives, members, source hashes and accepted logs;
`qualification.json` is the compact summary and `verification.json` the verified
replay result.

From a checkout containing the recorded commit and these artifacts:

```sh
python3 docs/validation/zotero-table-layout-20261121/verify_evidence.py
python3 docs/validation/zotero-table-layout-20261121/verify_intake.py \
  --snapshot docs/validation/zotero-table-layout-20261121/intake-publication-before-integration.json \
  --head HEAD --output /tmp/zotero-intake-replay.json
```

The evidence verifier checks both archives and every regular member without
extracting files, replays accepted test events, and checks tracked hashes against
the recorded Git commit/tree. `--skip-source-check` is available for archive-only
copies and explicitly reports that source binding was not checked.

## Remaining parity work

The next dedicated formatting increment is **active footnote-separator geometry**:
add a native model, matching reservation/pagination/rendering, ODT parsing and
emission, and interoperable DOCX persistence before widening import. Follow with
richer table groups and per-cell formatting, additional image envelopes and
structural editing across protected boundaries as described in the
[word-processor parity roadmap](../../roadmaps/zotero/word-processor-parity.md).

Installed Zotero-plugin sessions in Microsoft Word and supported LibreOffice
releases remain an explicit acceptance gate. Legacy Apache OpenOffice requires
its own identified compatibility target. This increment does not claim complete
plugin parity or testing of the entire repository.

## Primary format references

- [ODF 1.3 Part 3](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html): table styles, covered cells and padding attributes.
- [XSL 1.0 section 5.2](https://www.w3.org/TR/2001/REC-xsl-20011015/slice5.html#refine-shorthand): shorthand expansion and explicit-property precedence.
