# Document review and comparison

The Word workspace combines proofing, tracked changes, comments and a read-only
two-document comparison. Review never rewrites the source document just to show
differences.

The full interaction and engine contract is preserved in
[Document review details](document-review-details.md).

## Open review

| Command | Shortcut | Result |
| --- | --- | --- |
| Spelling / Writing | `F7` | Proofing findings beside the document |
| Review changes | — | Pending tracked changes |
| Compare | — | Two-document comparison workspace |
| Check document | `F7` | Runs ordinary and configured manual providers |

The pane stays beside the page on wide layouts and below it on narrow layouts.
**Escape** closes it and returns to writing.

## Writing pane

- Check-as-you-type runs after a short typing pause and prioritizes the active
  paragraph.
- Spelling, grammar and style findings use different underline colours.
- Clicking a finding shows suggestions; right-click keeps the normal edit menu.
- Filter by category, navigate findings, replace, ignore an occurrence, word or
  rule, or add a personal word.
- Corrections are undoable and bound to the document revision.
- A finding from an older revision cannot modify newer text.
- Manual-only providers are not started by ordinary typing; use **Check
  document** or F7.

The status bar shows waiting/checking/incomplete coverage and pending-change
counts. An unavailable checker is never shown as a clean result.

## Language and checking

The globe button opens **Language and checking**:

- selection scope: **Selected text**;
- collapsed caret: **Current paragraph**;
- **Use inherited language** removes a direct override;
- **Check this text** excludes quotations, identifiers or code;
- **Document language** changes the default for the whole document.

Each real change is one undo step and survives DOCX save/reload. Imported run,
paragraph and style language inheritance stays consistent between live checking
and save/reload.

## Tracked changes

- Insertions and deletions remain visible while editing.
- Accept or reject individual changes or reviewed groups.
- Comments and replies stay inline in Studio.
- Deleting or editing reviewed text invalidates only the affected review state.
- Footnotes and endnotes can be reviewed alongside body text.

Pending changes do not prevent ordinary editing. The review side is a view over
the model; it does not create a second editable copy.

## Compare two documents

**Review → Compare** opens a read-only workspace:

- both inputs remain unchanged;
- differences are grouped by body, tables, headers/footers, notes and comments
  where supported;
- navigation moves between changed regions;
- the active document is not modified and no revision spans are inserted.

Large documents use bounded comparison and report incomplete coverage rather
than pretending the result is complete.

## Engine API

Hosts can use the review controller and comparison service directly. The public
contract covers:

- proofing session lifecycle, scheduling and revision invalidation;
- applying suggestions and ignored-word state;
- tracked-change accept/reject;
- comment threads and replies;
- comparison input capture, result navigation and disposal.

See the [details](document-review-details.md) for the exact classes,
host integration steps and migration notes.

## Limits

- Comparison is reviewed for supported Word content, not arbitrary OOXML or
  binary equality.
- Optional manual grammar models require an explicit check.
- Provider availability and language coverage vary by host.
- A read-only comparison does not merge documents or produce a patch file.
- Local tests do not replace installed-desktop or accessibility acceptance.
