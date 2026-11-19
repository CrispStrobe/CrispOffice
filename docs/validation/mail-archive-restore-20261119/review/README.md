# Independent manifest restore review

The independent reviewer inspected the new store and native restoration code
and authored `packages/quds_mail_store/test/archive_restore_adversarial_test.dart`
separately from the implementation and its primary tests. No product-code change
was required by this review.

## Executed checks

The accepted run contains **15 passing tests, zero failures and zero skipped
tests**. Formatting and strict analysis of the independent test file also pass.
The exact test names, commands, runtime identities and raw-log hashes are in
[receipt.json](receipt.json). This count includes only the fresh accepted run;
it does not add cases from earlier attempts or other suites.

The probes verify:

- A same-size, validly redigested replacement manifest invalidates the preview.
- A manifest changed during the second decode stops before that message's
  commit while retaining the first message's confirmed progress and provenance.
- Same-size source mutation, codec substitution of original MIME, and observed
  source-directory or ancestor links cannot silently enter the destination.
- Cancellation after a confirmed commit retains both newly saved messages and
  new provenance on duplicate originals in the report; retry merges the rest.
- Cancellation before commit leaves no original, index, provenance or totals.
- Same-size corruption of an existing original, or corruption of its stored
  metadata projection, rejects the duplicate without overwriting the damaged
  row or adding provenance.
- Tighter restore limits are applied again to a previously accepted preview;
  destination quota failure rolls back all origins and index changes for the
  current duplicate.
- Failure samples remain bounded, progress diagnostics omit content and paths,
  throwing observers do not control storage outcomes, and two restorer instances
  cannot overlap on the same archive object.

[source-identities.json](source-identities.json) binds all mail-core and
mail-store Dart library files, the executed independent test, root manifest and
lockfile, store manifest, and executable validation harness. All **47 inputs**
have matching before/after hashes. This is a scoped source binding; the root
acceptance record separately qualifies dependencies and the full runtime.

Run [run_adversarial.py](run_adversarial.py) from the repository with the prepared
Dart runtime on `PATH` and `FLUTTER_ROOT` set. It resolves the installed test
entrypoint from the workspace package configuration and runs native VM/kernel
tests with the package's default SQLite native asset. It does not supply a
SQLite override or query GitHub Actions.

## Earlier attempts

The plain Dart CLI invocation stalled during implicit dependency/build-hook
resolution before emitting test events. It was interrupted; its uncounted logs
are in [cli-startup-incomplete](cli-startup-incomplete/README.md).

The first executed test run found two errors in the independent fixture: archive
diagnostics intentionally suppress completion events unless verbose logging is
enabled. Adding `verbose: true` to those two test observers made the intended
post-commit cancellation occur. The original fixture, raw logs and 13-pass /
2-failure receipt remain in [initial-fixture-run](initial-fixture-run/README.md).
No product fix was involved and those counts are not added to acceptance.

## Review scope and limits

The review covered per-message transactional provenance, deduplication integrity,
resource admission, verified original bytes, source path/manifest rechecks,
cross-profile destination ownership, failure redaction and cancellation
accounting. No blocking issue was identified in that scope.

Tests ran on Linux with native SQLite and controlled fixtures. Portable Dart
path checks still do not provide atomic directory-relative opens against hostile
concurrent path replacement; that implementation boundary is explicitly
documented. These tests do not qualify real provider accounts, native macOS or
Windows packaging, enterprise retention, or database-backup recovery.
