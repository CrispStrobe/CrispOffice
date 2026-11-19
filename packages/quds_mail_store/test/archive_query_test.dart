import 'package:quds_mail_store/src/archive_query.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('archive query grammar and limits', () {
    test('blank search compiles to all archived rows', () {
      for (final input in ['', ' ', '\t\r\n']) {
        final query = MailArchiveQuery.parse(input);
        expect(query.isEmpty, isTrue);
        expect(query.termCount, 0);
        expect(query.predicateSql, '1');
        expect(query.parameters, isEmpty);
      }
    });

    test('query arguments are immutable and never copied into SQL', () {
      const sentinel = 'PRIVATE_MESSAGE_SENTINEL';
      final query = MailArchiveQuery.parse('subject:$sentinel OR -bcc:secret');
      expect(query.predicateSql, isNot(contains(sentinel)));
      expect(query.parameters.first, contains(sentinel));
      expect(query.parameters, hasLength(2));
      expect(query.termCount, 2);
      expect(() => query.parameters.add('extra'), throwsUnsupportedError);
    });

    test('uppercase operators differ from lowercase literal terms', () {
      final query = MailArchiveQuery.parse('and or not');
      expect(query.parameters, ['"and"', '"or"', '"not"']);
      expect(query.termCount, 3);
    });

    test('field aliases map only to the declared archive index columns', () {
      for (final (alias, column) in const [
        ('subject', 'subject'),
        ('from', 'sender'),
        ('to', 'recipients_to'),
        ('cc', 'recipients_cc'),
        ('bcc', 'recipients_bcc'),
        ('bcontent', 'body'),
        ('acontent', 'attachment_text'),
        ('attachment', 'attachment_names'),
      ]) {
        final query = MailArchiveQuery.parse('${alias.toUpperCase()}:value');
        expect(query.parameters, ['$column : "value"']);
      }
    });

    test('escaped quotes and backslashes remain bound FTS literals', () {
      final query = MailArchiveQuery.parse(r'"say \"hello\" C:\\mail"');
      expect(query.parameters, ['"say ""hello"" C:\\mail"']);
    });

    test('prefix asterisk is outside the safely quoted FTS literal', () {
      final query = MailArchiveQuery.parse('subject:invo*');
      expect(query.parameters, ['subject : "invo"*']);
    });

    test('exact length and term limits are accepted', () {
      final query = MailArchiveQuery.parse(
        'one two',
        maxCodeUnits: 7,
        maxTerms: 2,
      );
      expect(query.termCount, 2);
    });

    test('one excess UTF-16 code unit has a bounded typed error', () {
      _error('one two', MailArchiveQueryError.queryTooLong, 6, maxCodeUnits: 6);
    });

    test('one excess term is rejected before SQL execution', () {
      _error('one two', MailArchiveQueryError.tooManyTerms, 4, maxTerms: 1);
    });

    test(
      'negation, parentheses and alternative nesting share a depth budget',
      () {
        expect(MailArchiveQuery.parse('(one)', maxDepth: 1).termCount, 1);
        expect(MailArchiveQuery.parse('[one]', maxDepth: 1).termCount, 1);
        expect(MailArchiveQuery.parse('-one', maxDepth: 1).termCount, 1);
        _error('((one))', MailArchiveQueryError.tooDeep, 2, maxDepth: 1);
        _error('[[one]]', MailArchiveQueryError.tooDeep, 2, maxDepth: 1);
        _error('--one', MailArchiveQueryError.tooDeep, 2, maxDepth: 1);
      },
    );

    test('invalid or unbounded caller limits fail safely', () {
      for (final call in <void Function()>[
        () => MailArchiveQuery.parse('one', maxCodeUnits: 0),
        () => MailArchiveQuery.parse('one', maxCodeUnits: 65537),
        () => MailArchiveQuery.parse('one', maxTerms: 0),
        () => MailArchiveQuery.parse('one', maxTerms: 257),
        () => MailArchiveQuery.parse('one', maxDepth: 0),
        () => MailArchiveQuery.parse('one', maxDepth: 33),
      ]) {
        expect(
          call,
          throwsA(
            isA<MailArchiveQueryException>().having(
              (error) => error.code,
              'code',
              MailArchiveQueryError.invalidLimits,
            ),
          ),
        );
      }
    });

    final rejected = <(String, MailArchiveQueryError, int)>[
      ('unknown:value', MailArchiveQueryError.unknownField, 0),
      ('subject:', MailArchiveQueryError.missingValue, 8),
      ('subject:(one)', MailArchiveQueryError.missingValue, 8),
      ('subject:OR', MailArchiveQueryError.missingValue, 8),
      ('"unclosed', MailArchiveQueryError.unclosedQuote, 0),
      ('(one', MailArchiveQueryError.unclosedGroup, 0),
      ('[one two', MailArchiveQueryError.unclosedGroup, 0),
      ('one)', MailArchiveQueryError.unexpectedToken, 3),
      ('one]', MailArchiveQueryError.unexpectedToken, 3),
      ('OR one', MailArchiveQueryError.unexpectedToken, 0),
      ('one OR', MailArchiveQueryError.unexpectedToken, 6),
      ('one AND', MailArchiveQueryError.unexpectedToken, 7),
      ('one AND OR two', MailArchiveQueryError.unexpectedToken, 8),
      ('[one AND two]', MailArchiveQueryError.unexpectedToken, 5),
      ('[]', MailArchiveQueryError.unexpectedToken, 1),
      ('()', MailArchiveQueryError.unexpectedToken, 1),
      ('-', MailArchiveQueryError.unexpectedToken, 1),
      ('one"two"', MailArchiveQueryError.unexpectedToken, 3),
      ('(one)(two)', MailArchiveQueryError.unexpectedToken, 5),
      ('"one"*', MailArchiveQueryError.unexpectedToken, 5),
      ('*one', MailArchiveQueryError.unsupportedWildcard, 0),
      ('on*e', MailArchiveQueryError.unsupportedWildcard, 0),
      ('one**', MailArchiveQueryError.unsupportedWildcard, 0),
      ('on?e', MailArchiveQueryError.unsupportedWildcard, 0),
      ('"one* two"', MailArchiveQueryError.unsupportedWildcard, 0),
      ('"one? two"', MailArchiveQueryError.unsupportedWildcard, 0),
      ('*', MailArchiveQueryError.emptyTerm, 0),
      ('""', MailArchiveQueryError.emptyTerm, 0),
      ('"   "', MailArchiveQueryError.emptyTerm, 0),
      ('!!!', MailArchiveQueryError.emptyTerm, 0),
      ('_', MailArchiveQueryError.emptyTerm, 0),
      (r'"one\ntwo"', MailArchiveQueryError.invalidEscape, 4),
      ('one\u0000two', MailArchiveQueryError.invalidCharacter, 3),
      ('"one\u0000two"', MailArchiveQueryError.invalidCharacter, 4),
      ('one\u007ftwo', MailArchiveQueryError.invalidCharacter, 3),
    ];
    for (var index = 0; index < rejected.length; index++) {
      final (input, code, offset) = rejected[index];
      test('invalid syntax case ${index + 1} returns $code', () {
        _error(input, code, offset);
      });
    }

    test('errors never reveal query contents through their diagnostic', () {
      const sentinel = 'PRIVATE_MAIL_QUERY_TOKEN';
      try {
        MailArchiveQuery.parse('$sentinel:secret');
        fail('Expected an unknown-field error.');
      } on MailArchiveQueryException catch (error) {
        expect(error.code, MailArchiveQueryError.unknownField);
        expect(error.toString(), isNot(contains(sentinel)));
        expect(error.toString(), isNot(contains('secret')));
      }
    });
  });

  group('archive query against real SQLite FTS5', () {
    late Database database;

    setUp(() {
      database = sqlite3.openInMemory();
      database.execute('CREATE TABLE archive_items(id TEXT PRIMARY KEY)');
      database.execute(
        'CREATE VIRTUAL TABLE archive_fts USING fts5('
        'id UNINDEXED, subject, sender, recipients_to, recipients_cc, '
        'recipients_bcc, body, attachment_names, attachment_text)',
      );
      for (final values in _messages) {
        database.execute('INSERT INTO archive_items VALUES (?)', [values[0]]);
        database.execute(
          'INSERT INTO archive_fts VALUES (?,?,?,?,?,?,?,?,?)',
          values,
        );
      }
    });

    tearDown(() => database.close());

    List<String> search(String input) {
      final query = MailArchiveQuery.parse(input);
      return database
          .select(
            'SELECT a.id FROM archive_items a '
            'WHERE ${query.predicateSql} ORDER BY a.id',
            query.parameters,
          )
          .map((row) => row['id'] as String)
          .toList();
    }

    final matches = <(String, List<String>)>[
      ('', ['a', 'b', 'c', 'd', 'e']),
      ('invoice', ['a', 'c']),
      ('subject:invoice', ['a']),
      ('SUBJECT:invoice', ['a']),
      ('from:alice', ['a']),
      ('to:alice', ['b']),
      ('cc:finance', ['a']),
      ('bcc:hidden', ['a']),
      ('bcc:hidden2', ['c']),
      ('bcontent:invoice', ['c']),
      ('acontent:confidential', ['a']),
      ('attachment:report.txt', ['b']),
      ('attachment:confidential', []),
      ('acontent:report.txt', []),
      ('from:"alice@example.test"', ['a']),
      ('subject:"quarterly invoice"', ['a']),
      ('"quick brown fox"', ['b']),
      ('quick fox', ['b', 'c']),
      ('quick AND fox', ['b', 'c']),
      ('subject:invo*', ['a']),
      ('bcontent:pay*', ['a']),
      ('-invoice', ['b', 'd', 'e']),
      ('NOT invoice', ['b', 'd', 'e']),
      ('-bcc:hidden', ['b', 'c', 'd', 'e']),
      ('invoice -subject:invoice', ['c']),
      ('subject:invoice OR subject:Support', ['a', 'c']),
      ('subject:invoice OR subject:Support bcontent:absent', ['a']),
      ('(subject:invoice OR subject:Support) bcontent:absent', []),
      ('-[subject:invoice subject:Support]', ['b', 'd', 'e']),
      ('[subject:invoice subject:Support]', ['a', 'c']),
      ('[subject:invoice OR subject:Support] -bcontent:overdue', ['a']),
      ('[(Project alpha) (quick brown)]', ['a', 'b']),
      ('NOT (invoice OR forecast)', ['d', 'e']),
      ('--invoice', ['a', 'c']),
      ('cafe resume', ['a']),
      ('"OR"', ['a']),
      ('or', ['a']),
      ('subject:العقد', ['e']),
      ('bcontent:الفاتورة', ['e']),
      ('attachment:اتفاق', ['e']),
      ('acontent:العربية', ['e']),
      (r'"say \"hello\""', ['a']),
      ('"invoice OR subject:Support"', []),
      (r'"x\"\" OR 1=1 --"', []),
    ];
    for (var index = 0; index < matches.length; index++) {
      final (query, expected) = matches[index];
      test('semantic search case ${index + 1}: $query', () {
        expect(search(query), expected);
      });
    }

    test(
      'field conditions cannot broaden a separately bound archive filter',
      () {
        final query = MailArchiveQuery.parse('invoice OR -invoice');
        final rows = database.select(
          'SELECT a.id FROM archive_items a WHERE (${query.predicateSql}) '
          'AND a.id=?',
          [...query.parameters, 'b'],
        );
        expect(rows.map((row) => row['id']), ['b']);
      },
    );

    test(
      'quoted SQL punctuation cannot execute statements or broaden results',
      () {
        expect(search(r'"x\"; DROP TABLE archive_items; --"'), isEmpty);
        expect(
          database.select('SELECT count(*) AS n FROM archive_items')[0]['n'],
          5,
        );
        expect(search('invoice'), ['a', 'c']);
      },
    );

    test(
      'all accepted adversarial tokens execute without FTS grammar errors',
      () {
        const punctuation = [
          'a-b',
          'a.b',
          'a@b',
          "a'b",
          r'a\b',
          'a/b',
          'a+b',
          'a^b',
          'a{b}',
          'a,b',
          'a;b',
          'a=b',
          'a~b',
          'a!b',
          'a|b',
          'a&b',
        ];
        for (final token in punctuation) {
          expect(search(token), isEmpty, reason: token);
          expect(search('$token*'), isEmpty, reason: '$token*');
        }
      },
    );
  });
}

void _error(
  String input,
  MailArchiveQueryError code,
  int offset, {
  int maxCodeUnits = 1024,
  int maxTerms = 32,
  int maxDepth = 8,
}) {
  expect(
    () => MailArchiveQuery.parse(
      input,
      maxCodeUnits: maxCodeUnits,
      maxTerms: maxTerms,
      maxDepth: maxDepth,
    ),
    throwsA(
      isA<MailArchiveQueryException>()
          .having((error) => error.code, 'code', code)
          .having((error) => error.offset, 'offset', offset),
    ),
  );
}

const _messages = <List<String>>[
  [
    'a',
    'Quarterly invoice',
    'Alice <alice@example.test>',
    'Bob <bob@example.test>',
    'finance@example.test',
    'hidden@example.test',
    'Project alpha payment due, say "hello". OR literal. Café résumé',
    'invoice.pdf',
    'Total confidential invoice',
  ],
  [
    'b',
    'Project update',
    'Bob <bob@example.test>',
    'Alice <alice@example.test>',
    'team@example.test',
    '',
    'Project beta second note quick brown fox',
    'report.txt',
    'forecast zebra',
  ],
  [
    'c',
    'Support request',
    'Carol <carol@example.test>',
    'support@example.test',
    '',
    'hidden2@example.test',
    'quick red fox urgently invoice overdue',
    '',
    '',
  ],
  ['d', 'Empty body', 'sender@example.test', '', '', '', '', 'broken.pdf', ''],
  [
    'e',
    'العقد الجديد',
    'ليلى <layla@example.test>',
    '',
    '',
    '',
    'الفاتورة الجديدة',
    'اتفاق.txt',
    'التسليم العربية',
  ],
];
