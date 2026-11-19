@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/src/archive_export_models.dart';
import 'package:quds_mail_store/src/archive_export_native.dart';
import 'package:quds_mail_store/src/archive_models.dart';
import 'package:quds_mail_store/src/errors.dart';
import 'package:test/test.dart';

import '../tool/archive_export_crash_fixture.dart' as fixture;

final _profile = MailProfileId('exports', hostId: 'native-export-tests');
const _limits = MailArchiveExportLimits();

MailBytes _bytes(String text) =>
    MailBytes(Uint8List.fromList([...utf8.encode(text), 0, 128, 255, 13, 10]));

MailArchiveExportPlan _plan(
  List<MailBytes> originals, {
  MailProfileId? profile,
}) => MailArchiveExportPlan(
  profile: profile ?? _profile,
  createdAt: DateTime.utc(2026, 11, 19, 17),
  items: [
    for (var index = 0; index < originals.length; index++)
      MailArchiveExportItem(
        id: originals[index].sha256,
        byteLength: originals[index].length,
        origins: [
          MailArchiveOrigin(
            source: 'Personal café مرحبا',
            folder: '/Inbox/2026',
            sourceMessageId: 'source:$index',
          ),
        ],
      ),
  ],
);

void _problem(MailArchiveExportReport report, MailProblemCode code) {
  expect(report.status, isNot(MailArchiveExportStatus.completed));
  expect(report.problem?.code, code);
}

Matcher _throwsCode(MailProblemCode code) => throwsA(
  isA<MailStoreStorageException>().having((error) => error.code, 'code', code),
);

Map<String, Object?> _manifest(String value) =>
    Map<String, Object?>.from(jsonDecode(value) as Map<String, Object?>);

String _redigest(Map<String, Object?> manifest) {
  manifest['sha256'] = crypto.sha256
      .convert(utf8.encode(jsonEncode(manifest['payload'])))
      .toString();
  return jsonEncode(manifest);
}

void main() {
  late Directory parent;
  late List<MailBytes> originals;
  late List<String> loads;
  late NativeMailArchiveExporter exporter;

  setUp(() async {
    parent = await Directory.systemTemp.createTemp('archive-export-test-');
    originals = [
      _bytes('Subject: First\r\n\r\nOriginal one'),
      _bytes('Subject: Second\r\n\r\nOriginal two'),
    ];
    loads = [];
    exporter = NativeMailArchiveExporter(
      profile: _profile,
      loadOriginal: (id) async {
        loads.add(id);
        final matches = originals.where((bytes) => bytes.sha256 == id);
        return MailSuccess(matches.isEmpty ? null : matches.single);
      },
    );
  });

  tearDown(() async {
    await parent.delete(recursive: true);
  });

  test('bulk export preserves exact originals and frozen provenance', () async {
    final unrelated = File(
      p.join(parent.path, '${originals.first.sha256}.eml'),
    );
    await unrelated.writeAsString('unrelated');
    final events = <MailArchiveExportProgress>[];
    final plan = _plan(originals);
    final report = await exporter.exportPlan(
      plan,
      parent: parent,
      onProgress: events.add,
    );
    expect(report.status, MailArchiveExportStatus.completed);
    expect(report.written, 2);
    expect(report.existing, 0);
    expect(report.failed, 0);
    expect(report.bytes, plan.totalBytes);
    expect(report.processed, report.planned);
    expect(await unrelated.readAsString(), 'unrelated');
    final root = Directory(report.directoryPath!);
    for (final original in originals) {
      expect(
        await File(p.join(root.path, '${original.sha256}.eml')).readAsBytes(),
        original.bytes,
      );
    }
    final encoded = await File(
      p.join(root.path, 'manifest.json'),
    ).readAsString();
    final decoded = decodeMailArchiveExportManifest(encoded, _limits);
    expect(decoded.profile, _profile);
    expect(decoded.createdAt, plan.createdAt);
    expect(
      decoded.items.map((item) => item.id),
      plan.items.map((item) => item.id),
    );
    expect(decoded.items.first.origins.single.source, 'Personal café مرحبا');
    expect(decoded.items.first.origins.single.folder, '/Inbox/2026');
    expect(encoded, isNot(contains('Subject: First')));
    expect(events.first.phase, MailArchiveExportPhase.started);
    expect(events.last.status, MailArchiveExportStatus.completed);
    expect(
      jsonEncode(events.map((event) => event.toJson()).toList()),
      isNot(contains(root.path)),
    );
  });

  test(
    'cancel after publication reports it and resume verifies before skipping',
    () async {
      final cancellation = MailCancellationSource();
      final first = await exporter.exportPlan(
        _plan(originals),
        parent: parent,
        cancellation: cancellation.token,
        onProgress: (event) {
          if (event.written == 1) cancellation.cancel();
        },
      );
      expect(first.status, MailArchiveExportStatus.cancelled);
      expect(first.written, 1);
      expect(first.failed, 0);
      expect(first.bytes, originals.first.length);
      expect(loads, [originals.first.sha256]);
      final root = Directory(first.directoryPath!);
      await Directory(p.join(root.path, '.pending-crash')).create();
      await File(
        p.join(root.path, '.pending-crash', 'original.eml'),
      ).writeAsString('incomplete staging');
      loads.clear();
      final resumed = await exporter.resume(root);
      expect(resumed.status, MailArchiveExportStatus.completed);
      expect(resumed.existing, 1);
      expect(resumed.written, 1);
      expect(loads, [originals.last.sha256]);
      expect(
        File(p.join(root.path, '.pending-crash', 'original.eml')).existsSync(),
        isTrue,
      );
      loads.clear();
      final again = await exporter.resume(root);
      expect(again.status, MailArchiveExportStatus.completed);
      expect(again.existing, 2);
      expect(again.written, 0);
      expect(loads, isEmpty);
    },
  );

  test('pre-cancelled export leaves no destination or source load', () async {
    final cancellation = MailCancellationSource()..cancel();
    final report = await exporter.exportPlan(
      _plan(originals),
      parent: parent,
      cancellation: cancellation.token,
    );
    expect(report.status, MailArchiveExportStatus.cancelled);
    expect(report.directoryPath, isNull);
    expect(parent.listSync(), isEmpty);
    expect(loads, isEmpty);
  });

  test(
    'source failure keeps successful originals and retry restores the gap',
    () async {
      final failing = NativeMailArchiveExporter(
        profile: _profile,
        loadOriginal: (id) async => id == originals.last.sha256
            ? const MailFailure(MailProblem(MailProblemCode.unavailable))
            : MailSuccess(originals.first),
      );
      final initial = await failing.exportPlan(
        _plan(originals),
        parent: parent,
      );
      expect(initial.status, MailArchiveExportStatus.partial);
      expect(initial.written, 1);
      expect(initial.failed, 1);
      expect(initial.failures.single.ordinal, 2);
      final resumed = await exporter.resume(Directory(initial.directoryPath!));
      expect(resumed.status, MailArchiveExportStatus.completed);
      expect(resumed.existing, 1);
      expect(resumed.written, 1);
    },
  );

  test(
    'loader cannot substitute different bytes for the frozen original',
    () async {
      final wrong = NativeMailArchiveExporter(
        profile: _profile,
        loadOriginal: (_) async => MailSuccess(_bytes('wrong original')),
      );
      final report = await wrong.exportPlan(_plan(originals), parent: parent);
      _problem(report, MailProblemCode.conflict);
      expect(report.written, 0);
      expect(report.failed, 2);
      expect(
        Directory(report.directoryPath!).listSync().whereType<File>().where(
          (file) => file.path.endsWith('.eml'),
        ),
        isEmpty,
      );
    },
  );

  for (final sameLength in [false, true]) {
    test(
      'resume refuses changed EML (same length: $sameLength) without overwrite',
      () async {
        final first = await exporter.exportPlan(
          _plan(originals),
          parent: parent,
        );
        final root = Directory(first.directoryPath!);
        final file = File(p.join(root.path, '${originals.first.sha256}.eml'));
        final damaged = sameLength
            ? List<int>.filled(originals.first.length, 65)
            : <int>[1, 2];
        await file.writeAsBytes(damaged);
        loads.clear();
        final resumed = await exporter.resume(root);
        _problem(resumed, MailProblemCode.conflict);
        expect(resumed.failed, 1);
        expect(resumed.existing, 1);
        expect(resumed.written, 0);
        expect(await file.readAsBytes(), damaged);
        expect(loads, isEmpty);
      },
    );
  }

  test(
    'observed EML symlink is rejected and its target is untouched',
    () async {
      final first = await exporter.exportPlan(_plan(originals), parent: parent);
      final root = Directory(first.directoryPath!);
      final path = p.join(root.path, '${originals.first.sha256}.eml');
      await File(path).delete();
      final external = File(p.join(parent.path, 'external.eml'));
      await external.writeAsString('external contents');
      await Link(path).create(external.path);
      final resumed = await exporter.resume(root);
      _problem(resumed, MailProblemCode.conflict);
      expect(resumed.failed, 1);
      expect(await external.readAsString(), 'external contents');
      expect(
        FileSystemEntity.typeSync(path, followLinks: false),
        FileSystemEntityType.link,
      );
    },
  );

  for (final name in [
    'manifest.json',
    '.export-owner.sqlite3',
    '.export-owner.sqlite3-journal',
  ]) {
    test('resume rejects a $name symlink before opening it', () async {
      final first = await exporter.exportPlan(_plan(originals), parent: parent);
      final root = Directory(first.directoryPath!);
      final file = File(p.join(root.path, name));
      if (file.existsSync()) await file.delete();
      final external = File(p.join(parent.path, 'external'));
      await external.writeAsString('external contents');
      await Link(file.path).create(external.path);
      final resumed = await exporter.resume(root);
      _problem(resumed, MailProblemCode.conflict);
      expect(resumed.processed, 0);
      expect(await external.readAsString(), 'external contents');
    });
  }

  test('resume rejects a symlink selected as the export directory', () async {
    final first = await exporter.exportPlan(_plan(originals), parent: parent);
    final alias = Link(p.join(parent.path, 'alias'));
    await alias.create(first.directoryPath!);
    final resumed = await exporter.resume(Directory(alias.path));
    _problem(resumed, MailProblemCode.conflict);
  });

  test('foreign archive profile cannot start or resume this export', () async {
    final foreign = NativeMailArchiveExporter(
      profile: MailProfileId('other', hostId: _profile.hostId),
      loadOriginal: (_) async => throw StateError('must not load'),
    );
    final rejected = await foreign.exportPlan(_plan(originals), parent: parent);
    _problem(rejected, MailProblemCode.permissionDenied);
    expect(parent.listSync(), isEmpty);
    final first = await exporter.exportPlan(_plan(originals), parent: parent);
    final resumed = await foreign.resume(Directory(first.directoryPath!));
    _problem(resumed, MailProblemCode.permissionDenied);
    expect(resumed.processed, 0);
  });

  test(
    'observer exceptions are counted without affecting exported originals',
    () async {
      final report = await exporter.exportPlan(
        _plan(originals),
        parent: parent,
        onProgress: (_) => throw StateError('observer-only'),
      );
      expect(report.status, MailArchiveExportStatus.completed);
      expect(report.written, 2);
      expect(report.observerErrors, 4);
    },
  );

  test(
    'overlapping exporters reject the same directory and release ownership',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final holding = NativeMailArchiveExporter(
        profile: _profile,
        loadOriginal: (id) async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          return MailSuccess(
            originals.firstWhere((bytes) => bytes.sha256 == id),
          );
        },
      );
      final pending = holding.exportPlan(_plan(originals), parent: parent);
      await entered.future;
      final root = parent.listSync().whereType<Directory>().single;
      final conflicting = await exporter.resume(root);
      _problem(conflicting, MailProblemCode.conflict);
      release.complete();
      final first = await pending;
      expect(first.status, MailArchiveExportStatus.completed);
      final next = await exporter.resume(root);
      expect(next.status, MailArchiveExportStatus.completed);
    },
  );

  test(
    'bounded failures keep truthful totals without message identifiers',
    () async {
      final failing = NativeMailArchiveExporter(
        profile: _profile,
        limits: const MailArchiveExportLimits(maxFailures: 1),
        loadOriginal: (_) async =>
            const MailFailure(MailProblem(MailProblemCode.unavailable)),
      );
      final report = await failing.exportPlan(_plan(originals), parent: parent);
      expect(report.failed, 2);
      expect(report.failures, hasLength(1));
      expect(report.droppedFailures, 1);
      expect(report.failures.single.ordinal, 1);
    },
  );

  test(
    'empty selection exports a valid manifest and resumes without loading',
    () async {
      final report = await exporter.exportPlan(_plan([]), parent: parent);
      expect(report.status, MailArchiveExportStatus.completed);
      expect(report.planned, 0);
      final resumed = await exporter.resume(Directory(report.directoryPath!));
      expect(resumed.status, MailArchiveExportStatus.completed);
      expect(loads, isEmpty);
    },
  );

  test('manifest mutation during export prevents a completed result', () async {
    final cancellation = MailCancellationSource();
    final first = await exporter.exportPlan(
      _plan(originals),
      parent: parent,
      cancellation: cancellation.token,
      onProgress: (event) {
        if (event.phase == MailArchiveExportPhase.started) {
          cancellation.cancel();
        }
      },
    );
    final root = Directory(first.directoryPath!);
    final mutating = NativeMailArchiveExporter(
      profile: _profile,
      loadOriginal: (id) async {
        await File(p.join(root.path, 'manifest.json')).writeAsString('{}');
        return MailSuccess(originals.firstWhere((bytes) => bytes.sha256 == id));
      },
    );
    final report = await mutating.resume(root);
    _problem(report, MailProblemCode.conflict);
    expect(report.written, 2);
  });

  test('replacing the export directory during a load is detected', () async {
    final cancellation = MailCancellationSource();
    final first = await exporter.exportPlan(
      _plan(originals),
      parent: parent,
      cancellation: cancellation.token,
      onProgress: (event) {
        if (event.phase == MailArchiveExportPhase.started) {
          cancellation.cancel();
        }
      },
    );
    final root = Directory(first.directoryPath!);
    var replaced = false;
    final moving = NativeMailArchiveExporter(
      profile: _profile,
      loadOriginal: (id) async {
        if (!replaced) {
          await root.rename('${root.path}-moved');
          await root.create();
          replaced = true;
        }
        return MailSuccess(originals.firstWhere((bytes) => bytes.sha256 == id));
      },
    );
    final report = await moving.resume(root);
    _problem(report, MailProblemCode.conflict);
    expect(report.written, 0);
    expect(root.listSync(), isEmpty);
  });

  group('strict bounded manifest', () {
    test('plan and item lists are immutable snapshots', () {
      final origins = [const MailArchiveOrigin(source: 'Source')];
      final items = [
        MailArchiveExportItem(
          id: originals.first.sha256,
          byteLength: originals.first.length,
          origins: origins,
        ),
      ];
      final plan = MailArchiveExportPlan(
        profile: _profile,
        createdAt: DateTime.utc(2026),
        items: items,
      );
      origins.clear();
      items.clear();
      expect(plan.items, hasLength(1));
      expect(plan.items.single.origins, hasLength(1));
      expect(() => plan.items.clear(), throwsUnsupportedError);
    });

    test('changed digest is refused', () {
      final value = _manifest(
        encodeMailArchiveExportManifest(_plan(originals), _limits),
      );
      value['sha256'] = '0' * 64;
      expect(
        () => decodeMailArchiveExportManifest(jsonEncode(value), _limits),
        _throwsCode(MailProblemCode.conflict),
      );
    });

    test('unknown version and extra envelope keys are rejected', () {
      final value = _manifest(
        encodeMailArchiveExportManifest(_plan(originals), _limits),
      );
      value['version'] = 2;
      expect(
        () => decodeMailArchiveExportManifest(jsonEncode(value), _limits),
        _throwsCode(MailProblemCode.unsupported),
      );
      value['version'] = 1;
      value['path'] = '../outside';
      expect(
        () => decodeMailArchiveExportManifest(jsonEncode(value), _limits),
        _throwsCode(MailProblemCode.invalidInput),
      );
    });

    for (final id in ['../outside', 'a' * 63, 'A' * 64, 'g' * 64]) {
      test('unsafe identity is rejected: $id', () {
        final value = _manifest(
          encodeMailArchiveExportManifest(_plan(originals), _limits),
        );
        final payload = value['payload']! as Map<String, Object?>;
        final item =
            (payload['items']! as List<Object?>).first! as Map<String, Object?>;
        item['id'] = id;
        expect(
          () => decodeMailArchiveExportManifest(_redigest(value), _limits),
          _throwsCode(MailProblemCode.invalidInput),
        );
      });
    }

    for (final folder in [
      'relative',
      '/../outside',
      '/one//two',
      '/one\\two',
      '/bad\u0000path',
    ]) {
      test('invalid provenance folder is rejected: ${jsonEncode(folder)}', () {
        final value = _manifest(
          encodeMailArchiveExportManifest(_plan(originals), _limits),
        );
        final payload = value['payload']! as Map<String, Object?>;
        final item =
            (payload['items']! as List<Object?>).first! as Map<String, Object?>;
        final origin =
            (item['origins']! as List<Object?>).first! as Map<String, Object?>;
        origin['folder'] = folder;
        expect(
          () => decodeMailArchiveExportManifest(_redigest(value), _limits),
          _throwsCode(MailProblemCode.invalidInput),
        );
      });
    }

    test('duplicate original identities and origins are rejected', () {
      final plan = _plan([originals.first, originals.first]);
      expect(
        () => encodeMailArchiveExportManifest(plan, _limits),
        _throwsCode(MailProblemCode.invalidInput),
      );
      final duplicated = MailArchiveExportPlan(
        profile: _profile,
        createdAt: DateTime.utc(2026),
        items: [
          MailArchiveExportItem(
            id: originals.first.sha256,
            byteLength: originals.first.length,
            origins: const [
              MailArchiveOrigin(source: 'Same'),
              MailArchiveOrigin(source: 'Same'),
            ],
          ),
        ],
      );
      expect(
        () => encodeMailArchiveExportManifest(duplicated, _limits),
        _throwsCode(MailProblemCode.invalidInput),
      );
    });

    test(
      'message, item, origin, aggregate and encoded limits are enforced',
      () {
        final plan = _plan(originals);
        for (final limits in [
          const MailArchiveExportLimits(maxMessages: 1),
          const MailArchiveExportLimits(maxMessageBytes: 1),
          const MailArchiveExportLimits(maxOrigins: 1),
          MailArchiveExportLimits(
            maxMessageBytes: originals.first.length,
            maxTotalBytes: originals.first.length,
          ),
          const MailArchiveExportLimits(maxManifestBytes: 100),
        ]) {
          expect(
            () => encodeMailArchiveExportManifest(plan, limits),
            _throwsCode(MailProblemCode.quotaExceeded),
          );
        }
      },
    );

    test('invalid configuration and deep or malformed JSON are rejected', () {
      expect(
        () => encodeMailArchiveExportManifest(
          _plan(originals),
          const MailArchiveExportLimits(maxFailures: -1),
        ),
        _throwsCode(MailProblemCode.invalidInput),
      );
      for (final input in ['{}', 'not json', '[' * 20 + ']' * 20]) {
        expect(
          () => decodeMailArchiveExportManifest(input, _limits),
          _throwsCode(MailProblemCode.invalidInput),
        );
      }
    });

    test(
      'oversized file is rejected before manifest materialization',
      () async {
        final initial = await exporter.exportPlan(
          _plan(originals),
          parent: parent,
        );
        final limited = NativeMailArchiveExporter(
          profile: _profile,
          limits: const MailArchiveExportLimits(maxManifestBytes: 100),
          loadOriginal: (_) async => throw StateError('must not load'),
        );
        final report = await limited.resume(Directory(initial.directoryPath!));
        _problem(report, MailProblemCode.quotaExceeded);
      },
    );
  });

  test(
    'SIGKILL after first publication releases ownership and resumes twice',
    () async {
      final library = await Isolate.resolvePackageUri(
        Uri.parse('package:quds_mail_store/quds_mail_store.dart'),
      );
      final package = File.fromUri(library!).parent.parent;
      final dart = p.join(p.dirname(Platform.resolvedExecutable), 'dart');
      final process = await Process.start(dart, [
        'run',
        p.join(package.path, 'tool/archive_export_crash_fixture.dart'),
        parent.path,
      ], workingDirectory: package.path);
      final ready = Completer<(int, String)>();
      final errors = StringBuffer();
      final stderr = process.stderr
          .transform(utf8.decoder)
          .listen(errors.write);
      final stdout = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final match = RegExp(r'^READY (\d+) (.+)$').firstMatch(line);
              if (match != null && !ready.isCompleted) {
                ready.complete((int.parse(match[1]!), match[2]!));
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
      try {
        final barrier = await ready.future.timeout(const Duration(seconds: 45));
        child = barrier.$1;
        final root = Directory(barrier.$2);
        final values = fixture.exportCrashOriginals();
        final recovery = NativeMailArchiveExporter(
          profile: fixture.exportCrashProfile,
          loadOriginal: (id) async =>
              MailSuccess(values.firstWhere((bytes) => bytes.sha256 == id)),
        );
        final conflict = await recovery.resume(root);
        _problem(conflict, MailProblemCode.conflict);
        expect(Process.killPid(child, ProcessSignal.sigkill), isTrue);
        final exit = await process.exitCode.timeout(
          const Duration(seconds: 10),
        );
        expect(exit, isNot(0));
        child = null;
        final resumed = await recovery.resume(root);
        expect(resumed.status, MailArchiveExportStatus.completed);
        expect(resumed.existing, 1);
        expect(resumed.written, 1);
        for (final value in values) {
          expect(
            await File(p.join(root.path, '${value.sha256}.eml')).readAsBytes(),
            value.bytes,
          );
        }
        final again = await recovery.resume(root);
        expect(again.status, MailArchiveExportStatus.completed);
        expect(again.existing, 2);
        expect(again.written, 0);
      } finally {
        if (child != null) Process.killPid(child, ProcessSignal.sigkill);
        process.kill(ProcessSignal.sigkill);
        await stdout.cancel();
        await stderr.cancel();
      }
    },
    timeout: const Timeout(Duration(seconds: 75)),
  );
}
