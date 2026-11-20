import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

void main() {
  test('whitespace-only nodes preserve word boundaries across inline tags', () {
    final body = buildMailBodyPresentation(
      const MailBody(
        html:
            '<b>Hello</b> \n\t <i>world</i> <a href="https://example.invalid/">again</a>',
      ),
    );
    expect(body.text, 'Hello world again');
  });

  test(
    'whitespace collapses across inline boundaries without erasing NBSP',
    () {
      final body = buildMailBodyPresentation(
        const MailBody(
          html: '<b>Hello </b> \t <i> world</i>&nbsp;<span>again</span>',
        ),
      );
      expect(body.text, 'Hello world\u00a0again');
    },
  );

  test('preformatted spaces, tabs and line breaks survive nested styling', () {
    final body = buildMailBodyPresentation(
      const MailBody(html: '<pre>  A\n\t<b>B  </b>\nC</pre>'),
    );
    expect(body.text, '  A\n\tB  \nC\n');
  });

  test('source indentation between nested block wrappers stays collapsed', () {
    final body = buildMailBodyPresentation(
      const MailBody(
        html: '''
      <div>
        <div>
          <p>First.</p>
          <p>Second.</p>
        </div>
      </div>
    ''',
      ),
    );
    expect(body.text, 'First.\nSecond.\n');
  });

  test('plain text whitespace remains verbatim', () {
    final body = buildMailBodyPresentation(
      const MailBody(plainText: '  A\n\tB  '),
    );
    expect(body.text, '  A\n\tB  ');
  });
}
