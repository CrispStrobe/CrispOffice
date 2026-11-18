# Imported-reference development checks

These are development and diagnostic attempts for the imported-reference search
and stored CSL copy increment. They are excluded from the final complete editor
cohort totals. The complete cohort run is owned by the parent workflow.

`attempt-1` ran the ten new substantive tests. Eight passed. One helper test had
an ambiguous fixture (both records had the name Amal and year 2024); the fixture
was corrected to make the intended positive/negative distinction. The other
failure found a real 559-pixel Library column overflow when opening the entire
workspace at 320 by 480 pixels with doubled text. The catalog height reserve now
accounts for enlarged text; its normal text-size behavior is unchanged.

`attempt-2` ran the same ten tests. Nine passed. The remaining test reached the
Import tab and found a real 20-pixel overflow before loading any references.
`debug-2.jsonl` records the full Flutter error: the Import column was constrained
to 256 by 1280 pixels. Import now uses naturally sized outer scrolling content,
a bounded paste field and an independently scrollable results list, rather than
estimating a fixed overall height for wrapped controls and instructions.

`attempt-3` again passed nine tests. The enlarged-text test missed the Load
references control because pending caret scrolling moved it after ensureVisible.
The test helper now settles focus scrolling before scrolling a requested
control into view, matching the helper used by the existing details suite.
The missed-tap warning remains in the raw event stream. No warning was disabled.

`layout-retest` exercised the single enlarged-text case after that harness
correction. It reached loading and found a real 73-pixel overflow in the root
workspace column. `debug-3.jsonl` records its 288 by 448 pixel constraints.
The workspace heading is now limited to two display lines, and read-only,
error and notice messages occupy a bounded scrollable region. The message text
is retained in full, replacing the previous four-line truncation.

`layout-final-retest` is the targeted check after those fixes. Consult its JSON
events and receipt for the actual result; it is not an additional suite in the
complete acceptance total.

The non-debug run receipts retain the invoked command, actual child process exit
code, timestamps and before/after SHA-256 hashes of the production files and new
test file. Raw stdout is JSON reporter output and stderr is retained separately.
`debug*.jsonl` records diagnosis only, using a temporary test copy that forwards
the original FlutterError handler while printing its complete details.

All runs use the locally provisioned Flutter/Dart runtime and `--no-pub`. They do
not use GitHub Actions or any live Zotero account. The clipboard, online catalog
and document controller interactions are controlled widget tests.

The archive also retains the first snapshot-helper unit run (10 pass; one oversized test fixture rejected during setup) and its corrected 11-pass run. These overlapping development checks are excluded from final acceptance totals.
