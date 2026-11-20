import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'fixtures/mail_fixture.dart';

MailInlineImage image(String url, {int claimedWidth = 1}) => MailInlineImage(
  attachment: MailAttachment(
    partPath: 'remote:$url',
    mediaType: 'image/png',
    displayName: 'Image',
    content: MailBytes(onePixelPng()),
  ),
  width: claimedWidth,
  height: 1,
);

void main() {
  test('offers only inert explicit image sources, with entities decoded', () {
    final reader = MailReaderController(
      result: mailFixture(
        html: '''
      <!-- <img src="https://comment.invalid/"> -->
      <script>const s = '<img src="https://script.invalid/">';</script>
      <iframe src="https://frame.invalid/"><img src="https://hidden.invalid/"></iframe>
      <svg><image src="https://svg.invalid/"></image></svg>
      <video src="https://video.invalid/"></video>
      <img src="//relative.invalid/"><img src="data:image/png;base64,A">
      <img src="https://user:password@credential.invalid/">
      <img src="https://image.invalid/a?x=1&amp;y=2">
      <img src=https://unquoted.invalid/b>
      <img src="https://image.invalid/a?x=1&amp;y=2">
    ''',
      ),
    );
    addTearDown(reader.dispose);
    expect(reader.presentation.remoteImageUrls.map((uri) => uri.toString()), [
      'https://image.invalid/a?x=1&y=2',
      'https://unquoted.invalid/b',
    ]);
    expect(reader.presentation.images, isEmpty);
  });

  test('candidate count remains bounded after the first eight are loaded', () {
    final reader = MailReaderController(
      result: mailFixture(
        html: [
          for (var i = 0; i < 20; i++) '<img src="https://image.invalid/$i">',
        ].join(),
      ),
    );
    addTearDown(reader.dispose);
    expect(reader.presentation.remoteImageUrls, hasLength(8));
    reader.addImages([
      for (var i = 0; i < 8; i++) image('https://image.invalid/$i'),
    ]);
    expect(reader.presentation.images, hasLength(8));
    expect(reader.presentation.remoteImageUrls, isEmpty);
    expect(reader.presentation.blockedResourceCount, 12);
    expect(reader.presentation.bodyText, contains('[External image blocked]'));
  });

  test(
    'partial loads keep accurate placeholders and accumulate across actions',
    () {
      final reader = MailReaderController(
        result: mailFixture(
          plainText: 'Plain alternative',
          html:
              '<img src="https://image.invalid/a"> '
              '<img src="https://image.invalid/b" alt="B">',
        ),
      );
      addTearDown(reader.dispose);
      final sourceHash = reader.result.original!.sha256;
      reader.search('blocked');
      reader.selectAll();
      reader.addImages([image('https://image.invalid/a')]);
      expect(reader.presentation.images, hasLength(1));
      expect(reader.presentation.blockedResourceCount, 1);
      expect(
        reader.presentation.bodyText,
        contains('[External image blocked: B]'),
      );
      expect(reader.searchMatches, hasLength(1));
      expect(reader.selectedText, isEmpty);
      reader.addImages([image('https://image.invalid/b')]);
      expect(reader.presentation.images, hasLength(2));
      expect(reader.presentation.blockedResourceCount, 0);
      expect(reader.searchMatches, isEmpty);
      expect(reader.result.original!.sha256, sourceHash);
      reader.setPreferHtml(false);
      expect(reader.presentation.images, isEmpty);
      reader.setPreferHtml(true);
      expect(reader.presentation.images, hasLength(2));
    },
  );

  test(
    'unrequested URLs and stale message completions cannot attach images',
    () {
      final original = mailFixture(html: '<img src="https://image.invalid/a">');
      final reader = MailReaderController(result: original);
      addTearDown(reader.dispose);
      reader.addImages([image('https://unrelated.invalid/')]);
      expect(reader.presentation.images, isEmpty);
      reader.replaceResult(
        mailFixture(html: '<img src="https://image.invalid/a">'),
      );
      reader.addImages([
        image('https://image.invalid/a'),
      ], expectedResult: original);
      expect(reader.presentation.images, isEmpty);
      reader.addImages([image('https://image.invalid/a')]);
      expect(reader.presentation.images, hasLength(1));
      reader.replaceResult(
        mailFixture(html: '<img src="https://image.invalid/a">'),
      );
      expect(reader.presentation.images, isEmpty);
    },
  );

  test(
    'untrusted dimensions cannot bypass cumulative local and remote pixels',
    () {
      final reader = MailReaderController(
        budget: const MailReadBudget(maxImagePixels: 2),
        result: mailFixture(
          html:
              '<img src="cid:local">'
              '<img src="https://image.invalid/a"><img src="https://image.invalid/b">',
          attachments: [
            byteAttachment(
              cid: 'local',
              mediaType: 'image/png',
              bytes: onePixelPng(),
            ),
          ],
        ),
      );
      addTearDown(reader.dispose);
      reader.addImages([
        image('https://image.invalid/a', claimedWidth: 1000),
        image('https://image.invalid/b'),
      ]);
      expect(reader.presentation.images, hasLength(2));
      expect(reader.presentation.images.map((image) => image.width), [1, 1]);
      expect(reader.presentation.blockedResourceCount, 1);
      expect(reader.presentation.remoteImageUrls, [
        Uri.parse('https://image.invalid/b'),
      ]);
    },
  );

  test('remote bytes share the cumulative decoded message budget', () {
    const html = '<img src="https://image.invalid/a">';
    final reader = MailReaderController(
      budget: MailReadBudget(
        maxDecodedBytes: html.length + onePixelPng().length - 1,
      ),
      result: mailFixture(html: html),
    );
    addTearDown(reader.dispose);
    reader.addImages([image('https://image.invalid/a')]);
    expect(reader.presentation.images, isEmpty);
    expect(reader.presentation.rejected, isFalse);
    expect(reader.presentation.blockedResourceCount, 1);
  });

  test(
    'malformed remote rasters retain their original blocked placeholder',
    () {
      final reader = MailReaderController(
        result: mailFixture(
          html: '<img src="https://image.invalid/a" alt="chart">',
        ),
      );
      addTearDown(reader.dispose);
      reader.addImages([
        MailInlineImage(
          attachment: byteAttachment(
            partPath: 'remote:https://image.invalid/a',
            mediaType: 'image/png',
          ),
          width: 1,
          height: 1,
        ),
      ]);
      expect(reader.presentation.images, isEmpty);
      expect(
        reader.presentation.bodyText,
        contains('[External image blocked: chart]'),
      );
    },
  );
}
