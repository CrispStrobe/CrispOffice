import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';
import 'package:quds_office_studio/studio_mail_threading.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

String digest(List<int> bytes) => crypto.sha256.convert(bytes).toString();

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: attachment_mime_probe.dart fixtures.json output',
    );
  }
  final manifest = File(args[0]).absolute;
  final output = Directory(args[1]).absolute..createSync(recursive: true);
  final cases = jsonDecode(manifest.readAsStringSync()) as List<Object?>;
  final results = <Map<String, Object?>>[];
  for (final rawCase in cases) {
    final fixture = rawCase! as Map<String, Object?>;
    final id = fixture['id']! as String;
    final body = File('${manifest.parent.path}/${fixture['bodyPath']}')
        .readAsStringSync();
    final files = (fixture['files']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final attachments = <StudioMailAttachment>[];
    for (final file in files) {
      final source = File('${manifest.parent.path}/${file['path']}')
          .readAsBytesSync();
      require(digest(source) == file['sha256'], '$id fixture input digest');
      final attachment = StudioMailAttachment(
        name: file['name']! as String,
        bytes: source,
      );
      // Prove ownership before MIME serialization, including across retries.
      source.fillRange(0, source.length, 0xa5);
      require(
        attachment.content.sha256 == file['sha256'],
        '$id attachment snapshot ownership',
      );
      attachments.add(attachment);
    }
    final draft = StudioMailDraft(
      to: 'reader@example.invalid',
      cc: 'copy@example.invalid',
      bcc: 'hidden@example.invalid',
      subject: fixture['subject']! as String,
      body: body,
      thread: StudioMailThread.replyTo(
        MailEnvelope(
          messageId: '<parent@example.invalid>',
          references: const ['<root@example.invalid>'],
        ),
      ),
      attachments: StudioMailAttachments.from(attachments),
    );
    require(draft.problem == null, '$id draft admission');
    final message = buildStudioMailMessage(draft, 'writer@example.invalid');
    final wire = message.renderMessage();
    require(wire.codeUnits.every((unit) => unit < 128), '$id ASCII wire');
    require(!wire.contains('hidden@example.invalid'), '$id private recipient');
    final bytes = Uint8List.fromList(ascii.encode(wire));
    require(bytes.length <= studioMailMaxWireBytes, '$id wire budget');
    require(
      draft.recipients.envelope.join(',') ==
          'reader@example.invalid,copy@example.invalid,hidden@example.invalid',
      '$id complete envelope',
    );
    final eml = File('${output.path}/$id.eml')..writeAsBytesSync(bytes);
    final parsed = const QudsMimeCodec().parse(bytes);
    require(
      parsed.status == MailParseStatus.complete,
      '$id production parse ${parsed.status.name}: '
      '${parsed.diagnostics.map((item) => item.code.name).join(',')}',
    );
    final recovered = parsed.message!;
    final expectedBody = body.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
    require(recovered.body.plainText == expectedBody, '$id production body');
    require(recovered.attachments.length == files.length, '$id file count');
    for (var i = 0; i < files.length; i++) {
      final expected = files[i];
      final actual = recovered.attachments[i];
      require(actual.displayName == expected['name'], '$id filename $i');
      require(actual.content.sha256 == expected['sha256'], '$id payload $i');
      require(actual.content.length == expected['length'], '$id byte count $i');
      require(
        actual.declaredSize == expected['length'],
        '$id declared size $i',
      );
      require(actual.mediaType == expected['mediaType'], '$id media type $i');
    }
    require(recovered.envelope.bcc.isEmpty, '$id decoded Bcc');
    require(
      recovered.envelope.inReplyTo == '<parent@example.invalid>',
      '$id parent header',
    );
    results.add({
      'id': id,
      'eml': eml.path,
      'wireBytes': bytes.length,
      'wireSha256': digest(bytes),
      'attachmentCount': attachments.length,
      'attachmentBytes': draft.attachments.totalBytes,
      'inputBodyUtf8Bytes': utf8.encode(body).length,
      'productionParse': parsed.status.name,
      'productionPlainBodySha256': digest(
        utf8.encode(recovered.body.plainText!),
      ),
      'canonicalBccAbsent': true,
      'hiddenRecipientRetainedInEnvelope': true,
      'snapshotOwnershipVerified': true,
      'maximumWireBytes': studioMailMaxWireBytes,
    });
  }
  final report = const JsonEncoder.withIndent('  ').convert(results);
  File('${output.path}/dart-results.json').writeAsStringSync('$report\n');
  stdout.writeln(report);
}
