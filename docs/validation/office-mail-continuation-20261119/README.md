# Office and Mail continuation — 19 November 2026

## Initial reconciliation checkpoint

This continuation starts from remote main `b070e228a749e22cc8ce2098029a76ab5fb8eccb` and retains both unmerged current continuations: `10bd0cc4` (including `1b6d280b`) and `004b2ad6` (including `c63558c0`). Their source changes and historical qualification evidence are preserved together.

The one merge conflict was in Studio Mail tests: the earlier saved-message and language-cycle tests are retained as `studio_saved_mail_test.dart`, and the newer account/session tests retain `studio_mail_test.dart`. Both behaviors will be reconciled in the host before fresh qualification. This checkpoint is not represented as a passing integrated source.

The next bounded work restores account-free saved EML reading alongside native accounts, repairs the browser import boundary and the remaining Mail composition/submission semantics, and validates the resulting frozen source locally. Historical test counts remain attached to their actual execution sources. No GitHub Actions status is queried or awaited.

## Implementation checkpoint

Saved EML reading is restored through an explicit saved-message view, retaining full/compact mode, exact source octets, delayed picker/file cleanup and current account state. A conditional entry keeps the native account code outside the browser entry. Narrow mailboxes use a list/detail view.

Native on-demand reads now use the bounded Quds IMAP provider with a session-owned credential snapshot and an exact mailbox path/UIDVALIDITY/UID identity. Mailbox envelope listing remains the existing high-level client; this is not the durable repository-driven R1 workspace. Insecure-origin discovery is refused before clients or credentials are used. Public errors and legacy protocol print output are contained.

The composer uses the shared Word RenderBox editing surface and produces an immutable plain-text draft. Recipient/header/size checks precede submission. MIME uses quoted-printable encoding. SMTP submission passes one explicit recipient and disables concurrent Sent-folder append. Unconfirmed submission retains its draft in the current session and requires an explicit delivery-check acknowledgement before another attempt. No durable outbox or exactly-once delivery is claimed.

Focused development checks and independent review are being completed. They do not yet qualify this combined source. The committed native and Node plans plus run_validation.py define the forthcoming frozen gate. GitHub Actions remain outside the process.

## Preserved qualification attempts

The complete first aggregate attempt at `97393efd` is preserved under
[`attempt-97393efd/`](attempt-97393efd/README.md). All nine native groups
completed with 1,859 passing cases and strict Dart analysis/formatting passed,
but the whitespace gate found one extra blank line at the end of the independent
auditor. The aggregate failed, and its later Node/Mail browser stages did not run.
Its native counts are not carried into an accepted later total.

The auditor's single EOF blank line was removed in `dfb28229`; the full baseline
whitespace check passed before starting another gate. That run was deliberately
interrupted with external exit 130 when remote main introduced material new Mail
actions at `666e9a2e`. Its original receipt remains `RUNNING` without rewriting;
the separate interruption notice records why execution ended. Complete original
bytes and the interruption record are under
[`attempt-dfb28229/`](attempt-dfb28229/README.md).

Earlier focused development runs, including failed regression attempts, are
preserved separately under [`development/`](development/README.md). The 90-file
archive is independently compared with its original bytes and reproducibly
rebuilt. Dirty development runs receive no invented exact source commit and
contribute zero cases to current aggregate acceptance.

## Newer main reconciliation

Checkpoint `e1b94285` retains newer remote main `666e9a2e` as an actual ancestor.
The only new product changes introduced by that reconciliation are the incoming
reply, forward and mark-read actions; the newer Word, SMTP, browser, saved-reader
and lifecycle safeguards on this branch remain intact. PR #191 was reopened
after the concurrent main integration closed it without merging its remaining
work. Reply/forward now quote the authoritative loaded plain-text message,
preserve complete Unicode scalar values at the explicit 8,000-scalar limit,
and protect retained uncertain drafts from implicit replacement. An explicit
confirmed discard removes only the session draft. HTML-only quotation, threading
headers and attachment forwarding remain outside this increment.

Mark-read uses the existing bounded `MailSetRead` provider path, which checks the
frozen mailbox, UIDVALIDITY, exact UID, read-write access and resulting flag.
The foreground operation is serialized, cancellation and stale session checks
remain in force, and no automatic write retry is introduced. These repairs and
their focused regression cases precede the next frozen qualification.
