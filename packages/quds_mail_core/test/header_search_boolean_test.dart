import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

MailHeaderSearchDocument _header({
  String subject = 'Quarterly report',
  String sender = 'Alice',
  bool? read = false,
  bool? flagged = true,
  DateTime? date,
}) => MailHeaderSearchDocument(
  subject: subject,
  sender: sender,
  to: 'Review Team',
  cc: 'Finance',
  isRead: read,
  isFlagged: flagged,
  date: date,
);

bool _matches(String input, MailHeaderSearchDocument document) =>
    MailHeaderSearchQuery.parse(input).matches(document);

Matcher _error(MailHeaderSearchError code, int offset) =>
    isA<MailHeaderSearchException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.offset, 'offset', offset);

void main() {
  group('Boolean header expressions', () {
    test('OR admits either sender and excludes unrelated rows', () {
      const input = 'from:alice OR from:bob';
      expect(_matches(input, _header()), isTrue);
      expect(_matches(input, _header(sender: 'Bob')), isTrue);
      expect(_matches(input, _header(sender: 'Carol')), isFalse);
    });

    test('explicit and implicit AND preserve cross-field matching', () {
      for (final input in [
        'from:alice subject:report to:team cc:finance is:unread',
        'from:alice AND subject:report AND to:team '
        'AND cc:finance AND is:unread',
      ]) {
        expect(_matches(input, _header()), isTrue);
        expect(_matches(input, _header(read: true)), isFalse);
        expect(_matches(input, _header(sender: 'Bob')), isFalse);
      }
    });

    test('AND binds before OR and parentheses change the result', () {
      final readAlice = _header(read: true);
      const ungrouped = 'from:alice OR from:bob AND is:unread';
      const grouped = '(from:alice OR from:bob) AND is:unread';
      expect(_matches(ungrouped, readAlice), isTrue);
      expect(_matches(grouped, readAlice), isFalse);
      expect(_matches(ungrouped, _header(sender: 'Bob')), isTrue);
      expect(_matches(grouped, _header(sender: 'Bob')), isTrue);
      expect(
        _matches(ungrouped, _header(sender: 'Bob', read: true)),
        isFalse,
      );
    });

    test('implicit AND has the same precedence as explicit AND', () {
      const input = 'from:alice OR from:bob is:unread';
      expect(_matches(input, _header(read: true)), isTrue);
      expect(_matches(input, _header(sender: 'Bob')), isTrue);
      expect(_matches(input, _header(sender: 'Bob', read: true)), isFalse);
    });

    test('NOT binds before both conjunction and disjunction', () {
      const input = 'NOT from:alice AND is:unread OR subject:urgent';
      expect(_matches(input, _header()), isFalse);
      expect(_matches(input, _header(sender: 'Bob')), isTrue);
      expect(_matches(input, _header(sender: 'Bob', read: true)), isFalse);
      expect(
        _matches(input, _header(subject: 'Urgent', read: true)),
        isTrue,
      );
    });

    test('negation applies to a complete group and nests predictably', () {
      for (final input in [
        'NOT (from:alice OR from:bob)',
        '-(from:alice OR from:bob)',
      ]) {
        expect(_matches(input, _header()), isFalse);
        expect(_matches(input, _header(sender: 'Bob')), isFalse);
        expect(_matches(input, _header(sender: 'Carol')), isTrue);
      }
      expect(_matches('NOT NOT from:alice', _header()), isTrue);
      expect(_matches('--from:alice', _header()), isTrue);
      expect(_matches('NOT -from:alice', _header()), isTrue);
      expect(
        _matches('NOT (NOT from:alice OR NOT is:unread)', _header()),
        isTrue,
      );
    });

    test('minus negates phrases and fields, preserving embedded hyphens', () {
      final document = _header(subject: 'Follow-up planning');
      expect(_matches('follow-up -subject:urgent', document), isTrue);
      expect(_matches('-"follow-up planning"', document), isFalse);
      expect(_matches('-is:read', document), isTrue);
      expect(_matches('subject:follow-up', document), isTrue);
    });

    test('groups may touch contents and follow explicit operators', () {
      final document = _header(subject: 'one two');
      for (final input in [
        '(one OR three)',
        'one AND(two OR three)',
        'one (two OR three)',
        'NOT(three OR four)',
        '-(three OR four)',
        '((one) AND (two OR three))',
      ]) {
        expect(_matches(input, document), isTrue, reason: input);
      }
    });

    test('term count counts leaves across groups and unary operators', () {
      final query = MailHeaderSearchQuery.parse(
        'NOT (from:alice OR from:bob) AND -subject:urgent',
      );
      expect(query.termCount, 3);
      expect(query.isEmpty, isFalse);
      expect(query.matches(_header(sender: 'Carol')), isTrue);
      expect(query.matches(_header()), isFalse);
      expect(query.matches(_header(sender: 'Carol')), isTrue);
    });
  });

  group('three-valued observations', () {
    test('AND, OR and NOT preserve the complete nullable flag truth table', () {
      for (final read in <bool?>[null, false, true]) {
        for (final flagged in <bool?>[null, false, true]) {
          final document = _header(read: read, flagged: flagged);
          final bothTrue = read == true && flagged == true;
          final eitherTrue = read == true || flagged == true;
          final bothFalse = read == false && flagged == false;
          final eitherFalse = read == false || flagged == false;
          for (final operands in [
            'is:read AND is:flagged',
            'is:flagged AND is:read',
          ]) {
            expect(_matches(operands, document), bothTrue);
            expect(_matches('NOT ($operands)', document), eitherFalse);
          }
          for (final operands in [
            'is:read OR is:flagged',
            'is:flagged OR is:read',
          ]) {
            expect(_matches(operands, document), eitherTrue);
            expect(_matches('NOT ($operands)', document), bothFalse);
          }
          expect(_matches('NOT is:read', document), read == false);
          expect(_matches('-is:unread', document), read == true);
          expect(_matches('NOT NOT is:read', document), read == true);
          expect(
            _matches('NOT is:read AND NOT is:flagged', document),
            bothFalse,
          );
          expect(
            _matches('NOT is:read OR NOT is:flagged', document),
            eitherFalse,
          );
        }
      }
    });

    test('unknown predicates do not become matches by negation', () {
      final document = _header(read: null, flagged: null);
      for (final input in [
        'NOT is:read',
        '-is:unread',
        'NOT is:flagged',
        '-is:unflagged',
        'NOT (is:read OR is:flagged)',
        'NOT (is:read AND is:flagged)',
        'NOT (is:read OR subject:absent)',
        'NOT (is:read AND subject:report)',
      ]) {
        expect(_matches(input, document), isFalse, reason: input);
      }
      expect(_matches('is:read OR subject:report', document), isTrue);
      expect(_matches('subject:report OR is:read', document), isTrue);
      expect(
        _matches('NOT (is:read AND subject:absent)', document),
        isTrue,
      );
    });

    test('missing date remains unknown through either negation spelling', () {
      final document = _header();
      for (final field in ['before', 'after', 'on']) {
        for (final prefix in ['NOT ', '-', 'NOT NOT ']) {
          final input = '$prefix$field:2026-11-20';
          expect(_matches(input, document), isFalse, reason: input);
        }
      }
      expect(
        _matches('is:unread OR NOT on:2026-11-20', document),
        isTrue,
      );
      expect(
        _matches('is:read OR NOT on:2026-11-20', document),
        isFalse,
      );
      expect(
        _matches('NOT (on:2026-11-20 AND subject:absent)', document),
        isTrue,
      );
    });

    test('observed date negation retains exclusive local-day boundaries', () {
      final document = _header(date: DateTime(2026, 11, 20, 23, 59));
      expect(_matches('NOT before:2026-11-20', document), isTrue);
      expect(_matches('-after:2026-11-20', document), isTrue);
      expect(_matches('NOT on:2026-11-20', document), isFalse);
      expect(
        _matches('(on:2026-11-19 OR on:2026-11-20) is:unread', document),
        isTrue,
      );
    });
  });

  group('literal and legacy compatibility', () {
    test('lowercase words and operator prefixes remain ordinary text', () {
      final document = _header(subject: 'and or not ANDromeda ORange NOTable');
      expect(_matches('and or not', document), isTrue);
      expect(_matches('ANDromeda ORange NOTable', document), isTrue);
      expect(_matches('and or not', _header()), isFalse);
    });

    test('operator words are literal inside fields and quotes', () {
      final document = _header(subject: 'AND OR NOT (draft)', sender: 'NOT');
      expect(_matches('subject:AND subject:OR from:NOT', document), isTrue);
      expect(_matches('"AND" "OR" "NOT" "(draft)"', document), isTrue);
      expect(_matches('subject:"AND OR NOT"', document), isTrue);
      expect(_matches('subject:OR', _header(subject: 'report')), isTrue);
    });

    test('nonempty field values are still adjacent text or quoted phrases', () {
      for (final input in ['from:(alice)', 'from:)', 'from: (alice)']) {
        expect(
          () => MailHeaderSearchQuery.parse(input),
          throwsA(_error(MailHeaderSearchError.missingValue, 5)),
          reason: input,
        );
      }
      expect(_matches('from:OR', _header(sender: 'Morgan')), isTrue);
    });
  });

  group('malformed expressions fail closed', () {
    test('incomplete, doubled and misplaced operators have exact offsets', () {
      const failures = <String, int>{
        'AND one': 0,
        'OR one': 0,
        'one AND': 7,
        'one OR': 6,
        'NOT': 3,
        'NOT ': 4,
        '-': 1,
        '--': 2,
        'one NOT': 7,
        'one AND OR two': 8,
        'one OR AND two': 7,
        'one OR OR two': 7,
        'one AND AND two': 8,
        '(one OR)': 7,
        '(one AND)': 8,
        '(-)': 2,
        '(NOT)': 4,
      };
      for (final entry in failures.entries) {
        expect(
          () => MailHeaderSearchQuery.parse(entry.key),
          throwsA(_error(MailHeaderSearchError.invalidExpression, entry.value)),
          reason: entry.key,
        );
      }
    });

    test('empty and unbalanced groups are errors rather than match-all', () {
      const failures = <String, int>{
        '()': 1,
        '( )': 2,
        '(': 1,
        ')': 0,
        '(one': 4,
        'one)': 3,
        '(one))': 5,
        'one OR ()': 8,
      };
      for (final entry in failures.entries) {
        expect(
          () => MailHeaderSearchQuery.parse(entry.key),
          throwsA(_error(MailHeaderSearchError.invalidExpression, entry.value)),
          reason: entry.key,
        );
      }
    });

    test('adjacent operands cannot silently become implicit AND', () {
      const failures = <String, int>{
        'one(two)': 3,
        '(one)two': 5,
        '(one)(two)': 5,
        '"one"two': 5,
        'one"two"': 3,
        '(one)OR two': 5,
        'subject:"one"two': 13,
      };
      for (final entry in failures.entries) {
        expect(
          () => MailHeaderSearchQuery.parse(entry.key),
          throwsA(_error(MailHeaderSearchError.invalidCharacter, entry.value)),
          reason: entry.key,
        );
      }
    });

    test('matching OR branches cannot hide errors or unknown fields', () {
      expect(
        () => MailHeaderSearchQuery.parse('subject:report OR body:secret'),
        throwsA(_error(MailHeaderSearchError.unknownField, 18)),
      );
      expect(
        () => MailHeaderSearchQuery.parse('subject:report OR ('),
        throwsA(_error(MailHeaderSearchError.invalidExpression, 19)),
      );
    });

    test('new error messages do not disclose query values', () {
      const secret = 'sensitive-recipient@example.test';
      const input = 'from:$secret OR';
      try {
        MailHeaderSearchQuery.parse(input);
        fail('A trailing OR must be rejected.');
      } on MailHeaderSearchException catch (error) {
        expect(error.code, MailHeaderSearchError.invalidExpression);
        expect(error.offset, input.length);
        expect(error.toString(), isNot(contains(secret)));
        expect(error.toString(), isNot(contains('from:')));
      }
    });
  });

  group('bounded Boolean grammar', () {
    test('OR cannot bypass the total 32-leaf budget', () {
      final maximum = List.filled(
        MailHeaderSearchQuery.maxTerms,
        'x',
      ).join(' OR ');
      expect(MailHeaderSearchQuery.parse('($maximum)').termCount, 32);
      final oversized = '$maximum OR x';
      expect(
        () => MailHeaderSearchQuery.parse(oversized),
        throwsA(
          _error(MailHeaderSearchError.tooManyTerms, oversized.length - 1),
        ),
      );
    });

    test('eight nested groups are accepted and a ninth is rejected', () {
      final maximum =
          '${'(' * MailHeaderSearchQuery.maxNestingDepth}'
          'x'
          '${')' * MailHeaderSearchQuery.maxNestingDepth}';
      expect(MailHeaderSearchQuery.parse(maximum).termCount, 1);
      expect(_matches(maximum, _header(subject: 'x')), isTrue);
      expect(
        () => MailHeaderSearchQuery.parse('($maximum)'),
        throwsA(_error(MailHeaderSearchError.nestingTooDeep, 8)),
      );
    });

    test('unary chains are bounded independently of parenthesis nesting', () {
      for (final operator in ['NOT ', '-']) {
        final maximum =
            '${operator * MailHeaderSearchQuery.maxOperators}x';
        expect(_matches(maximum, _header(subject: 'x')), isTrue);
        final oversized = '$operator$maximum';
        expect(
          () => MailHeaderSearchQuery.parse(oversized),
          throwsA(
            _error(
              MailHeaderSearchError.invalidExpression,
              operator.length * MailHeaderSearchQuery.maxOperators,
            ),
          ),
        );
      }
      final bothLimits =
          '${'NOT ' * MailHeaderSearchQuery.maxOperators}'
          '${'(' * MailHeaderSearchQuery.maxNestingDepth}'
          'x'
          '${')' * MailHeaderSearchQuery.maxNestingDepth}';
      expect(_matches(bothLimits, _header(subject: 'x')), isTrue);
    });

    test('binary and unary operators share the explicit-operator budget', () {
      final prefix = 'NOT ' * (MailHeaderSearchQuery.maxOperators - 1);
      final maximum = '${prefix}x OR y';
      expect(MailHeaderSearchQuery.parse(maximum).termCount, 2);
      final oversized = 'NOT $maximum';
      expect(
        () => MailHeaderSearchQuery.parse(oversized),
        throwsA(
          _error(
            MailHeaderSearchError.invalidExpression,
            oversized.indexOf('OR'),
          ),
        ),
      );
    });

    test('the UTF-16 length budget includes all grouping punctuation', () {
      final astral = '😀' * 511;
      final maximum = '($astral)';
      expect(maximum.length, MailHeaderSearchQuery.maxCodeUnits);
      expect(MailHeaderSearchQuery.parse(maximum).termCount, 1);
      expect(
        () => MailHeaderSearchQuery.parse('${maximum}x'),
        throwsA(_error(MailHeaderSearchError.queryTooLong, 1024)),
      );
    });
  });
}
