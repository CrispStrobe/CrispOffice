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
}
