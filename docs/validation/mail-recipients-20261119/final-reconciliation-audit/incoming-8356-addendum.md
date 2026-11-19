# Incoming 8356 host-test reconciliation addendum

**Retain all three incoming host-test declarations.** They add four widget cases: Gmail, Microsoft 365, EWS, and SMTP. No duplicate test-name or import blocker was found. No tests were executed in this read-only assessment.

Incoming tip: `8356fb0ad4630824a39453ea9a5923d9fb2a2101`. Its parent and merge base with the reference candidate are `c1b98f12f802863fb602e9919ead524891bfbcc6`. Reference candidate: `3279d1ffb0d80c0133fc6edaa2c3854512ac8481`.

## Meaningful additional assertions

| Incoming test | Added coverage worth retaining |
| --- | --- |
| `${service.name} host keeps hidden recipients out of canonical MIME` | Exercises manual composition for both cloud services with comma/semicolon lists, domain-case duplicate suppression, To precedence over Cc, Cc precedence over Bcc, complete explicit recipients, visible MIME roles, no hidden address in canonical bytes, and accepted-state feedback. |
| `EWS host preserves visible groups and hides Bcc from canonical MIME` | Exercises the same cross-group and domain-case deduplication through the EWS host. It complements the existing EWS case, which also verifies sender, subject, body, and retained-draft cleanup. |
| `SMTP recipient groups stay in the envelope and survive acknowledged retry` | Retains raw Cc/Bcc input after a controlled uncertain send, keeps resend disabled until acknowledgement, verifies exactly two explicit attempts, preserves the same deduplicated envelope and visible MIME roles on both attempts, excludes hidden recipients from canonical bytes, and keeps both Sent-append flags false. |

Read-only Dart AST/token comparison confirms that all three incoming assertion bodies are retained, ignoring whitespace, comments, and optional trailing commas. Their names occur zero times in the reference candidate and exactly once in each current target file. No original test names are missing, and no existing test body changed beyond formatting.

Imports remain identical to the reference candidate. The current cloud test retains its additional `studio_mail_compose.dart` import for the existing Reply all tests. No incoming import is missing and no import is duplicated.

The native `expect(message.bcc, isEmpty)` assertion is valid: `MimeMessage.bcc` calls `decodeHeaderMailAddressValue`, which delegates to `MailAddressParser.parseEmailAddresses`; null or empty header input returns an empty list.

## Slide compatibility

The incoming tip's own slide serial and dark-slide test changes are formatting only. Both current files are byte-identical to the reference candidate after final normalization. The serial reader retains `setInheritedBackground(resolvedBackground, masterBackground: ...)`, including reference-master tracking required for later master-color edits. The incoming full file snapshot contains the older assignment sequence, but that earlier sequence was not reapplied.

All seven hashes from the 57-case pure mail qualification still match. These four additional host/widget cases remain unexecuted, together with the previously documented MIME, provider, and full-lock gates.

`incoming-8356-host-test-checks.json` contains exact hashes, name/import inventories, token-comparison results, and source-preservation checks. `inspect_8356_test_delta.dart` records the static inspection method.
