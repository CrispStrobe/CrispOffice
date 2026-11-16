# English/German proofing continuation — 17 November 2026

## Initial integration and first implementation checkpoint

The starting head is `becfa07c1be62429a8bcf78910aa1ffb46248b1a`, which preserves all 128 unique commit heads from 189 audited fork/upstream branch and pull-request references. See `reconciliation.json`. The previous proofing handoff, rendering continuation, Zotero recovery and latest spreadsheet work are all ancestors. No histories were discarded or force-pushed.

The pinned Flutter 3.47.8 / Dart 3.13.7 and Rust 1.100.0 toolchains have been restored locally from verified upstream distributions. All 162 pinned Pub archives were verified against the existing workspace lock. No runtime dependency or language-data source was changed. See the setup and cache receipts.

This checkpoint unifies protected URL/email/backtick ranges across English and German hyphenation, preserves German alias equivalence across styled runs, and excludes identifiers and contraction fragments from automatic German breaks. The shared range scanner retains original UTF-16 coordinates, balanced URL brackets and surrounding prose punctuation. Backtick pairing uses a bounded pass over delimiter runs.

The first Dart suite passed **28 tests** (`english_hyphenation_test.dart`, `german_hyphenation_context_test.dart`, `proofing/proofing_text_ranges_test.dart`). An initial failure exposed the modifier-letter apostrophe case and two incorrect expected test offsets; the retained failed log and passing rerun make that correction visible.

German spelling/grammar and Harper improvements are in progress. This initial checkpoint does not claim final integration, native/Wasm, or host acceptance. No GitHub Actions queue is used or waited on.
