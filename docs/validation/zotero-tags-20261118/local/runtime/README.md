# Local runtime provenance

The [runtime receipt](runtime-ready.json) records genuine pinned Flutter 3.47.8 /
Dart 3.13.7, unchanged workspace manifests and locks, live current-source links,
and the setup-only 31-test smoke. That smoke is excluded from acceptance totals.
The [archive receipt](pub-cache-receipt.json) records SHA-256 verification of 162
official hosted package archives. Paths in these original receipts identify the
execution workspace; they are not additional delivery dependencies.

Exact dependency and runtime file hashes consumed by the accepted tests are
retained in each cohort's before/after inventories. The existing exact workspace
lock is docs/validation/proofing-20261116/integration-resume/workspace-pubspec.lock.
No tracked manifests, locks, dependencies or framework files were changed.
