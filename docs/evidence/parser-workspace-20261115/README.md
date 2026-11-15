# Canonical parser mirror on the Quds workspace graph

Saved Quds source: [`4e8c8f80f206e93be8530a94da478e06c0f87608`](https://github.com/CrispStrobe/quds_office_suite/commit/4e8c8f80f206e93be8530a94da478e06c0f87608). Mirrored canonical parser source: [`08296edbee08da013a8ff718798972552ccd03f7`](https://github.com/CrispStrobe/legacy-doc-parser/commit/08296edbee08da013a8ff718798972552ccd03f7).

**All 4,132 tests passed across the complete 144-suite unit inventory**, with zero failures, errors, skips, missing or unexpected suites and a successful terminal machine event. The source inventory was checked against every tracked `test/**/*_test.dart` before execution. Counts were derived from raw JSON events.

This is a fresh run in Quds' workspace dependency graph: **XML 7.1.0, test 1.31.1, archive 4.7.1 and lints 6.1.0**. The standalone parser's separately saved run used XML 6.6.1/test 1.33.0; its receipts remain scoped to that graph. Workspace resolution and the shared development constraints are the documented pubspec adaptations. All **865 Git entries in `lib/`, `test/` and `tool/`** exactly match canonical parser source `08296edb`; the complete comparison is archived.

Before/after snapshots confirm unchanged source files, HEAD/tree, tracked declarations, resolved lock/config/graph inputs and recorded tool hashes for this run. Exact resolution files are included and their bytes were checked against the source-bound before snapshot. No dependency resolution occurred during qualification.

The archive contains the command, machine events, per-suite result, inventory, before/after snapshots, tool hashes, runner, resolution profile and exact source identities. Every member and the complete archive inventory were verified against `artifacts-manifest.json`.

The scope is all tracked unit files in `packages/legacy_doc_parser/test`. This does not claim integration tests, a separate external Word corpus, native Word UI execution or application-wide qualification. No GitHub Actions result was awaited.
