import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_mailbox_session.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';

final _account = MailAccountId(
  'reader',
  profile: MailProfileId('profile', hostId: 'session-test'),
);
final _inbox = MailMailboxId('inbox', account: _account);
final _archive = MailMailboxId('archive', account: _account);

MailHeaderRecord _header(
  MailMailboxId mailbox,
  int uid, {
  MailMessageFlags? flags = const MailMessageFlags(),
  MailProviderKind provider = MailProviderKind.imap,
}) => MailHeaderRecord(
  id: MailMessageId('message-$uid'),
  remote: provider == MailProviderKind.imap
      ? MailImapIdentity(mailbox: mailbox, uidValidity: 7, uid: uid)
      : MailOpaqueIdentity(
          account: mailbox.account,
          provider: provider,
          value: '$uid',
        ),
  envelope: MailEnvelope(subject: 'Message $uid'),
  flags: flags,
);

MailCachedMailboxView _view(
  MailMailboxId mailbox, {
  int revision = 1,
  List<MailHeaderRecord>? headers,
}) => MailCachedMailboxView(
  mailbox: MailMailbox(id: mailbox, displayName: mailbox.value),
  revision: revision,
  capturedAt: DateTime.utc(2026, 11, 21),
  headers: headers ?? [_header(mailbox, 1)],
  hasMore: true,
);

final class _WatchStore extends Fake
    implements StudioMailMailboxStore, StudioMailMailboxWatchStore {
  @override
  MailAccountId get account => _account;
  final mailboxes = <MailMailboxId>[];
  final streams = <StreamController<MailResult<MailCachedMailboxView?>>>[];
  Completer<void>? cancellationGate;
  int cancellations = 0;

  @override
  Stream<MailResult<MailCachedMailboxView?>> watchView(MailMailboxId mailbox) {
    mailboxes.add(mailbox);
    final gate = cancellationGate;
    final stream = StreamController<MailResult<MailCachedMailboxView?>>(
      sync: true,
      onCancel: () async {
        cancellations++;
        await gate?.future;
      },
    );
    streams.add(stream);
    return stream.stream;
  }
}

final class _OneShotStore extends Fake implements StudioMailMailboxStore {
  @override
  MailAccountId get account => _account;
  @override
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox) async =>
      _view(mailbox);
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  late _WatchStore store;
  late StudioMailMailboxSession session;

  setUp(() {
    store = _WatchStore();
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
    for (final controller in store.streams) {
      await controller.close();
    }
  });

  Future<void> open(MailMailboxId mailbox, MailCachedMailboxView? view) async {
    final opening = session.select(mailbox);
    await _tick();
    store.streams.last.add(MailSuccess(view));
    await opening;
  }

  test('initial load, bounded counts and same-revision flag updates', () async {
    final opening = session.select(_inbox);
    expect(session.snapshot.phase, StudioMailMailboxPhase.loading);
    await _tick();
    store.streams.single.add(
      MailSuccess(
        _view(
          _inbox,
          headers: [
            _header(_inbox, 3, flags: const MailMessageFlags(isRead: true)),
            _header(_inbox, 2),
            _header(_inbox, 1, flags: null),
          ],
        ),
      ),
    );
    await opening;
    expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
    expect(session.snapshot.view!.headers.map((header) => header.id.value), [
      'message-3',
      'message-2',
      'message-1',
    ]);
    expect(session.snapshot.unreadCount, 1);
    expect(session.snapshot.unknownReadCount, 1);
    store.streams.single.add(
      MailSuccess(
        _view(
          _inbox,
          headers: [
            _header(_inbox, 3, flags: const MailMessageFlags(isRead: true)),
            _header(_inbox, 2, flags: const MailMessageFlags(isRead: true)),
            _header(_inbox, 1, flags: null),
          ],
        ),
      ),
    );
    expect(session.snapshot.unreadCount, 0);
    expect(session.snapshot.view!.hasMore, isTrue);
  });

  test(
    'A to B to A cancels each previous observer and clears old state',
    () async {
      await open(_inbox, _view(_inbox, revision: 9));
      final changing = session.select(_archive);
      expect(session.snapshot.view, isNull);
      // A queued emission from the old scope cannot repopulate the new one.
      store.streams.first.add(MailSuccess(_view(_inbox, revision: 10)));
      expect(session.snapshot.view, isNull);
      await _tick();
      store.streams.last.add(MailSuccess(_view(_archive)));
      await changing;
      expect(session.snapshot.mailbox, _archive);
      await open(_inbox, _view(_inbox, revision: 11));
      expect(store.mailboxes, [_inbox, _archive, _inbox]);
      expect(store.cancellations, 2);
      expect(session.snapshot.view!.revision, 11);
    },
  );

  test(
    'superseding an unfinished selection completes it without stale subscription',
    () async {
      final first = session.select(_inbox);
      final second = session.select(_archive);
      await first;
      await _tick();
      expect(store.mailboxes, [_archive]);
      store.streams.single.add(MailSuccess(_view(_archive)));
      await second;
      expect(session.snapshot.mailbox, _archive);
    },
  );

  test(
    'cross-account selection fails without reading its repository',
    () async {
      await open(_inbox, _view(_inbox));
      final foreign = MailAccountId('foreign', profile: _account.profile);
      await session.select(MailMailboxId('inbox', account: foreign));
      expect(store.mailboxes, [_inbox]);
      expect(session.snapshot.phase, StudioMailMailboxPhase.failed);
      expect(session.snapshot.problem!.code, MailProblemCode.permissionDenied);
      expect(session.snapshot.view, isNull);
    },
  );

  test(
    'wrong mailbox, provider and duplicate identities cannot replace a good snapshot',
    () async {
      final good = _view(_inbox);
      await open(_inbox, good);
      for (final invalid in [
        _view(_archive),
        _view(
          _inbox,
          headers: [_header(_inbox, 1, provider: MailProviderKind.ews)],
        ),
        _view(_inbox, headers: [_header(_inbox, 1), _header(_inbox, 1)]),
        _view(_inbox, headers: [_header(_archive, 1)]),
      ]) {
        store.streams.single.add(MailSuccess(invalid));
        expect(session.snapshot.phase, StudioMailMailboxPhase.failed);
        expect(session.snapshot.problem!.code, MailProblemCode.conflict);
        expect(session.snapshot.view, same(good));
      }
      store.streams.single.add(MailSuccess(_view(_inbox, revision: 2)));
      expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
    },
  );

  test(
    'typed and thrown failures retain saved content and recover on next event',
    () async {
      final good = _view(_inbox);
      await open(_inbox, good);
      store.streams.single.add(
        const MailFailure(MailProblem(MailProblemCode.quotaExceeded)),
      );
      expect(session.snapshot.problem!.code, MailProblemCode.quotaExceeded);
      expect(session.snapshot.view, same(good));
      store.streams.single.addError(
        StateError('private diagnostic is not exposed'),
      );
      expect(session.snapshot.problem!.code, MailProblemCode.storageFailure);
      expect(session.snapshot.view, same(good));
      store.streams.single.add(MailSuccess(_view(_inbox, revision: 2)));
      expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
      expect(session.snapshot.problem, isNull);
    },
  );

  test(
    'missing, empty and retired then recreated views have distinct states',
    () async {
      await open(_inbox, _view(_inbox, revision: 8));
      store.streams.single.add(const MailSuccess(null));
      expect(session.snapshot.phase, StudioMailMailboxPhase.missing);
      expect(session.snapshot.view, isNull);
      store.streams.single.add(MailSuccess(_view(_inbox, headers: [])));
      expect(session.snapshot.phase, StudioMailMailboxPhase.failed);
      expect(session.snapshot.problem!.code, MailProblemCode.conflict);
      expect(session.snapshot.view, isNull);
      store.streams.single.add(
        MailSuccess(_view(_inbox, revision: 9, headers: [])),
      );
      expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
      expect(session.snapshot.view!.headers, isEmpty);
      expect(session.snapshot.view!.revision, 9);
    },
  );

  test('older revisions cannot roll back a selected folder', () async {
    await open(_inbox, _view(_inbox, revision: 5));
    store.streams.single.add(MailSuccess(_view(_inbox, revision: 4)));
    expect(session.snapshot.problem!.code, MailProblemCode.conflict);
    expect(session.snapshot.view!.revision, 5);
  });

  test(
    'a listener can switch on ready without reentrant events or lost subscription',
    () async {
      final switched = Completer<void>();
      final listener = session.changes.listen((snapshot) {
        if (snapshot.phase == StudioMailMailboxPhase.ready &&
            snapshot.mailbox == _inbox) {
          unawaited(session.select(_archive).then((_) => switched.complete()));
        }
      });
      await open(_inbox, _view(_inbox));
      await _tick();
      expect(store.mailboxes, [_inbox, _archive]);
      store.streams.last.add(MailSuccess(_view(_archive)));
      await switched.future;
      expect(session.snapshot.mailbox, _archive);
      expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
      await listener.cancel();
    },
  );

  test('a listener can close on ready and drains its observer', () async {
    final closed = Completer<void>();
    final listener = session.changes.listen((snapshot) {
      if (snapshot.phase == StudioMailMailboxPhase.ready) {
        unawaited(session.close().then((_) => closed.complete()));
      }
    });
    await open(_inbox, _view(_inbox));
    await closed.future;
    expect(session.snapshot.phase, StudioMailMailboxPhase.closed);
    expect(store.cancellations, 1);
    await listener.cancel();
  });

  test(
    'an already queued snapshot cannot repopulate a switched or closed scope',
    () async {
      final observed = <StudioMailMailboxSnapshot>[];
      final listener = session.changes.listen(observed.add);
      final opening = session.select(_inbox);
      await _tick();
      observed.clear();
      store.streams.single.add(MailSuccess(_view(_inbox)));
      final switching = session.select(_archive);
      await opening;
      await _tick();
      expect(
        observed.where((value) => value.view?.mailbox.id == _inbox),
        isEmpty,
      );
      store.streams.last.add(MailSuccess(_view(_archive)));
      final closing = session.close();
      await switching;
      await closing;
      expect(
        observed.where((value) => value.view?.mailbox.id == _archive),
        isEmpty,
      );
      expect(observed.last.phase, StudioMailMailboxPhase.closed);
      await listener.cancel();
    },
  );

  test(
    'close invalidates immediately and drains cancellation before releasing owner',
    () async {
      store.cancellationGate = Completer<void>();
      await open(_inbox, _view(_inbox));
      var closed = false;
      final closing = session.close().then((_) => closed = true);
      expect(session.snapshot.phase, StudioMailMailboxPhase.closed);
      expect(session.snapshot.view, isNull);
      await session.select(_archive);
      await _tick();
      expect(closed, isFalse);
      expect(store.mailboxes, [_inbox]);
      store.cancellationGate!.complete();
      await closing;
      expect(closed, isTrue);
    },
  );

  test(
    'unexpected live store closure is failure, with last good view retained',
    () async {
      await open(_inbox, _view(_inbox));
      await store.streams.single.close();
      expect(session.snapshot.phase, StudioMailMailboxPhase.failed);
      expect(session.snapshot.problem!.code, MailProblemCode.unavailable);
      expect(session.snapshot.view, isNotNull);
    },
  );

  test(
    'one-shot injected stores keep their ready snapshot after stream completion',
    () async {
      await session.close();
      session = StudioMailMailboxSession(
        store: _OneShotStore(),
        provider: MailProviderKind.imap,
      );
      await session.select(_inbox);
      await _tick();
      expect(session.snapshot.phase, StudioMailMailboxPhase.ready);
    },
  );
}
