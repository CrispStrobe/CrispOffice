# Latest-main Mail integration — 20 November 2026

**Accepted source:** `58cc4283b35b29a4036528f65ee0590230d583f6`  
**Accepted tree:** `1cba111d27e6b0699ffa65c7df5be2bbb53e8e59`

The accepted result is **1,471 unique cases across 70 files**, with zero accepted failures or skips. **228 additional Node executions** recheck existing case identities; they are not added to the canonical count. This is a source-bound union, not a claim that every case ran at one commit.

| Accepted cohort | Execution source | Cases | Files |
| --- | --- | ---: | ---: |
| Retained core, transport and loader cases | `c62338c65571aa399da5592455b651fa5c6a9317` | 606 | 33 |
| Unchanged successful focused suites | `4163368b63b35414f25c3830fcc49055e6088953` | 694 | 31 |
| Complete corrected fixture suites | `58cc4283b35b29a4036528f65ee0590230d583f6` | 171 | 6 |
| **Canonical union** | Accepted at `58cc4283…` | **1,471** | **70** |

The shared Studio layout suite includes eight Word-only cases already represented in Word evidence. Do not add these counts to another package without comparing case identities. `accepted-test-cases.json` records the actual execution source for every case; `accepted-union.json` records replacement and retention boundaries.

## What this integration preserves and adds

The fixed incoming chain is PR275 reconciliation `f67c18574176d34f48ddab14918aee5a787c3843`, reader/session main `5e7e4d24284954603a0a5951699bea870ad1955f`, and tab/account main `329d03914808589d3e7650fa870df15a2408afe2`. Integrated source `4163368b…` preserves both the prior evidence checkpoint and incoming main as parents. `58cc4283…` changes six test files only. Earlier incoming branches, raw evidence and alternative test naming remain source-bound in their existing packages.

The stronger c623 bulk runner, coordinator compatibility, immutable ordering, typed results, stop problems and captured account/session/namespace guards remain. Compatible quota regressions are retained without duplicating identical competing core suites. Cloud apply results use conservative mutation certainty, including uncertain HTTP 410; send rejection handling remains separate. EWS guards recheck captured identity before applying a result.

The native host gains the incoming warm-session and ribbon behavior. Resume preserves the active reader; the saved-account connection attempt is bounded. Remote images require an explicit user action. The host considers at most eight approved HTTP(S) image candidates, refuses redirects, limits streamed bytes to the smaller of 4 MiB and the reader attachment budget, accepts static PNG/JPEG dimensions within the remaining pixel budget, and bounds each operation with a 15-second timeout. Reader retirement closes the owned client and stale responses cannot publish into a replacement message.

Two concrete reader repairs accompany the intake: every HTML/plain rebuild re-admits external images against the combined CID/external count and pixel budget, and only successfully admitted image URIs lose their blocked-image placeholder. Failed, blocked and unrequested alternatives retain their text. Regression cases cover cumulative-budget toggling, mixed image outcomes, source immutability, one-pass image input, selection/search rebuilds, streaming cancellation, redirects, stale readers and timeout behavior.

## Original failures and the correction

The complete initial 416 aggregate remains **failed**: 847 logical passes and 18 failures, plus 131 passing Node rechecks. Its raw logs, receipt, case identities and seals are preserved. All 171 executions in the six affected files are superseded by the complete follow-up, including 153 original passes; individual passing fragments are not used to conceal failed suites.

| Corrected file | Follow-up cases | Cause and preserved assertion |
| --- | ---: | --- |
| `studio_layout_theme_test.dart` | 9 | The obsolete MenuBar expectation becomes scoped ribbon/Home assertions with traffic-light geometry; the 17,845-byte prefix containing eight Word tests is identical. |
| `studio_mail_credential_backend_switch_test.dart` | 7 | Removed File-menu interactions target the keyed disabled ribbon button; ownership, stale callbacks and persistence assertions remain. |
| `studio_mail_lifecycle_test.dart` | 1 | Close targets the outer dialog ribbon; pending picker, disposal and ignored late-result checks remain. |
| `studio_mail_test.dart` | 81 | The narrow-window helper scrolls the lazy horizontal ribbon before targeting its Close control. |
| `studio_mail_workspace_test.dart` | 59 | A controlled response stream explicitly asserts cancellation; reader identity and ignored stale-image assertions remain. |
| `studio_saved_mail_test.dart` | 14 | Close targets the saved-message view's own control; original octet, disposal, picker and file-read assertions remain. |

The one renamed case is recorded explicitly: `pending account save also disables storage in the File menu` becomes `pending account save disables storage in the ribbon`.

The workspace failure was diagnosed, not suppressed by advancing time. A scratch probe demonstrated that `Stream.value.cancel()` uses a completed root-zone future whose callback escapes Flutter's fake-async pumping. An explicit async `onCancel` originating in the test zone completes during fake microtask processing and removes the pending timeout. The archive includes the exact probe, output and hashed SDK source locations. No production cleanup code changed.

## Verification and limits

Both runs sealed all 5,838 tracked source inputs, 6,188 dependency files and runtime inputs before and after execution. The verifier checks all 17,509 Git blob bindings across the c623, 416 and 58cc manifests; the final correction changes exactly the six approved tests. All 33 retained test blobs match c623. Core, MIME, store, native transport, enough_mail and loader inputs are unchanged. The only transport-production delta is the cloud mutation-evidence block; retained cloud-store cases use controlled successful nonmutation pulls, and unsupported JavaScript cases select unchanged stubs. Package roots, lock pins, shared SDK files and SQLite bytes match; native asset registration differs only by worktree path.

Formatting and strict core, transport, UI and Studio analysis pass. Studio analysis and all changed-file formatting pass again after correction. The 26 final PNGs are byte-identical to the individually reviewed c623 images; the exact comparison and earlier visual review are preserved. No new visual result is inferred from a filename alone.

These are local VM, headless Flutter and selected compiled-JavaScript checks using Flutter 3.47.8, Dart 3.13.7, package:test 1.31.1, Node 24.22.3 and sqlite3 package 3.9.1 with pinned native SQLite 3.54.1. No GitHub Actions result, live mailbox, real credential store, provider deployment or operating-system-specific end-to-end behavior is claimed. SDK binaries, caches, compiled kernels, native libraries and JavaScript outputs are excluded from the archive.

## Reproduce or inspect

Run the following from this evidence folder, `docs/validation/mail-latest-main-integration-20261120`. Supply an absolute repository path with the named commits available. The read-only verifier needs Python with PyYAML; runtime reproduction additionally needs Node and access to the pinned dependency archives.

```sh
sha256sum -c SHA256SUMS
mkdir /tmp/quds-mail-evidence
tar -xJf mail-latest-qualification.tar.xz -C /tmp/quds-mail-evidence
python3 verify_mail_latest_retention.py \
  --repo /absolute/path/to/quds_office_suite \
  --baseline-accepted /tmp/quds-mail-evidence/baseline/accepted \
  --baseline-sealed /tmp/quds-mail-evidence/baseline/sealed \
  --baseline-config /tmp/quds-mail-evidence/baseline/configuration \
  --focused /tmp/quds-mail-evidence/initial \
  --focused-config /tmp/quds-mail-evidence/runtime-provenance/configuration \
  --correction /tmp/quds-mail-evidence/correction \
  --out /tmp/quds-mail-recount
```

For fresh execution, prepare a separate clean checkout at 58cc4283 and new runtime/output directories:

```sh
python3 reproduce_flutter_runtime.py --repo /absolute/path/to/clean-checkout --runtime /absolute/path/to/new-runtime
python3 qualify_mail_latest_delta.py \
  --repo /absolute/path/to/clean-checkout \
  --runtime /absolute/path/to/new-runtime \
  --out /absolute/path/to/new-results \
  --expected-head 58cc4283b35b29a4036528f65ee0590230d583f6 \
  --format-base c62338c65571aa399da5592455b651fa5c6a9317
```

That default command reruns the 865-case focused corpus and 131 Node rechecks. The exact historical commands, including the 171-case correction selection, are in the original receipts. Earlier raw execution of the 606 retained cases is preserved in `../mail-final-integration-20261120`; this archive includes its accepted identities, seals and hashed package provenance so the retention boundary is independently checkable.
