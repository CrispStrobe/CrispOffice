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
  _registerIndependentBooleanCases();

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

const _independentHeader = MailHeaderSearchDocument(
  subject: 'Quarterly report urgent',
  sender: 'Alice',
  to: 'Bob',
  cc: 'Dana',
);

bool _independentMatches(String query, [MailHeaderSearchDocument header = _independentHeader]) =>
    MailHeaderSearchQuery.parse(query).matches(header);

Matcher _independentError(MailHeaderSearchError code) => isA<MailHeaderSearchException>()
    .having((error) => error.code, 'code', code);

void _registerIndependentBooleanCases() {
  group('Boolean header search', () {
    // Rows and columns are true, false and unavailable. Only known true matches.
    const states = <bool?>[true, false, null];
    const andExpected = [
      [true, false, false],
      [false, false, false],
      [false, false, false],
    ];
    const orExpected = [
      [true, true, true],
      [true, false, false],
      [true, false, false],
    ];
    const notAndExpected = [
      [false, true, false],
      [true, true, true],
      [false, true, false],
    ];
    const notOrExpected = [
      [false, false, false],
      [false, true, false],
      [false, false, false],
    ];
    for (var row = 0; row < states.length; row++) {
      for (var column = 0; column < states.length; column++) {
        test('observed read=${states[row]}, flagged=${states[column]}', () {
          final header = MailHeaderSearchDocument(
            subject: '',
            sender: '',
            isRead: states[row],
            isFlagged: states[column],
          );
          expect(
            _independentMatches('is:read AND is:flagged', header),
            andExpected[row][column],
          );
          expect(
            _independentMatches('is:read is:flagged', header),
            andExpected[row][column],
          );
          expect(
            _independentMatches('is:read OR is:flagged', header),
            orExpected[row][column],
          );
          expect(
            _independentMatches('NOT(is:read AND is:flagged)', header),
            notAndExpected[row][column],
          );
          expect(
            _independentMatches('NOT(is:read OR is:flagged)', header),
            notOrExpected[row][column],
          );
          expect(
            _independentMatches('NOT NOT is:read AND --is:flagged', header),
            andExpected[row][column],
          );
        });
      }
    }

    for (final (query, expected) in <(String, bool)>[
      ('missing OR Alice urgent', true),
      ('Alice OR missing absent', true),
      ('(Alice OR missing) absent', false),
      ('NOT missing AND urgent OR absent', true),
      ('NOT (Alice OR missing) AND urgent', false),
      ('Alice AND(urgent OR missing)', true),
      ('Alice OR(missing AND urgent)', true),
      ('NOT(NOT(Alice))', true),
      ('-missing', true),
      ('-Alice', false),
      ('--Alice', true),
      ('subject:"quarterly report" AND from:Alice', true),
      ('subject:OR', true),
      ('"OR"', true),
      ('or', true),
      ('from:NOT', false),
    ]) {
      test('precedence, grouping and literal boundary: $query', () {
        expect(_independentMatches(query), expected);
      });
    }

    test('missing dates remain unknown through negation and composition', () {
      expect(_independentMatches('NOT on:2026-11-21'), isFalse);
      expect(_independentMatches('NOT before:2026-11-21 OR Alice'), isTrue);
      expect(_independentMatches('NOT after:2026-11-21 AND Alice'), isFalse);
      expect(_independentMatches('NOT (after:2026-11-21 AND missing)'), isTrue);
      expect(_independentMatches('NOT (after:2026-11-21 OR Alice)'), isFalse);
      final dated = MailHeaderSearchDocument(
        subject: '',
        sender: '',
        date: DateTime(2026, 11, 21),
      );
      expect(_independentMatches('NOT on:2026-11-20', dated), isTrue);
      expect(_independentMatches('NOT before:2026-11-21', dated), isTrue);
      expect(_independentMatches('NOT after:2026-11-21', dated), isTrue);
    });

    test('operators and parentheses do not increase the term count', () {
      final query = MailHeaderSearchQuery.parse(
        'NOT (from:Alice OR subject:"quarterly report") AND -is:read',
      );
      expect(query.termCount, 3);
      expect(query.isEmpty, isFalse);
    });

    for (final query in [
      'AND a',
      'OR a',
      'a OR',
      'a AND',
      'NOT',
      '-',
      'a AND OR b',
      'a OR AND b',
      '(a',
      'a)',
      '()',
      'a OR ()',
      'NOT()',
      '(a OR)',
    ]) {
      test('rejects incomplete Boolean expression: $query', () {
        expect(
          () => MailHeaderSearchQuery.parse(query),
          throwsA(_independentError(MailHeaderSearchError.invalidExpression)),
        );
      });
    }

    test('operand adjacency still requires whitespace', () {
      for (final query in ['a(b)', '(a)b', '(a)(b)', '"a""b"', '(a)NOT b']) {
        expect(
          () => MailHeaderSearchQuery.parse(query),
          throwsA(_independentError(MailHeaderSearchError.invalidCharacter)),
          reason: query,
        );
      }
    });

    test('symbolic operators and wildcard syntax remain unsupported', () {
      for (final query in [
        'a && b',
        'a || b',
        'a*',
        'a?',
        '[a]',
        'subject:a*',
      ]) {
        expect(
          () => MailHeaderSearchQuery.parse(query),
          throwsA(_independentError(MailHeaderSearchError.unsupportedOperator)),
          reason: query,
        );
      }
    });

    test('groups cannot replace adjacent field values', () {
      for (final query in [
        'from:',
        'from:()',
        'subject:(Alice)',
        'from: Alice',
      ]) {
        expect(
          () => MailHeaderSearchQuery.parse(query),
          throwsA(_independentError(MailHeaderSearchError.missingValue)),
          reason: query,
        );
      }
    });

    test('accepts eight nested groups and refuses the ninth', () {
      expect(_independentMatches('${'(' * 8}Alice${')' * 8}'), isTrue);
      expect(
        () => MailHeaderSearchQuery.parse('${'(' * 9}Alice${')' * 9}'),
        throwsA(_independentError(MailHeaderSearchError.nestingTooDeep)),
      );
    });

    test('bounds unary work separately from the number of terms', () {
      expect(_independentMatches('${'NOT ' * 32}Alice'), isTrue);
      expect(_independentMatches('${'-' * 32}Alice'), isTrue);
      for (final query in ['${'NOT ' * 33}Alice', '${'-' * 33}Alice']) {
        expect(
          () => MailHeaderSearchQuery.parse(query),
          throwsA(_independentError(MailHeaderSearchError.invalidExpression)),
        );
      }
      expect(_independentMatches(List.filled(32, 'Alice').join(' ')), isTrue);
      expect(
        () => MailHeaderSearchQuery.parse(List.filled(33, 'Alice').join(' ')),
        throwsA(_independentError(MailHeaderSearchError.tooManyTerms)),
      );
    });

    test('binary and unary operators share the explicit operator budget', () {
      final limit = '${List.filled(32, 'Alice').join(' OR ')} AND -Alice';
      expect(
        () => MailHeaderSearchQuery.parse(limit),
        throwsA(_independentError(MailHeaderSearchError.invalidExpression)),
      );
      final accepted = '${List.filled(31, 'Alice').join(' OR ')} AND -Alice';
      expect(_independentMatches(accepted), isTrue);
    });
  });
}