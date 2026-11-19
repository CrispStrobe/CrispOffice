# Verified local runtime — 19 November 2026

The archive retains the scripts, checksums, full retained-input manifest, exact
archive identities and preparation logs for the frozen Flutter 3.47.8 / Dart
3.13.7 runtime. All 176 hosted package archives were matched to their locked
hashes; the workspace lock is unchanged. Node and the default SQLite 3.54.1
native asset are bound. FTS5 preparation succeeded.

The initial SQLite probe from the dependency-free workspace root did not invoke
the native hook and failed. The same preparation from the declaring store
package succeeded. Both attempts are preserved; neither is a product test.

See `runtime-complete.json`, `binding-receipt.json`, and `index.json` for exact
identities. Runtime paths describe this execution environment; the reproducible
bootstrap accepts a fresh destination. Source and raw product qualification
receipts are preserved separately. GitHub Actions were not used.
