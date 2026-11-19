# Body-only Mail quote follow-up

This additive development review follows `mail-main-666-reconciliation-review.md` and its 114-case receipt. Those files and all matching prior development artifacts remain byte-for-byte unchanged. The earlier claim that the full decoded reader text was suitable for quotes is superseded by this finding and repair.

## Finding and repair

Independent review found that `MailReaderController.decodedText` includes display metadata: Subject, From, To, Cc, Bcc, Reply-To, Date and attachment summaries. Quoting it could expose a hidden recipient from a loaded Sent message and duplicate forwarding headers. The earlier reply/forward checks asserted body containment but did not assert metadata exclusion.

`MailReaderPresentation` now exposes an optional `bodyText` field, defaulting to the empty string for existing constructor callers. The builder captures UTF-16 offsets immediately before and after its existing body projection and takes that slice only after the complete projection succeeds. Envelope and attachment-summary text is outside the slice. Rejected results remain empty. The displayed full text, HTML sanitizer, resource placeholders, text and image budgets, and rejection behavior are unchanged.

Studio reply/forward uses that loaded body projection, preserving its existing trimming and 8,000-code-unit quote limit. The visible From, Date and Subject forwarding header still comes from the selected envelope. Body text that literally starts with `Bcc:` or `Attachments:` remains ordinary quoted prose; the implementation does not strip labels or reparse HTML.

## Focused controls

- `packages/quds_office_editor/example/test/studio_mail_test.dart`: 44 cases passed. Four controls cover reply/forward × plain/HTML-only loaded MIME. Before composing, each proves the displayed reader actually includes the Bcc address and attachment filename. Both the draft and submitted plain text must retain body content and literal body labels, exclude envelope/attachment metadata, and preserve intended forwarding headers. Submission remains `appendToSent: false`.
- `packages/quds_mail_ui/test/presentation_test.dart`: corrected run passed 16 cases. New checks cover the default constructor, plain and HTML body isolation with non-BMP/mixed-script text, sanitizer output, and empty body text on rejection. Existing hostile-input, budget and CID controls also ran.
- Strict analysis and a no-change format check passed on the four changed Dart paths. The five changed paths were staged; no commits, remote writes, external accounts or Actions calls were made by this task.

The first new presentation run had 15 passes and one assertion failure because the expected HTML text omitted the existing `[External image blocked]` placeholder. Only that test expectation changed. The failed log remains available alongside the corrected run; production source was unchanged between the two attempts. The Studio run saw the final production source and was not repeated for an unrelated assertion-only correction in the presentation suite.

## Evidence scope

This is focused development evidence, not a replacement for the final integrated frozen-source gate. The new receipt binds 24 selected Mail source/test/changelog files and preserves the hashes of the prior 114-case artifacts. It records the initial failure, correction, final counts and commands. The new UI suite must be included in the final plan. Other prior suites were not rerun in this focused follow-up.

Independent reviewer `sync_review` read the stable production slice and all four Studio controls, found no further blocker, and requested no additional source change or optional test.
