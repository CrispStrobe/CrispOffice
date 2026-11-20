# Foreground bulk read and flag actions

The concurrently developed bulk-flags and bulk-actions branches are reconciled
in one implementation and one [foreground bulk action contract](bulk-actions.md).
That contract covers frozen visible selections, explicit read/unread/flag/unflag
assignments, four per-message outcomes, provider mutation evidence, cancellation,
localized progress/details and the cache boundary.

See the [integration and local validation record](../../validation/mail-bulk-actions-20261120/README.md)
for source intake, reconciliation decisions and accepted local evidence.

The next milestone is durable sessions and a remote-command journal; account-wide
search and conversations follow that persistence boundary.
