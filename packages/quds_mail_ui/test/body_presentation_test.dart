import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

void expectRejected(
  MailReaderPresentation presentation,
  MailDiagnosticCode code,
) {
  expect(presentation.rejected, isTrue);
  expect(presentation.text, isEmpty);
  expect(presentation.bodyText, isEmpty);
  expect(presentation.runs, isEmpty);
  expect(presentation.images, isEmpty);
  expect(presentation.diagnostics.single.code, code);
  expect(
    presentation.diagnostics.single.severity,
    MailDiagnosticSeverity.error,
  );
}

void main() {
  test('plain quotation preserves literal text and Unicode exactly', () {
    const text = 'Café مرحبًا 😀\r\n  Indent\nBcc: a literal body label.'
        '\n<script>Plain text is not HTML.</script>';
    final presentation = buildMailBodyPresentation(
      const MailBody(plainText: text, html: '<p>Not selected</p>'),
    );
    expect(presentation.rejected, isFalse);
    expect(presentation.usedHtml, isFalse);
    expect(presentation.text, text);
    expect(presentation.bodyText, text);
    expect(presentation.images, isEmpty);
    expect(presentation.diagnostics, isEmpty);
  });

  test('explicitly empty plain text never falls back to HTML by default', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(plainText: '', html: '<p>Must not enter the quote</p>'),
      budget: const MailReadBudget(maxBodyBytes: 1, maxRenderTextBytes: 1),
    );
    expect(presentation.rejected, isFalse);
    expect(presentation.usedHtml, isFalse);
    expect(presentation.text, isEmpty);
    expect(presentation.bodyText, isEmpty);
    expect(presentation.runs, isEmpty);
  });

  test('unselected alternatives are not scanned or budgeted', () {
    final html = 'large' * 1000;
    final presentation = buildMailBodyPresentation(
      MailBody(plainText: 'x', html: '$html<script>'),
      budget: const MailReadBudget(maxBodyBytes: 1, maxDecodedBytes: 1),
    );
    expect(presentation.rejected, isFalse);
    expect(presentation.bodyText, 'x');
  });

  test('HTML-only text uses inert entities, breaks and styling', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(
        html: 'Hello <b>world</b> &amp; مرحبًا<br>Next &#x1f600;',
      ),
    );
    expect(presentation.rejected, isFalse);
    expect(presentation.usedHtml, isTrue);
    expect(presentation.text, 'Hello world & مرحبًا\nNext 😀');
    expect(presentation.bodyText, presentation.text);
    expect(
      presentation.runs.any(
        (run) =>
            run.bold &&
            presentation.text.substring(run.start, run.end) == 'world',
      ),
      isTrue,
    );
  });

  test('paragraphs, lists and table cells retain readable separation', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(
        html: '<p>A</p><ul><li>B</li><li>C</li></ul>'
            '<table><tr><td>X</td><td>Y</td></tr></table>',
      ),
    );
    expect(presentation.rejected, isFalse);
    expect(presentation.bodyText, 'A\n• B\n• C\nX  Y\n');
  });

  test('explicit HTML preference can select the alternate body', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(plainText: 'plain', html: '<p>HTML</p>'),
      preferHtml: true,
    );
    expect(presentation.rejected, isFalse);
    expect(presentation.usedHtml, isTrue);
    expect(presentation.bodyText, 'HTML\n');
  });

  test('missing bodies reject without inventing quoted source', () {
    expectRejected(
      buildMailBodyPresentation(const MailBody()),
      MailDiagnosticCode.malformedMime,
    );
  });

  test('envelopes and attachments cannot affect body-only quotation', () {
    final message = MailMessage(
      raw: MailBytes(Uint8List(0)),
      envelope: MailEnvelope(
        subject: 'private metadata' * 100,
        bcc: List<MailAddress>.filled(
          1025,
          const MailAddress('hidden@example.invalid'),
        ),
      ),
      body: const MailBody(plainText: 'Body'),
      attachments: [
        MailAttachment(
          partPath: '2',
          mediaType: 'application/octet-stream',
          displayName: 'private-name.bin',
          content: MailBytes(Uint8List(10)),
        ),
      ],
    );
    final presentation = buildMailBodyPresentation(
      message.body,
      budget: const MailReadBudget(
        maxHeaderBytes: 1,
        maxHeaderFieldBytes: 1,
        maxAttachmentBytes: 1,
      ),
    );
    expect(presentation.rejected, isFalse);
    expect(presentation.bodyText, 'Body');
    expect(presentation.images, isEmpty);
    expect(presentation.diagnostics, isEmpty);
  });

  test('active markup and resource attributes never enter quoted text', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(
        html: '<p>Before</p>'
            '<ScRiPt>fetch("https://secret.invalid")</sCrIpT>'
            '<style>@import "https://secret.invalid/style";</style>'
            '<form><input value="secret"><button>secret</button></form>'
            '<svg><text>secret</text></svg>'
            '<iframe src="https://secret.invalid">secret</iframe>'
            '<object data="https://secret.invalid">secret</object>'
            '<p style="background:url(https://secret.invalid)"'
            ' onclick="secret()">After</p>'
            '<a href="java&#x73;cript:secret()">Visible link</a>',
      ),
    );
    expect(presentation.rejected, isFalse);
    expect(presentation.bodyText, 'Before\nAfter\nVisible link');
    expect(presentation.bodyText, isNot(contains('secret')));
    expect(presentation.images, isEmpty);
    expect(presentation.runs.every((run) => run.link == null), isTrue);
    expect(presentation.blockedResourceCount, greaterThan(0));
    expect(
      presentation.diagnostics.every(
        (diagnostic) =>
            diagnostic.severity == MailDiagnosticSeverity.information,
      ),
      isTrue,
    );
  });

  test('decoded markup remains literal text and is never reparsed', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(html: '&lt;script&gt;Visible data&lt;/script&gt;'),
    );
    expect(presentation.rejected, isFalse);
    expect(presentation.bodyText, '<script>Visible data</script>');
    expect(presentation.images, isEmpty);
    expect(presentation.blockedResourceCount, 0);
  });

  test('remote and CID images have no attachment lookup or resource path', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(
        html: '<img src="https://remote.invalid/private.png">'
            '<img srcset="https://remote.invalid/large.png 2x"'
            ' src="cid:private-name.png">',
      ),
    );
    expect(presentation.rejected, isFalse);
    expect(
      presentation.bodyText,
      '[External image blocked][Inline image unavailable]',
    );
    expect(presentation.bodyText, isNot(contains('private-name')));
    expect(presentation.bodyText, isNot(contains('remote.invalid')));
    expect(presentation.images, isEmpty);
    expect(presentation.blockedResourceCount, greaterThan(0));
  });

  test('safe links remain inert metadata; destinations are not quoted', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(
        html: '<a href="https://approved.invalid/path">Visible label</a>',
      ),
    );
    expect(presentation.rejected, isFalse);
    expect(presentation.bodyText, 'Visible label');
    expect(presentation.runs.single.link?.host, 'approved.invalid');
    expect(presentation.images, isEmpty);
  });

  test('selected input counts complete UTF-8 scalar values', () {
    final admitted = buildMailBodyPresentation(
      const MailBody(plainText: '😀'),
      budget: const MailReadBudget(maxBodyBytes: 4, maxRenderTextBytes: 4),
    );
    expect(admitted.rejected, isFalse);
    expect(admitted.bodyText, '😀');
    final rejected = buildMailBodyPresentation(
      const MailBody(plainText: '😀x'),
      budget: const MailReadBudget(maxBodyBytes: 4),
    );
    expectRejected(rejected, MailDiagnosticCode.bodyLimit);
    expect(rejected.diagnostics.single.observed, 5);
    expect(rejected.diagnostics.single.limit, 4);
  });

  test('selected HTML input is bounded before markup projection', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(html: '<p>Visible</p>'),
      budget: const MailReadBudget(maxBodyBytes: 12),
    );
    expectRejected(presentation, MailDiagnosticCode.bodyLimit);
  });

  test('decoded content budget is independently enforced', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(plainText: '😀'),
      budget: const MailReadBudget(maxDecodedBytes: 3),
    );
    expectRejected(presentation, MailDiagnosticCode.decodedLimit);
    expect(presentation.diagnostics.single.observed, 4);
    expect(presentation.diagnostics.single.limit, 3);
  });

  test('render output limit discards an already projected prefix', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(html: '<p>one</p><p>two</p>'),
      budget: const MailReadBudget(maxRenderTextBytes: 7),
    );
    expectRejected(presentation, MailDiagnosticCode.renderLimit);
    expect(presentation.diagnostics.single.observed, 8);
    expect(presentation.diagnostics.single.limit, 7);
  });

  test('HTML node and attribute limits discard the whole projection', () {
    for (final body in [
      const MailBody(html: '<p>x</p><p>y</p>'),
      const MailBody(html: '<p first="one" second="two">x</p>'),
    ]) {
      final presentation = buildMailBodyPresentation(
        body,
        budget: const MailReadBudget(maxHtmlNodes: 2),
      );
      expectRejected(presentation, MailDiagnosticCode.renderLimit);
    }
  });

  test('HTML nesting is bounded before deeper content is admitted', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(html: '<div><b><i>Deep</i></b></div>'),
      budget: const MailReadBudget(maxHtmlDepth: 2),
    );
    expectRejected(presentation, MailDiagnosticCode.renderLimit);
  });

  for (final malformed in [
    '<p>Prefix</p><!--private tail',
    '<p>Prefix</p><a href="private tail',
    '<p>Prefix</p><script>private tail',
    '<p>Prefix</p><style>private tail',
    '<p>Prefix</p><iframe>private tail',
    '<p>Prefix</p><form>private tail',
    '<p>Prefix</p><svg><text>private tail',
    '<p>Prefix</p><plaintext>private tail',
    '<p>Prefix</p><@>private tail',
    '<p>Prefix</p><>private tail',
  ]) {
    test(
      'incomplete HTML rejects instead of returning its prefix: $malformed',
      () {
        final presentation = buildMailBodyPresentation(
          MailBody(html: malformed),
        );
        expectRejected(presentation, MailDiagnosticCode.malformedMime);
        expect(presentation.usedHtml, isTrue);
        expect(
          presentation.diagnostics.single.message,
          isNot(contains('private tail')),
        );
      },
    );
  }

  test('ordinary optional closing tags do not lose complete visible text', () {
    final presentation = buildMailBodyPresentation(
      const MailBody(html: '<p>First<p>Second'),
    );
    expect(presentation.rejected, isFalse);
    expect(presentation.bodyText, 'First\nSecond');
  });

  test('strict quotation does not change legacy reader recovery behavior', () {
    const body = MailBody(html: '<p>Visible prefix</p><unfinished');
    final reader = buildMailPresentation(
      MailParseResult(
        status: MailParseStatus.complete,
        message: MailMessage(
          raw: MailBytes(Uint8List(0)),
          envelope: MailEnvelope(),
          body: body,
        ),
      ),
    );
    expect(reader.rejected, isFalse);
    expect(reader.bodyText, 'Visible prefix\n');
    expect(reader.diagnostics.last.code, MailDiagnosticCode.malformedMime);
    expectRejected(
      buildMailBodyPresentation(body),
      MailDiagnosticCode.malformedMime,
    );
  });

  test('invalid caller budgets fail before any projection', () {
    expect(
      () => buildMailBodyPresentation(
        const MailBody(plainText: 'x'),
        budget: const MailReadBudget(maxHtmlNodes: 0),
      ),
      throwsArgumentError,
    );
  });
}
