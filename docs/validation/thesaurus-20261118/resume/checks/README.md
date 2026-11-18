# Completed supplemental evidence

`evidence.tar.gz` contains the six original output directories `static`,
`engine`, `editor-zotero`, `spacy`, `studio` and `web-import`. Their files retain
their original bytes. `index.json` records the archive SHA-256, every member's
size and hash, and standard tar hardlinks used for identical files. Every member
was read back and verified after packaging. Compact receipts and event audits
are duplicated beside this README for review without extraction.

Extract into a new directory:

```bash
mkdir supplemental-evidence
tar -xzf evidence.tar.gz -C supplemental-evidence
```

Each original receipt uses paths relative to its cohort directory, such as
`logs/tests.stdout`. Those paths resolve directly inside the extracted archive.
The absolute command/cwd paths are the paths used during the recorded run; they
are provenance, not a claim that another host has the same directory layout.

The native cohort is saved separately in `../native`. Its original receipt
references `logs/native-acceptance.stdout`, `logs/native-acceptance.stderr`,
`logs/browser-build.stdout` and `logs/browser-build.stderr`. The corresponding
saved files are `../native/<basename>.gz`; decompress them to reproduce the
original bytes and compare the receipt's SHA-256 fields. Native test counts are
in `../native/native-test-audit.json` and the final combined receipt is
`../native/receipt.json`. `../native/test-receipt.json` is the earlier tests-only
checkpoint, preserved without rewriting its historical status.

`../browser-attempt/browser-report.json` is the later actual browser attempt.
Chromium failed before application startup; it completed no browser acceptance
steps. Neither the compiled fixture nor the successful Node import program is
an offline-browser pass.

See `../README.md` for fresh replay commands, source binding, the complete test
count and the three open release checks. The archive stores evidence only and
does not run tests or start a browser when extracted.
