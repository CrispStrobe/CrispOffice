import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';

void main() {
  _bulkAdapterTests();
  _membershipAdapterTests();
  _flagObservationTests();
  _membershipObservationTests();
  _archiveDestinationTests();
  _archiveAdapterTests();
  _browsingTests();

  for (final flag in [false, true]) {
    for (final evidence in <bool?>[false, true, null]) {
      test(
        '${flag ? 'flag' : 'read'} failure preserves mutation evidence $evidence',
        () async {
          final harness = _Harness()
            ..applyAnswer = (_, _) async => MailFailure(
              MailProblem(
                MailProblemCode.permissionDenied,
                mutationMayHaveOccurred: evidence,
              ),
            );
          final loader = _loader(harness);
          addTearDown(loader.dispose);
          final header = _header();
          final pending = flag
              ? loader.setFlagged(_mailbox(), header, flagged: true)
              : loader.setRead(_mailbox(), header, read: false);
          await expectLater(
            pending,
            throwsA(
              _problemEvidence(MailProblemCode.permissionDenied, evidence),
            ),
          );
          expect(harness.mutations, hasLength(1));
          expect(header.flags, isNull);
        },
      );
    }
  }

  test(
    'provider construction failure certifies no mutation was invoked',
    () async {
      final harness = _Harness()..factoryError = StateError('private detail');
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      await expectLater(
        loader.markRead(_mailbox(), _header()),
        throwsA(_problemEvidence(MailProblemCode.providerFailure, false)),
      );
      expect(harness.mutations, isEmpty);
    },
  );

  test(
    'mark-read freezes the full identity and requires provider success',
    () async {
      final completed = Completer<MailResult<MailUnit>>();
      final harness = _Harness()..applyAnswer = (_, _) => completed.future;
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      final mailbox = _mailbox(uidValidity: 83);
      final header = _header(uid: 0xffffffff)..sequenceId = 2;

      final pending = loader.markRead(mailbox, header);
      final request = harness.mutations.single;
      final command = request.$1 as MailSetRead;
      final identity = command.message as MailImapIdentity;
      mailbox.uidValidity = 84;
      header.uid = 3;
      completed.complete(const MailSuccess(MailUnit.value));
      await pending;

      expect(command.read, isTrue);
      expect(command.id, isNotEmpty);
      expect(identity.mailbox.value, 'INBOX');
      expect(identity.uidValidity, 83);
      expect(identity.uid, 0xffffffff);
      expect(identity.account, harness.configuration!.account);
      expect(request.$2.isCurrent, isTrue);
      expect(harness.requests, isEmpty);
      expect(header.isSeen, isFalse);
    },
  );

  test(
    'mark-read refuses incomplete or stale identities without networking',
    () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      for (final uid in [null, 0, -1, 0x100000000]) {
        final header = _header(uid: uid)..sequenceId = 2;
        await expectLater(
          loader.markRead(_mailbox(), header),
          throwsA(_problemEvidence(MailProblemCode.invalidInput, false)),
        );
      }
      for (final validity in [null, 0, -1, 0x100000000]) {
        await expectLater(
          loader.markRead(_mailbox(uidValidity: validity), _header()),
          throwsA(_problemEvidence(MailProblemCode.invalidInput, false)),
        );
      }
      await expectLater(
        loader.markRead(
          _mailbox(flags: [mail.MailboxFlag.noSelect]),
          _header(),
        ),
        throwsA(_problemEvidence(MailProblemCode.invalidInput, false)),
      );
      final stale = _header()
        ..setGuid(
          email: 'fixture@example.test',
          encodedMailboxName: 'INBOX',
          mailboxUidValidity: 999,
        );
      await expectLater(
        loader.markRead(_mailbox(), stale),
        throwsA(_problemEvidence(MailProblemCode.conflict, false)),
      );
      expect(harness.factoryCalls, 0);
      expect(harness.mutations, isEmpty);
    },
  );

  test(
    'mark-read never retries or turns an unconfirmed write into success',
    () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      for (final code in MailProblemCode.values) {
        harness.applyAnswer = (_, _) async => MailFailure(MailProblem(code));
        final before = harness.mutations.length;
        await expectLater(
          loader.markRead(_mailbox(), _header()),
          throwsA(_problem(code)),
        );
        expect(harness.mutations.length, before + 1);
      }
      harness.applyAnswer = (_, _) =>
          throw StateError('private server response fixture-only-password');
      await expectLater(
        loader.markRead(_mailbox(), _header()),
        throwsA(_problemEvidence(MailProblemCode.providerFailure, null)),
      );
    },
  );

  test(
    'mark-read rejects a provider from another account before writing',
    () async {
      final harness = _Harness()
        ..providerAccount = MailAccountId(
          'foreign',
          profile: MailProfileId('foreign-profile', hostId: 'foreign-host'),
        );
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      await expectLater(
        loader.markRead(_mailbox(), _header()),
        throwsA(_problemEvidence(MailProblemCode.invalidInput, false)),
      );
      expect(harness.mutations, isEmpty);
    },
  );

  test(
    'a mark-read operation cancels an older read without replaying it',
    () async {
      final delayed = Completer<MailResult<MailMessage>>();
      final harness = _Harness()..answer = (_, _, _) => delayed.future;
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      final first = loader.fetch(_mailbox(), _header());
      final expectation = expectLater(
        first,
        throwsA(_problem(MailProblemCode.cancelled)),
      );

      await loader.markRead(_mailbox(), _header(uid: 8));
      await expectation;
      delayed.completeError(StateError('late read failure'));
      await Future<void>.delayed(Duration.zero);

      expect(harness.requests.single.lease.isCurrent, isFalse);
      expect(harness.mutations, hasLength(1));
      expect(harness.mutations.single.$2.isCurrent, isTrue);
    },
  );

  test(
    'a new read cancels a pending write and ignores late write completion',
    () async {
      final delayed = Completer<MailResult<MailUnit>>();
      final harness = _Harness()..applyAnswer = (_, _) => delayed.future;
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      final first = loader.markRead(_mailbox(), _header());
      final expectation = expectLater(
        first,
        throwsA(_problemEvidence(MailProblemCode.cancelled, null)),
      );

      expect(
        await loader.fetch(_mailbox(), _header(uid: 8)),
        orderedEquals(harness.raw),
      );
      await expectation;
      delayed.complete(const MailSuccess(MailUnit.value));
      await Future<void>.delayed(Duration.zero);

      expect(harness.mutations.single.$2.isCurrent, isFalse);
      expect(harness.mutations.single.$2.cancellation!.isCancelled, isTrue);
      expect(harness.mutations, hasLength(1));
    },
  );

  test(
    'dispose promptly cancels a pending mark-read and prohibits later writes',
    () async {
      final delayed = Completer<MailResult<MailUnit>>();
      final harness = _Harness()..applyAnswer = (_, _) => delayed.future;
      final loader = _loader(harness);
      final first = loader.markRead(_mailbox(), _header());
      final expectation = expectLater(
        first,
        throwsA(_problemEvidence(MailProblemCode.staleOperation, null)),
      );

      loader.dispose();
      await expectation.timeout(const Duration(seconds: 1));
      await expectLater(
        loader.markRead(_mailbox(), _header()),
        throwsA(_problemEvidence(MailProblemCode.staleOperation, false)),
      );
      final credentials = await harness.credentials!.load(
        harness.configuration!.credential,
      );
      expect((credentials as MailSuccess<MailCredentialRecord?>).value, isNull);
      expect(harness.mutations.single.$2.isCurrent, isFalse);
      expect(harness.factoryCalls, 1);
      delayed.completeError(StateError('late write failure'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'returns exact original non-UTF8 octets in an independent copy',
    () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);

      final result = await loader.fetch(_mailbox(), _header());

      expect(result, orderedEquals(harness.raw));
      expect(result, containsAllInOrder([0xe9, 0xff, 0x00, 0x80]));
      result[0] = 0;
      expect(harness.lastMessage!.raw.bytes[0], isNot(0));
      expect(harness.requests, hasLength(1));
    },
  );

  test('freezes exact mailbox generation and UID, never sequence ID', () async {
    final result = Completer<MailResult<MailMessage>>();
    final harness = _Harness()..answer = (_, _, _) => result.future;
    final loader = _loader(harness);
    addTearDown(loader.dispose);
    final mailbox = _mailbox(uidValidity: 83);
    final header = _header(uid: 0xffffffff)..sequenceId = 2;

    final pending = loader.fetch(mailbox, header);
    final request = harness.requests.single.identity as MailImapIdentity;
    mailbox.uidValidity = 84;
    header.uid = 3;
    result.complete(MailSuccess(harness.message(request)));

    await pending;
    expect(request.uidValidity, 83);
    expect(request.uid, 0xffffffff);
    expect(request.mailbox.value, 'INBOX');
  });

  test(
    'uses the decoded full path for international nested mailboxes',
    () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      final mailbox = mail.Mailbox(
        encodedName: '&BBoEPgRA- &BB8EPgRHBEIEMA-',
        encodedPath: 'Parent/&BBoEPgRA- &BB8EPgRHBEIEMA-',
        flags: [],
        pathSeparator: '/',
        uidValidity: 8,
      );

      await loader.fetch(mailbox, _header());

      final identity = harness.requests.single.identity as MailImapIdentity;
      expect(identity.mailbox.value, mailbox.path);
      expect(identity.mailbox.value, isNot(mailbox.encodedPath));
    },
  );

  test('passes every read budget and TLS transport bound unchanged', () async {
    const budget = MailReadBudget(
      maxRawBytes: 1000,
      maxDecodedBytes: 901,
      maxBodyBytes: 802,
      maxAttachmentBytes: 703,
      maxAttachments: 6,
      maxParts: 7,
      maxNestingDepth: 8,
      maxHeaderBytes: 500,
      maxHeaderFieldBytes: 201,
      maxHtmlNodes: 102,
      maxHtmlDepth: 13,
      maxRenderTextBytes: 704,
      maxImagePixels: 1005,
    );
    const limits = MailTransportLimits(operationTimeout: Duration(seconds: 7));
    final harness = _Harness();
    final loader = NativeStudioMailMessageLoader(
      _account(socketType: mail.SocketType.starttls, port: 143),
      providerFactory: harness.create,
      budget: budget,
      limits: limits,
    );
    addTearDown(loader.dispose);

    await loader.fetch(_mailbox(), _header());

    expect(identical(harness.requests.single.budget, budget), isTrue);
    expect(identical(harness.limits, limits), isTrue);
    expect(harness.configuration!.endpoint.tls, MailTlsMode.startTls);
    expect(harness.configuration!.endpoint.port, 143);
    expect(harness.configuration!.username, 'incoming-user');
  });

  test(
    'a scoped IMAP body read does not change the normal reader budget',
    () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      const budget = MailReadBudget(maxRawBytes: 2 * 1024 * 1024);
      final mailbox = _mailbox();
      final header = _header();
      await loader.fetchMessage(mailbox, header, readBudget: budget);
      await loader.fetch(mailbox, header);
      expect(harness.requests.first.budget, same(budget));
      expect(harness.requests.last.budget.maxRawBytes, 32 * 1024 * 1024);
      expect(harness.requests.first.identity, harness.requests.last.identity);
    },
  );

  test('full-message budget is the default', () async {
    final harness = _Harness();
    final loader = _loader(harness);
    addTearDown(loader.dispose);

    await loader.fetch(_mailbox(), _header());

    expect(harness.requests.single.budget.maxRawBytes, 32 * 1024 * 1024);
    expect(harness.configuration!.endpoint.tls, MailTlsMode.implicitTls);
  });

  test(
    'rejects invalid UID and UIDVALIDITY before provider creation',
    () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      for (final uid in [null, 0, -1, 0x100000000]) {
        await expectLater(
          loader.fetch(_mailbox(), _header(uid: uid)),
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
      }
      for (final validity in [null, 0, -1, 0x100000000]) {
        await expectLater(
          loader.fetch(_mailbox(uidValidity: validity), _header()),
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
      }
      expect(harness.factoryCalls, 0);
    },
  );

  test(
    'rejects invalid or unselectable mailbox before provider access',
    () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      for (final path in ['', 'bad\r\npath', 'x' * 1025]) {
        await expectLater(
          loader.fetch(_mailbox(path: path), _header()),
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
      }
      await expectLater(
        loader.fetch(_mailbox(flags: [mail.MailboxFlag.noSelect]), _header()),
        throwsA(_problem(MailProblemCode.invalidInput)),
      );
      expect(harness.factoryCalls, 0);
    },
  );

  test('rejects inconsistent envelope GUID before provider access', () async {
    final harness = _Harness();
    final loader = _loader(harness);
    addTearDown(loader.dispose);
    final header = _header()
      ..setGuid(
        email: 'fixture@example.test',
        encodedMailboxName: 'INBOX',
        mailboxUidValidity: 999,
      );

    await expectLater(
      loader.fetch(_mailbox(), header),
      throwsA(_problem(MailProblemCode.conflict)),
    );
    expect(harness.factoryCalls, 0);
  });

  test('accepts a matching high-level GUID with full identity', () async {
    final harness = _Harness();
    final loader = _loader(harness);
    addTearDown(loader.dispose);
    final mailbox = _mailbox();
    final header = _header()
      ..setGuid(
        email: 'fixture@example.test',
        encodedMailboxName: mailbox.encodedName,
        mailboxUidValidity: mailbox.uidValidity!,
      );

    expect(await loader.fetch(mailbox, header), orderedEquals(harness.raw));
  });

  test(
    'rejects unsupported accounts and insecure modes without a provider',
    () {
      final harness = _Harness();
      for (final account in [
        _account(type: mail.ServerType.pop),
        _account(type: mail.ServerType.unknown),
        _account(socketType: mail.SocketType.plain),
        _account(socketType: mail.SocketType.plainNoStartTls),
        _account(socketType: mail.SocketType.unknown),
        _account(
          authentication: mail.OauthAuthentication(
            'incoming-user',
            mail.OauthToken(
              accessToken: 'test-access-token',
              expiresIn: 3600,
              refreshToken: 'test-refresh-token',
              scope: 'test',
              tokenType: 'Bearer',
              created: DateTime.utc(2026),
            ),
          ),
        ),
      ]) {
        expect(
          () => NativeStudioMailMessageLoader(
            account,
            providerFactory: harness.create,
          ),
          throwsA(_problem(MailProblemCode.unsupported)),
        );
      }
      expect(harness.factoryCalls, 0);
    },
  );

  test(
    'rejects invalid credentials, endpoint and budgets before networking',
    () {
      final harness = _Harness();
      for (final account in [
        _account(host: 'https://invalid.example.test'),
        _account(host: ''),
        _account(port: 0),
        _account(port: 65536),
        _account(username: ''),
        _account(username: 'bad\nusername'),
        _account(password: ''),
        _account(password: 'bad\r\npassword'),
        _account(password: 'x' * (16 * 1024 + 1)),
        _account(password: 'é' * (16 * 1024)),
      ]) {
        expect(
          () => NativeStudioMailMessageLoader(
            account,
            providerFactory: harness.create,
          ),
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
      }
      for (final budget in [
        const MailReadBudget(maxRawBytes: 0),
        const MailReadBudget(maxBodyBytes: 0),
        const MailReadBudget(maxRawBytes: 64 * 1024 * 1024 + 1),
      ]) {
        expect(
          () => NativeStudioMailMessageLoader(
            _account(),
            budget: budget,
            providerFactory: harness.create,
          ),
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
      }
      expect(harness.factoryCalls, 0);
    },
  );

  test(
    'rejects wrong account, mailbox, UIDVALIDITY, UID or absent identity',
    () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      for (final mismatch in [
        'account',
        'mailbox',
        'validity',
        'uid',
        'absent',
      ]) {
        harness.answer = (requested, _, _) async {
          final identity = requested as MailImapIdentity;
          final wrong = MailImapIdentity(
            mailbox: MailMailboxId(
              mismatch == 'mailbox' ? 'Archive' : identity.mailbox.value,
              account: mismatch == 'account'
                  ? MailAccountId(
                      'other-account',
                      profile: identity.account.profile,
                    )
                  : identity.account,
            ),
            uidValidity:
                identity.uidValidity + (mismatch == 'validity' ? 1 : 0),
            uid: identity.uid + (mismatch == 'uid' ? 1 : 0),
          );
          return MailSuccess(
            harness.message(mismatch == 'absent' ? null : wrong),
          );
        };
        await expectLater(
          loader.fetch(_mailbox(), _header()),
          throwsA(_problem(MailProblemCode.conflict)),
        );
      }
    },
  );

  test(
    'rejects excess raw bytes even when an injected provider returns success',
    () async {
      final harness = _Harness();
      final loader = NativeStudioMailMessageLoader(
        _account(),
        providerFactory: harness.create,
        budget: const MailReadBudget(maxRawBytes: 8),
      );
      addTearDown(loader.dispose);

      await expectLater(
        loader.fetch(_mailbox(), _header()),
        throwsA(_problem(MailProblemCode.quotaExceeded)),
      );
    },
  );

  test(
    'cancel settles a stalled request and prevents a late completion',
    () async {
      final delayed = Completer<MailResult<MailMessage>>();
      final harness = _Harness()..answer = (_, _, _) => delayed.future;
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      final pending = loader.fetch(_mailbox(), _header());
      final expectation = expectLater(
        pending,
        throwsA(_problem(MailProblemCode.cancelled)),
      );
      final request = harness.requests.single;

      loader.cancel();
      await expectation.timeout(const Duration(seconds: 1));
      expect(request.lease.isCurrent, isFalse);
      expect(request.lease.cancellation!.isCancelled, isTrue);
      delayed.complete(MailSuccess(harness.message(request.identity)));

      harness.answer = null;
      expect(
        await loader.fetch(_mailbox(), _header(uid: 8)),
        orderedEquals(harness.raw),
      );
      expect(harness.factoryCalls, 2);
    },
  );

  test(
    'starting another read cancels the first lease and ignores its late error',
    () async {
      final delayed = Completer<MailResult<MailMessage>>();
      final harness = _Harness()..answer = (_, _, _) => delayed.future;
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      final first = loader.fetch(_mailbox(), _header());
      final expectation = expectLater(
        first,
        throwsA(_problem(MailProblemCode.cancelled)),
      );
      harness.answer = null;

      final second = await loader.fetch(_mailbox(), _header(uid: 9));
      await expectation;
      delayed.completeError(StateError('late server detail must not escape'));
      await Future<void>.delayed(Duration.zero);

      expect(second, orderedEquals(harness.raw));
      expect(harness.requests.first.lease.isCurrent, isFalse);
      expect(harness.requests.last.lease.isCurrent, isTrue);
    },
  );

  test(
    'dispose cancels in-flight work, clears credentials and refuses reuse',
    () async {
      final delayed = Completer<MailResult<MailMessage>>();
      final harness = _Harness()..answer = (_, _, _) => delayed.future;
      final loader = _loader(harness);
      final pending = loader.fetch(_mailbox(), _header());
      final expectation = expectLater(
        pending,
        throwsA(_problem(MailProblemCode.staleOperation)),
      );
      final reference = harness.configuration!.credential;
      final before = await harness.credentials!.load(reference);
      expect(
        utf8.decode(
          (before as MailSuccess<MailCredentialRecord?>)
              .value!
              .opaqueData
              .bytes,
        ),
        'fixture-only-password',
      );

      loader.dispose();
      loader.dispose();
      await expectation.timeout(const Duration(seconds: 1));
      final after = await harness.credentials!.load(reference);
      expect((after as MailSuccess<MailCredentialRecord?>).value, isNull);
      await expectLater(
        loader.fetch(_mailbox(), _header()),
        throwsA(_problem(MailProblemCode.staleOperation)),
      );
      expect(harness.factoryCalls, 1);
      delayed.complete(
        MailSuccess(harness.message(harness.requests.single.identity)),
      );
    },
  );

  test('credentials are account-scoped and cannot be overwritten', () async {
    final harness = _Harness();
    final loader = _loader(harness);
    addTearDown(loader.dispose);
    await loader.fetch(_mailbox(), _header());
    final reference = harness.configuration!.credential;
    final foreign = MailCredentialReference(
      account: MailAccountId('foreign', profile: reference.account.profile),
      key: reference.key,
    );
    final wrongKey = MailCredentialReference(
      account: reference.account,
      key: 'other',
    );

    for (final invalid in [foreign, wrongKey]) {
      expect(
        await harness.credentials!.load(invalid),
        isA<MailFailure<MailCredentialRecord?>>(),
      );
      expect(
        await harness.credentials!.delete(invalid),
        isA<MailFailure<MailUnit>>(),
      );
    }
    expect(
      await harness.credentials!.deleteAccount(foreign.account),
      isA<MailFailure<MailUnit>>(),
    );
    expect(
      await harness.credentials!.store(
        MailCredentialRecord(
          reference: reference,
          opaqueData: MailBytes(Uint8List(1)),
        ),
      ),
      isA<MailFailure<MailUnit>>(),
    );
    final valid = await harness.credentials!.load(reference);
    expect((valid as MailSuccess<MailCredentialRecord?>).value, isNotNull);
    await harness.credentials!.deleteAccount(reference.account);
    final removed = await harness.credentials!.load(reference);
    expect((removed as MailSuccess<MailCredentialRecord?>).value, isNull);
  });

  test(
    'distinct account sessions never share identity or credentials',
    () async {
      final first = _Harness();
      final second = _Harness();
      final loader1 = _loader(first);
      final loader2 = _loader(second);
      addTearDown(loader1.dispose);
      addTearDown(loader2.dispose);
      await loader1.fetch(_mailbox(), _header());
      await loader2.fetch(_mailbox(), _header());

      expect(
        first.configuration!.account,
        isNot(second.configuration!.account),
      );
      expect(
        await first.credentials!.load(second.configuration!.credential),
        isA<MailFailure<MailCredentialRecord?>>(),
      );
    },
  );

  test(
    'provider failures are fixed typed errors without server details',
    () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      for (final code in MailProblemCode.values) {
        harness.answer = (_, _, _) async => MailFailure(MailProblem(code));
        await expectLater(
          loader.fetch(_mailbox(), _header()),
          throwsA(_problem(code)),
        );
      }
      harness.answer = (_, _, _) =>
          throw StateError('fixture-only-password server body');
      try {
        await loader.fetch(_mailbox(), _header());
        fail('Expected a redacted failure.');
      } on StudioMailMessageLoadException catch (error) {
        expect(error.code, MailProblemCode.providerFailure);
        expect(error.toString(), 'The message could not be loaded. Try again.');
        expect(error.toString(), isNot(contains('fixture-only-password')));
      }
    },
  );
}

void _browsingTests() {
  group('native IMAP foreground browsing', () {
    test(
      'a reader-only provider cannot imply a successful empty mailbox',
      () async {
        final loader = NativeStudioMailMessageLoader(
          _account(),
          providerFactory:
              ({
                required configuration,
                required credentialStore,
                required limits,
              }) => _ReaderOnlyProvider(configuration.account),
        );
        addTearDown(loader.dispose);
        await expectLater(
          loader.fetchHeaders(_mailbox()),
          throwsA(_problem(MailProblemCode.unsupported)),
        );
      },
    );

    test(
      'projects complete envelopes and preserves unobserved flags without bodies',
      () async {
        final harness = _Harness();
        final sent = DateTime.utc(2026, 11, 20, 9);
        harness.headersAnswer = (mailbox, _, _, _) async => MailSuccess(
          MailHeaderPage(
            messages: [
              _record(
                mailbox,
                uid: 9,
                envelope: MailEnvelope(
                  subject: 'موضوع — Inbox',
                  from: const [
                    MailAddress('sender@example.test', displayName: 'Sender'),
                  ],
                  to: const [MailAddress('to@example.test')],
                  cc: const [MailAddress('cc@example.test')],
                  bcc: const [MailAddress('bcc@example.test')],
                  replyTo: const [MailAddress('reply@example.test')],
                  sentAt: sent,
                  messageId: '<message@example.test>',
                  inReplyTo: '<parent@example.test>',
                  references: const [
                    '<root@example.test>',
                    '<parent@example.test>',
                  ],
                ),
              ),
              _record(mailbox, uid: 8, flags: const MailMessageFlags()),
              _record(
                mailbox,
                uid: 7,
                flags: const MailMessageFlags(
                  isRead: true,
                  isFlagged: true,
                  isAnswered: true,
                  isDraft: true,
                  isDeleted: true,
                ),
              ),
            ],
          ),
        );
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final page = await loader.fetchHeaders(_mailbox(), limit: 3);
        expect(page.messages.map((message) => message.uid), [9, 8, 7]);
        final first = page.messages.first;
        expect(first.decodeSubject(), 'موضوع — Inbox');
        expect(first.decodeDate(), sent);
        expect(first.from!.single.email, 'sender@example.test');
        expect(first.from!.single.personalName, 'Sender');
        expect(first.to!.single.email, 'to@example.test');
        expect(first.cc!.single.email, 'cc@example.test');
        expect(first.bcc!.single.email, 'bcc@example.test');
        expect(first.replyTo!.single.email, 'reply@example.test');
        expect(first.getHeaderValue('Message-ID'), '<message@example.test>');
        expect(first.getHeaderValue('In-Reply-To'), '<parent@example.test>');
        expect(
          first.getHeaderValue('References'),
          '<root@example.test> <parent@example.test>',
        );
        expect(first.flags, isNull);
        expect(page.messages[1].flags, isEmpty);
        expect(
          page.messages[2].flags,
          containsAll([
            r'\Seen',
            r'\Flagged',
            r'\Answered',
            r'\Draft',
            r'\Deleted',
          ]),
        );
        expect(first.decodeTextPlainPart(), isNull);
        expect(first.decodeTextHtmlPart(), isNull);
        expect(first.sequenceId, isNull);
        expect(() => page.messages.add(_header()), throwsUnsupportedError);
        expect(harness.requests, isEmpty);
        expect(harness.mutations, isEmpty);
        expect(harness.headerRequests.single.limit, 3);
        expect(harness.requestedValidities, [41]);
      },
    );

    test(
      'freezes the selected path and generation before asynchronous browsing',
      () async {
        final delayed = Completer<MailResult<MailHeaderPage>>();
        final harness = _Harness()
          ..headersAnswer = (_, _, _, _) => delayed.future;
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final selected = _mailbox(path: 'Projects/Original', uidValidity: 83);
        final pending = loader.fetchHeaders(selected);
        final request = harness.headerRequests.single;
        selected.uidValidity = 84;
        delayed.complete(
          MailSuccess(
            MailHeaderPage(
              messages: [_record(request.mailbox, uid: 9, uidValidity: 83)],
            ),
          ),
        );
        final page = await pending;
        expect(harness.requestedValidities, [83]);
        expect(request.mailbox.value, 'Projects/Original');
        expect(page.messages.single.uid, 9);
        await expectLater(
          loader.fetch(selected, page.messages.single),
          throwsA(_problem(MailProblemCode.conflict)),
        );
        expect(harness.requests, isEmpty);
      },
    );

    test(
      'pages retain descending order and reject a consumed continuation before networking',
      () async {
        final harness = _Harness()
          ..headersAnswer = (mailbox, cursor, _, _) async => MailSuccess(
            MailHeaderPage(
              messages: [
                for (final uid in cursor == null ? [9, 8] : [7, 6])
                  _record(mailbox, uid: uid),
              ],
              next: MailCursor(
                mailbox: mailbox,
                value: cursor == null ? 'next-1' : 'next-2',
              ),
            ),
          );
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final first = await loader.fetchHeaders(_mailbox());
        final second = await loader.fetchHeaders(
          _mailbox(),
          cursor: first.next,
        );
        expect(first.messages.map((message) => message.uid), [9, 8]);
        expect(second.messages.map((message) => message.uid), [7, 6]);
        await expectLater(
          loader.fetchHeaders(_mailbox(), cursor: first.next),
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
        expect(harness.headerRequests, hasLength(2));
      },
    );

    test(
      'refresh starts a new snapshot and permits newly arrived UIDs',
      () async {
        final harness = _Harness()
          ..headersAnswer = (mailbox, _, _, _) async => MailSuccess(
            MailHeaderPage(
              messages: [_record(mailbox, uid: 9)],
              next: MailCursor(
                mailbox: mailbox,
                value: 'same-position-on-refresh',
              ),
            ),
          );
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        await loader.fetchHeaders(_mailbox());
        expect((await loader.fetchHeaders(_mailbox())).messages.single.uid, 9);
        expect(harness.headerRequests, hasLength(2));
      },
    );

    for (final fault in [
      'account',
      'mailbox',
      'provider',
      'generation',
      'duplicate-uid',
      'duplicate-id',
      'unordered',
      'oversize',
    ]) {
      test('rejects $fault page before exposing any headers', () async {
        final harness = _Harness();
        harness.headersAnswer = (mailbox, _, _, _) async {
          final otherMailbox = MailMailboxId('Other', account: mailbox.account);
          final foreignAccount = MailAccountId(
            'other',
            profile: mailbox.account.profile,
          );
          final bad = switch (fault) {
            'account' => _record(
              MailMailboxId(mailbox.value, account: foreignAccount),
              uid: 7,
            ),
            'mailbox' => _record(otherMailbox, uid: 7),
            'provider' => _record(
              mailbox,
              uid: 7,
              remote: MailOpaqueIdentity(
                account: mailbox.account,
                provider: MailProviderKind.ews,
                value: 'foreign',
              ),
            ),
            'generation' => _record(mailbox, uid: 7, uidValidity: 42),
            'duplicate-uid' => _record(
              mailbox,
              uid: 8,
              id: MailMessageId('different-id'),
            ),
            'duplicate-id' => _record(
              mailbox,
              uid: 7,
              id: MailMessageId('message-8'),
            ),
            'unordered' => _record(mailbox, uid: 9),
            _ => _record(mailbox, uid: 7),
          };
          return MailSuccess(
            MailHeaderPage(messages: [_record(mailbox, uid: 8), bad]),
          );
        };
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        await expectLater(
          loader.fetchHeaders(_mailbox(), limit: fault == 'oversize' ? 1 : 2),
          throwsA(
            _problem(
              fault == 'generation'
                  ? MailProblemCode.conflict
                  : MailProblemCode.providerFailure,
            ),
          ),
        );
        expect(harness.headerRequests, hasLength(1));
        expect(harness.requests, isEmpty);
      });
    }

    test(
      'cross-page repeated messages cannot hide behind a new cursor',
      () async {
        final harness = _Harness()
          ..headersAnswer = (mailbox, cursor, _, _) async => MailSuccess(
            MailHeaderPage(
              messages: [_record(mailbox, uid: 9)],
              next: MailCursor(
                mailbox: mailbox,
                value: cursor == null ? 'next-1' : 'next-2',
              ),
            ),
          );
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final first = await loader.fetchHeaders(_mailbox());
        await expectLater(
          loader.fetchHeaders(_mailbox(), cursor: first.next),
          throwsA(_problem(MailProblemCode.providerFailure)),
        );
      },
    );

    for (final fault in ['mailbox', 'empty', 'oversize', 'repeat', 'cycle']) {
      test('rejects $fault continuation tokens', () async {
        final harness = _Harness();
        var pages = 0;
        harness.headersAnswer = (mailbox, cursor, _, _) async {
          pages++;
          final invalid = switch (fault) {
            'empty' => '',
            'oversize' => 'x' * 257,
            'repeat' => 'next-1',
            'cycle' => pages < 3 ? 'next-$pages' : 'next-1',
            _ => 'next-$pages',
          };
          return MailSuccess(
            MailHeaderPage(
              messages: [_record(mailbox, uid: 10 - pages)],
              next: MailCursor(
                mailbox: fault == 'mailbox'
                    ? MailMailboxId('Other', account: mailbox.account)
                    : mailbox,
                value: invalid,
              ),
            ),
          );
        };
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        MailCursor? cursor;
        if (fault == 'repeat' || fault == 'cycle') {
          cursor = (await loader.fetchHeaders(_mailbox())).next;
        }
        if (fault == 'cycle') {
          cursor = (await loader.fetchHeaders(_mailbox(), cursor: cursor)).next;
        }
        await expectLater(
          loader.fetchHeaders(_mailbox(), cursor: cursor),
          throwsA(_problem(MailProblemCode.providerFailure)),
        );
      });
    }

    test(
      'failed next pages retain their cursor for explicit retry without automatic replay',
      () async {
        final harness = _Harness();
        var failNext = true;
        harness.headersAnswer = (mailbox, cursor, _, _) async {
          if (cursor != null && failNext) {
            return const MailFailure(MailProblem(MailProblemCode.unavailable));
          }
          return MailSuccess(
            MailHeaderPage(
              messages: [_record(mailbox, uid: cursor == null ? 9 : 8)],
              next: cursor == null
                  ? MailCursor(mailbox: mailbox, value: 'next')
                  : null,
            ),
          );
        };
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final first = await loader.fetchHeaders(_mailbox());
        await expectLater(
          loader.fetchHeaders(_mailbox(), cursor: first.next),
          throwsA(_problem(MailProblemCode.unavailable)),
        );
        expect(harness.headerRequests, hasLength(2));
        failNext = false;
        expect(
          (await loader.fetchHeaders(
            _mailbox(),
            cursor: first.next,
          )).messages.single.uid,
          8,
        );
        expect(harness.headerRequests, hasLength(3));
      },
    );

    test(
      'empty expunged pages may progress and do not erase preceding UID bounds',
      () async {
        final harness = _Harness();
        var pages = 0;
        harness.headersAnswer = (mailbox, _, _, _) async {
          pages++;
          return MailSuccess(
            MailHeaderPage(
              messages: pages == 2
                  ? []
                  : [_record(mailbox, uid: pages == 1 ? 9 : 8)],
              next: pages == 3
                  ? null
                  : MailCursor(mailbox: mailbox, value: 'next-$pages'),
            ),
          );
        };
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final first = await loader.fetchHeaders(_mailbox());
        final second = await loader.fetchHeaders(
          _mailbox(),
          cursor: first.next,
        );
        expect(second.messages, isEmpty);
        expect(
          (await loader.fetchHeaders(
            _mailbox(),
            cursor: second.next,
          )).messages.single.uid,
          8,
        );
      },
    );

    test(
      'invalid page requests and foreign cursors fail before provider creation',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        for (final limit in [0, -1, 501]) {
          await expectLater(
            loader.fetchHeaders(_mailbox(), limit: limit),
            throwsA(_problem(MailProblemCode.invalidInput)),
          );
        }
        await expectLater(
          loader.fetchHeaders(_mailbox(uidValidity: null)),
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
        final foreign = MailMailboxId(
          'INBOX',
          account: MailAccountId(
            'foreign',
            profile: MailProfileId('foreign', hostId: 'foreign'),
          ),
        );
        await expectLater(
          loader.fetchHeaders(
            _mailbox(),
            cursor: MailCursor(mailbox: foreign, value: 'other'),
          ),
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
        expect(harness.factoryCalls, 0);
      },
    );

    test(
      'cancellation and disposal suppress late browsing completions',
      () async {
        for (final dispose in [false, true]) {
          final delayed = Completer<MailResult<MailHeaderPage>>();
          final harness = _Harness()
            ..headersAnswer = (_, _, _, _) => delayed.future;
          final loader = _loader(harness);
          addTearDown(loader.dispose);
          final pending = loader.fetchHeaders(_mailbox());
          final expectation = expectLater(
            pending,
            throwsA(
              _problem(
                dispose
                    ? MailProblemCode.staleOperation
                    : MailProblemCode.cancelled,
              ),
            ),
          );
          if (dispose) {
            loader.dispose();
          } else {
            loader.cancel();
          }
          await expectation;
          expect(harness.headerRequests.single.lease.isCurrent, isFalse);
          delayed.completeError(StateError('late private provider error'));
          await Future<void>.delayed(Duration.zero);
          expect(harness.headerRequests, hasLength(1));
        }
      },
    );

    test(
      'projected header identity cannot be retargeted through mutable fields or another session',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        final otherHarness = _Harness();
        final other = _loader(otherHarness);
        addTearDown(loader.dispose);
        addTearDown(other.dispose);
        final header = (await loader.fetchHeaders(_mailbox())).messages.single;
        await expectLater(
          loader.setFlagged(_mailbox(path: 'Other'), header, flagged: true),
          throwsA(_problem(MailProblemCode.conflict)),
        );
        await expectLater(
          other.fetch(_mailbox(), header),
          throwsA(_problem(MailProblemCode.conflict)),
        );
        header.uid = 8;
        header.guid = null;
        await expectLater(
          loader.setRead(_mailbox(), header, read: false),
          throwsA(_problem(MailProblemCode.conflict)),
        );
        expect(harness.mutations, isEmpty);
        expect(otherHarness.requests, isEmpty);
      },
    );
  });

  group('native IMAP confirmed message actions', () {
    test(
      'read/unread and flag/unflag preserve exact typed identities and await confirmation',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        for (final flagged in [false, true]) {
          for (final value in [false, true]) {
            final delayed = Completer<MailResult<MailUnit>>();
            harness.applyAnswer = (_, _) => delayed.future;
            final mailbox = _mailbox(uidValidity: 83);
            final header = _header(uid: 91);
            var finished = false;
            final pending =
                (flagged
                        ? loader.setFlagged(mailbox, header, flagged: value)
                        : loader.setRead(mailbox, header, read: value))
                    .then((_) {
                      finished = true;
                    });
            final operation = harness.mutations.last.$1;
            final identity = operation.message as MailImapIdentity;
            mailbox.uidValidity = 84;
            header.uid = 92;
            expect(finished, isFalse);
            if (flagged) {
              expect((operation as MailSetFlagged).flagged, value);
            } else {
              expect((operation as MailSetRead).read, value);
            }
            expect(identity.uidValidity, 83);
            expect(identity.uid, 91);
            delayed.complete(const MailSuccess(MailUnit.value));
            await pending;
            expect(finished, isTrue);
            expect(header.flags, isNull);
          }
        }
        expect(
          harness.mutations.map((entry) => entry.$1.id).toSet(),
          hasLength(4),
        );
      },
    );

    test(
      'unconfirmed flag and unread writes never replay or mutate the projection',
      () async {
        final harness = _Harness()
          ..applyAnswer = (_, _) async =>
              const MailFailure(MailProblem(MailProblemCode.conflict));
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final header = _header()..flags = [mail.MessageFlags.seen];
        await expectLater(
          loader.setRead(_mailbox(), header, read: false),
          throwsA(_problem(MailProblemCode.conflict)),
        );
        await expectLater(
          loader.setFlagged(_mailbox(), header, flagged: true),
          throwsA(_problem(MailProblemCode.conflict)),
        );
        expect(header.flags, [mail.MessageFlags.seen]);
        expect(harness.mutations, hasLength(2));
      },
    );

    test(
      'cancelled flag write observes late failures and leaves session reusable',
      () async {
        final delayed = Completer<MailResult<MailUnit>>();
        final harness = _Harness()..applyAnswer = (_, _) => delayed.future;
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final pending = loader.setFlagged(_mailbox(), _header(), flagged: true);
        final expectation = expectLater(
          pending,
          throwsA(_problem(MailProblemCode.cancelled)),
        );
        loader.cancel();
        await expectation;
        delayed.completeError(StateError('late private mutation reply'));
        await Future<void>.delayed(Duration.zero);
        harness.applyAnswer = (_, _) async => const MailSuccess(MailUnit.value);
        await loader.setFlagged(_mailbox(), _header(), flagged: false);
        expect(harness.mutations, hasLength(2));
        expect(harness.mutations.first.$2.isCurrent, isFalse);
      },
    );
  });
}

const _archiveProfile = MailArchiveProfile(
  id: 'imap-fixture',
  name: 'Fixture folder',
  source: 'fixture@example.test',
  kind: MailArchiveProfileKind.mailbox,
  folder: 'INBOX',
  includeSubfolders: false,
);

MailHeaderRecord _record(
  MailMailboxId mailbox, {
  int uid = 7,
  int uidValidity = 41,
  MailRemoteIdentity? remote,
  MailMessageId? id,
  MailEnvelope? envelope,
  MailMessageFlags? flags,
}) => MailHeaderRecord(
  id: id ?? MailMessageId('message-$uid'),
  remote:
      remote ??
      MailImapIdentity(mailbox: mailbox, uidValidity: uidValidity, uid: uid),
  envelope: envelope ?? MailEnvelope(subject: 'Header projection'),
  flags: flags,
);

T _success<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _archiveAdapterTests() {
  group('native IMAP folder archive', () {
    late Directory temporary;
    late SqliteMailArchive archive;
    MailArchiveFaultInjector? fault;

    setUp(() async {
      fault = null;
      temporary = await Directory.systemTemp.createTemp('studio-imap-archive-');
      archive = _success(
        await openNativeMailArchive(
          appDirectory: temporary,
          profile: MailProfileId('archive', hostId: 'studio-imap-tests'),
          faultInjector: (checkpoint) async => fault?.call(checkpoint),
        ),
      );
    });

    tearDown(() async {
      await archive.close();
      await temporary.delete(recursive: true);
    });

    test(
      'collects exact originals across pages with bounded reads and no writes',
      () async {
        final harness = _Harness();
        final originals = <String, Uint8List>{};
        harness.headersAnswer = (mailbox, cursor, _, _) async => MailSuccess(
          MailHeaderPage(
            messages: [
              for (final uid in cursor == null ? [7, 8] : [9])
                _record(mailbox, uid: uid),
            ],
            next: cursor == null
                ? MailCursor(mailbox: mailbox, value: 'second-page')
                : null,
          ),
        );
        harness.answer = (identity, _, _) async {
          final bytes = Uint8List.fromList([
            ...harness.raw,
            (identity as MailImapIdentity).uid,
          ]);
          final raw = MailBytes(bytes);
          originals[raw.sha256] = Uint8List.fromList(bytes);
          return MailSuccess(
            MailMessage(
              raw: raw,
              envelope: MailEnvelope(subject: 'Exact original'),
              remoteIdentity: identity,
            ),
          );
        };
        const budget = MailReadBudget(maxRawBytes: 4096, maxAttachments: 4);
        const limits = MailTransportLimits(maxPageSize: 2);
        final loader = NativeStudioMailMessageLoader(
          _account(),
          providerFactory: harness.create,
          budget: budget,
          limits: limits,
        );
        addTearDown(loader.dispose);
        final events = <MailArchiveRunProgress>[];

        final result = await loader.archiveMailbox(
          _mailbox(),
          archive: archive,
          profile: _archiveProfile,
          onProgress: events.add,
        );

        expect(result.status, MailArchiveRunStatus.completed);
        expect(result.pages, 2);
        expect(result.saved, 3);
        expect(result.processed, 3);
        expect(result.failed, 0);
        expect(
          result.bytes,
          originals.values.fold<int>(0, (sum, raw) => sum + raw.length),
        );
        expect(harness.headerRequests.map((request) => request.limit), [2, 2]);
        expect(harness.headerRequests.first.cursor, isNull);
        expect(harness.headerRequests.last.cursor!.value, 'second-page');
        expect(
          harness.requests.map((request) => request.budget.maxRawBytes),
          everyElement(4096),
        );
        expect(
          harness.requests.map((request) => request.budget.maxAttachments),
          everyElement(4),
        );
        expect(harness.mutations, isEmpty);
        final stats = _success(await archive.statistics());
        expect(stats.messages, 3);
        expect(stats.origins, 3);
        for (final entry in originals.entries) {
          expect(
            _success(await archive.loadOriginal(entry.key))!.bytes,
            orderedEquals(entry.value),
          );
        }
        expect(events.first.phase, MailArchiveRunPhase.started);
        expect(events.last.phase, MailArchiveRunPhase.finished);
        final log = jsonEncode(events.map((event) => event.toJson()).toList());
        expect(log, isNot(contains('fixture@example.test')));
        expect(log, isNot(contains('Exact original')));
        expect(log, isNot(contains('fixture-only-password')));
        expect(log, isNot(contains('second-page')));
      },
    );

    test(
      'freezes selected mailbox path and UIDVALIDITY before awaits',
      () async {
        final delayed = Completer<MailResult<MailHeaderPage>>();
        final harness = _Harness()
          ..headersAnswer = (_, _, _, _) => delayed.future;
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        var selected = _mailbox(path: 'Projects/Original', uidValidity: 83);
        final pending = loader.archiveMailbox(
          selected,
          archive: archive,
          profile: _archiveProfile,
        );
        final requested = harness.headerRequests.single.mailbox;
        selected.uidValidity = 84;
        selected = _mailbox(path: 'Projects/Changed', uidValidity: 84);
        delayed.complete(
          MailSuccess(
            MailHeaderPage(messages: [_record(requested, uidValidity: 83)]),
          ),
        );

        expect((await pending).saved, 1);
        final remote = harness.requests.single.identity as MailImapIdentity;
        expect(remote.mailbox.value, 'Projects/Original');
        expect(remote.uidValidity, 83);
        expect(selected.path, 'Projects/Changed');
      },
    );

    test(
      'rejects incomplete, invalid and non-selectable snapshots before networking',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final invalid = [
          _mailbox(flags: [mail.MailboxFlag.noSelect]),
          for (final validity in [null, 0, -1, 0x100000000])
            _mailbox(uidValidity: validity),
          for (final path in ['', '  ', 'bad\r\nfolder', 'x' * 1025])
            _mailbox(path: path),
        ];
        for (final mailbox in invalid) {
          final result = await loader.archiveMailbox(
            mailbox,
            archive: archive,
            profile: _archiveProfile,
          );
          expect(result.status, MailArchiveRunStatus.failed);
          expect(result.problem!.code, MailProblemCode.invalidInput);
          expect(result.processed, 0);
        }
        expect(harness.factoryCalls, 0);
        expect(harness.headerRequests, isEmpty);
        expect(_success(await archive.statistics()).messages, 0);
      },
    );

    test(
      'rejects a foreign provider account before reading any page',
      () async {
        final harness = _Harness()
          ..providerAccount = MailAccountId(
            'foreign',
            profile: MailProfileId('foreign', hostId: 'foreign'),
          );
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final result = await loader.archiveMailbox(
          _mailbox(),
          archive: archive,
          profile: _archiveProfile,
        );
        expect(result.status, MailArchiveRunStatus.failed);
        expect(result.problem!.code, MailProblemCode.invalidInput);
        expect(harness.headerRequests, isEmpty);
        expect(harness.requests, isEmpty);
      },
    );

    test(
      'sanitizes a throwing provider factory and leaves the loader reusable',
      () async {
        final harness = _Harness()
          ..factoryError = StateError(
            'fixture-only-password private server body',
          );
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final result = await loader.archiveMailbox(
          _mailbox(),
          archive: archive,
          profile: _archiveProfile,
        );
        expect(result.status, MailArchiveRunStatus.failed);
        expect(result.problem!.code, MailProblemCode.providerFailure);
        expect(result.failures, isEmpty);
        expect(
          result.problem.toString(),
          isNot(contains('fixture-only-password')),
        );
        expect(harness.headerRequests, isEmpty);
        harness.factoryError = null;
        expect(
          (await loader.archiveMailbox(
            _mailbox(),
            archive: archive,
            profile: _archiveProfile,
          )).saved,
          1,
        );
      },
    );

    for (final mismatch in [
      'account',
      'mailbox',
      'provider',
      'generation',
      'local-id',
      'cursor',
    ]) {
      test(
        'validates the whole page before writes for a mismatched $mismatch',
        () async {
          final harness = _Harness();
          harness.headersAnswer = (mailbox, _, _, _) async {
            final foreignAccount = MailAccountId(
              'foreign',
              profile: mailbox.account.profile,
            );
            final foreignMailbox = MailMailboxId(
              'Other',
              account: mailbox.account,
            );
            final remote = switch (mismatch) {
              'account' => MailImapIdentity(
                mailbox: MailMailboxId(mailbox.value, account: foreignAccount),
                uidValidity: 41,
                uid: 8,
              ),
              'mailbox' => MailImapIdentity(
                mailbox: foreignMailbox,
                uidValidity: 41,
                uid: 8,
              ),
              'provider' => MailOpaqueIdentity(
                account: mailbox.account,
                provider: MailProviderKind.graph,
                value: 'opaque',
              ),
              'generation' => MailImapIdentity(
                mailbox: mailbox,
                uidValidity: 42,
                uid: 8,
              ),
              _ => MailImapIdentity(mailbox: mailbox, uidValidity: 41, uid: 8),
            };
            return MailSuccess(
              MailHeaderPage(
                messages: [
                  _record(mailbox),
                  _record(
                    mailbox,
                    uid: 8,
                    remote: remote,
                    id: mismatch == 'local-id'
                        ? MailMessageId('message-7')
                        : null,
                  ),
                ],
                next: mismatch == 'cursor'
                    ? MailCursor(
                        mailbox: foreignMailbox,
                        value: 'foreign-cursor',
                      )
                    : null,
              ),
            );
          };
          final loader = _loader(harness);
          addTearDown(loader.dispose);
          final result = await loader.archiveMailbox(
            _mailbox(),
            archive: archive,
            profile: _archiveProfile,
          );
          expect(result.status, MailArchiveRunStatus.failed);
          expect(
            result.problem!.code,
            mismatch == 'generation'
                ? MailProblemCode.conflict
                : MailProblemCode.providerFailure,
          );
          expect(result.saved, 0);
          expect(result.pages, 0);
          expect(harness.requests, isEmpty);
          expect(harness.mutations, isEmpty);
          expect(_success(await archive.statistics()).messages, 0);
        },
      );
    }

    test('refuses oversized pages before reading any original', () async {
      final harness = _Harness()
        ..headersAnswer = (mailbox, _, _, _) async => MailSuccess(
          MailHeaderPage(
            messages: [_record(mailbox), _record(mailbox, uid: 8)],
          ),
        );
      final loader = NativeStudioMailMessageLoader(
        _account(),
        providerFactory: harness.create,
        limits: const MailTransportLimits(maxPageSize: 1),
      );
      addTearDown(loader.dispose);
      final result = await loader.archiveMailbox(
        _mailbox(),
        archive: archive,
        profile: _archiveProfile,
      );
      expect(result.status, MailArchiveRunStatus.failed);
      expect(result.problem!.code, MailProblemCode.providerFailure);
      expect(harness.requests, isEmpty);
    });

    test(
      'retains committed counts if the next page changes generation',
      () async {
        final harness = _Harness()
          ..headersAnswer = (mailbox, cursor, _, _) async => MailSuccess(
            MailHeaderPage(
              messages: [
                _record(
                  mailbox,
                  uid: cursor == null ? 7 : 8,
                  uidValidity: cursor == null ? 41 : 42,
                ),
              ],
              next: cursor == null
                  ? MailCursor(mailbox: mailbox, value: 'next')
                  : null,
            ),
          );
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final result = await loader.archiveMailbox(
          _mailbox(),
          archive: archive,
          profile: _archiveProfile,
        );
        expect(result.status, MailArchiveRunStatus.partial);
        expect(result.problem!.code, MailProblemCode.conflict);
        expect(result.saved, 1);
        expect(result.pages, 1);
        expect(harness.requests, hasLength(1));
        expect(_success(await archive.statistics()).messages, 1);
      },
    );

    test(
      'rejects mismatched fetched identities and continues the bounded page',
      () async {
        final harness = _Harness()
          ..headersAnswer = (mailbox, _, _, _) async => MailSuccess(
            MailHeaderPage(
              messages: [_record(mailbox), _record(mailbox, uid: 8)],
            ),
          );
        harness.answer = (identity, _, _) async {
          final remote = identity as MailImapIdentity;
          return MailSuccess(
            harness.message(
              remote.uid == 7
                  ? MailImapIdentity(
                      mailbox: remote.mailbox,
                      uidValidity: 99,
                      uid: remote.uid,
                    )
                  : remote,
            ),
          );
        };
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final result = await loader.archiveMailbox(
          _mailbox(),
          archive: archive,
          profile: _archiveProfile,
        );
        expect(result.status, MailArchiveRunStatus.partial);
        expect(result.saved, 1);
        expect(result.failed, 1);
        expect(result.failures.single.stage, MailArchiveRunStage.identity);
        expect(_success(await archive.statistics()).messages, 1);
      },
    );

    test('starting archive cancels a stalled selected-message read', () async {
      final delayed = Completer<MailResult<MailMessage>>();
      final harness = _Harness()..answer = (_, _, _) => delayed.future;
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      final read = loader.fetch(_mailbox(), _header());
      final cancelledRead = expectLater(
        read,
        throwsA(_problem(MailProblemCode.cancelled)),
      );
      harness.answer = null;
      final result = await loader.archiveMailbox(
        _mailbox(),
        archive: archive,
        profile: _archiveProfile,
      );
      await cancelledRead;
      delayed.completeError(StateError('late private read failure'));
      await Future<void>.delayed(Duration.zero);
      expect(result.saved, 1);
      expect(harness.requests.first.lease.isCurrent, isFalse);
      expect(harness.mutations, isEmpty);
    });

    for (final dispose in [false, true]) {
      for (final stage in ['headers', 'message']) {
        test(
          '${dispose ? 'dispose' : 'cancel'} releases stalled $stage and ignores late completion',
          () async {
            final headers = Completer<MailResult<MailHeaderPage>>();
            final message = Completer<MailResult<MailMessage>>();
            final started = Completer<void>();
            final harness = _Harness();
            if (stage == 'headers') {
              harness.headersAnswer = (_, _, _, _) {
                started.complete();
                return headers.future;
              };
            } else {
              harness.answer = (_, _, _) {
                started.complete();
                return message.future;
              };
            }
            final loader = _loader(harness);
            addTearDown(loader.dispose);
            final pending = loader.archiveMailbox(
              _mailbox(),
              archive: archive,
              profile: _archiveProfile,
            );
            await started.future;
            if (dispose) {
              loader.dispose();
            } else {
              loader.cancel();
            }
            final result = await pending.timeout(const Duration(seconds: 2));
            expect(result.status, MailArchiveRunStatus.cancelled);
            expect(
              result.problem!.code,
              dispose
                  ? MailProblemCode.staleOperation
                  : MailProblemCode.cancelled,
            );
            expect(result.saved, 0);
            expect(result.failed, 0);
            if (stage == 'headers') {
              headers.completeError(StateError('late private server error'));
            } else {
              message.complete(
                MailSuccess(harness.message(harness.requests.single.identity)),
              );
            }
            await Future<void>.delayed(Duration.zero);
            expect(_success(await archive.statistics()).messages, 0);
            expect(harness.mutations, isEmpty);
            if (dispose) {
              expect(
                _success(
                  await harness.credentials!.load(
                    harness.configuration!.credential,
                  ),
                ),
                isNull,
              );
              expect(
                (await loader.archiveMailbox(
                  _mailbox(),
                  archive: archive,
                  profile: _archiveProfile,
                )).problem!.code,
                MailProblemCode.staleOperation,
              );
            } else {
              harness.headersAnswer = null;
              harness.answer = null;
              expect(
                (await loader.archiveMailbox(
                  _mailbox(),
                  archive: archive,
                  profile: _archiveProfile,
                )).saved,
                1,
              );
            }
          },
        );
      }
    }

    test(
      'a replacement read cancels archive without its cleanup clearing the new read',
      () async {
        final headers = Completer<MailResult<MailHeaderPage>>();
        final message = Completer<MailResult<MailMessage>>();
        final harness = _Harness();
        harness.headersAnswer = (_, _, _, _) => headers.future;
        harness.answer = (_, _, _) => message.future;
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final pendingArchive = loader.archiveMailbox(
          _mailbox(),
          archive: archive,
          profile: _archiveProfile,
        );
        final pendingRead = loader.fetch(_mailbox(), _header(uid: 8));
        final cancelledRead = expectLater(
          pendingRead,
          throwsA(_problem(MailProblemCode.cancelled)),
        );
        expect((await pendingArchive).status, MailArchiveRunStatus.cancelled);
        loader.cancel();
        await cancelledRead;
        headers.completeError(StateError('late headers'));
        message.completeError(StateError('late read'));
        await Future<void>.delayed(Duration.zero);
        expect(_success(await archive.statistics()).messages, 0);
      },
    );

    test('pre-cancelled caller token does not start a provider', () async {
      final source = MailCancellationSource()..cancel();
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      final result = await loader.archiveMailbox(
        _mailbox(),
        archive: archive,
        profile: _archiveProfile,
        cancellation: source.token,
      );
      expect(result.status, MailArchiveRunStatus.cancelled);
      expect(result.problem!.code, MailProblemCode.cancelled);
      expect(harness.factoryCalls, 0);
    });

    test(
      'caller cancellation interrupts stalled reads and cancels its polling timer',
      () async {
        final source = MailCancellationSource();
        final delayed = Completer<MailResult<MailHeaderPage>>();
        final harness = _Harness()
          ..headersAnswer = (_, _, _, _) => delayed.future;
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final timers = <Timer>[];
        final pending = runZoned(
          () => loader.archiveMailbox(
            _mailbox(),
            archive: archive,
            profile: _archiveProfile,
            cancellation: source.token,
          ),
          zoneSpecification: ZoneSpecification(
            createPeriodicTimer: (self, parent, zone, duration, callback) {
              final timer = parent.createPeriodicTimer(
                zone,
                duration,
                callback,
              );
              timers.add(timer);
              return timer;
            },
          ),
        );
        source.cancel();
        final result = await pending.timeout(const Duration(seconds: 2));
        expect(result.status, MailArchiveRunStatus.cancelled);
        expect(result.problem!.code, MailProblemCode.cancelled);
        expect(timers, hasLength(1));
        expect(timers.single.isActive, isFalse);
        expect(harness.headerRequests, hasLength(1));
        delayed.completeError(
          StateError('late secret after caller cancellation'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(_success(await archive.statistics()).messages, 0);
      },
    );

    test(
      'normal completion also disposes its external cancellation timer',
      () async {
        final source = MailCancellationSource();
        final harness = _Harness();
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final timers = <Timer>[];
        final result = await runZoned(
          () => loader.archiveMailbox(
            _mailbox(),
            archive: archive,
            profile: _archiveProfile,
            cancellation: source.token,
          ),
          zoneSpecification: ZoneSpecification(
            createPeriodicTimer: (self, parent, zone, duration, callback) {
              final timer = parent.createPeriodicTimer(
                zone,
                duration,
                callback,
              );
              timers.add(timer);
              return timer;
            },
          ),
        );
        expect(result.saved, 1);
        expect(timers, hasLength(1));
        expect(timers.single.isActive, isFalse);
      },
    );

    for (final dispose in [false, true]) {
      test(
        '${dispose ? 'dispose' : 'cancel'} before commit rolls back the complete original',
        () async {
          final harness = _Harness();
          final loader = _loader(harness);
          addTearDown(loader.dispose);
          fault = (checkpoint) async {
            if (checkpoint == MailArchiveCheckpoint.beforeCommit) {
              if (dispose) {
                loader.dispose();
              } else {
                loader.cancel();
              }
            }
          };
          final result = await loader.archiveMailbox(
            _mailbox(),
            archive: archive,
            profile: _archiveProfile,
          );
          expect(result.status, MailArchiveRunStatus.cancelled);
          expect(result.saved, 0);
          expect(result.failed, 0);
          expect(_success(await archive.statistics()).messages, 0);
          expect(
            _success(await archive.loadOriginal(MailBytes(harness.raw).sha256)),
            isNull,
          );
        },
      );
    }

    test(
      'cancellation after a commit keeps saved counts and prevents another download',
      () async {
        final harness = _Harness()
          ..headersAnswer = (mailbox, _, _, _) async => MailSuccess(
            MailHeaderPage(
              messages: [_record(mailbox), _record(mailbox, uid: 8)],
            ),
          );
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final result = await loader.archiveMailbox(
          _mailbox(),
          archive: archive,
          profile: _archiveProfile,
          onProgress: (progress) {
            if (progress.phase == MailArchiveRunPhase.message) loader.cancel();
          },
        );
        expect(result.status, MailArchiveRunStatus.cancelled);
        expect(result.saved, 1);
        expect(result.processed, 1);
        expect(result.failed, 0);
        expect(harness.requests, hasLength(1));
        expect(_success(await archive.statistics()).messages, 1);
        expect(
          _success(
            await archive.loadOriginal(MailBytes(harness.raw).sha256),
          )!.bytes,
          orderedEquals(harness.raw),
        );
      },
    );

    test(
      'throwing progress observers cannot fail an otherwise valid archive',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final result = await loader.archiveMailbox(
          _mailbox(),
          archive: archive,
          profile: _archiveProfile,
          onProgress: (_) {
            throw StateError('private observer error');
          },
        );
        expect(result.status, MailArchiveRunStatus.completed);
        expect(result.saved, 1);
        expect(result.observerErrors, greaterThanOrEqualTo(4));
        expect(harness.mutations, isEmpty);
      },
    );

    test(
      'reconnecting a session deduplicates exact bytes and stable provenance',
      () async {
        final first = _Harness();
        final second = _Harness();
        final loader1 = _loader(first);
        final loader2 = _loader(second);
        addTearDown(loader1.dispose);
        addTearDown(loader2.dispose);
        final saved = await loader1.archiveMailbox(
          _mailbox(),
          archive: archive,
          profile: _archiveProfile,
        );
        loader1.dispose();
        final rerun = await loader2.archiveMailbox(
          _mailbox(),
          archive: archive,
          profile: _archiveProfile,
        );
        expect(
          first.configuration!.account,
          isNot(second.configuration!.account),
        );
        expect(saved.saved, 1);
        expect(rerun.status, MailArchiveRunStatus.completed);
        expect(rerun.saved, 0);
        expect(rerun.duplicates, 1);
        final stats = _success(await archive.statistics());
        expect(stats.messages, 1);
        expect(stats.origins, 1);
        expect(first.mutations, isEmpty);
        expect(second.mutations, isEmpty);
      },
    );

    test(
      'requires explicit mailbox profile scope without reading source mail',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        for (final profile in [
          const MailArchiveProfile(
            id: 'files',
            name: 'Files',
            source: 'Fixture',
          ),
          const MailArchiveProfile(
            id: 'recursive',
            name: 'Recursive',
            source: 'Fixture',
            kind: MailArchiveProfileKind.mailbox,
          ),
        ]) {
          final result = await loader.archiveMailbox(
            _mailbox(),
            archive: archive,
            profile: profile,
          );
          expect(result.status, MailArchiveRunStatus.failed);
          expect(result.problem!.code, MailProblemCode.unsupported);
        }
        expect(harness.headerRequests, isEmpty);
        expect(harness.requests, isEmpty);
      },
    );
  });
}

Matcher _problem(MailProblemCode code) => isA<StudioMailMessageLoadException>()
    .having((error) => error.code, 'code', code);

Matcher _problemEvidence(MailProblemCode code, bool? evidence) =>
    isA<StudioMailMessageLoadException>()
        .having((error) => error.code, 'code', code)
        .having(
          (error) => error.mutationMayHaveOccurred,
          'mutationMayHaveOccurred',
          evidence,
        );

NativeStudioMailMessageLoader _loader(_Harness harness) =>
    NativeStudioMailMessageLoader(_account(), providerFactory: harness.create);

mail.MailAccount _account({
  mail.ServerType type = mail.ServerType.imap,
  mail.SocketType socketType = mail.SocketType.ssl,
  String host = 'imap.example.test',
  int port = 993,
  String username = 'incoming-user',
  String password = 'fixture-only-password',
  mail.MailAuthentication? authentication,
}) => mail.MailAccount.fromManualSettingsWithAuth(
  name: 'Fixture account',
  email: 'fixture@example.test',
  incomingHost: host,
  outgoingHost: 'smtp.example.test',
  auth: authentication ?? mail.PlainAuthentication(username, password),
  incomingType: type,
  incomingPort: port,
  incomingSocketType: socketType,
);

mail.Mailbox _mailbox({
  String path = 'INBOX',
  int? uidValidity = 41,
  List<mail.MailboxFlag> flags = const [],
}) => mail.Mailbox(
  encodedName: path,
  encodedPath: path,
  flags: [...flags],
  pathSeparator: '/',
  uidValidity: uidValidity,
);

mail.MimeMessage _header({int? uid = 7}) => mail.MimeMessage()..uid = uid;

typedef _Answer =
    Future<MailResult<MailMessage>> Function(
      MailRemoteIdentity identity,
      MailReadBudget budget,
      MailOperationLease lease,
    );

typedef _ApplyAnswer =
    Future<MailResult<MailUnit>> Function(
      MailOperation operation,
      MailOperationLease lease,
    );

typedef _HeadersAnswer =
    Future<MailResult<MailHeaderPage>> Function(
      MailMailboxId mailbox,
      MailCursor? cursor,
      int limit,
      MailOperationLease lease,
    );

typedef _ObserveAnswer =
    Future<MailResult<MailFlagObservation>> Function(
      MailRemoteIdentity identity,
      MailOperationLease lease,
    );

typedef _MembershipObserveAnswer =
    Future<MailResult<MailMembershipObservation>> Function(
      MailRemoteIdentity identity,
      MailOperationLease lease,
    );

typedef _CapabilitiesAnswer =
    Future<MailResult<MailCapabilities>> Function(MailOperationLease lease);

final class _HeadersRequest {
  _HeadersRequest(this.mailbox, this.cursor, this.limit, this.lease);
  final MailMailboxId mailbox;
  final MailCursor? cursor;
  final int limit;
  final MailOperationLease lease;
}

final class _Request {
  _Request(this.identity, this.budget, this.lease);
  final MailRemoteIdentity identity;
  final MailReadBudget budget;
  final MailOperationLease lease;
}

final class _Harness {
  final raw = Uint8List.fromList([
    ...ascii.encode(
      'From: sender@example.test\r\n'
      'Subject: Exact octets\r\n'
      'Content-Type: application/octet-stream\r\n'
      'Content-Transfer-Encoding: binary\r\n\r\n',
    ),
    0xe9,
    0xff,
    0x00,
    0x80,
    0x0d,
    0x0a,
  ]);
  int factoryCalls = 0;
  MailImapConfiguration? configuration;
  MailCredentialStore? credentials;
  MailTransportLimits? limits;
  MailMessage? lastMessage;
  final requests = <_Request>[];
  final headerRequests = <_HeadersRequest>[];
  final requestedValidities = <int>[];
  final flagObservations = <(MailRemoteIdentity, MailOperationLease)>[];
  final membershipObservations = <(MailRemoteIdentity, MailOperationLease)>[];
  final capabilityRequests = <MailOperationLease>[];
  final archiveRequests = <MailOperationLease>[];
  Future<MailResult<MailMailbox>> Function(MailOperationLease)? archiveAnswer;
  _Answer? answer;
  _ApplyAnswer? applyAnswer;
  _HeadersAnswer? headersAnswer;
  _ObserveAnswer? observeAnswer;
  _MembershipObserveAnswer? membershipObserveAnswer;
  _CapabilitiesAnswer? capabilitiesAnswer;
  void Function()? beforeCreate;
  Object? factoryError;
  MailAccountId? providerAccount;
  final mutations = <(MailOperation, MailOperationLease)>[];

  MailMessage message(MailRemoteIdentity? identity) =>
      lastMessage = MailMessage(
        raw: MailBytes(raw),
        envelope: MailEnvelope(subject: 'Exact octets'),
        remoteIdentity: identity,
      );

  MailProvider create({
    required MailImapConfiguration configuration,
    required MailCredentialStore credentialStore,
    required MailTransportLimits limits,
  }) {
    factoryCalls++;
    this.configuration = configuration;
    credentials = credentialStore;
    this.limits = limits;
    beforeCreate?.call();
    if (factoryError case final error?) throw error;
    return _Provider(
      providerAccount ?? configuration.account,
      (identity, budget, lease) {
        requests.add(_Request(identity, budget, lease));
        return answer?.call(identity, budget, lease) ??
            Future.value(MailSuccess(message(identity)));
      },
      (operation, lease) {
        mutations.add((operation, lease));
        return applyAnswer?.call(operation, lease) ??
            Future.value(const MailSuccess(MailUnit.value));
      },
      (mailbox, cursor, limit, lease) {
        headerRequests.add(_HeadersRequest(mailbox, cursor, limit, lease));
        return headersAnswer?.call(mailbox, cursor, limit, lease) ??
            Future.value(
              MailSuccess(MailHeaderPage(messages: [_record(mailbox)])),
            );
      },
      requestedValidities.add,
      (identity, lease) {
        flagObservations.add((identity, lease));
        return observeAnswer?.call(identity, lease) ??
            Future.value(
              MailSuccess(
                MailFlagObservation.present(
                  identity: identity,
                  flags: const MailMessageFlags(isRead: true),
                ),
              ),
            );
      },
      (identity, lease) {
        membershipObservations.add((identity, lease));
        return membershipObserveAnswer?.call(identity, lease) ??
            Future.value(
              MailSuccess(
                MailMembershipObservation.imap(
                  identity: identity as MailImapIdentity,
                  isDeleted: false,
                ),
              ),
            );
      },
      (lease) {
        capabilityRequests.add(lease);
        return capabilitiesAnswer?.call(lease) ??
            Future.value(const MailSuccess(MailCapabilities.none()));
      },
      (lease) {
        archiveRequests.add(lease);
        return archiveAnswer?.call(lease) ??
            Future.value(
              MailSuccess(
                MailMailbox(
                  id: MailMailboxId(
                    'server-archive',
                    account: configuration.account,
                  ),
                  displayName: 'Archiv',
                ),
              ),
            );
      },
    );
  }
}

final class _Provider
    implements
        MailProvider,
        MailImapHeaderBrowser,
        MailFlagObserver,
        MailArchiveDestinationResolver,
        MailMembershipObserver {
  _Provider(
    this.account,
    this.answer,
    this.applyAnswer,
    this.headersAnswer,
    this.observeValidity,
    this.observeAnswer,
    this.membershipObserveAnswer,
    this.capabilitiesAnswer,
    this.archiveAnswer,
  );

  @override
  final MailAccountId account;
  final _Answer answer;
  final _ApplyAnswer applyAnswer;
  final _HeadersAnswer headersAnswer;
  final void Function(int) observeValidity;
  final _ObserveAnswer observeAnswer;
  final _MembershipObserveAnswer membershipObserveAnswer;
  final _CapabilitiesAnswer capabilitiesAnswer;
  final Future<MailResult<MailMailbox>> Function(MailOperationLease)
  archiveAnswer;

  @override
  Future<MailResult<MailMailbox>> resolveArchiveDestination(
    MailOperationLease lease,
  ) => archiveAnswer(lease);

  @override
  Future<MailResult<MailCapabilities>> capabilities(MailOperationLease lease) =>
      capabilitiesAnswer(lease);

  @override
  Future<MailResult<MailMembershipObservation>> observeMembership(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) => membershipObserveAnswer(identity, lease);

  @override
  Future<MailResult<MailFlagObservation>> observeFlags(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) => observeAnswer(identity, lease);

  @override
  Future<MailResult<MailHeaderPage>> fetchNewestHeaders(
    MailMailboxId mailbox, {
    required int uidValidity,
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) {
    observeValidity(uidValidity);
    return headersAnswer(mailbox, cursor, limit, lease);
  }

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) => headersAnswer(mailbox, cursor, limit, lease);

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) => applyAnswer(operation, lease);

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) => answer(identity, budget, lease);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected provider operation in bounded message adapter.',
  );
}

final class _ReaderOnlyProvider implements MailProvider {
  _ReaderOnlyProvider(this.account);

  @override
  final MailAccountId account;

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw StateError('Browsing must negotiate the optional provider port.');
}

void _archiveDestinationTests() {
  for (final cancelLoader in [true, false]) {
    test(
      'Archive destination bridge rechecks ${cancelLoader ? 'loader' : 'host'} lease after provider creation',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final host = MailAccountSession(loader.account);
        addTearDown(host.dispose);
        harness.beforeCreate = cancelLoader ? loader.cancel : host.invalidate;
        final result = await loader.resolveArchiveDestination(host.begin());
        expect(result, isA<MailFailure<MailMailbox>>());
        expect(harness.factoryCalls, 1);
        expect(harness.archiveRequests, isEmpty);
        expect(harness.mutations, isEmpty);
      },
    );
  }

  test(
    'Archive destination bridge resolves an exact same-account folder without mail reads or writes',
    () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      final host = MailAccountSession(loader.account);
      addTearDown(host.dispose);
      final result = _success(
        await loader.resolveArchiveDestination(host.begin()),
      );
      expect(
        result.id,
        MailMailboxId('server-archive', account: loader.account),
      );
      expect(result.displayName, 'Archiv');
      expect(harness.archiveRequests, hasLength(1));
      expect(harness.requests, isEmpty);
      expect(harness.headerRequests, isEmpty);
      expect(harness.mutations, isEmpty);
    },
  );

  test(
    'Archive destination bridge keeps unsupported distinct from network failure',
    () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      final host = MailAccountSession(loader.account);
      addTearDown(host.dispose);
      for (final code in [
        MailProblemCode.unsupported,
        MailProblemCode.unavailable,
        MailProblemCode.permissionDenied,
      ]) {
        harness.archiveAnswer = (_) async => MailFailure(MailProblem(code));
        final result = await loader.resolveArchiveDestination(host.begin());
        expect(result, isA<MailFailure<MailMailbox>>());
        expect((result as MailFailure<MailMailbox>).problem.code, code);
      }
      expect(harness.mutations, isEmpty);
    },
  );

  test('Archive destination bridge rejects a foreign account result', () async {
    final harness = _Harness();
    final loader = _loader(harness);
    addTearDown(loader.dispose);
    final host = MailAccountSession(loader.account);
    addTearDown(host.dispose);
    harness.archiveAnswer = (_) async => MailSuccess(
      MailMailbox(
        id: MailMailboxId(
          'archive',
          account: MailAccountId('foreign', profile: loader.account.profile),
        ),
        displayName: 'Archive',
      ),
    );
    final result = await loader.resolveArchiveDestination(host.begin());
    expect(
      (result as MailFailure<MailMailbox>).problem.code,
      MailProblemCode.invalidInput,
    );
    expect(harness.mutations, isEmpty);
  });

  test(
    'Archive destination bridge rejects stale or foreign host lease before provider construction',
    () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      final host = MailAccountSession(loader.account);
      final stale = host.begin();
      host.dispose();
      final foreign = MailAccountSession(
        MailAccountId('foreign', profile: loader.account.profile),
      );
      addTearDown(foreign.dispose);
      expect(
        (await loader.resolveArchiveDestination(stale)
                as MailFailure<MailMailbox>)
            .problem
            .code,
        MailProblemCode.staleOperation,
      );
      expect(
        (await loader.resolveArchiveDestination(foreign.begin())
                as MailFailure<MailMailbox>)
            .problem
            .code,
        MailProblemCode.invalidInput,
      );
      expect(harness.factoryCalls, 0);
    },
  );

  test(
    'Archive destination bridge cancels a pending result on disposal',
    () async {
      final gate = Completer<MailResult<MailMailbox>>();
      final harness = _Harness()..archiveAnswer = (_) => gate.future;
      final loader = _loader(harness);
      final host = MailAccountSession(loader.account);
      addTearDown(host.dispose);
      final pending = loader.resolveArchiveDestination(host.begin());
      loader.dispose();
      expect(
        (await pending as MailFailure<MailMailbox>).problem.code,
        MailProblemCode.staleOperation,
      );
      gate.completeError(StateError('Late provider response'));
      await Future<void>.delayed(Duration.zero);
      expect(harness.archiveRequests, hasLength(1));
      expect(harness.mutations, isEmpty);
    },
  );
}

void _flagObservationTests() {
  group('native historical flag observation adapter', () {
    MailImapIdentity historical(NativeStudioMailMessageLoader loader) =>
        MailImapIdentity(
          mailbox: MailMailboxId('Archive/2025', account: loader.account),
          uidValidity: 191,
          uid: 0xffffffff,
        );

    Matcher failure(MailProblemCode code) =>
        isA<MailFailure<MailFlagObservation>>().having(
          (result) => result.problem.code,
          'problem code',
          code,
        );

    void noMailActions(_Harness harness) {
      expect(harness.requests, isEmpty);
      expect(harness.headerRequests, isEmpty);
      expect(harness.mutations, isEmpty);
    }

    test(
      'reads the exact historical UID without loading a folder or body',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        final session = MailAccountSession(loader.account);
        final cancellation = MailCancellationSource();
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        final identity = historical(loader);
        final expected = MailFlagObservation.present(
          identity: identity,
          flags: const MailMessageFlags(isRead: true, isFlagged: true),
        );
        harness.observeAnswer = (_, _) async => MailSuccess(expected);
        final result = await loader.observeFlags(
          identity,
          lease: session.begin(cancellation: cancellation.token),
        );
        expect(result, isA<MailSuccess<MailFlagObservation>>());
        expect(
          (result as MailSuccess<MailFlagObservation>).value,
          same(expected),
        );
        expect(harness.factoryCalls, 1);
        expect(harness.flagObservations, hasLength(1));
        expect(harness.flagObservations.single.$1, same(identity));
        expect(harness.flagObservations.single.$2.account, loader.account);
        expect(harness.flagObservations.single.$2.isCurrent, isTrue);
        expect(
          harness.flagObservations.single.$2.cancellation,
          same(cancellation.token),
        );
        noMailActions(harness);
      },
    );

    for (final kind in [
      MailFlagObservationKind.missing,
      MailFlagObservationKind.identityChanged,
    ]) {
      test(
        'preserves provider ${kind.name} evidence for the original identity',
        () async {
          final harness = _Harness();
          final loader = _loader(harness);
          final session = MailAccountSession(loader.account);
          addTearDown(loader.dispose);
          addTearDown(session.dispose);
          final identity = historical(loader);
          final expected = kind == MailFlagObservationKind.missing
              ? MailFlagObservation.missing(identity: identity)
              : MailFlagObservation.identityChanged(identity: identity);
          harness.observeAnswer = (_, _) async => MailSuccess(expected);
          final result = await loader.observeFlags(
            identity,
            lease: session.begin(),
          );
          expect(
            (result as MailSuccess<MailFlagObservation>).value,
            same(expected),
          );
          expect(expected.identity, same(identity));
          expect(expected.flags, isNull);
          noMailActions(harness);
        },
      );
    }

    test(
      'preserves typed failures and sanitizes thrown provider errors',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        final session = MailAccountSession(loader.account);
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        const problem = MailProblem(MailProblemCode.authenticationRequired);
        harness.observeAnswer = (_, _) async => const MailFailure(problem);
        final result = await loader.observeFlags(
          historical(loader),
          lease: session.begin(),
        );
        expect(
          (result as MailFailure<MailFlagObservation>).problem,
          same(problem),
        );
        harness.observeAnswer = (_, _) async =>
            throw StateError('private fixture');
        expect(
          await loader.observeFlags(historical(loader), lease: session.begin()),
          failure(MailProblemCode.providerFailure),
        );
        expect(harness.flagObservations, hasLength(2));
        noMailActions(harness);
      },
    );

    test(
      'requires the optional observation port without falling back to a body read',
      () async {
        var factories = 0;
        final loader = NativeStudioMailMessageLoader(
          _account(),
          providerFactory:
              ({
                required configuration,
                required credentialStore,
                required limits,
              }) {
                factories++;
                return _ReaderOnlyProvider(configuration.account);
              },
        );
        final session = MailAccountSession(loader.account);
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        expect(
          await loader.observeFlags(historical(loader), lease: session.begin()),
          failure(MailProblemCode.unsupported),
        );
        expect(factories, 1);
      },
    );

    test(
      'rejects wrong identity and lease scopes before constructing a provider',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        final session = MailAccountSession(loader.account);
        final other = MailAccountId(
          'another-account',
          profile: loader.account.profile,
        );
        final otherSession = MailAccountSession(other);
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        addTearDown(otherSession.dispose);
        for (final identity in [
          MailOpaqueIdentity(
            account: loader.account,
            provider: MailProviderKind.ews,
            value: 'historical-item',
          ),
          MailImapIdentity(
            mailbox: MailMailboxId('Archive/2025', account: other),
            uidValidity: 191,
            uid: 501,
          ),
        ]) {
          expect(
            await loader.observeFlags(identity, lease: session.begin()),
            failure(MailProblemCode.invalidInput),
          );
        }
        expect(
          await loader.observeFlags(
            historical(loader),
            lease: otherSession.begin(),
          ),
          failure(MailProblemCode.invalidInput),
        );
        expect(harness.factoryCalls, 0);
        expect(harness.flagObservations, isEmpty);
        noMailActions(harness);
      },
    );

    test(
      'refuses stale or cancelled host leases before provider construction',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        final session = MailAccountSession(loader.account);
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        final stale = session.begin();
        session.invalidate();
        expect(
          await loader.observeFlags(historical(loader), lease: stale),
          failure(MailProblemCode.staleOperation),
        );
        final cancellation = MailCancellationSource();
        final cancelled = session.begin(cancellation: cancellation.token);
        cancellation.cancel();
        expect(
          await loader.observeFlags(historical(loader), lease: cancelled),
          failure(MailProblemCode.cancelled),
        );
        expect(harness.factoryCalls, 0);
        expect(harness.flagObservations, isEmpty);
        noMailActions(harness);
      },
    );

    for (final retireLoader in [false, true]) {
      test(
        '${retireLoader ? 'loader' : 'host'} retirement during provider construction prevents dispatch',
        () async {
          final harness = _Harness();
          final loader = _loader(harness);
          final session = MailAccountSession(loader.account);
          addTearDown(loader.dispose);
          addTearDown(session.dispose);
          harness.beforeCreate = retireLoader
              ? loader.dispose
              : session.invalidate;
          expect(
            await loader.observeFlags(
              historical(loader),
              lease: session.begin(),
            ),
            failure(MailProblemCode.staleOperation),
          );
          expect(harness.factoryCalls, 1);
          expect(harness.flagObservations, isEmpty);
          noMailActions(harness);
        },
      );
    }

    test('refuses a provider for another account before observation', () async {
      final harness = _Harness()
        ..providerAccount = MailAccountId(
          'wrong-provider',
          profile: MailProfileId('another-profile', hostId: 'test'),
        );
      final loader = _loader(harness);
      final session = MailAccountSession(loader.account);
      addTearDown(loader.dispose);
      addTearDown(session.dispose);
      expect(
        await loader.observeFlags(historical(loader), lease: session.begin()),
        failure(MailProblemCode.invalidInput),
      );
      expect(harness.flagObservations, isEmpty);
      noMailActions(harness);
    });

    test('does not overlap a pending observation with another check', () async {
      final response = Completer<MailResult<MailFlagObservation>>();
      final harness = _Harness()..observeAnswer = (_, _) => response.future;
      final loader = _loader(harness);
      final session = MailAccountSession(loader.account);
      addTearDown(loader.dispose);
      addTearDown(session.dispose);
      final identity = historical(loader);
      final pending = loader.observeFlags(identity, lease: session.begin());
      expect(
        await loader.observeFlags(identity, lease: session.begin()),
        failure(MailProblemCode.unavailable),
      );
      expect(harness.flagObservations, hasLength(1));
      expect(harness.factoryCalls, 1);
      response.complete(
        MailSuccess(MailFlagObservation.missing(identity: identity)),
      );
      expect(await pending, isA<MailSuccess<MailFlagObservation>>());
      noMailActions(harness);
    });

    for (final dispose in [false, true]) {
      test(
        '${dispose ? 'dispose' : 'cancel'} promptly finishes a non-cooperative observer and rejects its late result',
        () async {
          final response = Completer<MailResult<MailFlagObservation>>();
          final harness = _Harness()..observeAnswer = (_, _) => response.future;
          final loader = _loader(harness);
          final session = MailAccountSession(loader.account);
          addTearDown(loader.dispose);
          addTearDown(session.dispose);
          final identity = historical(loader);
          final pending = loader.observeFlags(identity, lease: session.begin());
          expect(harness.flagObservations, hasLength(1));
          dispose ? loader.dispose() : loader.cancel();
          expect(
            await pending.timeout(const Duration(seconds: 1)),
            failure(MailProblemCode.staleOperation),
          );
          expect(harness.flagObservations.single.$2.isCurrent, isFalse);
          response.complete(
            MailSuccess(MailFlagObservation.missing(identity: identity)),
          );
          await Future<void>.delayed(Duration.zero);
          if (dispose) {
            expect(
              await loader.observeFlags(identity, lease: session.begin()),
              failure(MailProblemCode.staleOperation),
            );
            expect(harness.factoryCalls, 1);
            expect(harness.flagObservations, hasLength(1));
          } else {
            harness.observeAnswer = null;
            expect(
              await loader.observeFlags(identity, lease: session.begin()),
              isA<MailSuccess<MailFlagObservation>>(),
            );
            expect(harness.flagObservations, hasLength(2));
          }
          noMailActions(harness);
        },
      );
    }

    for (final cancelToken in [false, true]) {
      test(
        'rejects a completed observation after ${cancelToken ? 'host token cancellation' : 'host generation changed'}',
        () async {
          final response = Completer<MailResult<MailFlagObservation>>();
          final harness = _Harness()..observeAnswer = (_, _) => response.future;
          final loader = _loader(harness);
          final session = MailAccountSession(loader.account);
          final cancellation = MailCancellationSource();
          addTearDown(loader.dispose);
          addTearDown(session.dispose);
          final identity = historical(loader);
          final pending = loader.observeFlags(
            identity,
            lease: session.begin(cancellation: cancellation.token),
          );
          cancelToken ? cancellation.cancel() : session.invalidate();
          response.complete(
            MailSuccess(MailFlagObservation.missing(identity: identity)),
          );
          expect(
            await pending,
            failure(
              cancelToken
                  ? MailProblemCode.cancelled
                  : MailProblemCode.staleOperation,
            ),
          );
          expect(harness.flagObservations, hasLength(1));
          noMailActions(harness);
        },
      );
    }

    test('observes a late provider exception after disposal', () async {
      final response = Completer<MailResult<MailFlagObservation>>();
      final harness = _Harness()..observeAnswer = (_, _) => response.future;
      final loader = _loader(harness);
      final session = MailAccountSession(loader.account);
      addTearDown(session.dispose);
      final pending = loader.observeFlags(
        historical(loader),
        lease: session.begin(),
      );
      loader.dispose();
      expect(await pending, failure(MailProblemCode.staleOperation));
      response.completeError(StateError('private late provider error'));
      await Future<void>.delayed(Duration.zero);
      expect(harness.flagObservations, hasLength(1));
      noMailActions(harness);
    });
  });
}

void _membershipAdapterTests() {
  group('native foreground membership adapter', () {
    MailOperation command(
      NativeStudioMailMessageLoader loader,
      MailBulkFlagAction action,
    ) {
      final identity = MailImapIdentity(
        mailbox: MailMailboxId('INBOX', account: loader.account),
        uidValidity: 83,
        uid: 0xffffffff,
      );
      return action == MailBulkFlagAction.move
          ? MailMove(
              id: 'persisted-move:0',
              message: identity,
              destination: MailMailboxId(
                'Archive/2026',
                account: loader.account,
              ),
            )
          : MailDelete(id: 'persisted-delete:0', message: identity);
    }

    void noReads(_Harness harness) {
      expect(harness.requests, isEmpty);
      expect(harness.headerRequests, isEmpty);
      expect(harness.flagObservations, isEmpty);
    }

    test(
      'capability discovery is read only and retains unsupported actions',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        final supported = MailCapabilities([MailCapability.delete]);
        harness.capabilitiesAnswer = (_) async => MailSuccess(supported);
        final capabilities = await loader.membershipCapabilities();
        expect(capabilities, same(supported));
        expect(capabilities.supports(MailCapability.move), isFalse);
        expect(capabilities.supports(MailCapability.delete), isTrue);
        expect(harness.capabilityRequests.single.account, loader.account);
        expect(harness.capabilityRequests.single.isCurrent, isTrue);
        expect(harness.mutations, isEmpty);
        noReads(harness);
      },
    );

    test(
      'capability errors stay typed and do not attempt a mutation',
      () async {
        final harness = _Harness()
          ..capabilitiesAnswer = (_) async => const MailFailure(
            MailProblem(
              MailProblemCode.unsupported,
              mutationMayHaveOccurred: false,
            ),
          );
        final loader = _loader(harness);
        addTearDown(loader.dispose);
        await expectLater(
          loader.membershipCapabilities(),
          throwsA(_problemEvidence(MailProblemCode.unsupported, false)),
        );
        expect(harness.mutations, isEmpty);
        noReads(harness);
      },
    );

    test(
      'disposed capability discovery refuses work before provider construction',
      () async {
        final harness = _Harness();
        final loader = _loader(harness)..dispose();
        await expectLater(
          loader.membershipCapabilities(),
          throwsA(_problemEvidence(MailProblemCode.staleOperation, false)),
        );
        expect(harness.factoryCalls, 0);
        expect(harness.capabilityRequests, isEmpty);
        expect(harness.mutations, isEmpty);
      },
    );

    test(
      'capability discovery cannot cancel or overlap an applying command',
      () async {
        final response = Completer<MailResult<MailUnit>>();
        final harness = _Harness()..applyAnswer = (_, _) => response.future;
        final loader = _loader(harness);
        final session = MailAccountSession(loader.account);
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        final pending = loader.applyMembership(
          command(loader, MailBulkFlagAction.delete),
          session.begin(),
        );
        await expectLater(
          loader.membershipCapabilities(),
          throwsA(_problemEvidence(MailProblemCode.unavailable, false)),
        );
        expect(harness.mutations.single.$2.isCurrent, isTrue);
        expect(harness.capabilityRequests, isEmpty);
        response.complete(const MailSuccess(MailUnit.value));
        expect(await pending, isA<MailSuccess<MailUnit>>());
        expect(harness.factoryCalls, 1);
      },
    );

    for (final action in [MailBulkFlagAction.move, MailBulkFlagAction.delete]) {
      test(
        '${action.name} retains the exact persisted operation and identity',
        () async {
          final harness = _Harness();
          final loader = _loader(harness);
          final session = MailAccountSession(loader.account);
          addTearDown(loader.dispose);
          addTearDown(session.dispose);
          final requested = command(loader, action);
          expect(
            await loader.applyMembership(requested, session.begin()),
            isA<MailSuccess<MailUnit>>(),
          );
          expect(harness.mutations.single.$1, same(requested));
          final identity =
              harness.mutations.single.$1.message as MailImapIdentity;
          expect(identity.uidValidity, 83);
          expect(identity.uid, 0xffffffff);
          expect(identity.mailbox.value, 'INBOX');
          expect(harness.capabilityRequests, isEmpty);
          noReads(harness);
        },
      );

      test('${action.name} cannot use the flag-only dispatch seam', () async {
        final harness = _Harness();
        final loader = _loader(harness);
        final session = MailAccountSession(loader.account);
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        final result = await loader.applyBulkFlag(
          command(loader, action),
          session.begin(),
        );
        expect(result, isA<MailFailure<MailUnit>>());
        final problem = (result as MailFailure<MailUnit>).problem;
        expect(problem.code, MailProblemCode.invalidInput);
        expect(problem.mutationMayHaveOccurred, isFalse);
        expect(harness.factoryCalls, 0);
        expect(harness.mutations, isEmpty);
      });

      for (final evidence in <bool?>[false, true, null]) {
        test(
          '${action.name} preserves provider mutation evidence $evidence',
          () async {
            final problem = MailProblem(
              evidence == false
                  ? MailProblemCode.unsupported
                  : MailProblemCode.conflict,
              mutationMayHaveOccurred: evidence,
              retryAfter: const Duration(seconds: 19),
            );
            final harness = _Harness()
              ..applyAnswer = (_, _) async => MailFailure(problem);
            final loader = _loader(harness);
            final session = MailAccountSession(loader.account);
            addTearDown(loader.dispose);
            addTearDown(session.dispose);
            final result = await loader.applyMembership(
              command(loader, action),
              session.begin(),
            );
            expect(result, isA<MailFailure<MailUnit>>());
            expect((result as MailFailure<MailUnit>).problem, same(problem));
            expect(harness.mutations, hasLength(1));
            noReads(harness);
          },
        );
      }

      for (final confirmed in [true, false]) {
        test(
          '${action.name} retains late ${confirmed ? 'confirmation' : 'uncertainty'} after disposal',
          () async {
            final response = Completer<MailResult<MailUnit>>();
            final harness = _Harness()..applyAnswer = (_, _) => response.future;
            final loader = _loader(harness);
            final session = MailAccountSession(loader.account);
            addTearDown(session.dispose);
            final requested = command(loader, action);
            final pending = loader.applyMembership(requested, session.begin());
            loader.dispose();
            expect(harness.mutations.single.$2.isCurrent, isFalse);
            final expected = confirmed
                ? const MailSuccess<MailUnit>(MailUnit.value)
                : const MailFailure<MailUnit>(
                    MailProblem(
                      MailProblemCode.conflict,
                      mutationMayHaveOccurred: true,
                    ),
                  );
            response.complete(expected);
            expect(await pending, same(expected));
            final later =
                await loader.applyMembership(requested, session.begin())
                    as MailFailure<MailUnit>;
            expect(later.problem.code, MailProblemCode.staleOperation);
            expect(later.problem.mutationMayHaveOccurred, isFalse);
            expect(harness.mutations, hasLength(1));
          },
        );
      }
    }

    test(
      'rejects flags, foreign scope, wrong provider and same-folder moves',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        final session = MailAccountSession(loader.account);
        final foreign = MailAccountSession(
          MailAccountId('foreign', profile: loader.account.profile),
        );
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        addTearDown(foreign.dispose);
        final identity = command(loader, MailBulkFlagAction.delete).message;
        final invalid = <(MailOperation, MailOperationLease)>[
          (
            MailSetRead(id: 'read', message: identity, read: true),
            session.begin(),
          ),
          (
            MailSetFlagged(id: 'flag', message: identity, flagged: true),
            session.begin(),
          ),
          (MailDelete(id: 'foreign-lease', message: identity), foreign.begin()),
          (
            MailDelete(
              id: 'foreign-message',
              message: MailImapIdentity(
                mailbox: MailMailboxId('INBOX', account: foreign.account),
                uidValidity: 83,
                uid: 7,
              ),
            ),
            session.begin(),
          ),
          (
            MailDelete(
              id: 'foreign-provider',
              message: MailOpaqueIdentity(
                account: loader.account,
                provider: MailProviderKind.graph,
                value: 'remote',
              ),
            ),
            session.begin(),
          ),
          (
            MailMove(
              id: 'same-folder',
              message: identity,
              destination: (identity as MailImapIdentity).mailbox,
            ),
            session.begin(),
          ),
        ];
        for (final (requested, lease) in invalid) {
          final result =
              await loader.applyMembership(requested, lease)
                  as MailFailure<MailUnit>;
          expect(result.problem.code, MailProblemCode.invalidInput);
          expect(result.problem.mutationMayHaveOccurred, isFalse);
        }
        expect(harness.factoryCalls, 0);
        expect(harness.mutations, isEmpty);
      },
    );

    test(
      'retired host generation prevents dispatch and provider exceptions stay uncertain',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        final session = MailAccountSession(loader.account);
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        final requested = command(loader, MailBulkFlagAction.delete);
        final stale = session.begin();
        session.invalidate();
        final refused =
            await loader.applyMembership(requested, stale)
                as MailFailure<MailUnit>;
        expect(refused.problem.code, MailProblemCode.staleOperation);
        expect(refused.problem.mutationMayHaveOccurred, isFalse);
        expect(harness.factoryCalls, 0);
        harness.applyAnswer = (_, _) =>
            throw StateError('private provider failure');
        final failed =
            await loader.applyMembership(requested, session.begin())
                as MailFailure<MailUnit>;
        expect(failed.problem.code, MailProblemCode.providerFailure);
        expect(failed.problem.mutationMayHaveOccurred, isTrue);
        expect(harness.mutations, hasLength(1));
      },
    );
  });
}

void _bulkAdapterTests() {
  group('native foreground bulk adapter', () {
    test('requires observed immutable mailbox identities', () async {
      final harness = _Harness();
      final loader = _loader(harness);
      addTearDown(loader.dispose);
      final mailbox = _mailbox();
      expect(
        () => loader.bulkIdentity(mailbox, _header()),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      final page = await loader.fetchHeaders(mailbox);
      final header = page.messages.single;
      final identity = loader.bulkIdentity(mailbox, header);
      expect(identity.uid, 7);
      expect(identity.uidValidity, 41);
      expect(identity.mailbox.account, loader.account);
      header.uid = 8;
      expect(
        () => loader.bulkIdentity(mailbox, header),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      header.uid = 7;
      mailbox.uidValidity = 42;
      expect(
        () => loader.bulkIdentity(mailbox, header),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      expect(harness.mutations, isEmpty);
      expect(harness.requests, isEmpty);
    });

    test('preserves definite uncertain and legacy provider evidence', () async {
      final harness = _Harness();
      final loader = _loader(harness);
      final session = MailAccountSession(loader.account);
      addTearDown(loader.dispose);
      addTearDown(session.dispose);
      final identity = MailImapIdentity(
        mailbox: MailMailboxId('INBOX', account: loader.account),
        uidValidity: 41,
        uid: 7,
      );
      for (final evidence in <bool?>[false, true, null]) {
        final problem = MailProblem(
          MailProblemCode.conflict,
          mutationMayHaveOccurred: evidence,
        );
        harness.applyAnswer = (_, _) async => MailFailure(problem);
        final result = await loader.applyBulkFlag(
          MailSetRead(id: 'bulk', message: identity, read: true),
          session.begin(),
        );
        expect(result, isA<MailFailure<MailUnit>>());
        expect((result as MailFailure<MailUnit>).problem, same(problem));
      }
      expect(harness.mutations, hasLength(3));
      expect(harness.requests, isEmpty);
      expect(harness.headerRequests, isEmpty);
    });

    test(
      'distinguishes factory refusal from an exception after dispatch',
      () async {
        final harness = _Harness()
          ..factoryError = StateError('private fixture');
        final loader = _loader(harness);
        final session = MailAccountSession(loader.account);
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        final command = MailSetFlagged(
          id: 'bulk',
          flagged: true,
          message: MailImapIdentity(
            mailbox: MailMailboxId('INBOX', account: loader.account),
            uidValidity: 41,
            uid: 7,
          ),
        );
        var result =
            await loader.applyBulkFlag(command, session.begin())
                as MailFailure<MailUnit>;
        expect(result.problem.mutationMayHaveOccurred, isFalse);
        expect(harness.mutations, isEmpty);
        harness.factoryError = null;
        harness.applyAnswer = (_, _) => throw StateError('private fixture');
        result =
            await loader.applyBulkFlag(command, session.begin())
                as MailFailure<MailUnit>;
        expect(result.problem.mutationMayHaveOccurred, isTrue);
        expect(result.problem.code, MailProblemCode.providerFailure);
        expect(harness.mutations, hasLength(1));
      },
    );

    test(
      'rejects wrong account and nonflag commands before provider work',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        final session = MailAccountSession(loader.account);
        final foreign = MailAccountSession(
          MailAccountId('other', profile: loader.account.profile),
        );
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        addTearDown(foreign.dispose);
        final identity = MailImapIdentity(
          mailbox: MailMailboxId('INBOX', account: loader.account),
          uidValidity: 41,
          uid: 7,
        );
        final delete =
            await loader.applyBulkFlag(
                  MailDelete(id: 'delete', message: identity),
                  session.begin(),
                )
                as MailFailure<MailUnit>;
        final mismatch =
            await loader.applyBulkFlag(
                  MailSetRead(id: 'read', message: identity, read: true),
                  foreign.begin(),
                )
                as MailFailure<MailUnit>;
        expect(delete.problem.code, MailProblemCode.invalidInput);
        expect(delete.problem.mutationMayHaveOccurred, isFalse);
        expect(mismatch.problem.code, MailProblemCode.invalidInput);
        expect(mismatch.problem.mutationMayHaveOccurred, isFalse);
        expect(harness.factoryCalls, 0);
      },
    );

    test('keeps late confirmation and rejects overlapping dispatch', () async {
      final gate = Completer<MailResult<MailUnit>>();
      final harness = _Harness()..applyAnswer = (_, _) => gate.future;
      final loader = _loader(harness);
      final session = MailAccountSession(loader.account);
      addTearDown(loader.dispose);
      addTearDown(session.dispose);
      final command = MailSetRead(
        id: 'read',
        read: true,
        message: MailImapIdentity(
          mailbox: MailMailboxId('INBOX', account: loader.account),
          uidValidity: 41,
          uid: 7,
        ),
      );
      final first = loader.applyBulkFlag(command, session.begin());
      final overlap =
          await loader.applyBulkFlag(command, session.begin())
              as MailFailure<MailUnit>;
      expect(overlap.problem.code, MailProblemCode.unavailable);
      expect(overlap.problem.mutationMayHaveOccurred, isFalse);
      session.invalidate();
      gate.complete(const MailSuccess(MailUnit.value));
      expect(await first, isA<MailSuccess<MailUnit>>());
      expect(harness.mutations, hasLength(1));
    });

    test('dispose invalidates provider lease and refuses later work', () async {
      final gate = Completer<MailResult<MailUnit>>();
      final harness = _Harness()..applyAnswer = (_, _) => gate.future;
      final loader = _loader(harness);
      final session = MailAccountSession(loader.account);
      addTearDown(session.dispose);
      final command = MailSetRead(
        id: 'read',
        read: true,
        message: MailImapIdentity(
          mailbox: MailMailboxId('INBOX', account: loader.account),
          uidValidity: 41,
          uid: 7,
        ),
      );
      final first = loader.applyBulkFlag(command, session.begin());
      loader.dispose();
      expect(harness.mutations.single.$2.isCurrent, isFalse);
      gate.complete(
        const MailFailure(
          MailProblem(MailProblemCode.conflict, mutationMayHaveOccurred: true),
        ),
      );
      expect(
        (await first as MailFailure<MailUnit>).problem.mutationMayHaveOccurred,
        isTrue,
      );
      final later =
          await loader.applyBulkFlag(command, session.begin())
              as MailFailure<MailUnit>;
      expect(later.problem.code, MailProblemCode.staleOperation);
      expect(later.problem.mutationMayHaveOccurred, isFalse);
      expect(harness.mutations, hasLength(1));
    });
  });
}

void _membershipObservationTests() {
  group('native historical membership observation adapter', () {
    MailImapIdentity historical(NativeStudioMailMessageLoader loader) =>
        MailImapIdentity(
          mailbox: MailMailboxId('Archive/2025', account: loader.account),
          uidValidity: 191,
          uid: 0xffffffff,
        );
    Matcher failure(MailProblemCode code) =>
        isA<MailFailure<MailMembershipObservation>>().having(
          (result) => result.problem.code,
          'problem code',
          code,
        );
    void noMailActions(_Harness harness) {
      expect(harness.requests, isEmpty);
      expect(harness.headerRequests, isEmpty);
      expect(harness.flagObservations, isEmpty);
      expect(harness.mutations, isEmpty);
    }

    for (final kind in MailMembershipObservationKind.values) {
      test(
        'forwards exact ${kind.name} evidence without a browse, body, flag read or command',
        () async {
          final harness = _Harness();
          final loader = _loader(harness);
          final session = MailAccountSession(loader.account);
          final cancellation = MailCancellationSource();
          addTearDown(loader.dispose);
          addTearDown(session.dispose);
          final identity = historical(loader);
          final observed = switch (kind) {
            MailMembershipObservationKind.present =>
              MailMembershipObservation.imap(
                identity: identity,
                isDeleted: true,
              ),
            MailMembershipObservationKind.missing =>
              MailMembershipObservation.missing(identity: identity),
            MailMembershipObservationKind.identityChanged =>
              MailMembershipObservation.identityChanged(identity: identity),
          };
          harness.membershipObserveAnswer = (_, _) async =>
              MailSuccess(observed);
          final result = await loader.observeMembership(
            identity,
            lease: session.begin(cancellation: cancellation.token),
          );
          expect(result, isA<MailSuccess<MailMembershipObservation>>());
          expect(
            (result as MailSuccess<MailMembershipObservation>).value,
            same(observed),
          );
          expect(harness.membershipObservations.single.$1, same(identity));
          expect(
            harness.membershipObservations.single.$2.cancellation,
            same(cancellation.token),
          );
          expect(
            harness.membershipObservations.single.$2.account,
            loader.account,
          );
          noMailActions(harness);
        },
      );
    }

    test(
      'a provider without membership observation remains unsupported',
      () async {
        final loader = NativeStudioMailMessageLoader(
          _account(),
          providerFactory:
              ({
                required configuration,
                required credentialStore,
                required limits,
              }) => _ReaderOnlyProvider(configuration.account),
        );
        final session = MailAccountSession(loader.account);
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        expect(
          await loader.observeMembership(
            historical(loader),
            lease: session.begin(),
          ),
          failure(MailProblemCode.unsupported),
        );
      },
    );

    test(
      'foreign identity and foreign provider are rejected without observation',
      () async {
        final harness = _Harness();
        final loader = _loader(harness);
        final session = MailAccountSession(loader.account);
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        final foreign = MailAccountId(
          'foreign',
          profile: loader.account.profile,
        );
        final identity = MailImapIdentity(
          mailbox: MailMailboxId('INBOX', account: foreign),
          uidValidity: 191,
          uid: 1,
        );
        expect(
          await loader.observeMembership(identity, lease: session.begin()),
          failure(MailProblemCode.invalidInput),
        );
        expect(harness.factoryCalls, 0);
        harness.providerAccount = foreign;
        expect(
          await loader.observeMembership(
            historical(loader),
            lease: session.begin(),
          ),
          failure(MailProblemCode.invalidInput),
        );
        expect(harness.membershipObservations, isEmpty);
        noMailActions(harness);
      },
    );

    test(
      'overlapping observation is refused and cancellation prevents late publication',
      () async {
        final response = Completer<MailResult<MailMembershipObservation>>();
        final harness = _Harness()
          ..membershipObserveAnswer = (_, _) => response.future;
        final loader = _loader(harness);
        final session = MailAccountSession(loader.account);
        addTearDown(loader.dispose);
        addTearDown(session.dispose);
        final identity = historical(loader);
        final pending = loader.observeMembership(
          identity,
          lease: session.begin(),
        );
        expect(
          await loader.observeMembership(identity, lease: session.begin()),
          failure(MailProblemCode.unavailable),
        );
        loader.cancel();
        expect(await pending, failure(MailProblemCode.staleOperation));
        response.complete(
          MailSuccess(MailMembershipObservation.missing(identity: identity)),
        );
        await Future<void>.delayed(Duration.zero);
        expect(harness.membershipObservations, hasLength(1));
        noMailActions(harness);
      },
    );

    test('a cancelled lease cannot create a provider', () async {
      final harness = _Harness();
      final loader = _loader(harness);
      final session = MailAccountSession(loader.account);
      final cancellation = MailCancellationSource();
      final lease = session.begin(cancellation: cancellation.token);
      cancellation.cancel();
      addTearDown(loader.dispose);
      addTearDown(session.dispose);
      expect(
        await loader.observeMembership(historical(loader), lease: lease),
        failure(MailProblemCode.cancelled),
      );
      expect(harness.factoryCalls, 0);
      noMailActions(harness);
    });
  });
}
