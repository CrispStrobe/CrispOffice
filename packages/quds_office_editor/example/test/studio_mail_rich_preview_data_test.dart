import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_rich_preview_data.dart';
import 'package:test/test.dart';

MailComposeBody _body(String text) => MailComposeBody(
  paragraphs: [
    MailComposeParagraph(runs: [MailComposeRun(text: text, bold: true)]),
  ],
);

String _text(StudioMailRichPreviewData preview) => preview.paragraphs
    .map((paragraph) => paragraph.runs.map((run) => run.text).join())
    .join('\n');

void main() {
  test(
    'small preview owns immutable formatting and retains the whole body',
    () {
      final body = MailComposeBody(
        paragraphs: [
          MailComposeParagraph(
            runs: [
              MailComposeRun(
                text: 'One 📨',
                bold: true,
                link: 'https://example.test/',
              ),
            ],
            alignment: MailComposeAlignment.right,
            rightToLeft: true,
          ),
          MailComposeParagraph(runs: [MailComposeRun(text: '')]),
        ],
      );
      final preview = StudioMailRichPreviewData(body);
      expect(_text(preview), body.plainText);
      expect(preview.visibleTextBytes, utf8.encode(body.plainText).length);
      expect(preview.truncated, isFalse);
      expect(preview.paragraphs.first.alignment, MailComposeAlignment.right);
      expect(preview.paragraphs.first.rightToLeft, isTrue);
      expect(preview.paragraphs.first.runs.single.bold, isTrue);
      expect(preview.paragraphs.first.runs.single.linkBlue, isTrue);
      expect(
        preview.paragraphs.first.runs.single.link,
        'https://example.test/',
      );
      expect(() => preview.paragraphs.clear(), throwsUnsupportedError);
    },
  );

  test(
    'UTF-8 byte limit never splits a surrogate pair or alters frozen body',
    () {
      final text =
          '${'x' * (StudioMailRichPreviewData.maxTextBytes - 2)}📨tail';
      final body = _body(text);
      final original = body.html;
      final preview = StudioMailRichPreviewData(body);
      expect(preview.truncated, isTrue);
      expect(
        _text(preview),
        'x' * (StudioMailRichPreviewData.maxTextBytes - 2),
      );
      expect(
        preview.visibleTextBytes,
        StudioMailRichPreviewData.maxTextBytes - 2,
      );
      expect(utf8.decode(utf8.encode(_text(preview))), _text(preview));
      expect(body.plainText, text);
      expect(body.html, original);
      expect(preview.paragraphs.single.runs.single.bold, isTrue);
    },
  );

  test(
    'complete scalar at the limit is retained and does not imply clipping',
    () {
      final text = '${'x' * (StudioMailRichPreviewData.maxTextBytes - 4)}📨';
      final preview = StudioMailRichPreviewData(_body(text));
      expect(_text(preview), text);
      expect(preview.visibleTextBytes, StudioMailRichPreviewData.maxTextBytes);
      expect(preview.truncated, isFalse);
      final plain = studioMailPlainPreviewText('$text!');
      expect(plain.text, text);
      expect(plain.truncated, isTrue);
    },
  );

  test('budget is shared across spans and paragraph separators', () {
    final body = MailComposeBody(
      paragraphs: [
        MailComposeParagraph(
          runs: [
            MailComposeRun(
              text: 'x' * (StudioMailRichPreviewData.maxTextBytes - 3),
              bold: true,
            ),
          ],
        ),
        MailComposeParagraph(
          runs: [
            MailComposeRun(text: 'ab', italic: true),
            MailComposeRun(text: 'c', strike: true),
          ],
        ),
      ],
    );
    final preview = StudioMailRichPreviewData(body);
    expect(preview.truncated, isTrue);
    expect(_text(preview).endsWith('\nab'), isTrue);
    expect(
      utf8.encode(_text(preview)).length,
      StudioMailRichPreviewData.maxTextBytes,
    );
  });

  test(
    'clipping retains fixed blue and explicitly black link presentation',
    () {
      for (final link in <String?>[null, 'https://example.test']) {
        for (final blue in [false, true]) {
          final body = MailComposeBody(
            paragraphs: [
              MailComposeParagraph(
                runs: [
                  MailComposeRun(
                    text: 'x' * (StudioMailRichPreviewData.maxTextBytes + 1),
                    link: link,
                    linkBlue: blue,
                  ),
                ],
              ),
            ],
          );
          final preview = StudioMailRichPreviewData(body);
          expect(preview.truncated, isTrue);
          expect(preview.paragraphs.single.runs.single.linkBlue, blue);
          expect(preview.paragraphs.single.runs.single.link, link);
        }
      }
    },
  );

  test('paragraph limit clips even when the text budget remains', () {
    final body = MailComposeBody(
      paragraphs: [
        for (var i = 0; i <= StudioMailRichPreviewData.maxParagraphs; i++)
          MailComposeParagraph(runs: [MailComposeRun(text: 'line$i')]),
      ],
    );
    final preview = StudioMailRichPreviewData(body);
    expect(preview.paragraphs.length, StudioMailRichPreviewData.maxParagraphs);
    expect(preview.truncated, isTrue);
    expect(_text(preview), isNot(contains('line256')));
    expect(body.paragraphs.length, 257);
  });

  test(
    'run limit clips pathological formatting and preserves admitted styles',
    () {
      final body = MailComposeBody(
        paragraphs: [
          MailComposeParagraph(
            runs: [
              for (var i = 0; i <= StudioMailRichPreviewData.maxRuns; i++)
                MailComposeRun(text: 'x', bold: i.isEven),
            ],
          ),
        ],
      );
      final preview = StudioMailRichPreviewData(body);
      expect(preview.visibleRuns, StudioMailRichPreviewData.maxRuns);
      expect(
        preview.paragraphs.single.runs.length,
        StudioMailRichPreviewData.maxRuns,
      );
      expect(preview.truncated, isTrue);
      expect(preview.paragraphs.single.runs[0].bold, isTrue);
      expect(preview.paragraphs.single.runs[1].bold, isFalse);
    },
  );

  test('exact structural limits do not claim unavailable content', () {
    final paragraphs = MailComposeBody(
      paragraphs: [
        for (var i = 0; i < StudioMailRichPreviewData.maxParagraphs; i++)
          MailComposeParagraph(runs: [MailComposeRun(text: '')]),
      ],
    );
    expect(StudioMailRichPreviewData(paragraphs).truncated, isFalse);
    final runs = MailComposeBody(
      paragraphs: [
        MailComposeParagraph(
          runs: [
            for (var i = 0; i < StudioMailRichPreviewData.maxRuns; i++)
              MailComposeRun(text: '', bold: i.isEven),
          ],
        ),
      ],
    );
    expect(StudioMailRichPreviewData(runs).truncated, isFalse);
  });

  test('legacy plain preview stays literal and scalar-safe', () {
    final ordinary = studioMailPlainPreviewText(
      '<img src="https://tracker.test"> & مرحبا',
    );
    expect(ordinary.text, '<img src="https://tracker.test"> & مرحبا');
    expect(ordinary.truncated, isFalse);
    final unicode = studioMailPlainPreviewText('📨' * 20000);
    expect(
      unicode.text.runes.length,
      StudioMailRichPreviewData.maxTextBytes ~/ 4,
    );
    expect(unicode.truncated, isTrue);
    expect(utf8.decode(utf8.encode(unicode.text)), unicode.text);
  });
}
