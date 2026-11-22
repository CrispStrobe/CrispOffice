import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

void main() {
  group('local tags', () {
    test('parse trims, preserves display text and deduplicates by key', () {
      final tags = MailTag.parseAll([' Work ', 'work', 'Receipts', 'travel']);
      expect(tags.map((tag) => tag.name), ['Receipts', 'travel', 'Work']);
      expect(tags[2].key, 'work');
      expect(MailTag.parse('Work'), MailTag.parse('work'));
    });

    test('reject empty, control, unsafe and excessive tags', () {
      for (final value in ['', ' ', 'a\nb', '.hidden', '😀', 'a' * 65]) {
        expect(() => MailTag.parse(value), throwsFormatException);
      }
      expect(
        () => MailTag.parseAll([
          for (var index = 0; index < 33; index++) 'tag$index',
        ]),
        throwsFormatException,
      );
    });
  });

  group('tag search', () {
    final doc = MailHeaderSearchDocument(
      subject: 'Quarterly report',
      sender: 'Alice <alice@example.test>',
      tags: const ['Work', 'Receipts'],
    );

    test('tag: matches a complete tag case-insensitively', () {
      final query = MailHeaderSearchQuery.parse('tag:work');
      expect(query.searchesTags, isTrue);
      expect(query.matches(doc), isTrue);
      expect(MailHeaderSearchQuery.parse('tag:wor').matches(doc), isFalse);
      expect(
        MailHeaderSearchQuery.parse('tag:"Receipts"').matches(doc),
        isTrue,
      );
    });

    test('tag: does not search subjects or senders', () {
      expect(
        MailHeaderSearchQuery.parse('tag:quarterly').matches(doc),
        isFalse,
      );
      expect(MailHeaderSearchQuery.parse('tag:alice').matches(doc), isFalse);
    });

    test('tags combine with Boolean filters', () {
      expect(
        MailHeaderSearchQuery.parse(
          'subject:report AND tag:work AND NOT tag:travel',
        ).matches(doc),
        isTrue,
      );
      expect(
        MailHeaderSearchQuery.parse('tag:work OR tag:travel').matches(doc),
        isTrue,
      );
    });
  });
}
