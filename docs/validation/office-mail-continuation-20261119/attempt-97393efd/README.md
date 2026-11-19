# Failed qualification attempt — 97393efd

**This attempt failed and is incomplete. Its cases contribute zero to accepted
qualification totals.** The full original gate directory remains preserved;
no original receipt or log was rewritten.

## Exact attempt and failure

The recorded source is `97393efd234e390375a19a98321911ecd80f7a69`, tree
`63debc84852f735c6d8051704655c3f120951dd4`. The outer receipt finished with
`status: FAIL` at `2026-11-19T12:02:26.808542+00:00` and reports unchanged source
and runtime fingerprints.

All nine native test groups, native analysis and native formatting completed
successfully. The native receipt reports **1,859 passing cases**, zero failed
cases and zero skipped cases, but the following whitespace gate failed with
exit code 2:

```text
docs/validation/office-mail-continuation-20261119/audit_results.py:955: new blank line at EOF.
```

This output is preserved verbatim in `gate/native/checks/whitespace.log` and
its gzip companion. The outer driver stopped after the unsuccessful native
phase. The later outer Node plan and Studio Mail browser compilation did not
run. The earlier core/store phase had already run its own VM, Node and browser
compiler checks; that partial execution does not make this aggregate successful.
No independent acceptance receipt was produced for this attempt.

The subsequent source `dfb2822953156496f60efd62f68ff4dc885c93ab` removed the
extra EOF blank line and started a fresh aggregate attempt. This archive retains
the original failure and its original source identity.

## Complete preserved evidence

`failed-attempt.tar.xz` contains **102 files from the complete original gate**,
plus the supplemental read-only IMAP scaling note, and five directory entries:
**108 indexed members, 103 regular files**. Every raw log, gzip log, manifest,
receipt and generated artifact present in this failed gate is included.

Compressed size: **1,385,260 bytes**. SHA-256:

```text
e8a21f72df1d8411ae155a1b849ec7e5736f3a983da14167efa9e25baeb22d7f
```

`failed-attempt-index.json` gives a sorted inventory with every member's original
relative path, kind, byte length and SHA-256. The archive uses deterministic XZ
compression and normalized, sorted tar headers while preserving file bytes.
`failed-attempt-originals-audit.json` records a separate verifier comparing all
103 regular members directly with their original bytes, checking all directory
entries and confirming complete gate-tree coverage: **zero errors**.

The supplemental `imap-reader-scaling-followup-97393efd.md` explicitly attributes
its reporter timings and 454 protocol cases to this earlier failed gate. Its
read-only code review was recorded against a later source with the same six
listed product/test files. It documents an existing suffix-copy scaling cost;
it does not introduce a change, an additional test, or an acceptance result.
A convenient copy is supplied beside the archive with the same original bytes.

## Verify or rebuild

Verify the saved archive without the original workspace:

```sh
python verify_failed_attempt_archive.py \
  --archive failed-attempt.tar.xz \
  --index failed-attempt-index.json \
  --output /tmp/office-failed-973-archive-check.json
```

For direct original-byte comparison, additionally supply:

```text
--gate /path/to/office-mail-gate-97393efd
--review /path/to/imap-reader-scaling-followup-97393efd.md
```

After verification, extract and rebuild from the retained originals:

```sh
mkdir -p /tmp/office-failed-973-originals
tar -xJf failed-attempt.tar.xz -C /tmp/office-failed-973-originals
python pack_failed_attempt.py \
  --gate /tmp/office-failed-973-originals/gate \
  --review /tmp/office-failed-973-originals/review/imap-reader-scaling-followup-97393efd.md \
  --output /tmp/office-failed-973-rebuilt
```

Use a fresh output directory. Archive verification/reconstruction executes no
product code, accesses no network, and queries no GitHub Actions.
