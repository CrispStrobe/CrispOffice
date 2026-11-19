# Refreshed incoming mail acceptance

Local integration HEAD: `983cfc3decfe639f9e5b9033f95617c361f847c8`.
Incoming mail head: `5611724b7b40cf0c86aa180f0d3f1316d5a77c9f`.
Incoming GUI head: `e2d2aec69a4a2b6c7da6159c929563f1166ff94d`.

The reconciled mail source retains both the incoming manifest decoder preflight
and the locally fixed exact encoded-byte accounting. The full mail store suite
passed **469 tests** on the Dart VM, including the incoming staging-directory and
decoder allocation regressions and our seven exact-byte regressions. Strict
analysis of the reduced mail core/store workspace and targeted formatting passed.
All **84 input hashes** remained unchanged throughout the acceptance run,
17:09:48–17:10:24 UTC on 19 November 2026.

A supplemental JavaScript/Node run passed all **six portable manifest boundary
tests** on the same accepted source. Its output and a supplemental receipt entry
are retained. Those six are the same regression cases already counted in the VM
suite, exercised on an additional backend.

`receipt.json` records exact commands, input/log hashes and scope. Source and
dependencies remain live-linked through the isolated scratch workspace. No
production dependency configuration changed; the default sqlite3 3.9.1 native
hook was used. The source SHA-256 of `archive_export_models.dart` is
`a270ccb5415a42918621a7ea0b4de286a912e21a7efa56879873295a2a7eabd3`.

The latest observed mail head at 17:09:30 UTC was
`9bdef4895922ae74f6275e421af5665552d18b4e`; its only new edit was the same export
ordering fix already included in the tested source. Both PR #205 and PR #206
were open drafts. The mail author's source-freeze README explicitly said final
acceptance was pending; no final author receipt was present. See
`../remote-audit-second-refresh.json` for exact status and GUI API review.

This receipt qualifies the mail core/store Linux VM paths and portable manifest
JavaScript tests. It does not qualify Flutter Studio widget behavior, native
AppKit window/menu behavior, or the complete combined GUI implementation. A quick
read-only GUI API review found no obvious API mismatches; that is separate from
execution. GitHub Actions were not queried or awaited.
