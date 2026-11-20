# Mail account ownership and final Outbox integration

The final qualified source is **`c20b41d9c7eed574c02e49f1fd96789843aec2e6`**
(tree `6a4a3402f2156490d8a7c0b1cb8d9d21fcb3ef32`). It combines our saved
account-ownership work with captured main
`13be50464d1b43e9f2100fb9ccc12f8fe22eb55e`, including PR #250's durable
Outbox and the Word frame-cache repair. **232 focused checks across 17 suites
passed**, with zero failed or skipped cases, and all **19 Dart files** in the
remaining delta passed formatting and strict analysis.

[PR #251](https://github.com/CrispStrobe/quds_office_suite/pull/251) records the
final follow-up publication and merge. PR #243 already merged the original
remembered-account increment at `a059c024`; later branch checkpoints continued
after that merge. This report corrects the earlier assumption that #243 was
still the pending final PR.

## User-visible result

Native IMAP/SMTP setup remembers up to **20 accounts per selected credential
backend**, with explicit New, Switch and Forget workflows. Selecting an account
fills setup; connection remains explicit. Legacy migration writes and verifies
the replacement before removing the previous record. Invalid, unreadable or
unavailable storage prevents destructive replacement or silent fallback.
System storage, a custom macOS keychain, an encrypted master-password vault and
session memory keep separate catalogs. Switching preserves the existing local
draft workflow. See the [remembered-account guide](../../roadmaps/mail/remembered-accounts.md).

This follow-up completes the remaining ownership safeguards: delayed A → B → A
initialization cannot replace a newer cached backend, in-flight operations keep
their captured owner, and injected stores can supply an explicit settings opener.
The native host retains its pending, connection, modal and busy guards. Changing
storage clears the old chooser and Forget target; disconnected setup credentials
are cleared, while active-session and newer-edit protection remain intact.
Typed boundaries, deterministic real-catalog fixtures, nine ownership regressions
and eleven additional body-projection contracts are retained.

The combined source preserves safe HTML-only reply and complete attachment
forwarding from PR #248. PR #250 adds the durable foreground Outbox for native
SMTP, EWS, Gmail and Microsoft 365. **Send** freezes MIME plus the complete
transport envelope, atomically transfers the exact saved draft revision into
the account's SQLite queue, then starts one explicit attempt. **Queue in Outbox**
saves without contacting the provider. Bcc remains in the transport envelope.

The Outbox supports explicit send/retry, guarded cancellation and confirmed
terminal-record removal. Interrupted attempts recover as uncertain. Reconnect,
refresh and restart do not send automatically; uncertainty requires a fresh
delivery check and acknowledgement before retry. Submission acceptance remains
distinct from delivery. Reconnect to the same account to inspect its queue;
the current bound is 100 entries per account. See the
[Outbox guide](../../roadmaps/mail/outbox.md) and
[reply/forward guide](../../roadmaps/mail/reply-forward.md).

## Final-source qualification

All accepted runs bind source `c20b41d9`, exact selected tests, local input
closures and dependency configuration. Each has a successful terminal event,
process and wrapper exit zero, no failures/skips, and unchanged source inputs,
HEAD and runner files. Loading and hidden diagnostic entries are excluded.

| Affected boundary | Accepted cases |
| --- | ---: |
| Account/backend switching, draft/session safety and composer regressions | 78 |
| New Outbox Studio store, submission, dialog and provider-host paths | 55 |
| Core Outbox state, codecs and atomic SQLite draft transfer | 79 |
| Word incremental layout and frame-cache regressions | 20 |
| **Total across 17 distinct suites** | **232** |

The Studio rows are disjoint parts of its 133-case cohort. The core/store row
combines 16 core cases and 63 store cases. [The qualification receipt](final-integration-qualification.json)
retains commands, per-suite results and source identities. Strict analysis uses
`--fatal-infos`; the 19-file gate covers the complete remaining Dart delta
against captured main. This is selected integration coverage, not a complete
repository acceptance claim.

The first store attempt is **rejected**: 44 cases passed and 19 failed during
setup because its direct Dart runner lacked the native-asset mapping. The same
63 cases then passed using the actual Flutter-generated mapping and the locked
test runner's supported kernel-compiler path. The genuine bundled SQLite
**3.54.1** binary matches SHA-256
`0a65852703763619a7a34633b4959b3b86c4103804a4dfe4e8b27b5de1c0647b`,
identical to incoming qualification. The maps and library hashes are captured
before/after; no product, dependency, test or assertion changed. The failed
attempt contributes zero cases to the total.

Qualification uses **Flutter 3.47.8 / Dart 3.13.7**, the pinned restored native
runtime recorded in the retained evidence. No GitHub Actions, workflow, check
or status queue was used as an acceptance dependency or awaited.

## Source preservation and replayable evidence

The native source merge preserves both `e1fd2e14` and `13be5046` as parents.
The 18 Dart delta files other than the native Mail host match the preceding publication.
Every incoming implementation, test and checker path matches captured main,
apart from the intentionally combined native host. Its Outbox lease/dispatch
checks and our settings/ownership guards are both retained. Dependency
manifests remain unchanged. The preserved incoming evidence keeps its own
source identity and is not counted as fresh execution here.

[The publication manifest](source-continuity.json) protects **18,666 tracked
paths**, including source, tests, fixtures, dependency manifests and incoming
evidence. Only the listed documentation areas may differ from the qualified
commit. [The verifier](verify_publication.py) checks the protected Git objects
and ancestry of both qualified source and captured main. The final documentation
publication does not change product or test source.

- [Final evidence archive](final-integration-evidence.tar.xz): **660,536 bytes**, **86 retained files**.
- SHA-256: `afb908afca716a5922344800516a47cf82fc146b6f9a7891a23d430110fc7e21`.
- [Member manifest](final-integration-evidence-manifest.json) and [archive verification](final-integration-archive-verification.json).
- [Replay from the extracted archive](final-integration-replay-verification.json): **232 unique cases, 17 suites, 19 static targets and 2,228 tracked source bindings verified**.

The archive retains raw events, exits, before/after inputs, exact runners,
resource monitors, native maps, preservation review and portable replay. The
SQLite binary and SDK/package caches are hash-bound rather than bundled.
Replay verifies recorded evidence; it does not execute tests or recreate the
native runtime.

From this directory, using Python 3.11 or newer and a repository containing the
qualified commit:

```bash
python3 verify_archive.py --manifest final-integration-evidence-manifest.json
tar -xJf final-integration-evidence.tar.xz
python3 validation-final/replay_evidence.py --repo ../../.. --output replay-check.json
python3 verify_publication.py --repo ../../.. --ref origin/main
```

## Earlier checkpoints and scope

The [earlier 699-case qualification](historical-625f4d76.md) remains bound to
`625f4d76`, before the latest Outbox integration. Its raw archive, strict
classification, source bindings and documentation-only publication remain
available. PR #250's incoming qualification likewise belongs to its own frozen
source. Those totals are not added to the 232 fresh final-source cases.
[Initial intake](intake.json), [the cumulative addendum](intake-addendum.md) and
[final integration](final-integration.json) record the fixed captures and
incremental remote checkpoints. Historical branch equivalents were reconciled
without reapplying old source over newer implementations.

The earlier broad editor-equivalence trial remains rejected; no complete corpus
or performance improvement is claimed. Pre-reset raw logs were not recovered;
[recovery.json](recovery.json) preserves only the known historical summary.
Native fixture tests do not qualify live provider services, installed OS
keychain permissions, browser execution or release packaging.

**M04W and M07 remain open.** Next boundaries are repository-driven account/folder
sessions and offline/unified mailbox state, Outbox preview/edit-copy and explicit
uncertain-record resolution, followed by undo-send, scheduling, background
execution and Sent reconciliation. The
[ordered parity roadmap](../../roadmaps/mail/README.md#desktop-mail-parity-ordered-increments)
keeps richer composition, account-wide search, organization and Calendar/People
as further qualified increments toward Outlook, Thunderbird and eM Client.
