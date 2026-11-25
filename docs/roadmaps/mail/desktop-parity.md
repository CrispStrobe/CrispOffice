# Desktop mail parity roadmap

**Goal:** a native desktop mail client that can replace Outlook, Thunderbird or
eM Client for ordinary work without hiding provider boundaries.

This is a direction document, not a promise of identical UI. "Parity" means the
workflow exists, uses durable intent where it mutates mail, reports uncertainty
honestly, and has installed/live-provider acceptance. Feature names from other
clients are references, not compatibility claims.

## Where we are

| Area | State | Remaining gap |
| --- | --- | --- |
| Accounts | IMAP/SMTP, EWS, Gmail, Microsoft 365; remembered chooser; one live account at a time | Multiple simultaneous sessions, system-browser OAuth/PKCE, account discovery |
| Mailbox | Browse, cached views, resumable sync, persistent cross-folder conversation keys, search | Complete shared workspace, unified inbox, provider thread discovery |
| Organization | Read/flag, Move/Delete, Archive, remembered destinations, durable journal, local tags/categories with `tag:` search and row metadata, ordered local tag rules with preview | Tag colors/shared tags, server keyword mapping, scheduled/background rules |
| Compose | Plain-text Word surface, signatures, Quick Text, attachments, durable sender snapshots, account-owned identities and full-message templates | Rich HTML composition, inline images, cloud/EWS alias authorization, per-identity signatures |
| Send | Durable Outbox, scheduling, Undo, retry/uncertain outcomes | Background execution, provider Sent reconciliation, live SMTP transcripts |
| Search | Headers, Boolean/people fields, saved queries, cached body, archive FTS, bounded one-folder IMAP/EWS/Gmail/Graph provider search with supported fields and explicit count precision | Richer provider grammar, missing participant/body fields, multi-folder scope, indexed discovery, live adapter qualification |
| Attachments | Bounded read-only open; attach files | Attach current document/PDF, edit received attachment copy, Office workflow |
| Calendar/People | Not implemented | Calendars, invitations, contacts, address completion, mail-to-task |
| Offline | Cached headers/bodies, durable drafts/Outbox | Complete account/folder offline sessions and bounded background refresh |
| Security | TLS, host-key verification, explicit remote images, safe HTML sanitizer | S/MIME/PGP, OAuth token vaults, shared-mailbox policies |
| Platforms | macOS/iOS tested in Studio; browser store path unqualified | Windows/Linux installed acceptance, browser quota/Web Locks |

## Delivery phases

### P0 — Reliable reader baseline
- Safe formatted HTML with external resources blocked.
- Plain-text line-ending and paragraph preservation.
- Focused compose caret/focus behavior.
- Bounded MIME, attachment, remote-image and search limits.
- Compact reader metadata (From/To/Cc/Bcc/Reply-To/date-time) and bounded raw-header inspection.

### P1 — Everyday mailbox
- Shared synchronized workspace with authoritative folder lists and unread counts.
- Repository-driven foreground sessions and bounded background refresh.
- Persistent cross-folder conversations and unified inbox.
- Provider-side and indexed body search with explicit coverage.

### P2 — Organization
- Local tags/categories with exact identity and search (`tag:`).
- Ordered rules with preview, dry run, conflict handling and recovery.
- Server keyword/category mapping where providers support it.
- Bulk organization through the existing durable journal.

### P3 — Composition
- Safe rich HTML compose with plain-text alternative.
- Inline images and deterministic MIME generation.
- Multiple sender identities/alias routing.
- Full-message templates, signatures and Quick Text.
- Attach current document/PDF; edit a received attachment copy.

### P4 — Sending and reconciliation
- Provider Sent-folder reconciliation by exact submitted identity.
- Background Outbox execution with explicit lifecycle/permission rules.
- Partial-recipient outcomes only after adapter/fork support and live transcripts.
- SMTPUTF8 and byte-stream submission only through qualified paths.

### P5 — Calendar and People
- Day/week/month views, invitations, RSVP and mail-to-task links.
- Contacts, address completion and account-scoped search.
- Do not send a meeting response just because an invitation was opened.

### P6 — Enterprise and trust
- Shared mailboxes and delegated access where providers expose them.
- S/MIME or PGP only with a reviewed key lifecycle and clear status.
- Retention, audit and multi-profile administration without claiming
  MailStore Server equivalence.
- WebAuthn/Touch ID vault unlock and platform credential integration.

### P7 — Platform release
- Installed Windows/Linux acceptance and browser persistence/quota.
- Accessibility, narrow layouts, high contrast and keyboard-only workflows.
- Reproducible signed builds; TestFlight/App Store/Play evidence per product.
- No shared Quds source may import AGPL/GPL host code.

## Reference workflows

Use these as comparison targets, not pixel-copy targets:

- **Outlook:** focused inbox, rules, categories, calendar, shared mailboxes,
  conversation cleanup, offline sync.
- **Thunderbird:** tags, saved searches, unified folders, message filters,
  add-ons, local folders and profile management.
- **eM Client:** unified inbox, watch-for-reply, templates, calendar/contacts,
  translation, backup and delegated/shared accounts.

## Next five delivery slices

1. ~~Local tags/categories with `tag:` search and assignment UI.~~ Implemented.
2. ~~Ordered rules with preview and explicit local-rules-only scope.~~ Implemented.
3. ~~Persistent cross-folder conversation index.~~ Implemented.
4. ~~IMAP provider-side body search with explicit one-folder coverage and cooperative cancellation.~~ [EWS/Graph/Gmail adapters](provider-search-adapters.md) and the shared Studio search dialog now extend this with provider-specific fields, dates and count certainty; live qualification remains open.
5. ~~Multiple sender identities and full-message templates.~~ [Implemented](sender-identities-templates.md) with durable snapshots, native SMTP alias routing, explicit template replacement and primary-only EWS/cloud submission.

The [25 November extension record](extension-20261125.md) separates source and
local test evidence from live-provider, installed-platform and release gates.

## Acceptance rules

Each slice needs:

1. a user path in the native Studio host;
2. typed limits, cancellation, stale-operation and restart behavior;
3. focused core/store/UI unit tests;
4. a disposable-account live test where a provider is involved;
5. an explicit statement of what is local-only, provider-mapped or unqualified;
6. source checkpoint and rebuilt app when the user requests delivery.

No feature is called "Outlook parity" merely because a fixture passes. Provider
semantics, installed-platform behavior and live-account evidence remain separate.
