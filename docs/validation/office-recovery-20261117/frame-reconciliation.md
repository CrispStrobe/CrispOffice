# ODF frame reconciliation — 17 November 2026

The recovered Office fidelity decoder and GECToR frame repair overlap. This
merge preserves the more complete structured table extraction while retaining
the fidelity decoder's linked drawing traversal and empty-anchor policy.
Historical evidence and the original source fixtures remain in their commits.

## Chosen behavior

- An anchor's own inline text is emitted once, before its nearest text-box
  stories in source order. `draw:a` may expose its direct `draw:frame` children.
- Text-box tables remain in `OfficeTextExtract.tables`; cell text stays inside
  its owning cell. Plain text and search still include the visible cell
  paragraphs in source order. No duplicate body paragraph represents a cell.
- A paragraph whose only content is one or more recognized text boxes is a
  structural anchor and adds no synthetic empty paragraph. This applies to
  empty, annotation-only and table-only text boxes, including empty tables.
  Ordinary authored empty `text:p` blocks, empty paragraphs inside a box,
  explicit `text:s`/tab whitespace and image-only paragraph anchors remain.
- Annotation, note, covered-cell and ruby annotation stories stay hidden.
  `text:soft-page-break` and image metadata cannot expose nested frames.
  Frame and inline-story traversal require namespace identity. The inherited
  top-level streaming table dispatcher is outside that namespace claim.
  The cumulative UTF-8 budget is checked before expanded whitespace allocation.
  Search and `readOdfText` also charge paragraph separators. Generic structured
  extraction charges decoded content and cell separators; later `plainString`
  wrappers and block separators remain outside its budget.

The empty-anchor rule follows the already qualified fidelity contract. An empty
text box has no visible text paragraph of its own, so introducing an extra blank
would make extraction depend on the presence of an otherwise invisible wrapper.
An empty table is still retained structurally without inventing a paragraph.

## Exact changes to prior assertions

Both incoming suites remain executable. No fixture XML or original visible
nonempty text was removed to make a regression pass.

1. In `odf_text_box_extraction_test.dart`, the annotation/covered-cell fixture
   still expects plain/search text `AB\nVisible`. Structured extraction now
   expects body paragraphs `['AB']` and tables `[[['Visible']]]` instead of
   body paragraphs `['AB', 'Visible']`. The shared helper independently checks
   structured paragraphs/tables and the original read/search sequence.
2. In `odf_frame_extraction_test.dart`, the original mixed-blank fixture is
   unchanged. Its expected paragraphs change from
   `['', '', '', ' \t', 'X', '']` to `['', '', ' \t', 'X', '']`.
   The removed entry belongs only to the empty text-box anchor; both authored
   empty paragraphs and the image-only anchor remain. Its search expectation
   correspondingly changes from `\n\n\n \t\nX\n` to
   `\n\n \t\nX\n`. This is the deliberate empty-anchor separator decision,
   not a relaxed text-content or whitespace assertion.

Three additional cases cover linked table-only frames with nonempty/empty tables
and linked image/page-break wrappers containing adversarial whitespace counts.
They check structured output, identical search/read output, exact UTF-8 budgets
and unchanged package bytes where applicable.

## Merge-time verification

The initial reconciled suites passed all 27 existing cases. After adding the
three controls, a focused six-file VM cohort passed **99 tests**, with zero
failures, errors or skips: 12 frame, 18 text-box, 19 export whitespace, 11
annotation, 12 covered-cell and 27 search-fidelity cases. The JSON event stream
ends with `success: true`. These are merge-time checks of the working source;
full source-bound qualification follows the frozen integration checkpoint.

An initial strict analysis invocation followed canonical-workspace symlinks back
to the source checkout, which has no root package configuration. It reported
unresolved package URIs and consequent undefined identifiers (187 diagnostics).
This failed invocation is retained separately in the local merge logs; it is
not a successful static-analysis result. No source or dependency change was
made to address that invocation context.

A follow-up already in flight before handoff supplied the existing canonical
configuration explicitly through `dart analyze --fatal-infos --packages=...`.
It passed with **No issues found** for the three extraction/decoder production
files and both frame regression files. It did not change the analyzer config,
source, dependency graph or lock; both the failed and corrected logs remain.

Local raw logs are under `runtime-recovery/merge-frame/`:
`focused-initial.jsonl`, `focused-final.jsonl`, their stderr files,
`analyze-final.log`, and `analyze-packages.log`. The root qualification workflow
will bind accepted final logs and source identities after integration.

No GitHub Actions, workflow, check-run or CI-status endpoint was queried or
awaited. This reconciliation did not stage or commit files.
