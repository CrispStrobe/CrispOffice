# Native Zotero engine — final integrated-source qualification

**Passed: 244 cases across 8 suites, zero failures
or skips.** Strict analysis with `dart analyze --fatal-infos` passed for
2 changed production/test/harness files, with no issues.

Source commit: `c6941f9ae82c74bf0f8d8a2a15d2a7a2c47c9f4f`.
Source tree: `4b9bc320788c30daf5b17bd8868ad8a651c86fa3`.

Explicit selected-field source context, native citing protocol/session behavior, writing-position preservation, transferred-clone isolation, staged research-note insertion and simple-field persistence.

Both commands ran from `packages/quds_office_engine` using the configured
Dart 3.13.7 SDK. [validation.json](validation.json) contains the exact argument
lists, actual process exit codes, timings, runtime and package-configuration
hashes, and 21 explicit source/test/manifest hashes.
The complete tracked source identity is the recorded Git tree. HEAD, tree and
all explicit inputs remained unchanged through execution. The executable-source
status was clean; concurrent package changelog documentation edits are excluded
from that check explicitly.

[tests.log](tests.log) and [analysis.log](analysis.log) retain complete raw output
and are hashed in the receipt. [preflight.json](preflight.json) records an initial
launcher stop before any test ran: a broad clean-tree guard encountered an editor
changelog documentation edit. Narrowing that guard required no product source
change and does not represent a failed test execution.

These counts belong to this final-source gate. Earlier overlapping engine,
Mail or Word runs must not be added as additional unique cases. No GitHub Actions
query/wait or installed Zotero/Word/LibreOffice acceptance was performed. The
previously retained Word VM/JavaScript portability evidence was not rerun here.
