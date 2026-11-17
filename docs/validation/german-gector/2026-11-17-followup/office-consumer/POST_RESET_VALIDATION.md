# Post-reset Office validation

## Current verified source results

The recovered pure Dart environment ran **703 substantive Office cases across 51 files**, with **zero failures and zero skips**. Strict analysis of the engine completed with `No issues found!`. Runtime engine/parser libraries and every selected test were byte-compared with the reviewed checkout, and all sealed inputs stayed unchanged during the run.

This is a new execution with its own raw evidence. It does not recreate the lost 694-case addendum or the lost pre-reset consumer artifacts.

## Additional correction

Continuous sections previously compared authored comment references from default headers and footers only. First/even variants with otherwise identical text could therefore reuse a master page containing the preceding section's comments.

The writer now includes references from all six emitted header/footer stories in the existing master-reuse key. Four focused cases cover first/even headers and footers. Each verifies that equal references reuse a master, different references select a new master, annotations are retained, and source IDs stay unchanged. All four fail on the preceding writer with the expected missing `mp1`, then pass with the correction. They are included in the 703-case total, not additional to it.

The recovered header-order and later-frame regressions are also included. Their test formatting has been restored with the pinned Dart formatter.

## Independent consumers: acceptance remains partial

The reconstructed harness generated five actual ODT packages and converted each to PDF and DOCX in the installed LibreOffice build. All **20 XML parts pass the pinned ODF 1.3 schemas in Jing**. Lxml accepts 19; the remaining nested page-count disagreement is preserved diagnostically.

Four of five strict semantic fixture checks pass. Actual rendered native field values retain bold/color and hyperlinks; malformed-field fallbacks remain visible; first/even/default header/footer text appears on the expected three pages; and the empty native field remains in the preceding column.

The bookmark fixture retains and visibly renders the later frame, but the reopened DOCX omits the frame's `FrameMark` range. The original generated ODT contains the complete range. The strict fixture remains a failure while independent round-trip and plain-ODT controls determine whether the loss occurs on import or export. This checkpoint does not claim full desktop-consumer or DOCX round-trip qualification.

## Runtime and evidence

The source archive is `post-reset-validation-1.tar.xz`, SHA-256 `ab499065bd648c0c0c84b9bba317aa58891cc0d4fbdac6c457164d71fb524655`, 252,792 bytes. Its adjacent index lists every member and checksum. It includes:

- Raw four-case fail-before and pass-after streams, commands and input seals.
- The complete 703-case stream, source bindings, input seals and summary.
- Strict analysis output.
- Both consumer attempts, generated ODT/PDF/DOCX files, XML, PDF coordinates, commands and source identities. The first attempt exposed a launcher configuration issue before generation; the second contains the five-fixture observations.
- The tested writer and changed tests, the preceding writer, reconstructed harnesses, reduced workspace manifests, lockfile and runtime receipts.

The SDK is the same Dart 3.13.7 binary as the earlier work. A separate two-package workspace contains unchanged engine/parser sources; production manifests are unchanged. All 55 retained dependency lock entries exactly match the prior frozen lock. The Flutter editor/Studio and native model cohorts were not rerun in this smaller environment.

Telemetry is suppressed before execution through `DASH__SUPPRESS_ANALYTICS=true` and `CI=true`. Dartdev commands additionally use `--suppress-analytics`; direct VM scripts preserve their original arguments because that flag belongs to Dartdev. Both launcher revisions and the rejected-flag consumer attempt are retained. No analytics opt-in or opt-out command is used in this recovered run.

## Native evidence auditor

The restored thread-sweep auditor was rerun against the preserved historical receipt. All **23 controls pass**, including deliberate corruptions of aggregates, counters, segmentation coverage and semantic rows. The new receipt is `../native-threads/thread-sweep-audit-controls-recovery.json`. This validates the auditor; it does not measure current-source native speed or quality.

No GitHub Actions were started, polled or awaited.
