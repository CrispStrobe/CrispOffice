# Language host and Word session lifecycle evidence

This separate capture preserves the later Studio language-host and Word-session
lifecycle work. The earlier `development-evidence` archive and its index remain
unchanged.

## Preserved records

The archive contains **26 members: 25 regular files and one directory**, totaling
**282,837 original file bytes**. It preserves all four raw JSON reporters and
stderr files, their source/command receipts, the original and repaired product
sources, the test sources, both strict-analysis logs, final formatting output,
and the development summary with exact static-adjustment diffs.

| Record | Passed | Failed | Skipped | Meaning |
| --- | ---: | ---: | ---: | --- |
| Incoming host baseline | 0 | 10 | 0 | Controlled reproduction of disposal/ownership, public feedback and cleanup failures |
| Incoming Word sequence subset | 1 | 3 | 0 | Controlled reproduction of disposed-session results, stale replacement-detector results and stale publication |
| Repaired host suite | 10 | 0 | 0 | Focused working-source host lifecycle verification |
| Complete Word language suite | 11 | 0 | 0 | Four new ownership cases and all seven incoming routing/apply/undo/review-pane cases |

The host checks ownership after asset loading, synchronous factory return and
identifier loading. Disposal releases the owned identifier and clears public
state. Late success, failure and cleanup cannot notify the stopped host.
Current load failures expose one fixed public message.

Word detection rejects completion after disposal or detector replacement. Its
proofing pass checks generation, document and configuration after every awaited
detection, including discarded results, before publishing. Disposing a session
also releases its detection caches and external detector reference.

These are **controlled baseline and unfrozen development observations**. They
do not establish aggregate acceptance, real native/provider operation or browser
Worker/Wasm execution. The bundled model asset was verified against its pinned
hash within the host suite.

After both runtime suites passed, strict analysis requested removing a redundant
test import and adding braces around an existing conditional. Both exact tested
source copies and final static-adjustment copies/diffs are preserved. All four
final strict targets pass. The final combined source run separately establishes
whether the final source is accepted; these counts are not promoted or added to
that result.

## Archive and verification

- Compressed file: `language-host-evidence.tar.xz`, **26,288 bytes**.
- Compressed SHA-256: `2ff4e3e88a92a390ba28376d3ccc350e2e67e86e0f0264046276fdbdce7f8cf4`.
- Decompressed tar SHA-256: `d3c358d426392d62176d86fa96e0cc54be802c942c6893ada206de4b9afe946f`.
- [Complete index](language-host-evidence.index.json).
- [Original-byte and reconstruction verification](language-host-evidence.verification.json).

The archive tool compared every file to its original bytes, verified the exact
member set, lengths, hashes, modes and nanosecond modification timestamps,
reproduced a second complete archive byte for byte, and verified reconstruction.
The archive is below 1 MiB and therefore needs no splitting.

From the repository root, verify using only the committed files:

```bash
python3 docs/validation/office-validation-recovery-20261119/development/archive_development.py verify \
  --index docs/validation/office-validation-recovery-20261119/development/language-host-evidence.index.json
```

For an original-byte comparison while the captured source directory is still
available, add:

```bash
  --source language-host-development=/workspace/scratch/1db61dbeed56/language-host-development
```

To reproduce into a new empty destination, use the same tool's `pack` command
with `--name language-host-evidence` and that exact `--source` argument. Source
paths may be remapped explicitly while preserving the indexed file metadata.
No GitHub Actions run, job, queue or status was queried or awaited.
