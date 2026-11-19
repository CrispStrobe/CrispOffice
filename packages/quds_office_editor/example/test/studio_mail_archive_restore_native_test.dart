import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

Uint8List _original(String subject) => Uint8List.fromList(
  utf8.encode(
    [
      'From: Alice <alice@example.test>',
      'To: Bob <bob@example.test>',
      'Bcc: Private <hidden@example.test>',
      'Subject: =?UTF-8?B?${base64Encode(utf8.encode(subject))}?=',
      'Message-ID: <same-provider-id@example.test>',
      'Date: Thu, 19 Nov 2026 12:00:00 +0000',
      'MIME-Version: 1.0',
      'Content-Type: multipart/mixed; boundary="restore-fixture"',
      '',
      '--restore-fixture',
      'Content-Type: text/plain; charset=utf-8',
      'Content-Transfer-Encoding: base64',
      '',
      base64Encode(utf8.encode('restorebodyneedle Grüße مرحبا')),
      '--restore-fixture',
      'Content-Type: text/plain; charset=utf-8',
      'Content-Disposition: attachment; filename="budget.txt"',
      'Content-Transfer-Encoding: base64',
      '',
      base64Encode(utf8.encode('attachmentrestoreneedle café')),
      '--restore-fixture',
      'Content-Type: application/octet-stream',
      'Content-Disposition: attachment; filename="original.bin"',
      'Content-Transfer-Encoding: base64',
      '',
      base64Encode([0, 255, 16, 13, 10]),
      '--restore-fixture--',
      '',
    ].join('\r\n'),
  ),
);

void main() {
  test(
    'real MIME export restores exact originals, origins and searchable text',
    () async {
      final temporary = await Directory(
        await Directory.systemTemp.resolveSymbolicLinks(),
      ).createTemp('studio-manifest-roundtrip-');
      final sourceDirectory = Directory(p.join(temporary.path, 'source'));
      final source = _value(
        await openNativeMailArchive(
          appDirectory: sourceDirectory,
          profile: MailProfileId('old-archive', hostId: 'old-host'),
          clock: () => DateTime.utc(2026, 11, 18),
        ),
      );
      final destination = _value(
        await openNativeMailArchive(
          appDirectory: Directory(p.join(temporary.path, 'destination')),
          profile: MailProfileId('new-archive', hostId: 'new-host'),
          clock: () => DateTime.utc(2026, 11, 19),
        ),
      );
      addTearDown(() async {
        await source.close();
        await destination.close();
        await temporary.delete(recursive: true);
      });
      const origins = [
        MailArchiveOrigin(
          source: 'Team mailbox',
          folder: '/Projects/2026',
          sourceMessageId: 'provider:stable-one',
        ),
        MailArchiveOrigin(
          source: 'Personal café مرحبا',
          folder: '/Saved/Important',
          sourceMessageId: 'local:second-copy',
        ),
      ];
      final originals = [
        _original('Archivprüfung أولى'),
        _original('Archivprüfung ثانية'),
      ];
      const codec = QudsMimeCodec();
      for (final bytes in originals) {
        final parsed = codec.parse(bytes);
        expect(parsed.message, isNotNull);
        expect(parsed.message!.attachments, hasLength(2));
        _value(
          await source.archiveMessageWithOrigins(
            parsed.message!,
            origins: origins,
          ),
        );
      }
      final exportPlan = _value(
        await source.planExport(const MailArchiveSearchRequest()),
      );
      final exported = await NativeMailArchiveExporter(
        profile: source.profile,
        loadOriginal: source.loadOriginal,
      ).exportPlan(exportPlan, parent: temporary);
      expect(exported.status, MailArchiveExportStatus.completed);
      final exportDirectory = Directory(exported.directoryPath!);
      final manifestFile = File(p.join(exportDirectory.path, 'manifest.json'));
      final manifestBefore = await manifestFile.readAsBytes();
      // Restoration must use the portable export after the old database is gone.
      await source.close();
      await sourceDirectory.delete(recursive: true);

      final restorer = NativeMailArchiveRestorer(
        archive: destination,
        codec: codec,
      );
      final plan = _value(await restorer.inspect(exportDirectory));
      expect(plan.sourceProfile, isNot(destination.profile));
      expect(_value(await destination.statistics()).messages, 0);
      final result = await restorer.restore(plan, indexAttachmentText: true);
      expect(result.status, MailArchiveRestoreStatus.completed);
      expect(result.saved, 2);
      expect(result.originsAdded, 4);
      // The binary attachment is preserved but is outside text extraction.
      expect(result.indexWarnings, 2);
      for (final original in originals) {
        final id = MailBytes(original).sha256;
        expect(_value(await destination.loadOriginal(id))!.bytes, original);
        final restoredOrigins = _value(await destination.listOrigins(id));
        expect(
          restoredOrigins.map((origin) => origin.source).toSet(),
          origins.map((origin) => origin.source).toSet(),
        );
        for (final origin in origins) {
          expect(
            restoredOrigins.any(
              (restored) =>
                  restored.source == origin.source &&
                  restored.folder == origin.folder &&
                  restored.sourceMessageId == origin.sourceMessageId,
            ),
            isTrue,
          );
        }
        expect(
          await File(p.join(exportDirectory.path, '$id.eml')).readAsBytes(),
          original,
        );
      }
      for (final query in [
        'subject:Archivprüfung',
        'bcontent:restorebodyneedle',
        'bcc:hidden',
        'attachment:budget',
        'acontent:attachmentrestoreneedle',
      ]) {
        expect(
          _value(
            await destination.search(MailArchiveSearchRequest(query: query)),
          ).total,
          2,
          reason: query,
        );
      }
      final repeat = await restorer.restore(plan);
      expect(repeat.saved, 0);
      expect(repeat.duplicates, 2);
      expect(repeat.originsAdded, 0);
      expect(_value(await destination.statistics()).origins, 4);
      expect((await manifestFile.readAsBytes()), manifestBefore);
      final integrity = _value(await destination.verifyIntegrity());
      expect(integrity.issues, isEmpty);
    },
  );
}
