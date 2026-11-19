# Quds enough_mail source and patch receipt

## Source identity

- Upstream: <https://github.com/Enough-Software/enough_mail>
- Commit: `fc69f17e24e9d03ce813bbf613c07a2ce94e5e9a`
- Upstream tree: `f0ece6bb3dd5b15c3cfb9b472bbefa8c73c657a9`
- Manifest version: **3.0.0**, preserved.
- Source: all 212 files tracked at that Git commit, including the native APIs,
  generated Dart files, examples, tests, license and notices.
- SHA-256 of `git archive --format=tar` at that commit:
  `b5e6773f4ddeb7ffdc32bdae3c6cb058a0ca8ed49368bce07023b0ffdb7f227e`.
- `UPSTREAM.json` records each original path and SHA-256, before local patches.
  Equality with the pub.dev 3.0.0 archive is **not asserted**. This fork uses the
  reviewed Git source, independently of the published archive.

The upstream `LICENSE` is retained **MPL-2.0**. No upstream file is relabeled MIT.
Local source additions inside this fork also carry the MPL notice. Independently
implemented Quds packages outside this directory keep their own MIT license.

## Local changes

1. `pubspec.yaml`: add `publish_to: none`; preserve package name, version, native
   dependencies, upstream repository URL and minimum Dart language version.
2. `lib/mime_core.dart`: add a supported public portable entry exporting MIME
   models, parser, codecs and diagnostics. It does not export `mime.dart`,
   `codecs.dart`, `MessageBuilder`, native clients or `dart:io` APIs.
3. `lib/src/mime_diagnostics.dart`: add typed, content-free diagnostic codes and
   `MimeDiagnostics.run`, which uses a Dart zone for operation-local callbacks.
   Concurrent operations do not share a mutable global diagnostic sink.
4. Replace the 22 active `print` calls in the portable MIME import closure with
   redacted diagnostics. Affected files are `codecs/mail_codec.dart`,
   `codecs/date_codec.dart`, `codecs/base64_mail_codec.dart`,
   `codecs/quoted_printable_mail_codec.dart`, `mime_message.dart`,
   `media_type.dart`, `private/imap/parser_helper.dart`, and
   `private/util/mail_address_parser.dart`. Original subjects, addresses, raw
   bytes, bodies and exception messages are never supplied to this callback.
5. Add `MailCodec.decodeCharsetStrict`. It uses the retained charset table with
   invalid-byte replacement disabled. Unknown charsets and malformed data
   produce an explicit code and `null`. Existing permissive body APIs keep
   their previous behavior for supported encodings; the Quds facade must
   perform strict validation first.
6. RFC 2231 parameter decoding now reports malformed percent escapes, missing
   charset/language prefixes, duplicate or missing continuation sections and
   unknown/malformed character encodings. Consecutive encoded sections are
   combined before charset decoding, including multibyte UTF-8 spanning a
   section boundary. Literal unencoded sections retain their literal contents.
7. `test/quds_portable_mime_test.dart` and `tool/portable_smoke.dart` contain
   independently authored fixtures and focused portability/diagnostic checks.
   The fixture uses reserved example addresses, never real private mail.
8. Restrict `enough_convert` imports to its public `latin.dart`, `windows.dart`
   and `koi8.dart` entries. Remove GBK, GB2312, GB18030 and Big5 aliases from
   the fork registry. These charsets now produce `unsupportedCharset`; strict
   decode returns `null`. This deliberate initial support restriction avoids
   importing CJK tables whose donor-source provenance is not yet qualified.
   The legacy GB18030-to-GBK alias was additionally not a complete GB18030
   decoder. The remaining 30 selected MPL source files are recorded by hash in
   `PORTABLE_CLOSURE.json`. No Big5, GBK or DOS module is in that closure.
9. Fix three pre-existing analyzer notices in native APIs: explicitly type the
   two manual account ports as `int`, and use a cascade for the mailto subject
   and encoding assignments. These retain the existing integer-port contract
   and builder behavior. Remove the now-unused conversion import after the
   RFC 2231 implementation change.
10. Reject undefined entries in the selected single-byte character tables in
    `MailCodec.decodeCharsetStrict`. The dependency's `allowInvalid: false`
    setting does not reject its `?` placeholders. The strict helper now reports
    `malformedCharacterData` and returns `null` for those replacements, while
    retaining a real ASCII question mark. It checks the decoded string without
    making another decoded-byte copy. Regressions cover Windows-1252,
    Windows-1253 and ISO-8859-3 undefined entries.
11. Validate calendar days, decimal numeric components, numeric zone digits/ranges and
    an optional weekday before constructing a `DateTime`. Dart's normalizing
    constructor must not turn a malformed date into a different valid instant.
    Missing time zones retain the legacy UTC fallback with an explicit
    `invalidDate` diagnostic so callers can suppress uncertain timestamps.
    Leap-second values also report `invalidDate`: Dart cannot represent them
    exactly, so the fork does not silently roll them into the next minute.
    Regressions include a valid leap day and a nonzero zone offset.

12. Add the native public `RawImapMessage`, `RawImapFetchResult`, and
    `ImapClient.uidFetchRawMessages` path. It retains exact complete literals,
    validates requested UID intervals and unique records, and does not normalize
    newlines or eagerly parse MIME. Header mode requests only envelope
    HEADER.FIELDS. Its parser rejects partial bodies, malformed prefixes,
    duplicate/out-of-range or non-decimal UIDs, repeated field lists and trailing
    response fields; a tagged OK
    cannot accept an earlier valid prefix. Valid unsolicited FLAGS-only updates
    are handled separately and do not consume the requested literal count.
    Bounded notification tracking rejects missing in-range literals and ambiguous
    sparse responses instead of turning them into false deletion tombstones.
    Later identified flags supersede earlier snapshots; an uncorrelated UID-less
    update after EXPUNGE cannot confirm a write through a stale sequence map.
    Strict iteration rejects repeated attached lists, while the raw parser
    requires one canonical `* sequence FETCH (...)` root with no trailing
    atom/list or sibling FETCH body. Legacy non-strict iteration is retained.
    FETCH recognition uses its untagged response position and IMAP atom
    delimiters, so malformed tabs, attached lists, quotes or literals are
    rejected instead of being ignored as absent messages. Unrelated status
    text, FLAGS data and a distinct FETCHX atom remain separate.
    Protocol atoms remain case-insensitive.
13. Add configurable literal, protocol-line/greeting and aggregate response-byte
    bounds. Deterministic budget failures are latched separately from provider
    or authentication errors. Strict response iteration suppresses the historical
    raw-literal warning output; malformed raw responses fail and abort the client.
    The distinct resource-limit error retains the legacy `FormatException`
    relationship, so existing parser callers and Quds quota classification agree.
14. Frame IMAP greetings across TCP fragmentation/coalescing. Add hard abort,
    connection-generation guards, and late socket/TLS result destruction.
    Production keeps the existing certificate and hostname trust policy.
    Controlled socket seams cover parser and late-result races. SMTP/POP
    greeting framing retains its existing mode; their shared connection and
    abort behavior is regression tested.
15. Correct OAUTHBEARER's GS2 authorization identity from `u=` to `a=` and send
    the required `AQ==` error-challenge terminator. Quds enables initial-response
    token mechanisms only with the corresponding AUTH capability and SASL-IR.
    OAuth browser authorization, PKCE, redirect and refresh remain host work.
16. Retain the default transport's public `RawSocket` owner through implicit TLS
    and STARTTLS, together with the pending TCP `ConnectionTask`. The original
    TCP owner remains available after TLS succeeds, so a hard abort can close
    buffered encrypted output without waiting for a graceful TLS shutdown.
    Cancellation, disconnect and connect timeout can close a stalled handshake
    before a secure socket is returned. A per-connection abort signal also
    settles the abandoned operation if the SDK handshake future stays pending.
    The Socket-compatible facade preserves
    ordered writes, partial-write readiness, input pause semantics and TLS
    subscription transfer; abort also cancels an open write producer. Hostname,
    `SecurityContext` and certificate callback policy are forwarded unchanged.
    Caller-injected arbitrary sockets keep the existing upgrade seam and own
    their pending-handshake lifecycle. Real Linux loopback regressions prove
    peer-observed closure, fresh retries, encrypted data continuity, default
    trust refusal and hostname checks, without claiming external-service or
    other-OS acceptance. Ordinary and already-secure manual `connect(Socket)`
    use and existing Socket-returning override signatures remain compatible.
17. Add `ImapClient.uidSearchRaw` for bounded UID discovery over a closed
    numeric interval. A dedicated strict parser requires exactly one complete
    simple SEARCH result and a successful tagged response, returning sorted
    immutable UIDs. It rejects missing/repeated/extended responses, non-decimal,
    duplicate and out-of-range UIDs, literals and malformed response shapes.
    UID-count exhaustion uses the existing resource-limit classification;
    protocol-line and aggregate response-byte limits remain enforced. Parser
    errors abort the operation instead of accepting a prefix as deletion
    authority. The existing general `SearchParser` remains unchanged. This
    primitive does not itself provide ESEARCH/PARTIAL, an unbounded mailbox
    snapshot or server-side count-limited pagination.

18. Make `MailClient.sendMessage` submit once before filing a Sent copy and
    always attempt outgoing cleanup. Preserve the original submission error
    and stack if submission fails. The new `MailSendPostSubmissionException`
    distinguishes confirmed submission followed by a Sent-copy or cleanup
    failure, retaining those two errors separately; callers must not retry
    SMTP for that outcome. The transaction helper and its tests carry the
    fork's MPL notice. `appendToSent: false` still performs cleanup and does
    not require a Sent mailbox.
19. Require a final DATA/BDAT `250` response before the high-level client
    confirms submission. A completed SMTP command rejects preliminary `1xx`
    responses and any recorded command-state failure, including an unexpected
    positive `250` response to DATA instead of `354`; a successful RSET cannot
    erase that failure. Original reply details remain available through the
    existing exception API. Public-client loopback regressions cover DATA and
    BDAT sender/recipient/final `1xx`, final `220`, premature DATA `250`, final
    `550`, and actual final `250` acceptance. They check that rejected or
    unconfirmed transactions never file Sent copies. This is SMTP acceptance,
    not a durable outbox, delivery confirmation, or external-provider test.
20. Settle and clear the active SMTP command before aborting its connection.
    Repeated abort remains safe and releases a high-level send and any queued
    disconnect even when the server stops replying. The public-client loopback
    regression holds the MAIL FROM response, checks the original fixed abort
    error and stack, and confirms that no submission or Sent copy is reported.
    This preserves the final-response acceptance checks and the distinction
    between submission failure and a failure after confirmed submission.

These native additions are covered by MPL-2.0. `UPSTREAM.json` remains the
unchanged original-source inventory; local additions and modifications are
identified by the consuming Quds commit and source-bound validation manifest.

`PORTABLE_CLOSURE.json` records the current 21-file local and 87-file complete
selected import closure, including external packages. `DEPENDENCIES.json`
records the 30-package runtime graph resolved by the root workspace lock;
`notices/` retains every package license and additional bundled notice found
in that graph. This is not a blanket clearance of every file in a downloaded
archive. Static inspection alone is not browser qualification; `verification/`
records actual compiler/runtime outcomes and the blocked Chromium attempt.

### Excluded charset provenance

`enough_convert` 1.7.1 declares MPL-2.0. Its GBK files additionally attribute
`fast_gbk` and an ICU mapping source; its Big5 table attributes
<https://gist.github.com/shiedman/5477198>. The inspected gist contains no
explicit license or copyright notice. The original fast_gbk repository does
contain a BSD-3-Clause license, but the complete table donor/version inventory
has not been qualified here. Those modules are excluded, rather than treating
the top-level MPL declaration as proof about every donor asset. Re-enabling
them requires a reviewed source and notices record plus decoder tests.

The selected Latin/Windows/KOI8 files and shared base files retain the package's
MPL license. Inspection of that exact closure found no additional copied-donor
attribution or conflicting license notice. Their exact hosted source archive is
<https://pub.dev/api/archives/enough_convert-1.7.1.tar.gz>, SHA-256
`65bff24436f4da878435e80ba24a6f762870751a6f5fd4ea51cdec232d90a936`.
Matching covered source for a consuming binary must include these files and
the retained MPL notice; the archive is not otherwise blanket-approved.

## Boundaries that still require callers' work

- This fork's MIME parser remains a whole-message parser. It does not establish
  raw/decoded/part/depth/header/image memory limits or cancellation budgets.
- Legacy tolerant codec APIs are not strict decoders. The Quds facade validates
  transfer encodings, encoded words and byte ranges before projection, and
  observes structured diagnostics instead of presenting fallback text as exact.
- Native protocol logging and SMTP outcomes require their own adapter review.
  Portability of `mime_core.dart` does not imply browser socket support.
- `MailCodec.decodeBinary` retains upstream CRLF removal for identity 7bit/8bit
  data. Byte-exact incoming attachments must be taken from their original body
  ranges, not reconstructed through that legacy helper.
- The original portable MIME patch adds no HTML rendering, sync, credentials
  or network request. The later native primitives above are consumed by
  `quds_mail_transport`, which owns bounded synchronization and host-vault
  access. Neither patch supplies an Apple application or distribution approval.

## Matching covered source for binaries

The maintained source is this directory in
<https://github.com/CrispStrobe/quds_office_suite>. A release maintainer must pin
the **exact consuming Quds commit** and distribute a publicly accessible source
archive or immutable commit URL containing this directory, `LICENSE`,
`UPSTREAM.json`, `QUDS_PATCHES.md`, and the matching build/dependency record.
The product's open-source information must point recipients to that immutable
covered source, rather than only the upstream moving branch. Record the URL
against each shipped binary before release. Development branch availability
alone is not the per-build source-distribution gate.
