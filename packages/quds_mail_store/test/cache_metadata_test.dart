@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('metadata', hostId: 'test-office');
final _account = MailAccountId('account', profile: _profile);
final _box = MailMailbox(
  id: MailMailboxId('inbox', account: _account),
  displayName: 'Inbox',
);
final _header = MailHeaderRecord(
  id: MailMessageId('message'),
  remote: MailImapIdentity(mailbox: _box.id, uidValidity: 1, uid: 1),
  envelope: MailEnvelope(subject: 'Subject'),
);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

final class _ReadProbe extends QueryInterceptor {
  int maximumText = 0;
  bool blobRead = false;

  void reset() {
    maximumText = 0;
    blobRead = false;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    blobRead |= statement.contains('SELECT b.hash,b.data');
    final result = await super.runSelect(executor, statement, args);
    for (final row in result) {
      for (final value in row.values) {
        if (value is String && value.length > maximumText) {
          maximumText = value.length;
        }
      }
    }
    return result;
  }
}

void main() {
  late Directory directory;
  late File file;
  late SqliteMailRepository store;
  late _ReadProbe probe;

  Future<SqliteMailRepository> open({
    MailStoreLimits limits = const MailStoreLimits(),
  }) async => _value(
    await SqliteMailRepository.open(
      executor: NativeDatabase(file).interceptWith(probe),
      profile: _profile,
      limits: limits,
    ),
  );

  Future<void> cache({
    String body = 'body',
    String attachmentName = 'file.bin',
  }) async {
    _value(
      await store.cacheMessage(
        _account,
        _header.id,
        MailMessage(
          raw: MailBytes(Uint8List.fromList([10, 20, 30])),
          envelope: _header.envelope,
          body: MailBody(plainText: body),
          localId: _header.id,
          remoteIdentity: _header.remote,
          attachments: [
            MailAttachment(
              partPath: '2',
              mediaType: 'application/octet-stream',
              displayName: attachmentName,
              content: MailBytes(Uint8List.fromList([40, 50, 60])),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> reopenWithSmallBudget() async {
    await store.close();
    store = await open(
      limits: const MailStoreLimits(maxMetadataCodeUnits: 4096),
    );
    probe.reset();
  }

  Future<MailResult<MailCachedMailboxView>> refresh() => store.saveMailboxView(
    _box,
    [_header],
    expectedRevision: 1,
    hasMore: false,
    lease: MailAccountSession(_account).begin(),
  );

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('quds-cache-metadata-');
    file = File('${directory.path}/mail.sqlite');
    probe = _ReadProbe();
    store = await open();
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.imap,
          displayName: 'Metadata',
        ),
      ),
    );
    _value(
      await store.saveMailboxView(
        _box,
        [_header],
        expectedRevision: null,
        hasMore: false,
        lease: MailAccountSession(_account).begin(),
      ),
    );
    await cache();
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  for (final (table, column, code) in [
    ('cached_messages', 'data', MailProblemCode.quotaExceeded),
    ('messages', 'envelope', MailProblemCode.quotaExceeded),
    ('messages', 'remote', MailProblemCode.storageFailure),
    ('cached_messages', 'raw_hash', MailProblemCode.storageFailure),
  ]) {
    test(
      'load preflights oversized $column before SQLite transfers it',
      () async {
        await store.close();
        final database = sqlite.sqlite3.open(file.path);
        database.execute('UPDATE $table SET $column=?', ['x' * (1024 * 1024)]);
        database.close();
        store = await open(
          limits: const MailStoreLimits(maxMetadataCodeUnits: 4096),
        );
        probe.reset();
        _problem(await store.loadCachedMessage(_account, _header.id), code);
        expect(probe.maximumText, lessThan(4096));
        expect(probe.blobRead, isFalse);
      },
    );
  }

  for (final (table, column) in [
    ('cached_messages', 'data'),
    ('messages', 'envelope'),
    ('messages', 'remote'),
    ('cached_messages', 'raw_hash'),
  ]) {
    test(
      'load rejects non-text $column before metadata or blobs are read',
      () async {
        await store.close();
        final database = sqlite.sqlite3.open(file.path);
        database.execute('UPDATE $table SET $column=?', [
          Uint8List(1024 * 1024),
        ]);
        database.close();
        store = await open();
        probe.reset();
        _problem(
          await store.loadCachedMessage(_account, _header.id),
          MailProblemCode.storageFailure,
        );
        expect(probe.maximumText, lessThan(4096));
        expect(probe.blobRead, isFalse);
      },
    );
  }

  test(
    'browse refresh rejects oversized cached JSON before transfer and rolls back',
    () async {
      await store.close();
      final database = sqlite.sqlite3.open(file.path);
      database.execute('UPDATE cached_messages SET data=?', [
        'x' * (1024 * 1024),
      ]);
      database.close();
      store = await open(
        limits: const MailStoreLimits(maxMetadataCodeUnits: 4096),
      );
      probe.reset();
      _problem(await refresh(), MailProblemCode.quotaExceeded);
      expect(probe.maximumText, lessThan(4096));
      expect(probe.blobRead, isFalse);
      expect(_value(await store.loadMailboxView(_box.id))!.revision, 1);
      // Explicit cleanup does not need to parse corrupt cached body metadata.
      expect(_value(await store.clearMailboxCache(_account)).evictedBodies, 1);
    },
  );

  test(
    'browse refresh rejects non-text cached metadata before transfer',
    () async {
      await store.close();
      final database = sqlite.sqlite3.open(file.path);
      database.execute('UPDATE cached_messages SET data=?', [
        Uint8List(1024 * 1024),
      ]);
      database.close();
      store = await open();
      probe.reset();
      _problem(await refresh(), MailProblemCode.storageFailure);
      expect(probe.blobRead, isFalse);
      expect(_value(await store.loadMailboxView(_box.id))!.revision, 1);
    },
  );

  for (final name in ['body', 'attachment metadata']) {
    test(
      'lower decoded budget rejects existing $name before reading blob bytes',
      () async {
        if (name == 'body') {
          await cache(body: 'x' * 5000);
        } else {
          await cache(attachmentName: 'x' * 5000);
        }
        await reopenWithSmallBudget();
        _problem(
          await store.loadCachedMessage(_account, _header.id),
          MailProblemCode.quotaExceeded,
        );
        expect(probe.blobRead, isFalse);
        _problem(await refresh(), MailProblemCode.quotaExceeded);
        expect(probe.blobRead, isFalse);
        expect(_value(await store.loadMailboxView(_box.id))!.revision, 1);
      },
    );
  }

  for (final (name, text) in [
    ('control-heavy JSON', '\u0001' * 3000),
    ('quote-heavy JSON', '"\\' * 1500),
    ('non-ASCII JSON', 'م漢é' * 1000),
  ]) {
    test(
      'previously valid $name remains readable with the same semantic budget',
      () async {
        await reopenWithSmallBudget();
        await cache(body: text);
        await reopenWithSmallBudget();
        final loaded = _value(
          await store.loadCachedMessage(_account, _header.id),
        )!;
        expect(loaded.body.plainText, text);
        expect(loaded.raw.bytes, [10, 20, 30]);
        expect(loaded.attachments.single.content.bytes, [40, 50, 60]);
        expect(_value(await refresh()).revision, 2);
      },
    );
  }

  test(
    'bounded malformed JSON fails explicitly before raw or attachment reads',
    () async {
      await store.close();
      final database = sqlite.sqlite3.open(file.path);
      database.execute('UPDATE cached_messages SET data=?', ['not valid JSON']);
      database.close();
      store = await open();
      probe.reset();
      _problem(
        await store.loadCachedMessage(_account, _header.id),
        MailProblemCode.storageFailure,
      );
      expect(probe.blobRead, isFalse);
      _problem(await refresh(), MailProblemCode.storageFailure);
      expect(probe.blobRead, isFalse);
    },
  );
}
