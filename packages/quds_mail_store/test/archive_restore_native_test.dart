@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';
import 'package:test/test.dart';

import '../tool/archive_restore_crash_fixture.dart' as fixture;

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _failure<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

final _sourceProfile = MailProfileId('source', hostId: 'old-device');
final _targetProfile = MailProfileId('target', hostId: 'new-device');
const _firstOrigins = [
  MailArchiveOrigin(
    source: 'Personal café مرحبا',
    folder: '/Inbox/2026',
    sourceMessageId: 'imap:one',
  ),
  MailArchiveOrigin(
    source: 'Secondary',
    folder: '/Sent/Projects',
    sourceMessageId: 'copy:one',
  ),
];
const _secondOrigins = [
  MailArchiveOrigin(source: 'Local', folder: '/Originals', sourceMessageId: ''),
];

MailBytes _bytes(String subject) => MailBytes(
  Uint8List.fromList([
    ...utf8.encode('Subject: $subject\r\n\r\nOriginal $subject'),
    0,
    128,
    255,
    13,
    10,
  ]),
);

final class _Codec implements MailCodec {
  const _Codec({this.partial = false});
  final bool partial;

  @override
  MailParseResult parse(
    Uint8List bytes, {
    MailReadBudget budget = const MailReadBudget(),
    MailCancellationToken? cancellation,
  }) {
    cancellation?.throwIfCancelled();
    budget.validate();
    return MailParseResult(
      status: partial ? MailParseStatus.partial : MailParseStatus.complete,
      message: MailMessage(
        raw: MailBytes(bytes),
        envelope: MailEnvelope(subject: 'Restored selection'),
        body: const MailBody(plainText: 'Restored body for search'),
      ),
    );
  }
}

List<String> _originKeys(List<MailArchiveOrigin> origins) =>
    origins
        .map(
          (origin) => jsonEncode([
            origin.source,
            origin.folder,
            origin.sourceMessageId,
          ]),
        )
        .toList()
      ..sort();

void main() {
  late Directory root;
  late Directory package;
  late List<MailBytes> originals;
  late SqliteMailArchive target;
  late NativeMailArchiveRestorer restorer;
  late MailArchiveRestorePlan preview;

  Future<SqliteMailArchive> openTarget({
    MailArchiveLimits limits = const MailArchiveLimits(),
  }) async => _value(
    await openNativeMailArchive(
      appDirectory: root,
      profile: _targetProfile,
      limits: limits,
      clock: () => DateTime.utc(2026, 11, 20),
    ),
  );

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final created = await Directory.systemTemp.createTemp('archive-restore-');
    root = Directory(await created.resolveSymbolicLinks());
    originals = [_bytes('First'), _bytes('Second')];
    final source = _value(
      await openNativeMailArchive(appDirectory: root, profile: _sourceProfile),
    );
    try {
      for (var index = 0; index < originals.length; index++) {
        _value(
          await source.archiveMessageWithOrigins(
            const _Codec().parse(originals[index].bytes).message!,
            origins: index == 0 ? _firstOrigins : _secondOrigins,
          ),
        );
      }
      final plan = MailArchiveExportPlan(
        profile: _sourceProfile,
        createdAt: DateTime.utc(2026, 11, 19, 18),
        items: [
          for (var index = 0; index < originals.length; index++)
            MailArchiveExportItem(
              id: originals[index].sha256,
              byteLength: originals[index].length,
              origins: index == 0 ? _firstOrigins : _secondOrigins,
            ),
        ],
      );
      final exported = await NativeMailArchiveExporter(
        profile: source.profile,
        loadOriginal: source.loadOriginal,
      ).exportPlan(plan, parent: root);
      expect(exported.status, MailArchiveExportStatus.completed);
      package = Directory(exported.directoryPath!);
    } finally {
      await source.close();
    }
    target = await openTarget();
    restorer = NativeMailArchiveRestorer(
      archive: target,
      codec: const _Codec(),
    );
    preview = _value(await restorer.inspect(package));
  });

  tearDown(() async {
    await target.close();
    await root.delete(recursive: true);
  });

  test('read-only preview identifies the full exported selection', () async {
    expect(preview.sourceProfile, _sourceProfile);
    expect(preview.createdAt, DateTime.utc(2026, 11, 19, 18));
    expect(preview.messageCount, 2);
    expect(preview.originCount, 3);
    expect(
      preview.totalBytes,
      originals.fold<int>(0, (n, bytes) => n + bytes.length),
    );
    expect(preview.directoryPath, package.path);
    expect(preview.manifestSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(_value(await target.statistics()).messages, 0);
    await File(p.join(package.path, '${originals.first.sha256}.eml')).delete();
    expect(_value(await restorer.inspect(package)).messageCount, 2);
    expect(_value(await target.statistics()).messages, 0);
  });

  test(
    'restores exact originals and all origins into a different persistent profile',
    () async {
      final before = {
        for (final file in package.listSync().whereType<File>())
          p.basename(file.path): await file.readAsBytes(),
      };
      final events = <MailArchiveRestoreProgress>[];
      final report = await restorer.restore(preview, onProgress: events.add);
      expect(report.status, MailArchiveRestoreStatus.completed);
      expect(report.planned, 2);
      expect(report.saved, 2);
      expect(report.duplicates, 0);
      expect(report.failed, 0);
      expect(report.processed, 2);
      expect(report.originsAdded, 3);
      expect(report.bytes, preview.totalBytes);
      expect(target.profile, _targetProfile);
      expect(events.first.phase, MailArchiveRestorePhase.started);
      expect(events.last.status, MailArchiveRestoreStatus.completed);
      final diagnosticText = jsonEncode(
        events.map((event) => event.toJson()).toList(),
      );
      expect(diagnosticText, isNot(contains(package.path)));
      expect(diagnosticText, isNot(contains('Secondary')));
      expect(diagnosticText, isNot(contains(originals.first.sha256)));
      for (final file in package.listSync().whereType<File>()) {
        expect(await file.readAsBytes(), before[p.basename(file.path)]);
      }
      expect(package.listSync(), hasLength(before.length));
      await target.close();
      target = await openTarget();
      final stats = _value(await target.statistics());
      expect(stats.messages, 2);
      expect(stats.origins, 3);
      for (var index = 0; index < originals.length; index++) {
        expect(
          _value(await target.loadOriginal(originals[index].sha256))!.bytes,
          originals[index].bytes,
        );
        expect(
          _originKeys(
            _value(await target.listOrigins(originals[index].sha256)),
          ),
          _originKeys(index == 0 ? _firstOrigins : _secondOrigins),
        );
      }
      expect(
        _value(
          await target.search(
            const MailArchiveSearchRequest(query: 'bcontent:restored'),
          ),
        ).total,
        2,
      );
    },
  );

  test(
    'rerunning verifies duplicates and never accumulates provenance or counts',
    () async {
      expect((await restorer.restore(preview)).saved, 2);
      final repeated = await restorer.restore(preview);
      expect(repeated.status, MailArchiveRestoreStatus.completed);
      expect(repeated.saved, 0);
      expect(repeated.duplicates, 2);
      expect(repeated.originsAdded, 0);
      expect(repeated.bytes, preview.totalBytes);
      expect(_value(await target.statistics()).origins, 3);
    },
  );

  test('merges exported origins with an existing destination origin', () async {
    const local = MailArchiveOrigin(source: 'Destination', folder: '/Kept');
    _value(
      await target.archiveMessage(
        const _Codec().parse(originals.first.bytes).message!,
        origin: local,
      ),
    );
    final report = await restorer.restore(preview);
    expect(report.saved, 1);
    expect(report.duplicates, 1);
    expect(report.originsAdded, 3);
    expect(
      _originKeys(_value(await target.listOrigins(originals.first.sha256))),
      _originKeys([..._firstOrigins, local]),
    );
  });

  test(
    'cancel after one commit retains all its origins and a rerun completes',
    () async {
      final cancel = MailCancellationSource();
      final report = await restorer.restore(
        preview,
        cancellation: cancel.token,
        onProgress: (event) {
          if (event.saved == 1) cancel.cancel();
        },
      );
      expect(report.status, MailArchiveRestoreStatus.cancelled);
      expect(report.saved, 1);
      expect(report.failed, 0);
      expect(report.originsAdded, 2);
      expect(report.bytes, originals.first.length);
      final retry = await restorer.restore(preview);
      expect(retry.status, MailArchiveRestoreStatus.completed);
      expect(retry.saved, 1);
      expect(retry.duplicates, 1);
      expect(retry.originsAdded, 1);
    },
  );

  test(
    'missing original reports a partial result and a retry fills the gap',
    () async {
      final missing = File(
        p.join(package.path, '${originals.first.sha256}.eml'),
      );
      await missing.delete();
      final report = await restorer.restore(preview);
      expect(report.status, MailArchiveRestoreStatus.partial);
      expect(report.saved, 1);
      expect(report.failed, 1);
      expect(report.failures.single.ordinal, 1);
      expect(report.failures.single.code, MailProblemCode.unavailable);
      await missing.writeAsBytes(originals.first.bytes, flush: true);
      final retry = await restorer.restore(preview);
      expect(retry.saved, 1);
      expect(retry.duplicates, 1);
      expect(retry.status, MailArchiveRestoreStatus.completed);
    },
  );

  test('wrong hashes and wrong sizes never enter the destination', () async {
    final first = File(p.join(package.path, '${originals.first.sha256}.eml'));
    final damaged = originals.first.bytes.toList()..[0] ^= 1;
    await first.writeAsBytes(damaged);
    await File(
      p.join(package.path, '${originals.last.sha256}.eml'),
    ).writeAsString('short');
    final report = await restorer.restore(preview);
    expect(report.status, MailArchiveRestoreStatus.failed);
    expect(report.failed, 2);
    expect(report.saved, 0);
    expect(
      report.failures.map((failure) => failure.code),
      everyElement(MailProblemCode.conflict),
    );
    expect(_value(await target.statistics()).messages, 0);
    expect(await first.readAsBytes(), damaged);
  });

  test('staging and unrelated EML files are ignored', () async {
    final staging = await Directory(
      p.join(package.path, '.pending-unfinished'),
    ).create();
    await File(
      p.join(staging.path, 'original.eml'),
    ).writeAsString('incomplete');
    await File(p.join(package.path, 'other.eml')).writeAsString('unrelated');
    final report = await restorer.restore(preview);
    expect(report.status, MailArchiveRestoreStatus.completed);
    expect(report.saved, 2);
    expect(_value(await target.statistics()).messages, 2);
    expect(File(p.join(staging.path, 'original.eml')).existsSync(), isTrue);
  });

  test('observer exceptions cannot alter committed results', () async {
    final report = await restorer.restore(
      preview,
      onProgress: (_) => throw StateError('observer'),
    );
    expect(report.status, MailArchiveRestoreStatus.completed);
    expect(report.saved, 2);
    expect(report.observerErrors, 4);
    expect(_value(await target.statistics()).origins, 3);
  });

  test(
    'pre-cancelled inspection and restore leave destination empty',
    () async {
      final cancel = MailCancellationSource()..cancel();
      _failure(
        await restorer.inspect(package, cancellation: cancel.token),
        MailProblemCode.cancelled,
      );
      final report = await restorer.restore(
        preview,
        cancellation: cancel.token,
      );
      expect(report.status, MailArchiveRestoreStatus.cancelled);
      expect(report.processed, 0);
      expect(_value(await target.statistics()).messages, 0);
    },
  );

  test(
    'new restore limits revalidate a preview without silently truncating',
    () async {
      final strict = NativeMailArchiveRestorer(
        archive: target,
        codec: const _Codec(),
        limits: const MailArchiveExportLimits(maxMessages: 1),
      );
      _failure(await strict.inspect(package), MailProblemCode.quotaExceeded);
      final report = await strict.restore(preview);
      expect(report.status, MailArchiveRestoreStatus.failed);
      expect(report.problem?.code, MailProblemCode.quotaExceeded);
      expect(report.saved, 0);
      expect(_value(await target.statistics()).messages, 0);
    },
  );

  test(
    'invalid UTF-8 and malformed manifests fail safely before mutation',
    () async {
      final manifest = File(p.join(package.path, 'manifest.json'));
      await manifest.writeAsBytes([255, 254, 0]);
      _failure(await restorer.inspect(package), MailProblemCode.invalidInput);
      await manifest.writeAsString('{"version":999}');
      expect(
        await restorer.inspect(package),
        isA<MailFailure<MailArchiveRestorePlan>>(),
      );
      expect(_value(await target.statistics()).messages, 0);
    },
  );

  test(
    'partial parsing preserves original and exposes index warnings',
    () async {
      final partial = NativeMailArchiveRestorer(
        archive: target,
        codec: const _Codec(partial: true),
      );
      final report = await partial.restore(preview);
      expect(report.status, MailArchiveRestoreStatus.completed);
      expect(report.saved, 2);
      expect(report.indexWarnings, 2);
      expect(
        _value(await target.loadOriginal(originals.first.sha256))!.bytes,
        originals.first.bytes,
      );
    },
  );

  test('empty exported selection completes without adding messages', () async {
    final emptyRoot = await Directory(
      p.join(root.path, 'empty-export'),
    ).create();
    await File(p.join(emptyRoot.path, 'manifest.json')).writeAsString(
      encodeMailArchiveExportManifest(
        MailArchiveExportPlan(
          profile: _sourceProfile,
          createdAt: DateTime.utc(2026, 11, 19),
          items: const [],
        ),
        const MailArchiveExportLimits(),
      ),
    );
    final plan = _value(await restorer.inspect(emptyRoot));
    final report = await restorer.restore(plan);
    expect(report.status, MailArchiveRestoreStatus.completed);
    expect(report.planned, 0);
    expect(report.processed, 0);
    expect(_value(await target.statistics()).messages, 0);
  });

  test(
    'SIGKILL after one atomic restore releases ownership and reruns safely',
    () async {
      final library = await Isolate.resolvePackageUri(
        Uri.parse('package:quds_mail_store/quds_mail_store.dart'),
      );
      final packageRoot = File.fromUri(library!).parent.parent;
      final destination = await Directory(
        p.join(root.path, 'crash-target'),
      ).create();
      final dart = p.join(p.dirname(Platform.resolvedExecutable), 'dart');
      final process = await Process.start(dart, [
        'run',
        p.join(packageRoot.path, 'tool/archive_restore_crash_fixture.dart'),
        package.path,
        destination.path,
      ], workingDirectory: packageRoot.path);
      final ready = Completer<int>();
      final errors = StringBuffer();
      final stderr = process.stderr
          .transform(utf8.decoder)
          .listen(errors.write);
      final stdout = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final match = RegExp(r'^READY (\d+)$').firstMatch(line);
              if (match != null && !ready.isCompleted) {
                ready.complete(int.parse(match[1]!));
              }
            },
            onDone: () {
              if (!ready.isCompleted) {
                ready.completeError(
                  StateError('Fixture exited before barrier: $errors'),
                );
              }
            },
          );
      int? child;
      SqliteMailArchive? recovered;
      try {
        child = await ready.future.timeout(const Duration(seconds: 45));
        _failure(
          await openNativeMailArchive(
            appDirectory: destination,
            profile: fixture.restoreCrashProfile,
          ),
          MailProblemCode.conflict,
        );
        expect(Process.killPid(child, ProcessSignal.sigkill), isTrue);
        expect(
          await process.exitCode.timeout(const Duration(seconds: 10)),
          isNot(0),
        );
        child = null;
        final opened = _value(
          await openNativeMailArchive(
            appDirectory: destination,
            profile: fixture.restoreCrashProfile,
          ),
        );
        recovered = opened;
        final firstStats = _value(await opened.statistics());
        expect(firstStats.messages, 1);
        expect(firstStats.origins, 2);
        expect(
          _originKeys(_value(await opened.listOrigins(originals.first.sha256))),
          _originKeys(_firstOrigins),
        );
        final recovery = NativeMailArchiveRestorer(
          archive: opened,
          codec: const fixture.RestoreCrashCodec(),
        );
        final recoveryPlan = _value(await recovery.inspect(package));
        final resumed = await recovery.restore(recoveryPlan);
        expect(resumed.status, MailArchiveRestoreStatus.completed);
        expect(resumed.saved, 1);
        expect(resumed.duplicates, 1);
        expect(resumed.originsAdded, 1);
        final repeated = await recovery.restore(recoveryPlan);
        expect(repeated.saved, 0);
        expect(repeated.duplicates, 2);
        expect(repeated.originsAdded, 0);
        for (final original in originals) {
          expect(
            _value(await opened.loadOriginal(original.sha256))!.bytes,
            original.bytes,
          );
        }
        expect(
          _value(
            await opened.search(
              const MailArchiveSearchRequest(query: 'restoredledger'),
            ),
          ).total,
          2,
        );
        expect(_value(await opened.verifyIntegrity()).issues, isEmpty);
      } finally {
        await recovered?.close();
        if (child != null) Process.killPid(child, ProcessSignal.sigkill);
        process.kill(ProcessSignal.sigkill);
        await stdout.cancel();
        await stderr.cancel();
      }
    },
    timeout: const Timeout(Duration(seconds: 75)),
  );
}
