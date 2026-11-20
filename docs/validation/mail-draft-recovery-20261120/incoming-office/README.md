# Incoming Office local gate

Qualified source: `6dbd12f734d6f3249e7824a120ae581b1c77e94c`;
tree: `7946aa3a80e4cbf1f85a714928745d1242326ec9`.

| Selection | Result |
| --- | --- |
| Five engine import/render/transform/gradient files | 114 distinct passing cases |
| Three editor pixel/rendering files | 29 distinct passing cases |
| Eleven changed Dart files | Strict analysis and format checks pass |

No skipped cases, test errors or duplicate successful identities were observed.
The changed source/test files, root manifest, lockfile and effective package
configuration hashes are unchanged across each run. The receipts preserve exact
commands and event hashes. These are focused behavior checks, not a whole-suite,
full dependency-closure, native PowerPoint, browser, or physical-device claim.

The SDK is Flutter 3.47.8 / Dart 3.13.7; `runtime.json` records its reported
source identities. Dependencies were resolved with offline enforced-lockfile
resolution; the tracked lock remains unchanged. The direct Dart test runner
uses the version in the effective package configuration because ordinary
workspace `dart test` incurred a silent startup delay. Flutter runs use
`--no-pub`. No GitHub CI result is relied upon.

After reproducing the pinned SDK/cache and workspace resolution, run
`python3 docs/validation/mail-draft-recovery-20261120/incoming-office/run_validation.py engine`
and the same command with `editor` or `static`. The runner records the actual
checked-out commit and inputs rather than assigning later execution to this
original source. Results on later commits need their own review.
