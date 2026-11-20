import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';

import 'fixtures/mail_fixture.dart';

final class _RecordingCodec implements MailCodec {
  MailReadBudget? budget;
  @override
  MailParseResult parse(
    Uint8List bytes, {
    MailReadBudget budget = const MailReadBudget(),
    MailCancellationToken? cancellation,
  }) {
    this.budget = budget;
    return mailFixture(raw: bytes);
  }
}

MailInlineImage _remoteImage(
  String url, {
  Uint8List? bytes,
  String mediaType = 'image/png',
  int width = 1,
  int height = 1,
}) => MailInlineImage(
  attachment: byteAttachment(
    partPath: 'remote:$url',
    mediaType: mediaType,
    bytes: bytes ?? onePixelPng(),
  ),
  width: width,
  height: height,
);

void main() {
  test(
    'full and preview modes pass their actual raw budgets into the codec',
    () {
      final codec = _RecordingCodec();
      final full = MailReaderController.fromBytes(Uint8List(1), codec: codec);
      expect(codec.budget!.maxRawBytes, 32 * 1024 * 1024);
      final preview = MailReaderController.fromBytes(
        Uint8List(1),
        codec: codec,
        mode: MailReaderMode.preview,
      );
      expect(codec.budget!.maxRawBytes, 20 * 1024 * 1024);
      expect(preview.budget.maxRawBytes, 20 * 1024 * 1024);
      full.dispose();
      preview.dispose();
    },
  );

  test(
    'search, selection and decoded copy include displayed headers and body',
    () {
      final controller = MailReaderController(
        result: mailFixture(plainText: 'First agenda. SECOND agenda.'),
      );
      controller.search('AGENDA');
      expect(controller.searchMatches, hasLength(2));
      controller.nextSearchMatch();
      expect(controller.selectedText, 'agenda');
      controller.nextSearchMatch();
      expect(controller.activeSearchMatch, 1);
      controller.nextSearchMatch(backwards: true);
      expect(controller.activeSearchMatch, 0);
      controller.search('Fixture subject', caseSensitive: true);
      expect(controller.searchMatches, hasLength(1));
      controller.selectAll();
      expect(controller.selectedText, contains('First agenda. SECOND agenda.'));
      expect(controller.selectedText, contains('reader@example.invalid'));
      expect(controller.result.original!.bytes, [255, 0, 13, 10, 65]);
      controller.dispose();
    },
  );

  test('selection never splits a surrogate or combined grapheme', () {
    final controller = MailReaderController(
      result: mailFixture(plainText: 'A 👩‍💻 é B'),
    );
    final start = controller.decodedText.indexOf('👩');
    controller.select(
      TextSelection(baseOffset: start + 1, extentOffset: start + 3),
    );
    expect(controller.selectedText, '👩‍💻');
    final accented = controller.decodedText.indexOf('é');
    controller.select(
      TextSelection(baseOffset: accented, extentOffset: accented + 1),
    );
    expect(controller.selectedText, 'é');
    controller.dispose();
  });

  test(
    'match limit is explicit and result replacement clears stale selection',
    () {
      final controller = MailReaderController(
        result: mailFixture(plainText: 'a ' * 1100),
      );
      controller.search('a', caseSensitive: true);
      expect(controller.searchMatches, hasLength(1000));
      expect(controller.searchHasMore, isTrue);
      controller.selectAll();
      final revision = controller.revision;
      controller.replaceResult(mailFixture(plainText: 'new'));
      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.revision, greaterThan(revision));
      expect(controller.selectedText, isEmpty);
      controller.dispose();
    },
  );

  test(
    'switching body alternative preserves raw bytes and invalidates action revision',
    () {
      final result = mailFixture(plainText: 'plain', html: '<b>rich</b>');
      final controller = MailReaderController(result: result);
      final hash = result.original!.sha256;
      controller.setPreferHtml(false);
      expect(controller.decodedText, contains('plain'));
      expect(result.original!.sha256, hash);
      expect(controller.revision, 1);
      controller.dispose();
    },
  );

  test(
    'remote image batches append once and retain immutable source ownership',
    () {
      const a = 'https://images.invalid/a';
      const b = 'https://images.invalid/b';
      final result = mailFixture(
        html: '<img src="$a"><img src="$b">Visible body',
        plainText: 'Plain body',
      );
      final controller = MailReaderController(result: result);
      addTearDown(controller.dispose);
      final originalHash = result.original!.sha256;
      expect(
        controller.addImages([_remoteImage(a, width: 999, height: 999)]),
        1,
      );
      expect(controller.presentation.images.single.width, 1);
      expect(controller.presentation.images.single.height, 1);
      expect(controller.addImages([_remoteImage(b)]), 1);
      expect(
        controller.presentation.images.map(
          (image) => image.attachment.partPath,
        ),
        ['remote:$a', 'remote:$b'],
      );
      final revision = controller.revision;
      expect(controller.addImages([_remoteImage(a)]), 0);
      expect(controller.revision, revision);
      expect(controller.result, same(result));
      expect(result.original!.sha256, originalHash);
      expect(result.message!.attachments, isEmpty);

      controller.setPreferHtml(false);
      expect(controller.presentation.images, isEmpty);
      expect(controller.decodedText, contains('Plain body'));
      controller.setPreferHtml(true);
      expect(controller.presentation.images, hasLength(2));
      expect(
        controller.decodedText,
        isNot(contains('[External image blocked]')),
      );
      controller.replaceResult(mailFixture(html: '<img src="$a">New message'));
      expect(controller.presentation.images, isEmpty);
      expect(controller.decodedText, contains('[External image blocked]'));
    },
  );

  test(
    'image admission resets stale selection and rebuilds exact search offsets',
    () {
      const url = 'https://images.invalid/a';
      final controller = MailReaderController(
        result: mailFixture(html: '<img src="$url">needle'),
      );
      addTearDown(controller.dispose);
      controller.search('needle');
      final oldMatch = controller.searchMatches.single;
      controller.selectAll();
      final oldEnd = controller.selection.end;
      expect(controller.addImages([_remoteImage(url)]), 1);
      expect(controller.decodedText.length, isNot(oldEnd));
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(controller.selectedText, isEmpty);
      expect(controller.searchMatches.single.start, isNot(oldMatch.start));
      expect(
        controller.searchMatches.single.start,
        controller.decodedText.indexOf('needle'),
      );
      controller.nextSearchMatch();
      expect(controller.selectedText, 'needle');
    },
  );

  test(
    'remote image pixels share the cumulative CID budget across batches',
    () {
      const a = 'https://images.invalid/a';
      const b = 'https://images.invalid/b';
      final controller = MailReaderController(
        result: mailFixture(
          html: '<img src="cid:local"><img src="$a"><img src="$b">',
          attachments: [
            byteAttachment(
              cid: 'local',
              mediaType: 'image/png',
              bytes: onePixelPng(),
            ),
          ],
        ),
        budget: const MailReadBudget(maxImagePixels: 2),
      );
      addTearDown(controller.dispose);
      expect(controller.presentation.images, hasLength(1));
      expect(controller.addImages([_remoteImage(a)]), 1);
      final admitted = controller.presentation;
      expect(admitted.images, hasLength(2));
      expect(controller.addImages([_remoteImage(b)]), 0);
      expect(controller.presentation, same(admitted));
    },
  );

  test('remote bytes count both bodies and all original attachments', () {
    const a = 'https://images.invalid/a';
    const b = 'https://images.invalid/b';
    const html = '<img src="$a"><img src="$b">';
    const plain = 'Café';
    final original = byteAttachment(bytes: Uint8List(7));
    final baseBytes = utf8.encode(html).length + utf8.encode(plain).length + 7;
    final controller = MailReaderController(
      result: mailFixture(
        html: html,
        plainText: plain,
        attachments: [original],
      ),
      budget: MailReadBudget(maxDecodedBytes: baseBytes + onePixelPng().length),
    );
    addTearDown(controller.dispose);
    expect(controller.presentation.rejected, isFalse);
    expect(controller.addImages([_remoteImage(a)]), 1);
    final admitted = controller.presentation;
    expect(controller.addImages([_remoteImage(b)]), 0);
    expect(controller.presentation, same(admitted));
  });

  test(
    'remote image count includes attachments that are not displayed images',
    () {
      const a = 'https://images.invalid/a';
      const b = 'https://images.invalid/b';
      final controller = MailReaderController(
        result: mailFixture(
          html: '<img src="$a"><img src="$b">',
          attachments: [byteAttachment()],
        ),
        budget: const MailReadBudget(maxAttachments: 2),
      );
      addTearDown(controller.dispose);
      expect(controller.addImages([_remoteImage(a)]), 1);
      expect(controller.addImages([_remoteImage(b)]), 0);
      expect(controller.presentation.images, hasLength(1));
    },
  );

  test(
    'invalid remote images leave the view unchanged and cannot erase a valid peer',
    () {
      const a = 'https://images.invalid/a';
      const b = 'https://images.invalid/b';
      final bomb = onePixelPng();
      ByteData.sublistView(bomb).setUint32(16, 30000);
      ByteData.sublistView(bomb).setUint32(20, 30000);
      for (final invalid in [
        _remoteImage(b, bytes: bomb),
        _remoteImage(b, bytes: onePixelPng().sublist(0, 35)),
        _remoteImage(b, mediaType: 'image/svg+xml'),
        _remoteImage('https://unrelated.invalid/a'),
      ]) {
        final controller = MailReaderController(
          result: mailFixture(html: '<img src="$a"><img src="$b">'),
        );
        final before = controller.presentation;
        controller.selectAll();
        final selection = controller.selection;
        expect(controller.addImages([invalid]), 0);
        expect(controller.presentation, same(before));
        expect(controller.selection, selection);
        expect(controller.revision, 0);
        expect(controller.addImages([_remoteImage(a), invalid]), 1);
        expect(
          controller.presentation.images.single.attachment.partPath,
          'remote:$a',
        );
        expect(controller.presentation.remoteImageUrls, [Uri.parse(b)]);
        expect(controller.presentation.blockedResourceCount, 1);
        controller.dispose();
      }
    },
  );

  test('per-image attachment limits apply before remote publication', () {
    const url = 'https://images.invalid/a';
    final controller = MailReaderController(
      result: mailFixture(html: '<img src="$url">'),
      budget: MailReadBudget(maxAttachmentBytes: onePixelPng().length - 1),
    );
    addTearDown(controller.dispose);
    final before = controller.presentation;
    expect(controller.addImages([_remoteImage(url)]), 0);
    expect(controller.presentation, same(before));
  });

  test('rejected and disposed readers cannot admit remote images', () {
    const url = 'https://images.invalid/a';
    final rejected = MailReaderController(
      result: mailFixture(html: '<img src="$url">'),
      budget: const MailReadBudget(maxBodyBytes: 1),
    );
    expect(rejected.presentation.rejected, isTrue);
    expect(rejected.addImages([_remoteImage(url)]), 0);
    rejected.dispose();
    final disposed = MailReaderController(
      result: mailFixture(html: '<img src="$url">'),
    )..dispose();
    expect(disposed.addImages([_remoteImage(url)]), 0);
  });
}
