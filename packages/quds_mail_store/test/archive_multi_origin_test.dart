@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _failure<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

void main() {
  late sqlite.Database database;
  late SqliteMailArchive archive;
  MailArchiveFaultInjector? fault;
  final message = MailMessage(
    raw: MailBytes(
      Uint8List.fromList(utf8.encode('Subject: Atomic\r\n\r\nOriginal')),
    ),
    envelope: MailEnvelope(subject: 'Atomic'),
    body: const MailBody(plainText: 'Indexed original'),
  );
  const origins = [
    MailArchiveOrigin(source: 'One', folder: '/Inbox', sourceMessageId: 'a'),
    MailArchiveOrigin(source: 'Two', folder: '/Saved', sourceMessageId: 'b'),
    MailArchiveOrigin(source: 'Three', folder: '/Copy', sourceMessageId: 'c'),
  ];

  Future<void> open({
    MailArchiveLimits limits = const MailArchiveLimits(),
  }) async {
    archive = _value(
      await SqliteMailArchive.open(
        executor: NativeDatabase.opened(
          database,
          closeUnderlyingOnClose: false,
        ),
        profile: MailProfileId('multi-origin', hostId: 'tests'),
        limits: limits,
        faultInjector: (point) async => fault?.call(point),
      ),
    );
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = sqlite.sqlite3.openInMemory();
    fault = null;
    await open();
  });

  tearDown(() async {
    await archive.close();
    database.close();
  });

  test(
    'multi-origin write is one original and one index with exact provenance count',
    () async {
      final added = _value(
        await archive.archiveMessageWithOrigins(message, origins: origins),
      );
      expect(added.duplicate, isFalse);
      expect(added.originAdded, isTrue);
      expect(added.originsAdded, 3);
      final repeated = _value(
        await archive.archiveMessageWithOrigins(message, origins: origins),
      );
      expect(repeated.duplicate, isTrue);
      expect(repeated.originAdded, isFalse);
      expect(repeated.originsAdded, 0);
      final stats = _value(await archive.statistics());
      expect(stats.messages, 1);
      expect(stats.indexedMessages, 1);
      expect(stats.origins, 3);
    },
  );

  test('normalized repeated origins coalesce without overcounting', () async {
    final added = _value(
      await archive.archiveMessageWithOrigins(
        message,
        origins: [
          origins.first,
          const MailArchiveOrigin(
            source: 'One',
            folder: r'\Inbox\',
            sourceMessageId: 'a',
          ),
          origins.first,
        ],
      ),
    );
    expect(added.originsAdded, 1);
    expect(
      _value(await archive.listOrigins(message.raw.sha256)).single.folder,
      '/Inbox',
    );
  });

  test('invalid later origin rejects the entire new message', () async {
    _failure(
      await archive.archiveMessageWithOrigins(
        message,
        origins: [
          origins.first,
          const MailArchiveOrigin(source: 'Invalid', folder: '/bad/../folder'),
        ],
      ),
      MailProblemCode.invalidInput,
    );
    expect(_value(await archive.statistics()).messages, 0);
    expect(_value(await archive.statistics()).origins, 0);
  });

  test('empty provenance is rejected without an orphan original', () async {
    _failure(
      await archive.archiveMessageWithOrigins(message, origins: const []),
      MailProblemCode.invalidInput,
    );
    expect(_value(await archive.statistics()).messages, 0);
  });

  test(
    'commit fault rolls back original, all origins and FTS content',
    () async {
      fault = (point) async {
        if (point == MailArchiveCheckpoint.beforeCommit) {
          throw StateError('injected');
        }
      };
      _failure(
        await archive.archiveMessageWithOrigins(message, origins: origins),
        MailProblemCode.storageFailure,
      );
      expect(_value(await archive.statistics()).messages, 0);
      expect(_value(await archive.statistics()).origins, 0);
      expect(
        _value(
          await archive.search(
            const MailArchiveSearchRequest(query: 'Indexed'),
          ),
        ).total,
        0,
      );
    },
  );

  test(
    'late cancellation rolls back every new origin on an existing original',
    () async {
      _value(await archive.archiveMessage(message, origin: origins.first));
      final cancellation = MailCancellationSource();
      fault = (point) async {
        if (point == MailArchiveCheckpoint.beforeCommit) cancellation.cancel();
      };
      _failure(
        await archive.archiveMessageWithOrigins(
          message,
          origins: origins,
          cancellation: cancellation.token,
        ),
        MailProblemCode.cancelled,
      );
      expect(_value(await archive.statistics()).messages, 1);
      expect(_value(await archive.listOrigins(message.raw.sha256)).length, 1);
      expect(
        _value(await archive.loadOriginal(message.raw.sha256))!.bytes,
        message.raw.bytes,
      );
    },
  );

  test('global origin quota rolls back additions on existing content', () async {
    await archive.close();
    await open(limits: const MailArchiveLimits(maxMessages: 1, maxOrigins: 2));
    _value(await archive.archiveMessage(message, origin: origins.first));
    // The request fits the per-call origin count, but its union exceeds quota.
    _failure(
      await archive.archiveMessageWithOrigins(
        message,
        origins: origins.sublist(1),
      ),
      MailProblemCode.quotaExceeded,
    );
    expect(_value(await archive.statistics()).origins, 1);
    expect(
      _value(await archive.listOrigins(message.raw.sha256)).single.source,
      'One',
    );
  });

  test(
    'origin list is copied before asynchronous storage can observe caller edits',
    () async {
      final mutable = [origins.first, origins[1]];
      final pending = archive.archiveMessageWithOrigins(
        message,
        origins: mutable,
      );
      mutable.clear();
      final result = _value(await pending);
      expect(result.originsAdded, 2);
      expect(_value(await archive.statistics()).origins, 2);
    },
  );

  test('single-origin API retains legacy result semantics', () async {
    final first = _value(
      await archive.archiveMessage(message, origin: origins.first),
    );
    expect(first.originAdded, isTrue);
    expect(first.originsAdded, 1);
    final second = _value(
      await archive.archiveMessage(message, origin: origins.first),
    );
    expect(second.originAdded, isFalse);
    expect(second.originsAdded, 0);
  });
}
