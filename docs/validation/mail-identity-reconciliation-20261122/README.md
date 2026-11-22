# Mail identity transitions — implementation and local qualification

## Baseline and preservation

Work starts from remote main `b2bba1638924237435460e4238d4bd98c407fc3a`.
The [initial intake](intake.json) captures 30 fork branches, four upstream
branches, and the latest 100 updated fork pull requests. All 29 non-main fork
tips and all four upstream tips are ancestors of that main; both repositories
had no open pull requests. No older work needs to be reapplied.

Incremental implementation is saved to
`codex/mail-identity-reconciliation-20261122`. The final publication will recheck
remote history, reconcile concurrent work, and merge through a normal pull
request. GitHub Actions are not an acceptance gate for this task; verification
runs locally and the final record will distinguish completed checks from any
unqualified behavior. No branch protections or required checks are changed.

## Selected milestone

Continue the first ordered task in
[the membership recovery contract](../../roadmaps/mail/membership-recovery.md):
preserve authoritative identities returned by successful IMAP and EWS moves,
and reconcile exact retained cache membership atomically with the receipt.

- Preserve existing unit-result provider interfaces and custom host adapters.
- Add optional typed move evidence, bounded and bound to the original operation.
- Capture IMAP COPYUID and EWS replacement identities without guessing from
  subjects, RFC Message-ID, or disappearance of the old identity.
- Persist evidence with the durable command journal and preserve it on restart.
- Apply cache changes only while the captured local state is still current;
  retain the acknowledgement and require refresh when local state has changed.
- Preserve historical uncertainty, non-replay behavior, dated coverage, account
  isolation, bodies, drafts, Outbox payloads, archives, and sync cursors.
- Exercise protocol edge cases, transactional rollback, restart, stale writers,
  host account rebinding, and compatibility before merging.

## Qualification status

Implementation and local qualification are in progress. This initial checkpoint
makes no passing-test or full Outlook/Thunderbird/eM Client parity claim.
