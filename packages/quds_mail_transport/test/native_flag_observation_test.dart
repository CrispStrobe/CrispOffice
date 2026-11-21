@TestOn('vm')
library;

import 'dart:async';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

import 'support/imap_fixture.dart';

FixtureMessage _message({List<String>? flags = const []}) => FixtureMessage(
  raw: fixtureBytes('Subject: Body must not be requested\r\n\r\nPrivate body'),
  flags: flags,
);

MailImapIdentity _identity(ImapFixture fixture, [int uid = 1]) =>
    MailImapIdentity(
      mailbox: fixture.mailbox,
      uidValidity: fixture.uidValidity,
      uid: uid,
    );

MailOperationLease _lease(ImapFixture fixture) =>
    MailAccountSession(fixture.account).begin();

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  final problem = (result as MailFailure<T>).problem;
  expect(problem.code, code);
  expect(problem.mutationMayHaveOccurred, isFalse);
}

void _readOnly(ImapFixture fixture) {
  expect(
    fixture.commands.where(
      (command) =>
          command.startsWith('UID STORE ') ||
          command.startsWith('UID MOVE ') ||
          command.startsWith('UID COPY ') ||
          command.startsWith('APPEND ') ||
          command == 'EXPUNGE' ||
          command == 'CLOSE',
    ),
    isEmpty,
  );
  for (final command in fixture.commands.where(
    (command) => command.startsWith('UID FETCH '),
  )) {
    expect(command, contains('BODY.PEEK[HEADER.FIELDS '));
    expect(command, isNot(contains('BODY.PEEK[]')));
  }
}

void main() {
  test('observes fresh exact UID flags without Seen or body changes', () async {
    final original = _message(flags: [r'\FLAGGED', r'\Answered']);
    final fixture = ImapFixture(messages: {1: original})..readOnly = true;
    final provider = fixture.provider();
    final remote = _identity(fixture);
    final first = _value(
      await provider.observeFlags(remote, lease: _lease(fixture)),
    );
    expect(first.kind, MailFlagObservationKind.present);
    expect(first.identity, remote);
    expect(
      first.flags,
      const MailMessageFlags(isFlagged: true, isAnswered: true),
    );
    expect(fixture.messages[1], same(original));

    fixture.messages[1] = _message(flags: [r'\Seen', r'\Draft', r'\Deleted']);
    final second = _value(
      await provider.observeFlags(remote, lease: _lease(fixture)),
    );
    expect(
      second.flags,
      const MailMessageFlags(isRead: true, isDraft: true, isDeleted: true),
    );
    expect(fixture.credentials.loads, 2);
    expect(fixture.clients, hasLength(2));
    expect(fixture.clients.every((client) => client.socket.closed), isTrue);
    _readOnly(fixture);
  });

  test('explicit empty FLAGS is a known snapshot', () async {
    final fixture = ImapFixture(messages: {1: _message()});
    final observed = _value(
      await fixture.provider().observeFlags(
        _identity(fixture),
        lease: _lease(fixture),
      ),
    );
    expect(observed.kind, MailFlagObservationKind.present);
    expect(observed.flags, const MailMessageFlags());
    _readOnly(fixture);
  });

  test('changed UIDVALIDITY invalidates only the original identity', () async {
    final fixture = ImapFixture(messages: {1: _message()});
    final remote = _identity(fixture);
    fixture.uidValidity++;
    final observed = _value(
      await fixture.provider().observeFlags(remote, lease: _lease(fixture)),
    );
    expect(observed.kind, MailFlagObservationKind.identityChanged);
    expect(observed.identity, remote);
    expect(observed.flags, isNull);
    expect(
      fixture.commands.where((command) => command.startsWith('UID FETCH ')),
      isEmpty,
    );
    _readOnly(fixture);
  });

  test('completed exact UID read can establish current absence', () async {
    final fixture = ImapFixture(messages: {2: _message()});
    final remote = _identity(fixture);
    final observed = _value(
      await fixture.provider().observeFlags(remote, lease: _lease(fixture)),
    );
    expect(observed.kind, MailFlagObservationKind.missing);
    expect(observed.identity, remote);
    expect(observed.flags, isNull);
    expect(
      fixture.commands.singleWhere(
        (command) => command.startsWith('UID FETCH '),
      ),
      startsWith('UID FETCH 1:1 '),
    );
    _readOnly(fixture);
  });

  for (final entry in <String, void Function(ImapFixture)>{
    'omitted flags': (fixture) => fixture.messages[1] = _message(flags: null),
    'wrong returned UID': (fixture) => fixture.wrongFetchedUid = true,
    'duplicate returned UID': (fixture) => fixture.duplicateFetch = true,
    'missing UIDVALIDITY': (fixture) => fixture.omitValidity = true,
  }.entries) {
    test('${entry.key} cannot certify a flag observation', () async {
      final fixture = ImapFixture(messages: {1: _message()});
      entry.value(fixture);
      _problem(
        await fixture.provider().observeFlags(
          _identity(fixture),
          lease: _lease(fixture),
        ),
        MailProblemCode.providerFailure,
      );
      _readOnly(fixture);
    });
  }

  test(
    'cross-account identity and lease fail before credentials or IO',
    () async {
      final fixture = ImapFixture(messages: {1: _message()});
      final other = MailAccountId('other', profile: fixture.account.profile);
      final provider = fixture.provider();
      _problem(
        await provider.observeFlags(
          MailImapIdentity(
            mailbox: MailMailboxId('INBOX', account: other),
            uidValidity: fixture.uidValidity,
            uid: 1,
          ),
          lease: _lease(fixture),
        ),
        MailProblemCode.invalidInput,
      );
      _problem(
        await provider.observeFlags(
          _identity(fixture),
          lease: MailAccountSession(other).begin(),
        ),
        MailProblemCode.invalidInput,
      );
      _problem(
        await provider.observeFlags(
          MailOpaqueIdentity(
            account: fixture.account,
            provider: MailProviderKind.ews,
            value: '1',
          ),
          lease: _lease(fixture),
        ),
        MailProblemCode.invalidInput,
      );
      expect(fixture.credentials.loads, 0);
      expect(fixture.commands, isEmpty);
    },
  );

  test(
    'retired and cancelled observation leases never read credentials',
    () async {
      final fixture = ImapFixture(messages: {1: _message()});
      final provider = fixture.provider();
      final session = MailAccountSession(fixture.account);
      final stale = session.begin();
      session.invalidate();
      _problem(
        await provider.observeFlags(_identity(fixture), lease: stale),
        MailProblemCode.staleOperation,
      );
      final cancellation = MailCancellationSource();
      final cancelled = session.begin(cancellation: cancellation.token);
      cancellation.cancel();
      _problem(
        await provider.observeFlags(_identity(fixture), lease: cancelled),
        MailProblemCode.cancelled,
      );
      expect(fixture.credentials.loads, 0);
      expect(fixture.commands, isEmpty);
    },
  );

  test('late fetched flags cannot outlive the account generation', () async {
    final fixture = ImapFixture(
      messages: {
        1: _message(flags: [r'\Seen']),
      },
    );
    final started = Completer<void>();
    final release = Completer<void>();
    fixture.beforeReply = (command) async {
      if (command.startsWith('UID FETCH ')) {
        started.complete();
        await release.future;
      }
    };
    final session = MailAccountSession(fixture.account);
    final pending = fixture.provider().observeFlags(
      _identity(fixture),
      lease: session.begin(),
    );
    await started.future;
    session.invalidate();
    _problem(await pending, MailProblemCode.staleOperation);
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fixture.clients.single.socket.closed, isTrue);
    _readOnly(fixture);
  });
}
