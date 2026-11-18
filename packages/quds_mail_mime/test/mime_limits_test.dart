import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:test/test.dart';

import 'fixtures/messages.dart';

void main() {
  const codec = QudsMimeCodec();
  void rejected(String source, MailReadBudget budget, MailDiagnosticCode code) {
    final result = codec.parse(eml(source), budget: budget);
    expect(result.status, MailParseStatus.rejected);
    expect(result.message, isNull);
    expect(result.diagnostics.map((d) => d.code), contains(code));
  }

  test('raw limit is enforced before retaining another copy', () {
    final result = codec.parse(
      eml(simpleMessage),
      budget: const MailReadBudget(maxRawBytes: 8),
    );
    expect(result.status, MailParseStatus.rejected);
    expect(result.original, isNull);
    expect(result.diagnostics.single.code, MailDiagnosticCode.rawLimit);
  });
  test('decoded and body budgets count alternatives cumulatively', () {
    final source = mixed([
      withBody('12345'),
      withBody('67890'),
    ], type: 'alternative');
    rejected(
      source,
      const MailReadBudget(maxDecodedBytes: 9),
      MailDiagnosticCode.decodedLimit,
    );
    rejected(
      source,
      const MailReadBudget(maxBodyBytes: 9),
      MailDiagnosticCode.bodyLimit,
    );
  });
  test('attachment decoded size is checked before base64 allocation', () {
    rejected(
      'Content-Type: application/octet-stream\r\n'
      'Content-Transfer-Encoding: base64\r\n\r\nAAECA/8=',
      const MailReadBudget(maxAttachmentBytes: 4),
      MailDiagnosticCode.attachmentLimit,
    );
  });
  test('part and attachment count bounds stop traversal', () {
    final source = mixed(
      List.generate(
        4,
        (_) => 'Content-Type: application/octet-stream\r\n\r\nx',
      ),
    );
    rejected(
      source,
      const MailReadBudget(maxParts: 3),
      MailDiagnosticCode.partCountLimit,
    );
    rejected(
      source,
      const MailReadBudget(maxAttachments: 2),
      MailDiagnosticCode.attachmentCountLimit,
    );
  });
  test('depth bounds are checked before entering child headers', () {
    var source = withBody('leaf');
    for (var i = 0; i < 6; i++) {
      source =
          'Content-Type: multipart/mixed; boundary=b$i\r\n\r\n'
          '--b$i\r\n$source\r\n--b$i--\r\n';
    }
    rejected(
      source,
      const MailReadBudget(maxNestingDepth: 4),
      MailDiagnosticCode.nestingLimit,
    );
  });
  test('unsupported attachments still count toward the attachment budget', () {
    final source = mixed(
      List.generate(
        3,
        (_) =>
            'Content-Type: application/octet-stream\r\n'
            'Content-Transfer-Encoding: unsupported\r\n\r\nx',
      ),
    );
    rejected(
      source,
      const MailReadBudget(maxAttachments: 2),
      MailDiagnosticCode.attachmentCountLimit,
    );
  });
  test('folded fields and cumulative header bytes are bounded', () {
    rejected(
      'Subject: short\r\n ${'a' * 30}\r\n\r\nbody',
      const MailReadBudget(maxHeaderFieldBytes: 32),
      MailDiagnosticCode.headerFieldLimit,
    );
    rejected(
      mixed([withBody('x'), withBody('y')]),
      const MailReadBudget(maxHeaderBytes: 100),
      MailDiagnosticCode.headerLimit,
    );
  });
  test('decoded legacy charset expansion respects rendering bytes', () {
    rejected(
      withBody(
        '=E9=E9=E9',
        charset: 'iso-8859-1',
        encoding: 'quoted-printable',
      ),
      const MailReadBudget(maxRenderTextBytes: 5),
      MailDiagnosticCode.renderLimit,
    );
  });
  test('a cancelled parse never starts copying or projecting source', () {
    final cancellation = MailCancellationSource()..cancel();
    final result = codec.parse(
      eml(simpleMessage),
      cancellation: cancellation.token,
    );
    expect(result.status, MailParseStatus.cancelled);
    expect(result.original, isNull);
  });
  test('invalid caller budgets are programmer errors', () {
    expect(
      () => codec.parse(
        eml(simpleMessage),
        budget: const MailReadBudget(maxParts: 0),
      ),
      throwsArgumentError,
    );
  });
}
