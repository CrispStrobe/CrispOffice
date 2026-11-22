# Accepted combined engine gate

Source: `6ba219a03a9933eded77980f9d7cdbd118183ee1`.

All **620 tests in the 21 requested suites passed**, with zero failures, errors,
or skips. Loading/hidden events are recorded separately and excluded from this
count. The run includes all 38 new malformed-field recovery cases and the
existing 1,500-citation adjacency stress test. Elapsed process time was 107.179
seconds.

The command used the verified Flutter 3.47.8 bundled Dart 3.13.7 runtime, JSON
reporting, and concurrency four. The Git head and all recorded source/dependency
inputs remained unchanged throughout the run. Source inventories include all
engine library/test inputs, the local legacy parser source, root/package
manifests, locks, analysis configuration, and the resolved package configuration.
Resolved dependency manifests are captured separately.

`receipt.json` records the exact command, runtime, source, timing, process exit,
counts and log hashes. `test-identities.json` contains every counted result;
`excluded-loading-tests.json` preserves excluded harness events. The full raw
stdout and stderr are retained as gzip files. `errors.json` and
`unparsed-stdout.json` are empty. The inherited malformed-note expectation failure
from the earlier source is retained separately under
`../../attempts/pre-integration/engine/`.

These are local source tests. They do not establish installed Zotero, Word,
LibreOffice or platform acceptance, and no GitHub Actions result was awaited.
