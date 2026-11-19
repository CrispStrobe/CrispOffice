# Final mail source and evidence audit

**No concrete mail implementation blocker was found.** This was a read-only review of the current mail worktree and its source-bound evidence. No network operations, test runs, production edits, or commits were performed by this audit.

## Verified scope and preservation

- Baseline: `2170791c9250d72c9df31a065408365f9b50abaa`.
- Audit HEAD: `9f4219317e80f6202772bf0895e27643b04545ea`. Unrelated reconciliation was still in progress; this is a mail-scoped audit.
- All seven production/test SHA-256 values in the final offline mail provenance still match the worktree.
- The copied repository provenance, compact receipt, and final passing log match the scratch evidence byte for byte.
- `quds_mail_core` remains at tree `2860c22f05dacc4cdeb18552e419c01e9d9b6862`, identical to the baseline, with no tracked or untracked changes.
- Diff from the baseline is empty for mail core, MIME, store, transport, mail UI, and the entire `third_party` tree.
- Previous `docs/validation/mail-reply-threading-20261119` evidence remains untouched at tree `754dcc9092f2c75955c982b9e810f4662db8ea42`.
- The scoped mail diff whitespace check passed, and no merge conflict markers were found in reviewed mail files.

## Source review findings

### Recipient model

No concrete blocker found. ASCII bare-mailbox parsing rejects controls/unsupported syntax, bounds 100 entries and 25,600 characters before deduplication, preserves local-part case, folds domain case for identity, prioritizes To then Cc then Bcc, and exposes immutable group/envelope snapshots.

### Reply all

No concrete blocker found. Authoritative Reply-To takes precedence over From; connected sender is excluded by supported identity; original To/Cc roles are preserved with To precedence. Bcc source metadata is not read. Source scan is bounded at 1,024 entries; at most 100 distinct outgoing recipients are admitted; unsupported participants fail explicitly. Empty/self-only targets remain editable. Plain quote and thread metadata use the original shared builder.

### Canonical mime

Source review confirms builder assigns From/To/Cc/Subject and validated reply headers, never Bcc. Empty visible groups remain absent. The prepared canonical MIME excludes Bcc addresses; maximum-length header folding and MIME round trips remain unexecuted.

### Smtp envelope

Native host passes every deduplicated To/Cc/Bcc address via explicit recipients. Vendor sendMessage forwards that list to both DATA and BDAT SMTP implementations; message header recipients are not substituted. appendToSent remains false.

### Ews envelope

Shared host supplies complete MailTransportEnvelope recipients. Existing EWS adapter rejects Bcc in canonical MIME, checks visible recipients against intended envelope, derives hidden recipients, and supplies separate SOAP BccRecipients with canonical MIME unchanged.

### Gmail and microsoft365

Both services use the shared EWS/cloud host. Existing cloud adapter validates canonical MIME, derives hidden recipients from explicit envelope minus visible To/Cc, and adds Bcc only to a private provider request copy; immutable prepared bytes remain unchanged. API/recipient-facing behavior has not been live-tested.

### Composer and retry

To/Cc/Bcc and thread are immutable draft fields. Composer initializes all fields from retained draft and preserves thread in every submitted snapshot. Hosts retain the full draft before submission. Uncertain-send acknowledgement and no-automatic-retry gates remain; confirmed acceptance clears draft and uncertainty.

## Qualification boundary

The preserved offline run passed 57 pure mail cases: 8 recipient, 33 reply, and 16 threading cases. It retained 46 test declarations and omitted 18 entire MIME-dependent declarations. Its cached dependency graph differs from the full repository lock; the exact differences are recorded in the source harness receipt. This audit reverified source identity rather than rerunning those tests.

The following execution remains pending:

- Full Flutter composer and host widget suites.
- Full MIME serialization/round-trip suites, including 100 maximum-length recipients.
- SMTP/EWS/Gmail/Microsoft365 provider integration and live send behavior.
- Full repository locked dependency resolution and workspace analyzer.
- Previously pending layout-theme and downloads-manager widget suites.

No live mail submission was performed. `audit.json` records the machine checks, source hashes for all reviewed adapters and vendor paths, and these findings.
