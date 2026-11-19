@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_store/src/archive_database.dart';
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

const _origins = [
  MailArchiveOrigin(source: 'Personal', folder: '/Inbox', sourceMessageId: 'a'),
  MailArchiveOrigin(source: 'Backup', folder: '/Saved', sourceMessageId: 'b'),
  MailArchiveOrigin(source: 'أرشيف', folder: '/قديم', sourceMessageId: 'c'),
];

MailMessage _message(
  String key, {
  List<MailAttachment> attachments = const [],
}) => MailMessage(
  raw: MailBytes(Uint8List.fromList(utf8.encode('Subject: $key\r\n\r\n$key'))),
  envelope: MailEnvelope(subject: key),
  body: MailBody(plainText: 'Searchable checkpoint $key'),
  attachments: attachments,
);

MailArchiveRestorePlan _plan(
  List<MailMessage> messages, {
  int revision = 0,
  List<MailArchiveOrigin> origins = _origins,
  String directory = '/source/export',
}) => MailArchiveRestorePlan.fromManifest(
  directoryPath: directory,
  manifest: encodeMailArchiveExportManifest(
    MailArchiveExportPlan(
      profile: MailProfileId('old-profile', hostId: 'different-source-host'),
      createdAt: DateTime.utc(2026, 11, 19).add(Duration(seconds: revision)),
      items: [
        for (final message in messages)
          MailArchiveExportItem(
            id: message.raw.sha256,
            byteLength: message.raw.length,
            origins: origins,
          ),
      ],
    ),
    const MailArchiveExportLimits(),
  ),
);

void main() {
  late sqlite.Database database;
  late SqliteMailArchive archive;
  MailArchiveFaultInjector? fault;
  final first = _message('First');
  final second = _message('Second');
  final third = _message('Third');
  final plan = _plan([first, second, third]);
  final destination = MailProfileId('destination', hostId: 'restore-tests');

  Future<void> open({
    MailArchiveLimits limits = const MailArchiveLimits(),
  }) async {
    archive = _value(
      await SqliteMailArchive.open(
        executor: NativeDatabase.opened(
          database,
          closeUnderlyingOnClose: false,
        ),
        profile: destination,
        limits: limits,
        faultInjector: (point) async => fault?.call(point),
      ),
    );
  }

  Future<MailArchiveImportResult> restore(
    MailMessage message,
    int ordinal, {
    MailArchiveRestorePlan? selection,
    bool warning = false,
  }) async => _value(
    await archive.archiveRestoreMessage(
      message,
      plan: selection ?? plan,
      ordinal: ordinal,
      indexWarning: warning,
    ),
  );

  int count(String table) =>
      database.select('SELECT count(*) AS n FROM $table').single['n'] as int;
  int total(String column) =>
      database.select('SELECT $column FROM archive_totals').single[column]
          as int;
  List<Map<String, Object?>> rows(String table) => [
    for (final row in database.select('SELECT * FROM $table'))
      Map<String, Object?>.from(row),
  ];

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
    'fresh archive has no checkpoint and reads do not create metadata',
    () async {
      expect(_value(await archive.restoreCheckpoint(plan)), isNull);
      expect(_value(await archive.loadRestoreReceipt(plan, 1)), isNull);
      expect(_value(await archive.listRestoreCheckpoints()), isEmpty);
      expect(count('archive_restore_jobs'), 0);
      expect(count('archive_restore_receipts'), 0);
      expect(total('logical_bytes'), 0);
    },
  );

  test(
    'one-based noncontiguous receipts survive reopen with exact counts',
    () async {
      await restore(third, 3);
      await restore(first, 1, warning: true);
      await archive.close();
      await open();
      final checkpoint = _value(await archive.restoreCheckpoint(plan))!;
      expect(checkpoint.manifestSha256, plan.manifestSha256);
      expect(checkpoint.planned, 3);
      expect(checkpoint.totalBytes, plan.totalBytes);
      expect(checkpoint.completedMessages, 2);
      expect(checkpoint.completedBytes, first.raw.length + third.raw.length);
      final receipt = _value(await archive.loadRestoreReceipt(plan, 1))!;
      expect(receipt.ordinal, 1);
      expect(receipt.byteLength, first.raw.length);
      expect(receipt.indexWarning, isTrue);
      expect(_value(await archive.loadRestoreReceipt(plan, 2)), isNull);
      expect(
        _value(await archive.loadRestoreReceipt(plan, 3))!.indexWarning,
        isFalse,
      );
      expect(
        _value(await archive.listRestoreCheckpoints()).single.completedMessages,
        2,
      );
      expect(total('restore_jobs'), 1);
      expect(total('restore_receipts'), 2);
    },
  );

  test(
    'repeated commits preserve receipt identity and all prior origins',
    () async {
      _value(await archive.archiveMessage(first, origin: _origins.first));
      final initial = await restore(first, 1, warning: true);
      expect(initial.duplicate, isTrue);
      expect(initial.originsAdded, 2);
      final before = total('logical_bytes');
      final repeated = await restore(first, 1);
      expect(repeated.duplicate, isTrue);
      expect(repeated.originsAdded, 0);
      expect(repeated.entry.archivedAt, initial.entry.archivedAt);
      expect(total('logical_bytes'), before);
      expect(count('archive_items'), 1);
      expect(count('archive_origins'), 3);
      expect(count('archive_restore_receipts'), 1);
      expect(
        _value(await archive.loadRestoreReceipt(plan, 1))!.indexWarning,
        isTrue,
      );
    },
  );

  test('receipts retain warnings from skipped attachment text', () async {
    final message = _message(
      'Attachment',
      attachments: [
        MailAttachment(
          partPath: '1',
          mediaType: 'application/pdf',
          displayName: 'document.pdf',
          content: MailBytes(Uint8List.fromList([1, 2, 3])),
        ),
      ],
    );
    final selection = _plan([message]);
    await restore(message, 1, selection: selection);
    expect(
      _value(await archive.loadRestoreReceipt(selection, 1))!.indexWarning,
      isTrue,
    );
  });

  for (final ordinal in [-1, 0, 4]) {
    test(
      'invalid one-based ordinal $ordinal cannot create a receipt',
      () async {
        _failure(
          await archive.archiveRestoreMessage(
            first,
            plan: plan,
            ordinal: ordinal,
          ),
          MailProblemCode.invalidInput,
        );
        _failure(
          await archive.loadRestoreReceipt(plan, ordinal),
          MailProblemCode.invalidInput,
        );
        expect(count('archive_items'), 0);
        expect(count('archive_restore_jobs'), 0);
      },
    );
  }

  test(
    'mismatched message size or hash cannot satisfy another ordinal',
    () async {
      for (final wrong in [_message('Wrong'), second]) {
        _failure(
          await archive.archiveRestoreMessage(wrong, plan: plan, ordinal: 1),
          MailProblemCode.conflict,
        );
      }
      expect(count('archive_items'), 0);
      expect(count('archive_restore_receipts'), 0);
    },
  );

  test(
    'empty selection has no work and cannot manufacture a completion',
    () async {
      final empty = _plan([]);
      expect(_value(await archive.restoreCheckpoint(empty)), isNull);
      _failure(
        await archive.loadRestoreReceipt(empty, 1),
        MailProblemCode.invalidInput,
      );
      _failure(
        await archive.archiveRestoreMessage(first, plan: empty, ordinal: 1),
        MailProblemCode.invalidInput,
      );
      expect(count('archive_restore_jobs'), 0);
    },
  );

  test(
    'version-one migration preserves originals, origins and FTS bytes',
    () async {
      _value(await archive.archiveMessageWithOrigins(first, origins: _origins));
      final content = {
        for (final table in [
          'archive_owner',
          'archive_items',
          'archive_origins',
          'archive_fts',
        ])
          table: rows(table),
      };
      await archive.close();
      final oldDatabase = sqlite.sqlite3.openInMemory();
      for (final statement in mailArchiveSchemaV1) {
        oldDatabase.execute(statement);
      }
      for (final entry in content.entries) {
        for (final row in entry.value) {
          oldDatabase.execute(
            'INSERT INTO ${entry.key}(${row.keys.join(',')}) '
            'VALUES(${List.filled(row.length, '?').join(',')})',
            row.values.toList(),
          );
        }
      }
      oldDatabase.execute('PRAGMA user_version=1');
      database.close();
      database = oldDatabase;
      final shadowBefore = rows('archive_fts_data');
      final logicalBefore = total('logical_bytes');
      await open();
      expect(database.select('PRAGMA user_version').single.values.single, 2);
      for (final entry in content.entries) {
        expect(rows(entry.key), entry.value);
      }
      expect(rows('archive_fts_data'), shadowBefore);
      expect(total('logical_bytes'), logicalBefore);
      expect(total('restore_jobs'), 0);
      expect(total('restore_receipts'), 0);
      expect(
        _value(await archive.loadOriginal(first.raw.sha256))!.bytes,
        first.raw.bytes,
      );
      expect(
        _value(
          await archive.search(
            const MailArchiveSearchRequest(query: 'Searchable'),
          ),
        ).total,
        1,
      );
      expect((await restore(first, 1)).duplicate, isTrue);
      expect(_value(await archive.loadRestoreReceipt(plan, 1)), isNotNull);
    },
  );

  for (final point in MailArchiveCheckpoint.values) {
    test(
      'fault at ${point.name} rolls back original, index, origins and receipt',
      () async {
        fault = (observed) async {
          if (observed == point) throw StateError('injected restore failure');
        };
        _failure(
          await archive.archiveRestoreMessage(first, plan: plan, ordinal: 1),
          MailProblemCode.storageFailure,
        );
        for (final table in [
          'archive_items',
          'archive_origins',
          'archive_fts',
          'archive_restore_jobs',
          'archive_restore_receipts',
        ]) {
          expect(count(table), 0, reason: table);
        }
        expect(total('logical_bytes'), 0);
        expect(total('restore_jobs'), 0);
        expect(total('restore_receipts'), 0);
      },
    );
  }

  test(
    'late cancellation rolls back new origins and receipt on a duplicate',
    () async {
      _value(await archive.archiveMessage(first, origin: _origins.first));
      final logicalBefore = total('logical_bytes');
      final indexBefore = rows('archive_fts');
      final cancellation = MailCancellationSource();
      fault = (point) async {
        if (point == MailArchiveCheckpoint.beforeCommit) cancellation.cancel();
      };
      _failure(
        await archive.archiveRestoreMessage(
          first,
          plan: plan,
          ordinal: 1,
          cancellation: cancellation.token,
        ),
        MailProblemCode.cancelled,
      );
      expect(count('archive_items'), 1);
      expect(count('archive_origins'), 1);
      expect(count('archive_restore_jobs'), 0);
      expect(count('archive_restore_receipts'), 0);
      expect(total('logical_bytes'), logicalBefore);
      expect(rows('archive_fts'), indexBefore);
    },
  );

  test(
    'receipt quota rolls back new content and permits duplicate retries',
    () async {
      await archive.close();
      await open(limits: const MailArchiveLimits(maxRestoreReceipts: 1));
      await restore(first, 1);
      _failure(
        await archive.archiveRestoreMessage(second, plan: plan, ordinal: 2),
        MailProblemCode.quotaExceeded,
      );
      expect(count('archive_items'), 1);
      expect(count('archive_fts'), 1);
      expect(count('archive_restore_jobs'), 1);
      expect(count('archive_restore_receipts'), 1);
      expect(
        _value(await archive.restoreCheckpoint(plan))!.completedMessages,
        1,
      );
      expect((await restore(first, 1)).duplicate, isTrue);
      _value(await archive.forgetRestoreCheckpoint(plan.manifestSha256));
      await restore(second, 2);
      expect(count('archive_items'), 2);
      expect(count('archive_restore_receipts'), 1);
    },
  );

  test(
    'job quota never evicts old progress or adds duplicate provenance',
    () async {
      await archive.close();
      await open(limits: const MailArchiveLimits(maxRestoreJobs: 1));
      final oldPlan = _plan([first], origins: [_origins.first]);
      final newPlan = _plan([first], revision: 1);
      await restore(first, 1, selection: oldPlan);
      _failure(
        await archive.archiveRestoreMessage(first, plan: newPlan, ordinal: 1),
        MailProblemCode.quotaExceeded,
      );
      expect(count('archive_origins'), 1);
      expect(_value(await archive.restoreCheckpoint(newPlan)), isNull);
      expect(_value(await archive.loadRestoreReceipt(oldPlan, 1)), isNotNull);
      _value(await archive.forgetRestoreCheckpoint(oldPlan.manifestSha256));
      expect((await restore(first, 1, selection: newPlan)).originsAdded, 2);
    },
  );

  test(
    'fixed metadata bytes are counted once and released by cleanup',
    () async {
      _value(await archive.archiveMessageWithOrigins(first, origins: _origins));
      final originalBytes = total('logical_bytes');
      await restore(first, 1);
      expect(total('logical_bytes'), originalBytes + 192 + 256);
      await restore(first, 1);
      expect(total('logical_bytes'), originalBytes + 192 + 256);
      _value(await archive.forgetRestoreCheckpoint(plan.manifestSha256));
      expect(total('logical_bytes'), originalBytes);
      expect(total('restore_jobs'), 0);
      expect(total('restore_receipts'), 0);
    },
  );

  test('logical byte quota includes receipt metadata atomically', () async {
    _value(await archive.archiveMessageWithOrigins(first, origins: _origins));
    final originalBytes = total('logical_bytes');
    await archive.close();
    await open(
      limits: MailArchiveLimits(
        maxMessageBytes: 128,
        maxArchiveBytes: originalBytes + 192 + 255,
      ),
    );
    _failure(
      await archive.archiveRestoreMessage(first, plan: plan, ordinal: 1),
      MailProblemCode.quotaExceeded,
    );
    expect(total('logical_bytes'), originalBytes);
    expect(count('archive_restore_jobs'), 0);
    expect(count('archive_restore_receipts'), 0);
    expect(count('archive_origins'), 3);
  });

  test('missing expected provenance requires an atomic retry repair', () async {
    await restore(first, 1);
    database.execute(
      'DELETE FROM archive_origins WHERE message=? AND source=?',
      [first.raw.sha256, 'Backup'],
    );
    expect(_value(await archive.loadRestoreReceipt(plan, 1)), isNull);
    final repaired = await restore(first, 1);
    expect(repaired.duplicate, isTrue);
    expect(repaired.originsAdded, 1);
    expect(count('archive_origins'), 3);
    expect(count('archive_restore_receipts'), 1);
    expect(_value(await archive.loadRestoreReceipt(plan, 1)), isNotNull);
  });

  for (final damage in ['size', 'message', 'ordinal', 'job']) {
    test(
      'corrupted $damage metadata never authorizes a completed receipt',
      () async {
        await restore(first, 1);
        if (damage == 'size') {
          database.execute(
            'UPDATE archive_restore_receipts SET byte_length=byte_length+1',
          );
        } else if (damage == 'message') {
          _value(await archive.archiveMessage(second, origin: _origins.first));
          database.execute('UPDATE archive_restore_receipts SET message=?', [
            second.raw.sha256,
          ]);
        } else if (damage == 'ordinal') {
          database.execute('UPDATE archive_restore_receipts SET ordinal=2');
        } else {
          database.execute(
            'UPDATE archive_restore_jobs SET total_bytes=total_bytes+1',
          );
        }
        _failure(
          await archive.restoreCheckpoint(plan),
          MailProblemCode.conflict,
        );
        _failure(
          await archive.loadRestoreReceipt(plan, damage == 'ordinal' ? 2 : 1),
          MailProblemCode.conflict,
        );
      },
    );
  }

  for (final damage in [
    'raw',
    'metadata',
    'missing index',
    'stale index',
    'duplicate index',
  ]) {
    test('damaged destination $damage fails receipt reuse', () async {
      await restore(first, 1);
      if (damage == 'raw') {
        database.execute('UPDATE archive_items SET raw=?', [
          Uint8List(first.raw.length),
        ]);
      } else if (damage == 'metadata') {
        database.execute("UPDATE archive_items SET subject='Changed'");
      } else if (damage == 'missing index') {
        database.execute('DELETE FROM archive_fts');
      } else if (damage == 'stale index') {
        database.execute("UPDATE archive_fts SET body='Changed'");
      } else {
        database.execute('INSERT INTO archive_fts SELECT * FROM archive_fts');
      }
      _failure(
        await archive.loadRestoreReceipt(plan, 1),
        damage == 'raw' || damage == 'metadata'
            ? MailProblemCode.storageFailure
            : MailProblemCode.conflict,
      );
      expect(count('archive_restore_receipts'), 1);
    });
  }

  test('receipt relation prevents deleting its original', () async {
    await restore(first, 1);
    expect(
      () => database.execute('DELETE FROM archive_items'),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(_value(await archive.loadRestoreReceipt(plan, 1)), isNotNull);
  });

  test(
    'forgetting progress preserves every original, origin and search row',
    () async {
      await restore(first, 1);
      await restore(third, 3);
      final originalRows = rows('archive_items');
      final originRows = rows('archive_origins');
      final indexRows = rows('archive_fts');
      _value(await archive.forgetRestoreCheckpoint(plan.manifestSha256));
      expect(rows('archive_items'), originalRows);
      expect(rows('archive_origins'), originRows);
      expect(rows('archive_fts'), indexRows);
      expect(_value(await archive.restoreCheckpoint(plan)), isNull);
      expect(_value(await archive.loadRestoreReceipt(plan, 1)), isNull);
      expect(count('archive_restore_jobs'), 0);
      expect(count('archive_restore_receipts'), 0);
      expect((await restore(first, 1)).duplicate, isTrue);
    },
  );

  test(
    'cleanup cancellation preserves the complete checkpoint transaction',
    () async {
      await restore(first, 1);
      final before = total('logical_bytes');
      final cancellation = MailCancellationSource();
      fault = (point) async {
        if (point == MailArchiveCheckpoint.beforeCommit) cancellation.cancel();
      };
      _failure(
        await archive.forgetRestoreCheckpoint(
          plan.manifestSha256,
          cancellation: cancellation.token,
        ),
        MailProblemCode.cancelled,
      );
      expect(total('logical_bytes'), before);
      expect(_value(await archive.loadRestoreReceipt(plan, 1)), isNotNull);
    },
  );

  test(
    'explicit cleanup remains possible under tighter reopened limits',
    () async {
      final otherPlan = _plan([first], revision: 1);
      await restore(first, 1);
      await restore(first, 1, selection: otherPlan);
      await archive.close();
      await open(
        limits: const MailArchiveLimits(
          maxRestoreJobs: 1,
          maxRestoreReceipts: 1,
        ),
      );
      final retained = _value(await archive.listRestoreCheckpoints());
      expect(retained, hasLength(2));
      expect(
        retained.map((entry) => entry.manifestSha256),
        containsAll([plan.manifestSha256, otherPlan.manifestSha256]),
      );
      expect(
        retained.fold<int>(
          0,
          (count, entry) => count + entry.completedMessages,
        ),
        2,
      );
      _value(await archive.forgetRestoreCheckpoint(plan.manifestSha256));
      expect(
        _value(await archive.listRestoreCheckpoints()).single.manifestSha256,
        otherPlan.manifestSha256,
      );
      _value(await archive.forgetRestoreCheckpoint(otherPlan.manifestSha256));
      expect(count('archive_items'), 1);
    },
  );

  test(
    'cancelled reads report cancellation without modifying receipts',
    () async {
      await restore(first, 1);
      final cancellation = MailCancellationSource()..cancel();
      _failure(
        await archive.restoreCheckpoint(plan, cancellation: cancellation.token),
        MailProblemCode.cancelled,
      );
      _failure(
        await archive.listRestoreCheckpoints(cancellation: cancellation.token),
        MailProblemCode.cancelled,
      );
      _failure(
        await archive.loadRestoreReceipt(
          plan,
          1,
          cancellation: cancellation.token,
        ),
        MailProblemCode.cancelled,
      );
      expect(_value(await archive.loadRestoreReceipt(plan, 1)), isNotNull);
    },
  );

  test(
    'source path changes retain identity while manifest changes isolate work',
    () async {
      await restore(first, 1);
      final moved = _plan([first, second, third], directory: '/new/location');
      final changed = _plan([first, second, third], revision: 1);
      expect(moved.manifestSha256, plan.manifestSha256);
      expect(_value(await archive.loadRestoreReceipt(moved, 1)), isNotNull);
      expect(changed.manifestSha256, isNot(plan.manifestSha256));
      expect(_value(await archive.restoreCheckpoint(changed)), isNull);
      expect(_value(await archive.loadRestoreReceipt(changed, 1)), isNull);
    },
  );

  test(
    'same exported manifest has independent progress in two destination profiles',
    () async {
      await restore(first, 1);
      final other = _value(
        await SqliteMailArchive.open(
          executor: NativeDatabase.memory(),
          profile: MailProfileId('other-destination', hostId: 'restore-tests'),
        ),
      );
      try {
        expect(_value(await other.restoreCheckpoint(plan)), isNull);
        expect(_value(await other.loadRestoreReceipt(plan, 1)), isNull);
        expect(
          _value(
            await other.archiveRestoreMessage(first, plan: plan, ordinal: 1),
          ).duplicate,
          isFalse,
        );
        _value(await archive.forgetRestoreCheckpoint(plan.manifestSha256));
        expect(_value(await other.loadRestoreReceipt(plan, 1)), isNotNull);
        expect(_value(await archive.loadRestoreReceipt(plan, 1)), isNull);
      } finally {
        await other.close();
      }
    },
  );

  test(
    'overlapping duplicate writes converge on one original and one receipt',
    () async {
      final results = await Future.wait([
        archive.archiveRestoreMessage(first, plan: plan, ordinal: 1),
        archive.archiveRestoreMessage(first, plan: plan, ordinal: 1),
      ]);
      expect(
        results.map(_value).where((result) => !result.duplicate),
        hasLength(1),
      );
      expect(count('archive_items'), 1);
      expect(count('archive_origins'), 3);
      expect(total('restore_jobs'), 1);
      expect(total('restore_receipts'), 1);
      expect(
        _value(await archive.restoreCheckpoint(plan))!.completedMessages,
        1,
      );
    },
  );

  test(
    'checkpoint limits reject invalid zero and unbounded configurations',
    () {
      expect(const MailArchiveLimits().maxRestoreJobs, 64);
      expect(const MailArchiveLimits().maxRestoreReceipts, 100000);
      for (final limits in [
        const MailArchiveLimits(maxRestoreJobs: 0),
        const MailArchiveLimits(maxRestoreReceipts: 0),
        const MailArchiveLimits(maxRestoreJobs: 10001),
        const MailArchiveLimits(maxRestoreReceipts: 1000001),
      ]) {
        expect(limits.isValid, isFalse);
      }
    },
  );
}
