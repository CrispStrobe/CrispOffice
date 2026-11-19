/// A real native export process. The parent kills it after one EML was flushed
/// and published, while the next source load is paused and ownership is held.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/src/archive_export_models.dart';
import 'package:quds_mail_store/src/archive_export_native.dart';
import 'package:quds_mail_store/src/archive_models.dart';

final exportCrashProfile = MailProfileId(
  'export-crash',
  hostId: 'archive-export-tests',
);

List<MailBytes> exportCrashOriginals() => [
  for (final name in ['first', 'second'])
    MailBytes(
      Uint8List.fromList([
        ...utf8.encode('Subject: $name\r\n\r\n$name original\r\n'),
        0,
        127,
        128,
        255,
      ]),
    ),
];

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Expected a synthetic export parent directory.');
    exitCode = 2;
    return;
  }
  final parent = Directory(arguments.single);
  final originals = exportCrashOriginals();
  var loaded = 0;
  final exporter = NativeMailArchiveExporter(
    profile: exportCrashProfile,
    loadOriginal: (id) async {
      if (++loaded == 2) {
        final output = parent.listSync().whereType<Directory>().single;
        stdout.writeln('READY $pid ${output.path}');
        await stdout.flush();
        while (true) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      return MailSuccess(originals.firstWhere((bytes) => bytes.sha256 == id));
    },
  );
  final report = await exporter.exportPlan(
    MailArchiveExportPlan(
      profile: exportCrashProfile,
      createdAt: DateTime.utc(2026, 11, 19),
      items: [
        for (final original in originals)
          MailArchiveExportItem(
            id: original.sha256,
            byteLength: original.length,
            origins: const [MailArchiveOrigin(source: 'Synthetic export')],
          ),
      ],
    ),
    parent: parent,
  );
  stderr.writeln('Unexpected fixture completion: ${report.status.name}');
  exitCode = 3;
}
