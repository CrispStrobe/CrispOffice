# Independent Studio Outbox review

Reviewed on 2026-11-20 against the authored Studio changes from
`c3df77d01ea9df4846e18131e69160d858f174ac`. This was a read-only review of
product code; only this report was written. The reviewer implemented the
core/store changes, but did not author the Studio integration reviewed here.
The source hashes below were identical before and after this review. The final
evidence audit binds the reviewed product sources to checkpoint
`ce9ff1c8b155c03a0e2707d6fc8b41b52e611a93`, tree
`49d07c3b264ed4b47cf3eb0999ac3f8c5c2ae01f`. The validator correction described
below is separately qualified; it does not change product source.

## Findings and resolution

No remaining blocking functional or security defect was found in the reviewed
Studio changes. This is a bounded source review, not proof of delivery or an
installed-platform security assessment.

The earlier review finding about misleading status text is resolved. A queued
legacy draft may already have an uncertain submission history, and a definite
failure on a later retry does not disprove earlier acceptance. The English,
German and Arabic labels now describe a queued item as awaiting explicit send
and failed results as the **latest attempt**. The separate uncertainty warning
and acknowledgement requirement remain visible.

The reviewed implementation satisfies these integration contracts:

- **Production capability:** `openStudioMailDraftStore` returns
  `SqliteStudioMailDraftStore`, which owns both draft and Outbox operations under
  the existing native profile lease. Native SMTP and the shared EWS/Gmail/
  Microsoft 365 host use it by default. An explicitly injected draft-only
  adapter retains the earlier foreground-send path; it does not acquire durable
  Outbox behavior merely by implementing `StudioMailDraftStore`.
- **Atomic transfer and freezing:** the adapter first saves the exact editor
  snapshot, validates composer inputs, generates MIME once, and calls the
  repository's draft-revision transfer. It changes local draft state only after
  that transaction succeeds. The repository validates identity, revision,
  immutable payload and transitions; semantic MIME construction remains the
  Studio builder's responsibility. This is not an arbitrary raw-message import
  API. Frozen bytes, recipients, source revision and reply metadata are retained
  across subsequent attempts.
- **Legacy uncertainty:** persisted draft uncertainty transfers into the queued
  item. Compose requires its acknowledgement before Send or Queue. Later
  Outbox retries require a fresh unchecked acknowledgement. An acknowledged
  attempt followed by definite rejection retains older uncertainty and cannot
  become an ordinary retry or cancellable item.
- **Account and session isolation:** both hosts reject an Outbox-capable store
  whose account differs from the stable draft identity. Every provider callback
  checks the current session, stable account and sender. The HTTP host rebinds
  only the account identifier to its verified live provider; wire, envelope,
  draft ID and revision are unchanged at that boundary. The generic submit
  helper checks the live session after committing the attempt and before
  invoking the provider. A mismatched result identity or unrelated recipient
  response is treated as uncertain.
- **Explicit sending and recovery:** queueing, opening, refreshing and reconnecting
  do not invoke submission. A foreground attempt is persisted before the
  network call. Same-owner active tracking prevents refresh from recovering a
  live operation; failed completion persistence drops that active marker so a
  later inspection recovers uncertainty. Closing retains the durable record.
- **Payload/privacy boundaries:** native replay requires ASCII parse/render
  equality before invoking the existing mail client, passes the complete saved
  envelope including Bcc, and leaves concurrent Sent filing disabled. HTTP
  providers retain their existing request and private-recipient handling; this
  does not claim their outer request bytes equal the stored MIME. The list
  decodes bounded local subject headers and renders no message body or remote
  resources. Cancellation cannot erase possible acceptance. Explicit local
  cleanup permits submitted records, including a later confirmed acceptance
  after acknowledged retry, cancelled records, and definite permanent failures
  without older uncertainty. Cleanup does not imply recall or resolution of
  earlier duplicate risk.

## Documentation and qualification boundaries

The Outbox guide, parity roadmap and current changelog accurately distinguish
foreground local persistence from scheduled/background delivery. They retain
the limits on offline access, body preview/export/editing, explicit uncertain
record resolution, local unencrypted storage, live-provider testing and
installed-platform qualification. The initial validation README was explicitly
marked work in progress; the final evidence was audited separately below.

The completed pure-Dart qualification contains **264 distinct cases across 27
suites**: core/store **172/13**, incoming Word layout **20/3**, and enough_mail
SMTP/submission **72/11**. It is not a total of 264 Mail feature tests. Strict
event audits report zero failures, errors, skips, incomplete cases or protocol
errors, and one successful terminal event per command. Its 640 source entries
and 461 selected runtime entries are unchanged before/after; that runtime
inventory is not a claim to hash the complete dependency closure.

Separately, the native draft/Outbox adapter receipt was checked against its raw
JSON event log: **34 distinct cases in two suites**, zero failures/errors/skips,
with one successful terminal event. This includes the existing 16 draft cases
and 18 Outbox cases; earlier runs must not be added again. The log SHA-256 is
`0fea7ccd9ba74f26df7d7b30ec587579d0c9e869f47cb9320ae13a73b14b0c34`.
The widget fixtures use a separate synchronous, in-memory actual SQLite opener
to cooperate with Flutter's fake clock. They do not replace the native
disk/reopen/profile-lease cohort. The final Studio cohort includes those same
34 native adapter cases, so they are not added again. No additional product
tests were run by the reviewer. GitHub Actions were not used or awaited.

## Final evidence audit

Independent reconstruction from the original test logs establishes **874
distinct Dart cases across 52 suites**: Studio Mail **610/25**, core/store
**172/13**, SMTP/submission **72/11**, and incoming Word layout **20/3**. The
cohorts have no overlap by canonical suite path plus case name. Every requested
Studio suite is present, with no unexpected suite or duplicate case name.
All four cohorts have zero failures, errors, skips or incomplete cases and one
successful terminal event per command. This total includes 20 Word cases; the
separate validator tests below are not added to it.

The original Studio command exited successfully, but its first strict audit
rejected the log because Python `str.splitlines()` treated literal U+0085,
U+2028 and U+2029 inside three unsafe-filename test names as record delimiters.
Those are legal JSON string characters. The unchanged original log is valid
UTF-8 JSONL with LF record boundaries. The rejected `final-studio/summary.json`
is retained, along with its nine reported framing/protocol errors.

The corrected `final-studio/lf-framing-audit.json` was produced by
`audit_studio_lf_final.py`. This independent reproduction loads the original
strict auditor from the checkpoint, adapts only its record splitting to LF,
and separately decodes every byte-framed JSON record. It preserves all error,
skip, hidden-case, completion and terminal-event checks. Its 610-case result is
identical to the corrected repository auditor. No log bytes were edited,
discarded or normalized, and no product test rerun was necessary. The original
Studio log SHA-256 is
`0fa212da555a3cecdccc0dc17e00ce4c98d3d5e8ccf4a466eb4dcd1be454097a`.

All **2,638 Studio source inputs** match both their before/after manifests and
the checkpoint's Git blobs. The **640 pure-Dart inputs** likewise match that
checkpoint; the only subsequent difference in that manifest is the separately
qualified `tools/mail/check_store.py` correction. The Studio manifest's 11
selected runtime inputs remain equal before/after. A separately timed
supplement records the actual Flutter native-assets map, mapped SQLite library
and engine frontend; their hashes also match the independent post-run check.
These are selected runtime inventories, not a complete dependency closure.

The validator correction reads bytes before LF splitting, which also avoids
Python's universal-newline conversion accepting bare CR as a record delimiter.
It changes no event acceptance rule. Its final qualification records **48
Python test methods**, including six new methods covering literal/escaped
Unicode separators, malformed records, real error events, missing completions,
CRLF compatibility and invalid non-LF delimiters. The final checker hash is
`d56b7abce9d4693b21ea9d3f3cb81456a6712a4543323e58ac1c21169caed998`;
its regression test hash is
`f414de6e298fbc1a0c7dfb4e9a322f2a0a74f5489812da19405125f80584f7b6`.
Earlier failed and intermediate validator receipts remain development evidence.

Finally, the independent static-receipt audit confirms **24 changed Dart files**
match the qualified source: formatting reports zero changes, strict analysis
reports no issues, and the recorded commands exit successfully with empty
stderr. This includes the three incoming Word Dart files; it is not a whole
repository analysis claim.

## Reviewed authored library identities

All paths below are relative to `packages/quds_office_editor/example/lib/`.

| File | SHA-256 |
| --- | --- |
| `studio_mail_compose.dart` | `f73830e5d629ecb3e6adbb56523053c39a6fddf9506dc50ac5667b432d963954` |
| `studio_mail_draft_store.dart` | `f54e092778d12d608e536c3ba6a6c78568f4b76a1eada30eb1b9ba130d4b69fc` |
| `studio_mail_ews.dart` | `38409ae30267e0bd0e74f1a85dce17a70252388a32f9d97d5fa61ea2cf37b482` |
| `studio_mail_native.dart` | `a95afda43e218d9d6ea82349de95ccbb4b47c9c8c6b96f28c922976758514d89` |
| `studio_mail_outbox.dart` | `09f52face56749588ae4fa92413adc50ac017b1cc9fe8d82657dab73e0ed974a` |
| `studio_mail_outbox_dialog.dart` | `0a2402814e63166cc12836c8b838b6ba87a67efdb6101a1eb9c1c6d0de1c5dae` |
| `studio_mail_outbox_strings.dart` | `59f354cf2bdf42a7dc36774aa28ec8d7bed4eec1d276ebe33b2d1baad6cc9dc6` |
| `studio_mail_submission.dart` | `da84f31d81235575431c21d94e27ef95cdf95dc54086f356ae3e0d2993ea90e6` |
