import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';

void main() {
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
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
      }
      for (final validity in [null, 0, -1, 0x100000000]) {
        await expectLater(
          loader.markRead(_mailbox(uidValidity: validity), _header()),
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
      }
      await expectLater(
        loader.markRead(
          _mailbox(flags: [mail.MailboxFlag.noSelect]),
          _header(),
        ),
        throwsA(_problem(MailProblemCode.invalidInput)),
      );
      final stale = _header()
        ..setGuid(
          email: 'fixture@example.test',
          encodedMailboxName: 'INBOX',
          mailboxUidValidity: 999,
        );
      await expectLater(
        loader.markRead(_mailbox(), stale),
        throwsA(_problem(MailProblemCode.conflict)),
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
        throwsA(_problem(MailProblemCode.providerFailure)),
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
        throwsA(_problem(MailProblemCode.invalidInput)),
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
        throwsA(_problem(MailProblemCode.cancelled)),
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
        throwsA(_problem(MailProblemCode.staleOperation)),
      );

      loader.dispose();
      await expectation.timeout(const Duration(seconds: 1));
      await expectLater(
        loader.markRead(_mailbox(), _header()),
        throwsA(_problem(MailProblemCode.staleOperation)),
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

Matcher _problem(MailProblemCode code) => isA<StudioMailMessageLoadException>()
    .having((error) => error.code, 'code', code);

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
  _Answer? answer;
  _ApplyAnswer? applyAnswer;
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
    );
  }
}

final class _Provider implements MailProvider {
  _Provider(this.account, this.answer, this.applyAnswer);

  @override
  final MailAccountId account;
  final _Answer answer;
  final _ApplyAnswer applyAnswer;

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
