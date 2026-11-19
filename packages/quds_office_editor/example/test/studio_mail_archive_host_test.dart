import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_archive_host.dart';

final class _OneMessageStore extends Fake implements StudioMailArchiveStore {
  int closes = 0;
  int writes = 0;
  bool failWrite = false;
  bool failClose = false;
  bool? indexAttachments;
  MailMessage? received;
  MailArchiveOrigin? receivedOrigin;
  void Function()? onCommitted;
  @override
  Future<MailResult<MailArchiveImportResult>> archiveMessage(
    MailMessage message, {
    required MailArchiveOrigin origin,
    bool indexAttachmentText = false,
    MailCancellationToken? cancellation,
  }) async {
    writes++;
    received = message;
    receivedOrigin = origin;
    indexAttachments = indexAttachmentText;
    if (failWrite) throw StateError('private SQL and token');
    onCommitted?.call();
    return MailSuccess(
      MailArchiveImportResult(
        entry: MailArchiveEntry(
          id: message.raw.sha256,
          envelope: message.envelope,
          archivedAt: DateTime.utc(2026),
          byteLength: message.raw.length,
          attachmentCount: 0,
          indexTruncated: false,
          attachmentTextIndexed: 0,
          attachmentTextSkipped: 0,
        ),
        duplicate: false,
        originAdded: true,
      ),
    );
  }

  @override
  Future<void> close() async {
    closes++;
    if (failClose) throw StateError('private close error');
  }
}

MailMessage _message() => MailMessage(
  raw: MailBytes(Uint8List.fromList([1, 2, 3])),
  envelope: MailEnvelope(subject: 'Selected original'),
);

void main() {
  late Directory temporary;
  setUp(
    () async =>
        temporary = await Directory.systemTemp.createTemp('archive-host-test-'),
  );
  tearDown(() async => temporary.delete(recursive: true));

  test('an EML file is admitted by length before bounded allocation', () async {
    final file = File('${temporary.path}/large.eml');
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(1024 * 1024 * 1024);
    await handle.close();
    final results = await NativeStudioMailArchiveFiles()
        .readMessages(
          StudioMailArchiveInput(name: 'large.eml', path: file.path),
          maxMessageBytes: 1024,
          cancellation: MailCancellationSource().token,
        )
        .toList();
    expect(results, hasLength(1));
    expect(
      (results.single as MailFailure<Uint8List>).problem.code,
      MailProblemCode.quotaExceeded,
    );
  });

  test(
    'EML input preserves every original byte including NUL and line endings',
    () async {
      final bytes = Uint8List.fromList([
        83,
        117,
        98,
        106,
        101,
        99,
        116,
        58,
        32,
        65,
        13,
        10,
        13,
        10,
        0,
        255,
        10,
      ]);
      final file = await File(
        '${temporary.path}/original.eml',
      ).writeAsBytes(bytes);
      final results = await NativeStudioMailArchiveFiles()
          .readMessages(
            StudioMailArchiveInput(name: 'original.eml', path: file.path),
            maxMessageBytes: 1024,
            cancellation: MailCancellationSource().token,
          )
          .toList();
      expect(
        (results.single as MailSuccess<Uint8List>).value,
        orderedEquals(bytes),
      );
    },
  );

  test(
    'empty, unsupported and missing sources return typed failures',
    () async {
      final file = await File('${temporary.path}/empty.eml').create();
      final host = NativeStudioMailArchiveFiles();
      for (final item in [
        (
          StudioMailArchiveInput(name: 'empty.eml', path: file.path),
          MailProblemCode.invalidInput,
        ),
        (
          StudioMailArchiveInput(name: 'mail.pst', path: file.path),
          MailProblemCode.unsupported,
        ),
        (
          StudioMailArchiveInput(
            name: 'missing.eml',
            path: '${temporary.path}/missing.eml',
          ),
          MailProblemCode.unavailable,
        ),
      ]) {
        final results = await host
            .readMessages(
              item.$1,
              maxMessageBytes: 1024,
              cancellation: MailCancellationSource().token,
            )
            .toList();
        expect(
          (results.single as MailFailure<Uint8List>).problem.code,
          item.$2,
        );
      }
    },
  );

  test('cancelled input never opens a missing file', () async {
    final cancellation = MailCancellationSource()..cancel();
    final results = await NativeStudioMailArchiveFiles()
        .readMessages(
          StudioMailArchiveInput(
            name: 'missing.eml',
            path: '${temporary.path}/missing.eml',
          ),
          maxMessageBytes: 1024,
          cancellation: cancellation.token,
        )
        .toList();
    expect(
      (results.single as MailFailure<Uint8List>).problem.code,
      MailProblemCode.cancelled,
    );
  });

  test(
    'export publishes exact original bytes and cleans temporary files',
    () async {
      final destination = File('${temporary.path}/export.eml');
      final bytes = MailBytes(Uint8List.fromList([0, 255, 13, 10, 42]));
      final host = NativeStudioMailArchiveFiles(
        chooseExportPath: (_) async => destination.path,
      );
      final result = await host.exportOriginal(
        'safe.eml',
        bytes,
        cancellation: MailCancellationSource().token,
      );
      expect((result as MailSuccess<bool>).value, isTrue);
      expect(await destination.readAsBytes(), orderedEquals(bytes.bytes));
      expect(await temporary.list().length, 1);
    },
  );

  test(
    'cancellation after save picker leaves an existing destination intact',
    () async {
      final destination = await File(
        '${temporary.path}/existing.eml',
      ).writeAsString('original');
      final cancellation = MailCancellationSource();
      final host = NativeStudioMailArchiveFiles(
        chooseExportPath: (_) async {
          cancellation.cancel();
          return destination.path;
        },
      );
      final result = await host.exportOriginal(
        'safe.eml',
        MailBytes(Uint8List.fromList([1, 2, 3])),
        cancellation: cancellation.token,
      );
      expect(
        (result as MailFailure<bool>).problem.code,
        MailProblemCode.cancelled,
      );
      expect(await destination.readAsString(), 'original');
      expect(await temporary.list().length, 1);
    },
  );

  test('a cancelled save picker does not report an exported file', () async {
    final host = NativeStudioMailArchiveFiles(
      chooseExportPath: (_) async => null,
    );
    final result = await host.exportOriginal(
      'safe.eml',
      MailBytes(Uint8List.fromList([1])),
      cancellation: MailCancellationSource().token,
    );
    expect((result as MailSuccess<bool>).value, isFalse);
    expect(await temporary.list().length, 0);
  });
  test(
    'export refuses an existing file without altering its contents',
    () async {
      final destination = await File(
        '${temporary.path}/existing.eml',
      ).writeAsString('keep original');
      final host = NativeStudioMailArchiveFiles(
        chooseExportPath: (_) async => destination.path,
      );
      final result = await host.exportOriginal(
        'safe.eml',
        MailBytes(Uint8List.fromList([1, 2, 3])),
        cancellation: MailCancellationSource().token,
      );
      expect(
        (result as MailFailure<bool>).problem.code,
        MailProblemCode.conflict,
      );
      expect(await destination.readAsString(), 'keep original');
      expect(await temporary.list().length, 1);
    },
  );

  test(
    'export refuses an existing symlink without changing link or target',
    () async {
      final target = await File(
        '${temporary.path}/target.eml',
      ).writeAsString('keep target');
      final link = await Link('${temporary.path}/link.eml').create(target.path);
      final host = NativeStudioMailArchiveFiles(
        chooseExportPath: (_) async => link.path,
      );
      final result = await host.exportOriginal(
        'safe.eml',
        MailBytes(Uint8List.fromList([1, 2, 3])),
        cancellation: MailCancellationSource().token,
      );
      expect(
        (result as MailFailure<bool>).problem.code,
        MailProblemCode.conflict,
      );
      expect(await link.target(), target.path);
      expect(await target.readAsString(), 'keep target');
      expect(await temporary.list().length, 2);
    },
  );

  test(
    'a picker exception returns a sanitized failure and writes nothing',
    () async {
      final host = NativeStudioMailArchiveFiles(
        chooseExportPath: (_) async => throw StateError('private-path'),
      );
      final result = await host.exportOriginal(
        'safe.eml',
        MailBytes(Uint8List.fromList([1])),
        cancellation: MailCancellationSource().token,
      );
      expect(
        (result as MailFailure<bool>).problem.code,
        MailProblemCode.unavailable,
      );
      expect(await temporary.list().length, 0);
    },
  );
  test(
    'native MBOX streaming restores the explicitly selected quoting rules',
    () async {
      final file = await File('${temporary.path}/quoted.mbox').writeAsString(
        'From sender@example.test Thu Nov 19 12:00:00 2026\nSubject: Quoted\n\n>>From preserved\n',
      );
      final host = NativeStudioMailArchiveFiles();
      for (final dialect in MailMboxDialect.values) {
        final results = await host
            .readMessages(
              StudioMailArchiveInput(name: 'quoted.mbox', path: file.path),
              maxMessageBytes: 1024,
              cancellation: MailCancellationSource().token,
              dialect: dialect,
            )
            .toList();
        final bytes = (results.single as MailSuccess<Uint8List>).value;
        expect(
          String.fromCharCodes(bytes),
          contains(
            dialect == MailMboxDialect.mboxrd
                ? '\n>From preserved'
                : '\n>>From preserved',
          ),
        );
      }
    },
  );
  test(
    'selected-message helper forwards immutable content and closes its store',
    () async {
      final store = _OneMessageStore();
      final message = _message();
      const origin = MailArchiveOrigin(source: 'Account A', folder: '/Inbox');
      final result = await archiveStudioMailMessage(
        message,
        origin: origin,
        indexAttachmentText: true,
        openArchive: () async => MailSuccess(store),
      );
      expect(result, isA<MailSuccess<MailArchiveImportResult>>());
      expect(store.received, same(message));
      expect(store.receivedOrigin, same(origin));
      expect(store.indexAttachments, isTrue);
      expect(store.closes, 1);
    },
  );

  test(
    'selected-message helper returns the typed open failure without a write',
    () async {
      final result = await archiveStudioMailMessage(
        _message(),
        origin: const MailArchiveOrigin(source: 'Account A'),
        openArchive: () async =>
            const MailFailure(MailProblem(MailProblemCode.conflict)),
      );
      expect(
        (result as MailFailure<MailArchiveImportResult>).problem.code,
        MailProblemCode.conflict,
      );
    },
  );

  test(
    'selected-message helper sanitizes thrown writes and still closes',
    () async {
      final store = _OneMessageStore()..failWrite = true;
      final result = await archiveStudioMailMessage(
        _message(),
        origin: const MailArchiveOrigin(source: 'Account A'),
        openArchive: () async => MailSuccess(store),
      );
      expect(
        (result as MailFailure<MailArchiveImportResult>).problem.code,
        MailProblemCode.storageFailure,
      );
      expect(store.closes, 1);
    },
  );

  test(
    'confirmed archive survives a later cancellation and close failure',
    () async {
      final cancellation = MailCancellationSource();
      final store = _OneMessageStore()
        ..failClose = true
        ..onCommitted = cancellation.cancel;
      final result = await archiveStudioMailMessage(
        _message(),
        origin: const MailArchiveOrigin(source: 'Account A'),
        cancellation: cancellation.token,
        openArchive: () async => MailSuccess(store),
      );
      expect(result, isA<MailSuccess<MailArchiveImportResult>>());
      expect(store.closes, 1);
    },
  );

  test('cancelled selected-message action never opens the archive', () async {
    final cancellation = MailCancellationSource()..cancel();
    var opens = 0;
    final result = await archiveStudioMailMessage(
      _message(),
      origin: const MailArchiveOrigin(source: 'Account A'),
      cancellation: cancellation.token,
      openArchive: () async {
        opens++;
        return MailSuccess(_OneMessageStore());
      },
    );
    expect(
      (result as MailFailure<MailArchiveImportResult>).problem.code,
      MailProblemCode.cancelled,
    );
    expect(opens, 0);
  });

  test(
    'cancelling during archive open closes the acquired owner before writing',
    () async {
      final opened = Completer<MailResult<StudioMailArchiveStore>>();
      final cancellation = MailCancellationSource();
      final store = _OneMessageStore();
      final operation = archiveStudioMailMessage(
        _message(),
        origin: const MailArchiveOrigin(source: 'Account A'),
        cancellation: cancellation.token,
        openArchive: () => opened.future,
      );
      cancellation.cancel();
      opened.complete(MailSuccess(store));
      final result = await operation;
      expect(
        (result as MailFailure<MailArchiveImportResult>).problem.code,
        MailProblemCode.cancelled,
      );
      expect(store.writes, 0);
      expect(store.closes, 1);
    },
  );
}
