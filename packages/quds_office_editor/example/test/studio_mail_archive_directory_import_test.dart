import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';
import 'package:quds_office_studio/studio_mail_archive_directory_import.dart';
import 'package:quds_office_studio/studio_mail_archive_host.dart';

const _separator = 'From sender@example.test Thu Nov 19 14:20:00 2026\n';
const _first = 'From: first@example.test\nSubject: First\n\nfirst body\n';
const _second =
    'From: second@example.test\r\nSubject: Second\r\n\r\nsecond body';

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

Uint8List _raw(String subject) => Uint8List.fromList([
  ...utf8.encode(
    'From: synthetic@example.test\r\nSubject: $subject\r\n'
    'Content-Type: application/octet-stream\r\n'
    'Content-Transfer-Encoding: binary\r\n\r\n',
  ),
  0,
  127,
  128,
  255,
  13,
  10,
]);

final class _ArchiveAdapter extends Fake implements StudioMailArchiveStore {
  _ArchiveAdapter(this.archive);
  final SqliteMailArchive archive;
  final List<MailArchiveOrigin> origins = [];
  final List<MailMessage> messages = [];
  int calls = 0;
  int? failAt;
  MailProblemCode failureCode = MailProblemCode.storageFailure;
  bool throwFailure = false;
  bool? indexedAttachments;
  void Function()? afterCommit;

  @override
  MailProfileId get profile => archive.profile;

  @override
  Future<MailResult<MailArchiveImportResult>> archiveMessage(
    MailMessage message, {
    required MailArchiveOrigin origin,
    bool indexAttachmentText = false,
    MailCancellationToken? cancellation,
  }) async {
    calls++;
    indexedAttachments = indexAttachmentText;
    if (calls == failAt) {
      if (throwFailure) throw StateError('synthetic private storage details');
      return MailFailure(MailProblem(failureCode));
    }
    final result = await archive.archiveMessage(
      message,
      origin: origin,
      indexAttachmentText: indexAttachmentText,
      cancellation: cancellation,
    );
    if (result is MailSuccess<MailArchiveImportResult>) {
      origins.add(origin);
      messages.add(message);
      afterCommit?.call();
    }
    return result;
  }
}

final class _ScriptedFiles extends Fake implements StudioMailArchiveFiles {
  _ScriptedFiles({required this.entries, this.records = const []});
  final List<MailArchiveDirectoryEntry> entries;
  final List<MailResult<Uint8List>> records;
  bool omitTerminal = false;
  bool throwReading = false;
  int reads = 0;

  @override
  Stream<MailArchiveDirectoryEntry> enumerateDirectory(
    String path, {
    required MailCancellationToken cancellation,
    MailArchiveDirectoryLimits limits = const MailArchiveDirectoryLimits(),
    bool recursive = true,
  }) async* {
    for (final entry in entries) {
      if (!omitTerminal || !entry.terminal) yield entry;
    }
  }

  @override
  Stream<MailResult<Uint8List>> readMessages(
    StudioMailArchiveInput input, {
    required int maxMessageBytes,
    required MailCancellationToken cancellation,
    MailMboxDialect dialect = MailMboxDialect.mboxrd,
  }) async* {
    reads++;
    yield* Stream.fromIterable(records);
    if (throwReading) throw const FileSystemException('private source path');
  }
}

MailArchiveDirectoryProgress _progress({
  int files = 0,
  int skipped = 0,
  int errors = 0,
  int limited = 0,
}) => MailArchiveDirectoryProgress(
  entriesInspected: 1 + files + skipped + errors + limited,
  directoriesVisited: 1,
  filesAccepted: files,
  acceptedBytes: 0,
  skippedEntries: skipped,
  errorEntries: errors,
  limitedEntries: limited,
);

void main() {
  late Directory temporary;
  late Directory input;
  late SqliteMailArchive archive;
  late _ArchiveAdapter store;
  late NativeStudioMailArchiveFiles files;
  late MailCancellationSource cancellation;

  setUp(() async {
    // Resolve the system temporary directory once, as the quds_mail_store
    // tests do: macOS exposes it through `/var -> /private/var`, and directory
    // import deliberately rejects links in the chosen root's ancestors.
    temporary = await Directory(
      await Directory.systemTemp.resolveSymbolicLinks(),
    ).createTemp('archive-directory-host-');
    input = await Directory(p.join(temporary.path, 'source')).create();
    final opened = await openNativeMailArchive(
      appDirectory: Directory(p.join(temporary.path, 'archive')),
      profile: MailProfileId('directory-import', hostId: 'studio-tests'),
    );
    archive = _value(opened);
    store = _ArchiveAdapter(archive);
    files = NativeStudioMailArchiveFiles();
    cancellation = MailCancellationSource();
  });

  tearDown(() async {
    await archive.close();
    await temporary.delete(recursive: true);
  });

  Future<File> write(String relative, List<int> bytes) async {
    final file = File(p.join(input.path, relative));
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<StudioMailDirectoryImportReport> run({
    StudioMailArchiveFiles? selectedFiles,
    String? directory,
    String folder = '/Imported',
    bool recursive = true,
    bool indexAttachmentText = false,
    MailMboxDialect dialect = MailMboxDialect.mboxrd,
    int maxMessageBytes = 32 * 1024 * 1024,
    int maxMessages = 100000,
    MailArchiveDirectoryLimits limits = const MailArchiveDirectoryLimits(),
    void Function(StudioMailDirectoryImportProgress)? onProgress,
  }) => importStudioMailDirectory(
    store: store,
    files: selectedFiles ?? files,
    directory: directory ?? input.path,
    source: 'Synthetic mail tree',
    folder: folder,
    recursive: recursive,
    indexAttachmentText: indexAttachmentText,
    dialect: dialect,
    maxMessageBytes: maxMessageBytes,
    maxMessages: maxMessages,
    directoryLimits: limits,
    cancellation: cancellation.token,
    onProgress: onProgress,
  );

  Future<StudioMailArchiveInput> scanOne(String relative) async {
    final entries = await files
        .enumerateDirectory(input.path, cancellation: cancellation.token)
        .toList();
    final entry = entries.singleWhere(
      (entry) =>
          entry.outcome == MailArchiveDirectoryOutcome.file &&
          entry.relativePath == relative,
    );
    return StudioMailArchiveInput(
      name: p.basename(relative),
      path: entry.absolutePath!,
      directoryRoot: input.path,
      expectedSize: entry.byteLength,
    );
  }

  test(
    'nested EML and MBOX import exact bytes into a real native archive',
    () async {
      final binary = _raw('Binary original');
      await write('Inbox/2026/binary.EML', binary);
      final container = utf8.encode('$_separator$_first$_separator$_second');
      final mbox = await write('Old/letters.mbox', container);
      final observed = <StudioMailDirectoryImportProgress>[];
      final report = await run(
        onProgress: observed.add,
        indexAttachmentText: true,
      );
      expect(report.status, MailArchiveRunStatus.completed);
      expect(report.progress.files, 2);
      expect(report.progress.saved, 3);
      expect(report.progress.failed, 0);
      expect(report.progress.skipped, 0);
      expect(store.indexedAttachments, isTrue);
      expect(store.origins.map((origin) => origin.folder).toSet(), {
        '/Imported/Inbox/2026',
        '/Imported/Old',
      });
      for (final expected in [
        binary,
        utf8.encode(_first),
        utf8.encode(_second),
      ]) {
        final original = MailBytes(Uint8List.fromList(expected));
        expect(
          _value(await archive.loadOriginal(original.sha256))!.bytes,
          expected,
        );
      }
      expect(await mbox.readAsBytes(), container);
      expect(_value(await archive.statistics()).messages, 3);
      expect(observed.last.saved, 3);
      expect(
        jsonEncode(observed.map((event) => event.toJson()).toList()),
        isNot(contains(input.path)),
      );
    },
  );

  test(
    'identical basenames retain distinct folders and stable source identities',
    () async {
      final raw = _raw('One content in two places');
      await write('First/same.eml', raw);
      await write('Second/same.eml', raw);
      final first = await run(folder: r'\Root\Migration\');
      expect(first.status, MailArchiveRunStatus.completed);
      expect(first.progress.saved, 1);
      expect(first.progress.duplicates, 1);
      final id = MailBytes(raw).sha256;
      final origins = _value(await archive.listOrigins(id));
      expect(origins.map((origin) => origin.folder).toSet(), {
        '/Root/Migration/First',
        '/Root/Migration/Second',
      });
      expect(
        origins.map((origin) => origin.sourceMessageId).toSet(),
        hasLength(2),
      );
      for (final origin in origins) {
        expect(origin.sourceMessageId, matches(r'^file:[0-9a-f]{64}:1$'));
        expect(origin.sourceMessageId, isNot(contains('same.eml')));
      }
      final second = await run(folder: '/Root/Migration');
      expect(second.progress.saved, 0);
      expect(second.progress.duplicates, 2);
      expect(_value(await archive.statistics()).origins, 2);
      expect(
        _value(
          await archive.listOrigins(id),
        ).map((origin) => origin.sourceMessageId),
        origins.map((origin) => origin.sourceMessageId),
      );
    },
  );

  test('a root file joins provenance without an extra path segment', () async {
    await write('root.eml', _raw('Root'));
    final report = await run(folder: '/');
    expect(report.status, MailArchiveRunStatus.completed);
    expect(store.origins.single.folder, '/');
  });

  test(
    'nonrecursive import reports nested and unsupported entries as skipped',
    () async {
      await write('root.eml', _raw('Root'));
      await write('Nested/hidden.eml', _raw('Nested'));
      await write('notes.txt', utf8.encode('not a message'));
      final report = await run(recursive: false);
      expect(report.status, MailArchiveRunStatus.partial);
      expect(report.progress.saved, 1);
      expect(report.progress.skipped, 2);
      expect(report.progress.failed, 0);
      expect(store.origins.single.folder, '/Imported');
    },
  );

  test('pre-cancelled import never enumerates or commits', () async {
    cancellation.cancel();
    final report = await run(directory: p.join(input.path, 'missing'));
    expect(report.status, MailArchiveRunStatus.cancelled);
    expect(report.progress.processed, 0);
    expect(report.progress.files, 0);
    expect(store.calls, 0);
  });

  test(
    'cancellation immediately after a confirmed commit preserves its count',
    () async {
      await write(
        'letters.mbox',
        utf8.encode('$_separator$_first$_separator$_second'),
      );
      store.afterCommit = cancellation.cancel;
      final report = await run();
      expect(report.status, MailArchiveRunStatus.cancelled);
      expect(report.progress.saved, 1);
      expect(report.progress.failed, 0);
      expect(store.calls, 1);
      expect(_value(await archive.statistics()).messages, 1);
    },
  );

  test(
    'progress observer exceptions do not change import correctness',
    () async {
      await write('original.eml', _raw('Observer exception'));
      final report = await run(
        onProgress: (_) => throw StateError('private observer'),
      );
      expect(report.status, MailArchiveRunStatus.completed);
      expect(report.progress.saved, 1);
      expect(report.progress.observerErrors, greaterThan(0));
      expect(_value(await archive.statistics()).messages, 1);
    },
  );

  test(
    'message cap stops a multi-message container with exact committed counts',
    () async {
      await write(
        'letters.mbox',
        utf8.encode('$_separator$_first$_separator$_second'),
      );
      final report = await run(maxMessages: 1);
      expect(report.status, MailArchiveRunStatus.limited);
      expect(report.problem?.code, MailProblemCode.quotaExceeded);
      expect(report.progress.saved, 1);
      expect(report.progress.failed, 0);
      expect(store.calls, 1);
    },
  );

  test(
    'message exactly at the raw cap imports; over-cap record remains a failure',
    () async {
      await write(
        'letters.mbox',
        utf8.encode('$_separator$_first$_separator$_second'),
      );
      final report = await run(maxMessageBytes: utf8.encode(_first).length);
      expect(report.status, MailArchiveRunStatus.partial);
      expect(report.progress.saved, 1);
      expect(report.progress.failed, 1);
      expect(_value(await archive.statistics()).messages, 1);
    },
  );

  test(
    'scanner EML and aggregate byte caps are reported as limited work',
    () async {
      final raw = _raw('Limited source');
      await write('large.eml', raw);
      final perFile = await run(
        limits: MailArchiveDirectoryLimits(maxEmlBytes: raw.length - 1),
      );
      expect(perFile.status, MailArchiveRunStatus.limited);
      expect(perFile.progress.limited, 1);
      expect(perFile.progress.saved, 0);
      final aggregate = await run(
        limits: MailArchiveDirectoryLimits(maxTotalFileBytes: raw.length - 1),
      );
      expect(aggregate.status, MailArchiveRunStatus.limited);
      expect(aggregate.problem?.code, MailProblemCode.quotaExceeded);
      expect(aggregate.progress.limited, 1);
      expect(store.calls, 0);
    },
  );

  test(
    'depth and file limits report incomplete scanning instead of completion',
    () async {
      await write('Deep/child.eml', _raw('Child'));
      final depth = await run(
        limits: const MailArchiveDirectoryLimits(maxDepth: 0),
      );
      expect(depth.status, MailArchiveRunStatus.limited);
      expect(depth.progress.limited, 1);
      final count = await run(
        limits: const MailArchiveDirectoryLimits(maxFiles: 0),
      );
      expect(count.status, MailArchiveRunStatus.limited);
      expect(count.progress.files, 0);
      expect(count.progress.saved, 0);
    },
  );

  test(
    'a missing source directory reports a scan error and no saved mail',
    () async {
      final report = await run(directory: p.join(input.path, 'missing'));
      expect(report.status, MailArchiveRunStatus.failed);
      expect(report.problem?.code, MailProblemCode.unavailable);
      expect(report.progress.scanErrors, 1);
      expect(report.progress.processed, 0);
    },
  );

  test(
    'malformed MBOX preamble is counted without stopping other files',
    () async {
      await write('malformed.mbox', utf8.encode('not an MBOX\n'));
      await write('valid.eml', _raw('Still import'));
      final report = await run();
      expect(report.status, MailArchiveRunStatus.partial);
      expect(report.progress.saved, 1);
      expect(report.progress.failed, 1);
      expect(_value(await archive.statistics()).messages, 1);
    },
  );

  test(
    'selected MBOX dialect is passed through without rewriting MIME bytes',
    () async {
      const quoted = 'Subject: Quoted\n\n>From one\n>>From two\n';
      const unquoted = 'Subject: Quoted\n\nFrom one\n>>From two\n';
      await write('quoted.mbox', utf8.encode('$_separator$quoted'));
      final report = await run(dialect: MailMboxDialect.mboxo);
      expect(report.progress.saved, 1);
      expect(store.messages.single.raw.bytes, utf8.encode(unquoted));
    },
  );

  for (final code in [
    MailProblemCode.storageFailure,
    MailProblemCode.permissionDenied,
    MailProblemCode.unavailable,
    MailProblemCode.quotaExceeded,
  ]) {
    test(
      'typed $code storage failure stops with confirmed previous work counted',
      () async {
        await write(
          'letters.mbox',
          utf8.encode(
            '$_separator$_first$_separator$_second'
            '${_separator}Subject: Third\n\nthird',
          ),
        );
        store.failAt = 2;
        store.failureCode = code;
        final report = await run();
        expect(
          report.status,
          code == MailProblemCode.quotaExceeded
              ? MailArchiveRunStatus.limited
              : MailArchiveRunStatus.partial,
        );
        expect(report.problem?.code, code);
        expect(report.progress.saved, 1);
        expect(report.progress.failed, 1);
        expect(store.calls, 2);
        expect(_value(await archive.statistics()).messages, 1);
      },
    );
  }

  test(
    'unexpected storage exception is sanitized and stops before later files',
    () async {
      await write('one.eml', _raw('One'));
      await write('two.eml', _raw('Two'));
      store.failAt = 1;
      store.throwFailure = true;
      final report = await run();
      expect(report.status, MailArchiveRunStatus.failed);
      expect(report.problem?.code, MailProblemCode.storageFailure);
      expect(report.progress.failed, 1);
      expect(store.calls, 1);
    },
  );

  test(
    'invalid source/folder/budget is rejected before source enumeration',
    () async {
      for (final settings in [
        (folder: '/../outside', messages: 100, bytes: 1000),
        (folder: '/ok', messages: 0, bytes: 1000),
        (folder: '/ok', messages: 100, bytes: 0),
      ]) {
        final report = await run(
          folder: settings.folder,
          maxMessages: settings.messages,
          maxMessageBytes: settings.bytes,
        );
        expect(report.status, MailArchiveRunStatus.failed);
        expect(report.problem?.code, MailProblemCode.invalidInput);
        expect(report.progress.files, 0);
      }
    },
  );

  group('native read revalidation after scanning', () {
    test('a valid scanned binary EML is returned byte for byte', () async {
      final expected = _raw('Binary scan');
      await write('original.eml', expected);
      final selected = await scanOne('original.eml');
      final records = await files
          .readMessages(
            selected,
            maxMessageBytes: expected.length,
            cancellation: cancellation.token,
          )
          .toList();
      expect(records, hasLength(1));
      expect(_value(records.single), expected);
    });

    test(
      'changed size before reading fails without returning message bytes',
      () async {
        final file = await write('changed.eml', _raw('Changed size'));
        final selected = await scanOne('changed.eml');
        await file.writeAsString('replacement');
        final records = await files
            .readMessages(
              selected,
              maxMessageBytes: 1024,
              cancellation: cancellation.token,
            )
            .toList();
        expect(records, hasLength(1));
        expect(
          (records.single as MailFailure).problem.code,
          MailProblemCode.conflict,
        );
      },
    );

    test(
      'a file replaced by a symlink is rejected before reading the target',
      () async {
        final expected = _raw('Before symlink');
        final file = await write('changed.eml', expected);
        final selected = await scanOne('changed.eml');
        final external = await File(
          p.join(temporary.path, 'outside.eml'),
        ).writeAsBytes(expected);
        await file.delete();
        await Link(file.path).create(external.path);
        final records = await files
            .readMessages(
              selected,
              maxMessageBytes: 1024,
              cancellation: cancellation.token,
            )
            .toList();
        expect(records, hasLength(1));
        expect(
          (records.single as MailFailure).problem.code,
          MailProblemCode.conflict,
        );
        expect(await external.readAsBytes(), expected);
      },
    );

    test(
      'an ancestor replaced by a symlink is rejected after scan admission',
      () async {
        await write('Nested/changed.eml', _raw('Before ancestor link'));
        final selected = await scanOne('Nested/changed.eml');
        final nested = Directory(p.join(input.path, 'Nested'));
        final moved = await nested.rename(p.join(temporary.path, 'moved'));
        await Link(nested.path).create(moved.path);
        final records = await files
            .readMessages(
              selected,
              maxMessageBytes: 1024,
              cancellation: cancellation.token,
            )
            .toList();
        expect(records, hasLength(1));
        expect(
          (records.single as MailFailure).problem.code,
          MailProblemCode.conflict,
        );
      },
    );

    test(
      'MBOX growth after a returned record cannot import appended messages',
      () async {
        final file = await write(
          'growing.mbox',
          utf8.encode('$_separator$_first$_separator$_second'),
        );
        final selected = await scanOne('growing.mbox');
        final records = <MailResult<Uint8List>>[];
        await for (final record in files.readMessages(
          selected,
          maxMessageBytes: 1024,
          cancellation: cancellation.token,
        )) {
          records.add(record);
          if (records.length == 1) {
            await file.writeAsString(
              '\n${_separator}Subject: Added\n\nappended',
              mode: FileMode.append,
            );
          }
        }
        final messages = records.whereType<MailSuccess<Uint8List>>().toList();
        expect(messages.map((message) => utf8.decode(message.value)), [
          _first,
          _second,
        ]);
        expect(
          records.whereType<MailFailure<Uint8List>>().single.problem.code,
          MailProblemCode.conflict,
        );
      },
    );

    test(
      'file change after EML yield remains visible as a trailing conflict',
      () async {
        final raw = _raw('Original before change');
        final file = await write('changing.eml', raw);
        final selected = await scanOne('changing.eml');
        final records = <MailResult<Uint8List>>[];
        await for (final record in files.readMessages(
          selected,
          maxMessageBytes: 1024,
          cancellation: cancellation.token,
        )) {
          records.add(record);
          if (records.length == 1) await file.writeAsString('changed');
        }
        expect(_value(records.first), raw);
        expect(
          (records.last as MailFailure).problem.code,
          MailProblemCode.conflict,
        );
      },
    );
  });

  group('injected scanner and stream outcomes', () {
    late List<MailArchiveDirectoryEntry> entries;
    setUp(() {
      entries = [
        MailArchiveDirectoryEntry(
          outcome: MailArchiveDirectoryOutcome.file,
          absolutePath: p.join(input.path, 'one.eml'),
          relativePath: 'one.eml',
          relativeFolder: '',
          byteLength: 1,
          progress: _progress(files: 1),
        ),
        MailArchiveDirectoryEntry(
          outcome: MailArchiveDirectoryOutcome.completed,
          progress: _progress(files: 1),
          terminal: true,
        ),
      ];
    });

    test(
      'read failures and exceptions are counted without inventing originals',
      () async {
        final fake = _ScriptedFiles(
          entries: entries,
          records: const [
            MailFailure(MailProblem(MailProblemCode.unavailable)),
          ],
        )..throwReading = true;
        final report = await run(selectedFiles: fake);
        expect(report.status, MailArchiveRunStatus.partial);
        expect(report.progress.failed, 2);
        expect(report.progress.saved, 0);
        expect(store.calls, 0);
      },
    );

    test(
      'scanner errors and skipped entries remain in the final report',
      () async {
        final fake = _ScriptedFiles(
          entries: [
            MailArchiveDirectoryEntry(
              outcome: MailArchiveDirectoryOutcome.skipped,
              progress: _progress(skipped: 1),
              issue: MailArchiveDirectoryIssue.symbolicLink,
            ),
            MailArchiveDirectoryEntry(
              outcome: MailArchiveDirectoryOutcome.error,
              progress: _progress(skipped: 1, errors: 1),
              issue: MailArchiveDirectoryIssue.inaccessible,
            ),
            MailArchiveDirectoryEntry(
              outcome: MailArchiveDirectoryOutcome.completed,
              progress: _progress(skipped: 1, errors: 1),
              terminal: true,
            ),
          ],
        );
        final report = await run(selectedFiles: fake);
        expect(report.status, MailArchiveRunStatus.partial);
        expect(report.progress.skipped, 1);
        expect(report.progress.scanErrors, 1);
        expect(report.progress.failed, 0);
      },
    );

    test(
      'missing terminal scan event cannot be mistaken for completion',
      () async {
        final fake = _ScriptedFiles(
          entries: entries,
          records: [MailSuccess(_raw('Before scanner disappeared'))],
        )..omitTerminal = true;
        final report = await run(selectedFiles: fake);
        expect(report.status, MailArchiveRunStatus.partial);
        expect(report.problem?.code, MailProblemCode.unavailable);
        expect(report.progress.saved, 1);
      },
    );

    test('unsafe relative metadata is rejected before a read', () async {
      final fake = _ScriptedFiles(
        entries: [
          MailArchiveDirectoryEntry(
            outcome: MailArchiveDirectoryOutcome.file,
            absolutePath: p.join(input.path, 'one.eml'),
            relativePath: '../one.eml',
            relativeFolder: '..',
            byteLength: 1,
            progress: _progress(files: 1),
          ),
          entries.last,
        ],
        records: [MailSuccess(_raw('Must not read'))],
      );
      final report = await run(selectedFiles: fake);
      expect(report.status, MailArchiveRunStatus.partial);
      expect(report.progress.failed, 1);
      expect(fake.reads, 0);
    });
  });
}
