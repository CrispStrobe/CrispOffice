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

T value<T>(MailResult<T> result) => (result as MailSuccess<T>).value;

void fails<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

void main() {
  late sqlite.Database database;
  late SqliteMailArchive archive;
  final profile = MailProfileId('portable', hostId: 'test');
  final now = DateTime.utc(2026, 11, 19, 12);

  Future<String> add(
    String subject, {
    String folder = '/Inbox',
    String source = 'Local',
    String? raw,
  }) async {
    final bytes = MailBytes(
      Uint8List.fromList(
        utf8.encode(raw ?? 'Subject: $subject\r\n\r\n$subject'),
      ),
    );
    return value(
      await archive.archiveMessage(
        MailMessage(
          raw: bytes,
          envelope: MailEnvelope(subject: subject, sentAt: now),
          body: MailBody(plainText: subject),
        ),
        origin: MailArchiveOrigin(
          source: source,
          folder: folder,
          sourceMessageId: subject,
        ),
      ),
    ).entry.id;
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = sqlite.sqlite3.openInMemory();
    archive = value(
      await SqliteMailArchive.open(
        executor: NativeDatabase.opened(
          database,
          closeUnderlyingOnClose: false,
        ),
        profile: profile,
        clock: () => now,
      ),
    );
  });

  tearDown(() async {
    await archive.close();
    database.close();
  });

  test(
    'plans all filtered results, ignoring pagination and preserving sort',
    () async {
      final z = await add('zebra invoice');
      final a = await add('alpha invoice');
      await add('unrelated');
      await add('other invoice', folder: '/Sent');
      final plan = value(
        await archive.planExport(
          const MailArchiveSearchRequest(
            query: 'subject:invoice',
            folder: '/Inbox',
            includeSubfolders: false,
            sort: MailArchiveSort.subject,
            limit: 1,
            offset: 1,
          ),
        ),
      );
      expect(plan.profile, profile);
      expect(plan.createdAt, now);
      expect(plan.items.map((item) => item.id), [a, z]);
      expect(
        plan.totalBytes,
        plan.items.fold<int>(0, (n, item) => n + item.byteLength),
      );
      expect(() => plan.items.clear(), throwsUnsupportedError);
      await add('another invoice');
      expect(plan.items, hasLength(2));
    },
  );

  test(
    'captures every origin of each selected original without duplicating bytes',
    () async {
      const raw = 'Subject: One\r\n\r\noriginal';
      final id = await add('one', raw: raw);
      await add('two', raw: raw, source: 'Secondary', folder: '/Copy');
      final plan = value(
        await archive.planExport(
          const MailArchiveSearchRequest(source: 'Local'),
        ),
      );
      expect(plan.items.single.id, id);
      expect(plan.items.single.origins.map((origin) => origin.source), [
        'Local',
        'Secondary',
      ]);
      expect(() => plan.items.single.origins.clear(), throwsUnsupportedError);
    },
  );

  test('empty match is an explicit zero-message plan', () async {
    final plan = value(
      await archive.planExport(const MailArchiveSearchRequest()),
    );
    expect(plan.items, isEmpty);
    expect(plan.totalBytes, 0);
  });

  test(
    'uses the same structured date, size and descendant filters as search',
    () async {
      final id = await add('invoice', folder: '/Inbox/Work');
      await add(
        'invoice',
        folder: '/Inbox2',
        raw: 'Subject: invoice\r\n\r\nseparate',
      );
      final request = MailArchiveSearchRequest(
        query: 'invoice',
        folder: '/Inbox',
        sentSince: now,
        sentBefore: now.add(const Duration(days: 1)),
        minBytes: 1,
        maxBytes: 1000,
        hasAttachments: false,
      );
      final plan = value(await archive.planExport(request));
      expect(plan.items.map((item) => item.id), [id]);
      expect(
        plan.items.map((item) => item.id),
        value(await archive.search(request)).hits.map((hit) => hit.entry.id),
      );
    },
  );

  test('refuses invalid queries and invalid bounds', () async {
    fails(
      await archive.planExport(
        const MailArchiveSearchRequest(query: 'subject:'),
      ),
      MailProblemCode.invalidInput,
    );
    fails(
      await archive.planExport(
        const MailArchiveSearchRequest(),
        exportLimits: const MailArchiveExportLimits(maxMessages: 0),
      ),
      MailProblemCode.invalidInput,
    );
  });

  test(
    'enforces message count, individual and aggregate byte limits before originals load',
    () async {
      await add('first');
      await add('second');
      fails(
        await archive.planExport(
          const MailArchiveSearchRequest(),
          exportLimits: const MailArchiveExportLimits(maxMessages: 1),
        ),
        MailProblemCode.quotaExceeded,
      );
      fails(
        await archive.planExport(
          const MailArchiveSearchRequest(),
          exportLimits: const MailArchiveExportLimits(maxMessageBytes: 1),
        ),
        MailProblemCode.quotaExceeded,
      );
      fails(
        await archive.planExport(
          const MailArchiveSearchRequest(),
          exportLimits: const MailArchiveExportLimits(
            maxMessageBytes: 32,
            maxTotalBytes: 32,
          ),
        ),
        MailProblemCode.quotaExceeded,
      );
    },
  );

  test('bounds provenance count and encoded manifest allocation', () async {
    await add('one');
    await add('two');
    fails(
      await archive.planExport(
        const MailArchiveSearchRequest(),
        exportLimits: const MailArchiveExportLimits(maxOrigins: 1),
      ),
      MailProblemCode.quotaExceeded,
    );
    fails(
      await archive.planExport(
        const MailArchiveSearchRequest(),
        exportLimits: const MailArchiveExportLimits(maxManifestBytes: 256),
      ),
      MailProblemCode.quotaExceeded,
    );
  });

  test('accepts a plan at its exact encoded manifest byte limit', () async {
    await add('café "invoice"', source: 'محلي', folder: '/Inbox/رسائل');
    const request = MailArchiveSearchRequest();
    final initial = value(await archive.planExport(request));
    final encoded = encodeMailArchiveExportManifest(
      initial,
      const MailArchiveExportLimits(),
    );
    final byteLength = utf8.encode(encoded).length;
    final exact = MailArchiveExportLimits(maxManifestBytes: byteLength);
    final plan = value(await archive.planExport(request, exportLimits: exact));
    expect(encodeMailArchiveExportManifest(plan, exact), encoded);
    fails(
      await archive.planExport(
        request,
        exportLimits: MailArchiveExportLimits(maxManifestBytes: byteLength - 1),
      ),
      MailProblemCode.quotaExceeded,
    );
  });

  test('cancelled plans leave originals and provenance unchanged', () async {
    await add('one');
    final cancel = MailCancellationSource()..cancel();
    fails(
      await archive.planExport(
        const MailArchiveSearchRequest(),
        cancellation: cancel.token,
      ),
      MailProblemCode.cancelled,
    );
    final stats = value(await archive.statistics());
    expect(stats.messages, 1);
    expect(stats.origins, 1);
  });

  test(
    'missing or unsafe persisted provenance cannot enter a portable plan',
    () async {
      final id = await add('one');
      database.execute('UPDATE archive_origins SET folder=? WHERE message=?', [
        '/../escaped',
        id,
      ]);
      fails(
        await archive.planExport(const MailArchiveSearchRequest()),
        MailProblemCode.invalidInput,
      );
      database.execute('DELETE FROM archive_origins WHERE message=?', [id]);
      fails(
        await archive.planExport(const MailArchiveSearchRequest()),
        MailProblemCode.storageFailure,
      );
    },
  );

  test(
    'preflights NUL-containing oversized persisted metadata before hydration',
    () async {
      await add('one');
      database.execute('UPDATE archive_origins SET source=?', [
        'x\u0000${'a' * 4000}',
      ]);
      fails(
        await archive.planExport(const MailArchiveSearchRequest()),
        MailProblemCode.quotaExceeded,
      );
    },
  );

  test(
    'refuses corrupt raw lengths without exporting partial originals',
    () async {
      await add('one');
      database.execute('PRAGMA ignore_check_constraints=ON');
      database.execute('UPDATE archive_items SET raw_size=raw_size+1');
      database.execute('PRAGMA ignore_check_constraints=OFF');
      fails(
        await archive.planExport(const MailArchiveSearchRequest()),
        MailProblemCode.storageFailure,
      );
    },
  );

  test('closed archive cannot create a new export plan', () async {
    await archive.close();
    fails(
      await archive.planExport(const MailArchiveSearchRequest()),
      MailProblemCode.unavailable,
    );
  });
}
