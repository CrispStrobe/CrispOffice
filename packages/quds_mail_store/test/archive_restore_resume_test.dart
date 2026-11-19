@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

final class _CountingCodec implements MailCodec {
  int calls = 0;
  bool partial = false;

  @override
  MailParseResult parse(
    Uint8List bytes, {
    MailReadBudget budget = const MailReadBudget(),
    MailCancellationToken? cancellation,
  }) {
    calls++;
    cancellation?.throwIfCancelled();
    return MailParseResult(
      status: partial ? MailParseStatus.partial : MailParseStatus.complete,
      message: MailMessage(
        raw: MailBytes(bytes),
        envelope: MailEnvelope(subject: 'Resume test'),
        body: const MailBody(plainText: 'durable resume ledger'),
      ),
    );
  }
}

void main() {
  late Directory root;
  late Directory source;
  late sqlite.Database database;
  late SqliteMailArchive archive;
  late NativeMailArchiveRestorer restorer;
  late _CountingCodec codec;
  late List<MailBytes> originals;
  late MailArchiveRestorePlan plan;
  final profile = MailProfileId('destination', hostId: 'resume-tests');
  const origins = [
    MailArchiveOrigin(
      source: 'Private source',
      folder: '/Inbox',
      sourceMessageId: 'one',
    ),
    MailArchiveOrigin(
      source: 'Other source',
      folder: '/Sent',
      sourceMessageId: 'two',
    ),
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
        profile: profile,
        limits: limits,
      ),
    );
    codec = _CountingCodec();
    restorer = NativeMailArchiveRestorer(archive: archive, codec: codec);
  }

  File originalFile(int ordinal) =>
      File(p.join(source.path, '${originals[ordinal].sha256}.eml'));

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final temporary = await Directory.systemTemp.createTemp('restore-resume-');
    root = Directory(await temporary.resolveSymbolicLinks());
    source = await Directory(p.join(root.path, 'export')).create();
    database = sqlite.sqlite3.openInMemory();
    originals = [
      for (var i = 0; i < 3; i++)
        MailBytes(
          Uint8List.fromList(
            utf8.encode('Subject: Original $i\r\n\r\nBody $i\r\n'),
          ),
        ),
    ];
    final export = MailArchiveExportPlan(
      profile: MailProfileId('old-profile', hostId: 'old-device'),
      createdAt: DateTime.utc(2026, 11, 19),
      items: [
        for (final original in originals)
          MailArchiveExportItem(
            id: original.sha256,
            byteLength: original.length,
            origins: origins,
          ),
      ],
    );
    await File(p.join(source.path, 'manifest.json')).writeAsString(
      encodeMailArchiveExportManifest(export, const MailArchiveExportLimits()),
    );
    for (var i = 0; i < originals.length; i++) {
      await originalFile(i).writeAsBytes(originals[i].bytes);
    }
    await open();
    plan = _value(await restorer.inspect(source));
  });

  tearDown(() async {
    await archive.close();
    database.close();
    await root.delete(recursive: true);
  });

  test(
    'reopened destination resumes without reading committed source files',
    () async {
      final cancel = MailCancellationSource();
      final first = await restorer.restore(
        plan,
        cancellation: cancel.token,
        onProgress: (event) {
          if (event.saved == 1) cancel.cancel();
        },
      );
      expect(first.status, MailArchiveRestoreStatus.cancelled);
      expect(first.saved, 1);
      await archive.close();
      await open();
      plan = _value(await restorer.inspect(source));
      expect(plan.checkpoint?.completedMessages, 1);
      expect(plan.checkpoint?.completedBytes, originals.first.length);
      await originalFile(0).delete();
      final events = <MailArchiveRestoreProgress>[];
      final resumed = await restorer.restore(
        plan,
        resume: true,
        onProgress: events.add,
      );
      expect(resumed.status, MailArchiveRestoreStatus.completed);
      expect(
        (resumed.saved, resumed.duplicates, resumed.resumed, resumed.processed),
        (2, 0, 1, 3),
      );
      expect(resumed.bytes, originals[1].length + originals[2].length);
      expect(resumed.resumedBytes, originals.first.length);
      expect(codec.calls, 2);
      expect(events.last.processed, 3);
      expect(events.last.toJson()['resumed'], 1);
      expect(_value(await archive.statistics()).origins, 6);
      expect(
        _value(await archive.restoreCheckpoint(plan))?.completedMessages,
        3,
      );
      final logged = jsonEncode(events.map((event) => event.toJson()).toList());
      expect(logged, isNot(contains(source.path)));
      expect(logged, isNot(contains('Private source')));
      expect(logged, isNot(contains(plan.manifestSha256)));
    },
  );

  test('sparse successful receipts retry a failed middle item only', () async {
    await originalFile(1).delete();
    final first = await restorer.restore(plan);
    expect((first.saved, first.failed), (2, 1));
    expect(first.status, MailArchiveRestoreStatus.partial);
    expect(_value(await archive.restoreCheckpoint(plan))?.completedMessages, 2);
    await originalFile(1).writeAsBytes(originals[1].bytes);
    await originalFile(0).delete();
    await originalFile(2).delete();
    codec.calls = 0;
    final next = await restorer.restore(plan, resume: true);
    expect(next.status, MailArchiveRestoreStatus.completed);
    expect((next.saved, next.resumed, next.failed), (1, 2, 0));
    expect(codec.calls, 1);
  });

  test(
    'moving an unchanged export retains progress, full verification still reads it',
    () async {
      expect((await restorer.restore(plan)).saved, 3);
      source = await source.rename(p.join(root.path, 'moved'));
      final moved = _value(await restorer.inspect(source));
      expect(moved.manifestSha256, plan.manifestSha256);
      expect(moved.checkpoint?.completedMessages, 3);
      await originalFile(0).delete();
      codec.calls = 0;
      final resumed = await restorer.restore(moved, resume: true);
      expect(
        (resumed.resumed, resumed.saved, resumed.duplicates, codec.calls),
        (3, 0, 0, 0),
      );
      final verified = await restorer.restore(moved);
      expect(verified.status, MailArchiveRestoreStatus.partial);
      expect(
        (verified.resumed, verified.duplicates, verified.failed),
        (0, 2, 1),
      );
      expect(codec.calls, 2);
    },
  );

  test(
    'a supplied preview count cannot manufacture a destination receipt',
    () async {
      final forged = plan.withCheckpoint(
        MailArchiveRestoreCheckpoint(
          manifestSha256: plan.manifestSha256,
          planned: 3,
          totalBytes: plan.totalBytes,
          completedMessages: 3,
          completedBytes: plan.totalBytes,
        ),
      );
      final report = await restorer.restore(forged, resume: true);
      expect((report.saved, report.resumed, codec.calls), (3, 0, 3));
    },
  );

  test(
    'resume refuses corrupted destination originals before using their receipt',
    () async {
      expect((await restorer.restore(plan)).saved, 3);
      final changed = Uint8List.fromList(originals.first.bytes);
      changed[0] ^= 1;
      database.execute('UPDATE archive_items SET raw=? WHERE id=?', [
        changed,
        originals.first.sha256,
      ]);
      codec.calls = 0;
      final report = await restorer.restore(plan, resume: true);
      expect(report.status, MailArchiveRestoreStatus.failed);
      expect(report.problem?.code, MailProblemCode.storageFailure);
      expect((report.resumed, report.failed, codec.calls), (0, 1, 0));
    },
  );

  test(
    'missing provenance is repaired before the message is confirmed again',
    () async {
      expect((await restorer.restore(plan)).saved, 3);
      database.execute(
        'DELETE FROM archive_origins WHERE message=? AND source=?',
        [originals.first.sha256, origins.first.source],
      );
      codec.calls = 0;
      final report = await restorer.restore(plan, resume: true);
      expect(report.status, MailArchiveRestoreStatus.completed);
      expect(
        (report.resumed, report.duplicates, report.originsAdded, codec.calls),
        (2, 1, 1, 1),
      );
      expect(
        _value(await archive.listOrigins(originals.first.sha256)),
        hasLength(2),
      );
    },
  );

  test(
    'forgetting progress preserves originals and makes the next run verify all files',
    () async {
      expect((await restorer.restore(plan)).saved, 3);
      _value(await archive.forgetRestoreCheckpoint(plan.manifestSha256));
      expect(_value(await restorer.inspect(source)).checkpoint, isNull);
      expect(_value(await archive.statistics()).messages, 3);
      codec.calls = 0;
      final report = await restorer.restore(plan, resume: true);
      expect(
        (report.saved, report.duplicates, report.resumed, codec.calls),
        (0, 3, 0, 3),
      );
    },
  );

  test(
    'index warnings remain separate for resumed and current messages',
    () async {
      codec.partial = true;
      final first = await restorer.restore(plan);
      expect(first.indexWarnings, 3);
      codec.partial = false;
      codec.calls = 0;
      final report = await restorer.restore(
        plan,
        resume: true,
        indexAttachmentText: true,
      );
      expect(report.indexWarnings, 0);
      expect(report.resumedIndexWarnings, 3);
      expect(report.resumed, 3);
      expect(codec.calls, 0);
    },
  );

  test(
    'cancellation during confirmation preserves durable progress and exact run counts',
    () async {
      expect((await restorer.restore(plan)).saved, 3);
      final cancel = MailCancellationSource();
      final report = await restorer.restore(
        plan,
        resume: true,
        cancellation: cancel.token,
        onProgress: (event) {
          if (event.resumed == 1) cancel.cancel();
        },
      );
      expect(report.status, MailArchiveRestoreStatus.cancelled);
      expect((report.resumed, report.saved, report.processed), (1, 0, 1));
      expect(
        _value(await archive.restoreCheckpoint(plan))?.completedMessages,
        3,
      );
      expect((await restorer.restore(plan, resume: true)).resumed, 3);
    },
  );

  test(
    'exact manifest bytes bind progress and a changed confirmed preview is rejected',
    () async {
      expect((await restorer.restore(plan)).saved, 3);
      final manifest = File(p.join(source.path, 'manifest.json'));
      await manifest.writeAsString('${await manifest.readAsString()}\n');
      final stale = await restorer.restore(plan, resume: true);
      expect(stale.status, MailArchiveRestoreStatus.failed);
      expect(stale.problem?.code, MailProblemCode.conflict);
      expect(stale.processed, 0);
      final changed = _value(await restorer.inspect(source));
      expect(changed.checkpoint, isNull);
      final newSelection = await restorer.restore(changed, resume: true);
      expect((newSelection.resumed, newSelection.duplicates), (0, 3));
      expect(_value(await archive.listRestoreCheckpoints()), hasLength(2));
    },
  );

  test(
    'destination per-message bounds also apply to previously committed items',
    () async {
      expect((await restorer.restore(plan)).saved, 3);
      await archive.close();
      await open(limits: const MailArchiveLimits(maxMessageBytes: 1));
      final report = await restorer.restore(plan, resume: true);
      expect(report.problem?.code, MailProblemCode.quotaExceeded);
      expect(report.resumed, 0);
      expect(codec.calls, 0);
    },
  );
}
