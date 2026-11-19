@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';
import 'package:quds_mail_store/src/platform_configuration.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../tool/archive_crash_fixture.dart' as fixture;

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _failure<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

Future<SqliteMailArchive> _open(
  Directory directory, {
  MailProfileId? profile,
  MailArchiveFaultInjector? fault,
}) async => _value(
  await openNativeMailArchive(
    appDirectory: directory,
    profile: profile ?? fixture.archiveCrashProfile,
    clock: () => fixture.archiveCrashTime,
    faultInjector: fault,
  ),
);

String _archivePath(Directory directory, {MailProfileId? profile}) => p.join(
  directory.path,
  'quds_mail_archive',
  mailStoreNamespace(profile ?? fixture.archiveCrashProfile),
  'archive.sqlite3',
);

String _snapshotArchiveRows(Directory directory) {
  final database = sqlite.sqlite3.open(_archivePath(directory));
  try {
    return jsonEncode({
      for (final table in const [
        'archive_owner',
        'archive_totals',
        'archive_items',
        'archive_origins',
        'archive_saved_searches',
        'archive_profiles',
        'archive_fts_data',
        'archive_fts_idx',
        'archive_fts_content',
        'archive_fts_docsize',
        'archive_fts_config',
      ])
        table: [
          for (final row in database.select(
            'SELECT * FROM $table ORDER BY 1,2',
          ))
            Map<String, Object?>.from(row),
        ],
    });
  } finally {
    database.close();
  }
}

void _corruptPostingBlocks(Directory directory) {
  final database = sqlite.sqlite3.open(_archivePath(directory));
  try {
    // This synthetic corruption removes posting leaves while keeping the
    // original MIME, metadata and FTS content intact. Reading FTS columns alone
    // cannot detect it; a real MATCH and FTS5 integrity-check do.
    expect(
      database.select('SELECT id FROM archive_fts_data WHERE id>10'),
      isNotEmpty,
    );
    database.execute('DELETE FROM archive_fts_data WHERE id>10');
    expect(database.select('SELECT id FROM archive_fts'), hasLength(1));
  } finally {
    database.close();
  }
}

Future<void> _seed(Directory directory) async {
  final archive = await _open(directory);
  try {
    _value(
      await archive.archiveMessage(
        fixture.archiveCrashMessage(pending: false),
        origin: fixture.archiveCrashOrigin,
      ),
    );
  } finally {
    await archive.close();
  }
}

Future<void> _killAtBarrier(
  Directory directory,
  fixture.ArchiveCrashScenario scenario,
) async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:quds_mail_store/quds_mail_archive_native.dart'),
  );
  final package = File.fromUri(library!).parent.parent;
  // A kernel test runner may be dartvm. The adjacent official Dart CLI runs
  // the child through the same real native-assets hook as normal consumers.
  final dart = p.join(p.dirname(Platform.resolvedExecutable), 'dart');
  final process = await Process.start(dart, [
    'run',
    p.join(package.path, 'tool/archive_crash_fixture.dart'),
    directory.path,
    scenario.name,
  ], workingDirectory: package.path);
  final ready = Completer<int>();
  final output = <String>[];
  final errors = StringBuffer();
  int? owner;
  var exited = false;
  final exit = process.exitCode.then((code) {
    exited = true;
    return code;
  });
  final stderr = process.stderr.transform(utf8.decoder).listen(errors.write);
  final stdout = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(
        (line) {
          output.add(line);
          final prefix = 'READY ${scenario.name} ';
          if (line.startsWith(prefix) && !ready.isCompleted) {
            final reported = int.tryParse(line.substring(prefix.length));
            if (reported == null || reported <= 0) {
              ready.completeError(StateError('Invalid fixture owner PID.'));
            } else {
              owner = reported;
              ready.complete(reported);
            }
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        },
        onDone: () {
          if (!ready.isCompleted) {
            ready.completeError(
              StateError('Fixture exited before READY: $output; $errors'),
            );
          }
        },
      );
  try {
    final child = await ready.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TestFailure(
        'No ${scenario.name} barrier. stdout=$output; stderr=$errors',
      ),
    );
    expect(exited, isFalse);
    _failure(
      await openNativeMailArchive(
        appDirectory: directory,
        profile: fixture.archiveCrashProfile,
      ),
      MailProblemCode.conflict,
    );
    expect(Process.killPid(child, ProcessSignal.sigkill), isTrue);
    final code = await exit.timeout(const Duration(seconds: 10));
    expect(code, isNot(0), reason: 'SIGKILL must terminate abnormally.');
    if (child == process.pid) expect(code, -9);
    print(
      'ARCHIVE_SIGKILL ${scenario.name} '
      'owner=$child launcher=${process.pid} exit=$code',
    );
    expect(errors.toString(), isNot(contains('ARCHIVE_CRASH_FIXTURE_FAILURE')));
    expect(errors.toString(), isNot(contains('Unhandled exception')));
  } finally {
    if (!exited) {
      if (owner case final child?) {
        Process.killPid(child, ProcessSignal.sigkill);
      }
      process.kill(ProcessSignal.sigkill);
      await exit.timeout(const Duration(seconds: 10));
    }
    await stdout.cancel();
    await stderr.cancel();
  }
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('crisp-archive-native-');
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'native restart preserves binary MIME, Unicode headers and provenance',
    () async {
      final message = fixture.archiveCrashMessage(pending: false);
      await _seed(directory);
      final archive = await _open(directory);
      try {
        final original = _value(
          await archive.loadOriginal(message.raw.sha256),
        )!;
        expect(original.bytes, message.raw.bytes);
        final exported = original.copyBytes()..[0] = 0;
        expect(exported, isNot(message.raw.bytes));
        expect(
          _value(await archive.loadOriginal(message.raw.sha256))!.bytes,
          message.raw.bytes,
        );
        final results = _value(
          await archive.search(
            const MailArchiveSearchRequest(query: 'subject:baselineledger'),
          ),
        );
        expect(
          results.hits.single.entry.envelope.subject,
          message.envelope.subject,
        );
        expect(
          results.hits.single.entry.envelope.bcc.single.address,
          'blind@example.invalid',
        );
        expect(results.hits.single.entry.archivedAt, fixture.archiveCrashTime);
        final origin = _value(
          await archive.listOrigins(message.raw.sha256),
        ).single;
        expect(origin.source, fixture.archiveCrashOrigin.source);
        expect(origin.folder, fixture.archiveCrashOrigin.folder);
        expect(
          origin.sourceMessageId,
          fixture.archiveCrashOrigin.sourceMessageId,
        );
        expect(_value(await archive.verifyIntegrity()).issues, isEmpty);
      } finally {
        await archive.close();
      }
      final database = sqlite.sqlite3.open(_archivePath(directory));
      try {
        expect(
          database.select('PRAGMA journal_mode').single.values.single,
          'wal',
        );
        expect(
          database.select('PRAGMA integrity_check').single.values.single,
          'ok',
        );
      } finally {
        database.close();
      }
    },
  );

  test(
    'exclusive native owner rejects peers and is released by idempotent close',
    () async {
      final first = await _open(directory);
      try {
        _failure(
          await openNativeMailArchive(
            appDirectory: directory,
            profile: fixture.archiveCrashProfile,
          ),
          MailProblemCode.conflict,
        );
      } finally {
        await Future.wait([first.close(), first.close()]);
      }
      final reopened = await _open(directory);
      await reopened.close();
    },
  );

  test(
    'native close keeps ownership until the accepted transaction finishes',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final archive = await _open(
        directory,
        fault: (point) async {
          if (point == MailArchiveCheckpoint.beforeCommit) {
            entered.complete();
            await release.future;
          }
        },
      );
      final message = fixture.archiveCrashMessage(pending: false);
      final writing = archive.archiveMessage(
        message,
        origin: fixture.archiveCrashOrigin,
      );
      await entered.future;
      final closing = archive.close();
      try {
        _failure(
          await openNativeMailArchive(
            appDirectory: directory,
            profile: fixture.archiveCrashProfile,
          ),
          MailProblemCode.conflict,
        );
      } finally {
        release.complete();
        _value(await writing);
        await closing;
      }
      final reopened = await _open(directory);
      try {
        expect(
          _value(await reopened.loadOriginal(message.raw.sha256))!.bytes,
          message.raw.bytes,
        );
      } finally {
        await reopened.close();
      }
    },
  );

  test(
    'future native schema is refused without alteration or a leaked owner',
    () async {
      await _seed(directory);
      var database = sqlite.sqlite3.open(_archivePath(directory));
      final originalVersion =
          database.select('PRAGMA user_version').single.values.single as int;
      final before = database
          .select('SELECT id,raw,metadata_hash FROM archive_items')
          .single;
      database.execute('PRAGMA user_version=99');
      database.close();
      _failure(
        await openNativeMailArchive(
          appDirectory: directory,
          profile: fixture.archiveCrashProfile,
        ),
        MailProblemCode.unsupported,
      );
      database = sqlite.sqlite3.open(_archivePath(directory));
      try {
        expect(database.select('PRAGMA user_version').single.values.single, 99);
        final after = database
            .select('SELECT id,raw,metadata_hash FROM archive_items')
            .single;
        expect(after['id'], before['id']);
        expect(after['raw'], before['raw']);
        expect(after['metadata_hash'], before['metadata_hash']);
        database.execute('PRAGMA user_version=$originalVersion');
      } finally {
        database.close();
      }
      final reopened = await _open(directory);
      try {
        expect(_value(await reopened.statistics()).messages, 1);
      } finally {
        await reopened.close();
      }
    },
  );

  test(
    'identical profile IDs in different hosts have distinct native archives',
    () async {
      final otherProfile = MailProfileId(
        fixture.archiveCrashProfile.value,
        hostId: 'other-host',
      );
      final first = await _open(directory);
      final other = await _open(directory, profile: otherProfile);
      try {
        _value(
          await first.archiveMessage(
            fixture.archiveCrashMessage(pending: false),
            origin: fixture.archiveCrashOrigin,
          ),
        );
        expect(_value(await other.statistics()).messages, 0);
        expect(
          _archivePath(directory),
          isNot(_archivePath(directory, profile: otherProfile)),
        );
        expect(File(_archivePath(directory)).existsSync(), isTrue);
        expect(
          File(_archivePath(directory, profile: otherProfile)).existsSync(),
          isTrue,
        );
      } finally {
        await first.close();
        await other.close();
      }
    },
  );

  test(
    'removing a live account and its cache container preserves the separate archive',
    () async {
      final profile = fixture.archiveCrashProfile;
      final archive = await _open(directory);
      final cache = _value(
        await openNativeMailStore(appDirectory: directory, profile: profile),
      );
      final account = MailAccountId('live-cache', profile: profile);
      final mailbox = MailMailboxId('INBOX', account: account);
      final id = MailMessageId('cached-original');
      final remote = MailImapIdentity(mailbox: mailbox, uidValidity: 1, uid: 1);
      final original = fixture.archiveCrashMessage(pending: false);
      try {
        _value(
          await cache.createAccount(
            MailStoreAccount(
              id: account,
              provider: MailProviderKind.imap,
              displayName: 'Synthetic live account',
            ),
          ),
        );
        _value(
          await cache.commitSyncPage(
            MailSyncPage(
              mailbox: mailbox,
              upserts: [
                MailHeaderRecord(
                  id: id,
                  remote: remote,
                  envelope: original.envelope,
                ),
              ],
              tombstones: const [],
              next: MailCursor(mailbox: mailbox, value: 'one'),
              hasMore: false,
            ),
            expectedCursor: null,
            lease: MailAccountSession(account).begin(),
          ),
        );
        _value(
          await cache.cacheMessage(
            account,
            id,
            MailMessage(
              raw: original.raw,
              envelope: original.envelope,
              body: original.body,
              localId: id,
              remoteIdentity: remote,
            ),
          ),
        );
        _value(
          await archive.archiveMessage(
            original,
            origin: fixture.archiveCrashOrigin,
          ),
        );
        expect(
          _value(await cache.loadCachedMessage(account, id))!.raw.bytes,
          original.raw.bytes,
        );
        _value(await cache.removeAccount(account));
        expect(_value(await cache.listAccounts()), isEmpty);
        await cache.close();
        await Directory(
          p.join(directory.path, 'quds_mail'),
        ).delete(recursive: true);
        expect(
          _value(await archive.loadOriginal(original.raw.sha256))!.bytes,
          original.raw.bytes,
        );
        expect(_value(await archive.verifyIntegrity()).issues, isEmpty);
      } finally {
        await cache.close();
        await archive.close();
      }
      final reopened = await _open(directory);
      try {
        expect(
          _value(await reopened.loadOriginal(original.raw.sha256))!.bytes,
          original.raw.bytes,
        );
      } finally {
        await reopened.close();
      }
    },
  );

  test(
    'clean native integrity verification leaves every persisted row unchanged',
    () async {
      await _seed(directory);
      final before = _snapshotArchiveRows(directory);
      final archive = await _open(directory);
      try {
        final report = _value(await archive.verifyIntegrity());
        expect(report.processed, 1);
        expect(report.issues, isEmpty);
      } finally {
        await archive.close();
      }
      expect(_snapshotArchiveRows(directory), before);
    },
  );

  test(
    'corrupt native FTS postings are detected and rebuilt without changing original bytes',
    () async {
      await _seed(directory);
      _corruptPostingBlocks(directory);
      final original = fixture.archiveCrashMessage(pending: false);
      final archive = await _open(directory);
      try {
        expect(
          _value(await archive.loadOriginal(original.raw.sha256))!.bytes,
          original.raw.bytes,
        );
        _failure(
          await archive.search(
            const MailArchiveSearchRequest(query: 'baselineledger'),
          ),
          MailProblemCode.storageFailure,
        );
        _failure(
          await archive.verifyIntegrity(),
          MailProblemCode.storageFailure,
        );
        final repaired = _value(await archive.rebuildIndex());
        expect(repaired.processed, 1);
        expect(repaired.issues, isEmpty);
        expect(
          _value(
            await archive.search(
              const MailArchiveSearchRequest(query: 'baselineledger'),
            ),
          ).total,
          1,
        );
        expect(
          _value(await archive.loadOriginal(original.raw.sha256))!.bytes,
          original.raw.bytes,
        );
        expect(_value(await archive.verifyIntegrity()).issues, isEmpty);
      } finally {
        await archive.close();
      }
      final reopened = await _open(directory);
      try {
        expect(_value(await reopened.verifyIntegrity()).issues, isEmpty);
        expect(
          _value(
            await reopened.search(
              const MailArchiveSearchRequest(query: 'baselineledger'),
            ),
          ).total,
          1,
        );
        expect(
          _value(await reopened.loadOriginal(original.raw.sha256))!.bytes,
          original.raw.bytes,
        );
      } finally {
        await reopened.close();
      }
    },
  );

  test(
    'failure before native repair commit rolls back the structural FTS rebuild',
    () async {
      await _seed(directory);
      _corruptPostingBlocks(directory);
      final before = _snapshotArchiveRows(directory);
      final archive = await _open(
        directory,
        fault: (point) async {
          if (point == MailArchiveCheckpoint.beforeCommit) {
            throw StateError(
              'Synthetic storage failure before structural repair commit',
            );
          }
        },
      );
      try {
        _failure(await archive.rebuildIndex(), MailProblemCode.storageFailure);
        _failure(
          await archive.search(
            const MailArchiveSearchRequest(query: 'baselineledger'),
          ),
          MailProblemCode.storageFailure,
        );
        final original = fixture.archiveCrashMessage(pending: false);
        expect(
          _value(await archive.loadOriginal(original.raw.sha256))!.bytes,
          original.raw.bytes,
        );
      } finally {
        await archive.close();
      }
      expect(_snapshotArchiveRows(directory), before);
      final retry = await _open(directory);
      try {
        expect(_value(await retry.rebuildIndex()).issues, isEmpty);
        expect(_value(await retry.verifyIntegrity()).issues, isEmpty);
        expect(
          _value(
            await retry.search(
              const MailArchiveSearchRequest(query: 'baselineledger'),
            ),
          ).total,
          1,
        );
      } finally {
        await retry.close();
      }
    },
  );

  for (final scenario in fixture.ArchiveCrashScenario.values) {
    test(
      'SIGKILL ${scenario.name} honors the durable archive transaction boundary',
      () async {
        await _seed(directory);
        await _killAtBarrier(directory, scenario);
        final committed = scenario == fixture.ArchiveCrashScenario.committed;
        final baseline = fixture.archiveCrashMessage(pending: false);
        final pending = fixture.archiveCrashMessage(pending: true);
        for (var reopen = 0; reopen < 2; reopen++) {
          final archive = await _open(directory);
          try {
            expect(
              _value(await archive.loadOriginal(baseline.raw.sha256))!.bytes,
              baseline.raw.bytes,
            );
            final recovered = _value(
              await archive.loadOriginal(pending.raw.sha256),
            );
            expect(recovered?.bytes, committed ? pending.raw.bytes : null);
            final stats = _value(await archive.statistics());
            expect(stats.messages, committed ? 2 : 1);
            expect(stats.indexedMessages, stats.messages);
            expect(stats.origins, stats.messages);
            expect(
              stats.rawBytes,
              baseline.raw.length + (committed ? pending.raw.length : 0),
            );
            final found = _value(
              await archive.search(
                const MailArchiveSearchRequest(query: 'pendingledger'),
              ),
            );
            expect(found.total, committed ? 1 : 0);
            expect(
              _value(await archive.listOrigins(pending.raw.sha256)),
              hasLength(committed ? 1 : 0),
            );
            expect(_value(await archive.verifyIntegrity()).issues, isEmpty);
          } finally {
            await archive.close();
          }
        }
        final database = sqlite.sqlite3.open(_archivePath(directory));
        try {
          expect(
            database
                .select('SELECT count(*) AS n FROM archive_items')
                .single['n'],
            committed ? 2 : 1,
          );
          expect(
            database
                .select('SELECT count(*) AS n FROM archive_fts')
                .single['n'],
            committed ? 2 : 1,
          );
          expect(
            database
                .select('SELECT count(*) AS n FROM archive_origins')
                .single['n'],
            committed ? 2 : 1,
          );
          expect(
            database.select('PRAGMA integrity_check').single.values.single,
            'ok',
          );
        } finally {
          database.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 90)),
      skip: Platform.isWindows ? 'Requires POSIX SIGKILL.' : false,
    );
  }
}
