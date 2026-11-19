# Incoming Mail regression reconciliation

This mapping records how the current Mail tests retain the behavioral intentions
of the concurrent continuations. The original files remain available through
their merged source commits. This is a coverage map, not a claim that historical
executions ran against the current source. Only the new frozen qualification
determines accepted current results.

## Saved messages

The incoming `studio_saved_message_test.dart` in PR #193 (`4ed8154a`) and
`studio_saved_mail_incoming_test.dart` in PR #194 (`4b8b9e2e`) express the same
nine cases with different dialog class names. Their intentions now run against
the shared native/browser saved-message implementation through the canonical
`example/test/studio_saved_mail_test.dart`:

| Incoming intention | Current case |
| --- | --- |
| Picked bytes replace the welcome message in the selected mode; replaced controllers dispose | `Mail opens saved bytes and disposes replaced controllers` |
| Delayed path reading replaces the reader after completion | `a delayed saved-message path read replaces the chosen mode` |
| Cancelling leaves the reader intact | `cancelling the picker preserves the current Mail message` |
| Dismissal before a picker path result performs no file read | `a late picker path after closing saved Mail is never read` |
| Dismissal during a file read ignores completion | `a file read finishing after closing Mail is discarded` |
| Picker and read failures preserve the reader and localized feedback | Both `picker` and `file read` cases named `failure preserves the reader with localized feedback` |
| Picker and read failures after dismissal are ignored | Both `picker` and `file read` cases named `failure after closing saved Mail is ignored` |

The canonical suite additionally retains empty-picker handling, the valid
Welcome sample body, exact original octets, input-buffer mutation isolation,
full/compact mode preservation, account navigation, narrow enlarged-text chrome,
and the active spreadsheet while changing Studio language and visiting Mail.
The canonical `studio_mail_lifecycle_test.dart` retains its independent pending
picker-close regression. PR #192's later `studio_saved_mail_lifecycle_test.dart`
at `79e77725` repeats that intention; it does not need a third execution.

The duplicate saved test files and unused `studio_saved_message.dart` production
reader were removed. Production uses `StudioSavedMailView` in
`studio_saved_mail.dart`, with conditional native/browser file loading; it also
serializes picker operations and supplies the Welcome message's transfer
encoding. The superseded readers imported `dart:io` directly.

## Account sessions

The incoming PR #193 `studio_mail_session_test.dart` is retained as a focused
supplement to the canonical account and discovery suites, using the selected
native constructor, an injected message loader and the Word body composer.

| Incoming intention | Current coverage |
| --- | --- |
| Closing pending connect aborts both owned transports | Session: `closing during connect aborts pending owned clients` |
| Discovery completing after close creates no client | Discovery: both late success and failure cases |
| Discovery uses credentials captured at connection start | Session: `discovery uses the credentials captured when connect starts` |
| List/fetch setup failure releases the candidate | Account: each `connect`, `list`, and `fetch` failure also permits a fresh connection |
| No selectable mailbox releases the candidate | Account: empty mailbox list; session: `only nonselectable folders release both owned transports`, including a nonselectable inbox |
| Disconnected mailbox selection cannot start a late fetch | Account: mailbox `select` success and error after disconnect, with fetch count asserted |
| Old mailbox success/error cannot replace a new session | Session: both `old mailbox results` and `old mailbox failure` cases |
| Old message read cannot open in a new session | Account: both late message read success and error after reconnect |
| A draft opened before disconnect is not sent | Session: `a draft from a disconnected session is not sent` |
| Late send failure cannot affect a replacement session | Session: `late send failure cannot alter a replacement session` |
| Cleanup errors do not prevent independent transport aborts | Session: `disconnect contains cleanup errors and aborts both transports` |
| Empty sender lists are safe to search | Account: `search tolerates messages with an empty sender list` |

The session supplement contains eight cases, including the success/error pair.
Its discovery fixture uses the provider's `addIncomingServer` and
`addOutgoingServer` methods so preferred protocol-specific endpoints are
populated exactly as discovered configurations require. It does not weaken the
production check that rejects insecure discovery and non-IMAP accounts.

The late PR #193 `studio_live_mail_continuation_test.dart` at `4cf5831d` repeats
the canonical account suite's secure manual setup, asynchronous close/setup
failures, reader lifecycle, mailbox failure, compose/send, disconnect and German
labels. Its old raw-error and body-TextField expectations are superseded by
redacted localized feedback and the Word document composer. It introduces no
additional behavioral intention. Its redundant incoming test helper
`test/support/studio_mail_fixture.dart` has no remaining callers and is removed.

The current qualification plans select the surviving canonical and supplementary
files explicitly; deleted duplicate files do not contribute passing counts.
