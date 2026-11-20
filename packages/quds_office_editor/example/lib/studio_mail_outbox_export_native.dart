import 'package:file_picker/file_picker.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_archive_host.dart';

/// Reuses the archive's staged, flushed, no-clobber export. Frozen MIME is
/// written byte-for-byte; saving never parses it or changes queue state.
Future<MailResult<bool>> exportStudioMailOutboxFile(
  String suggestedName,
  MailBytes bytes, {
  required MailCancellationToken cancellation,
  required bool Function() isCurrent,
}) => exportStudioMailOutboxFileTo(
  suggestedName,
  bytes,
  cancellation: cancellation,
  isCurrent: isCurrent,
  choosePath: (name) => FilePicker.platform.saveFile(
    fileName: name,
    type: FileType.custom,
    allowedExtensions: [name.endsWith('.json') ? 'json' : 'eml'],
  ),
);

/// Native picker seam for deterministic cancellation and filesystem tests.
Future<MailResult<bool>> exportStudioMailOutboxFileTo(
  String suggestedName,
  MailBytes bytes, {
  required MailCancellationToken cancellation,
  required bool Function() isCurrent,
  required Future<String?> Function(String name) choosePath,
}) => NativeStudioMailArchiveFiles(
  isExportCurrent: isCurrent,
  chooseExportPath: (name) async {
    if (!isCurrent()) {
      throw const MailCancelled(MailCancellationReason.accountChanged);
    }
    final path = await choosePath(name);
    if (!isCurrent()) {
      throw const MailCancelled(MailCancellationReason.accountChanged);
    }
    return path;
  },
).exportOriginal(suggestedName, bytes, cancellation: cancellation);
