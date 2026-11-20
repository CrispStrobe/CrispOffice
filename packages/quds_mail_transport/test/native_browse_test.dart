@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_transport/src/cursor.dart';
import 'package:test/test.dart';

import 'support/imap_fixture.dart';

FixtureMessage _message({List<String>? flags = const []}) => FixtureMessage(
  raw: fixtureBytes('Subject: Newest fixture\r\n\r\nBody\r\n'),
  flags: flags,
);

Future<MailResult<MailHeaderPage>> _browse(
  ImapFixture fixture, {
  MailImapHeaderBrowser? browser,
  MailCursor? cursor,
  int? uidValidity,
  int limit = 2,
  MailOperationLease? lease,
}) => (browser ?? fixture.provider()).fetchNewestHeaders(
  fixture.mailbox,
  uidValidity: uidValidity ?? fixture.uidValidity,
  cursor: cursor,
  limit: limit,
  lease: lease ?? MailAccountSession(fixture.account).begin(),
);

MailHeaderPage _page(MailResult<MailHeaderPage> result) =>
    (result as MailSuccess<MailHeaderPage>).value;

MailProblemCode _code(MailResult<MailHeaderPage> result) =>
    (result as MailFailure<MailHeaderPage>).problem.code;

List<int> _uids(MailHeaderPage page) => [
  for (final record in page.messages) (record.remote as MailImapIdentity).uid,
];

void main() {
  test('newest pages descend by UID across sparse high ranges', () async {
    final fixture = ImapFixture(
      uidNext: 0xffffffff,
      messages: {
        5: _message(),
        0xfffffffe: _message(flags: [r'\Seen', r'\Flagged']),
        1000000: _message(flags: null),
      },
    );
    final browser = fixture.provider();
    final first = _page(await _browse(fixture, browser: browser));
    expect(_uids(first), [0xfffffffe, 1000000]);
    expect(
      first.messages.first.flags,
      const MailMessageFlags(isRead: true, isFlagged: true),
    );
    expect(first.messages.last.flags, isNull);
    final cursor = ImapBrowseCursor.decode(first.next, fixture.mailbox)!;
    expect(cursor.initialCeiling, 0xfffffffe);
    expect(cursor.nextCeiling, 999999);
    final second = _page(
      await _browse(fixture, browser: browser, cursor: first.next),
    );
    expect(_uids(second), [5]);
    expect(second.next, isNull);
    expect(fixture.commands, contains('UID SEARCH UID 1:4294967294'));
    expect(fixture.commands, contains('UID SEARCH UID 1:999999'));
    expect(
      fixture.commands.where((command) => command.startsWith('UID FETCH ')),
      everyElement(contains('BODY.PEEK[HEADER.FIELDS')),
    );
    expect(
      fixture.commands.any((command) => command.startsWith('UID STORE ')),
      isFalse,
    );
  });

  test('later arrivals remain outside continuation until refresh', () async {
    final fixture = ImapFixture(
      uidNext: 3000001,
      messages: {1: _message(), 3000000: _message()},
    );
    final first = _page(await _browse(fixture, limit: 1));
    fixture.uidNext = 4000001;
    fixture.messages[4000000] = _message();
    final second = _page(await _browse(fixture, cursor: first.next, limit: 1));
    expect(_uids(first), [3000000]);
    expect(_uids(second), [1]);
    expect(second.next, isNull);
    expect(_uids(_page(await _browse(fixture, limit: 1))), [4000000]);
  });

  test('a never-populated mailbox has no zero UID search', () async {
    final fixture = ImapFixture(uidNext: 1);
    final page = _page(await _browse(fixture));
    expect(page.messages, isEmpty);
    expect(page.next, isNull);
    expect(
      fixture.commands.any((command) => command.startsWith('UID ')),
      isFalse,
    );
  });

  test('empty first page still requires the selected UIDVALIDITY', () async {
    final fixture = ImapFixture(uidNext: 1);
    expect(
      _code(await _browse(fixture, uidValidity: fixture.uidValidity + 1)),
      MailProblemCode.conflict,
    );
    expect(
      fixture.commands.any((command) => command.startsWith('UID ')),
      isFalse,
    );
  });

  test(
    'generation rollover never mixes continuation with a fresh mailbox',
    () async {
      final fixture = ImapFixture(
        uidNext: 9,
        messages: {1: _message(), 8: _message()},
      );
      final validity = fixture.uidValidity;
      final first = _page(await _browse(fixture, limit: 1));
      fixture.uidValidity++;
      fixture.uidNext = 1;
      fixture.messages.clear();
      fixture.commands.clear();
      expect(
        _code(
          await _browse(fixture, cursor: first.next, uidValidity: validity),
        ),
        MailProblemCode.conflict,
      );
      expect(
        fixture.commands.any((command) => command.startsWith('UID ')),
        isFalse,
      );
      fixture.commands.clear();
      expect(
        _code(await _browse(fixture, cursor: first.next)),
        MailProblemCode.conflict,
      );
      expect(fixture.commands, isEmpty);
    },
  );

  test('backwards UIDNEXT rejects the fixed initial ceiling', () async {
    final fixture = ImapFixture(
      uidNext: 9,
      messages: {1: _message(), 8: _message()},
    );
    final first = _page(await _browse(fixture, limit: 1));
    fixture.uidNext = 8;
    fixture.commands.clear();
    expect(
      _code(await _browse(fixture, cursor: first.next)),
      MailProblemCode.providerFailure,
    );
    expect(
      fixture.commands.any((command) => command.startsWith('UID ')),
      isFalse,
    );
  });

  test(
    'a completely expunged fetched range still advances to older UIDs',
    () async {
      final fixture = ImapFixture(
        uidNext: 9000001,
        messages: {1: _message(), 1000000: _message(), 9000000: _message()},
      );
      fixture.beforeReply = (command) async {
        if (command.startsWith('UID FETCH ')) {
          fixture.messages.remove(9000000);
          fixture.messages.remove(1000000);
        }
      };
      final first = _page(await _browse(fixture));
      expect(first.messages, isEmpty);
      expect(
        ImapBrowseCursor.decode(first.next, fixture.mailbox)!.nextCeiling,
        999999,
      );
      final second = _page(await _browse(fixture, cursor: first.next));
      expect(_uids(second), [1]);
      expect(second.next, isNull);
    },
  );

  test(
    'empty bounded windows retain older ranges without another FETCH',
    () async {
      final fixture = ImapFixture(uidNext: 9000001);
      final page = _page(await _browse(fixture));
      expect(page.messages, isEmpty);
      expect(
        ImapBrowseCursor.decode(page.next, fixture.mailbox)!.nextCeiling,
        8991812,
      );
      expect(
        fixture.commands.where((command) => command.startsWith('UID SEARCH ')),
        hasLength(1),
      );
      final last = _page(
        await _browse(
          fixture,
          cursor: ImapBrowseCursor(
            uidValidity: fixture.uidValidity,
            initialCeiling: 9000000,
            nextCeiling: 20,
          ).encode(fixture.mailbox),
        ),
      );
      expect(last.messages, isEmpty);
      expect(last.next, isNull);
      expect(
        fixture.commands.where((command) => command.startsWith('UID FETCH ')),
        isEmpty,
      );
    },
  );

  test(
    'ascending archive and durable sync remain separate from browsing',
    () async {
      final fixture = ImapFixture(
        uidNext: 9,
        messages: {8: _message(), 1: _message()},
      );
      final provider = fixture.provider();
      final ascending = _page(
        await provider.fetchHeaders(
          fixture.mailbox,
          limit: 1,
          lease: MailAccountSession(fixture.account).begin(),
        ),
      );
      final descending = _page(
        await _browse(fixture, browser: provider, limit: 1),
      );
      expect(_uids(ascending), [1]);
      expect(_uids(descending), [8]);
      expect(
        _code(await _browse(fixture, cursor: ascending.next)),
        MailProblemCode.invalidInput,
      );
      final sync = await provider.pullChanges(
        fixture.mailbox,
        cursor: descending.next,
        limit: 1,
        lease: MailAccountSession(fixture.account).begin(),
      );
      expect(
        (sync as MailFailure<MailSyncPage>).problem.code,
        MailProblemCode.invalidInput,
      );
    },
  );

  test('invalid bounds fail before credentials or network', () async {
    final fixture = ImapFixture();
    for (final limit in [0, -1, 501]) {
      expect(
        _code(await _browse(fixture, limit: limit)),
        MailProblemCode.invalidInput,
      );
    }
    for (final validity in [0, -1, 0x100000000]) {
      expect(
        _code(await _browse(fixture, uidValidity: validity)),
        MailProblemCode.invalidInput,
      );
    }
    expect(fixture.credentials.loads, 0);
    expect(fixture.clients, isEmpty);
  });

  test(
    'foreign and malformed cursor positions fail before networking',
    () async {
      final fixture = ImapFixture();
      final foreign = MailMailboxId('Other', account: fixture.account);
      final valid = ImapBrowseCursor(
        uidValidity: fixture.uidValidity,
        initialCeiling: 3,
        nextCeiling: 2,
      ).encode(fixture.mailbox);
      final cursors = [
        MailCursor(mailbox: foreign, value: valid.value),
        MailCursor(mailbox: fixture.mailbox, value: 'not-json'),
        MailCursor(mailbox: fixture.mailbox, value: 'x' * 257),
        for (final next in [0, 3, 4])
          MailCursor(
            mailbox: fixture.mailbox,
            value: jsonEncode([
              'quds-imap-browse-v1',
              mailboxScope(fixture.mailbox),
              fixture.uidValidity,
              3,
              next,
            ]),
          ),
      ];
      for (final cursor in cursors) {
        expect(
          _code(await _browse(fixture, cursor: cursor)),
          MailProblemCode.invalidInput,
        );
      }
      expect(fixture.clients, isEmpty);
    },
  );

  test(
    'dense mailboxes page through a small discovery budget without truncation',
    () async {
      final fixture = ImapFixture(
        uidNext: 5,
        messages: {1: _message(), 2: _message(), 3: _message()},
      );
      final browser = fixture.provider(
        limits: const MailTransportLimits(maxDiscoveredUids: 2),
      );
      final first = _page(await _browse(fixture, browser: browser, limit: 1));
      final second = _page(
        await _browse(fixture, browser: browser, cursor: first.next, limit: 1),
      );
      final third = _page(
        await _browse(fixture, browser: browser, cursor: second.next, limit: 1),
      );
      expect(_uids(first), [3]);
      expect(_uids(second), [2]);
      expect(_uids(third), [1]);
      expect(third.next, isNull);
      expect(
        fixture.commands.where((command) => command.startsWith('UID SEARCH ')),
        ['UID SEARCH UID 3:4', 'UID SEARCH UID 1:2', 'UID SEARCH UID 1:1'],
      );
    },
  );

  test(
    'the default first fifty remain available with 10001 actual messages',
    () async {
      final message = _message();
      final fixture = ImapFixture(
        uidNext: 10002,
        messages: {for (var uid = 1; uid <= 10001; uid++) uid: message},
      );
      final first = _page(await _browse(fixture, limit: 50));
      expect(_uids(first), List.generate(50, (index) => 10001 - index));
      expect(fixture.commands, contains('UID SEARCH UID 2:10001'));
      expect(
        fixture.commands.where((command) => command.startsWith('UID SEARCH ')),
        hasLength(1),
      );
      expect(
        fixture.commands.where((command) => command.startsWith('UID FETCH ')),
        hasLength(1),
      );
      final second = _page(
        await _browse(fixture, cursor: first.next, limit: 50),
      );
      expect(_uids(second), List.generate(50, (index) => 9951 - index));
    },
  );

  test(
    '8000 high UIDs use a tail window below the 64KiB line budget',
    () async {
      const ceiling = 0xfffffffe;
      final message = _message();
      final fixture = ImapFixture(
        uidNext: ceiling + 1,
        messages: {
          for (var offset = 0; offset < 8000; offset++)
            ceiling - offset: message,
        },
      );
      final page = _page(await _browse(fixture, limit: 50));
      expect(_uids(page), List.generate(50, (index) => ceiling - index));
      const windowSize = (64 * 1024 - 32) ~/ 11;
      expect(
        fixture.commands,
        contains('UID SEARCH UID ${ceiling - windowSize + 1}:$ceiling'),
      );
      expect(
        fixture.commands.where((command) => command.startsWith('UID SEARCH ')),
        hasLength(1),
      );
    },
  );

  for (final kind in ['line', 'response']) {
    test(
      '$kind byte budget also bounds the small-count whole-range optimization',
      () async {
        const ceiling = 0xfffffffe;
        final fixture = ImapFixture(
          uidNext: ceiling + 1,
          messages: {
            for (var offset = 0; offset < (kind == 'line' ? 50 : 300); offset++)
              ceiling - offset: _message(),
          },
        );
        final browser = fixture.provider(
          limits: MailTransportLimits(
            maxProtocolLineBytes: kind == 'line' ? 512 : 64 * 1024,
            maxResponseBytes: kind == 'response' ? 4096 : 16 * 1024 * 1024,
          ),
        );
        final result = await _browse(fixture, browser: browser, limit: 1);
        expect(
          result,
          isA<MailSuccess<MailHeaderPage>>(),
          reason: fixture.commands
              .where((command) => command.startsWith('UID '))
              .join('; '),
        );
        final page = _page(result);
        expect(_uids(page), [ceiling]);
        final windowSize = kind == 'line'
            ? (512 - 32) ~/ 11
            : (4096 ~/ 2 - 64) ~/ 11;
        expect(
          fixture.commands,
          contains('UID SEARCH UID ${ceiling - windowSize + 1}:$ceiling'),
        );
      },
    );
  }

  test(
    'an inadequate aggregate budget fails during control traffic without an empty success',
    () async {
      final fixture = ImapFixture(
        uidNext: 3,
        messages: {1: _message(), 2: _message()},
      );
      final browser = fixture.provider(
        limits: const MailTransportLimits(maxResponseBytes: 512),
      );
      expect(
        _code(await _browse(fixture, browser: browser)),
        MailProblemCode.quotaExceeded,
      );
      expect(
        fixture.commands.where((command) => command.startsWith('UID ')),
        isEmpty,
      );
      expect(fixture.clients, hasLength(1));
    },
  );

  for (final count in [0, -1, 0x100000000, null]) {
    test(
      'unknown or invalid SELECT count $count uses a bounded tail',
      () async {
        final fixture =
            ImapFixture(
                uidNext: 11,
                messages: {1: _message(), 8: _message(), 9: _message()},
              )
              ..selectedMessageCount = count
              ..omitExists = count == null;
        final browser = fixture.provider(
          limits: const MailTransportLimits(maxDiscoveredUids: 2),
        );
        final page = _page(await _browse(fixture, browser: browser));
        expect(_uids(page), [9]);
        expect(fixture.commands, contains('UID SEARCH UID 9:10'));
        expect(
          ImapBrowseCursor.decode(page.next, fixture.mailbox)!.nextCeiling,
          8,
        );
      },
    );
  }

  test(
    'an inaccurate small count cannot bypass the strict discovery quota',
    () async {
      final fixture = ImapFixture(
        uidNext: 4,
        messages: {1: _message(), 2: _message(), 3: _message()},
      )..selectedMessageCount = 1;
      final browser = fixture.provider(
        limits: const MailTransportLimits(maxDiscoveredUids: 2),
      );
      expect(
        _code(await _browse(fixture, browser: browser, limit: 1)),
        MailProblemCode.quotaExceeded,
      );
      expect(
        fixture.commands.where((command) => command.startsWith('UID FETCH ')),
        isEmpty,
      );
      expect(fixture.clients, hasLength(1));
    },
  );

  test(
    'large sparse folders expose one empty window per explicit request',
    () async {
      final fixture = ImapFixture(
        uidNext: 101,
        messages: {1: _message(), 50: _message(), 100: _message()},
      );
      final browser = fixture.provider(
        limits: const MailTransportLimits(maxDiscoveredUids: 2),
      );
      final first = _page(await _browse(fixture, browser: browser));
      final second = _page(
        await _browse(fixture, browser: browser, cursor: first.next),
      );
      expect(_uids(first), [100]);
      expect(second.messages, isEmpty);
      expect(
        ImapBrowseCursor.decode(second.next, fixture.mailbox)!.nextCeiling,
        96,
      );
      expect(
        fixture.commands.where((command) => command.startsWith('UID SEARCH ')),
        ['UID SEARCH UID 99:100', 'UID SEARCH UID 97:98'],
      );
      expect(
        fixture.commands.where((command) => command.startsWith('UID FETCH ')),
        hasLength(1),
      );
    },
  );

  test('the explicit legacy numeric ceiling remains enforced', () async {
    final fixture = ImapFixture(uidNext: 9000001);
    final browser = fixture.provider(
      limits: const MailTransportLimits(maxUidScan: 1000),
    );
    expect(
      _code(await _browse(fixture, browser: browser)),
      MailProblemCode.unsupported,
    );
    expect(
      fixture.commands.any((command) => command.startsWith('UID ')),
      isFalse,
    );
  });

  for (final fault in ['duplicate', 'wrong-uid', 'undiscovered', 'oversize']) {
    test('$fault FETCH rejects the entire page without replay', () async {
      final fixture = ImapFixture(
        uidNext: 4,
        messages: {1: _message(), 2: _message()},
      );
      switch (fault) {
        case 'duplicate':
          fixture.duplicateFetch = true;
        case 'wrong-uid':
          fixture.wrongFetchedUid = true;
        case 'undiscovered':
          fixture.searchResponses = ['* SEARCH 1'];
        case 'oversize':
          fixture.oversizeLiteral = true;
      }
      expect(
        _code(await _browse(fixture)),
        fault == 'oversize'
            ? MailProblemCode.quotaExceeded
            : MailProblemCode.providerFailure,
      );
      expect(fixture.clients, hasLength(1));
      expect(fixture.clients.single.socket.closed, isTrue);
    });
  }

  test(
    'cancelling discovery closes the connection and ignores late completion',
    () async {
      final fixture = ImapFixture(
        uidNext: 3,
        messages: {1: _message(), 2: _message()},
      );
      final started = Completer<void>();
      final release = Completer<void>();
      fixture.beforeReply = (command) async {
        if (command.startsWith('UID SEARCH ')) {
          started.complete();
          await release.future;
        }
      };
      final source = MailCancellationSource();
      final browser = fixture.provider();
      final pending = _browse(
        fixture,
        browser: browser,
        lease: MailAccountSession(
          fixture.account,
        ).begin(cancellation: source.token),
      );
      await started.future;
      source.cancel();
      expect(_code(await pending), MailProblemCode.cancelled);
      expect(fixture.clients.single.socket.closed, isTrue);
      release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        fixture.commands.where((command) => command.startsWith('UID FETCH ')),
        isEmpty,
      );
      fixture.beforeReply = null;
      expect(_uids(_page(await _browse(fixture, browser: browser))), [2, 1]);
    },
  );
}
