# Loaded conversations — folding and observed counts

Updated 21 November 2026. This continuation extends the existing loaded-message
ordering with explicit folding, accessible controls and observed group counts.

## Scope and user path

The shared `MailMessageList` offers **Conversations** when the host supplies
account-scoped RFC threading headers. Studio supplies these headers in its
IMAP, EWS/cloud, cached-mailbox and synchronized-folder lists. This workflow
operates on already loaded headers and does not contact a provider.

1. Enable **Conversations** to bring related loaded messages together. Every
   group starts expanded, preserving the previous individual-message view.
2. Use the disclosure beside a group to collapse it. The first member under
   the current local ordering remains visible; expanding restores its loaded
   children. Clicking a message row still opens that individual message.
3. Read the group's **loaded**, **unread** and **flagged** counts. These describe
   the members that match the current loaded-header search and filters,
   including children hidden by folding. They are not server totals. Unknown
   read or flag values are excluded from observed counts; the adjacent help
   indicator reports each unknown-state count separately.
4. With the message list focused, Left collapses and Right expands the
   cursor's conversation in LTR. Arabic/RTL mirrors these keys. Up/Down and
   Home/End continue to navigate visible individual messages. Disclosure also
   exposes its expanded state and explicit expand/collapse accessibility
   actions.
5. In hosts offering bulk actions, **Select shown** and Ctrl/Cmd+A select only
   visible message rows. Collapsing immediately removes hidden children from
   the checked set. Expanding does not silently reselect them. No conversation
   control authorizes an action on an entire group.

Controls and loaded/observed/unknown counts are localized in English, German
and Arabic. Long text remains bounded in compact layouts; the disclosure is
usable with enlarged text. Turning **Conversations** off restores the existing
local sort without grouping. Within the same host scope, the user's folding
choice follows stable account/member identities through sorting, filtering,
metadata refresh, added replies and replacement of the first visible member.
Changing account/folder scope or recreating the list resets the option and
folding choices. Hosts with a separate scope for each loaded page retain that
page boundary.

## Identity, safety and preservation contract

The pure-Dart API is `groupMailConversations(MailConversationEntry list)`,
exported from `quds_mail_core`. It accepts a loaded, optionally filtered and
sorted snapshot and returns immutable groups in first-seen order.

- Group solely on explicit RFC Message-ID, In-Reply-To and References links.
  Never infer a conversation from matching subjects, senders or timestamps.
- Use strict bracketed ASCII dot-atom IDs, at most 254 code units, preserving
  case. Invalid References tokens invalidate the entire chain; apparently
  valid IDs are not extracted from comments or malformed input.
- Admit at most 64 References entries per row. IMAP raw References fields are
  limited to 8,192 characters before splitting; oversized lists are ignored.
  Every loaded input row retains its distinct mailbox-row ID.
- A missing ancestor can link two loaded replies without fabricating its body
  or row. Cycles and duplicate RFC IDs remain bounded.
- Groups never join across host/profile/account namespaces. Unscoped
  third-party rows remain isolated by default. Folding state uses account and
  local member IDs, never RFC Message-ID, a sequence number or a row index.
- Filtering and sorting precede grouping. Aggregates use only those filtered
  loaded members. Folding changes visibility without changing identities,
  provider ownership or the host's opened-message state.
- Every disclosure invalidates old interaction callbacks and open bulk-menu
  snapshots. Hidden children cannot be opened or included in a new action
  through a retained callback. A busy host disables disclosure. A changed
  host/session revision continues to clear checked rows under the existing
  selection contract.

## Local qualification

The earlier ordering checkpoint's unexecuted-test warning is superseded for
these exact cohorts. This continuation used the genuine repository-pinned
Flutter 3.47.8 / Dart 3.13.7 runtime and locked dependencies. The
[current work record](../../validation/mail-client-next-20261121/README.md)
records the executed checks, source checkpoints and raw local evidence.
GitHub Actions were not queried or awaited for acceptance.

| Cohort | Passed | Relationship |
| --- | ---: | --- |
| Pure-Dart conversation grouping | 10 | Separate core suite |
| Conversation widget suite | 18 | Included in the shared-list total below |
| Four shared-list widget suites | 108 | Includes the 18 conversation cases, plus navigation and both bulk-action suites |
| Conversation localization | 3 | EN/DE/AR; included in the six-case conversation/Boolean localization run |

Every listed cohort finished with zero failures and zero skips. The counts
above are overlapping scopes and must not be added into a unique grand total.
Changed Dart paths also passed analysis and formatting checks.

The widget cases cover default expansion, filtered observed/unknown counts,
hidden-selection pruning, keyboard selection and disclosure in both text
directions, stale row/disclosure/bulk-menu callbacks, account/scope isolation,
sort and membership changes, metadata refresh, busy state, accessibility
actions, and a 240-pixel RTL layout with 2× text. The core suite covers explicit
links, absent ancestors, malformed data, duplicates, cycles and account
isolation. Tests use synthetic messages; they do not establish live-provider
header availability or installed-platform acceptance.

Focused local replay commands from the repository root:

~~~bash
cd packages/quds_mail_core
dart test test/conversations_test.dart
cd ../quds_mail_ui
flutter test --no-pub test/message_list_conversations_test.dart test/message_list_test.dart test/message_list_bulk_test.dart test/bulk_message_list_test.dart
cd ../quds_office_editor/example
flutter test --no-pub test/studio_mail_conversation_strings_test.dart test/studio_mail_boolean_search_strings_test.dart
~~~

## Remaining acceptance boundaries

This increment folds and summarizes loaded conversations. It does not fetch
missing ancestors, discover other folders, deduplicate cross-folder copies,
persist a conversation index, or add server-side/whole-mailbox threading.
Absent or unusable threading metadata leaves rows separate instead of guessing
links. Folding state is transient view state, not an account-level preference.

The next conversation boundary is a persistent account-scoped index maintained
alongside synchronized membership, including tombstones and UIDVALIDITY resets.
Bounded queries need cross-folder provenance and visible partial-cache coverage
before supporting an account-wide conversation workspace. Named cached-header
searches are the companion organization increment in the current work record;
indexed body search and capability-gated server discovery remain separate work.
Durable move/delete, tag/category and ordered-rule workflows still require
uncertain-operation recovery, followed by broader composition and send controls.

## Remote preservation and intake

The continuation started from fork main
`01517de8886ef7bd24947894be5dc823d0328869`. Its
[initial intake](../../validation/mail-client-next-20261121/intake.md) verified
all 27 captured fork branch heads, the latest 100 PR heads and four upstream
heads as ancestors of that baseline, with no open PRs. The conversation feature
was incrementally checkpointed to remote `work/mail-client-next-20261121` at
`c9a3475541a58778b0db26f4d1b4516e9e51e20a`. Later concurrent intake and final
publication belong to the current work record; an initial ancestry snapshot is
not a claim that no later branch can contain new work.
