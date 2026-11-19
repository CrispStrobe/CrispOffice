# Native Mail transport static review

Captured: 2026-11-19T06:20:20.903951+00:00

Reviewed worktree base: `e78d7e91e9c2dc0d86e9cbcf8ab262acb8bc190e`. The final committed source is identified by the per-file Git blob and SHA-256 hashes in `transport-review.json`.

## Result

T01-T11 remain resolved by static inspection. A later exact-SDK review found open T12 in real pending-TLS ownership; see the follow-up below. This is a static review, not a test-pass or live-service qualification claim. No Dart/Flutter execution or Actions/CI query was performed by this reviewer.

## Findings and fixes

### T01: Malformed raw FETCH could become false tombstones

Location: `RawFetchParser and ImapClient.onUntaggedResponse`. Status: resolved by static inspection. The parser now latches fatal failure and the raw command is failed/aborted; no accepted prefix can become a successful page.

### T02: Multipart header-only source failed MIME parsing

Location: `rawImapHeaderItem and NativeMailImapProvider._header`. Status: resolved by static inspection. Header fetch now requests only envelope fields, excluding MIME content headers that require an omitted body. Full BODY[] fetch remains byte exact.

### T03: Unbalanced response syntax could print private literal data

Location: `ImapResponse.iterate(strict: true)`. Status: resolved by static inspection. Strict raw parsing rejects unbalanced parentheses/unterminated values; the legacy warning no longer prints literal content.

### T04: Case-sensitive FETCH atoms could be ignored

Location: `RawFetchParser._parseUntagged`. Status: resolved by static inspection. Protocol atoms are compared case-insensitively, with literal bytes untouched.

### T05: Cancelled connections could complete late or remain open

Location: `ClientBase.connectToServer, upgradeToSslSocket, abort; NativeMailImapProvider._run`. Status: resolved by static inspection. Hard abort destroys current sockets and invalidates the connection generation. Generation is checked both around connect completion and after TLS/subscription awaits; late sockets are destroyed.

### T06: Sparse UID space allowed excessively large whole sweeps

Location: `MailTransportLimits.maxUidScan and pullChanges`. Status: resolved by static inspection. Whole UID sweeps are explicitly limited to a default ceiling of 10000 (configurable through 100000); larger UIDNEXT/continuation ceilings return unsupported before FETCH. This is an explicit first-slice limitation, not sparse-mailbox scalability.

### T07: OAUTHBEARER GS2 identity and challenge handling were incorrect

Location: `ImapClient.authenticateWithOAuthBearer; NativeMailImapProvider._authenticate`. Status: resolved by static inspection. GS2 uses a=, an error continuation sends AQ==, and both OAuth modes require the advertised mechanism plus SASL-IR before initial-response authentication.

### T08: Input-budget failures could be mislabeled authentication/transient errors

Location: `ProtocolResourceLimit, ImapResponseReader, Uint8ListReader, ClientBase greeting handling and _run`. Status: resolved by static inspection. Literal, line, greeting and aggregate response limits latch a typed quota condition; quota classification precedes authentication classification.

### T09: Acknowledged STORE could report success without desired flags

Location: `NativeMailImapProvider._readIdentity/_setFlag/apply`. Status: resolved by static inspection. Source identity is read before mutation, exact UID flags are re-read after STORE, and MOVE checks source absence. Unsupported MOVE and missing source are rejected before mutation.

### T10: Final lease invalidation could hide completed-write uncertainty

Location: `NativeMailImapProvider._Operation.mutationStarted and _run`. Status: resolved by static inspection. The mutation-started state remains latched through final lease checks; any subsequent failure is conflict without automatic retry.

### T11: Malformed FETCH sequence prefix remained silently ignored

Location: `RawFetchParser._parseUntagged`. Status: resolved by static inspection. FETCH-looking data is detected separately, then positive 32-bit sequence syntax is validated. A malformed prefix fails instead of generating a successful empty sync page.

## Evidence boundaries

- The controlled socket fixture exercises actual ClientBase connect/upgrade/abort and enough_mail command/response code, but substitutes socket construction. It does not prove real TLS negotiation, trust-store behavior, certificate hostname rejection, or live account/provider compatibility.
- UID sweeps use numeric windows and tombstones for missing UIDs. The explicit ceiling prevents unbounded sparse scans; scalable discovery/CONDSTORE/QRESYNC remains outside this slice.
- MOVE success verifies acknowledged command plus source absence, not a returned destination UID mapping. Reconciliation of destination membership remains a later sync responsibility.
- Header parsing accepts partial envelope projections because MailHeaderRecord has no diagnostics field; after envelope-only HEADER.FIELDS this is not a demonstrated corruption blocker. Full-message parsing rejects partial results.
- No concrete INBOX-case-alias regression was demonstrated; canonicalization was not added as an unsolicited scope expansion.
- No live OAuth flow, platform keychain, SMTP sending, background retry, or mailbox-wide expunge is qualified here.

## Controlled-test evidence

The new tests were read and checked for meaningful assertions covering malformed/duplicate sync responses, byte-exact raw content, multipart envelope headers, mixed-case FETCH, UIDVALIDITY reset, sparse UID ceilings, credentials, write reconciliation, connection and TLS-upgrade cancellation, and scoped durable-store integration. Execution results belong in a separate gate receipt and are not implied by this review.

Manifest SHA-256: `f9a924bd2c4954a0b733aac58713d9133b83720864d2ea0a3cbedccad831f365`. Files: 25.

## Final committed source refresh

Reviewed commit: `9d4bdf70f0b979a736764daf671f10e4f8b70286`. Tree: `c0a1ccdfa10497549bf88029700ce7a0b67ace62`. Worktree clean: `True`. The manifest now covers all 31 paths changed by this commit.

- Reviewed the final manual-connect greeting reset: connect(socket, connectionInformation:...) clears _greetingBytes together with resetting greeting state.
- RawImapMessage bytes documentation now identifies BODY[HEADER.FIELDS ...] correctly; byte-copy implementation is unchanged.
- Read four additional resource-classification tests for oversized greeting, protocol line, aggregate authentication response bytes and header literals. They assert typed quota failures and no successful sync page.
- The committed README and fork patch notes explicitly separate controlled protocol evidence from real TLS, live OAuth/account interoperability and future large/sparse mailbox pagination.
- The complete changed-path manifest includes formatter-only existing Mail core/store tests and package/fork documentation, in addition to transport and fork implementation files.

Final manifest SHA-256: `8fc999c83f52d1bc77a9a88771879a894cc8a88c45b91befaf8e9e8086d7b6ac`. All 11 finding statuses remain resolved by static inspection; no test pass claim is made by this reviewer.

## Open follow-up at ca00a8ff

Reviewed commit: `ca00a8ffb3c0c82c646eaf2e5a134ab7348ae90e`; tree `4e2d8a787be55cfde9dd57adb11ca49bf4d99bd1`; cumulative changed-path manifest: 31 files, SHA-256 `721d6be517169acd4a0dcb1be37f8b9e2226bc4a30ac309c1bd3ec5927a1a0b5`.

The quota exception compatibility and package notice changes are sound by static inspection. T12 remains open: real SecureSocket handshakes detach their underlying raw connection before the returned future completes. The current abort path cannot close that detached connection while the handshake is stalled. The successful-upgrade cleanup itself is safe. See `tls-sdk-review.json` and `.md` for exact source proof and the required real-loopback regression.
