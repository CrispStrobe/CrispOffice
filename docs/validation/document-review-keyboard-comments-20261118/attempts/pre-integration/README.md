# Preserved first frozen run

This attempt tested `785f4694b6afb9904ed496b7b50ef05cc099c32b` before the late incoming merges. It completed with **389 passed, 2 failed, 0 skipped**. It is retained as a failed attempt, not accepted validation.

1. `word_review_pane_test.dart` still expected Check document to be disabled during a background check. The intended new behavior keeps that explicit action available. Only that expectation was corrected; stale-result assertions remain.
2. `studio_sheet_navigation_test.dart` sent a synthetic draft without giving its embedded editor focus. The existing input guard dropped that draft. The same failure was reproduced on the original `ec284801` baseline. The repaired fixture focuses the real editor and verifies the rejected draft before testing the switch; all original behavior assertions remain. See [the diagnosis](../../worksheet-fixture-verification.json).

`verification.json` is the unmodified runner report. `evidence.tar.xz` contains the complete unmodified output directory, including raw and compressed reporter logs, individual cases and errors, analysis/format/whitespace logs, and source/environment manifests. `index.json` records the archive and per-file SHA-256 hashes.

The accepted integrated run is recorded separately at the validation directory root.
