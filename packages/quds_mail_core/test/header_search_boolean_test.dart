import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

const _header = MailHeaderSearchDocument(
  subject: 'Quarterly report urgent',
  sender: 'Alice',
  to: 'Bob',
  cc: 'Dana',
);

bool _matches(String query, [MailHeaderSearchDocument header = _header]) =>
    MailHeaderSearchQuery.parse(query).matches(header);

Matcher _error(MailHeaderSearchError code) => isA<MailHeaderSearchException>()
    .having((error) => error.code, 'code', code);

void main() {
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
            _matches('is:read AND is:flagged', header),
            andExpected[row][column],
          );
          expect(
            _matches('is:read is:flagged', header),
            andExpected[row][column],
          );
          expect(
            _matches('is:read OR is:flagged', header),
            orExpected[row][column],
          );
          expect(
            _matches('NOT(is:read AND is:flagged)', header),
            notAndExpected[row][column],
          );
          expect(
            _matches('NOT(is:read OR is:flagged)', header),
            notOrExpected[row][column],
          );
          expect(
            _matches('NOT NOT is:read AND --is:flagged', header),
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
        expect(_matches(query), expected);
      });
    }

    test('missing dates remain unknown through negation and composition', () {
      expect(_matches('NOT on:2026-11-21'), isFalse);
      expect(_matches('NOT before:2026-11-21 OR Alice'), isTrue);
      expect(_matches('NOT after:2026-11-21 AND Alice'), isFalse);
      expect(_matches('NOT (after:2026-11-21 AND missing)'), isTrue);
      expect(_matches('NOT (after:2026-11-21 OR Alice)'), isFalse);
      final dated = MailHeaderSearchDocument(
        subject: '',
        sender: '',
        date: DateTime(2026, 11, 21),
      );
      expect(_matches('NOT on:2026-11-20', dated), isTrue);
      expect(_matches('NOT before:2026-11-21', dated), isTrue);
      expect(_matches('NOT after:2026-11-21', dated), isTrue);
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
          throwsA(_error(MailHeaderSearchError.invalidExpression)),
        );
      });
    }

    test('operand adjacency still requires whitespace', () {
      for (final query in ['a(b)', '(a)b', '(a)(b)', '"a""b"', '(a)NOT b']) {
        expect(
          () => MailHeaderSearchQuery.parse(query),
          throwsA(_error(MailHeaderSearchError.invalidCharacter)),
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
          throwsA(_error(MailHeaderSearchError.unsupportedOperator)),
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
          throwsA(_error(MailHeaderSearchError.missingValue)),
          reason: query,
        );
      }
    });

    test('accepts eight nested groups and refuses the ninth', () {
      expect(_matches('${'(' * 8}Alice${')' * 8}'), isTrue);
      expect(
        () => MailHeaderSearchQuery.parse('${'(' * 9}Alice${')' * 9}'),
        throwsA(_error(MailHeaderSearchError.nestingTooDeep)),
      );
    });

    test('bounds unary work separately from the number of terms', () {
      expect(_matches('${'NOT ' * 32}Alice'), isTrue);
      expect(_matches('${'-' * 32}Alice'), isTrue);
      for (final query in ['${'NOT ' * 33}Alice', '${'-' * 33}Alice']) {
        expect(
          () => MailHeaderSearchQuery.parse(query),
          throwsA(_error(MailHeaderSearchError.invalidExpression)),
        );
      }
      expect(_matches(List.filled(32, 'Alice').join(' ')), isTrue);
      expect(
        () => MailHeaderSearchQuery.parse(List.filled(33, 'Alice').join(' ')),
        throwsA(_error(MailHeaderSearchError.tooManyTerms)),
      );
    });

    test('binary and unary operators share the explicit operator budget', () {
      final limit = '${List.filled(32, 'Alice').join(' OR ')} AND -Alice';
      expect(
        () => MailHeaderSearchQuery.parse(limit),
        throwsA(_error(MailHeaderSearchError.invalidExpression)),
      );
      final accepted = '${List.filled(31, 'Alice').join(' OR ')} AND -Alice';
      expect(_matches(accepted), isTrue);
    });
  });
}
