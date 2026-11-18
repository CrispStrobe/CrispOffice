import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';

/// Synthetic boundary-sized input. RSS includes fixture construction and VM.
void main() {
  final bytes = Uint8List(16 * 1024 * 1024);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = i & 255;
  }
  final source = Uint8List.fromList(
    ascii.encode(
      'Content-Type: application/octet-stream\r\n'
      'Content-Disposition: attachment; filename=synthetic.bin\r\n'
      'Content-Transfer-Encoding: base64\r\n\r\n${base64.encode(bytes)}',
    ),
  );
  final before = ProcessInfo.currentRss;
  final timer = Stopwatch()..start();
  final parsed = const QudsMimeCodec().parse(source);
  timer.stop();
  if (parsed.status != MailParseStatus.complete ||
      parsed.message!.attachments.single.content.sha256 !=
          MailBytes(bytes).sha256) {
    throw StateError('Synthetic boundary input did not retain exact bytes.');
  }
  print(
    jsonEncode(<String, Object>{
      'platform': Platform.operatingSystem,
      'runtime': Platform.version,
      'rawBytes': source.length,
      'attachmentBytes': bytes.length,
      'elapsedMicroseconds': timer.elapsedMicroseconds,
      'rssBeforeParse': before,
      'rssAfterParse': ProcessInfo.currentRss,
      'processPeakRss': ProcessInfo.maxRss,
      'scope':
          'Whole process including fixture construction; desktop host only.',
    }),
  );
}
