# Loaded conversation ordering — 21 November 2026

## Scope and user path

This increment adds an opt-in **Conversations** chip to the shared
MailMessageList when the host supplies account-scoped RFC threading headers.
It brings related loaded messages together in the existing list and displays
a count beside the first row of a multi-message group. Each message remains a
separate selectable/openable row. Turning the chip off restores the current
folder's prior local sort.

The option is now supplied by Studio's IMAP mailbox, EWS/cloud mailbox,
cached mailbox and synchronized-folder message lists. The shared UI is
localized in English, German and Arabic. It does not contact any provider.

The pure-Dart API is groupMailConversations(MailConversationEntry list), exported
from quds_mail_core. Its input is a loaded, optionally already filtered and
sorted snapshot; its immutable output is a list of groups in first-seen order.

## Identity, safety and preservation contract

- Group solely on explicit RFC Message-ID, In-Reply-To and References links.
  **Never guess** a thread from a matching subject, sender or timestamp.
- Use strict bracketed ASCII dot-atom IDs, at most 254 code units, and preserve
  case. Invalid References tokens invalidate that entire chain; do not extract
  apparently valid IDs from comments or malformed input.
- Admit at most 64 References entries per row. IMAP raw References fields are
  limited to 8,192 characters before splitting, and oversized lists are
  ignored. Every loaded input row has a distinct mailbox-row ID.
- A missing ancestor can link two loaded replies without fabricating its body
  or a row. Cycles and duplicate RFC IDs are safe.
- Groups never join across host/profile/account namespaces. Studio's durable
  header rows encode the full namespace. Unscoped third-party rows remain
  isolated by default.
- Filtering and sorting run **before** grouping. Hidden rows cannot be selected,
  opened or included in an action through the conversation control. A toggle
  fences previously opened bulk menus via the existing interaction generation.
- Changing folder/account scope resets the option. Existing keyboard navigation,
  message opening, bulk receipts and loaded counts continue to use individual
  mailbox-row IDs.

## Explicit limits and next acceptance boundaries

This is **not** a full Outlook/Thunderbird conversation view. The feature only
reorders already loaded rows; it does not collapse groups, aggregate unread
counts, fetch missing ancestors, discover mail in other folders, deduplicate
unified cross-folder copies, persist conversation identifiers, or implement
server-side/whole-mailbox threading. Stale/absent provider headers yield single
rows rather than guessed links.

Recommended next steps, in order:

1. Persist and incrementally maintain an account-scoped conversation index
   alongside synchronized header membership, including tombstones and
   UIDVALIDITY resets. Add bounded paginated queries and cross-folder
   provenance so incomplete local coverage stays visible.
2. Add expandable/collapsible conversation rows with accessible keyboard
   controls, explicit per-message actions and aggregate unread/flag counts.
   Preserve selection and scroll position across incoming sync snapshots.
3. Implement saved live search views using the same account/folder provenance;
   extend to indexed body search and server capability-gated discovery.
4. Complete durable move/delete, tag/category and ordered rules workflows with
   uncertain-operation recovery; then schedule/undo-send and rich composition.

## Validation status

Source and focused tests are committed to the remote work branch, with
regressions for absent ancestors, duplicates, invalid References, account
isolation, sorting, filtering, visible-only bulk actions and scope reset.

**The tests have not been executed in this session.** The execution environment
has no Dart or Flutter SDK, and GitHub Actions were deliberately not used as a
blocking gate because the queue is starved. Do not describe these tests as
passing until a qualified toolchain actually runs them.

Commands for an equipped local checkout:

~~~bash
cd packages/quds_mail_core && dart test test/conversations_test.dart
cd ../quds_mail_ui && flutter test test/message_list_conversations_test.dart
flutter test test/message_list_test.dart
cd ../../packages/quds_office_editor/example && flutter test
~~~

The last command is broad and should be run with the repository's established
bounded runner if machine resources are constrained. A real provider smoke test
must separately check IMAP/EWS/cloud header availability; synthetic tests do
not prove a provider returns every threading field.

## Remote intake disposition

At intake, fork main was 2f90a0c8f21499d5a1113943971cb7379183885c.
The 23 other active fork branches were all ancestors (ahead=0) of that main.
There were no open PRs. Upstream
MohammedAsaadAsaad/quds_office_suite/main was
15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba; its comparison against the
fork showed zero upstream-only commits, so there was no missing upstream work
to replay. The new work was checkpointed directly to
work/mail-parity-next-20261121 before publication to main.
