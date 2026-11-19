# Saved-message tests preserved from the concurrent branch

Original source: `packages/quds_office_editor/example/test/studio_saved_mail_test.dart`
at commit `3119a4598e61f061e7b7633ea4a352d841332b9e` (captured PR #191).
The adjacent `legacy-saved-mail-test.dart.txt` is a byte-for-byte copy of that file.
SHA-256: `8eeabb02027a2e941f8a6cc4d804fc2b0dbd6bfe03a53e6d868b08e387576ca6`.

The first five cases exercise the prior local `.eml` reader: saved-byte opening,
compact mode, cancelled/empty picker results, late picker completion, and late
file-read completion. Main replaced that interface with IMAP/SMTP account setup
before this continuation. PR #191 describes a saved-message restoration plan but
does not implement it. These source assertions are retained here as historical
requirements, not skipped tests or evidence that the planned feature exists.

The sixth case, language cycling and preservation of the active spreadsheet,
remains a current requirement. The runnable `studio_saved_mail_test.dart` retains
it against the actual account setup controls in German and keeps the English,
German, Arabic, and return-to-English assertions.

The original picker-era `studio_mail_lifecycle_test.dart` has been replaced by two
current network-UI lifecycle cases. Each opens a reader, suspends the next message
request, closes Mail, verifies reader disposal, and then completes that request
with success or failure. The current Mail suite separately covers replacement,
failure preservation, reconnect isolation, and asynchronous connection cleanup.
No legacy case is represented as current passing saved-message acceptance.
