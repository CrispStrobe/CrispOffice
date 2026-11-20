import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'fixtures/mail_fixture.dart';

void _expectRejected(
  MailReaderPresentation presentation,
  MailDiagnosticCode code, {
  String? reason,
}) {
  expect(presentation.rejected, isTrue, reason: reason);
  expect(presentation.text, isEmpty, reason: reason);
  expect(presentation.bodyText, isEmpty, reason: reason);
  expect(presentation.runs, isEmpty, reason: reason);
  expect(presentation.images, isEmpty, reason: reason);
  expect(
    presentation.diagnostics.any(
      (diagnostic) =>
          diagnostic.code == code &&
          diagnostic.severity == MailDiagnosticSeverity.error,
    ),
    isTrue,
    reason: reason,
  );
  for (final diagnostic in presentation.diagnostics) {
    expect(
      diagnostic.message,
      isNot(contains('Visible prefix')),
      reason: reason,
    );
  }
}

void main() {
  test(
    'explicit empty plain text wins without scanning the HTML alternative',
    () {
      final quote = buildMailBodyPresentation(
        const MailBody(
          plainText: '',
          html: '<script>an oversized, unterminated alternative',
        ),
        budget: const MailReadBudget(
          maxBodyBytes: 1,
          maxDecodedBytes: 1,
          maxRenderTextBytes: 1,
          maxHtmlNodes: 1,
          maxHtmlDepth: 1,
        ),
      );

      expect(quote.rejected, isFalse);
      expect(quote.usedHtml, isFalse);
      expect(quote.text, isEmpty);
      expect(quote.bodyText, isEmpty);
      expect(quote.runs, isEmpty);
      expect(quote.images, isEmpty);
      expect(quote.diagnostics, isEmpty);
    },
  );

  test('explicit HTML preference budgets only the selected alternative', () {
    final quote = buildMailBodyPresentation(
      MailBody(plainText: 'unselected plain text ' * 100, html: '<b>Rich</b>'),
      preferHtml: true,
      budget: const MailReadBudget(
        maxBodyBytes: 16,
        maxDecodedBytes: 16,
        maxRenderTextBytes: 16,
      ),
    );

    expect(quote.rejected, isFalse);
    expect(quote.usedHtml, isTrue);
    expect(quote.text, 'Rich');
    expect(quote.bodyText, 'Rich');
    expect(
      quote.runs.any(
        (run) => run.bold && quote.text.substring(run.start, run.end) == 'Rich',
      ),
      isTrue,
    );
  });

  test('HTML-only quotation has no envelope or attachment chrome', () {
    final message = mailFixture(
      html:
          '<p>Visible 😀 مرحبًا.</p>'
          '<p>Bcc: a literal body label.</p>',
      attachments: [byteAttachment()],
    ).message!;
    final quote = buildMailBodyPresentation(
      message.body,
      budget: const MailReadBudget(
        maxRawBytes: 1,
        maxHeaderBytes: 1,
        maxHeaderFieldBytes: 1,
        maxAttachmentBytes: 1,
      ),
    );

    expect(quote.rejected, isFalse);
    expect(quote.usedHtml, isTrue);
    expect(quote.text.trim(), 'Visible 😀 مرحبًا.\nBcc: a literal body label.');
    expect(quote.bodyText, quote.text);
    expect(quote.images, isEmpty);
    for (final metadata in [
      'Fixture subject',
      'sender@example.invalid',
      'reader@example.invalid',
      'original.bin',
      'application/octet-stream',
      'Attachments:',
      '(No subject)',
    ]) {
      expect(quote.text, isNot(contains(metadata)));
    }
  });

  test('active HTML and image resources cannot enter a quotation', () {
    final quote = buildMailBodyPresentation(
      const MailBody(
        html: '$hostileHtml<img src="cid:private-inline@example.invalid">',
      ),
    );

    expect(quote.rejected, isFalse);
    expect(quote.text, contains('Hello world & مرحبًا.'));
    expect(quote.text, contains('Visible after CSS'));
    expect(quote.text, contains('End of visible message.'));
    expect(quote.text, contains('[External image blocked]'));
    expect(quote.text, contains('[Inline image unavailable]'));
    for (final hidden in [
      'fetch(',
      'Hidden frame text',
      'Hidden object text',
      'secret',
      'script.invalid',
      'image.invalid',
      'private-inline@example.invalid',
    ]) {
      expect(quote.text, isNot(contains(hidden)));
    }
    expect(quote.images, isEmpty);
    expect(quote.blockedResourceCount, greaterThan(0));
    final links = quote.runs.map((run) => run.link).whereType<Uri>().toSet();
    expect(links.map((uri) => uri.host), ['approved.invalid']);
  });

  test(
    'a missing body rejects while an explicitly empty HTML body succeeds',
    () {
      _expectRejected(
        buildMailBodyPresentation(const MailBody()),
        MailDiagnosticCode.malformedMime,
      );

      final empty = buildMailBodyPresentation(const MailBody(html: ''));
      expect(empty.rejected, isFalse);
      expect(empty.usedHtml, isTrue);
      expect(empty.text, isEmpty);
      expect(empty.bodyText, isEmpty);
      expect(empty.diagnostics, isEmpty);
    },
  );

  test(
    'selected body limits count UTF-8 bytes and admit the exact boundary',
    () {
      const body = MailBody(plainText: 'é😀');
      final admitted = buildMailBodyPresentation(
        body,
        budget: const MailReadBudget(
          maxBodyBytes: 6,
          maxDecodedBytes: 6,
          maxRenderTextBytes: 6,
        ),
      );
      expect(admitted.rejected, isFalse);
      expect(admitted.text, 'é😀');
      expect(admitted.bodyText, 'é😀');

      _expectRejected(
        buildMailBodyPresentation(
          body,
          budget: const MailReadBudget(maxBodyBytes: 5),
        ),
        MailDiagnosticCode.bodyLimit,
      );
      _expectRejected(
        buildMailBodyPresentation(
          body,
          budget: const MailReadBudget(maxDecodedBytes: 5),
        ),
        MailDiagnosticCode.decodedLimit,
      );
    },
  );

  for (final (name, budget) in <(String, MailReadBudget)>[
    ('text output', const MailReadBudget(maxRenderTextBytes: 16)),
    ('HTML node', const MailReadBudget(maxHtmlNodes: 3)),
    ('HTML depth', const MailReadBudget(maxHtmlDepth: 2)),
  ]) {
    test('$name limit discards every partially projected character', () {
      final quote = buildMailBodyPresentation(
        const MailBody(
          html:
              '<p>Visible prefix</p>'
              '<div><span><b>overflow</b></span></div>',
        ),
        budget: budget,
      );

      _expectRejected(quote, MailDiagnosticCode.renderLimit);
      expect(quote.usedHtml, isTrue);
    });
  }

  test(
    'incomplete HTML rejects the entire quotation instead of its prefix',
    () {
      for (final tail in [
        '<!-- unfinished comment',
        '<a href="unterminated attribute',
        '<script>unterminated active content',
        '<iframe>unterminated frame content',
        '<object>unterminated suppressed content',
        '<plaintext>unsupported raw text',
      ]) {
        final quote = buildMailBodyPresentation(
          MailBody(html: '<p>Visible prefix</p>$tail'),
        );

        _expectRejected(quote, MailDiagnosticCode.malformedMime, reason: tail);
        expect(quote.usedHtml, isTrue);
      }
    },
  );

  test('strict quotation rejection leaves the existing reader tolerant', () {
    const html = '<p>Visible prefix</p><!-- unfinished comment';
    _expectRejected(
      buildMailBodyPresentation(const MailBody(html: html)),
      MailDiagnosticCode.malformedMime,
    );

    final reader = buildMailPresentation(mailFixture(html: html));
    expect(reader.rejected, isFalse);
    expect(reader.bodyText.trim(), 'Visible prefix');
  });
}
