# Mail capability extension — 25 November 2026

## Baseline and scope

Work starts from `ef120d1ce3fb3e0a4753b33876b6a3c9722e9b61` on the canonical
`CrispStrobe/quds_office_suite` repository. CrispOffice Studio is the native
host in `packages/quds_office_editor/example`. Source checkpoints are retained
on `codex/mail-capabilities-20261125`.

The existing implementation already covers IMAP/SMTP, Exchange EWS, Gmail and
Microsoft 365 accounts; durable drafts and a frozen Outbox; foreground
scheduling and Undo; cached headers and bodies; Boolean and saved searches;
durable flags, Move/Delete/Archive; local tags and previewed rules; persistent
conversation keys; and a bounded HTML reader. A connected host owns one live
account at a time.

The current desktop roadmap identifies sender identities and full-message
templates as its next composition increment. Server search is implemented only
in the IMAP host. This extension follows those existing seams instead of
introducing a second persistence or delivery mechanism.

| Area | Extension | Required evidence |
| --- | --- | --- |
| Composition model | Bounded account-owned sender identities and literal full-message templates | Validation, ownership and immutable snapshot tests |
| Durable settings | Additive SQLite migration and atomic revisioned settings replacement | Existing-data migration, round-trip, conflict and corrupt-data tests |
| Native composer | Identity selection, template management and explicit application | Widget and draft/Outbox snapshot tests |
| Provider search | Optional shared typed search port with honest per-provider fields and count precision | Request serialization, response limits, cancellation and isolation tests |
| Connected search UI | Selected-folder search for supported Exchange/cloud providers | Available-field, count-label, cancellation and stale-session tests |

## Behavior boundaries

Templates contain literal recipients, subject and plain-text body, with an
optional identity reference. Applying a template is an explicit compose action;
it does not queue or send mail and does not import attachments or reply/thread
metadata. Stored drafts and Outbox messages must retain their selected sender
snapshot independently of later settings changes.

Sender identities do not create another account or grant provider permission.
Native SMTP can submit a selected address under the connected account; the
server still decides whether that sender is authorized. Exchange/cloud hosts
retain their existing primary-address submission restriction until alias
submission is separately qualified.

Search remains bounded to one explicitly selected folder. Provider search
syntax and fields differ: unsupported fields must remain unavailable rather
than silently broadening the query. Counts must distinguish exact totals,
provider estimates and unknown totals. Results use the existing reader and
account/session checks. Search itself does not mutate mail.

## Verification record

Implementation and verification are in progress. Final executed commands,
results, checkpoint identities and remaining acceptance gates are recorded
here before the review handoff. Historical roadmap test totals do not qualify
these new changes.

Live provider interoperability, installed desktop/mobile acceptance, browser
persistence and a signed release remain separate gates. This source work does
not claim they have passed.
