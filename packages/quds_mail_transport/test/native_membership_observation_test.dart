@TestOn('vm')
library;

import 'dart:async';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

import 'support/imap_fixture.dart';

FixtureMessage _message({List<String>? flags = const []}) => FixtureMessage(
  raw: fixtureBytes('Subject: Private\r\n\r\nBody must not be requested'),
  flags: flags,
);

MailImapIdentity _identity(ImapFixture fixture) => MailImapIdentity(
  mailbox: fixture.mailbox,
  uidValidity: fixture.uidValidity,
  uid: 1,
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
          command.startsWith('UID SEARCH ') ||
          command.startsWith('APPEND ') ||
          command == 'EXPUNGE' ||
          command == 'CLOSE',
    ),
    isEmpty,
  );
  for (final command in fixture.commands.where(
    (command) => command.startsWith('UID FETCH '),
  )) {
    expect(command, startsWith('UID FETCH 1:1 '));
    expect(command, contains('BODY.PEEK[HEADER.FIELDS '));
    expect(command, isNot(contains('BODY.PEEK[]')));
  }
}

void main() {
  test(
    'checks fresh source membership and Deleted without changing flags',
    () async {
      final original = _message(flags: [r'\Seen', r'\FLAGGED']);
      final fixture = ImapFixture(messages: {1: original})..readOnly = true;
      final provider = fixture.provider();
      final remote = _identity(fixture);
      final first = _value(
        await provider.observeMembership(remote, lease: _lease(fixture)),
      );
      expect(first.kind, MailMembershipObservationKind.present);
      expect(first.identity, remote);
      expect(first.mailboxes, [fixture.mailbox]);
      expect(first.isDeleted, isFalse);
      expect(first.deletionMailbox, isNull);
      expect(fixture.messages[1], same(original));

      final deleted = _message(flags: [r'\Deleted', r'\Draft']);
      fixture.messages[1] = deleted;
      final second = _value(
        await provider.observeMembership(remote, lease: _lease(fixture)),
      );
      expect(second.isDeleted, isTrue);
      expect(second.mailboxes, [fixture.mailbox]);
      expect(fixture.messages[1], same(deleted));
      expect(fixture.credentials.loads, 2);
      expect(fixture.clients.every((client) => client.socket.closed), isTrue);
      _readOnly(fixture);
    },
  );

  test('empty flags establish a present unmarked source UID', () async {
    final fixture = ImapFixture(messages: {1: _message()});
    final observed = _value(
      await fixture.provider().observeMembership(
        _identity(fixture),
        lease: _lease(fixture),
      ),
    );
    expect(observed.kind, MailMembershipObservationKind.present);
    expect(observed.isDeleted, isFalse);
    _readOnly(fixture);
  });

  test(
    'source absence supplies no destination identity or deletion claim',
    () async {
      final fixture = ImapFixture(messages: {2: _message()});
      final remote = _identity(fixture);
      final observed = _value(
        await fixture.provider().observeMembership(
          remote,
          lease: _lease(fixture),
        ),
      );
      expect(observed.kind, MailMembershipObservationKind.missing);
      expect(observed.identity, remote);
      expect(observed.mailboxes, isEmpty);
      expect(observed.isDeleted, isNull);
      expect(observed.deletionMailbox, isNull);
      _readOnly(fixture);
    },
  );

  test(
    'replaced UIDVALIDITY never reads an unrelated replacement UID',
    () async {
      final fixture = ImapFixture(messages: {1: _message()});
      final remote = _identity(fixture);
      fixture.uidValidity++;
      final observed = _value(
        await fixture.provider().observeMembership(
          remote,
          lease: _lease(fixture),
        ),
      );
      expect(observed.kind, MailMembershipObservationKind.identityChanged);
      expect(observed.identity, remote);
      expect(observed.mailboxes, isEmpty);
      expect(observed.isDeleted, isNull);
      expect(
        fixture.commands.where((command) => command.startsWith('UID FETCH ')),
        isEmpty,
      );
      _readOnly(fixture);
    },
  );

  for (final entry in <String, void Function(ImapFixture)>{
    'missing FLAGS': (fixture) => fixture.messages[1] = _message(flags: null),
    'wrong UID': (fixture) => fixture.wrongFetchedUid = true,
    'duplicate UID': (fixture) => fixture.duplicateFetch = true,
    'missing UIDVALIDITY': (fixture) => fixture.omitValidity = true,
  }.entries) {
    test('${entry.key} is a failed check, never known membership', () async {
      final fixture = ImapFixture(messages: {1: _message()});
      entry.value(fixture);
      _problem(
        await fixture.provider().observeMembership(
          _identity(fixture),
          lease: _lease(fixture),
        ),
        MailProblemCode.providerFailure,
      );
      _readOnly(fixture);
    });
  }

  test('wrong account/provider and lease do not access credentials', () async {
    final fixture = ImapFixture();
    final other = MailAccountId('other', profile: fixture.account.profile);
    final provider = fixture.provider();
    _problem(
      await provider.observeMembership(
        MailImapIdentity(
          mailbox: MailMailboxId('INBOX', account: other),
          uidValidity: 41,
          uid: 1,
        ),
        lease: _lease(fixture),
      ),
      MailProblemCode.invalidInput,
    );
    _problem(
      await provider.observeMembership(
        MailOpaqueIdentity(
          account: fixture.account,
          provider: MailProviderKind.ews,
          value: '1',
        ),
        lease: _lease(fixture),
      ),
      MailProblemCode.invalidInput,
    );
    _problem(
      await provider.observeMembership(
        _identity(fixture),
        lease: MailAccountSession(other).begin(),
      ),
      MailProblemCode.invalidInput,
    );
    expect(fixture.credentials.loads, 0);
    expect(fixture.commands, isEmpty);
  });

  test('cancelled and retired checks perform no IO', () async {
    final fixture = ImapFixture();
    final provider = fixture.provider();
    final session = MailAccountSession(fixture.account);
    final stale = session.begin();
    session.invalidate();
    _problem(
      await provider.observeMembership(_identity(fixture), lease: stale),
      MailProblemCode.staleOperation,
    );
    final cancellation = MailCancellationSource();
    final cancelled = session.begin(cancellation: cancellation.token);
    cancellation.cancel();
    _problem(
      await provider.observeMembership(_identity(fixture), lease: cancelled),
      MailProblemCode.cancelled,
    );
    expect(fixture.credentials.loads, 0);
    expect(fixture.commands, isEmpty);
  });

  for (final cancel in [false, true]) {
    test(
      '${cancel ? 'cancelled' : 'retired'} in-flight check suppresses late evidence',
      () async {
        final fixture = ImapFixture(messages: {1: _message()});
        final started = Completer<void>();
        final released = Completer<void>();
        fixture.beforeReply = (command) async {
          if (command.startsWith('UID FETCH ')) {
            started.complete();
            await released.future;
          }
        };
        final session = MailAccountSession(fixture.account);
        final cancellation = MailCancellationSource();
        final pending = fixture.provider().observeMembership(
          _identity(fixture),
          lease: session.begin(cancellation: cancellation.token),
        );
        await started.future;
        if (cancel) {
          cancellation.cancel();
        } else {
          session.invalidate();
        }
        _problem(
          await pending,
          cancel ? MailProblemCode.cancelled : MailProblemCode.staleOperation,
        );
        released.complete();
        await Future<void>.delayed(Duration.zero);
        _readOnly(fixture);
      },
    );
  }
}
