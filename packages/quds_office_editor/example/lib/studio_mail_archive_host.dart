import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';

/// Narrow host seam: widgets can test failures and races without a real archive.
abstract interface class StudioMailArchiveStore {
  set diagnostics(MailArchiveDiagnostics? value);
  Future<MailResult<MailArchiveImportResult>> archiveMessage(
    MailMessage message, {
    required MailArchiveOrigin origin,
    bool indexAttachmentText = false,
    MailCancellationToken? cancellation,
  });
  Future<MailResult<MailArchiveSearchPage>> search(
    MailArchiveSearchRequest request,
  );
  Future<MailResult<MailBytes?>> loadOriginal(String id);
  Future<MailResult<List<MailArchiveOrigin>>> listOrigins(String id);
  Future<MailResult<MailArchiveStats>> statistics();
  Future<MailResult<MailUnit>> saveSearch(MailArchiveSavedSearch search);
  Future<MailResult<List<MailArchiveSavedSearch>>> listSearches();
  Future<MailResult<MailUnit>> removeSearch(String name);
  Future<MailResult<MailArchiveMaintenancePage>> verifyIntegrity({
    String? afterId,
    int limit = 50,
    MailCancellationToken? cancellation,
  });
  Future<MailResult<MailArchiveMaintenancePage>> rebuildIndex({
    String? afterId,
    int limit = 50,
    MailCancellationToken? cancellation,
    MailCodec? codec,
    bool? indexAttachmentText,
  });
  Future<void> close();
}

typedef StudioMailArchiveOpener =
    Future<MailResult<StudioMailArchiveStore>> Function();

/// Shared durable namespace for file imports and foreground mailbox runs.
Future<MailResult<SqliteMailArchive>> openStudioMailSqliteArchive({
  MailArchiveLimits limits = const MailArchiveLimits(),
  MailArchiveDiagnostics? diagnostics,
}) async {
  try {
    return await openNativeMailArchive(
      appDirectory: await getApplicationSupportDirectory(),
      profile: MailProfileId('studio-local-archive', hostId: 'crispoffice'),
      limits: limits,
      diagnostics: diagnostics,
    );
  } on Object {
    return const MailFailure(MailProblem(MailProblemCode.storageFailure));
  }
}

Future<MailResult<StudioMailArchiveStore>> openStudioMailArchive({
  MailArchiveLimits limits = const MailArchiveLimits(),
}) async {
  try {
    final result = await openStudioMailSqliteArchive(limits: limits);
    return switch (result) {
      MailSuccess(value: final archive) => MailSuccess(_ArchiveStore(archive)),
      MailFailure(problem: final problem) => MailFailure(problem),
    };
  } on Object {
    return const MailFailure(MailProblem(MailProblemCode.storageFailure));
  }
}

/// Archive an explicitly selected message without changing its live account.
/// The opened archive is always closed. Cancellation after a confirmed commit
/// must not replace success with a retryable-looking failure.
Future<MailResult<MailArchiveImportResult>> archiveStudioMailMessage(
  MailMessage message, {
  required MailArchiveOrigin origin,
  StudioMailArchiveOpener? openArchive,
  bool indexAttachmentText = false,
  MailCancellationToken? cancellation,
}) async {
  StudioMailArchiveStore? store;
  try {
    cancellation?.throwIfCancelled();
    final opened = await (openArchive?.call() ?? openStudioMailArchive());
    if (opened case MailFailure(problem: final problem)) {
      return MailFailure(problem);
    }
    store = (opened as MailSuccess<StudioMailArchiveStore>).value;
    cancellation?.throwIfCancelled();
    return await store.archiveMessage(
      message,
      origin: origin,
      indexAttachmentText: indexAttachmentText,
      cancellation: cancellation,
    );
  } on MailCancelled {
    return const MailFailure(MailProblem(MailProblemCode.cancelled));
  } on Object {
    return const MailFailure(MailProblem(MailProblemCode.storageFailure));
  } finally {
    try {
      await store?.close();
    } on Object {
      // Keep the confirmed archive result even if ownership cleanup fails.
    }
  }
}

final class _ArchiveStore implements StudioMailArchiveStore {
  _ArchiveStore(this.archive);
  final SqliteMailArchive archive;

  @override
  set diagnostics(MailArchiveDiagnostics? value) => archive.diagnostics = value;
  @override
  Future<MailResult<MailArchiveImportResult>> archiveMessage(
    MailMessage message, {
    required MailArchiveOrigin origin,
    bool indexAttachmentText = false,
    MailCancellationToken? cancellation,
  }) => archive.archiveMessage(
    message,
    origin: origin,
    indexAttachmentText: indexAttachmentText,
    cancellation: cancellation,
  );
  @override
  Future<MailResult<MailArchiveSearchPage>> search(
    MailArchiveSearchRequest request,
  ) => archive.search(request);
  @override
  Future<MailResult<MailBytes?>> loadOriginal(String id) =>
      archive.loadOriginal(id);
  @override
  Future<MailResult<List<MailArchiveOrigin>>> listOrigins(String id) =>
      archive.listOrigins(id);
  @override
  Future<MailResult<MailArchiveStats>> statistics() => archive.statistics();
  @override
  Future<MailResult<MailUnit>> saveSearch(MailArchiveSavedSearch search) =>
      archive.saveSearch(search);
  @override
  Future<MailResult<List<MailArchiveSavedSearch>>> listSearches() =>
      archive.listSearches();
  @override
  Future<MailResult<MailUnit>> removeSearch(String name) =>
      archive.removeSearch(name);
  @override
  Future<MailResult<MailArchiveMaintenancePage>> verifyIntegrity({
    String? afterId,
    int limit = 50,
    MailCancellationToken? cancellation,
  }) => archive.verifyIntegrity(
    afterId: afterId,
    limit: limit,
    cancellation: cancellation,
  );
  @override
  Future<MailResult<MailArchiveMaintenancePage>> rebuildIndex({
    String? afterId,
    int limit = 50,
    MailCancellationToken? cancellation,
    MailCodec? codec,
    bool? indexAttachmentText,
  }) => archive.rebuildIndex(
    afterId: afterId,
    limit: limit,
    cancellation: cancellation,
    codec: codec,
    indexAttachmentText: indexAttachmentText,
  );
  @override
  Future<void> close() => archive.close();
}

final class StudioMailArchiveInput {
  const StudioMailArchiveInput({required this.name, required this.path});
  final String name;
  final String path;
}

abstract interface class StudioMailArchiveFiles {
  Future<List<StudioMailArchiveInput>?> pickFiles();
  Stream<MailResult<Uint8List>> readMessages(
    StudioMailArchiveInput input, {
    required int maxMessageBytes,
    required MailCancellationToken cancellation,
    MailMboxDialect dialect = MailMboxDialect.mboxrd,
  });
  Future<MailResult<bool>> exportOriginal(
    String suggestedName,
    MailBytes bytes, {
    required MailCancellationToken cancellation,
  });
}

/// File sizes are checked on an opened handle before EML allocation. MBOX is
/// streamed through a bounded framer. The picker never eagerly loads file data.
final class NativeStudioMailArchiveFiles implements StudioMailArchiveFiles {
  NativeStudioMailArchiveFiles({this.chooseFiles, this.chooseExportPath});
  final Future<List<StudioMailArchiveInput>?> Function()? chooseFiles;
  final Future<String?> Function(String suggestedName)? chooseExportPath;

  @override
  Future<List<StudioMailArchiveInput>?> pickFiles() async {
    if (chooseFiles != null) return chooseFiles!();
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['eml', 'mbox'],
      allowMultiple: true,
      withData: false,
    );
    if (selection == null) return null;
    if (selection.files.any((file) => file.path == null)) {
      throw const FileSystemException('No native file handle was selected.');
    }
    return [
      for (final file in selection.files)
        StudioMailArchiveInput(name: file.name, path: file.path!),
    ];
  }

  @override
  Stream<MailResult<Uint8List>> readMessages(
    StudioMailArchiveInput input, {
    required int maxMessageBytes,
    required MailCancellationToken cancellation,
    MailMboxDialect dialect = MailMboxDialect.mboxrd,
  }) async* {
    try {
      cancellation.throwIfCancelled();
      if (maxMessageBytes < 1) {
        yield const MailFailure(MailProblem(MailProblemCode.invalidInput));
        return;
      }
      if (input.name.toLowerCase().endsWith('.mbox')) {
        await for (final entry in readMailMbox(
          File(input.path).openRead(),
          maxMessageBytes: maxMessageBytes,
          cancellation: cancellation,
          dialect: dialect,
        )) {
          if (cancellation.isCancelled) break;
          yield entry.bytes != null
              ? MailSuccess(entry.bytes!)
              : MailFailure(
                  entry.problem ??
                      const MailProblem(MailProblemCode.invalidInput),
                );
        }
      } else if (input.name.toLowerCase().endsWith('.eml')) {
        yield await _readEml(input.path, maxMessageBytes, cancellation);
      } else {
        yield const MailFailure(MailProblem(MailProblemCode.unsupported));
      }
    } on MailCancelled {
      yield const MailFailure(MailProblem(MailProblemCode.cancelled));
    } on FileSystemException catch (error) {
      yield MailFailure(_fileProblem(error));
    } on Object {
      yield const MailFailure(MailProblem(MailProblemCode.unavailable));
    }
  }

  Future<MailResult<Uint8List>> _readEml(
    String path,
    int maxBytes,
    MailCancellationToken cancellation,
  ) async {
    RandomAccessFile? handle;
    try {
      cancellation.throwIfCancelled();
      handle = await File(path).open();
      final length = await handle.length();
      if (length < 1) {
        return const MailFailure(MailProblem(MailProblemCode.invalidInput));
      }
      if (length > maxBytes) {
        return const MailFailure(MailProblem(MailProblemCode.quotaExceeded));
      }
      cancellation.throwIfCancelled();
      final bytes = await handle.read(length);
      cancellation.throwIfCancelled();
      // A concurrently changed file must not silently become a partial import.
      if (bytes.length != length || await handle.length() != length) {
        return const MailFailure(MailProblem(MailProblemCode.conflict));
      }
      return MailSuccess(bytes);
    } finally {
      await handle?.close();
    }
  }

  @override
  Future<MailResult<bool>> exportOriginal(
    String suggestedName,
    MailBytes bytes, {
    required MailCancellationToken cancellation,
  }) async {
    Directory? temporary;
    File? reservation;
    FileStat? reservationStat;
    bool published = false;
    try {
      cancellation.throwIfCancelled();
      final path = chooseExportPath != null
          ? await chooseExportPath!(suggestedName)
          : await FilePicker.platform.saveFile(
              fileName: suggestedName,
              type: FileType.custom,
              allowedExtensions: const ['eml'],
            );
      cancellation.throwIfCancelled();
      if (path == null) return const MailSuccess(false);
      final destination = File(path);
      temporary = await destination.parent.createTemp(
        '.crispoffice-mail-export-',
      );
      final staged = File(
        '${temporary.path}${Platform.pathSeparator}original.eml',
      );
      await staged.writeAsBytes(bytes.bytes, flush: true);
      cancellation.throwIfCancelled();
      // Exclusive creation refuses existing files and symlinks. Reserve only
      // after the complete original has been flushed to the sibling directory.
      await destination.create(exclusive: true);
      reservation = destination;
      reservationStat = await destination.stat();
      cancellation.throwIfCancelled();
      await staged.rename(destination.path);
      published = true;
      return const MailSuccess(true);
    } on MailCancelled {
      return const MailFailure(MailProblem(MailProblemCode.cancelled));
    } on FileSystemException catch (error) {
      return MailFailure(_fileProblem(error));
    } on Object {
      return const MailFailure(MailProblem(MailProblemCode.unavailable));
    } finally {
      if (!published && reservation != null && reservationStat != null) {
        try {
          final type = await FileSystemEntity.type(
            reservation.path,
            followLinks: false,
          );
          final current = await reservation.stat();
          // Remove only the unchanged empty reservation this export created.
          // An independently changed file or a replacement link is left alone.
          if (type == FileSystemEntityType.file &&
              current.size == 0 &&
              current.modified == reservationStat.modified &&
              current.changed == reservationStat.changed) {
            await reservation.delete();
          }
        } on Object {
          // Preserve the sanitized export failure if reservation cleanup fails.
        }
      }
      try {
        await temporary?.delete(recursive: true);
      } on Object {
        // A cleanup failure must not turn a completed export into a retry.
      }
    }
  }

  MailProblem _fileProblem(FileSystemException error) =>
      MailProblem(switch (error.osError?.errorCode) {
        13 || 5 => MailProblemCode.permissionDenied,
        28 || 112 => MailProblemCode.quotaExceeded,
        17 || 80 || 183 => MailProblemCode.conflict,
        _ => MailProblemCode.unavailable,
      });
}
