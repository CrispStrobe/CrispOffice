# First combined attempt — retained, not accepted

Frozen source: `911d8f43c420bd0d2bea1b9844f3f59f61d46dcf`.

The complete 68-suite run executed 1,312 cases: **1,303 passed, nine failed,
none skipped**. Strict analysis (34 paths), formatting and whitespace passed.
All 5,164 source and 11,165 runtime records remained unchanged. This attempt
is not final qualification; none of its counts is added to the accepted run.

- Two editor failures expose old reset-both-language expectations. The merged
  per-fragment control preserves the inactive DOCX language slot. The corrected
  tests explicitly check both slots, East Asian metadata, formatting, styles,
  undo/redo and DOCX round trips, with a selected language distinct from the
  initial inactive slot.
- Seven Studio footer failures use a wide RenderView but leave MediaQuery view
  metrics at the compact default. The fixture correction sets both physical
  size and device pixel ratio, preserves every wide-state assertion and adds
  explicit compact-state controls. Product footer behavior is unchanged.

The raw events, receipts, command output, case records and before/after source
and runtime inventories are retained in the indexed archive. They are never
rewritten into a successful receipt.
