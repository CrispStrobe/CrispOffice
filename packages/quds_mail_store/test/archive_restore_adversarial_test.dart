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

final _sourceProfile = MailProfileId('export-source', hostId: 'source-host');
final _destinationProfile = MailProfileId(
  'restore-destination',
  hostId: 'different-host',
);
const _origins = [
  MailArchiveOrigin(
    source: 'Personal-export',
    folder: '/Inbox/رسائل',
    sourceMessageId: 'provider:original-a',
  ),
  MailArchiveOrigin(
    source: 'Second--export',
    folder: '/Historical/café',
    sourceMessageId: 'provider:original-b',
  ),
];

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

MailBytes _original(int number) => MailBytes(
  Uint8List.fromList(
    utf8.encode(
      'From: sender@example.invalid\r\n'
      'Subject: Private original $number\r\n'
      'Message-ID: <reused@example.invalid>\r\n\r\n'
      'Exact original content $number.\r\n',
    ),
  ),
);

MailMessage _decoded(Uint8List bytes) => MailMessage(
  raw: MailBytes(bytes),
  envelope: MailEnvelope(subject: 'Decoded original'),
  body: MailBody(plainText: 'Searchable original'),
);

final class _InterceptingCodec implements MailCodec {
  _InterceptingCodec({this.intercept});

  final MailParseResult? Function(Uint8List bytes, int call)? intercept;
  int calls = 0;

  @override
  MailParseResult parse(
    Uint8List bytes, {
    MailReadBudget budget = const MailReadBudget(),
    MailCancellationToken? cancellation,
  }) {
    calls++;
    return intercept?.call(bytes, calls) ??
        MailParseResult(
          status: MailParseStatus.complete,
          message: _decoded(bytes),
        );
  }
}

void main() {
  late Directory parent;
  late Directory source;
  late sqlite.Database database;
  late SqliteMailArchive archive;
  late MailArchiveExportPlan exported;
  late List<MailBytes> originals;
  MailArchiveFaultInjector? fault;
  var archiveOpen = false;

  Future<void> open({
    MailArchiveLimits limits = const MailArchiveLimits(),
  }) async {
    if (archiveOpen) await archive.close();
    archive = _value(
      await SqliteMailArchive.open(
        executor: NativeDatabase.opened(
          database,
          closeUnderlyingOnClose: false,
        ),
        profile: _destinationProfile,
        limits: limits,
        faultInjector: (point) async => fault?.call(point),
      ),
    );
    archiveOpen = true;
  }

  Future<void> writePackage({int count = 2}) async {
    originals = [
      for (var number = 0; number < count; number++) _original(number),
    ];
    exported = MailArchiveExportPlan(
      profile: _sourceProfile,
      createdAt: DateTime.utc(2026, 11, 19),
      items: [
        for (final original in originals)
          MailArchiveExportItem(
            id: original.sha256,
            byteLength: original.length,
            origins: _origins,
          ),
      ],
    );
    for (final original in originals) {
      await File(
        p.join(source.path, '${original.sha256}.eml'),
      ).writeAsBytes(original.bytes);
    }
    await File(p.join(source.path, 'manifest.json')).writeAsString(
      encodeMailArchiveExportManifest(
        exported,
        const MailArchiveExportLimits(),
      ),
    );
  }

  String substitutedManifest() => encodeMailArchiveExportManifest(
    MailArchiveExportPlan(
      profile: exported.profile,
      createdAt: exported.createdAt,
      items: [
        for (final item in exported.items)
          MailArchiveExportItem(
            id: item.id,
            byteLength: item.byteLength,
            origins: [
              for (final origin in item.origins)
                MailArchiveOrigin(
                  source: origin.source.replaceAll('export', 'forged'),
                  folder: origin.folder,
                  sourceMessageId: origin.sourceMessageId,
                ),
            ],
          ),
      ],
    ),
    const MailArchiveExportLimits(),
  );

  Future<MailArchiveStats> stats() async => _value(await archive.statistics());

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final temporary = await Directory.systemTemp.createTemp(
      'archive-restore-adversarial-',
    );
    // Real macOS temporary paths may contain /var -> /private/var. The source
    // checks deliberately reject observed links, so use the real fixture root.
    parent = Directory(await temporary.resolveSymbolicLinks());
    source = await Directory(p.join(parent.path, 'selection')).create();
    database = sqlite.sqlite3.openInMemory();
    archiveOpen = false;
    fault = null;
    await open();
    await writePackage();
  });

  tearDown(() async {
    if (archiveOpen) await archive.close();
    database.close();
    await parent.delete(recursive: true);
  });

  test(
    'a same-size redigested manifest invalidates the confirmed preview',
    () async {
      final codec = _InterceptingCodec();
      final restorer = NativeMailArchiveRestorer(
        archive: archive,
        codec: codec,
      );
      final preview = _value(await restorer.inspect(source));
      final file = File(p.join(source.path, 'manifest.json'));
      final before = await file.readAsBytes();
      final replacement = substitutedManifest();
      expect(utf8.encode(replacement).length, before.length);
      await file.writeAsString(replacement);

      final report = await restorer.restore(preview);
      expect(report.status, MailArchiveRestoreStatus.failed);
      expect(report.problem?.code, MailProblemCode.conflict);
      expect(report.saved, 0);
      expect(report.duplicates, 0);
      expect(codec.calls, 0);
      expect((await stats()).messages, 0);
      expect(await file.readAsString(), replacement);
    },
  );

  test(
    'a manifest change while parsing stops before the current commit',
    () async {
      await writePackage(count: 3);
      final codec = _InterceptingCodec(
        intercept: (_, call) {
          if (call == 2) {
            final file = File(p.join(source.path, 'manifest.json'));
            final modified = file.statSync().modified;
            file.writeAsStringSync(substitutedManifest());
            file.setLastModifiedSync(modified.add(const Duration(seconds: 2)));
          }
          return null;
        },
      );
      final restorer = NativeMailArchiveRestorer(
        archive: archive,
        codec: codec,
      );
      final preview = _value(await restorer.inspect(source));
      final report = await restorer.restore(preview);

      expect(report.status, MailArchiveRestoreStatus.partial);
      expect(report.problem?.code, MailProblemCode.conflict);
      expect(report.saved, 1);
      expect(report.originsAdded, _origins.length);
      expect(report.bytes, originals.first.length);
      expect(codec.calls, 2);
      expect((await stats()).messages, 1);
      expect(_value(await archive.loadOriginal(originals[1].sha256)), isNull);
      expect(
        _value(
          await archive.listOrigins(originals.first.sha256),
        ).map((origin) => origin.source),
        unorderedEquals(_origins.map((origin) => origin.source)),
      );
    },
  );

  test(
    'same-size source mutation after decoding does not commit the item',
    () async {
      await writePackage(count: 1);
      final file = File(p.join(source.path, '${originals.single.sha256}.eml'));
      final corrupted = originals.single.copyBytes()..[0] ^= 1;
      final codec = _InterceptingCodec(
        intercept: (_, _) {
          final modified = file.statSync().modified;
          file.writeAsBytesSync(corrupted);
          file.setLastModifiedSync(modified.add(const Duration(seconds: 2)));
          return null;
        },
      );
      final restorer = NativeMailArchiveRestorer(
        archive: archive,
        codec: codec,
      );
      final report = await restorer.restore(
        _value(await restorer.inspect(source)),
      );

      expect(report.status, MailArchiveRestoreStatus.failed);
      expect(report.problem?.code, MailProblemCode.conflict);
      expect(report.saved, 0);
      expect(report.originsAdded, 0);
      expect((await stats()).messages, 0);
      expect(await file.readAsBytes(), corrupted);
    },
  );

  test('a codec cannot replace verified MIME with another original', () async {
    await writePackage(count: 1);
    final substitute = _original(9);
    expect(substitute.length, originals.single.length);
    final codec = _InterceptingCodec(
      intercept: (_, _) => MailParseResult(
        status: MailParseStatus.complete,
        message: _decoded(substitute.bytes),
      ),
    );
    final restorer = NativeMailArchiveRestorer(archive: archive, codec: codec);
    final report = await restorer.restore(
      _value(await restorer.inspect(source)),
    );

    expect(report.status, MailArchiveRestoreStatus.failed);
    expect(report.problem?.code, MailProblemCode.conflict);
    expect(report.saved, 0);
    expect(report.bytes, 0);
    expect((await stats()).messages, 0);
  });

  test(
    'cancellation from confirmed storage diagnostics retains the commit count',
    () async {
      final cancellation = MailCancellationSource();
      archive.diagnostics = MailArchiveDiagnostics(
        verbose: true,
        sink: (event) {
          if (event.operation == MailArchiveOperation.archive &&
              event.phase == MailArchivePhase.completed) {
            cancellation.cancel();
          }
        },
      );
      final codec = _InterceptingCodec();
      final restorer = NativeMailArchiveRestorer(
        archive: archive,
        codec: codec,
      );
      final preview = _value(await restorer.inspect(source));
      final events = <MailArchiveRestoreProgress>[];
      final report = await restorer.restore(
        preview,
        cancellation: cancellation.token,
        onProgress: events.add,
      );

      expect(report.status, MailArchiveRestoreStatus.cancelled);
      expect(report.saved, 1);
      expect(report.failed, 0);
      expect(report.originsAdded, _origins.length);
      expect(report.bytes, originals.first.length);
      expect(events.last.saved, 1);
      expect(codec.calls, 1);
      expect((await stats()).messages, 1);
      expect(
        _value(await archive.loadOriginal(originals.first.sha256))!.bytes,
        originals.first.bytes,
      );

      archive.diagnostics = null;
      final retry = await restorer.restore(preview);
      expect(retry.status, MailArchiveRestoreStatus.completed);
      expect(retry.saved, 1);
      expect(retry.duplicates, 1);
      expect(retry.originsAdded, _origins.length);
      expect((await stats()).origins, originals.length * _origins.length);
    },
  );

  test(
    'late cancellation also counts new provenance on a duplicate original',
    () async {
      _value(
        await archive.archiveMessage(
          _decoded(originals.first.bytes),
          origin: _origins.first,
        ),
      );
      final cancellation = MailCancellationSource();
      archive.diagnostics = MailArchiveDiagnostics(
        verbose: true,
        sink: (event) {
          if (event.operation == MailArchiveOperation.archive &&
              event.phase == MailArchivePhase.completed) {
            cancellation.cancel();
          }
        },
      );
      final restorer = NativeMailArchiveRestorer(
        archive: archive,
        codec: _InterceptingCodec(),
      );
      final report = await restorer.restore(
        _value(await restorer.inspect(source)),
        cancellation: cancellation.token,
      );

      expect(report.status, MailArchiveRestoreStatus.cancelled);
      expect(report.saved, 0);
      expect(report.duplicates, 1);
      expect(report.failed, 0);
      expect(report.originsAdded, 1);
      expect(report.bytes, originals.first.length);
      expect((await stats()).messages, 1);
      expect((await stats()).origins, _origins.length);
      expect(archive.profile, _destinationProfile);
    },
  );

  test(
    'cancellation just before commit leaves original, FTS and provenance absent',
    () async {
      final cancellation = MailCancellationSource();
      fault = (point) async {
        if (point == MailArchiveCheckpoint.beforeCommit) cancellation.cancel();
      };
      final restorer = NativeMailArchiveRestorer(
        archive: archive,
        codec: _InterceptingCodec(),
      );
      final report = await restorer.restore(
        _value(await restorer.inspect(source)),
        cancellation: cancellation.token,
      );

      expect(report.status, MailArchiveRestoreStatus.cancelled);
      expect(report.saved, 0);
      expect(report.failed, 0);
      expect(report.originsAdded, 0);
      expect(report.bytes, 0);
      final state = await stats();
      expect(state.messages, 0);
      expect(state.origins, 0);
      expect(state.indexedMessages, 0);
      expect(state.rawBytes, 0);
    },
  );

  for (final damage in ['raw', 'metadata']) {
    test(
      'a corrupt existing $damage record never receives new provenance',
      () async {
        await writePackage(count: 1);
        final original = originals.single;
        _value(
          await archive.archiveMessage(
            _decoded(original.bytes),
            origin: const MailArchiveOrigin(source: 'Existing target only'),
          ),
        );
        final corrupted = original.copyBytes()..[0] ^= 1;
        if (damage == 'raw') {
          database.execute('UPDATE archive_items SET raw=? WHERE id=?', [
            corrupted,
            original.sha256,
          ]);
        } else {
          database.execute('UPDATE archive_items SET subject=? WHERE id=?', [
            'Tampered metadata',
            original.sha256,
          ]);
        }
        final restorer = NativeMailArchiveRestorer(
          archive: archive,
          codec: _InterceptingCodec(),
        );
        final report = await restorer.restore(
          _value(await restorer.inspect(source)),
        );

        expect(report.status, MailArchiveRestoreStatus.failed);
        expect(report.problem?.code, MailProblemCode.storageFailure);
        expect(report.saved, 0);
        expect(report.duplicates, 0);
        expect(report.originsAdded, 0);
        expect(report.bytes, 0);
        expect((await stats()).messages, 1);
        expect(
          _value(await archive.listOrigins(original.sha256)).single.source,
          'Existing target only',
        );
        final row = database
            .select('SELECT raw,subject FROM archive_items')
            .single;
        if (damage == 'raw') {
          expect(row['raw'], corrupted);
        } else {
          expect(row['subject'], 'Tampered metadata');
        }
        expect(
          await File(
            p.join(source.path, '${original.sha256}.eml'),
          ).readAsBytes(),
          original.bytes,
        );
      },
    );
  }

  test(
    'restore reapplies tighter limits to a previously valid preview',
    () async {
      final codec = _InterceptingCodec();
      final preview = _value(
        await NativeMailArchiveRestorer(
          archive: archive,
          codec: codec,
        ).inspect(source),
      );
      final constrained = NativeMailArchiveRestorer(
        archive: archive,
        codec: codec,
        limits: const MailArchiveExportLimits(maxMessages: 1),
      );
      final report = await constrained.restore(preview);

      expect(report.status, MailArchiveRestoreStatus.failed);
      expect(report.problem?.code, MailProblemCode.quotaExceeded);
      expect(report.saved, 0);
      expect(report.duplicates, 0);
      expect(codec.calls, 0);
      expect((await stats()).messages, 0);
    },
  );

  test(
    'destination quota rolls back all provenance and indexing on a duplicate',
    () async {
      await writePackage(count: 1);
      await open(
        limits: const MailArchiveLimits(maxMessages: 1, maxOrigins: 2),
      );
      _value(
        await archive.archiveMessage(
          _decoded(originals.single.bytes),
          origin: const MailArchiveOrigin(source: 'Existing target only'),
        ),
      );
      final before = jsonEncode([
        for (final row in database.select('SELECT * FROM archive_fts'))
          Map<String, Object?>.from(row),
      ]);
      final restorer = NativeMailArchiveRestorer(
        archive: archive,
        codec: _InterceptingCodec(),
      );
      final report = await restorer.restore(
        _value(await restorer.inspect(source)),
      );

      expect(report.status, MailArchiveRestoreStatus.failed);
      expect(report.problem?.code, MailProblemCode.quotaExceeded);
      expect(report.duplicates, 0);
      expect(report.originsAdded, 0);
      expect((await stats()).origins, 1);
      expect(
        jsonEncode([
          for (final row in database.select('SELECT * FROM archive_fts'))
            Map<String, Object?>.from(row),
        ]),
        before,
      );
    },
  );

  test(
    'failure samples stay bounded and observer errors do not expose content',
    () async {
      await writePackage(count: 3);
      final codec = _InterceptingCodec(
        intercept: (_, _) =>
            throw StateError('private-token at /private/source'),
      );
      final restorer = NativeMailArchiveRestorer(
        archive: archive,
        codec: codec,
        limits: const MailArchiveExportLimits(maxFailures: 1),
      );
      final events = <MailArchiveRestoreProgress>[];
      final report = await restorer.restore(
        _value(await restorer.inspect(source)),
        onProgress: (event) {
          events.add(event);
          throw StateError('observer-private-token');
        },
      );

      expect(report.status, MailArchiveRestoreStatus.failed);
      expect(report.failed, 3);
      expect(report.failures, hasLength(1));
      expect(report.droppedFailures, 2);
      expect(report.observerErrors, events.length);
      expect(report.saved, 0);
      final diagnostics = jsonEncode(
        events.map((event) => event.toJson()).toList(),
      );
      for (final privateValue in [
        'private-token',
        parent.path,
        _sourceProfile.value,
        _origins.first.source,
        'sender@example.invalid',
      ]) {
        expect(diagnostics, isNot(contains(privateValue)));
      }
      expect((await stats()).messages, 0);
    },
  );

  test('two restorer instances cannot overlap on one archive', () async {
    final competitor = NativeMailArchiveRestorer(
      archive: archive,
      codec: _InterceptingCodec(),
    );
    final preview = _value(await competitor.inspect(source));
    Future<MailArchiveRestoreReport>? competingRun;
    final codec = _InterceptingCodec(
      intercept: (_, call) {
        if (call == 1) competingRun = competitor.restore(preview);
        return null;
      },
    );
    final report = await NativeMailArchiveRestorer(
      archive: archive,
      codec: codec,
    ).restore(preview);
    final rejected = await competingRun!;

    expect(report.status, MailArchiveRestoreStatus.completed);
    expect(report.saved, originals.length);
    expect(rejected.status, MailArchiveRestoreStatus.failed);
    expect(rejected.problem?.code, MailProblemCode.conflict);
    expect(rejected.saved, 0);
    expect((await stats()).messages, originals.length);
    final retry = await competitor.restore(preview);
    expect(retry.status, MailArchiveRestoreStatus.completed);
    expect(retry.duplicates, originals.length);
    expect(retry.originsAdded, 0);
  });

  test(
    'inspection rejects a symbolic-link ancestor of a regular source directory',
    () async {
      final alias = Link(p.join(parent.path, 'ancestor-link'));
      await alias.create(parent.path);
      final restorer = NativeMailArchiveRestorer(
        archive: archive,
        codec: _InterceptingCodec(),
      );
      final inspected = await restorer.inspect(
        Directory(p.join(alias.path, p.basename(source.path))),
      );

      expect(inspected, isA<MailFailure<MailArchiveRestorePlan>>());
      expect(
        (inspected as MailFailure<MailArchiveRestorePlan>).problem.code,
        MailProblemCode.conflict,
      );
      expect((await stats()).messages, 0);
      await alias.delete();
    },
    skip: Platform.isWindows
        ? 'Creating links requires Windows privileges.'
        : false,
  );

  test(
    'a source directory replaced by a link during parsing cannot commit',
    () async {
      await writePackage(count: 1);
      final moved = p.join(parent.path, 'moved-selection');
      final codec = _InterceptingCodec(
        intercept: (_, _) {
          source.renameSync(moved);
          Link(source.path).createSync(moved);
          return null;
        },
      );
      final restorer = NativeMailArchiveRestorer(
        archive: archive,
        codec: codec,
      );
      final preview = _value(await restorer.inspect(source));
      final report = await restorer.restore(preview);

      expect(report.status, MailArchiveRestoreStatus.failed);
      expect(report.problem?.code, MailProblemCode.conflict);
      expect(report.saved, 0);
      expect(report.originsAdded, 0);
      expect((await stats()).messages, 0);
      expect(
        await File(
          p.join(moved, '${originals.single.sha256}.eml'),
        ).readAsBytes(),
        originals.single.bytes,
      );
      await Link(source.path).delete();
    },
    skip: Platform.isWindows
        ? 'Creating links requires Windows privileges.'
        : false,
  );
}
