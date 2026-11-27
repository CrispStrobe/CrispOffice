import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'fixtures/mail_fixture.dart';

MailParseResult _htmlResult(String html) {
  final message = MailMessage(
    raw: MailBytes(Uint8List.fromList(utf8.encode(html))),
    envelope: MailEnvelope(
      subject: 'Formatted message',
      from: const [MailAddress('sender@example.test')],
      to: const [MailAddress('reader@example.test')],
    ),
    body: MailBody(html: html, plainText: 'Plain fallback'),
  );
  return MailParseResult(status: MailParseStatus.complete, message: message);
}

void main() {
  test('plain text normalizes CRLF without flattening paragraphs', () {
    final message = MailMessage(
      raw: MailBytes(Uint8List.fromList(utf8.encode('raw'))),
      envelope: MailEnvelope(subject: 'Plain'),
      body: const MailBody(
        plainText:
            'Antwort zur Anzeige\r\n\r\nHallo,\r\n'
            'sie können das Labor haben.\r\n\r\nViele Grüße',
      ),
    );
    final plain = buildMailPresentation(
      MailParseResult(status: MailParseStatus.complete, message: message),
      preferHtml: false,
    );
    expect(plain.bodyText, contains('Anzeige\n\nHallo,\n'));
    expect(plain.bodyText, contains('haben.\n\nViele Grüße'));
    expect(plain.bodyText, isNot(contains('\r')));
  });

  test('sanitizes active HTML but keeps safe table formatting and images', () {
    final presentation = buildMailPresentation(
      _htmlResult('''
<!doctype html><html><head>
<style>.hero { color: #123456; background-image: url(https://tracker.test/bg) }</style>
</head><body>
<script>alert(1)</script>
<div class="hero" onclick="steal()">Hello <b>world</b></div>
<table style="border-collapse:collapse; position:fixed">
<tr><td style="padding:4px">Cell</td></tr></table>
<img src="cid:logo@example" alt="Logo">
<img src="https://tracker.test/pixel.gif" alt="Pixel">
<a href="javascript:alert(2)">bad</a>
<a href="https://example.test/path">good</a>
<form><input value="secret"></form>
</body></html>
'''),
      preferHtml: true,
    );
    final safe = presentation.safeHtml;
    expect(safe, isNotNull);
    expect(safe, contains('<table'));
    expect(safe, contains('<td'));
    expect(safe, contains('data-mail-cid="logo@example"'));
    expect(safe, contains('data-mail-remote="https://tracker.test/pixel.gif"'));
    expect(safe, contains('href="https://example.test/path"'));
    expect(safe, isNot(contains('<script')));
    expect(safe, isNot(contains('onclick')));
    expect(safe, isNot(contains('javascript:')));
    expect(safe, isNot(contains('<form')));
    expect(safe, isNot(contains('src=')));
    expect(safe, isNot(contains('background-image')));
    expect(safe, isNot(contains('position:fixed')));
  });

  test('deep transactional HTML is sanitized rather than rejected', () {
    final presentation = buildMailPresentation(
      _htmlResult(
        '${'<div>' * 100}<p>Deep Amazon-style table content</p>${'</div>' * 100}',
      ),
      preferHtml: true,
    );
    expect(presentation.rejected, isFalse);
    expect(presentation.safeHtml, isNotNull);
    expect(presentation.safeHtml, contains('Deep Amazon-style table content'));
    expect(
      presentation.diagnostics.where(
        (item) => item.code == MailDiagnosticCode.renderLimit,
      ),
      isEmpty,
    );
  });

  testWidgets('an admitted remote image replaces its placeholder', (
    tester,
  ) async {
    final controller = MailReaderController(
      result: _htmlResult(
        '<p>Photo</p>'
        '<img src="https://images.test/photo.png" alt="photo">',
      ),
      preferHtml: true,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MailMessageView(controller: controller, richHtml: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('External image blocked'), findsOneWidget);
    final uri = controller.presentation.remoteImageUrls.single;
    expect(
      controller.addImages([
        MailInlineImage(
          attachment: byteAttachment(
            partPath: 'remote:$uri',
            mediaType: 'image/png',
            bytes: onePixelPng(),
          ),
          width: 1,
          height: 1,
        ),
      ]),
      1,
    );
    await tester.pumpAndSettle();
    expect(find.text('External image blocked'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('rich HTML offers explicit remote-image loading', (tester) async {
    var loaded = 0;
    final controller = MailReaderController(
      result: _htmlResult(
        '<p>Hello <strong>formatted</strong> mail.</p>'
        '<img src="https://tracker.test/pixel.gif" alt="blocked">',
      ),
      preferHtml: true,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MailMessageView(
            controller: controller,
            richHtml: true,
            onLoadRemoteImages: () => loaded++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mail-rich-body')), findsOneWidget);
    expect(find.text('Load external image'), findsOneWidget);
    await tester.tap(find.text('Load external image'));
    expect(loaded, 1);
    expect(find.byKey(const ValueKey('mail-copy')), findsNothing);
  });
}
