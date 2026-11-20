import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'fixtures/mail_fixture.dart';

MailInlineImage _image(String id) => MailInlineImage(
  attachment: byteAttachment(
    partPath: 'remote:https://images.example.test/$id.png',
    mediaType: 'image/png',
    bytes: onePixelPng(),
  ),
  width: 1,
  height: 1,
);

void main() {
  test('appending images consumes each input once and keeps prior images', () {
    final controller = MailReaderController(
      result: mailFixture(
        html:
            '<img src="https://images.example.test/one.png">needle'
            '<img src="https://images.example.test/two.png">',
      ),
    );
    final original = controller.result.original!.sha256;
    controller.search('needle');
    final oldOffset = controller.searchMatches.single.start;
    controller.selectAll();
    var iterations = 0;
    Iterable<MailInlineImage> once() sync* {
      iterations++;
      expect(iterations, 1);
      yield _image('one');
    }

    controller.addImages(once());
    expect(iterations, 1);
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selectedText, isEmpty);
    expect(controller.searchMatches.single.start, isNot(oldOffset));
    expect(
      controller.searchMatches.single.start,
      controller.decodedText.indexOf('needle'),
    );
    controller.nextSearchMatch();
    expect(controller.selectedText, 'needle');
    controller.addImages([_image('two')]);
    expect(controller.presentation.images, hasLength(2));
    expect(controller.result.original!.sha256, original);
    expect(controller.revision, 2);
    controller.dispose();
  });

  test('only successfully loaded URI placeholders disappear', () {
    final controller = MailReaderController(
      result: mailFixture(
        html:
            '<img src="https://images.example.test/one.png" alt="Loaded">'
            '<img src="https://images.example.test/two.png" alt="Unavailable">'
            '<img src="data:image/svg+xml,blocked" alt="Blocked">',
      ),
    );
    controller.addImages([_image('one')]);
    expect(
      controller.decodedText,
      isNot(contains('[External image blocked: Loaded]')),
    );
    expect(
      controller.decodedText,
      contains('[External image blocked: Unavailable]'),
    );
    expect(
      controller.decodedText,
      contains('[External image blocked: Blocked]'),
    );
    expect(controller.presentation.blockedResourceCount, 2);
    controller.dispose();
  });

  test(
    'plain mode cannot admit remote images and mode changes retain HTML images',
    () {
      final controller = MailReaderController(
        result: mailFixture(
          plainText: 'plain',
          html:
              '<img src="cid:local"><img src="https://images.example.test/one.png" alt="Remote">',
          attachments: [
            byteAttachment(
              cid: 'local',
              mediaType: 'image/png',
              bytes: onePixelPng(),
            ),
          ],
        ),
        budget: const MailReadBudget(maxImagePixels: 2),
        preferHtml: false,
      );
      expect(controller.addImages([_image('one')]), 0);
      expect(controller.presentation.images, isEmpty);
      controller.setPreferHtml(true);
      expect(
        controller.presentation.images.single.attachment.contentId,
        'local',
      );
      expect(controller.addImages([_image('one')]), 1);
      expect(controller.presentation.images, hasLength(2));
      controller.setPreferHtml(false);
      expect(controller.presentation.images, isEmpty);
      controller.setPreferHtml(true);
      expect(controller.presentation.images, hasLength(2));
      controller.replaceResult(mailFixture(plainText: 'replacement'));
      expect(controller.presentation.images, isEmpty);
      controller.dispose();
      expect(controller.addImages([_image('two')]), 0);
      expect(controller.presentation.images, isEmpty);
    },
  );

  test('a local image can exhaust the shared budget before a remote action', () {
    final controller = MailReaderController(
      result: mailFixture(
        html:
            '<img src="cid:local"><img src="https://images.example.test/one.png" alt="Remote">',
        attachments: [
          byteAttachment(
            cid: 'local',
            mediaType: 'image/png',
            bytes: onePixelPng(),
          ),
        ],
      ),
      budget: const MailReadBudget(maxImagePixels: 1),
    );
    addTearDown(controller.dispose);
    expect(controller.addImages([_image('one')]), 0);
    expect(controller.presentation.images.single.attachment.contentId, 'local');
    expect(
      controller.decodedText,
      contains('[External image blocked: Remote]'),
    );
  });

  test(
    'external image admission preserves count, pixels and format limits',
    () {
      final controller = MailReaderController(
        result: mailFixture(
          html:
              '<img src="https://images.example.test/one.png">'
              '<img src="https://images.example.test/two.png">bounded',
        ),
        budget: const MailReadBudget(maxImagePixels: 1, maxAttachments: 1),
      );
      controller.addImages([
        MailInlineImage(attachment: byteAttachment(), width: 1, height: 1),
        _image('one'),
        _image('one'),
        _image('two'),
      ]);
      expect(controller.presentation.images, hasLength(1));
      expect(
        controller.presentation.images.single.attachment.partPath,
        endsWith('/one.png'),
      );
      controller.dispose();
    },
  );

  test('rejected source cannot become an image-bearing success', () {
    final controller = MailReaderController(
      result: mailFixture(plainText: 'bounded'),
      budget: const MailReadBudget(maxRenderTextBytes: 1),
    );
    expect(controller.presentation.rejected, isTrue);
    controller.addImages([_image('one')]);
    expect(controller.presentation.rejected, isTrue);
    expect(controller.presentation.images, isEmpty);
    expect(controller.revision, 0);
    controller.dispose();
  });

  test(
    'HTML spacing preserves inline word boundaries and preformatted text',
    () {
      final presentation = buildMailBodyPresentation(
        const MailBody(
          html:
              '<div><b>One</b> \n <i>two</i>  three</div>'
              '<div>four&nbsp;five</div><pre> A\n  B </pre>',
        ),
      );
      expect(
        presentation.text,
        contains('One two three\nfour\u00a0five\n A\n  B '),
      );
      expect(presentation.text, isNot(contains('One  two')));
    },
  );

  test('remote candidates come only from inert image nodes and remain bounded', () {
    final presentation = buildMailPresentation(
      mailFixture(
        html:
            '<script src="https://script.example.test/a"></script>'
            '<iframe src="https://frame.example.test/a"><img src="https://hidden.example.test/a"></iframe>'
            '<img src="https://user:password@images.example.test/private">'
            '<img src="&#104;ttps://images.example.test/one.png">'
            '<img src="https://images.example.test/one.png">'
            '${[for (var i = 0; i < 12; i++) '<img src="https://images.example.test/$i.png">'].join()}',
      ),
    );
    expect(presentation.remoteImageUrls, hasLength(8));
    expect(
      presentation.remoteImageUrls.first.toString(),
      'https://images.example.test/one.png',
    );
    expect(
      presentation.remoteImageUrls.every(
        (uri) => uri.host == 'images.example.test' && uri.userInfo.isEmpty,
      ),
      isTrue,
    );
    expect(() => presentation.remoteImageUrls.clear(), throwsUnsupportedError);
    expect(presentation.images, isEmpty);
  });
}
