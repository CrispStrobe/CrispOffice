# Loaded-mailbox range selection and searchable addresses

This increment advances everyday triage in the
[ordered mail parity plan](README.md#desktop-mail-parity-ordered-increments).
Its source and regression tests are committed. Fresh Flutter execution and
visual qualification remain open because the local executor was unavailable;
see the [work record](../../validation/mail-keyboard-triage-20261121/README.md).

## User workflow

In a mailbox that supports checked-message actions, focus the message list or
check a message. Use the following controls:

| Input | Result |
| --- | --- |
| Up/Down, Home/End | Move the keyboard cursor without opening a message; establish a new range anchor |
| Space | Toggle the cursor's checkbox and establish a new anchor |
| Shift+Up/Down, Shift+Home/End | Extend or contract a checked range from the anchor to the cursor |
| Shift+Space | Select the range ending at the cursor |
| Shift+click on a row or checkbox | Select the visible range ending at that row without opening it |
| Ctrl/Cmd+A or Select shown | Check every currently shown row |
| Escape or Clear selection | Clear the checked set |
| Enter or ordinary row click | Open the explicitly chosen message |
| Selection help | Open the localized keyboard and range-selection guide |

The range follows the currently displayed ordering. It includes both endpoints.
Reversing direction can shrink it or cross the anchor. Messages explicitly
checked before a range starts remain checked when the range contracts; only
the active range's additions disappear. A normal cursor move or checkbox/Space
toggle ends that range and establishes a fresh anchor.

Selection alone does not submit any operation. Use **Actions for selected
messages** to explicitly mark the checked messages read/unread or flag/unflag
them through the existing host-owned durable command workflow.

## Scope and lifecycle

- Ranges cover only currently shown rows. Unloaded messages, filtered-out
  messages and collapsed conversation children never join them.
- Query/filter edits, sorting, conversation folding and every host widget
  update end the active range and discard its anchor. The next range starts
  from the current visible cursor, with no remembered hidden endpoint.
- Existing checked-row pruning and scope/revision clearing remain in force.
  An account/folder change cannot retain a prior account's range.
- A host refresh may retain compatible explicit checks, but a new range does
  not reuse the previous ordering or transient selection baseline.
- Read-only hosts have no checkboxes or selection help. Busy or
  refresh-required hosts cannot extend/toggle selection or dispatch a batch.
  Normal local browsing keeps its existing behavior.
- Pointer callbacks retain the current interaction generation. A callback
  captured before a query, sort, fold, host update or selection change cannot
  start a new range. Every range update invalidates older popup snapshots.
- The list handles these keyboard commands only while its own focus subtree
  owns the event. The search field keeps normal text/IME editing. Modified
  Ctrl/Cmd/Alt combinations do not become Shift range commands.
- Plain cursor movement and range movement reveal virtualized rows. Range
  state uses stable row identities rather than persisted list indexes.

The shared `MailMessageList` supplies this behavior wherever a host opts into
the existing `onBulkAction` callback. Cached/synchronized views that are
read-only do not acquire remote mutation permissions. English, German and
Arabic host help uses the existing scrollable, direction-aware dialog.

## Synchronized header search consistency

The synchronized mailbox's loaded-header projection now includes both the
display name and address for every **From**, **To** and **Cc** entry. For example,
`from:writer@example.test` still matches a sender displayed as
`Alice Author <writer@example.test>`, and `to:"Project Team"` can match the
recipient's visible display name.

Empty or absent names fall back to the mailbox address. Multiple senders and
recipients are included. Bcc and private transport-envelope recipients never
enter this projection. Search still inspects the loaded header page only; it
does not read bodies, download messages, synchronize a folder or contact a
provider. The same projection is used in connected and offline synchronized
browsing.

## Verification boundary

New widget regressions exercise range contraction/reversal, independent checks,
pointer and keyboard input, filtering/sorting/folding, stale callbacks,
scope/revision changes, disabled/read-only states and explicit batch snapshots.
Connected/offline synchronized-search cases exercise all visible address groups,
Bcc exclusion and the absence of provider/body-reading side effects.

These are prepared regressions, not claimed passing executions. The work record
separates source review and remote readback from Dart/Flutter tests, analyzer,
formatter and visual checks. No GitHub Actions result is used as a substitute.

## Next ordered boundaries

1. Execute the focused UI and Studio regressions, then the existing shared
   list/search/conversation cohorts with the pinned SDK and locked dependencies.
2. Add explicit saved-search folder sets: stable account/mailbox identities,
   existing-definition compatibility, no silent scope broadening, per-folder
   coverage, deduplication and stale-scope recovery.
3. Complete repository-observed unified navigation and durable move/delete
   before expanding automatic rules and background account work.
4. Continue richer identities/composition, provider Sent reconciliation and
   installed-platform/live-provider qualification.

The comparator references inform workflow design; this increment does not
claim exact key bindings or complete parity across products:
[Thunderbird message selection](https://support.mozilla.org/en-US/kb/keyboard-shortcuts-thunderbird),
[Outlook message-list shortcuts](https://support.microsoft.com/en-us/accessibility/outlook/keyboard-shortcuts-for-outlook),
[Thunderbird saved-search folder scopes](https://support.mozilla.org/en-US/kb/using-saved-searches),
and [eM Client Search Folders](https://www.emclient.com/webdocumentation/en/10.0/emclient/Content/Favorite%20Folders/About%20Search%20Folders.htm).
Checked 21 November 2026. The broader current comparison also considers
[eM Client 11](https://www.emclient.com/blogpost.aspx?id=842), including its account
selection for Global folders and command discoverability.
