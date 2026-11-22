import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_mailbox_session.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';

final _account = MailAccountId(
  'reader',
  profile: MailProfileId('profile', hostId: 'retained-session-test'),
);
final _inbox = MailMailboxId('inbox', account: _account);
final _archive = MailMailboxId('archive', account: _account);

MailHeaderRecord _header(
  MailMailboxId mailbox,
  int uid, {
  int validity = 7,
  String? localId,
  MailMessageFlags? flags = const MailMessageFlags(),
  MailProviderKind provider = MailProviderKind.imap,
}) => MailHeaderRecord(
  id: MailMessageId(localId ?? 'message-$uid'),
  remote: provider == MailProviderKind.imap
      ? MailImapIdentity(mailbox: mailbox, uidValidity: validity, uid: uid)
      : MailOpaqueIdentity(
          account: mailbox.account,
          provider: provider,
          value: '$uid',
        ),
  envelope: MailEnvelope(subject: 'Message $uid'),
  flags: flags,
);

MailMailboxSyncSnapshot _sync(
  MailMailboxId mailbox, {
  int revision = 1,
  int count = 1,
  int offset = 0,
  int limit = 100,
  bool partial = false,
  List<MailHeaderRecord>? headers,
  bool? hasMoreHeaders,
}) {
  final page =
      headers ??
      [
        for (var i = offset; i < count && i < offset + limit; i++)
          _header(mailbox, i + 1),
      ];
  return MailMailboxSyncSnapshot(
    summary: MailMailboxSyncSummary(
      mailbox: MailMailbox(id: mailbox, displayName: mailbox.value),
      revision: revision,
      updatedAt: DateTime.utc(2026, 11, 22),
      hasMore: partial,
      headerCount: count,
    ),
    headers: page,
    offset: offset,
    hasMoreHeaders: hasMoreHeaders ?? offset + page.length < count,
  );
}

MailCachedMailboxView _browse(MailMailboxId mailbox) => MailCachedMailboxView(
  mailbox: MailMailbox(id: mailbox, displayName: mailbox.value),
  revision: 1,
  capturedAt: DateTime.utc(2026, 11, 21),
  headers: [_header(mailbox, 9)],
  hasMore: true,
);

typedef _PageRequest = ({MailMailboxId mailbox, int limit, int offset});

final class _Store extends Fake
    implements
        StudioMailMailboxStore,
        StudioMailMailboxWatchStore,
        StudioMailSyncStore {
  @override
  MailAccountId get account => _account;

  final requests = <_PageRequest>[];
  final syncStreams =
      <StreamController<MailResult<MailMailboxSyncSnapshot?>>>[];
  final browseStreams =
      <StreamController<MailResult<MailCachedMailboxView?>>>[];
  Completer<void>? cancellationGate;
  int cancellations = 0;

  @override
  Stream<MailResult<MailMailboxSyncSnapshot?>> watchSyncMailbox(
    MailMailboxId mailbox, {
    int limit = 100,
    int offset = 0,
  }) {
    requests.add((mailbox: mailbox, limit: limit, offset: offset));
    final gate = cancellationGate;
    final controller = StreamController<MailResult<MailMailboxSyncSnapshot?>>(
      sync: true,
      onCancel: () async {
        cancellations++;
        await gate?.future;
      },
    );
    syncStreams.add(controller);
    return controller.stream;
  }

  @override
  Stream<MailResult<MailCachedMailboxView?>> watchView(MailMailboxId mailbox) {
    final gate = cancellationGate;
    final controller = StreamController<MailResult<MailCachedMailboxView?>>(
      sync: true,
      onCancel: () async {
        cancellations++;
        await gate?.future;
      },
    );
    browseStreams.add(controller);
    return controller.stream;
  }
}

final class _OneShotStore extends Fake implements StudioMailMailboxStore {
  @override
  MailAccountId get account => _account;
  final read = Completer<MailCachedMailboxView?>();
  int loads = 0;

  @override
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox) {
    loads++;
    return read.future;
  }
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  late _Store store;
  late StudioMailMailboxSession session;

  setUp(() {
    store = _Store();
    session = StudioMailMailboxSession(
      store: store,
      provider: MailProviderKind.imap,
    );
  });

  tearDown(() async {
    if (store.cancellationGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    await session.close();
    for (final stream in store.syncStreams) {
      await stream.close();
    }
    for (final stream in store.browseStreams) {
      await stream.close();
    }
  });

  Future<void> open(
    MailMailboxId mailbox,
    MailMailboxSyncSnapshot? view, {
    int offset = 0,
    int limit = 100,
  }) async {
    final opening = session.selectSynchronized(
      mailbox,
      offset: offset,
      limit: limit,
    );
    await _tick();
    store.syncStreams.last.add(MailSuccess(view));
    await opening;
  }

  test(
    'synchronized pages retain their own coverage and source identity',
    () async {
      final page = _sync(
        _inbox,
        count: 5,
        offset: 2,
        limit: 2,
        partial: true,
        headers: [_header(_inbox, 3, flags: null), _header(_inbox, 4)],
      );
      await open(_inbox, page, offset: 2, limit: 2);
      final snapshot = session.snapshot;
      expect(snapshot.phase, StudioMailMailboxPhase.ready);
      expect(snapshot.source, StudioMailMailboxSource.synchronized);
      expect(snapshot.view, isNull);
      expect(snapshot.synchronizedView, same(page));
      expect(snapshot.mailboxDetails, same(page.mailbox));
      expect(snapshot.headers.map((header) => header.id.value), [
        'message-3',
        'message-4',
      ]);
      expect(snapshot.offset, 2);
      expect(snapshot.pageSize, 2);
      expect(snapshot.headerCount, 5);
      expect(snapshot.nextOffset, 4);
      expect(snapshot.hasMore, isTrue);
      expect(snapshot.unreadCount, 1);
      expect(snapshot.unknownReadCount, 1);
      expect(snapshot.capturedAt, DateTime.utc(2026, 11, 22));
      expect(store.browseStreams, isEmpty);

      await open(
        _inbox,
        _sync(_inbox, count: 5, offset: 4, limit: 2),
        offset: 4,
        limit: 2,
      );
      expect(session.snapshot.headers.single.id.value, 'message-5');
      expect(session.snapshot.nextOffset, isNull);
      expect(session.snapshot.hasMore, isFalse);
    },
  );

  test(
    'same revision flag changes remain observable without changing page',
    () async {
      await open(_inbox, _sync(_inbox, count: 2));
      store.syncStreams.single.add(
        MailSuccess(
          _sync(
            _inbox,
            count: 2,
            headers: [
              _header(_inbox, 1, flags: const MailMessageFlags(isRead: true)),
              _header(_inbox, 2, flags: null),
            ],
          ),
        ),
      );
      expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
      expect(session.snapshot.unreadCount, 0);
      expect(session.snapshot.unknownReadCount, 1);
    },
  );

  test(
    'switching sources and A-B-A ignores retired and queued callbacks',
    () async {
      final delivered = <StudioMailMailboxSnapshot>[];
      final listening = session.changes.listen(delivered.add);
      final browsing = session.select(_inbox);
      await _tick();
      store.browseStreams.single.add(MailSuccess(_browse(_inbox)));
      final syncing = session.selectSynchronized(_inbox);
      await browsing;
      await _tick();
      expect(delivered.where((value) => value.view != null), isEmpty);
      store.syncStreams.last.add(MailSuccess(_sync(_inbox, revision: 9)));
      await syncing;
      final switching = session.selectSynchronized(_archive);
      store.syncStreams.first.add(MailSuccess(_sync(_inbox, revision: 10)));
      expect(session.snapshot.headers, isEmpty);
      await _tick();
      store.syncStreams.last.add(MailSuccess(_sync(_archive)));
      await switching;
      await open(_inbox, _sync(_inbox, revision: 11));
      expect(store.requests.map((request) => request.mailbox), [
        _inbox,
        _archive,
        _inbox,
      ]);
      expect(store.cancellations, 3);
      expect(session.snapshot.revision, 11);
      await listening.cancel();
    },
  );

  test(
    'same-account ID in a different profile is rejected before reading',
    () async {
      final foreign = MailAccountId(
        'reader',
        profile: MailProfileId('other', hostId: 'retained-session-test'),
      );
      await session.selectSynchronized(
        MailMailboxId('inbox', account: foreign),
      );
      expect(store.requests, isEmpty);
      expect(session.snapshot.source, StudioMailMailboxSource.synchronized);
      expect(session.snapshot.problem!.code, MailProblemCode.permissionDenied);
    },
  );

  test('invalid limits and offsets never subscribe to local storage', () async {
    for (final options in [
      (limit: 0, offset: 0),
      (limit: 1001, offset: 0),
      (limit: 100, offset: -1),
      (limit: 100, offset: 9007199254740992),
    ]) {
      await session.selectSynchronized(
        _inbox,
        limit: options.limit,
        offset: options.offset,
      );
      expect(session.snapshot.problem!.code, MailProblemCode.invalidInput);
    }
    expect(store.requests, isEmpty);
  });

  test(
    'wrong identity, generation and duplicate records cannot replace data',
    () async {
      final good = _sync(_inbox, count: 2);
      await open(_inbox, good);
      final foreign = MailMailboxId(
        'inbox',
        account: MailAccountId('other', profile: _account.profile),
      );
      for (final invalid in [
        _sync(_archive, count: 2),
        _sync(
          _inbox,
          count: 2,
          headers: [_header(_inbox, 1), _header(foreign, 2)],
        ),
        _sync(
          _inbox,
          count: 2,
          headers: [_header(_inbox, 1), _header(_archive, 2)],
        ),
        _sync(
          _inbox,
          count: 2,
          headers: [
            _header(_inbox, 1),
            _header(_inbox, 2, provider: MailProviderKind.ews),
          ],
        ),
        _sync(
          _inbox,
          count: 2,
          headers: [_header(_inbox, 1), _header(_inbox, 2, validity: 8)],
        ),
        _sync(
          _inbox,
          count: 2,
          headers: [
            _header(_inbox, 1),
            _header(_inbox, 1, localId: 'duplicate-remote'),
          ],
        ),
        _sync(
          _inbox,
          count: 2,
          headers: [
            _header(_inbox, 1),
            _header(_inbox, 2, localId: 'message-1'),
          ],
        ),
      ]) {
        store.syncStreams.single.add(MailSuccess(invalid));
        expect(session.snapshot.phase, StudioMailMailboxPhase.failed);
        expect(session.snapshot.problem!.code, MailProblemCode.conflict);
        expect(session.snapshot.synchronizedView, same(good));
      }
    },
  );

  test(
    'malformed counts, paging and revisions retain the last valid page',
    () async {
      final good = _sync(_inbox, revision: 3, count: 3, limit: 2);
      await open(_inbox, good, limit: 2);
      for (final invalid in [
        _sync(_inbox, revision: 2, count: 3, limit: 2),
        _sync(_inbox, revision: 0, count: 3, limit: 2),
        _sync(_inbox, revision: 9007199254740992, count: 3, limit: 2),
        _sync(_inbox, revision: 4, count: -1, headers: []),
        _sync(_inbox, revision: 4, count: 9007199254740992, headers: []),
        _sync(_inbox, revision: 4, count: 3, limit: 2, offset: 1),
        _sync(_inbox, revision: 4, count: 3, headers: [_header(_inbox, 1)]),
        _sync(_inbox, revision: 4, count: 3, limit: 2, hasMoreHeaders: false),
        _sync(
          _inbox,
          revision: 4,
          count: 3,
          headers: [_header(_inbox, 1), _header(_inbox, 2), _header(_inbox, 3)],
        ),
      ]) {
        store.syncStreams.single.add(MailSuccess(invalid));
        expect(session.snapshot.problem!.code, MailProblemCode.conflict);
        expect(session.snapshot.synchronizedView, same(good));
      }
      store.syncStreams.single.add(
        MailSuccess(_sync(_inbox, revision: 4, count: 3, limit: 2)),
      );
      expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
      expect(session.snapshot.problem, isNull);
    },
  );

  test(
    'missing checkpoints and empty synchronized folders remain distinct',
    () async {
      await open(_inbox, null);
      expect(session.snapshot.phase, StudioMailMailboxPhase.missing);
      expect(session.snapshot.synchronizedView, isNull);
      expect(store.browseStreams, isEmpty);
      store.syncStreams.single.add(MailSuccess(_sync(_inbox, count: 0)));
      expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
      expect(session.snapshot.synchronizedView, isNotNull);
      expect(session.snapshot.headers, isEmpty);
      store.syncStreams.single.add(const MailSuccess(null));
      expect(session.snapshot.phase, StudioMailMailboxPhase.missing);
      expect(session.snapshot.headers, isEmpty);
    },
  );

  test(
    'typed, thrown and terminal failures preserve synchronized data',
    () async {
      final good = _sync(_inbox);
      await open(_inbox, good);
      store.syncStreams.single.add(
        const MailFailure(MailProblem(MailProblemCode.quotaExceeded)),
      );
      expect(session.snapshot.problem!.code, MailProblemCode.quotaExceeded);
      expect(session.snapshot.synchronizedView, same(good));
      expect(session.snapshot.source, StudioMailMailboxSource.synchronized);
      store.syncStreams.single.addError(StateError('private storage text'));
      expect(session.snapshot.problem!.code, MailProblemCode.storageFailure);
      expect(session.snapshot.synchronizedView, same(good));
      store.syncStreams.single.add(MailSuccess(_sync(_inbox, revision: 2)));
      expect(session.snapshot.problem, isNull);
      await store.syncStreams.single.close();
      expect(session.snapshot.problem!.code, MailProblemCode.unavailable);
      expect(session.snapshot.revision, 2);
    },
  );

  test('a removed last page repairs to the last retained page', () async {
    await open(
      _inbox,
      _sync(_inbox, count: 5, offset: 4, limit: 2),
      offset: 4,
      limit: 2,
    );
    store.syncStreams.single.add(
      MailSuccess(_sync(_inbox, revision: 2, count: 3, offset: 4, limit: 2)),
    );
    expect(session.snapshot.phase, StudioMailMailboxPhase.loading);
    expect(session.snapshot.offset, 2);
    expect(session.snapshot.headers, isEmpty);
    await _tick();
    expect(store.requests.last, (mailbox: _inbox, limit: 2, offset: 2));
    store.syncStreams.last.add(
      MailSuccess(_sync(_inbox, revision: 2, count: 3, offset: 2, limit: 2)),
    );
    expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
    expect(session.snapshot.headers.single.id.value, 'message-3');
    expect(session.snapshot.nextOffset, isNull);
  });

  test(
    'initial out-of-range wait finishes only after empty page repair',
    () async {
      var completed = false;
      final opening = session
          .selectSynchronized(_inbox, limit: 2, offset: 4)
          .then((_) => completed = true);
      await _tick();
      store.syncStreams.single.add(
        MailSuccess(_sync(_inbox, revision: 6, count: 0, offset: 4, limit: 2)),
      );
      await _tick();
      expect(completed, isFalse);
      expect(store.requests.last.offset, 0);
      store.syncStreams.last.add(
        MailSuccess(_sync(_inbox, revision: 6, count: 0, limit: 2)),
      );
      await opening;
      expect(completed, isTrue);
      expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
      expect(session.snapshot.offset, 0);
      expect(session.snapshot.headerCount, 0);
    },
  );

  test(
    'page repair keeps revision fence and cannot roll membership back',
    () async {
      final opening = session.selectSynchronized(_inbox, limit: 2, offset: 4);
      await _tick();
      store.syncStreams.single.add(
        MailSuccess(_sync(_inbox, revision: 6, count: 3, offset: 4, limit: 2)),
      );
      await _tick();
      store.syncStreams.last.add(
        MailSuccess(_sync(_inbox, revision: 5, count: 3, offset: 2, limit: 2)),
      );
      await opening;
      expect(session.snapshot.phase, StudioMailMailboxPhase.failed);
      expect(session.snapshot.problem!.code, MailProblemCode.conflict);
      expect(session.snapshot.headers, isEmpty);
      store.syncStreams.last.add(
        MailSuccess(_sync(_inbox, revision: 6, count: 3, offset: 2, limit: 2)),
      );
      expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
    },
  );

  test('a source switch supersedes a pending page repair waiter', () async {
    final opening = session.selectSynchronized(_inbox, limit: 2, offset: 4);
    await _tick();
    store.syncStreams.single.add(
      MailSuccess(_sync(_inbox, count: 0, offset: 4, limit: 2)),
    );
    final browsing = session.select(_inbox);
    await opening;
    await _tick();
    expect(store.requests.length, 1);
    store.browseStreams.single.add(MailSuccess(_browse(_inbox)));
    await browsing;
    expect(session.snapshot.source, StudioMailMailboxSource.browse);
    expect(session.snapshot.headers.single.id.value, 'message-9');
  });

  test(
    'clear immediately retires selected data and remains reusable',
    () async {
      await open(_inbox, _sync(_inbox));
      final cleared = session.clear();
      expect(session.snapshot.phase, StudioMailMailboxPhase.idle);
      expect(session.snapshot.mailbox, isNull);
      expect(session.snapshot.headers, isEmpty);
      store.syncStreams.single.add(MailSuccess(_sync(_inbox, revision: 2)));
      await cleared;
      expect(session.snapshot.phase, StudioMailMailboxPhase.idle);
      await open(_archive, _sync(_archive));
      expect(session.snapshot.mailbox, _archive);
      expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
    },
  );

  test('clear settles unfinished selection and drains cancellation', () async {
    store.cancellationGate = Completer<void>();
    final opening = session.selectSynchronized(_inbox);
    await _tick();
    var cleared = false;
    final clearing = session.clear().then((_) => cleared = true);
    await opening;
    await _tick();
    expect(cleared, isFalse);
    store.cancellationGate!.complete();
    await clearing;
    expect(cleared, isTrue);
  });

  test(
    'close drains synchronized observer and prevents later selection',
    () async {
      store.cancellationGate = Completer<void>();
      await open(_inbox, _sync(_inbox));
      var closed = false;
      final closing = session.close().then((_) => closed = true);
      expect(session.snapshot.phase, StudioMailMailboxPhase.closed);
      await session.selectSynchronized(_archive);
      await _tick();
      expect(store.requests.length, 1);
      expect(closed, isFalse);
      store.cancellationGate!.complete();
      await closing;
      expect(closed, isTrue);
    },
  );

  test('an unsupported sync store fails without loading browse data', () async {
    final oneShot = _OneShotStore();
    await session.close();
    session = StudioMailMailboxSession(
      store: oneShot,
      provider: MailProviderKind.imap,
    );
    await session.selectSynchronized(_inbox);
    expect(session.snapshot.phase, StudioMailMailboxPhase.failed);
    expect(session.snapshot.problem!.code, MailProblemCode.unsupported);
    expect(session.snapshot.source, StudioMailMailboxSource.synchronized);
    expect(oneShot.loads, 0);
  });

  test('close drains a cancelled one-shot read before owner release', () async {
    final oneShot = _OneShotStore();
    await session.close();
    session = StudioMailMailboxSession(
      store: oneShot,
      provider: MailProviderKind.imap,
    );
    final opening = session.select(_inbox);
    await _tick();
    var closed = false;
    final closing = session.close().then((_) => closed = true);
    await opening;
    await _tick();
    expect(closed, isFalse);
    oneShot.read.complete(_browse(_inbox));
    await closing;
    expect(session.snapshot.phase, StudioMailMailboxPhase.closed);
    expect(session.snapshot.headers, isEmpty);
  });
}
