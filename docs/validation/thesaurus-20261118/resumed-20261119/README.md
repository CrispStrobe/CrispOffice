# Resumed qualification — 19 November 2026

## Recovery and integration checkpoint

The interrupted continuation did save `7e4adc08`. Its nine indexed evidence
archives passed byte-for-byte verification. The complete 129-suite replay was
not saved and remains pending at this preparation checkpoint.

`ff0775cb` reconciles the latest captured Notes (`840362cd`) and Zotero
(`0abd0e59`) follow-ups. Main (`690e6ac8`) and Mail (`086e15b7`) were already
included. All 391 captured refs are accounted for: 363 by ancestry and 28 by
14 independently replayed historical equivalents. The final ancestry audit is
in `incoming/integrated-audit-ff0775cb.json`.

The merge keeps the stable Flex layout from `3847d5f4`, retains both tracked
and untracked Notes IME/undo cases, combines responsive selection checks, and
preserves incoming real-font fixtures and hit-tested Zotero Notes selection.
The 1,789 application, asset and manifest entries reviewed against `7e4adc08`
are unchanged. New test/support files are treated as new qualification inputs.

## Local runtime

The restored Flutter 3.47.8 / Dart 3.13.7 archive passed its full official hash.
176 hosted archives were checked against the combined workspace/tooling locks.
Both offline enforced-lock resolutions passed and the repository lock stayed
unchanged. Exact scripts, receipts, command logs and host checks are in
`evidence/runtime-recovery-20261119.tar.xz`, with its member index alongside it.

## Qualification runner

The replay runner now records failed preflight attempts, validates positive
concurrency/timeout settings, rejects malformed suite records and missed-tap or
overflow diagnostics in either output stream, and stops descendant processes
on timeout or interruption. Four concurrent suites run within each sequential
cohort by default. Fourteen controls include a real timeout test whose child
ignores SIGTERM. They all passed before the source freeze.

Replay with a new output directory:

```sh
python3 docs/validation/thesaurus-20261118/reconciled/run_targeted.py \
  --runtime /absolute/verified-runtime \
  --output /absolute/new-combined-evidence \
  --concurrency 4 --timeout 1800
```

The plan selects 42 engine, 73 editor, ten Studio and four Mail UI suites.
Analysis and formatting cover 29 changed Dart paths, including the new font
helper. Original failed/interrupted evidence remains in its historical folders.

## Work pending at this checkpoint

- Execute the 129-suite affected-source union and its analysis/format checks.
- Independently audit the final results and publish the exact source/evidence
  relationship without double-counting overlapping historical runs.
- Keep the actual offline browser, installed Studio/real OS IME, and independent
  human linguistic review gates open. This host still denies AF_UNIX sockets
  and lacks the native compiler/GTK/display setup. The linguistic packet remains
  unreviewed.

Validation is local. GitHub Actions are not queried, dispatched or awaited.
