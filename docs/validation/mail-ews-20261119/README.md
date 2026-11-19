# On-premises EWS validation — 19 November 2026

The EWS implementation was built on `0336116d6a07a16f5b46dbe07583b47ee9dcec83`.
This record covers native protocol fixtures, the existing mail regression suites,
JavaScript import isolation, storage contracts and the foreground Studio host.
It does **not** claim interoperability with a live Exchange installation, a
packaged desktop/mobile build, or a successful hosted CI run.

## Results

| Check | Result |
| --- | --- |
| `quds_mail_core` VM suite | 54 passed, including 5 new EWS identity cases |
| `quds_mail_mime` VM suite | 32 passed |
| `quds_mail_store` VM suite | 118 passed, including 8 new EWS persistence cases |
| `quds_mail_transport` VM suite | 227 passed, including EWS SOAP, provider, TLS, NTLM and configuration cases |
| Transport JavaScript/Node boundary | 11 passed: EWS unsupported (1), EWS configuration (7), existing IMAP unsupported (3) |
| Studio mail regression, 11 files | 157 passed, including all 15 new EWS widget cases |
| Focused EWS widget suite | 15 passed; these are included in the 157 above |
| Core, MIME, store and transport analysis | Clean with `--fatal-infos` |
| Changed Studio implementation, strings and tests | Flutter analysis clean |
| Independent NTLMv2 acceptor | 5 expected outcomes with pyspnego 0.12.4 |

The independent acceptor accepted an explicit Windows domain, `DOMAIN\user`,
and a UPN. It rejected a different TLS channel binding and a tampered MIC. It used
fixture credentials and a loopback certificate; it was not an Exchange server.

The Studio cases exercise manual NTLM setup, explicit Basic selection, password
controller clearing, pagination, MIME/attachment metadata in the shared reader,
read/flag/move/delete actions, capability gates, insecure endpoint rejection,
late-result isolation, composing/submitting MIME, uncertain-send acknowledgement,
redacted errors and a narrow layout. Review found and fixed a paging path that
could clear the refresh requirement after an unconfirmed mutation; the final
regression asserts that Load More cannot bypass this requirement.

## Evidence and source binding

- [Receipt](receipt.json) records commands, totals, environment, limits and hashes.
- [Source manifest](source-sha256.json) binds the mail packages and Studio mail
  sources/tests used for the final result.
- `logs/` contains compressed original successful run output. The Node run was
  observed in the session transcript; a raw Node log was not preserved.
- [Independent NTLM receipt](ntlm-interop-receipt.json) records the five outcomes
  and the exact NTLM/HTTP source hashes.
- [Dependency receipt](dependencies.json) records verified package inputs and
  successful offline resolution. No package version or archive hash changed.

The native suites used the official Dart 3.13.7 SDK in an isolated workspace with
direct symlinks to this checkout's library and test directories. All 203 entries
in the initial regression manifest were independently rehashed after review:
zero changes or missing files. The store suite and analysis were subsequently
rerun after formatting its new test file. The final source manifest records that
formatted file. The complete transport run used the same active source.
The Studio suites used the official Flutter 3.47.8 SDK and the actual
repository workspace. The root lockfile equals the base commit's lockfile.

## Reproduce

Use Flutter 3.47.8 / Dart 3.13.7 and resolve the root workspace:

```sh
flutter pub get
```

Run `dart analyze --fatal-infos` and `dart test` from each of
`packages/quds_mail_core`, `packages/quds_mail_mime`, `packages/quds_mail_store`
and `packages/quds_mail_transport`. From the transport package also run:

```sh
dart test --platform node test/ews_unsupported_test.dart \
  test/ews_configuration_test.dart test/unsupported_test.dart
```

From `packages/quds_office_editor/example`:

```sh
flutter analyze lib/studio_mail_ews.dart lib/studio_mail_native.dart \
  lib/studio_mail_strings.dart test/studio_mail_ews_test.dart
flutter test test/studio_mail*_test.dart test/studio_saved_mail_test.dart
```

The CI workflow now includes these mail package and Studio checks. Its remote
results are not part of this local qualification record.

## Live acceptance still required

Use the read-only [connection probe and deployment guide](../../roadmaps/mail/exchange-ews.md)
with an administrator-supplied EWS URL and trusted certificate chain. Verify the
actual IIS authentication/Extended Protection policy, any reverse proxy, and the
intended Exchange build. Then use a disposable mailbox for sending and mutation
acceptance. No endpoint or credentials were supplied for this work.

The supported scope is native EWS mail with host-owned credentials. The Studio
host keeps credentials, downloaded messages and unsent drafts in memory only.
There is no claim for Autodiscover, Kerberos, OAuth token acquisition, Calendar,
Contacts, full delegation, public/archive folders or durable Studio outbox
integration. A possibly accepted submission remains uncertain until reconciled;
the adapter never automatically repeats it.
