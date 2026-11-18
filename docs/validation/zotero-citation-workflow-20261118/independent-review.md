# Independent citation-workflow code review

Recorded at **2026-11-18T16:04:43.018461+00:00**. Git HEAD at review: `ee88b8f809e6640ab6218584215c6f1b0f8f2bd2`;
the working-tree source snapshot is bound by the hashes below, including files
not yet committed at review time.

## Outcome and scope

No unresolved blocking issue was found in the inspected integration after the
two error-handling repairs and search-scroll correction below. Review covered
source identity grouping, source/option ownership, staged selection and ordering,
custom formatted-text preservation, current-source preview validation, stale
editing targets, read-only behavior, cancellation, selection bounds and large
metadata failure paths.

This was **source and test-definition inspection**. The reviewer did **not**
execute product tests, static analysis, a native application or a live Zotero
account during this review. The new regression definitions were inspected after
the fixes; their execution and the full-cohort acceptance belong to the separate
validation receipts. This note contributes no test count. GitHub Actions were
not queried or awaited.

## Findings resolved during review

### 1. Catch source-catalog limit errors before opening a route

`word_zotero_dialog.dart::_compose` originally resolved all available sources
inside the dialog's `WidgetBuilder`. More than 10,000 distinct validated aliases
can make `ZoteroSourceResolver` throw. A build-time exception escapes the
workspace's asynchronous `_run` error handler and produces a Flutter error
widget instead of the recoverable workspace message.

**Resolution inspected:** available-source grouping now runs once inside
`_run`, before `_showReview`. The already resolved list is passed to the composer.
The integration regression `oversized alias catalog reports an error before
opening the composer` supplies 10,001 validated aliases and checks the message,
absence of the composer, and unchanged document revision/history.

### 2. Keep the composer open when a combined citation exceeds metadata bounds

`word_zotero_composer.dart::_apply` originally created the final citation in an
unguarded button callback. Individually valid source snapshots can collectively
exceed the engine's 1 MiB citation metadata bound. That exception also lies
outside the parent workspace's pending route await.

**Resolution inspected:** `_apply` catches `FormatException`, shows its message
in the composer and retains the complete editable draft. The regression
`oversized combined citation keeps its draft and can be repaired` adds two
600 KiB source payloads, checks that the unsuccessful Apply keeps text and both
sources, removes one source and retries successfully. Original source snapshots
remain unchanged.

### 3. Start a new source search at its first result

The composer source chooser previously retained its scroll offset when search
text changed. A long filtered result set could therefore begin partway down.

**Resolution inspected:** the chooser owns a `ScrollController`, resets it on
query edits and disposes it with the search controller. The regression
`filtering scrolled source candidates starts at the first match` exercises a
scrolled candidate list before searching.

## Other inspected behavior

- Linked-source grouping uses only validated Zotero URI aliases and follows
  transitive bridges. Equal bare CSL IDs or item keys do not merge different
  libraries. Offline records with different stored metadata remain distinct;
  equivalent JSON map key order does not create spurious copies.
- Existing citation occurrences retain separate stable keys through reorder and
  removal. Their edited locator, prefix, suffix and author options stay with the
  occurrence. Newly added/reused sources clear earlier occurrence and processor
  options while retaining source metadata and URI aliases.
- Source-picker results remain staged until Apply. Applying the cited-source
  picker retains the positions of other-tab selections and checks the captured
  document/caret target and selected-item identities. Citation writes pass the
  existing `_write` target/editability checks.
- Read-only and Track changes flows can inspect and copy stored data while the
  insertion controls remain disabled. Cancellation returns no document mutation.
- Custom text requires review after changing source membership/order. Imported
  formatted text is retained only when the original source sequence and visible
  cache are unchanged; changed membership/order discards the obsolete formatted
  representation. Restoring the original sequence can preserve it.
- The connected single-source preview receives the current sole source, requires
  a validated Zotero URI, and supplies `expectedCitationUri` to the existing
  validated client request. Pending preview work disables source edits and does
  not update a disposed composer.
- Additional sources are bounded by the shared 20-source policy; existing
  larger imported clusters remain editable without truncation. Rejected additions
  do not prevent deselection. Source choice and inspection use lazy result lists.

## Inspected source binding

Hashes identify the reviewed bytes; later formatting or source edits need a new
binding before this note can describe them.

| File (under `packages/quds_office_editor/`) | SHA-256 |
| --- | --- |
| `lib/src/embed/word_zotero_sources.dart` | `5d14798d62f158464f0a75e00d35ed8a83ad478ab828014ab3d57f6a266f4d74` |
| `lib/src/embed/word_zotero_document_sources.dart` | `ac3e031757606457e3a90f47488ea592dd51a06e17adf9556e31eaed3d060ce4` |
| `lib/src/embed/word_zotero_composer.dart` | `aa60679b1bdcfacf904f58844fb301fa0c41280e5df74e7eb1b1dbb0aa3eb7c4` |
| `lib/src/embed/word_zotero_dialog.dart` | `ec39d217b19e2feced3d0b43115cd6105975882ac42775e3b59c1706cebad505` |
| `test/word_zotero_document_sources_test.dart` | `c65d15cbc34e28e75316c53ab37d6ef3336c5369403501cc90983ca7ce909ec8` |
| `test/word_zotero_document_source_picker_test.dart` | `8cfa5aa68b92bdd198eb8c089db67d0b3ccc8d10454dac28afd63f9e7ce65232` |
| `test/word_zotero_composer_test.dart` | `16f4ad7274b180776940893be8e4ae3e9dff71e2c6ba9cfdf412cbb757f235ac` |
| `test/word_zotero_document_reuse_test.dart` | `5234d171f495fdac5a196fb4e85d94129aa564b1788c3aa9c9c9597ae813251b` |
