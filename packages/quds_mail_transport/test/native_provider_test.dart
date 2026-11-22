import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:test/test.dart';

import 'support/imap_fixture.dart';

FixtureMessage _message({List<String>? flags = const []}) => FixtureMessage(
  raw: fixtureBytes(
    'From: sender@example.test\r\n'
    'To: recipient@example.test\r\nSubject: Fixture\r\n\r\nBody\r\n',
  ),
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

MailProblemCode _code<T>(MailResult<T> result) =>
    (result as MailFailure<T>).problem.code;

void main() {
  group('foreground move/delete evidence', () {
    for (final destination in ['INBOX', 'inbox', 'iNbOx']) {
      test(
        'same-folder MOVE to $destination is refused before login',
        () async {
          final fixture = ImapFixture(messages: {1: _message()});
          final result = await fixture.provider().apply(
            MailMove(
              id: 'same-folder',
              message: _identity(fixture),
              destination: MailMailboxId(destination, account: fixture.account),
            ),
            _lease(fixture),
          );
          expect(_code(result), MailProblemCode.invalidInput);
          expect(
            (result as MailFailure<MailUnit>).problem.mutationMayHaveOccurred,
            isFalse,
          );
          expect(fixture.credentials.loads, 0);
          expect(fixture.commands, isEmpty);
          expect(fixture.messages, hasLength(1));
        },
      );
    }

    for (final action in [MailBulkFlagAction.move, MailBulkFlagAction.delete]) {
      test(
        '${action.name} on a read-only mailbox proves no mutation',
        () async {
          final fixture = ImapFixture(messages: {1: _message()})
            ..readOnly = true;
          final plan = MailBulkFlagPlan(
            id: 'read-only',
            mailbox: fixture.mailbox,
            action: action,
            destination: action == MailBulkFlagAction.move
                ? MailMailboxId('Archive', account: fixture.account)
                : null,
            messages: [_identity(fixture)],
          );
          final result = await fixture.provider().apply(
            plan.operationAt(0),
            _lease(fixture),
          );
          expect(_code(result), MailProblemCode.permissionDenied);
          expect(
            (result as MailFailure<MailUnit>).problem.mutationMayHaveOccurred,
            isFalse,
          );
          expect(
            fixture.commands.where(
              (command) =>
                  command.startsWith('UID MOVE ') ||
                  command.startsWith('UID STORE '),
            ),
            isEmpty,
          );
        },
      );

      for (final lostReply in [true, false]) {
        test(
          '${action.name} ${lostReply ? 'lost reply' : 'unconfirmed effect'} stops without replay',
          () async {
            final fixture =
                ImapFixture(messages: {1: _message(), 2: _message()})
                  ..closeAfterMutation = lostReply
                  ..acknowledgeWithoutChange = !lostReply;
            final provider = fixture.provider();
            final report = await MailBulkFlagRunner().run(
              plan: MailBulkFlagPlan(
                id: 'membership-evidence',
                mailbox: fixture.mailbox,
                action: action,
                destination: action == MailBulkFlagAction.move
                    ? MailMailboxId('Archive', account: fixture.account)
                    : null,
                messages: [_identity(fixture), _identity(fixture, 2)],
              ),
              lease: _lease(fixture),
              apply: provider.apply,
              isScopeCurrent: () => true,
            );
            expect(report.uncertainCount, 1);
            expect(report.unattemptedCount, 1);
            expect(report.items.first.problem?.mutationMayHaveOccurred, isTrue);
            expect(report.requiresRefresh, isTrue);
            expect(
              fixture.commands.where(
                (command) =>
                    command.startsWith('UID MOVE ') ||
                    command.startsWith('UID STORE '),
              ),
              hasLength(1),
            );
            expect(
              fixture.commands.any(
                (command) =>
                    command.contains('EXPUNGE') ||
                    command.contains('COPY') ||
                    command == 'CLOSE',
              ),
              isFalse,
            );
            expect(fixture.messages[2]!.flags, isEmpty);
          },
        );
      }
    }
  });

  test(
    'bulk IMAP failures distinguish stale generation from uncertain STORE',
    () async {
      final fixture = ImapFixture(messages: {1: _message(), 2: _message()});
      final identity = _identity(fixture);
      fixture.uidValidity++;
      final beforeWrite = await fixture.provider().apply(
        MailSetRead(id: 'stale-generation', message: identity, read: true),
        _lease(fixture),
      );
      expect(_code(beforeWrite), MailProblemCode.conflict);
      expect(
        (beforeWrite as MailFailure<MailUnit>).problem.mutationMayHaveOccurred,
        isFalse,
      );
      expect(
        fixture.commands.where((command) => command.startsWith('UID STORE ')),
        isEmpty,
      );

      fixture.closeAfterMutation = true;
      final provider = fixture.provider();
      final report = await MailBulkFlagCoordinator().run(
        plan: MailBulkFlagPlan(
          id: 'uncertain-imap',
          mailbox: fixture.mailbox,
          provider: MailProviderKind.imap,
          action: MailBulkFlagAction.markRead,
          messages: [_identity(fixture, 1), _identity(fixture, 2)],
        ),
        lease: _lease(fixture),
        apply: (operation, lease) async => MailBulkFlagAttempt.fromResult(
          await provider.apply(operation, lease),
        ),
        isScopeCurrent: () => true,
      );
      expect(report.uncertainCount, 1);
      expect(report.unattemptedCount, 1);
      expect(report.items.first.problem?.mutationMayHaveOccurred, isTrue);
      expect(
        fixture.commands.where((command) => command.startsWith('UID STORE ')),
        hasLength(1),
      );
      expect(fixture.messages[1]!.flags, contains(r'\Seen'));
      expect(fixture.messages[2]!.flags, isEmpty);
    },
  );

  test(
    'bulk IMAP missing UID is definite and later selected UID still runs',
    () async {
      final fixture = ImapFixture(messages: {1: _message(), 3: _message()});
      final provider = fixture.provider();
      final report = await MailBulkFlagCoordinator().run(
        plan: MailBulkFlagPlan(
          id: 'missing-imap',
          mailbox: fixture.mailbox,
          provider: MailProviderKind.imap,
          action: MailBulkFlagAction.flag,
          messages: [
            _identity(fixture, 1),
            _identity(fixture, 2),
            _identity(fixture, 3),
          ],
        ),
        lease: _lease(fixture),
        apply: (operation, lease) async => MailBulkFlagAttempt.fromResult(
          await provider.apply(operation, lease),
        ),
        isScopeCurrent: () => true,
      );
      expect(report.confirmedCount, 2);
      expect(report.failedCount, 1);
      expect(report.items[1].problem?.mutationMayHaveOccurred, isFalse);
      expect(report.requiresRefresh, isFalse);
      expect(
        fixture.commands.where((command) => command.startsWith('UID STORE ')),
        hasLength(2),
      );
    },
  );

  test(
    'actual command parser discovers selectable folders over required TLS',
    () async {
      final fixture = ImapFixture();
      final result = await fixture.provider().listMailboxes(_lease(fixture));
      expect(
        (result as MailSuccess<List<MailMailbox>>).value.map(
          (box) => box.id.value,
        ),
        ['INBOX', 'Archive'],
      );
      expect(fixture.clients.single.requestedSecure, isTrue);
      expect(fixture.clients.single.socket.closed, isTrue);
      expect(
        fixture.commands.where((command) => command == 'CAPABILITY'),
        hasLength(2),
      );
    },
  );

  test(
    'late socket completion after cancellation is destroyed before greeting/auth',
    () async {
      final fixture = ImapFixture();
      final connected = Completer<void>();
      final release = Completer<void>();
      fixture.beforeConnect = () async {
        connected.complete();
        await release.future;
      };
      final cancellation = MailCancellationSource();
      final provider = fixture.provider();
      final pending = provider.capabilities(
        MailAccountSession(
          fixture.account,
        ).begin(cancellation: cancellation.token),
      );
      await connected.future;
      cancellation.cancel();
      expect(_code(await pending), MailProblemCode.cancelled);
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fixture.clients.single.socket.closed, isTrue);
      expect(fixture.clients.single.isConnected, isFalse);
      expect(fixture.commands, isEmpty);
      fixture.beforeConnect = null;
      expect(
        await provider.capabilities(_lease(fixture)),
        isA<MailSuccess<MailCapabilities>>(),
      );
    },
  );

  test(
    'required STARTTLS completes before authentication and refreshes capabilities',
    () async {
      final fixture = ImapFixture(supportsStartTls: true);
      expect(
        await fixture
            .provider(tls: MailTlsMode.startTls)
            .capabilities(_lease(fixture)),
        isA<MailSuccess<MailCapabilities>>(),
      );
      final tls = fixture.commands.indexOf('STARTTLS');
      final login = fixture.commands.indexWhere(
        (command) => command.startsWith('LOGIN '),
      );
      expect(tls, greaterThanOrEqualTo(0));
      expect(login, greaterThan(tls));
      expect(fixture.commands.sublist(tls + 1, login), ['CAPABILITY']);
      expect(
        fixture.clients.single.sockets.every((socket) => socket.closed),
        isTrue,
      );
    },
  );

  test(
    'late TLS upgrade cannot revive an aborted account generation',
    () async {
      final fixture = ImapFixture(supportsStartTls: true);
      final started = Completer<void>();
      final release = Completer<void>();
      fixture.beforeTlsUpgrade = () async {
        started.complete();
        await release.future;
      };
      final session = MailAccountSession(fixture.account);
      final pending = fixture
          .provider(tls: MailTlsMode.startTls)
          .capabilities(session.begin());
      await started.future;
      session.invalidate();
      expect(_code(await pending), MailProblemCode.staleOperation);
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        fixture.clients.single.sockets.every((socket) => socket.closed),
        isTrue,
      );
      expect(fixture.clients.single.isConnected, isFalse);
      expect(
        fixture.commands.any((command) => command.startsWith('LOGIN ')),
        isFalse,
      );
    },
  );

  test(
    'capabilities do not promise SMTP, calendar or missing MOVE extension',
    () async {
      final fixture = ImapFixture(supportsMove: false);
      final result = await fixture.provider().capabilities(_lease(fixture));
      expect((result as MailSuccess<MailCapabilities>).value.supported, {
        MailCapability.mail,
        MailCapability.folders,
        MailCapability.delete,
      });
    },
  );

  test('missing STARTTLS refuses credentials instead of downgrading', () async {
    final fixture = ImapFixture();
    final result = await fixture
        .provider(tls: MailTlsMode.startTls)
        .capabilities(_lease(fixture));
    expect(_code(result), MailProblemCode.permissionDenied);
    expect(
      fixture.commands.any((command) => command.startsWith('LOGIN ')),
      isFalse,
    );
    expect(fixture.clients.single.requestedSecure, isFalse);
    expect(fixture.clients.single.socket.closed, isTrue);
  });

  test(
    'missing and rejected credentials are typed and never reused from cache',
    () async {
      final fixture = ImapFixture(rejectLogin: true);
      final provider = fixture.provider();
      expect(
        _code(await provider.capabilities(_lease(fixture))),
        MailProblemCode.authenticationRequired,
      );
      fixture.credentials.revoked = true;
      fixture.commands.clear();
      expect(
        _code(await provider.capabilities(_lease(fixture))),
        MailProblemCode.authenticationRequired,
      );
      expect(fixture.credentials.loads, 2);
      expect(fixture.commands, isEmpty);
    },
  );

  test('fragmented greeting is framed before any command executes', () async {
    final fixture = ImapFixture()..fragmentedGreeting = true;
    expect(
      await fixture.provider().capabilities(_lease(fixture)),
      isA<MailSuccess<MailCapabilities>>(),
    );
    expect(fixture.clients.single.socket.errors, isEmpty);
  });

  test(
    'discovered UID pages retain flags and reconcile gaps with scoped ranges',
    () async {
      final fixture = ImapFixture(
        uidNext: 5,
        messages: {
          1: _message(flags: [r'\Seen', r'\Flagged', r'\Recent']),
          3: _message(flags: []),
        },
      );
      final provider = fixture.provider();
      final first =
          (await provider.pullChanges(
                    fixture.mailbox,
                    limit: 1,
                    lease: _lease(fixture),
                  )
                  as MailSuccess<MailSyncPage>)
              .value;
      expect(
        first.upserts.single.flags,
        const MailMessageFlags(isRead: true, isFlagged: true),
      );
      expect(first.tombstones, isEmpty);
      expect(first.imapRange!.firstUid, 1);
      expect(first.imapRange!.lastUid, 1);
      expect(first.hasMore, isTrue);
      expect(first.resetRequired, isFalse);
      final second =
          (await provider.pullChanges(
                    fixture.mailbox,
                    cursor: first.next,
                    limit: 1,
                    lease: _lease(fixture),
                  )
                  as MailSuccess<MailSyncPage>)
              .value;
      expect((second.upserts.single.remote as MailImapIdentity).uid, 3);
      expect(second.upserts.single.flags, const MailMessageFlags());
      expect(second.tombstones, isEmpty);
      expect(second.imapRange!.firstUid, 2);
      expect(second.imapRange!.lastUid, 4);
      expect(second.hasMore, isFalse);
      expect(
        fixture.commands.where((command) => command.startsWith('UID FETCH ')),
        everyElement(contains('BODY.PEEK[HEADER.FIELDS')),
      );
    },
  );

  test(
    'omitted FLAGS remains unknown instead of clearing durable observations',
    () async {
      final fixture = ImapFixture(
        uidNext: 2,
        messages: {1: _message(flags: null)},
      );
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 1,
        lease: _lease(fixture),
      );
      expect(
        (result as MailSuccess<MailSyncPage>).value.upserts.single.flags,
        isNull,
      );
    },
  );

  test(
    'ordinary multipart source synchronizes only requested envelope headers',
    () async {
      final header = fixtureBytes(
        'From: sender@example.test\r\nSubject: Multipart\r\n'
        'Content-Type: multipart/mixed; boundary="parts"\r\n'
        'Content-Transfer-Encoding: binary\r\n\r\n',
      );
      final fixture = ImapFixture(
        uidNext: 2,
        messages: {
          1: FixtureMessage(
            raw: fixtureBytes('not downloaded'),
            headers: header,
          ),
        },
      );
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 1,
        lease: _lease(fixture),
      );
      expect(
        (result as MailSuccess<MailSyncPage>)
            .value
            .upserts
            .single
            .envelope
            .subject,
        'Multipart',
      );
      expect(
        fixture.commands.any((command) => command.contains('BODY.PEEK[]')),
        isFalse,
      );
    },
  );

  test(
    'mixed-case IMAP FETCH atoms preserve messages instead of inventing tombstones',
    () async {
      final fixture = ImapFixture(
        uidNext: 2,
        messages: {
          1: _message(flags: [r'\Seen']),
        },
      )..lowerCaseFetch = true;
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 1,
        lease: _lease(fixture),
      );
      final page = (result as MailSuccess<MailSyncPage>).value;
      expect(page.upserts, hasLength(1));
      expect(page.upserts.single.flags?.isRead, isTrue);
      expect(page.tombstones, isEmpty);
    },
  );

  test(
    'UIDVALIDITY rollover restarts the cursor and explicitly requests reset',
    () async {
      final fixture = ImapFixture(uidNext: 4, messages: {1: _message()});
      final provider = fixture.provider();
      final first =
          (await provider.pullChanges(
                    fixture.mailbox,
                    limit: 1,
                    lease: _lease(fixture),
                  )
                  as MailSuccess<MailSyncPage>)
              .value;
      fixture.uidValidity++;
      final next =
          (await provider.pullChanges(
                    fixture.mailbox,
                    cursor: first.next,
                    limit: 1,
                    lease: _lease(fixture),
                  )
                  as MailSuccess<MailSyncPage>)
              .value;
      expect(next.resetRequired, isTrue);
      expect((next.upserts.single.remote as MailImapIdentity).uid, 1);
      expect(next.upserts.single.id, isNot(first.upserts.single.id));
    },
  );

  for (final afterLiteral in [false, true]) {
    final position = afterLiteral ? 'after' : 'before';
    for (final entry in <String, String>{
      'same UID': r'* 1 FETCH (UID 1 FLAGS (\Seen))',
      'unrelated UID': r'* 7 FETCH (UID 99 FLAGS (\Seen))',
      'rev1 without UID': r'* 7 FETCH (FLAGS (\Seen))',
    }.entries) {
      test(
        '${entry.key} flag notification $position literal does not consume the page limit',
        () async {
          final fixture = ImapFixture(uidNext: 2, messages: {1: _message()});
          (afterLiteral
                  ? fixture.afterFetchResponses
                  : fixture.beforeFetchResponses)
              .add(entry.value);
          final result = await fixture.provider().pullChanges(
            fixture.mailbox,
            limit: 1,
            lease: _lease(fixture),
          );
          final page = (result as MailSuccess<MailSyncPage>).value;
          expect(page.upserts, hasLength(1));
          expect((page.upserts.single.remote as MailImapIdentity).uid, 1);
          expect(
            page.upserts.single.flags?.isRead,
            afterLiteral && entry.key == 'same UID',
          );
          expect(page.tombstones, isEmpty);
          expect(fixture.clients.single.socket.errors, isEmpty);
        },
      );
    }
  }

  test(
    'sequence-correlated rev1 notifications allow a sparse completed response',
    () async {
      final fixture = ImapFixture(uidNext: 3, messages: {1: _message()})
        ..beforeFetchResponses.add(r'* 1 FETCH (FLAGS (\Seen))')
        ..afterFetchResponses.add('* 1 FETCH (FLAGS ())');
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 2,
        lease: _lease(fixture),
      );
      final page = (result as MailSuccess<MailSyncPage>).value;
      expect(page.upserts, hasLength(1));
      expect(page.tombstones, isEmpty);
      expect(page.imapRange!.lastUid, 2);
    },
  );

  test(
    'unrelated rev1 updates stay bounded when a full UID interval is returned',
    () async {
      final fixture = ImapFixture(uidNext: 2, messages: {1: _message()})
        ..beforeFetchResponses.addAll([
          '* 7 FETCH (FLAGS ())',
          '* 8 FETCH (FLAGS ())',
          '* 9 FETCH (FLAGS ())',
        ]);
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 1,
        lease: _lease(fixture),
      );
      final page = (result as MailSuccess<MailSyncPage>).value;
      expect(page.upserts, hasLength(1));
      expect(page.tombstones, isEmpty);
    },
  );

  for (final entry in <String, List<String>>{
    'in-range UID with no complete literal': [
      r'* 2 FETCH (UID 2 FLAGS (\Seen))',
    ],
    'unknown rev1 sequence in a sparse response': [
      r'* 7 FETCH (FLAGS (\Seen))',
    ],
    'rev1 sequence identity changed by EXPUNGE': [
      r'* 1 FETCH (FLAGS (\Seen))',
      '* 1 EXPUNGE',
    ],
  }.entries) {
    test('${entry.key} cannot fabricate a successful tombstone page', () async {
      final fixture = ImapFixture(uidNext: 3, messages: {1: _message()})
        ..beforeFetchResponses.addAll(entry.value);
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 2,
        lease: _lease(fixture),
      );
      expect(result, isA<MailFailure<MailSyncPage>>());
      expect(fixture.clients.single.socket.closed, isTrue);
    });
  }

  for (final entry in <String, String>{
    'invalid UID': r'* 1 FETCH (UID invalid FLAGS (\Seen))',
    'duplicate UID': r'* 1 FETCH (UID 1 UID 1 FLAGS (\Seen))',
    'duplicate flags': r'* 1 FETCH (UID 1 FLAGS () FLAGS (\Seen))',
    'nested flag': r'* 1 FETCH (UID 1 FLAGS (\Seen (nested)))',
    'missing BODY literal': r'* 1 FETCH (UID 1 FLAGS (\Seen) BODY[] NIL)',
  }.entries) {
    test('malformed notification with ${entry.key} fails atomically', () async {
      final fixture = ImapFixture(uidNext: 2, messages: {1: _message()})
        ..beforeFetchResponses.add(entry.value);
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 1,
        lease: _lease(fixture),
      );
      expect(result, isA<MailFailure<MailSyncPage>>());
      expect(fixture.clients.single.socket.closed, isTrue);
    });
  }

  test(
    'flags alone never turn an omitted requested literal into an empty success',
    () async {
      final fixture = ImapFixture(uidNext: 2)
        ..searchResponses = ['* SEARCH 1']
        ..beforeFetchResponses.add(r'* 1 FETCH (UID 1 FLAGS (\Seen))');
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 1,
        lease: _lease(fixture),
      );
      expect(result, isA<MailFailure<MailSyncPage>>());
    },
  );

  for (final withUid in [false, true]) {
    test(
      'late ${withUid ? 'UID' : 'sequence'} flag update prevents false STORE confirmation',
      () async {
        final fixture = ImapFixture(uidNext: 2, messages: {1: _message()})
          ..afterFetchResponses.add(
            '* 1 FETCH (${withUid ? 'UID 1 ' : ''}FLAGS ())',
          );
        final result = await fixture.provider().apply(
          MailSetRead(
            id: 'read-with-concurrent-change',
            message: _identity(fixture),
            read: true,
          ),
          _lease(fixture),
        );
        expect(_code(result), MailProblemCode.conflict);
        expect(fixture.messages[1]!.flags, contains(r'\Seen'));
        expect(
          fixture.commands.where((command) => command.startsWith('UID STORE ')),
          hasLength(1),
        );
      },
    );
  }

  test(
    'EXPUNGE followed by an uncorrelated rev1 update cannot confirm STORE',
    () async {
      final fixture = ImapFixture(uidNext: 2, messages: {1: _message()});
      fixture.beforeReply = (command) async {
        if (command.startsWith('UID STORE ')) {
          fixture.afterFetchResponses.addAll([
            '* 1 EXPUNGE',
            '* 1 FETCH (FLAGS ())',
          ]);
        }
      };
      final result = await fixture.provider().apply(
        MailSetRead(
          id: 'read-with-expunge-renumbering',
          message: _identity(fixture),
          read: true,
        ),
        _lease(fixture),
      );
      expect(_code(result), MailProblemCode.conflict);
      expect(fixture.messages[1]!.flags, contains(r'\Seen'));
      expect(
        fixture.commands.where((command) => command.startsWith('UID STORE ')),
        hasLength(1),
      );
    },
  );

  for (final entry in <(String, String, bool)>[
    ('OK before literal', '* OK [ALERT] FETCH cache is refreshing', false),
    ('mixed-case OK after literal', '* oK FETCH response is complete', true),
    ('NO after literal', '* NO [ALERT] FETCH cache is unavailable', true),
    ('BAD before literal', '* BAD FETCH warning has no command tag', false),
  ]) {
    test('status text containing FETCH: ${entry.$1}', () async {
      final fixture = ImapFixture(uidNext: 2, messages: {1: _message()});
      (entry.$3 ? fixture.afterFetchResponses : fixture.beforeFetchResponses)
          .add(entry.$2);
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 1,
        lease: _lease(fixture),
      );
      final page = (result as MailSuccess<MailSyncPage>).value;
      expect(page.upserts, hasLength(1));
      expect((page.upserts.single.remote as MailImapIdentity).uid, 1);
      expect(page.tombstones, isEmpty);
      expect(fixture.clients.single.socket.errors, isEmpty);
    });
  }

  test(
    'forged cross-mailbox cursor is rejected before vault or connection work',
    () async {
      final fixture = ImapFixture(uidNext: 4);
      final provider = fixture.provider();
      final first =
          (await provider.pullChanges(
                    fixture.mailbox,
                    limit: 1,
                    lease: _lease(fixture),
                  )
                  as MailSuccess<MailSyncPage>)
              .value;
      final other = MailMailboxId('Archive', account: fixture.account);
      fixture.commands.clear();
      final result = await provider.pullChanges(
        other,
        cursor: MailCursor(mailbox: other, value: first.next.value),
        limit: 1,
        lease: _lease(fixture),
      );
      expect(_code(result), MailProblemCode.invalidInput);
      expect(fixture.commands, isEmpty);
    },
  );

  test(
    'sparse high UIDNEXT synchronizes without enumerating numeric holes',
    () async {
      final fixture = ImapFixture(
        uidNext: 1000001,
        messages: {1000000: _message()},
      );
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 100,
        lease: _lease(fixture),
      );
      final page = (result as MailSuccess<MailSyncPage>).value;
      expect((page.upserts.single.remote as MailImapIdentity).uid, 1000000);
      expect(page.tombstones, isEmpty);
      expect(page.imapRange!.firstUid, 1);
      expect(page.imapRange!.lastUid, 1000000);
      expect(page.hasMore, isFalse);
      expect(
        fixture.commands.any((command) => command.startsWith('UID FETCH ')),
        isTrue,
      );
    },
  );

  test(
    'on-demand literal retains bare LF and non-UTF8 octets without reserialization',
    () async {
      final raw = Uint8List.fromList([
        ...utf8.encode(
          'From: sender@example.test\r\nSubject: Exact\r\n'
          'Content-Type: text/plain; charset=windows-1252\r\n'
          'Content-Transfer-Encoding: 8bit\r\n\r\n',
        ),
        67,
        97,
        102,
        0xe9,
        10,
        88,
      ]);
      final fixture = ImapFixture(messages: {1: FixtureMessage(raw: raw)});
      final result = await fixture.provider().fetchMessage(
        _identity(fixture),
        budget: const MailReadBudget(),
        lease: _lease(fixture),
      );
      final message = (result as MailSuccess<MailMessage>).value;
      expect(message.raw.bytes, raw);
      expect(message.remoteIdentity, _identity(fixture));
      expect(message.body.plainText, contains('Café'));
      expect(fixture.commands.last, contains('BODY.PEEK[]'));
    },
  );

  test('stale full-message UIDVALIDITY fails before body fetch', () async {
    final fixture = ImapFixture(messages: {1: _message()});
    final identity = _identity(fixture);
    fixture.uidValidity++;
    final result = await fixture.provider().fetchMessage(
      identity,
      budget: const MailReadBudget(),
      lease: _lease(fixture),
    );
    expect(_code(result), MailProblemCode.conflict);
    expect(
      fixture.commands.any((command) => command.contains('BODY.PEEK[]')),
      isFalse,
    );
  });

  final invalid = <String, void Function(ImapFixture)>{
    'out-of-range UID': (fixture) => fixture.wrongFetchedUid = true,
    'duplicate FETCH': (fixture) => fixture.duplicateFetch = true,
    'unbalanced response': (fixture) => fixture.malformedLiteral = true,
    'partial BODY literal': (fixture) => fixture.partialBody = true,
  };
  for (final entry in invalid.entries) {
    test(
      '${entry.key} cannot turn a tagged OK into a partial success',
      () async {
        final fixture = ImapFixture(messages: {1: _message()});
        entry.value(fixture);
        final result = await fixture.provider().fetchMessage(
          _identity(fixture),
          budget: const MailReadBudget(),
          lease: _lease(fixture),
        );
        expect(result, isA<MailFailure<MailMessage>>());
        expect(fixture.clients.single.socket.closed, isTrue);
      },
    );
  }

  test(
    'malformed FETCH prefix cannot create an empty successful sync/tombstone page',
    () async {
      final fixture = ImapFixture(uidNext: 2, messages: {1: _message()})
        ..malformedFetchPrefix = true;
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 1,
        lease: _lease(fixture),
      );
      expect(result, isA<MailFailure<MailSyncPage>>());
      expect(fixture.clients.single.socket.closed, isTrue);
    },
  );

  for (final delimiters in [
    ('missing list separator', ' ', ''),
    ('tab list separator', ' ', '\t'),
    ('tab sequence separator', '\t', ' '),
    ('attached quoted prefix', ' ', '"bad" '),
    ('attached closing list', ' ', ')'),
  ]) {
    test(
      'FETCH with ${delimiters.$1} cannot fabricate a successful tombstone page',
      () async {
        final fixture = ImapFixture(uidNext: 2, messages: {1: _message()})
          ..fetchSequenceSeparator = delimiters.$2
          ..fetchListSeparator = delimiters.$3;
        final result = await fixture.provider().pullChanges(
          fixture.mailbox,
          limit: 1,
          lease: _lease(fixture),
        );
        expect(result, isA<MailFailure<MailSyncPage>>());
        expect(fixture.clients.single.socket.closed, isTrue);
      },
    );
  }

  test(
    'FETCH with attached literal cannot fabricate a tombstone page',
    () async {
      final fixture = ImapFixture(uidNext: 2, messages: {1: _message()})
        ..bareFetchLiteral = true;
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 1,
        lease: _lease(fixture),
      );
      expect(result, isA<MailFailure<MailSyncPage>>());
      expect(fixture.clients.single.socket.closed, isTrue);
    },
  );

  test(
    'rejected duplicate sync record never advances a successful partial page',
    () async {
      final fixture = ImapFixture(uidNext: 2, messages: {1: _message()})
        ..duplicateFetch = true;
      final result = await fixture.provider().pullChanges(
        fixture.mailbox,
        limit: 2,
        lease: _lease(fixture),
      );
      expect(result, isA<MailFailure<MailSyncPage>>());
    },
  );

  test('malformed raw response never logs private literal text', () async {
    final output = <String>[];
    final fixture = ImapFixture(
      messages: {
        1: FixtureMessage(
          raw: fixtureBytes('Subject: private-sentinel-719\r\n\r\nsecret-body'),
        ),
      },
    )..malformedLiteral = true;
    final result = await runZoned(
      () => fixture.provider().fetchMessage(
        _identity(fixture),
        budget: const MailReadBudget(),
        lease: _lease(fixture),
      ),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => output.add(line),
      ),
    );
    expect(result, isA<MailFailure<MailMessage>>());
    expect(output.join('\n'), isNot(contains('private-sentinel-719')));
    expect(output.join('\n'), isNot(contains('secret-body')));
  });

  test(
    'announced oversized literal is quota failure before payload reception',
    () async {
      final fixture = ImapFixture(messages: {1: _message()})
        ..oversizeLiteral = true;
      final result = await fixture.provider().fetchMessage(
        _identity(fixture),
        budget: const MailReadBudget(maxRawBytes: 1024),
        lease: _lease(fixture),
      );
      expect(_code(result), MailProblemCode.quotaExceeded);
      expect(fixture.clients.single.socket.closed, isTrue);
    },
  );

  test(
    'oversized greeting is a non-retryable quota failure before authentication',
    () async {
      final fixture = ImapFixture()..greeting = '* OK ${'X' * 512}\r\n';
      final result = await fixture
          .provider(
            limits: const MailTransportLimits(maxProtocolLineBytes: 128),
          )
          .capabilities(_lease(fixture));
      expect(_code(result), MailProblemCode.quotaExceeded);
      expect(
        (result as MailFailure<MailCapabilities>).problem.retryAfter,
        isNull,
      );
      expect(fixture.commands, isEmpty);
      expect(fixture.clients.single.socket.closed, isTrue);
    },
  );

  test(
    'protocol line budget remains quota failure even before login',
    () async {
      final fixture = ImapFixture()..longProtocolLine = true;
      final result = await fixture
          .provider(
            limits: const MailTransportLimits(maxProtocolLineBytes: 128),
          )
          .capabilities(_lease(fixture));
      expect(_code(result), MailProblemCode.quotaExceeded);
      expect(
        fixture.commands.any((command) => command.startsWith('LOGIN ')),
        isFalse,
      );
    },
  );

  test(
    'aggregate response bytes are bounded across authentication commands',
    () async {
      final fixture = ImapFixture();
      final result = await fixture
          .provider(limits: const MailTransportLimits(maxResponseBytes: 128))
          .capabilities(_lease(fixture));
      expect(_code(result), MailProblemCode.quotaExceeded);
      expect(fixture.clients.single.socket.closed, isTrue);
    },
  );

  test(
    'header literal limit fails the entire sync page without tombstones',
    () async {
      final fixture = ImapFixture(uidNext: 2, messages: {1: _message()});
      final result = await fixture
          .provider(limits: const MailTransportLimits(maxHeaderBytes: 64))
          .pullChanges(fixture.mailbox, limit: 1, lease: _lease(fixture));
      expect(_code(result), MailProblemCode.quotaExceeded);
    },
  );

  test(
    'dropped connection fails and the next operation uses a fresh authenticated client',
    () async {
      final fixture = ImapFixture(messages: {1: _message()})..dropFetch = true;
      final provider = fixture.provider();
      expect(
        await provider.fetchMessage(
          _identity(fixture),
          budget: const MailReadBudget(),
          lease: _lease(fixture),
        ),
        isA<MailFailure<MailMessage>>(),
      );
      fixture.dropFetch = false;
      expect(
        await provider.fetchMessage(
          _identity(fixture),
          budget: const MailReadBudget(),
          lease: _lease(fixture),
        ),
        isA<MailSuccess<MailMessage>>(),
      );
      expect(fixture.credentials.loads, 2);
      expect(fixture.clients, hasLength(2));
    },
  );

  test(
    'timeout destroys the connection and rejects a delayed completion',
    () async {
      final fixture = ImapFixture(messages: {1: _message()});
      final gate = Completer<void>();
      fixture.beforeReply = (command) async {
        if (command.startsWith('UID FETCH ')) await gate.future;
      };
      final provider = fixture.provider(
        limits: const MailTransportLimits(
          operationTimeout: Duration(milliseconds: 100),
        ),
      );
      final result = await provider.fetchMessage(
        _identity(fixture),
        budget: const MailReadBudget(),
        lease: _lease(fixture),
      );
      expect(result, isA<MailFailure<MailMessage>>());
      expect(fixture.clients.single.socket.closed, isTrue);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fixture.clients.single.socket.closed, isTrue);
    },
  );

  test(
    'vault completion after cancellation cannot open a connection',
    () async {
      final fixture = ImapFixture();
      final gate = Completer<void>();
      fixture.credentials.beforeLoad = () => gate.future;
      final cancellation = MailCancellationSource();
      final session = MailAccountSession(fixture.account);
      final pending = fixture.provider().capabilities(
        session.begin(cancellation: cancellation.token),
      );
      cancellation.cancel();
      expect(_code(await pending), MailProblemCode.cancelled);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fixture.commands, isEmpty);
      expect(fixture.clients.single.isConnected, isFalse);
    },
  );

  test(
    'STORE proves requested UID flags with a fresh observation; delete never expunges',
    () async {
      final fixture = ImapFixture(messages: {1: _message()});
      final provider = fixture.provider();
      expect(
        await provider.apply(
          MailSetRead(id: 'read-1', message: _identity(fixture), read: true),
          _lease(fixture),
        ),
        isA<MailSuccess<MailUnit>>(),
      );
      expect(
        await provider.apply(
          MailSetFlagged(
            id: 'flag-1',
            message: _identity(fixture),
            flagged: true,
          ),
          _lease(fixture),
        ),
        isA<MailSuccess<MailUnit>>(),
      );
      expect(
        await provider.apply(
          MailDelete(id: 'delete-1', message: _identity(fixture)),
          _lease(fixture),
        ),
        isA<MailSuccess<MailUnit>>(),
      );
      expect(
        fixture.messages[1]!.flags,
        containsAll([r'\Seen', r'\Flagged', r'\Deleted']),
      );
      expect(
        fixture.commands.any(
          (command) => command.contains('EXPUNGE') || command == 'CLOSE',
        ),
        isFalse,
      );
    },
  );

  test(
    'acknowledged STORE without changed flags requires reconciliation',
    () async {
      final fixture = ImapFixture(messages: {1: _message()})
        ..acknowledgeWithoutChange = true;
      final result = await fixture.provider().apply(
        MailSetRead(id: 'read', message: _identity(fixture), read: true),
        _lease(fixture),
      );
      expect(_code(result), MailProblemCode.conflict);
    },
  );

  test(
    'connection drop after remote mutation is conflict, never retryable success',
    () async {
      final fixture = ImapFixture(messages: {1: _message()})
        ..closeAfterMutation = true;
      final result = await fixture.provider().apply(
        MailSetRead(id: 'read', message: _identity(fixture), read: true),
        _lease(fixture),
      );
      expect(_code(result), MailProblemCode.conflict);
      expect((result as MailFailure<MailUnit>).problem.retryAfter, isNull);
      expect(
        fixture.commands.where((command) => command.startsWith('UID STORE ')),
        hasLength(1),
      );
    },
  );

  test(
    'MOVE requires capability and verifies source absence without global EXPUNGE',
    () async {
      final fixture = ImapFixture(
        messages: {1: _message()},
        supportsMove: false,
      );
      final provider = fixture.provider();
      final move = MailMove(
        id: 'move',
        message: _identity(fixture),
        destination: MailMailboxId('Archive', account: fixture.account),
      );
      expect(
        _code(await provider.apply(move, _lease(fixture))),
        MailProblemCode.unsupported,
      );
      expect(
        fixture.commands.any((command) => command.startsWith('UID MOVE ')),
        isFalse,
      );
      fixture.supportsMove = true;
      expect(
        await provider.apply(move, _lease(fixture)),
        isA<MailSuccess<MailUnit>>(),
      );
      expect(fixture.messages.containsKey(1), isFalse);
      expect(
        fixture.commands.any((command) => command.contains('EXPUNGE')),
        isFalse,
      );
    },
  );

  test(
    'OAuthBearer GS2 identity uses a= and secrets stay inside auth command',
    () async {
      final fixture = ImapFixture();
      expect(
        await fixture
            .provider(authentication: MailImapAuthentication.oauthBearer)
            .capabilities(_lease(fixture)),
        isA<MailSuccess<MailCapabilities>>(),
      );
      final command = fixture.commands.singleWhere(
        (command) => command.startsWith('AUTHENTICATE '),
      );
      final decoded = utf8.decode(base64.decode(command.split(' ').last));
      expect(decoded, startsWith('n,a=reader@example.test,\u0001'));
      expect(
        decoded,
        contains('auth=Bearer fixture-only-password\u0001\u0001'),
      );
    },
  );
  test(
    'OAuthBearer error challenge is drained once and returns authenticationRequired',
    () async {
      final fixture = ImapFixture()..challengeAuth = true;
      final result = await fixture
          .provider(authentication: MailImapAuthentication.oauthBearer)
          .capabilities(_lease(fixture));
      expect(_code(result), MailProblemCode.authenticationRequired);
      expect(
        fixture.commands.where(
          (command) => command.startsWith('AUTHENTICATE '),
        ),
        hasLength(1),
      );
      expect(fixture.commands.last, 'AQ==');
      expect(fixture.clients.single.socket.closed, isTrue);
    },
  );

  test(
    'token auth without SASL-IR is explicitly unsupported before sending a token',
    () async {
      final fixture = ImapFixture()..supportsSaslIr = false;
      final result = await fixture
          .provider(authentication: MailImapAuthentication.xoauth2)
          .capabilities(_lease(fixture));
      expect(_code(result), MailProblemCode.unsupported);
      expect(
        fixture.commands.any((command) => command.startsWith('AUTHENTICATE ')),
        isFalse,
      );
    },
  );
}
