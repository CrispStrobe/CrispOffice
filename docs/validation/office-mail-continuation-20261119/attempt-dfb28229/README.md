# Interrupted qualification attempt — dfb28229

**This attempt was externally interrupted and remains incomplete. It contributes
zero cases to accepted qualification totals.** Original receipts retain their
original status; no run is relabelled as successful or completed.

## Source and interruption

The original outer receipt records source
`dfb2822953156496f60efd62f68ff4dc885c93ab`, tree
`c17be0ddbd11ff414e10ee6bbbf4783f6d6b4d3b`. Its saved status is **`RUNNING`**,
with no final completion timestamp. Four Python control phases and the core/store
phase have successful outer entries; the native phase has started but has no
accepted outer result.

The root coordinator reported an external interruption with **process exit
code 130** after core/store and the start of native checks. Remote main had
advanced with Mail reply, forward and mark-read changes, so the coordinator
stopped this execution to reconcile main and create a fresh source freeze.
The audit agent independently corroborated this task-level interruption report.

`interruption-notice.json` records that report separately, including its origin
and the time at which this notice was recorded. Exit130 is not invented as a
field of the original runner receipt, and the original `RUNNING` receipt is
preserved byte-for-byte. No independent acceptance audit was produced.

The later outer Node plan and Studio Mail browser compiler phases did not run.
The earlier core/store phase includes its own portable/compiler checks. Partial
results from this interrupted attempt are not carried into the final acceptance
record, and this archive makes no assertion about the completed count of an
interrupted native group.

## Preserved evidence and integrity

`interrupted-attempt.tar.xz` retains the **complete original gate directory**:
52 regular files and five directory entries. The separately authored interruption
notice adds one file, yielding **58 indexed members and 53 regular files**.
All raw logs, gzip files, manifests, receipts and generated artifacts present in
this interrupted directory are included, with no excluded gate paths.

Compressed size: **1,279,064 bytes**. SHA-256:

```text
ac17e3decb5613598c408c134cb9c8b176b8dc49554eef35320d3d1c8f896dd2
```

`interrupted-attempt-index.json` records every member's kind, original relative
path, byte length and SHA-256. XZ compression and normalized, sorted tar headers
make the archive reproducible while preserving original content bytes.
`interrupted-attempt-originals-audit.json` records independent direct comparisons
against all 53 original regular files, directory checks and full gate-tree
coverage: **zero errors**. Packing and verification left the original evidence,
repository and runtime untouched.

## Verify or rebuild

Verify the archive without the original workspace:

```sh
python verify_interrupted_attempt_archive.py \
  --archive interrupted-attempt.tar.xz \
  --index interrupted-attempt-index.json \
  --output /tmp/office-interrupted-dfb-archive-check.json
```

To compare the original files too, additionally supply:

```text
--gate /path/to/office-mail-gate-final-dfb28229
--notice /path/to/interruption-notice.json
```

After verification, rebuild using the preserved originals:

```sh
mkdir -p /tmp/office-interrupted-dfb-originals
tar -xJf interrupted-attempt.tar.xz -C /tmp/office-interrupted-dfb-originals
python pack_interrupted_attempt.py \
  --gate /tmp/office-interrupted-dfb-originals/gate \
  --notice /tmp/office-interrupted-dfb-originals/notice/interruption-notice.json \
  --output /tmp/office-interrupted-dfb-rebuilt
```

Use a fresh output directory. These evidence tools execute no product code,
access no network, and query no GitHub Actions. They do not resume or complete
the interrupted test run.
