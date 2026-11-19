# Preserved earlier attempts

Only the final accepted mail and incoming receipts contribute to the release
total. Earlier checks remain separate and are never added to that total.

- The first broad mail preflight stopped before tests because eight incoming
  GUI/branding/sample files were not canonical under the pinned Dart formatter.
  Strict analysis and whitespace checks passed. All eight were formatted;
  `format-reconciliation.json` proves each result is exactly the formatter's
  output for the prior bytes. That attempt ran **zero tests**.
- The next mail run passed all native, shared UI and Studio mail cohorts, but
  an additional Node selection incorrectly included `archive_query_test.dart`.
  That suite imports native `sqlite3`/`dart:ffi` and belongs on the VM. It was
  already fully covered by the native cohort. The corrected harness retains
  the portable manifest suite and declared browser-error suite on Node.
  This earlier run also observed temporary VBA CLI fixtures while a parallel
  incoming-engine qualification was running. Its aggregate input-stability
  condition therefore failed. Its counts are excluded. Final mail acceptance
  runs after incoming-engine fixture work ends, against the same product code
  and the corrected committed harness.
- The independent adversarial suite's first executed attempt omitted the
  `verbose: true` diagnostic option in two cancellation fixtures. The fixture
  options were corrected; no product-code change was required. The initial
  results and sources are retained in `review/`, and only the final tests as
  included in accepted mail-store coverage count toward release acceptance.
- Initial plain `dart test` launches entered implicit dependency resolution
  before reporting cases. Those starts were interrupted and count no tests.
  Accepted VM/Node runs invoke the installed test entrypoint with explicit
  package configuration; Flutter tests use `--no-pub`.
- Earlier incoming GUI/VBA test runs were superseded after the required
  formatting checkpoint. They are retained under `incoming/attempts/`; the
  final incoming receipt counts each selected case once.
