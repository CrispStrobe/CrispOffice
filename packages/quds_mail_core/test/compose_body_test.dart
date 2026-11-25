import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

MailComposeBody _body(String text) => MailComposeBody(
  paragraphs: [
    MailComposeParagraph(runs: [MailComposeRun(text: text)]),
  ],
);

void main() {
  test('immutable canonical snapshots derive consistent plain and HTML', () {
    final runs = [
      MailComposeRun(text: '<hello> & "world"\nمرحبا 📨', bold: true),
    ];
    final paragraphs = [
      MailComposeParagraph(runs: runs, alignment: MailComposeAlignment.center),
      MailComposeParagraph(runs: [MailComposeRun(text: '')]),
      MailComposeParagraph(
        runs: [
          MailComposeRun(
            text: 'Finish',
            italic: true,
            underline: true,
            strike: true,
          ),
        ],
        rightToLeft: false,
      ),
    ];
    final body = MailComposeBody(paragraphs: paragraphs);
    runs.clear();
    paragraphs.clear();
    expect(body.plainText, '<hello> & "world"\nمرحبا 📨\n\nFinish');
    expect(
      body.html,
      contains('&lt;hello&gt; &amp; &quot;world&quot;<br />مرحبا 📨'),
    );
    expect(body.html, contains('text-decoration:underline line-through'));
    expect(body.html, contains('dir="ltr"'));
    expect(body.hasFormatting, isTrue);
    expect(MailComposeBody.fromHtml(body.html), body);
    expect(() => body.paragraphs.clear(), throwsUnsupportedError);
    expect(() => body.paragraphs.first.runs.clear(), throwsUnsupportedError);
    expect(body.toString(), 'MailComposeBody(redacted)');
    expect(body.paragraphs.first.toString(), 'MailComposeParagraph(redacted)');
    expect(
      body.paragraphs.first.runs.first.toString(),
      'MailComposeRun(redacted)',
    );
  });

  test(
    'CRLF split across formatting spans and empty spans normalizes once',
    () {
      final body = MailComposeBody(
        paragraphs: [
          MailComposeParagraph(
            runs: [
              MailComposeRun(text: 'one\r', bold: true),
              MailComposeRun(text: '', italic: true),
              MailComposeRun(text: '\ntwo\rthree\r\nfour'),
            ],
          ),
        ],
      );
      expect(body.plainText, 'one\ntwo\nthree\nfour');
      expect(MailComposeBody.fromHtml(body.html).plainText, body.plainText);
      expect(body.html, isNot(contains('\r')));
    },
  );

  test('adjacent equivalent spans coalesce into one stable representation', () {
    final body = MailComposeBody(
      paragraphs: [
        MailComposeParagraph(
          runs: [
            MailComposeRun(text: 'a', bold: true),
            MailComposeRun(text: 'b', bold: true),
            MailComposeRun(text: 'c'),
          ],
        ),
      ],
    );
    expect(body.paragraphs.single.runs.length, 2);
    expect(body.paragraphs.single.runs.first.text, 'ab');
    expect(MailComposeBody.fromHtml(body.html), body);
    expect(_body('').plainText, '');
    expect(_body('').hasFormatting, isFalse);
    expect(MailComposeBody.fromHtml(_body('').html), _body(''));
  });

  test('all style combinations and paragraph directions round-trip', () {
    for (var flags = 0; flags < 16; flags++) {
      for (final alignment in MailComposeAlignment.values) {
        for (final rtl in <bool?>[null, true, false]) {
          final body = MailComposeBody(
            paragraphs: [
              MailComposeParagraph(
                alignment: alignment,
                rightToLeft: rtl,
                runs: [
                  MailComposeRun(
                    text: "one 'quoted' & two\t\nthree",
                    bold: flags & 1 != 0,
                    italic: flags & 2 != 0,
                    underline: flags & 4 != 0,
                    strike: flags & 8 != 0,
                    link: 'https://example.test/path?a=1&b=%22quoted%22',
                  ),
                ],
              ),
            ],
          );
          expect(MailComposeBody.fromHtml(body.html), body);
        }
      }
    }
  });

  for (final link in [
    'https://example.test/path?q=hello%20world#fragment',
    'http://example.test:8080/',
    'mailto:hello+mail@example.test',
  ]) {
    test('admits an explicit safe link $link', () {
      expect(MailComposeRun.isSupportedLink(link), isTrue);
      final body = MailComposeBody(
        paragraphs: [
          MailComposeParagraph(
            runs: [MailComposeRun(text: 'Open', link: link)],
          ),
        ],
      );
      expect(
        MailComposeBody.fromHtml(body.html).paragraphs.single.runs.single.link,
        link,
      );
    });
  }

  for (final link in [
    '',
    '//example.test',
    '/path',
    'javascript:alert(1)',
    'data:text/html,hello',
    'file:///private/mail',
    'cid:image',
    'https://user:password@example.test/',
    'https://example.test/\nsecret',
    'https://example.test/%0d%0aX-Foo:bar',
    'https://example.test/%00',
    'https://example.test/%5cprivate',
    'https://example.test/%FF',
    'https://example.test/%xx',
    'https://example.test/has space',
    'https://example.test:70000/',
    'https://',
    'mailto:a@example.test?bcc=hidden@example.test',
    'mailto:a@example.test#fragment',
    'mailto:.a@example.test',
    'mailto:a..b@example.test',
    'mailto:a.@example.test',
    'mailto:a@example.test,b@example.test',
  ]) {
    test('rejects unsafe or unsupported link ${link.codeUnits}', () {
      expect(MailComposeRun.isSupportedLink(link), isFalse);
      expect(
        () => MailComposeRun(text: 'Open', link: link),
        throwsFormatException,
      );
    });
  }

  for (final value in [
    '\u0000',
    '\u000b',
    '\u001b',
    '\u007f',
    '\u0085',
    '\ud800',
    '\udc00',
    '\ud800a',
  ]) {
    test('rejects invalid text ${value.codeUnits} without leaking it', () {
      try {
        _body('private$value');
        fail('Invalid input was accepted.');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains('private')));
        expect(error.source, isNull);
      }
    });
  }

  test('plain, escaped HTML and UTF-8 budgets are independent', () {
    expect(
      _body('x' * MailComposeBody.maxPlainTextBytes).plainText.length,
      MailComposeBody.maxPlainTextBytes,
    );
    expect(
      () => _body('x' * (MailComposeBody.maxPlainTextBytes + 1)),
      throwsFormatException,
    );
    expect(
      () => _body('📨' * (MailComposeBody.maxPlainTextBytes ~/ 4 + 1)),
      throwsFormatException,
    );
    expect(
      () => _body('&' * MailComposeBody.maxPlainTextBytes),
      throwsFormatException,
    );
    expect(
      () => MailComposeBody.fromHtml('x' * (MailComposeBody.maxHtmlBytes + 1)),
      throwsFormatException,
    );
  });

  test(
    'empty first, middle and trailing paragraphs have a line-box placeholder',
    () {
      final body = MailComposeBody(
        paragraphs: [
          for (final text in ['', 'middle', '', 'last', ''])
            MailComposeParagraph(runs: [MailComposeRun(text: text)]),
        ],
      );
      expect(body.plainText, '\nmiddle\n\nlast\n');
      expect('<br /></p>'.allMatches(body.html).length, 3);
      expect(MailComposeBody.fromHtml(body.html), body);
      expect(
        () => MailComposeBody.fromHtml(
          body.html.replaceFirst('<br /></p>', '</p>'),
        ),
        throwsFormatException,
      );
      expect(
        () => MailComposeBody.fromHtml(
          body.html.replaceFirst('middle</span>', 'middle</span><br />'),
        ),
        throwsFormatException,
      );
      final soft = _body('\n');
      expect(soft.html, contains('<span><br /></span></p>'));
      expect(soft.html, isNot(contains('</span><br />')));
      expect(MailComposeBody.fromHtml(soft.html).plainText, '\n');
    },
  );

  test('structure is bounded before iterables can grow without limit', () {
    final paragraph = MailComposeParagraph(runs: [MailComposeRun(text: '')]);
    expect(() => MailComposeBody(paragraphs: const []), throwsFormatException);
    expect(
      () => MailComposeBody(
        paragraphs: Iterable.generate(
          MailComposeBody.maxParagraphs + 1,
          (_) => paragraph,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => MailComposeParagraph(
        runs: Iterable.generate(
          MailComposeBody.maxRuns + 1,
          (_) => MailComposeRun(text: ''),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => MailComposeRun(
        text: 'x',
        link: 'https://example.test/${'x' * MailComposeRun.maxLinkBytes}',
      ),
      throwsFormatException,
    );
  });

  test('rejects hostile, noncanonical and hidden-content HTML completely', () {
    final valid = _body('ordinary & safe').html;
    final invalid = <String>[
      '<p>ordinary</p>',
      valid.replaceAll(
        'data-crispoffice-mail="1"',
        'data-crispoffice-mail="2"',
      ),
      '<!DOCTYPE div [<!ENTITY x SYSTEM "file:///private">]>$valid',
      '$valid<script>alert(1)</script>',
      valid.replaceFirst('<span>', '<span onclick="alert(1)">'),
      valid.replaceFirst('<span>', '<span><img src="https://tracker.test/">'),
      valid.replaceFirst('<span>', '<span><svg onload="alert(1)">'),
      valid.replaceFirst('<span>', '<span><!--hidden-->'),
      valid.replaceFirst('<span>', '<span><![CDATA[hidden]]>'),
      valid.replaceFirst('<span>', '<span><span>'),
      valid.replaceFirst(
        '<span>',
        '<span style="background:url(https://tracker.test)">',
      ),
      valid.replaceFirst('text-align:left', 'text-align:left;background:red'),
      valid.replaceFirst('&amp;', '&#38;'),
      valid.replaceFirst('&amp;', '&unknown;'),
      valid.replaceFirst('ordinary', 'ordinary\r\n'),
      valid.replaceFirst('</span>', '</SPAN>'),
      valid.replaceFirst(
        'ordinary',
        '<a href="javascript:alert(1)">ordinary</a>',
      ),
      valid.replaceFirst('</div>', ''),
      valid.replaceFirst('<span>', '<span style="">'),
      valid.replaceFirst('ordinary', 'ord</span><span>inary'),
      '$valid ',
    ];
    for (final html in invalid) {
      expect(() => MailComposeBody.fromHtml(html), throwsFormatException);
    }
  });
}
