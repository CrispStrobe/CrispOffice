# Studio recipient groups and Reply all — 2026-11-19

## Subsequent integration qualification

All 219 selected Mail host cases and 6 focused transport cases passed in the integrated Zotero workflow qualification. See the [19 November integrated report](../zotero-workflow-20261119/README.md) for exact source, raw evidence and local validation limits. The checkpoint record below is retained as originally written.

## Scope and publication policy

Continue from remote main `2170791c9250d72c9df31a065408365f9b50abaa`.
Save incremental checkpoints on `work/mail-continuation-20261119`, then merge
the reviewed candidate into remote main. GitHub Actions are neither awaited
nor used as an acceptance gate. Local checks and source review are recorded
for this continuation; historical results are not new validation.

The initial remote inventory contained 16 branches and no open PR in the latest
100 updated PR records. The newer `integrate/recent-pptx` head
`5c3f9d7fd4531dfac7c0e49fba1827c39e17caf6` is a direct child of the starting
main and was fast-forwarded onto this continuation before mail changes. Its
original commit is preserved. Independent review identified slide background,
theme and rich-text editing compatibility risks that require local regression
checks and corrections before the final merge.

## Mail increment

- Bounded comma/semicolon-separated bare ASCII mailboxes in To, Cc and Bcc.
- Stable deduplication across groups, with exact local parts and case-insensitive
  DNS domains; the first spelling and To-before-Cc-before-Bcc precedence win.
- Visible To/Cc MIME headers and an explicit complete envelope; no Bcc header
  in the canonical outgoing MIME. Existing provider-specific Bcc submission
  mechanisms remain responsible for their delivery API representation.
- Reply all uses Reply-To (or From), original To and Cc, excludes the connected
  account identity and never reads source Bcc. Unsupported/oversized source
  recipient lists fail explicitly rather than selecting a silent subset.
- Existing plain-text quote, reply-thread metadata and uncertain-send
  acknowledgement remain part of the foreground draft contract.

This remains session-only composition. Durable drafts/outbox, attachments,
SMTPUTF8, display-name address-list parsing, alias discovery and live-provider
interoperability are outside this increment.

## Validation status

Implementation and regression work are in progress. The pinned Flutter 3.47.8
runtime is being prepared locally. No test result is claimed by this checkpoint.
The final receipt will distinguish executed checks from remaining boundaries.
