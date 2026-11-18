import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:test/test.dart';

import 'fixtures/messages.dart';

void main() {
  const codec = QudsMimeCodec();
  test('encoded Q word can start with an escaped UTF8 octet', () {
    final result = codec.parse(
      eml('Subject: =?UTF-8?Q?=E2=82=AC?=\r\n\r\nbody'),
    );
    expect(result.status, MailParseStatus.complete);
    expect(result.message!.envelope.subject, '€');
    expect(result.diagnostics, isEmpty);
  });

  test('rendered bytes accumulate across every MIME alternative', () {
    final result = codec.parse(
      eml(mixed([withBody('1234'), withBody('5678')], type: 'alternative')),
      budget: const MailReadBudget(maxRenderTextBytes: 7),
    );
    expect(result.status, MailParseStatus.rejected);
    expect(result.message, isNull);
    expect(
      result.diagnostics.map((d) => d.code),
      contains(MailDiagnosticCode.renderLimit),
    );
    final limit = result.diagnostics.firstWhere(
      (d) => d.code == MailDiagnosticCode.renderLimit,
    );
    expect(limit.observed, 8);
    expect(limit.limit, 7);
  });
}
