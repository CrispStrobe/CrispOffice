# Integrated gate and preflight attempts

These complete compressed archives preserve every original file, including raw and compressed reporter logs, case/error lists, verification receipts, and before/after source and environment manifests. **None of these archives contributes to acceptance.** Each `*-verification.json` is an exact readable copy of the original receipt; each `*-receipt.json` supplies per-file hashes and explains the rejection. Archive metadata is normalized for reproducible packaging while original file bytes remain unchanged.

## First integrated gate: `bfa88aab`

`first-gate-bfa88aab.tar.gz` contains all 20 original files from `review-drafts-first-gate-bfa88aab/`.

- Source: `bfa88aab88a74028285619dfa07f3a81868fe59b`, tree `3418afd634efcaaa14c4712103f69ae5e817bffd`.
- 879 tests passed, two failed, zero skipped. Engine: 95 passed. Editor: 690 passed and two failed. Studio: 94 passed.
- The failing cases were `viewing keeps keyboard findings inspectable without correction` and `document protection keeps keyboard findings inspectable without correction`. The new shared selection guard blocked body findings before distinguishing body and comment handling. The root agent subsequently restricted that guard to the comment branch.
- Strict analysis found seven info-level diagnostics: two in review code and five in incoming Mail code. Formatting detected one discrepancy. Whitespace diagnostics primarily came from pristine vendored `enough_mail`, plus a Mail UI pubspec end-of-file issue. All original diagnostics remain in the archive.
- All 4,946 recorded source/fixture/configuration inputs and the recorded runtime/dependency inputs remained unchanged during this failed gate. This confirms its failure is bound to that source; it does not convert the result into acceptance.

## Initial preflight after fixes

`preflight-fixes-initial.tar.gz` contains both original files from `review-drafts-preflight-fixes/`.

The first offline lock command omitted the prepared runtime cache environment. Pub therefore could not find `flutter_lints` in its selected cache and exited 69. The lock, package configuration and runtime receipt hashes before and after were identical. The later corrected preflight is separate evidence and does not replace this failure.

## Read or unpack

```sh
tar -xzf first-gate-bfa88aab.tar.gz
tar -xzf preflight-fixes-initial.tar.gz
```

The archives contain only relative paths. No original evidence file was edited during packaging. Their uncompressed contents were scanned for common credentials, tokens, private keys, authenticated URLs and authorization values; no match or redaction was required. No Dart/Flutter command ran during packaging.

## Corrected development preflight

`preflight-fixes-corrected.tar.gz` preserves all five original files from `review-drafts-preflight-fixes2/`. With the prepared runtime environment supplied, offline lock enforcement, formatting, strict analysis of 39 files, and both viewing/protected keyboard inspection cases passed. The before/after workspace lock, package configuration and runtime receipt hashes were identical. This successful development preflight is explicitly excluded from acceptance; the next frozen-source gate is separate. Exact readable verification and per-file hash receipts accompany the archive.
