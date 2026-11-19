# Saved-message tests preserved from the concurrent branch

Original source: `packages/quds_office_editor/example/test/studio_saved_mail_test.dart`
at commit `3119a4598e61f061e7b7633ea4a352d841332b9e` (captured PR #191).
The adjacent `legacy-saved-mail-test.dart.txt` is a byte-for-byte copy of that file.
SHA-256: `8eeabb02027a2e941f8a6cc4d804fc2b0dbd6bfe03a53e6d868b08e387576ca6`.

The first five cases exercise the local `.eml` reader: saved-byte opening,
compact mode, cancelled/empty picker results, late picker completion, and late
file-read completion. Main had replaced that interface with IMAP/SMTP account
setup. PR #191 described restoration but did not implement it, so its unchanged
source was first preserved here as a historical requirement.

The fixed reference capture subsequently included implemented readers at
`e80beb2ed2fe70397a5a8fff5c9e908b04862f78` (PR #193) and
`2abf5d264e5065772fc4ca05c7cab6d34256ab9d` (office-finish). Their reader behavior
is identical. The integrated production code uses `StudioSavedMessageDialog`
with `StudioSavedMailDialog` as a compatibility typedef, opened from the current
network Mail dialog by a visible, localized **Open message** action and tooltip.

All five historical reader cases are runnable again in
`studio_saved_mail_test.dart`, adapted from the exact office-finish tree to the
saved-reader entry point. Its sixth case checks the actual German account setup,
opens and closes the nested saved-message reader, preserves the active sheet
controller, and cycles English, German, Arabic, and back to English. The raw
snapshot alongside this note remains unchanged for provenance.

The incoming nine-case suites are also retained: `studio_saved_message_test.dart`
exercises the canonical name from PR #193, and
`studio_saved_mail_incoming_test.dart` exercises the compatible office-finish
name. Both cover byte and path reading, mode preservation, cancellation, late
completion, picker/file errors, controller cleanup, and localized feedback.
The original PR #193 pending-picker lifecycle case now lives separately in
`studio_saved_mail_lifecycle_test.dart`.

`studio_mail_lifecycle_test.dart` retains two current network lifecycle cases.
Each opens a reader, suspends the next message request, closes Mail, verifies
reader disposal, and then completes that request with success or failure.
`studio_mail_test.dart` retains the network UI and confirmed-send warning cases;
`studio_mail_session_test.dart` retains PR #193's discovery, setup, stale-session,
and independent transport-abort controls. No cases are skipped or represented
as passed solely because their source was preserved. Test results belong to
the raw validation logs for the tested integrated source.
