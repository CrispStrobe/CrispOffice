# Unified retained-folder navigation — work record

## Intake

Baseline: `2eecf9aec2c7d1f979064448b911b516d3f56c73` on 22 November 2026.
All 21 observed fork branch heads and all four upstream heads were ancestors of
this baseline. Both repositories had no open pull requests. Recent PRs and
exact observed heads are retained in [intake.json](intake.json).

Work is checkpointed to `work/mail-parity-20261122-next`. GitHub Actions are
not an execution dependency; local commands and their actual results will be
recorded here before publication. Branch protection and workflows remain intact.

## Intended increment

The existing Cached mail reader lists saved foreground browsing windows. It
omits folders represented only by durable synchronized memberships. This
increment brings both into one account-scoped, repository-observed folder
catalog while keeping their different coverage and pagination visible.

- One folder entry per exact account/folder identity, including sync-only folders.
- Explicit browsing-window versus synchronized-header source selection.
- Bounded synchronized pages and safe repair after membership removal.
- Reader identity and stale-callback guards across folder/source/page changes.
- Credential-free, provider-free local reading with honest missing-body states.
- Existing browse-only host compatibility and English/German/Arabic controls.

This does not add automatic network sync, a cross-account unified inbox, or
durable move/delete dispatch. The latter remains the next ordered milestone:
IMAP `\\Deleted`, Gmail Trash labels, EWS changed identities and Graph immutable
identities require distinct reconciliation behavior. No destination identity may
be guessed and uncertain writes must never replay automatically.

## Validation

Pending implementation and fresh local execution. Earlier test counts in the
repository are historical and are not evidence for this increment.
