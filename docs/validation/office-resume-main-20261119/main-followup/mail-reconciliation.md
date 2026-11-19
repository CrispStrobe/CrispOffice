# Mail reconciliation with main 666e9a2e

## Source and scope

This development review covers the normal merge of exact main
`666e9a2ea46f7aeaaa1d01b60aabea0c2fe6f0fd` into the saved continuation at
`656ff823`. The earlier qualified source is
`22ffa8bdcc11e5e10eb37f2326f832066f609a08`. Its evidence remains historical;
the new merged source requires its own frozen acceptance gate.

Main's native/browser module split, bounded UID/raw-octet message loader,
shared saved-message view, Word-based composer, MIME/envelope builder,
diagnostic print-containment zone, discovery validation, narrow layouts,
and reply/forward/mark-read actions are retained. The native host explicitly
sends with `appendToSent: false` and an explicit recipient list. Integration
does not restore the older default Sent-append behavior.

## Carried safeguards and current behavior

- Connection attempts retain their initial credentials and check the current
  generation plus pending client identity before continuing. A nonselectable
  INBOX is excluded when choosing the first folder. Candidate loaders and
  clients are released after setup failure or stale completion.
- Shutdown independently aborts both low-level transports and requests
  high-level disconnect, with each cleanup failure contained inside the
  existing private operation zone. Stale completions repeat cleanup against
  their original client rather than the replacement session.
- Reader replacement remains deferred until the old widget detaches. Closing
  or disconnecting releases the reader and bounded loader and prevents late
  message completions from changing the UI.
- A `MailSendPostSubmissionException` is caught before generic submission
  uncertainty. It clears the retained draft and uncertainty state, shows the
  current accepted-submission notice, and displays fixed copy/cleanup warnings
  without exposing underlying response text. SMTP is not retried. The ordinary
  uncertain-submission path still retains its draft and requires acknowledgement
  before a user attempts another send.
- Reply and forward quote `MailReaderController.decodedText`: the already
  loaded, bounded message presentation. The high-level list entry is only an
  envelope and normally has no body. Reply-To selection, subject prefixes,
  forwarding headers and the existing quote-length bound are retained.
- Mark-read sets the busy state before awaiting the UID request, so a folder
  change cannot race the operation. Only a successful completion in the
  originating session changes the message's seen flag. Errors use fixed
  localized feedback; stale success/error cannot affect a reconnected session.

## Mapping the prior 71 Mail executions

The old number included two nine-case suites exercising compatibility names
for the same saved-reader implementation. Those duplicate API fixtures are not
counted as separate modern product requirements. Their sources remain in Git.

| Source22 suite / executions | Current coverage |
| --- | --- |
| `studio_mail_test.dart` / 30 | The current native host suite retains setup, mailbox, message, send, reconnect and cleanup behavior through main's loader/composer APIs. Four typed outcome/stale-warning cases are carried forward. Main's no-Sent-copy and uncertain-draft policies remain asserted. |
| `studio_mail_lifecycle_test.dart` / 2 network cases | Two explicit cases in current `studio_mail_test.dart` display a reader, suspend the next read, close the host, verify reader/loader disposal and complete the old read with success/error. |
| `studio_mail_session_test.dart` / 14 | Current native host and discovery suites cover pending setup/transport cleanup, stale mailbox/message/send/draft completions, empty senders, discovery dismissal and the original credential snapshot. Cleanup assertions now check both transports even when both abort calls and disconnect fail. The obsolete session suite is removed. |
| `studio_saved_mail_test.dart` / 6 | Current saved-view tests preserve byte opening, compact mode, cancellation/empty results, late picker/read completion, and language cycling with the same active sheet. German account setup is checked before entering the saved view. |
| `studio_saved_message_test.dart` / 9 | The shared current saved-view suite covers byte/path success, mode/reader preservation, late picker paths that must not start reads, picker/read failures and late failures, plus localized feedback. The removed dialog class is not resurrected. |
| `studio_saved_mail_incoming_test.dart` / 9 | Same shared saved-view requirements above, formerly repeated through the compatibility alias. The duplicate obsolete suite is removed. |
| `studio_saved_mail_lifecycle_test.dart` / 1 | Main's current `studio_mail_lifecycle_test.dart` directly covers a pending picker completing after the saved view closes and its controller is disposed. |

`studio_saved_message.dart` and the old saved-dialog aliases are intentionally
superseded by main's `StudioSavedMailView` and conditional native/browser host.
The unused `test/support/studio_mail_fixture.dart` had no remaining Dart imports;
its monolithic native constructor assumption failed strict analysis against
the browser-facing conditional export, so it is removed. Current suites own
fixtures for the actual public native, discovery, loader and shared-view APIs.

## New action regressions

Two end-to-end widget cases use body-free envelopes and separate loaded message
bytes, then submit Reply/Forward through the actual composer. They verify
Reply-To, a blank forwarding recipient before user input, preserved subject
prefixes, quoted loaded text, the narrow forwarding layout, and no Sent append.
Four mark-read cases verify selected UID use, busy serialization, failure
preservation, and late success/error after reconnect. The ordinary native suite
also checks fallback from a nonselectable INBOX.

## Development validation

The eight-file Flutter VM cohort passed **114/114 cases**, with zero errors or
skips and a successful terminal reporter event (59.400 seconds):

| Suite | Passed |
| --- | ---: |
| `studio_mail_test.dart` | 42 |
| `studio_mail_discovery_test.dart` | 9 |
| `studio_mail_lifecycle_test.dart` | 1 |
| `studio_mail_compose_test.dart` | 21 |
| `studio_mail_message_loader_test.dart` | 19 |
| `studio_mail_operation_test.dart` | 7 |
| `studio_mail_web_test.dart` | 1 |
| `studio_saved_mail_test.dart` | 14 |

Strict fatal-info/fatal-warning analysis and formatting pass all 21 remaining
Mail Dart paths. The initial analysis result is preserved: it found the unused
legacy helper and `avoid_print` diagnostics in the tests whose purpose is to
verify direct print suppression. All direct print assertions remain; a narrowly
documented `avoid_print` file exception explains that intentional test behavior.
The unused helper removal and non-executable lint comment followed test launch;
no tested production or test behavior changed after launch. The final frozen
gate will bind and execute the complete final source.

Raw logs and the machine-readable final readback are next to this review:
`mail-main-666-development.jsonl`, `mail-main-666-development.stderr`,
`mail-main-666-analysis.log`, `mail-main-666-analysis-corrected.log`,
`mail-main-666-format.log`, and `mail-main-666-development-receipt.json`.

These are development controls using injected clients/providers/file pickers.
The explicitly imported browser host is exercised on the VM; this cohort does
not establish browser compilation, live-browser behavior, installed-platform
IME behavior, real Mail account interoperability, real external sending, or
linguistic acceptance. No external account, remote write or GitHub Actions
operation was used by this reconciliation.
