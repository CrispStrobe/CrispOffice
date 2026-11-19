# Attempt at 08336f71 — runtime passes, strict analysis rejected

Frozen source: `08336f71b273eb81a4f2652328ad1c91c08e048c`.
All 25 native/VM suites completed: 382 passed, zero failed, zero skipped.
Formatting, whitespace and source/runtime stability checks passed. The full
gate is rejected because strict analysis found 21 issues in two incoming
test files. The four Node suites had not launched.

- The unused support fixture imports the platform facade, whose default web
  class does not expose the native `clientFactory` seam. Importing the native
  dialog explicitly makes this native fixture's dependency accurate.
- The protocol-output containment tests intentionally invoke `print` twenty
  times. A file-local `avoid_print` annotation documents those probes; no
  production lint policy or executable test body changes.

The two-file repair changes no application code, plans, test selection or
assertions. The rejected raw events, original diagnostics, receipts and
independent audit remain in the indexed archive. These executions contribute
zero to a subsequent accepted run.
