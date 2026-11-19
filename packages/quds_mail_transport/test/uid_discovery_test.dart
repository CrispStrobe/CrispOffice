@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_transport/src/cursor.dart';
import 'package:test/test.dart';

import 'support/imap_fixture.dart';

FixtureMessage _message() => FixtureMessage(
  raw: fixtureBytes('Subject: Discovery fixture\r\n\r\nBody\r\n'),
);

MailOperationLease _lease(ImapFixture fixture) =>
    MailAccountSession(fixture.account).begin();

Future<MailResult<MailSyncPage>> _pull(
  ImapFixture fixture, {
  MailProvider? provider,
  MailCursor? cursor,
  int limit = 2,
}) => (provider ?? fixture.provider()).pullChanges(
  fixture.mailbox,
  cursor: cursor,
  limit: limit,
  lease: _lease(fixture),
);

MailSyncPage _page(MailResult<MailSyncPage> result) =>
    (result as MailSuccess<MailSyncPage>).value;

MailProblemCode _code(MailResult<MailSyncPage> result) =>
    (result as MailFailure<MailSyncPage>).problem.code;

List<int> _uids(MailSyncPage page) =>
    page.upserts
        .map((record) => (record.remote as MailImapIdentity).uid)
        .toList()
      ..sort();

Iterable<String> _fetches(ImapFixture fixture) =>
    fixture.commands.where((command) => command.startsWith('UID FETCH '));

void main() {
  test(
    'sparse unordered discovery pages near the 32-bit UID ceiling',
    () async {
      final fixture = ImapFixture(
        uidNext: 0xffffffff,
        messages: {0xfffffffe: _message(), 1000000: _message(), 42: _message()},
      );
      final provider = fixture.provider();
      final first = _page(await _pull(fixture, provider: provider));
      expect(_uids(first), [42, 1000000]);
      expect(first.hasMore, isTrue);
      expect(first.tombstones, isEmpty);
      expect(first.imapRange!.firstUid, 1);
      expect(first.imapRange!.lastUid, 1000000);
      final second = _page(
        await _pull(fixture, provider: provider, cursor: first.next),
      );
      expect(_uids(second), [0xfffffffe]);
      expect(second.hasMore, isFalse);
      expect(second.imapRange!.firstUid, 1000001);
      expect(second.imapRange!.lastUid, 0xfffffffe);
      expect(second.tombstones, isEmpty);
      expect(_fetches(fixture), hasLength(2));
      expect(fixture.commands, contains('UID SEARCH UID 1:4294967294'));
      expect(fixture.commands, contains('UID SEARCH UID 1000001:4294967294'));
    },
  );

  test(
    'page size counts existing messages rather than numeric holes',
    () async {
      final fixture = ImapFixture(
        uidNext: 9000001,
        messages: {500000: _message(), 9000000: _message()},
      );
      final first = _page(await _pull(fixture, limit: 1));
      final second = _page(await _pull(fixture, cursor: first.next, limit: 1));
      expect(_uids(first), [500000]);
      expect(_uids(second), [9000000]);
      expect(first.hasMore, isTrue);
      expect(second.hasMore, isFalse);
      expect(first.imapRange!.lastUid, 500000);
      expect(second.imapRange!.firstUid, 500001);
      expect(first.tombstones, isEmpty);
      expect(second.tombstones, isEmpty);
    },
  );

  test(
    'an empty remaining search confirms its whole range without FETCH',
    () async {
      final fixture = ImapFixture(uidNext: 9000001);
      final page = _page(await _pull(fixture));
      expect(page.upserts, isEmpty);
      expect(page.tombstones, isEmpty);
      expect(page.imapRange!.firstUid, 1);
      expect(page.imapRange!.lastUid, 9000000);
      expect(page.hasMore, isFalse);
      expect(_fetches(fixture), isEmpty);
      expect(fixture.commands, contains('UID SEARCH UID 1:9000000'));
    },
  );

  test(
    'a never-populated mailbox has no invalid zero-UID search range',
    () async {
      final fixture = ImapFixture(uidNext: 1);
      final page = _page(await _pull(fixture));
      expect(page.upserts, isEmpty);
      expect(page.imapRange, isNull);
      expect(page.hasMore, isFalse);
      expect(
        fixture.commands.any((command) => command.startsWith('UID ')),
        isFalse,
      );
    },
  );

  test('new arrivals beyond the frozen ceiling enter the next sweep', () async {
    final fixture = ImapFixture(
      uidNext: 3000001,
      messages: {1000000: _message(), 3000000: _message()},
    );
    final first = _page(await _pull(fixture, limit: 1));
    fixture.uidNext = 4000001;
    fixture.messages[4000000] = _message();
    final second = _page(await _pull(fixture, cursor: first.next, limit: 1));
    expect(_uids(second), [3000000]);
    expect(second.hasMore, isFalse);
    expect(second.imapRange!.lastUid, 3000000);
    final refreshed = _page(
      await _pull(fixture, cursor: second.next, limit: 3),
    );
    expect(_uids(refreshed), [1000000, 3000000, 4000000]);
    expect(refreshed.hasMore, isFalse);
  });

  for (final format in ['quds-imap-window-v1', 'quds-imap-discovery-v2']) {
    test('saved $format cursors resume with a new revision', () async {
      final fixture = ImapFixture(
        uidNext: 3000001,
        messages: {1: _message(), 2000000: _message()},
      );
      final legacy = MailCursor(
        mailbox: fixture.mailbox,
        value: jsonEncode([
          format,
          mailboxScope(fixture.mailbox),
          fixture.uidValidity,
          2,
          3000000,
        ]),
      );
      final page = _page(await _pull(fixture, cursor: legacy));
      expect(_uids(page), [2000000]);
      expect(page.imapRange!.firstUid, 2);
      expect(page.imapRange!.lastUid, 3000000);
      final next = ImapScanCursor.decode(page.next, fixture.mailbox)!;
      expect(jsonDecode(page.next.value)[0], 'quds-imap-discovery-v3');
      expect(next.revision, 1);
      expect(page.resetRequired, isFalse);
    });
  }

  test(
    'page revisions advance through completed, empty and reset sweeps',
    () async {
      final fixture = ImapFixture(
        uidNext: 3,
        messages: {1: _message(), 2: _message()},
      );
      final first = _page(await _pull(fixture, limit: 1));
      final complete = _page(
        await _pull(fixture, cursor: first.next, limit: 1),
      );
      fixture.messages.clear();
      final empty = _page(await _pull(fixture, cursor: complete.next));
      fixture.uidValidity++;
      fixture.uidNext = 1;
      final reset = _page(await _pull(fixture, cursor: empty.next));
      final stillEmpty = _page(await _pull(fixture, cursor: reset.next));
      final pages = [first, complete, empty, reset, stillEmpty];
      expect(
        pages.map(
          (page) => ImapScanCursor.decode(page.next, fixture.mailbox)!.revision,
        ),
        [1, 2, 3, 4, 5],
      );
      expect(
        pages.map((page) => page.next.value).toSet(),
        hasLength(pages.length),
      );
      expect(first.hasMore, isTrue);
      expect(complete.hasMore, isFalse);
      expect(empty.imapRange, isNotNull);
      expect(reset.resetRequired, isTrue);
      expect(reset.imapRange, isNull);
      expect(stillEmpty.resetRequired, isFalse);
      expect(stillEmpty.imapRange, isNull);
    },
  );

  test(
    'revision exhaustion fails before protocol work without wrapping',
    () async {
      final fixture = ImapFixture(uidNext: 1);
      final penultimate = ImapScanCursor(
        uidValidity: fixture.uidValidity,
        nextUid: 1,
        ceiling: 0,
        revision: ImapScanCursor.maxRevision - 1,
      ).encode(fixture.mailbox);
      final last = _page(await _pull(fixture, cursor: penultimate));
      expect(
        ImapScanCursor.decode(last.next, fixture.mailbox)!.revision,
        ImapScanCursor.maxRevision,
      );
      expect(last.next.value, isNot(penultimate.value));
      fixture.commands.clear();
      expect(
        _code(await _pull(fixture, cursor: last.next)),
        MailProblemCode.invalidInput,
      );
      expect(fixture.commands, isEmpty);
    },
  );

  test('UIDVALIDITY rollover discards an old high-UID continuation', () async {
    final fixture = ImapFixture(
      uidNext: 2000001,
      messages: {1000000: _message(), 2000000: _message()},
    );
    final first = _page(await _pull(fixture, limit: 1));
    fixture.uidValidity++;
    fixture.uidNext = 2;
    fixture.messages
      ..clear()
      ..[1] = _message();
    final page = _page(await _pull(fixture, cursor: first.next));
    expect(page.resetRequired, isTrue);
    expect(_uids(page), [1]);
    expect(page.imapRange!.uidValidity, fixture.uidValidity);
    expect(page.imapRange!.firstUid, 1);
    expect(page.imapRange!.lastUid, 1);
  });

  test(
    'a backwards UIDNEXT cannot authorize deletion of a saved range',
    () async {
      final fixture = ImapFixture(
        uidNext: 2000001,
        messages: {1000000: _message(), 2000000: _message()},
      );
      final first = _page(await _pull(fixture, limit: 1));
      fixture.uidNext = 1000001;
      fixture.commands.clear();
      expect(
        _code(await _pull(fixture, cursor: first.next)),
        MailProblemCode.providerFailure,
      );
      expect(
        fixture.commands.any((command) => command.startsWith('UID ')),
        isFalse,
      );
    },
  );

  test(
    'a discovered message expunged before FETCH is absent in its range',
    () async {
      final fixture = ImapFixture(
        uidNext: 9000001,
        messages: {1000000: _message(), 9000000: _message()},
      );
      fixture.beforeReply = (command) async {
        if (command.startsWith('UID FETCH ')) fixture.messages.remove(1000000);
      };
      final page = _page(await _pull(fixture));
      expect(_uids(page), [9000000]);
      expect(page.imapRange!.firstUid, 1);
      expect(page.imapRange!.lastUid, 9000000);
      expect(page.tombstones, isEmpty);
      expect(page.hasMore, isFalse);
    },
  );

  test(
    'an in-range FETCH UID absent from discovery rejects the whole page',
    () async {
      final fixture = ImapFixture(
        uidNext: 4,
        messages: {1: _message(), 2: _message()},
      )..searchResponses = ['* SEARCH 1'];
      expect(_code(await _pull(fixture)), MailProblemCode.providerFailure);
      expect(fixture.clients.single.socket.closed, isTrue);
    },
  );

  for (final entry in <String, List<String>>{
    'missing': [],
    'repeated': ['* SEARCH 1', '* SEARCH 1'],
    'duplicate UID': ['* SEARCH 1 1'],
    'zero UID': ['* SEARCH 0'],
    'overflow UID': ['* SEARCH 4294967296'],
    'out-of-range UID': ['* SEARCH 3'],
    'malformed suffix': ['* SEARCH 1 garbage'],
    'unrequested ESEARCH': ['* ESEARCH UID ALL 1'],
  }.entries) {
    test('${entry.key} discovery cannot authorize a page or FETCH', () async {
      final fixture = ImapFixture(uidNext: 2, messages: {1: _message()})
        ..searchResponses = entry.value;
      expect(_code(await _pull(fixture)), MailProblemCode.providerFailure);
      expect(_fetches(fixture), isEmpty);
      expect(fixture.clients.single.socket.closed, isTrue);
    });
  }

  test(
    'SEARCH status prose and mixed-case data preserve valid discovery',
    () async {
      final fixture = ImapFixture(uidNext: 2, messages: {1: _message()})
        ..searchResponses = [
          '* OK [ALERT] SEARCH index refreshed',
          '* sEaRcH 1',
          '* NO SEARCH diagnostic only',
        ];
      expect(_uids(_page(await _pull(fixture))), [1]);
    },
  );

  test('a tagged SEARCH failure cannot commit a valid result prefix', () async {
    final fixture = ImapFixture(uidNext: 2, messages: {1: _message()})
      ..searchStatus = 'NO';
    expect(_code(await _pull(fixture)), MailProblemCode.providerFailure);
    expect(_fetches(fixture), isEmpty);
  });

  test(
    'discovery count limits fail atomically and release the provider',
    () async {
      final fixture = ImapFixture(
        uidNext: 1000001,
        messages: {1: _message(), 2: _message(), 1000000: _message()},
      );
      final provider = fixture.provider(
        limits: const MailTransportLimits(maxDiscoveredUids: 2),
      );
      expect(
        _code(await _pull(fixture, provider: provider)),
        MailProblemCode.quotaExceeded,
      );
      expect(_fetches(fixture), isEmpty);
      expect(fixture.clients.single.socket.closed, isTrue);
      fixture.messages.remove(2);
      expect(_uids(_page(await _pull(fixture, provider: provider))), [
        1,
        1000000,
      ]);
    },
  );

  test(
    'discovery obeys the protocol line budget before parsing a prefix',
    () async {
      final fixture = ImapFixture(uidNext: 2, messages: {1: _message()})
        ..searchResponses = ['* SEARCH${' 1' * 300}'];
      expect(
        _code(
          await _pull(
            fixture,
            provider: fixture.provider(
              limits: const MailTransportLimits(maxProtocolLineBytes: 512),
            ),
          ),
        ),
        MailProblemCode.quotaExceeded,
      );
      expect(_fetches(fixture), isEmpty);
    },
  );

  test('an explicit legacy numeric ceiling retains its old meaning', () async {
    expect(const MailTransportLimits().maxUidScan, isNull);
    expect(const MailTransportLimits().maxDiscoveredUids, 10000);
    final fixture = ImapFixture(
      uidNext: 1000001,
      messages: {1000000: _message()},
    );
    expect(
      _code(
        await _pull(
          fixture,
          provider: fixture.provider(
            limits: const MailTransportLimits(maxUidScan: 10000),
          ),
        ),
      ),
      MailProblemCode.unsupported,
    );
    expect(
      fixture.commands.any((command) => command.startsWith('UID ')),
      isFalse,
    );
  });

  test(
    'cancelling stalled SEARCH prevents FETCH and allows a fresh operation',
    () async {
      final fixture = ImapFixture(uidNext: 2, messages: {1: _message()});
      final arrived = Completer<void>();
      final release = Completer<void>();
      fixture.beforeReply = (command) async {
        if (command.startsWith('UID SEARCH ')) {
          arrived.complete();
          await release.future;
        }
      };
      final cancellation = MailCancellationSource();
      final provider = fixture.provider();
      final pending = provider.pullChanges(
        fixture.mailbox,
        limit: 1,
        lease: MailAccountSession(
          fixture.account,
        ).begin(cancellation: cancellation.token),
      );
      try {
        await arrived.future.timeout(const Duration(seconds: 2));
        cancellation.cancel();
        expect(
          _code(await pending.timeout(const Duration(seconds: 2))),
          MailProblemCode.cancelled,
        );
        expect(_fetches(fixture), isEmpty);
        expect(fixture.clients.single.socket.closed, isTrue);
      } finally {
        release.complete();
        fixture.beforeReply = null;
      }
      expect(_uids(_page(await _pull(fixture, provider: provider))), [1]);
    },
  );
}
