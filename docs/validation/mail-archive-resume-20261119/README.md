# Durable mail archive restoration — implementation checkpoint

This work extends the verified manifest-restoration milestone with durable,
destination-owned progress. It starts at `596430dcb816dd418204d62e78f4dc518afdc0e1`,
which contains remote main `caf378f40fd5bda50f504a6816404d01d8bbb8f8` and the
inspected VBA arrays and Studio layout/theme branches (#210 and #211).

## Planned behavior

- Commit a bounded restore receipt in the same SQLite transaction as each
  original, searchable projection and complete provenance set.
- After cancellation or process termination, resume only unfinished items.
  Revalidate confirmed destination originals and their provenance before
  reporting them as previously committed; do not parse their source EML again.
- Bind progress to the exact manifest bytes and destination archive. A changed
  manifest is a different selection. A matching export can be moved without
  losing its progress. Keep source files unchanged.
- Keep full verification reruns available and distinguish current-run saves,
  duplicates and verified bytes from resumed confirmations and bytes.
- Upgrade existing version-one archives additively, impose progress-storage
  bounds, and let users forget progress without removing archived messages.
- Explain these choices in English, German and Arabic with narrow/RTL coverage.

## Acceptance status

Implementation and local qualification are in progress. Historical evidence
retained from other milestones is not counted as a fresh result. Acceptance
will cover schema migration, transaction rollback, interrupted-process resume,
manifest changes, destination corruption, quotas, UI behavior and the incoming
VBA/layout/theme changes. GitHub Actions are not awaited or used as a gate.

The initial reconciliation record freshly checks inherited historical
equivalence mappings and records the inspected remote heads. A final refresh
will account for remote movement before publication.
