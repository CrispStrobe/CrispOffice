@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

T value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void failure<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

final profile = MailProfileId('archive', hostId: 'archive-tests');
const origin = MailArchiveOrigin(source: 'Personal', folder: '/Inbox');
MailBytes bytes(String text) =>
    MailBytes(Uint8List.fromList(utf8.encode(text)));

MailMessage message(
  String key, {
  String subject = 'Quarterly report',
  String? plain = 'The project budget is approved.',
  String? html,
  DateTime? date,
  List<MailAttachment> attachments = const [],
}) => MailMessage(
  raw: bytes(
    'From: Alice <alice@example.test>\r\nSubject: $subject\r\n'
    'Message-ID: <shared@example.test>\r\n\r\n$key',
  ),
  envelope: MailEnvelope(
    subject: subject,
    from: [
      const MailAddress('alice@example.test', displayName: 'Alice Sender'),
    ],
    to: [const MailAddress('bob@example.test', displayName: 'Bob Receiver')],
    cc: [const MailAddress('copy@example.test')],
    bcc: [const MailAddress('hidden@example.test')],
    messageId: '<shared@example.test>',
    sentAt: date,
  ),
  body: MailBody(plainText: plain, html: html),
  attachments: attachments,
);

MailAttachment attachment(
  String name,
  String content, {
  String type = 'text/plain',
}) => MailAttachment(
  partPath: name,
  mediaType: type,
  displayName: name,
  content: bytes(content),
);

void main() {
  late sqlite.Database database;
  late SqliteMailArchive archive;
  var now = DateTime.utc(2026, 11, 19, 10);
  MailArchiveFaultInjector? fault;

  Future<void> open({
    MailArchiveLimits limits = const MailArchiveLimits(),
    MailProfileId? owner,
  }) async {
    archive = value(
      await SqliteMailArchive.open(
        executor: NativeDatabase.opened(
          database,
          closeUnderlyingOnClose: false,
        ),
        profile: owner ?? profile,
        limits: limits,
        clock: () => now,
        faultInjector: (point) async => fault?.call(point),
      ),
    );
  }

  Future<MailArchiveImportResult> add(
    MailMessage item, {
    MailArchiveOrigin source = origin,
    bool text = false,
  }) async => value(
    await archive.archiveMessage(
      item,
      origin: source,
      indexAttachmentText: text,
    ),
  );

  Future<List<String>> find(
    String query, {
    MailArchiveSearchRequest? request,
  }) async => value(
    await archive.search(request ?? MailArchiveSearchRequest(query: query)),
  ).hits.map((hit) => hit.entry.id).toList();

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = sqlite.sqlite3.openInMemory();
    now = DateTime.utc(2026, 11, 19, 10);
    fault = null;
    await open();
  });

  tearDown(() async {
    await archive.close();
    database.close();
  });

  test(
    'archives original bytes, headers, source and searchable data without an account',
    () async {
      final item = message('Original\u0000binary\u00ff');
      final saved = await add(item);
      expect(saved.duplicate, isFalse);
      expect(saved.originAdded, isTrue);
      expect(saved.entry.id, item.raw.sha256);
      expect(saved.entry.envelope.bcc.single.address, 'hidden@example.test');
      expect(saved.entry.archivedAt, now);
      expect(
        value(await archive.loadOriginal(saved.entry.id))!.bytes,
        item.raw.bytes,
      );
      expect(
        value(await archive.listOrigins(saved.entry.id)).single.folder,
        '/Inbox',
      );
      expect(await find('subject:report bcontent:budget'), [saved.entry.id]);
      final stats = value(await archive.statistics());
      expect(stats.messages, 1);
      expect(stats.indexedMessages, 1);
      expect(stats.rawBytes, item.raw.length);
      expect(stats.origins, 1);
    },
  );

  test(
    'deduplication is content-based and additional provenance is retained',
    () async {
      final item = message('same bytes');
      final first = await add(item);
      now = now.add(const Duration(days: 1));
      final second = await add(item);
      expect(second.duplicate, isTrue);
      expect(second.originAdded, isFalse);
      expect(second.entry.archivedAt, first.entry.archivedAt);
      final third = await add(
        item,
        source: const MailArchiveOrigin(source: 'Backup', folder: '/Old'),
      );
      expect(third.duplicate, isTrue);
      expect(third.originAdded, isTrue);
      expect(value(await archive.statistics()).messages, 1);
      expect(value(await archive.listOrigins(first.entry.id)), hasLength(2));
    },
  );

  test(
    'different original bytes with the same Message-ID remain separate',
    () async {
      final first = await add(message('first'));
      final second = await add(message('second'));
      expect(first.entry.id, isNot(second.entry.id));
      expect(second.duplicate, isFalse);
      expect(value(await archive.statistics()).messages, 2);
    },
  );

  test('reopening retains original bytes, search and provenance', () async {
    final item = message('restart');
    await add(item);
    await archive.close();
    await open();
    expect(await find('budget'), [item.raw.sha256]);
    expect(
      value(await archive.loadOriginal(item.raw.sha256))!.bytes,
      item.raw.bytes,
    );
    expect(
      value(await archive.listOrigins(item.raw.sha256)).single.source,
      'Personal',
    );
  });

  test('a different profile cannot open the existing archive', () async {
    await add(message('owner'));
    await archive.close();
    final other = await SqliteMailArchive.open(
      executor: NativeDatabase.opened(database, closeUnderlyingOnClose: false),
      profile: MailProfileId('other', hostId: 'archive-tests'),
    );
    failure(other, MailProblemCode.permissionDenied);
    await open();
    expect(value(await archive.statistics()).messages, 1);
  });

  for (final query in [
    'subject:quarterly',
    'from:Alice',
    'to:Bob',
    'cc:copy',
    'bcc:hidden',
    'bcontent:"project budget"',
    '[rejected approved]',
    'subject:quart* -from:carol',
  ]) {
    test('fielded archive search matches $query', () async {
      final saved = await add(message('search'));
      expect(await find(query), [saved.entry.id]);
    });
  }

  test(
    'HTML-only bodies index visible text and entities without executable markup',
    () async {
      final saved = await add(
        message(
          'html',
          plain: null,
          html:
              '<html><head><title>headsecret</title></head><body>'
              '<script>scriptsecret</script><style>stylesecret</style>'
              '<p>Revenue &amp; caf&#233; مرحبا</p><img src="https://remote.invalid/private">'
              '<!-- commentsecret --></body></html>',
        ),
      );
      expect(await find('bcontent:revenue bcontent:cafe bcontent:مرحبا'), [
        saved.entry.id,
      ]);
      for (final secret in [
        'scriptsecret',
        'stylesecret',
        'headsecret',
        'commentsecret',
        'remote',
      ]) {
        expect(await find('bcontent:$secret'), isEmpty);
      }
    },
  );

  test('attachment names index by default while text is opt-in', () async {
    final saved = await add(
      message(
        'attachment',
        attachments: [attachment('invoice.txt', 'hiddenattachmentneedle')],
      ),
    );
    expect(await find('attachment:invoice'), [saved.entry.id]);
    expect(await find('acontent:hiddenattachmentneedle'), isEmpty);
    expect(saved.entry.attachmentTextIndexed, 0);
    expect(saved.entry.attachmentTextSkipped, 1);
  });

  for (final type in [
    'text/plain',
    'text/csv',
    'text/tab-separated-values',
    'application/json',
    'text/xml',
    'application/xml',
    'text/html',
  ]) {
    test('opt-in supported attachment text: $type', () async {
      final saved = await add(
        message(
          'text-$type',
          attachments: [
            attachment(
              'document',
              type == 'text/html' ? '<p>contentneedle</p>' : 'contentneedle',
              type: type,
            ),
          ],
        ),
        text: true,
      );
      expect(await find('acontent:contentneedle'), [saved.entry.id]);
      expect(saved.entry.attachmentTextIndexed, 1);
    });
  }

  test(
    'unsupported binary and malformed text remain archived and visibly skipped',
    () async {
      final saved = await add(
        message(
          'skip',
          attachments: [
            attachment('paper.pdf', 'pdfneedle', type: 'application/pdf'),
            MailAttachment(
              partPath: '2',
              mediaType: 'text/plain',
              displayName: 'bad.txt',
              content: MailBytes(Uint8List.fromList([0xc3, 0x28])),
            ),
          ],
        ),
        text: true,
      );
      expect(saved.entry.attachmentTextSkipped, 2);
      expect(saved.entry.attachmentTextIndexed, 0);
      expect(await find('attachment:paper'), [saved.entry.id]);
      expect(await find('acontent:pdfneedle'), isEmpty);
      expect(value(await archive.loadOriginal(saved.entry.id)), isNotNull);
    },
  );

  test(
    'UTF-16 BOM attachment text is decoded without altering originals',
    () async {
      final content = Uint8List.fromList([
        0xff,
        0xfe,
        for (final c in 'needle'.codeUnits) ...[c, 0],
      ]);
      final item = message(
        'utf16',
        attachments: [
          MailAttachment(
            partPath: '1',
            mediaType: 'text/plain',
            displayName: 'utf16.txt',
            content: MailBytes(content),
          ),
        ],
      );
      final saved = await add(item, text: true);
      expect(await find('acontent:needle'), [saved.entry.id]);
      expect(
        value(await archive.loadOriginal(saved.entry.id))!.bytes,
        item.raw.bytes,
      );
    },
  );

  test('attachment extraction has an aggregate byte budget', () async {
    await archive.close();
    await open(limits: const MailArchiveLimits(maxAttachmentTextBytes: 8));
    final saved = await add(
      message(
        'budget',
        attachments: [
          attachment('a.txt', 'abcde'),
          attachment('b.txt', 'fghij'),
          attachment('large.txt', '0123456789'),
        ],
      ),
      text: true,
    );
    expect(saved.entry.attachmentTextIndexed, 1);
    expect(saved.entry.attachmentTextSkipped, 2);
    expect(await find('acontent:abcde'), [saved.entry.id]);
    expect(await find('acontent:fghij'), isEmpty);
  });

  test(
    'index truncation is explicit and never truncates original MIME',
    () async {
      await archive.close();
      await open(limits: const MailArchiveLimits(maxIndexCodeUnits: 5));
      final item = message('untouched original', subject: 'abc😀z');
      final saved = await add(item);
      expect(saved.entry.indexTruncated, isTrue);
      expect(
        value(await archive.loadOriginal(saved.entry.id))!.bytes,
        item.raw.bytes,
      );
      expect(value(await archive.verifyIntegrity()).issues, isEmpty);
    },
  );

  test(
    'source and folder filters refer to the same provenance, with literal wildcard characters',
    () async {
      final saved = await add(
        message('folders'),
        source: const MailArchiveOrigin(source: 'A', folder: '/20%_work/Child'),
      );
      await add(
        message('folders'),
        source: const MailArchiveOrigin(source: 'B', folder: '/Other'),
      );
      expect(
        await find(
          '',
          request: const MailArchiveSearchRequest(
            source: 'A',
            folder: '/20%_work',
          ),
        ),
        [saved.entry.id],
      );
      expect(
        await find(
          '',
          request: const MailArchiveSearchRequest(
            source: 'B',
            folder: '/20%_work',
          ),
        ),
        isEmpty,
      );
      expect(
        await find(
          '',
          request: const MailArchiveSearchRequest(
            folder: '/20%_work',
            includeSubfolders: false,
          ),
        ),
        isEmpty,
      );
      expect(
        await find('', request: const MailArchiveSearchRequest(folder: '/20')),
        isEmpty,
      );
      expect(
        await find('', request: const MailArchiveSearchRequest(folder: '/')),
        [saved.entry.id],
      );
    },
  );

  test(
    'date filters normalize UTC with inclusive lower and exclusive upper bounds',
    () async {
      final first = await add(
        message('date1', date: DateTime.parse('2026-11-19T10:00:00+02:00')),
      );
      await add(message('date2', date: DateTime.utc(2026, 11, 20, 8)));
      await add(message('unknown'));
      expect(
        await find(
          '',
          request: MailArchiveSearchRequest(
            sentSince: DateTime.utc(2026, 11, 19, 8),
            sentBefore: DateTime.utc(2026, 11, 20, 8),
          ),
        ),
        [first.entry.id],
      );
      expect(
        value(
          await archive.search(
            const MailArchiveSearchRequest(sort: MailArchiveSort.sentNewest),
          ),
        ).hits.last.entry.envelope.sentAt,
        isNull,
      );
    },
  );

  test('archive date and message date are independent filters', () async {
    final saved = await add(message('old mail', date: DateTime.utc(2000)));
    expect(
      await find(
        '',
        request: MailArchiveSearchRequest(
          archivedSince: now,
          archivedBefore: now.add(const Duration(seconds: 1)),
        ),
      ),
      [saved.entry.id],
    );
    expect(
      await find('', request: MailArchiveSearchRequest(sentSince: now)),
      isEmpty,
    );
  });

  test(
    'size bounds are inclusive and attachment filters distinguish both states',
    () async {
      final item = message('with', attachments: [attachment('a', 'b')]);
      final saved = await add(item);
      await add(message('without'));
      expect(
        await find(
          '',
          request: MailArchiveSearchRequest(
            minBytes: item.raw.length,
            maxBytes: item.raw.length,
            hasAttachments: true,
          ),
        ),
        [saved.entry.id],
      );
      expect(
        value(
          await archive.search(
            const MailArchiveSearchRequest(hasAttachments: false),
          ),
        ).total,
        1,
      );
    },
  );

  test(
    'pagination is stable for tied timestamps and contains no duplicates',
    () async {
      for (var i = 0; i < 7; i++) {
        await add(message('page $i'));
      }
      final first = value(
        await archive.search(const MailArchiveSearchRequest(limit: 3)),
      );
      final second = value(
        await archive.search(
          const MailArchiveSearchRequest(limit: 3, offset: 3),
        ),
      );
      final third = value(
        await archive.search(
          const MailArchiveSearchRequest(limit: 3, offset: 6),
        ),
      );
      expect(first.total, 7);
      expect(first.hasMore, isTrue);
      expect(third.hasMore, isFalse);
      expect({
        ...first.hits.map((h) => h.entry.id),
        ...second.hits.map((h) => h.entry.id),
        ...third.hits.map((h) => h.entry.id),
      }, hasLength(7));
    },
  );

  for (final request in [
    const MailArchiveSearchRequest(limit: 0),
    const MailArchiveSearchRequest(limit: 201),
    const MailArchiveSearchRequest(offset: -1),
    const MailArchiveSearchRequest(minBytes: -1),
    const MailArchiveSearchRequest(minBytes: 10, maxBytes: 9),
    const MailArchiveSearchRequest(source: ''),
    const MailArchiveSearchRequest(folder: '../secret'),
    const MailArchiveSearchRequest(query: 'unknown:needle'),
    MailArchiveSearchRequest(
      sentSince: DateTime.utc(2026),
      sentBefore: DateTime.utc(2026),
    ),
  ]) {
    test(
      'invalid search request is rejected without SQL leakage (${request.query}/${request.limit}/${request.offset}/${request.minBytes}/${request.folder}/${request.source})',
      () async {
        failure(await archive.search(request), MailProblemCode.invalidInput);
      },
    );
  }

  test(
    'saved searches retain all criteria across restart and reset pagination',
    () async {
      final request = MailArchiveSearchRequest(
        query: 'from:alice',
        source: 'Personal',
        folder: '/Inbox',
        includeSubfolders: false,
        sentSince: DateTime.utc(2020),
        sentBefore: DateTime.utc(2030),
        archivedSince: DateTime.utc(2026),
        archivedBefore: DateTime.utc(2027),
        minBytes: 4,
        maxBytes: 9999,
        hasAttachments: true,
        sort: MailArchiveSort.sentOldest,
        limit: 20,
        offset: 20,
      );
      value(
        await archive.saveSearch(
          MailArchiveSavedSearch(name: 'Projects', request: request),
        ),
      );
      await archive.close();
      await open();
      final saved = value(await archive.listSearches()).single;
      expect(saved.name, 'Projects');
      expect(saved.request.query, request.query);
      expect(saved.request.source, request.source);
      expect(saved.request.folder, request.folder);
      expect(saved.request.includeSubfolders, isFalse);
      expect(saved.request.sentSince, request.sentSince);
      expect(saved.request.sentBefore, request.sentBefore);
      expect(saved.request.archivedSince, request.archivedSince);
      expect(saved.request.archivedBefore, request.archivedBefore);
      expect(saved.request.minBytes, 4);
      expect(saved.request.maxBytes, 9999);
      expect(saved.request.hasAttachments, isTrue);
      expect(saved.request.sort, MailArchiveSort.sentOldest);
      expect(saved.request.limit, 20);
      expect(saved.request.offset, 0);
      value(await archive.removeSearch('Projects'));
      expect(value(await archive.listSearches()), isEmpty);
    },
  );

  test(
    'profile changes and deletion preserve archived messages and origins',
    () async {
      final saved = await add(message('profile'));
      value(
        await archive.saveProfile(
          const MailArchiveProfile(
            id: 'files',
            name: 'Local files',
            source: 'Personal',
            folder: '/Inbox',
            indexAttachmentText: true,
          ),
        ),
      );
      await archive.close();
      await open();
      final config = value(await archive.listProfiles()).single;
      expect(config.indexAttachmentText, isTrue);
      expect(config.folder, '/Inbox');
      value(await archive.removeProfile(config.id));
      expect(value(await archive.listProfiles()), isEmpty);
      expect(value(await archive.loadOriginal(saved.entry.id)), isNotNull);
      expect(value(await archive.listOrigins(saved.entry.id)), hasLength(1));
    },
  );

  test(
    'canonical folder overflow cannot persist unreadable profiles or origins',
    () async {
      const existing = MailArchiveProfile(
        id: 'bounded',
        name: 'Bounded',
        source: 'Personal',
        folder: '/Inbox',
      );
      value(await archive.saveProfile(existing));
      final oversized = 'x' * 4096;
      failure(
        await archive.saveProfile(
          MailArchiveProfile(
            id: existing.id,
            name: existing.name,
            source: existing.source,
            folder: oversized,
          ),
        ),
        MailProblemCode.invalidInput,
      );
      expect(value(await archive.listProfiles()).single.folder, '/Inbox');
      failure(
        await archive.archiveMessage(
          message('oversized folder'),
          origin: MailArchiveOrigin(source: 'Personal', folder: oversized),
        ),
        MailProblemCode.invalidInput,
      );
      failure(
        await archive.saveSearch(
          MailArchiveSavedSearch(
            name: 'Oversized folder',
            request: MailArchiveSearchRequest(folder: oversized),
          ),
        ),
        MailProblemCode.invalidInput,
      );
      expect(value(await archive.statistics()).messages, 0);
      expect(value(await archive.listSearches()), isEmpty);
    },
  );

  test(
    'exact canonical folder boundary survives profile and origin round trips',
    () async {
      final relative = 'x' * 4095;
      final canonical = '/$relative';
      expect(canonical.length, 4096);
      for (final folder in [relative, canonical]) {
        value(
          await archive.saveProfile(
            MailArchiveProfile(
              id: 'bounded',
              name: 'Bounded',
              source: 'Personal',
              folder: folder,
            ),
          ),
        );
        final saved = await add(
          message('bounded folder'),
          source: MailArchiveOrigin(source: 'Personal', folder: folder),
        );
        expect(
          value(await archive.listOrigins(saved.entry.id)).single.folder,
          canonical,
        );
        expect(
          await find(
            '',
            request: MailArchiveSearchRequest(
              folder: canonical,
              includeSubfolders: false,
            ),
          ),
          [saved.entry.id],
        );
      }
      await archive.close();
      await open();
      expect(value(await archive.listProfiles()).single.folder, canonical);
      expect(value(await archive.statistics()).origins, 1);
    },
  );

  test(
    'saved-search and profile limits roll back the attempted insert',
    () async {
      await archive.close();
      await open(
        limits: const MailArchiveLimits(maxSavedSearches: 1, maxProfiles: 1),
      );
      value(
        await archive.saveSearch(
          const MailArchiveSavedSearch(
            name: 'a',
            request: MailArchiveSearchRequest(),
          ),
        ),
      );
      failure(
        await archive.saveSearch(
          const MailArchiveSavedSearch(
            name: 'b',
            request: MailArchiveSearchRequest(),
          ),
        ),
        MailProblemCode.quotaExceeded,
      );
      expect(value(await archive.listSearches()), hasLength(1));
      value(
        await archive.saveProfile(
          const MailArchiveProfile(id: 'a', name: 'a', source: 's'),
        ),
      );
      failure(
        await archive.saveProfile(
          const MailArchiveProfile(id: 'b', name: 'b', source: 's'),
        ),
        MailProblemCode.quotaExceeded,
      );
      expect(value(await archive.listProfiles()), hasLength(1));
    },
  );

  test(
    'unknown saved-search schema fails explicitly and is preserved',
    () async {
      database.execute(
        'INSERT INTO archive_saved_searches(name,data) VALUES(?,?)',
        ['future', '{"version":99}'],
      );
      failure(await archive.listSearches(), MailProblemCode.unsupported);
      expect(
        database.select('SELECT * FROM archive_saved_searches'),
        hasLength(1),
      );
    },
  );

  test(
    'message and origin quotas roll back raw content, indexes and provenance',
    () async {
      await archive.close();
      await open(
        limits: const MailArchiveLimits(maxMessages: 1, maxOrigins: 1),
      );
      final item = message('first');
      await add(item);
      failure(
        await archive.archiveMessage(message('second'), origin: origin),
        MailProblemCode.quotaExceeded,
      );
      failure(
        await archive.archiveMessage(
          item,
          origin: const MailArchiveOrigin(source: 'second'),
        ),
        MailProblemCode.quotaExceeded,
      );
      final stats = value(await archive.statistics());
      expect(stats.messages, 1);
      expect(stats.origins, 1);
      expect(stats.indexedMessages, 1);
      expect(value(await archive.verifyIntegrity()).issues, isEmpty);
    },
  );

  test(
    'logical-byte quota includes metadata and rolls back a first import',
    () async {
      await archive.close();
      await open(
        limits: const MailArchiveLimits(
          maxMessageBytes: 1024,
          maxArchiveBytes: 1024,
        ),
      );
      failure(
        await archive.archiveMessage(message('limit'), origin: origin),
        MailProblemCode.quotaExceeded,
      );
      expect(value(await archive.statistics()).messages, 0);
      expect(database.select('SELECT * FROM archive_fts'), isEmpty);
    },
  );

  for (final point in MailArchiveCheckpoint.values) {
    test(
      'transaction fault at ${point.name} leaves no partial archive',
      () async {
        fault = (current) async {
          if (current == point) throw StateError('secret SQL and mail');
        };
        failure(
          await archive.archiveMessage(message('rollback'), origin: origin),
          MailProblemCode.storageFailure,
        );
        expect(value(await archive.statistics()).messages, 0);
        expect(database.select('SELECT * FROM archive_fts'), isEmpty);
        expect(database.select('SELECT * FROM archive_origins'), isEmpty);
      },
    );
  }

  test(
    'pre-cancelled and cancelled-before-commit imports cannot leave content',
    () async {
      final cancellation = MailCancellationSource()..cancel();
      failure(
        await archive.archiveMessage(
          message('cancelled'),
          origin: origin,
          cancellation: cancellation.token,
        ),
        MailProblemCode.cancelled,
      );
      final late = MailCancellationSource();
      fault = (point) async {
        if (point == MailArchiveCheckpoint.beforeCommit) late.cancel();
      };
      failure(
        await archive.archiveMessage(
          message('late'),
          origin: origin,
          cancellation: late.token,
        ),
        MailProblemCode.cancelled,
      );
      expect(value(await archive.statistics()).messages, 0);
    },
  );

  test('close waits for an accepted write and rejects new work', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    fault = (point) async {
      if (point == MailArchiveCheckpoint.beforeCommit) {
        entered.complete();
        await release.future;
      }
    };
    final writing = archive.archiveMessage(message('closing'), origin: origin);
    await entered.future;
    var closed = false;
    final closing = archive.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    failure(await archive.statistics(), MailProblemCode.unavailable);
    release.complete();
    value(await writing);
    await closing;
    fault = null;
    await open();
    expect(value(await archive.statistics()).messages, 1);
  });

  test(
    'verbose logs have operation boundaries and contain no private content',
    () async {
      final logs = <MailArchiveDiagnostic>[];
      archive.diagnostics = MailArchiveDiagnostics(
        sink: logs.add,
        verbose: true,
      );
      await add(message('privatebody', subject: 'privatesubject'));
      await find('subject:privatesubject');
      final text = jsonEncode(logs.map((event) => event.toJson()).toList());
      for (final secret in [
        'privatebody',
        'privatesubject',
        'alice',
        'Personal',
        'Inbox',
        'SELECT',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      expect(
        logs.map((event) => event.phase),
        containsAll([
          MailArchivePhase.started,
          MailArchivePhase.progress,
          MailArchivePhase.completed,
        ]),
      );
      expect(
        logs
            .where((event) => event.operation == MailArchiveOperation.archive)
            .map((e) => e.operationId)
            .toSet(),
        hasLength(1),
      );
      archive.diagnostics = MailArchiveDiagnostics(
        verbose: true,
        sink: (_) => throw StateError('logger unavailable'),
      );
      expect((await add(message('logger failure'))).duplicate, isFalse);
    },
  );

  test('nonverbose logging records only sanitized failures', () async {
    final logs = <MailArchiveDiagnostic>[];
    archive.diagnostics = MailArchiveDiagnostics(sink: logs.add);
    await add(message('normal'));
    failure(
      await archive.search(
        const MailArchiveSearchRequest(query: 'secret:private'),
      ),
      MailProblemCode.invalidInput,
    );
    expect(logs, hasLength(1));
    expect(logs.single.phase, MailArchivePhase.failed);
    expect(logs.single.problem, MailProblemCode.invalidInput);
  });

  test(
    'raw corruption is detected and cannot be exported or accepted as duplicate',
    () async {
      final item = message('integrity');
      final saved = await add(item);
      final changed = item.raw.copyBytes()..[0] = 0;
      database.execute('UPDATE archive_items SET raw=? WHERE id=?', [
        changed,
        saved.entry.id,
      ]);
      final report = value(await archive.verifyIntegrity());
      expect(
        report.issues.map((i) => i.code),
        contains(MailArchiveIntegrityCode.rawHashMismatch),
      );
      failure(
        await archive.loadOriginal(saved.entry.id),
        MailProblemCode.storageFailure,
      );
      failure(
        await archive.archiveMessage(item, origin: origin),
        MailProblemCode.storageFailure,
      );
      expect(
        database.select('SELECT raw FROM archive_items').single['raw'],
        changed,
      );
    },
  );

  test(
    'metadata corruption is detected and rebuild preserves the evidence',
    () async {
      final saved = await add(message('meta'));
      database.execute('UPDATE archive_items SET index_data=? WHERE id=?', [
        '[]',
        saved.entry.id,
      ]);
      final verify = value(await archive.verifyIntegrity());
      expect(
        verify.issues.map((i) => i.code),
        contains(MailArchiveIntegrityCode.metadataHashMismatch),
      );
      final rebuild = value(await archive.rebuildIndex());
      expect(
        rebuild.issues.map((i) => i.code),
        contains(MailArchiveIntegrityCode.metadataHashMismatch),
      );
      expect(
        database
            .select('SELECT index_data FROM archive_items')
            .single['index_data'],
        '[]',
      );
    },
  );

  test(
    'missing and incorrect index rows are detected and rebuilt from originals',
    () async {
      final first = await add(message('missing'));
      final second = await add(message('wrong'));
      database.execute('DELETE FROM archive_fts WHERE id=?', [first.entry.id]);
      database.execute('UPDATE archive_fts SET body=? WHERE id=?', [
        'wrongtext',
        second.entry.id,
      ]);
      final before = value(await archive.verifyIntegrity());
      expect(
        before.issues.map((i) => i.code),
        containsAll([
          MailArchiveIntegrityCode.missingIndex,
          MailArchiveIntegrityCode.indexMismatch,
        ]),
      );
      final fixed = value(await archive.rebuildIndex());
      expect(fixed.processed, 2);
      expect(fixed.issues, isEmpty);
      expect(await find('budget'), hasLength(2));
      expect(value(await archive.verifyIntegrity()).issues, isEmpty);
    },
  );

  test(
    'reindex failure rolls the entire page back to the original index state',
    () async {
      final first = await add(message('rebuild1'));
      await add(message('rebuild2'));
      database.execute('DELETE FROM archive_fts');
      var calls = 0;
      fault = (point) async {
        if (point == MailArchiveCheckpoint.afterIndex && ++calls == 2) {
          throw StateError('disk error');
        }
      };
      failure(await archive.rebuildIndex(), MailProblemCode.storageFailure);
      expect(await find('budget'), isEmpty);
      expect(value(await archive.loadOriginal(first.entry.id)), isNotNull);
    },
  );

  test(
    'reindex cancellation retains old search rows and original MIME',
    () async {
      final saved = await add(message('rebuild cancel'));
      final cancellation = MailCancellationSource();
      fault = (point) async {
        if (point == MailArchiveCheckpoint.afterIndex) cancellation.cancel();
      };
      failure(
        await archive.rebuildIndex(cancellation: cancellation.token),
        MailProblemCode.cancelled,
      );
      expect(await find('budget'), [saved.entry.id]);
    },
  );

  test('maintenance continuation covers each record once', () async {
    for (var i = 0; i < 5; i++) {
      await add(message('maintenance$i'));
    }
    String? cursor;
    var processed = 0;
    for (var page = 0; page < 3; page++) {
      final result = value(
        await archive.verifyIntegrity(afterId: cursor, limit: 2),
      );
      expect(result.issues, isEmpty);
      processed += result.processed;
      cursor = result.nextAfterId;
      expect(result.hasMore, page < 2);
    }
    expect(processed, 5);
  });

  test(
    'missing provenance is reported without silently inventing a source',
    () async {
      final saved = await add(message('origin'));
      database.execute('DELETE FROM archive_origins WHERE message=?', [
        saved.entry.id,
      ]);
      expect(
        value(await archive.verifyIntegrity()).issues.single.code,
        MailArchiveIntegrityCode.missingOrigin,
      );
      expect(value(await archive.listOrigins(saved.entry.id)), isEmpty);
    },
  );

  test(
    'codec-driven rebuild refreshes extraction but keeps byte-for-byte originals',
    () async {
      final original = message(
        'reparse',
        attachments: [attachment('notes.txt', 'attachmentneedle')],
      );
      final saved = await add(original);
      expect(await find('acontent:attachmentneedle'), isEmpty);
      value(
        await archive.rebuildIndex(
          codec: _Codec(original),
          indexAttachmentText: true,
        ),
      );
      expect(await find('acontent:attachmentneedle'), [saved.entry.id]);
      expect(
        value(await archive.loadOriginal(saved.entry.id))!.bytes,
        original.raw.bytes,
      );
      expect(value(await archive.verifyIntegrity()).issues, isEmpty);
    },
  );

  test('codec cannot replace originals during rebuild', () async {
    final original = message('first raw');
    await add(original);
    failure(
      await archive.rebuildIndex(codec: _Codec(message('different raw'))),
      MailProblemCode.invalidInput,
    );
    expect(
      value(await archive.loadOriginal(original.raw.sha256))!.bytes,
      original.raw.bytes,
    );
  });

  test(
    'tighter reopening bounds detect oversized content before loading it',
    () async {
      final item = message('size');
      await add(item);
      await archive.close();
      await open(limits: const MailArchiveLimits(maxMessageBytes: 10));
      failure(
        await archive.loadOriginal(item.raw.sha256),
        MailProblemCode.quotaExceeded,
      );
      expect(
        value(await archive.verifyIntegrity()).issues.single.code,
        MailArchiveIntegrityCode.exceedsReadLimit,
      );
      expect(
        value(await archive.rebuildIndex()).issues.single.code,
        MailArchiveIntegrityCode.exceedsReadLimit,
      );
    },
  );
  test(
    'duplicate import rejects corrupt metadata instead of reporting success',
    () async {
      final item = message('duplicate integrity');
      await add(item);
      database.execute('UPDATE archive_items SET index_data=?', ['[]']);
      failure(
        await archive.archiveMessage(item, origin: origin),
        MailProblemCode.storageFailure,
      );
      expect(value(await archive.statistics()).messages, 1);
    },
  );

  test(
    'duplicate import restores a missing index without changing original bytes',
    () async {
      final item = message('duplicate repair');
      await add(item);
      database.execute('DELETE FROM archive_fts');
      final retry = await add(item);
      expect(retry.duplicate, isTrue);
      expect(retry.originAdded, isFalse);
      expect(await find('budget'), [item.raw.sha256]);
      expect(value(await archive.verifyIntegrity()).issues, isEmpty);
    },
  );

  test(
    'provider session invalidation before commit rolls back archival',
    () async {
      final account = MailAccountId('provider', profile: profile);
      final session = MailAccountSession(account);
      final lease = session.begin();
      fault = (point) async {
        if (point == MailArchiveCheckpoint.beforeCommit) session.invalidate();
      };
      failure(
        await archive.archiveMessage(
          message('stale'),
          origin: origin,
          lease: lease,
        ),
        MailProblemCode.staleOperation,
      );
      expect(value(await archive.statistics()).messages, 0);
    },
  );

  test(
    'empty reference identifiers cannot bypass metadata cardinality limits',
    () async {
      final item = MailMessage(
        raw: bytes('raw'),
        envelope: MailEnvelope(references: List.filled(1025, '')),
      );
      failure(
        await archive.archiveMessage(item, origin: origin),
        MailProblemCode.quotaExceeded,
      );
      expect(value(await archive.statistics()).messages, 0);
    },
  );

  test(
    'attachment text separators count against the shared index budget',
    () async {
      await archive.close();
      await open(limits: const MailArchiveLimits(maxIndexCodeUnits: 8));
      final item = MailMessage(
        raw: bytes('bounded'),
        envelope: MailEnvelope(),
        attachments: [for (var i = 0; i < 10; i++) attachment('', 'a')],
      );
      final saved = await add(item, text: true);
      final fields =
          jsonDecode(
                database
                        .select('SELECT index_data FROM archive_items')
                        .single['index_data']
                    as String,
              )
              as List<Object?>;
      expect(
        fields.cast<String>().fold<int>(
          0,
          (total, field) => total + field.length,
        ),
        lessThanOrEqualTo(8),
      );
      expect(saved.entry.indexTruncated, isTrue);
      expect(value(await archive.verifyIntegrity()).issues, isEmpty);
    },
  );

  test(
    'oversized derived preview is rejected before search hydration',
    () async {
      await add(message('preview limit'));
      await archive.close();
      await open(limits: const MailArchiveLimits(maxMetadataCodeUnits: 4096));
      database.execute('UPDATE archive_items SET preview=?', ['x' * 5000]);
      failure(
        await archive.search(const MailArchiveSearchRequest()),
        MailProblemCode.quotaExceeded,
      );
      expect(
        value(await archive.verifyIntegrity()).issues.single.code,
        MailArchiveIntegrityCode.exceedsReadLimit,
      );
    },
  );

  test(
    'oversized damaged FTS values stop whole-index work before hydration',
    () async {
      final saved = await add(message('index limit'));
      await archive.close();
      await open(limits: const MailArchiveLimits(maxIndexCodeUnits: 512));
      database.execute('UPDATE archive_fts SET body=?', ['x' * 5000]);
      failure(await archive.verifyIntegrity(), MailProblemCode.quotaExceeded);
      failure(await archive.rebuildIndex(), MailProblemCode.quotaExceeded);
      expect(
        database.select('SELECT body FROM archive_fts').single['body'],
        'x' * 5000,
      );
      // Explicitly restore a sufficient read budget to repair the damaged
      // projection; a bounded maintenance call never silently raises limits.
      await archive.close();
      await open();
      value(await archive.rebuildIndex());
      expect(await find('budget'), [saved.entry.id]);
    },
  );

  test(
    'oversized stored search and profile records fail before decoding',
    () async {
      database.execute(
        'INSERT INTO archive_saved_searches(name,data) VALUES(?,?)',
        ['large', 'x' * 20000],
      );
      database.execute('INSERT INTO archive_profiles(id,data) VALUES(?,?)', [
        'large',
        'x' * 20000,
      ]);
      failure(await archive.listSearches(), MailProblemCode.quotaExceeded);
      failure(await archive.listProfiles(), MailProblemCode.quotaExceeded);
    },
  );

  for (final size in [5000, 16000]) {
    test(
      'NUL-prefixed preview of $size units cannot bypass read limits',
      () async {
        final item = message('NUL preview $size');
        await add(item);
        await archive.close();
        await open(limits: const MailArchiveLimits(maxMetadataCodeUnits: 4096));
        database.execute('UPDATE archive_items SET preview=?', [
          '\u0000${'x' * size}',
        ]);
        failure(
          await archive.search(const MailArchiveSearchRequest()),
          MailProblemCode.quotaExceeded,
        );
        failure(
          await archive.archiveMessage(item, origin: origin),
          MailProblemCode.quotaExceeded,
        );
        for (final result in [
          await archive.verifyIntegrity(),
          await archive.rebuildIndex(),
        ]) {
          expect(
            value(result).issues.single.code,
            MailArchiveIntegrityCode.exceedsReadLimit,
          );
        }
        expect(
          value(await archive.loadOriginal(item.raw.sha256))!.bytes,
          item.raw.bytes,
        );
      },
    );
  }

  test('NUL-prefixed FTS text cannot bypass whole-index byte limits', () async {
    final item = message('NUL index');
    await add(item);
    await archive.close();
    await open(limits: const MailArchiveLimits(maxIndexCodeUnits: 512));
    final damaged = '\u0000${'x' * 5000}';
    database.execute('UPDATE archive_fts SET body=?', [damaged]);
    failure(await archive.verifyIntegrity(), MailProblemCode.quotaExceeded);
    failure(await archive.rebuildIndex(), MailProblemCode.quotaExceeded);
    expect(
      database.select('SELECT body FROM archive_fts').single['body'],
      damaged,
    );
    expect(
      value(await archive.loadOriginal(item.raw.sha256))!.bytes,
      item.raw.bytes,
    );
  });

  test(
    'astral text uses exact UTF-16 limits after bounded SQLite hydration',
    () async {
      final item = message('astral read', plain: '原文 مرحبا 😀');
      await add(item);
      expect(value(await archive.verifyIntegrity()).issues, isEmpty);
      await archive.close();
      await open(limits: const MailArchiveLimits(maxMetadataCodeUnits: 4096));
      database.execute('UPDATE archive_items SET preview=?', ['😀' * 2200]);
      // SQLite counts 2,200 code points; Dart correctly counts 4,400 units.
      failure(
        await archive.search(const MailArchiveSearchRequest()),
        MailProblemCode.quotaExceeded,
      );
      expect(
        value(await archive.rebuildIndex()).issues.single.code,
        MailArchiveIntegrityCode.exceedsReadLimit,
      );
    },
  );

  test('NUL-prefixed persisted settings and provenance stay bounded', () async {
    final item = message('NUL stored settings');
    await add(item);
    database.execute(
      'INSERT INTO archive_saved_searches(name,data) VALUES(?,?)',
      ['large', '\u0000${'x' * 50000}'],
    );
    database.execute('INSERT INTO archive_profiles(id,data) VALUES(?,?)', [
      'large',
      '\u0000${'x' * 50000}',
    ]);
    failure(await archive.listSearches(), MailProblemCode.quotaExceeded);
    failure(await archive.listProfiles(), MailProblemCode.quotaExceeded);
    await archive.close();
    await open(limits: const MailArchiveLimits(maxMetadataCodeUnits: 4096));
    database.execute('UPDATE archive_origins SET folder=?', [
      '\u0000${'x' * 16000}',
    ]);
    failure(
      await archive.listOrigins(item.raw.sha256),
      MailProblemCode.quotaExceeded,
    );
  });

  test(
    'whole-index row quota prevents processing an unbounded damaged index',
    () async {
      await add(message('extra index rows'));
      await archive.close();
      await open(limits: const MailArchiveLimits(maxMessages: 1));
      database.execute('INSERT INTO archive_fts(id,body) VALUES(?,?)', [
        'f' * 64,
        'orphan',
      ]);
      failure(await archive.verifyIntegrity(), MailProblemCode.quotaExceeded);
      failure(await archive.rebuildIndex(), MailProblemCode.quotaExceeded);
      expect(
        database.select('SELECT count(*) AS n FROM archive_fts').single['n'],
        2,
      );
      expect(value(await archive.statistics()).messages, 1);
    },
  );

  test('rebuild does not load a damaged BLOB beyond its stored size', () async {
    final item = message('damaged raw length');
    await add(item);
    // Simulate on-disk damage, which ordinary SQL writes are prevented from
    // creating by the schema's length(raw)=raw_size CHECK constraint.
    database.execute('PRAGMA ignore_check_constraints=ON');
    database.execute('UPDATE archive_items SET raw=?', [Uint8List(5000)]);
    database.execute('PRAGMA ignore_check_constraints=OFF');
    await archive.close();
    await open(limits: const MailArchiveLimits(maxMessageBytes: 1024));
    final report = value(await archive.rebuildIndex());
    expect(report.issues.single.code, MailArchiveIntegrityCode.rawHashMismatch);
    expect(
      database.select('SELECT length(raw) AS n FROM archive_items').single['n'],
      5000,
    );
    failure(
      await archive.loadOriginal(item.raw.sha256),
      MailProblemCode.storageFailure,
    );
  });

  test('duplicate reindex respects a tighter reopened index budget', () async {
    final item = message('tighter duplicate', plain: '😀' * 1000);
    await add(item);
    await archive.close();
    await open(limits: const MailArchiveLimits(maxIndexCodeUnits: 512));
    failure(
      await archive.archiveMessage(item, origin: origin),
      MailProblemCode.quotaExceeded,
    );
    expect(
      database.select('SELECT body FROM archive_fts').single['body'],
      '😀' * 1000,
    );
    expect(
      value(await archive.loadOriginal(item.raw.sha256))!.bytes,
      item.raw.bytes,
    );
  });
}

final class _Codec implements MailCodec {
  const _Codec(this.message);
  final MailMessage message;
  @override
  MailParseResult parse(
    Uint8List bytes, {
    MailReadBudget budget = const MailReadBudget(),
    MailCancellationToken? cancellation,
  }) => MailParseResult(status: MailParseStatus.complete, message: message);
}
