import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'fixtures/mail_fixture.dart';

void main() {
  _nestedWrapperWhitespaceTest();
  test(
    'existing presentation constructors default to an empty body projection',
    () {
      final p = MailReaderPresentation(
        text: 'An existing caller supplies display text.',
        runs: const [],
        images: const [],
        diagnostics: const [],
      );
      expect(p.bodyText, isEmpty);
    },
  );

  for (final html in [false, true]) {
    test(
      '${html ? 'HTML' : 'plain'} body projection excludes reader metadata',
      () {
        const body = 'Visible body 😀 مرحبًا.\nBcc: a literal body label.';
        final p = buildMailPresentation(
          MailParseResult(
            status: MailParseStatus.complete,
            message: MailMessage(
              raw: MailBytes(Uint8List(0)),
              envelope: MailEnvelope(
                subject: 'Envelope metadata 😀',
                from: const [MailAddress('sender@example.invalid')],
                bcc: const [MailAddress('hidden@example.invalid')],
              ),
              body: MailBody(
                plainText: html ? null : body,
                html: html
                    ? '<p>Visible body 😀 مرحبًا.</p>'
                          '<p>Bcc: a literal body label.</p>'
                          '<script>not quoted active text</script>'
                          '<img src="https://blocked.invalid/image">'
                    : null,
              ),
              attachments: [byteAttachment()],
            ),
          ),
        );
        expect(p.rejected, isFalse);
        expect(p.usedHtml, html);
        expect(p.text, contains('hidden@example.invalid'));
        expect(p.text, contains('original.bin'));
        expect(
          p.bodyText.trim(),
          html ? '$body\n[External image blocked]' : body,
        );
        for (final metadata in [
          'Envelope metadata',
          'sender@example.invalid',
          'hidden@example.invalid',
          'original.bin',
          'application/octet-stream',
        ]) {
          expect(p.bodyText, isNot(contains(metadata)));
        }
        if (html) {
          expect(p.bodyText, isNot(contains('not quoted active text')));
          expect(p.bodyText, isNot(contains('blocked.invalid')));
          expect(p.blockedResourceCount, greaterThan(0));
        }
      },
    );
  }

  test('direct DTO plain/HTML bodies share one cumulative body budget', () {
    final p = buildMailPresentation(
      mailFixture(plainText: '1234', html: '5678'),
      budget: const MailReadBudget(maxBodyBytes: 7),
    );
    expect(p.rejected, isTrue);
    expect(p.bodyText, isEmpty);
    expect(p.diagnostics.last.code, MailDiagnosticCode.bodyLimit);
  });

  test(
    'hostile HTML becomes inert text and explicit absolute link metadata',
    () {
      final p = buildMailPresentation(mailFixture(html: hostileHtml));
      expect(p.rejected, isFalse);
      expect(p.text, contains('Hello world & مرحبًا.'));
      expect(p.text, contains('Visible after CSS'));
      expect(p.text, contains('End of visible message.'));
      expect(p.text, isNot(contains('fetch(')));
      expect(p.text, isNot(contains('Hidden frame text')));
      expect(p.text, isNot(contains('Hidden object text')));
      expect(p.text, isNot(contains('secret')));
      expect(p.images, isEmpty);
      expect(p.blockedResourceCount, greaterThanOrEqualTo(14));
      final links = p.runs.map((run) => run.link).whereType<Uri>().toSet();
      expect(links.map((uri) => uri.host), ['approved.invalid']);
      expect(
        p.runs.any(
          (run) => run.bold && p.text.substring(run.start, run.end) == 'world',
        ),
        isTrue,
      );
    },
  );

  test('script raw text cannot smuggle fake nested style or image content', () {
    final p = buildMailPresentation(
      mailFixture(
        html:
            '<ScRiPt>"<div><img src=https://never.invalid>"</sCrIpT><p>After</p>',
      ),
    );
    expect(p.text, contains('After'));
    expect(p.text, isNot(contains('never.invalid')));
    expect(p.images, isEmpty);
  });

  test('all CSS, event, srcset, SVG and image schemes are inert', () {
    for (final source in [
      'https://a.invalid/a',
      '//a.invalid/a',
      'data:image/svg+xml,a',
      'javascript:alert(1)',
      'file:///a',
      'blob:https://a.invalid/a',
    ]) {
      final p = buildMailPresentation(
        mailFixture(
          html:
              '<p onclick="fetch(1)" style="background:url($source)">Content</p>'
              '<img src="$source"><svg><image href="$source"/></svg>',
        ),
      );
      expect(p.images, isEmpty, reason: source);
      expect(p.runs.where((run) => run.link != null), isEmpty);
      expect(p.blockedResourceCount, greaterThan(0));
    }
  });

  test(
    'link admission refuses encoded active schemes, protocol-relative, user info and controls',
    () {
      for (final value in [
        'javascript:alert(1)',
        'data:text/html,a',
        '//a.invalid',
        'https://user:secret@a.invalid',
        'https://a.invalid/\nfoo',
        'file:///private',
      ]) {
        expect(approvedMailLink(value), isNull, reason: value);
      }
      expect(approvedMailLink('https://example.invalid/a'), isNotNull);
      expect(approvedMailLink('mailto:reader@example.invalid'), isNotNull);
    },
  );

  test('node and nesting rejection discards the entire partial projection', () {
    for (final budget in [
      const MailReadBudget(maxHtmlNodes: 3),
      const MailReadBudget(maxHtmlDepth: 2),
    ]) {
      final p = buildMailPresentation(
        mailFixture(html: '<div><div><p>private</p></div></div>'),
        budget: budget,
      );
      expect(p.rejected, isTrue);
      expect(p.text, isEmpty);
      expect(p.bodyText, isEmpty);
      expect(p.diagnostics.last.code, MailDiagnosticCode.renderLimit);
    }
  });

  test('oversized text, body, header and input are explicitly rejected', () {
    final cases = <(MailParseResult, MailReadBudget, MailDiagnosticCode)>[
      (
        mailFixture(plainText: 'x' * 100),
        const MailReadBudget(maxRenderTextBytes: 40),
        MailDiagnosticCode.renderLimit,
      ),
      (
        mailFixture(html: 'x' * 100),
        const MailReadBudget(maxBodyBytes: 50),
        MailDiagnosticCode.bodyLimit,
      ),
      (
        mailFixture(),
        const MailReadBudget(maxHeaderFieldBytes: 5),
        MailDiagnosticCode.headerFieldLimit,
      ),
      (
        mailFixture(raw: Uint8List(100)),
        const MailReadBudget(maxRawBytes: 50),
        MailDiagnosticCode.rawLimit,
      ),
    ];
    for (final (result, budget, code) in cases) {
      final p = buildMailPresentation(result, budget: budget);
      expect(p.rejected, isTrue);
      expect(p.text, isEmpty);
      expect(p.bodyText, isEmpty);
      expect(p.diagnostics.last.code, code);
    }
  });

  test('decoded and attachment budgets are cumulative before presentation', () {
    final p = buildMailPresentation(
      mailFixture(
        plainText: 'hello',
        attachments: [byteAttachment(bytes: Uint8List(8))],
      ),
      budget: const MailReadBudget(maxDecodedBytes: 10),
    );
    expect(p.rejected, isTrue);
    expect(p.diagnostics.last.code, MailDiagnosticCode.decodedLimit);
    final a = buildMailPresentation(
      mailFixture(attachments: [byteAttachment()]),
      budget: const MailReadBudget(maxAttachmentBytes: 3),
    );
    expect(a.rejected, isTrue);
    expect(a.diagnostics.last.code, MailDiagnosticCode.attachmentLimit);
  });

  test(
    'CID PNG is admitted by exact identity without touching source snapshots',
    () {
      final a = byteAttachment(
        cid: 'one@example.invalid',
        mediaType: 'image/png',
        bytes: onePixelPng(),
      );
      final p = buildMailPresentation(
        mailFixture(
          html: '<img src="cid:one%40example.invalid">',
          attachments: [a],
        ),
      );
      expect(p.images, hasLength(1));
      expect(identical(p.images.single.attachment, a), isTrue);
      expect((p.images.single.width, p.images.single.height), (1, 1));
    },
  );

  test(
    'duplicate and unsupported CID inputs do not decode arbitrary images',
    () {
      final a = byteAttachment(cid: 'x', mediaType: 'image/svg+xml');
      final p = buildMailPresentation(
        mailFixture(html: '<img src="cid:x">', attachments: [a]),
      );
      expect(p.images, isEmpty);
      expect(p.diagnostics.last.code, MailDiagnosticCode.imageLimit);
      final duplicate = buildMailPresentation(
        mailFixture(html: '<img src="cid:x">', attachments: [a, a]),
      );
      expect(duplicate.images, isEmpty);
      expect(duplicate.diagnostics.last.code, MailDiagnosticCode.malformedMime);
    },
  );

  test(
    'PNG pixel bombs and truncated chunks are refused before native decode',
    () {
      final bytes = onePixelPng();
      ByteData.sublistView(bytes).setUint32(16, 30000);
      ByteData.sublistView(bytes).setUint32(20, 30000);
      final p = buildMailPresentation(
        mailFixture(
          html: '<img src="cid:bomb">',
          attachments: [
            byteAttachment(cid: 'bomb', mediaType: 'image/png', bytes: bytes),
          ],
        ),
      );
      expect(p.images, isEmpty);
      expect(p.diagnostics.last.code, MailDiagnosticCode.imageLimit);
      final truncated = buildMailPresentation(
        mailFixture(
          html: '<img src="cid:bad">',
          attachments: [
            byteAttachment(
              cid: 'bad',
              mediaType: 'image/png',
              bytes: bytes.sublist(0, 35),
            ),
          ],
        ),
      );
      expect(truncated.images, isEmpty);
    },
  );

  test('cumulative CID pixels count unique images and refuse excess', () {
    final p = buildMailPresentation(
      mailFixture(
        html: '<img src="cid:a"><img src="cid:a"><img src="cid:b">',
        attachments: [
          byteAttachment(
            cid: 'a',
            mediaType: 'image/png',
            bytes: onePixelPng(),
          ),
          byteAttachment(
            cid: 'b',
            partPath: '1.3',
            mediaType: 'image/png',
            bytes: onePixelPng(),
          ),
        ],
      ),
      budget: const MailReadBudget(maxImagePixels: 1),
    );
    expect(p.images, hasLength(1));
    expect(p.diagnostics.last.code, MailDiagnosticCode.imageLimit);
  });

  test('plain alternative can be selected without changing original data', () {
    final result = mailFixture(plainText: 'plain', html: '<b>rich</b>');
    final p = buildMailPresentation(result, preferHtml: false);
    expect(p.usedHtml, isFalse);
    expect(p.text, contains('plain'));
    expect(p.text, isNot(contains('rich')));
    expect(result.original!.bytes, [255, 0, 13, 10, 65]);
  });
}

void _nestedWrapperWhitespaceTest() {
  test('nested transactional HTML wrappers do not create blank lines', () {
    const html = '''
      <div>
        <div>
          <table><tr><td>
            <div>Review of your submission is complete.</div>
            <div>Congratulations!</div>
          </td></tr></table>
        </div>
      </div>
    ''';
    final presentation = buildMailBodyPresentation(
      const MailBody(html: html),
      preferHtml: true,
    );
    expect(presentation.text, contains('Review of your submission'));
    expect(presentation.text, contains('Congratulations!'));
    expect(RegExp(r'\n\s*\n\s*\n').hasMatch(presentation.text), isFalse);
  });
}
