# Outbox review and management — continuation

## Scope and checkpoint

Continue the durable foreground Outbox after PR #250 at
`13be50464d1b43e9f2100fb9ccc12f8fe22eb55e`.

The requested next increment is bounded, reviewable message preview/export,
safe editing into an independent draft, and explicit local resolution of an
uncertain record without resending. No opening, refreshing, reconnecting or
recovery action may submit mail. Frozen MIME and envelope fidelity, durable
attempt identity, account ownership and draft revision safety remain required.

Initial intake captures all 17 live branch heads and the 50 most recently
updated PRs. Reconcile ready continuations before implementation and refresh
again before final publication; preserve active owner branches and historical
equivalent content without overwriting later work.

Save incremental commits on `work/mail-outbox-management-20261120`, qualify
locally with the repository-pinned runtime, and merge the qualified candidate
to remote main. GitHub Actions are neither queried nor awaited.

Implementation and qualification are in progress. This checkpoint makes no
passing-test or release-acceptance claim.
