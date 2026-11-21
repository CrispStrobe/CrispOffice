import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

Uint8List _message() => Uint8List.fromList(
  utf8.encode(
    'From: Leo <leo@example.com>\r\n'
    'To: Anna <anna@example.com>\r\n'
    'Subject: Report\r\n'
    'Date: Thu, 19 Nov 2026 09:42:00 +0000\r\n'
    'MIME-Version: 1.0\r\n'
    'Content-Type: multipart/mixed; boundary=b\r\n\r\n'
    '--b\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nHello.\r\n'
    '--b\r\nContent-Type: application/pdf\r\n'
    'Content-Disposition: attachment; filename=report.pdf\r\n'
    'Content-Transfer-Encoding: base64\r\n\r\n'
    '${base64.encode(List<int>.filled(3000, 65))}\r\n'
    '--b--\r\n',
  ),
);

final class _German extends MailReaderLabels {
  const _German();
  @override
  String get from => 'Von';
  @override
  String get date => 'Datum';
  @override
  String get attachments => 'Anhänge';
  @override
  String formatDate(DateTime date) => 'Donnerstag';
}

void main() {
  test('default labels format the date and attachment size readably', () {
    final controller = MailReaderController.fromBytes(
      _message(),
      codec: const QudsMimeCodec(),
    );
    final text = controller.decodedText;
    final expected = const MailReaderLabels().formatDate(
      DateTime.utc(2026, 11, 19, 9, 42),
    );
    expect(text, contains('Date: $expected'));
    expect(text, isNot(contains('T09:42:00')));
    expect(text, contains('report.pdf · application/pdf · 3 KB'));
    expect(const MailReaderLabels().formatSize(1), '1 byte');
    expect(const MailReaderLabels().formatSize(500), '500 bytes');
    expect(const MailReaderLabels().formatSize(3 * 1024 * 1024), '3.0 MB');
    controller.dispose();
  });

  test('host labels replace every header label', () {
    final controller = MailReaderController.fromBytes(
      _message(),
      codec: const QudsMimeCodec(),
      labels: const _German(),
    );
    final text = controller.decodedText;
    expect(text, contains('Von: '));
    expect(text, contains('Datum: Donnerstag'));
    expect(text, contains('Anhänge:'));
    expect(text, isNot(contains('From:')));
    controller.setPreferHtml(false);
    expect(controller.decodedText, contains('Datum: Donnerstag'));
    controller.dispose();
  });

  testWidgets('a completely decoded message shows no status line', (
    tester,
  ) async {
    final controller = MailReaderController.fromBytes(
      _message(),
      codec: const QudsMimeCodec(),
    );
    expect(controller.result.status, MailParseStatus.complete);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MailMessageView(controller: controller)),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('mail-reader-status')), findsNothing);
    expect(find.textContaining('reader'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
