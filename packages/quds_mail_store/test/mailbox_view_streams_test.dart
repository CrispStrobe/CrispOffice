@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:test/test.dart';

final _profile = MailProfileId('view-streams', hostId: 'test-office');
final _account = MailAccountId('account', profile: _profile);
final _mailbox = MailMailbox(
  id: MailMailboxId('INBOX', account: _account),
  displayName: 'Inbox · البريد الوارد',
);
final _now = DateTime.utc(2026, 11, 21);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

MailHeaderRecord _header(
  int uid, {
  MailMailbox? mailbox,
  MailMessageFlags? flags = const MailMessageFlags(),
}) => MailHeaderRecord(
  id: MailMessageId('message-$uid'),
  remote: MailImapIdentity(
    mailbox: (mailbox ?? _mailbox).id,
    uidValidity: 7,
    uid: uid,
  ),
  envelope: MailEnvelope(subject: 'Subject $uid'),
  flags: flags,
);

final class _ReadProbe extends QueryInterceptor {
  bool failViewRead = false;
  bool bodyRead = false;
  int viewReads = 0;
  Completer<void>? gate;
  Completer<void>? started;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    bodyRead |=
        statement.contains('SELECT b.hash,b.data') ||
        statement.contains('SELECT data FROM cached_messages');
    if (statement.startsWith('SELECT v.*,b.display_name,b.is_label')) {
      viewReads++;
      if (failViewRead) {
        throw const MailStoreStorageException(MailProblemCode.storageFailure);
      }
      final pending = gate;
      if (pending != null) {
        gate = null;
        started?.complete();
        await pending.future;
      }
    }
    return super.runSelect(executor, statement, args);
  }
}

final class _Snapshots<T> {
  _Snapshots(Stream<MailResult<T>> stream) {
    subscription = stream.listen((event) {
      events.add(event);
      for (final waiter in List.of(_waiters)) {
        if (waiter.$1(event)) {
          _waiters.remove(waiter);
          waiter.$2.complete(event);
        }
      }
    }, onDone: done.complete);
  }

  final events = <MailResult<T>>[];
  final done = Completer<void>();
  final _waiters = <(bool Function(MailResult<T>), Completer<MailResult<T>>)>[];
  late final StreamSubscription<MailResult<T>> subscription;

  Future<void> cancel() => subscription.cancel();

  Future<MailResult<T>> matching(
    bool Function(MailResult<T>) matches, {
    int after = 0,
  }) {
    for (final event in events.skip(after)) {
      if (matches(event)) return Future.value(event);
    }
    final completer = Completer<MailResult<T>>();
    _waiters.add((matches, completer));
    return completer.future.timeout(const Duration(seconds: 5));
  }
}

void main() {
  late Directory directory;
  late File file;
  late SqliteMailRepository store;
  late MailAccountSession session;
  late _ReadProbe probe;
  var failCommit = false;
  final cancellations = <Future<void> Function()>[];

  Future<SqliteMailRepository> open({
    MailStoreLimits limits = const MailStoreLimits(),
  }) async => _value(
    await SqliteMailRepository.open(
      executor: NativeDatabase(file).interceptWith(probe),
      profile: _profile,
      limits: limits,
      clock: () => _now,
      faultInjector: (point) {
        if (point == MailStoreCheckpoint.beforeCommit && failCommit) {
          throw const MailStoreStorageException(MailProblemCode.storageFailure);
        }
      },
    ),
  );

  Future<MailResult<MailCachedMailboxView>> save(
    List<MailHeaderRecord> headers, {
    MailMailbox? mailbox,
    int? revision,
    bool hasMore = false,
  }) => store.saveMailboxView(
    mailbox ?? _mailbox,
    headers,
    expectedRevision: revision,
    hasMore: hasMore,
    lease: session.begin(),
  );

  _Snapshots<T> watch<T>(Stream<MailResult<T>> stream) {
    final snapshots = _Snapshots(stream);
    cancellations.add(snapshots.cancel);
    return snapshots;
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp(
      'quds-mail-view-streams-',
    );
    file = File('${directory.path}/mail.sqlite3');
    session = MailAccountSession(_account);
    probe = _ReadProbe();
    failCommit = false;
    store = await open();
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.imap,
          displayName: 'View stream account',
        ),
      ),
    );
  });

  tearDown(() async {
    for (final cancel in cancellations) {
      await cancel();
    }
    cancellations.clear();
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'initial absence, saved empty folder and retained order are distinct',
    () async {
      final views = watch(store.watchMailboxView(_mailbox.id));
      expect(_value(await views.matching((_) => true)), isNull);
      final empty = _value(await save([]));
      final emptySnapshot = _value(
        await views.matching(
          (event) =>
              event is MailSuccess<MailCachedMailboxView?> &&
              event.value?.revision == empty.revision,
        ),
      )!;
      expect(emptySnapshot.headers, isEmpty);

      final full = _value(
        await save(
          [_header(9), _header(2), _header(8)],
          revision: empty.revision,
          hasMore: true,
        ),
      );
      final snapshot = _value(
        await views.matching(
          (event) =>
              event is MailSuccess<MailCachedMailboxView?> &&
              event.value?.revision == full.revision,
        ),
      )!;
      expect(snapshot.headers.map((header) => header.id.value), [
        'message-9',
        'message-2',
        'message-8',
      ]);
      expect(snapshot.mailbox.id, _mailbox.id);
      expect(snapshot.capturedAt, _now);
      expect(snapshot.hasMore, isTrue);
      expect(() => snapshot.headers.clear(), throwsUnsupportedError);
      expect(_value(await store.listHeaders(_mailbox.id)), isEmpty);
      expect(_value(await store.readCursor(_mailbox.id)), isNull);
      expect(probe.bodyRead, isFalse);
    },
  );

  test(
    'catalog and view update only after a complete successful transaction',
    () async {
      final views = watch(store.watchMailboxView(_mailbox.id));
      final catalogs = watch(store.watchMailboxViews(_account));
      await views.matching((_) => true);
      await catalogs.matching((_) => true);
      failCommit = true;
      _problem(await save([_header(1)]), MailProblemCode.storageFailure);
      failCommit = false;
      final saved = _value(await save([_header(2), _header(3)]));
      await views.matching(
        (event) =>
            event is MailSuccess<MailCachedMailboxView?> &&
            event.value?.revision == saved.revision,
      );
      final catalog = _value(
        await catalogs.matching(
          (event) =>
              event is MailSuccess<List<MailCachedMailboxSummary>> &&
              event.value.isNotEmpty,
        ),
      );
      expect(catalog.single.headerCount, 2);
      expect(catalog.single.revision, saved.revision);
      expect(
        views.events.every((event) {
          final view = _value(event);
          return view == null || view.headers.length == 2;
        }),
        isTrue,
      );
      expect(
        catalogs.events.every((event) {
          final folders = _value(event);
          return folders.isEmpty || folders.single.headerCount == 2;
        }),
        isTrue,
      );
    },
  );

  test(
    'journal acknowledgement refreshes exact flags and catalog revision',
    () async {
      final saved = _value(await save([_header(1)], hasMore: true));
      final views = watch(store.watchMailboxView(_mailbox.id));
      final catalogs = watch(store.watchMailboxViews(_account));
      await views.matching((_) => true);
      await catalogs.matching((_) => true);
      final plan = MailBulkFlagPlan(
        id: 'mark-read',
        mailbox: _mailbox.id,
        action: MailBulkFlagAction.markRead,
        messages: [saved.headers.single.remote],
      );
      final handle = _value(
        await store.createFlagBatch(
          plan,
          subjects: ['Subject 1'],
          lease: session.begin(),
        ),
      );
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      _value(
        await store.recordFlagResult(
          handle,
          0,
          MailBulkFlagItemResult.restore(
            operation: plan.operationAt(0),
            outcome: MailBulkFlagOutcome.confirmed,
          ),
        ),
      );
      final patched = _value(
        await views.matching(
          (event) =>
              event is MailSuccess<MailCachedMailboxView?> &&
              event.value?.headers.single.flags?.isRead == true,
        ),
      )!;
      expect(patched.headers.single.flags?.isFlagged, isFalse);
      expect(patched.capturedAt, saved.capturedAt);
      expect(patched.hasMore, saved.hasMore);
      expect(patched.revision, greaterThan(saved.revision));
      final catalog = _value(
        await catalogs.matching(
          (event) =>
              event is MailSuccess<List<MailCachedMailboxSummary>> &&
              event.value.single.revision == patched.revision,
        ),
      );
      expect(catalog.single.capturedAt, saved.capturedAt);
    },
  );

  test('cache cleanup emits absent view and empty catalog', () async {
    _value(await save([_header(1)]));
    final views = watch(store.watchMailboxView(_mailbox.id));
    final catalogs = watch(store.watchMailboxViews(_account));
    await views.matching((_) => true);
    await catalogs.matching((_) => true);
    _value(await store.clearMailboxCache(_account));
    expect(
      _value(
        await views.matching(
          (event) =>
              event is MailSuccess<MailCachedMailboxView?> &&
              event.value == null,
        ),
      ),
      isNull,
    );
    expect(
      _value(
        await catalogs.matching(
          (event) =>
              event is MailSuccess<List<MailCachedMailboxSummary>> &&
              event.value.isEmpty,
        ),
      ),
      isEmpty,
    );
  });

  test('read failure stays typed and a later commit can recover', () async {
    final saved = _value(await save([_header(1)]));
    probe.failViewRead = true;
    final views = watch(store.watchMailboxView(_mailbox.id));
    _problem(await views.matching((_) => true), MailProblemCode.storageFailure);
    probe.failViewRead = false;
    _value(await store.saveMailbox(_mailbox));
    final recovered = _value(
      await views.matching(
        (event) => event is MailSuccess<MailCachedMailboxView?>,
      ),
    );
    expect(recovered?.revision, saved.revision);
    expect(recovered?.headers.single.id, saved.headers.single.id);
  });

  test(
    'catalog quota and invalid limits remain explicit stream failures',
    () async {
      _value(await save([]));
      final second = MailMailbox(
        id: MailMailboxId('Archive', account: _account),
        displayName: 'Archive',
      );
      _value(await save([], mailbox: second));
      _problem(
        await store.watchMailboxViews(_account, limit: 1).first,
        MailProblemCode.quotaExceeded,
      );
      _problem(
        await store.watchMailboxViews(_account, limit: 0).first,
        MailProblemCode.invalidInput,
      );
      final catalog = _value(await store.watchMailboxViews(_account).first);
      expect(catalog.map((folder) => folder.mailbox.id.value), [
        'Archive',
        'INBOX',
      ]);
      expect(() => catalog.clear(), throwsUnsupportedError);
    },
  );

  test(
    'reopened stricter header bound refuses an oversized retained window',
    () async {
      _value(await save([_header(1), _header(2)]));
      await store.close();
      store = await open(limits: const MailStoreLimits(maxPageSize: 1));
      _problem(
        await store.watchMailboxView(_mailbox.id).first,
        MailProblemCode.quotaExceeded,
      );
      expect(probe.bodyRead, isFalse);
    },
  );

  test(
    'foreign profile and retired account cannot produce another scope',
    () async {
      _value(await save([_header(1)]));
      final foreign = MailAccountId(
        'account',
        profile: MailProfileId('other', hostId: 'test-office'),
      );
      _problem(
        await store
            .watchMailboxView(MailMailboxId('INBOX', account: foreign))
            .first,
        MailProblemCode.permissionDenied,
      );
      _problem(
        await store.watchMailboxViews(foreign).first,
        MailProblemCode.permissionDenied,
      );
      final views = watch(store.watchMailboxView(_mailbox.id));
      await views.matching((_) => true);
      _value(await store.removeAccount(_account));
      _problem(
        await views.matching(
          (event) => event is MailFailure<MailCachedMailboxView?>,
        ),
        MailProblemCode.unavailable,
      );
    },
  );

  test(
    'paused listeners coalesce committed snapshots without re-reading',
    () async {
      final first = _value(await save([_header(1)]));
      final views = watch(store.watchMailboxView(_mailbox.id));
      await views.matching((_) => true);
      views.subscription.pause();
      final second = _value(await save([_header(2)], revision: first.revision));
      final third = _value(await save([_header(3)], revision: second.revision));
      expect(views.events, hasLength(1));
      final reads = probe.viewReads;
      views.subscription.resume();
      final latest = _value(
        await views.matching(
          (event) =>
              event is MailSuccess<MailCachedMailboxView?> &&
              event.value?.revision == third.revision,
        ),
      )!;
      expect(latest.headers.single.id.value, 'message-3');
      expect(views.events, hasLength(2));
      expect(probe.viewReads, reads + 1);
    },
  );

  test(
    'cancellation drains an in-flight read and suppresses its late result',
    () async {
      _value(await save([_header(1)]));
      final gate = Completer<void>();
      probe.gate = gate;
      probe.started = Completer<void>();
      final views = watch(store.watchMailboxView(_mailbox.id));
      await probe.started!.future.timeout(const Duration(seconds: 5));
      var cancelled = false;
      final cancelling = views.subscription.cancel().then(
        (_) => cancelled = true,
      );
      await Future<void>.value();
      expect(cancelled, isFalse);
      gate.complete();
      await cancelling.timeout(const Duration(seconds: 5));
      expect(views.events, isEmpty);
      _value(await store.saveMailbox(_mailbox));
      expect(views.events, isEmpty);
    },
  );

  test(
    'active subscriptions finish on close and closed subscriptions fail once',
    () async {
      final views = watch(store.watchMailboxView(_mailbox.id));
      final catalogs = watch(store.watchMailboxViews(_account));
      await views.matching((_) => true);
      await catalogs.matching((_) => true);
      await store.close();
      await Future.wait([
        views.done.future,
        catalogs.done.future,
      ]).timeout(const Duration(seconds: 5));
      final closedView = await store.watchMailboxView(_mailbox.id).toList();
      final closedCatalog = await store.watchMailboxViews(_account).toList();
      expect(closedView, hasLength(1));
      expect(closedCatalog, hasLength(1));
      _problem(closedView.single, MailProblemCode.unavailable);
      _problem(closedCatalog.single, MailProblemCode.unavailable);
    },
  );
}
