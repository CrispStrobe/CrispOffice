# Final transport test plan review

The final native plan registers **35 test files** in four groups, including 21 inherited protocol/shared-client suites and the new real-loopback TLS suite. The Node plan registers **9 files** in three groups. All named files exist in integrated main. All **23 changed transport or fork Dart files** are explicitly included in both strict analysis and formatting. Core/store acceptance is recorded separately on the same final source.

The original T12 gap is resolved in the plan by `test/native_tls_test.dart`. Its final 14 development cases cover stalled implicit TLS and STARTTLS cancellation/deadline/retry, successful local TLS and IMAP exchange, concrete certificate/hostname validation failure, manual socket behavior, and deterministic partial-write controls. The peer-observed closure occurs before fixture teardown. The three strengthened evidence assertions and retained development receipts are detailed in `transport-review.json`.

No actionable plan gap remains. No Dart/Flutter was run by this reviewer. Final source-bound qualification is still a separate root gate; the reviewed development logs do not replace it. Partial-write controls use a deterministic RawSocket fixture and do not establish OS backpressure or actual Windows execution. Local TLS tests do not establish live account/OAuth-host interoperability.

All 37 author-reviewed source paths match integrated main. The runner binds every tracked packages/apps/third_party input, including the local TLS certificate/key fixtures.

- Native plan SHA-256: `95a423703ecbd552a840e6fe0d4471875b8e79f88cdee3bc8d2c675ebbb9aa13`
- Node plan SHA-256: `742e24efef60b50cd51ee1f2c810f83941bf7e32f5cd2cb9e6fab11157981c94`
- Reviewed author commit: `cdcfe878f01263f52c935d9ae0a90e6113a07e3f`
- Source manifest SHA-256: `5dc61c9d20bf2227236b489799b77c2765a24b04e8e7d6f8625e7186a0ebff48`

Exact plan groups, paths and integration metadata are recorded in `transport-test-plan-review.json`.
