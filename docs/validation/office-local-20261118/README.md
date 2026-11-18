# Quds Office local qualification — 18 November 2026

## Saved source and reconciliation

Source checkpoint: `401d012657881a54727d58bc35e537faa45d5fbe`. The continuation starts from main `482e0817`, retaining PRs #151/#152 and the later German grammar/formatting changes. It adopts the isolated civil-date conditional-format repair and its eight regression tests from `2bfac9b2`, and restores missing historical evidence without changing that evidence’s original source attribution. See `remote-review.md` and `remote-review.json` for the incoming audit of 190 branch heads and 152 PR heads.

Remote branch: `codex/office-local-qualification-20261118`. Each checkpoint uses a non-forced expected-head update and `[skip ci]`. GitHub Actions are neither queried nor awaited. The source checkout stays detached and clean; evidence is published through a separate index, preserving source/HEAD stability without a duplicate checkout.

## Current qualification status

Final qualification is **in progress, not accepted**. The source-derived selection has 224 unique test files: engine Zotero 19, editor Zotero 13, engine integration 138, editor integration 37, Harper 3 and GECToR 14. It retains all 179 historical baseline files. Required gates also include five strict analysis commands, formatting and Python controls, 17 Node suites, two editor-example smoke tests, the calendar regression under UTC/Berlin/Los Angeles, 40 retained document consumers, five boundary cases, five existing focused frame/field consumers, and the serial native 1/2/4/8-thread sweep.

The native recovery archive records exact library, quantizer, model and pack hashes, restoration of 27 pinned Python packages, all eight public font fixtures and 3,504 matching document-runtime files. It is a setup receipt, not a fresh product qualification. Limited shared-disk capacity requires compact Flutter extraction and release of reproducible build intermediates; every adaptation will be recorded before the qualification input snapshots.

No final passing total is inferred from previous runs. Two inherited private-PDF early returns remain explicitly excluded from substantive counts. Native DOCX rendering uses LibreOffice; no Microsoft Word result is claimed.
