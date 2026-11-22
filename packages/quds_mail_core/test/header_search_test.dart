import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

const _header = MailHeaderSearchDocument(
  subject: 'Quarterly report for Project North',
  sender: 'Alice Example <alice@example.test>',
  to: 'Review Team <team@example.test>',
  cc: 'Finance <finance@example.test>',
  isRead: false,
  isFlagged: true,
);

bool _matches(String query, [MailHeaderSearchDocument header = _header]) =>
    MailHeaderSearchQuery.parse(query).matches(header);

Matcher _error(MailHeaderSearchError code, {int? offset}) {
  final matcher = isA<MailHeaderSearchException>().having(
    (error) => error.code,
    'code',
    code,
  );
  return offset == null
      ? matcher
      : matcher.having((error) => error.offset, 'offset', offset);
}

void main() {
  group('retained body matching', () {
    const withBody = MailHeaderSearchDocument(
      subject: 'Delivery',
      sender: 'Alice <alice@example.test>',
      body: 'Your parcel is at the delivery address.',
    );

    test('body: searches only retained plain text', () {
      final query = MailHeaderSearchQuery.parse('body:parcel');
      expect(query.searchesBody, isTrue);
      expect(query.matches(withBody), isTrue);
      expect(
        query.matches(
          const MailHeaderSearchDocument(
            subject: 'Parcel subject',
            sender: 'parcel@example.test',
          ),
        ),
        isFalse,
      );
    });

    test('an unqualified term does not search the body', () {
      final query = MailHeaderSearchQuery.parse('parcel');
      expect(query.searchesBody, isFalse);
      expect(query.matches(withBody), isFalse);
      expect(
        query.matches(
          const MailHeaderSearchDocument(
            subject: 'Parcel subject',
            sender: 'alice@example.test',
          ),
        ),
        isTrue,
      );
    });

    test('body phrases and Boolean expressions stay bounded', () {
      final query = MailHeaderSearchQuery.parse(
        'body:"delivery address" AND NOT body:returned',
      );
      expect(query.searchesBody, isTrue);
      expect(query.matches(withBody), isTrue);
      expect(
        query.matches(
          const MailHeaderSearchDocument(
            subject: '',
            sender: '',
            body: 'Delivery address: returned to sender.',
          ),
        ),
        isFalse,
      );
    });
  });

  group('loaded header matching', () {
    test(
      'empty and whitespace queries match without inventing observations',
      () {
        const unknown = MailHeaderSearchDocument(subject: '', sender: '');
        for (final input in ['', ' \t\n\r', '\u00a0\u2003\u3000']) {
          final query = MailHeaderSearchQuery.parse(input);
          expect(query.isEmpty, isTrue);
          expect(query.termCount, 0);
          expect(query.matches(unknown), isTrue);
        }
        expect(unknown.to, '');
        expect(unknown.cc, '');
        expect(unknown.date, isNull);
        expect(unknown.isRead, isNull);
        expect(unknown.isFlagged, isNull);
      },
    );

    test('unqualified terms search only subject and sender', () {
      expect(_matches('quarterly'), isTrue);
      expect(_matches('example.test'), isTrue);
      expect(_matches('review'), isFalse);
      expect(_matches('finance'), isFalse);
      expect(_matches('not-present'), isFalse);
    });

    test('all terms must match and may match different visible headers', () {
      final query = MailHeaderSearchQuery.parse('north alice quarterly');
      expect(query.isEmpty, isFalse);
      expect(query.termCount, 3);
      expect(query.matches(_header), isTrue);
      expect(_matches('north bob'), isFalse);
      expect(_matches('north\t\nalice'), isTrue);
      expect(_matches('north\u2003alice'), isTrue);
    });

    test('phrases preserve order and whitespace inside a substring', () {
      expect(_matches('"report for"'), isTrue);
      expect(_matches('"for report"'), isFalse);
      expect(_matches('"report  for"'), isFalse);
      expect(_matches('"Project North" alice'), isTrue);
    });

    test('field names and text are case-insensitive Unicode substrings', () {
      const unicode = MailHeaderSearchDocument(
        subject: 'ÜBERGABE für فريق العمل 😀',
        sender: 'ÉMILIE <emilie@example.test>',
      );
      expect(_matches('SuBjEcT:übergabe FrOm:émilie', unicode), isTrue);
      expect(_matches('subject:"فريق العمل" 😀', unicode), isTrue);
      expect(_matches('subject:"😀"', unicode), isTrue);
      expect(_matches('subject:EMILIE', unicode), isFalse);
    });

    test('each address group is searched independently', () {
      expect(_matches('from:alice subject:north to:team cc:finance'), isTrue);
      expect(_matches('from:team'), isFalse);
      expect(_matches('to:alice'), isFalse);
      expect(_matches('cc:team'), isFalse);
      expect(_matches('subject:alice'), isFalse);
      expect(_matches('TO:"Review Team" CC:FINANCE'), isTrue);
    });

    test('quoted values decode only escaped quote and backslash', () {
      const escaped = MailHeaderSearchDocument(
        subject: r'Plan "A" in C:\notes',
        sender: '',
      );
      expect(_matches(r'subject:"Plan \"A\""', escaped), isTrue);
      expect(_matches(r'"C:\\notes"', escaped), isTrue);
    });

    test('quoted literals allow reserved punctuation and operator words', () {
      const literal = MailHeaderSearchDocument(
        subject: 'Re: A*B? (C) [D] -E F|G H&I AND OR NOT',
        sender: '',
      );
      expect(_matches('"Re:" "A*B?" "(C)" "[D]" "-E"', literal), isTrue);
      expect(_matches('"F|G" "H&I" "AND" "OR" "NOT"', literal), isTrue);
      expect(_matches('subject:Re: subject:OR', literal), isTrue);
      expect(_matches('and or not', literal), isTrue);
    });

    test('a compiled query can be reused against independent rows', () {
      final query = MailHeaderSearchQuery.parse('subject:north from:alice');
      expect(query.matches(_header), isTrue);
      expect(
        query.matches(
          const MailHeaderSearchDocument(subject: 'South', sender: 'Alice'),
        ),
        isFalse,
      );
      expect(query.matches(_header), isTrue);
      expect(query.termCount, 2);
    });
  });

  group('observed flag predicates', () {
    test('every read/flag truth-table state preserves unknown values', () {
      for (final read in <bool?>[null, false, true]) {
        for (final flagged in <bool?>[null, false, true]) {
          final header = MailHeaderSearchDocument(
            subject: '',
            sender: '',
            isRead: read,
            isFlagged: flagged,
          );
          expect(_matches('is:read', header), read == true);
          expect(_matches('is:unread', header), read == false);
          expect(_matches('is:flagged', header), flagged == true);
          expect(_matches('is:unflagged', header), flagged == false);
          expect(
            _matches('is:unread is:flagged', header),
            read == false && flagged == true,
          );
        }
      }
    });

    test('states are case-insensitive and contradictory states match none', () {
      expect(_matches('IS:UNREAD is:FLAGGED'), isTrue);
      expect(_matches('is:read is:unread'), isFalse);
      expect(_matches('is:flagged is:unflagged'), isFalse);
      expect(_matches('is:"unread"'), isTrue);
    });
  });

  group('local calendar dates', () {
    MailHeaderSearchDocument dated(DateTime? date) =>
        MailHeaderSearchDocument(subject: '', sender: '', date: date);

    test('before and after are exclusive of the complete named day', () {
      for (final date in [
        DateTime(2026, 11, 20),
        DateTime(2026, 11, 20, 12, 34, 56),
        DateTime(2026, 11, 20, 23, 59, 59, 999),
      ]) {
        final header = dated(date);
        expect(_matches('on:2026-11-20', header), isTrue);
        expect(_matches('before:2026-11-20', header), isFalse);
        expect(_matches('after:2026-11-20', header), isFalse);
        expect(_matches('after:2026-11-19 before:2026-11-21', header), isTrue);
      }
    });

    test('UTC instants use the same local day as their display date', () {
      final displayed = DateTime(2026, 11, 20, 0, 1);
      expect(_matches('on:2026-11-20', dated(displayed.toUtc())), isTrue);
      final late = DateTime(2026, 11, 20, 23, 59);
      expect(_matches('on:2026-11-20', dated(late.toUtc())), isTrue);
    });

    test(
      'explicit-offset input is converted before comparing calendar days',
      () {
        final instant = DateTime.parse('2026-11-20T23:30:00-12:00');
        final local = instant.toLocal();
        final expected =
            '${local.year.toString().padLeft(4, '0')}-'
            '${local.month.toString().padLeft(2, '0')}-'
            '${local.day.toString().padLeft(2, '0')}';
        expect(_matches('on:$expected', dated(instant)), isTrue);
        expect(_matches('before:$expected', dated(instant)), isFalse);
        expect(_matches('after:$expected', dated(instant)), isFalse);
      },
    );

    test('missing dates match no date predicate', () {
      for (final field in ['before', 'after', 'on']) {
        expect(_matches('$field:2026-11-20', dated(null)), isFalse);
      }
    });

    test('valid leap days and four-digit edge years are accepted', () {
      expect(_matches('on:2024-02-29', dated(DateTime(2024, 2, 29))), isTrue);
      expect(_matches('on:2000-02-29', dated(DateTime(2000, 2, 29))), isTrue);
      expect(_matches('on:0001-01-01', dated(DateTime(1))), isTrue);
      expect(_matches('on:9999-12-31', dated(DateTime(9999, 12, 31))), isTrue);
    });

    test('normalized, ambiguous and invalid date values are rejected', () {
      for (final value in [
        '2026-02-29',
        '1900-02-29',
        '2026-04-31',
        '2026-00-10',
        '2026-13-10',
        '2026-11-00',
        '2026-11-32',
        '0000-01-01',
        '10000-01-01',
        '26-11-20',
        '2026-1-20',
        '2026/11/20',
        '2026-11-20T00:00:00Z',
        '２０２６-１１-２０',
        'tomorrow',
      ]) {
        expect(
          () => MailHeaderSearchQuery.parse('on:$value'),
          throwsA(_error(MailHeaderSearchError.invalidDate, offset: 3)),
          reason: value,
        );
      }
    });
  });

  group('bounded and explicit grammar', () {
    test('accepts exactly the code-unit budget and rejects one more', () {
      final maximum = 'x' * MailHeaderSearchQuery.maxCodeUnits;
      expect(MailHeaderSearchQuery.parse(maximum).termCount, 1);
      expect(
        () => MailHeaderSearchQuery.parse('${maximum}x'),
        throwsA(_error(MailHeaderSearchError.queryTooLong, offset: 1024)),
      );
      final astral = '😀' * 512;
      expect(astral.length, 1024);
      expect(MailHeaderSearchQuery.parse(astral).termCount, 1);
      expect(
        () => MailHeaderSearchQuery.parse('${astral}x'),
        throwsA(_error(MailHeaderSearchError.queryTooLong)),
      );
    });

    test('accepts exactly 32 terms, including trailing whitespace', () {
      final maximum = List.filled(
        MailHeaderSearchQuery.maxTerms,
        'x',
      ).join(' ');
      expect(MailHeaderSearchQuery.parse('$maximum \t').termCount, 32);
      expect(
        () => MailHeaderSearchQuery.parse('$maximum x'),
        throwsA(_error(MailHeaderSearchError.tooManyTerms, offset: 64)),
      );
    });

    test('unknown fields cannot become silent literal searches', () {
      for (final field in ['bcc', 'has', 'attachment', 'sender', 'wat']) {
        expect(
          () => MailHeaderSearchQuery.parse('$field:value'),
          throwsA(_error(MailHeaderSearchError.unknownField, offset: 0)),
        );
      }
    });

    test('fields require an adjacent nonempty value', () {
      expect(
        () => MailHeaderSearchQuery.parse('from:'),
        throwsA(_error(MailHeaderSearchError.missingValue, offset: 5)),
      );
      expect(
        () => MailHeaderSearchQuery.parse('from: alice'),
        throwsA(_error(MailHeaderSearchError.missingValue, offset: 5)),
      );
      for (final query in ['""', '" "', 'subject:""', ':value']) {
        expect(
          () => MailHeaderSearchQuery.parse(query),
          throwsA(_error(MailHeaderSearchError.emptyTerm)),
        );
      }
    });

    test('unsupported symbolic operators and wildcards are explicit', () {
      for (final query in [
        '[one two]',
        'from:ali*',
        'subject:r?port',
        'one || two',
        'one&&two',
      ]) {
        expect(
          () => MailHeaderSearchQuery.parse(query),
          throwsA(_error(MailHeaderSearchError.unsupportedOperator)),
          reason: query,
        );
      }
    });

    test('invalid states have a typed failure at the value offset', () {
      for (final state in ['unknown', 'true', 'false', 'notread', '']) {
        expect(
          () => MailHeaderSearchQuery.parse('is:$state'),
          throwsA(
            _error(
              state.isEmpty
                  ? MailHeaderSearchError.missingValue
                  : MailHeaderSearchError.invalidState,
              offset: 3,
            ),
          ),
        );
      }
    });

    test('quotes cannot be concatenated with bare terms or field keys', () {
      for (final query in ['"one"two', 'one"two"', '"from":alice']) {
        expect(
          () => MailHeaderSearchQuery.parse(query),
          throwsA(_error(MailHeaderSearchError.invalidCharacter)),
        );
      }
      expect(
        () => MailHeaderSearchQuery.parse('subject:"private phrase'),
        throwsA(_error(MailHeaderSearchError.unclosedQuote, offset: 8)),
      );
    });

    test('unsupported and incomplete escapes are rejected', () {
      for (final query in [r'"a\nb"', r'"a\tb"', r'a\b', '"a\\']) {
        expect(
          () => MailHeaderSearchQuery.parse(query),
          throwsA(_error(MailHeaderSearchError.invalidEscape)),
        );
      }
    });

    test('control characters cannot hide in bare or quoted values', () {
      for (final control in ['\x00', '\x01', '\x0b', '\x7f', '\x85']) {
        expect(
          () => MailHeaderSearchQuery.parse('a${control}b'),
          throwsA(_error(MailHeaderSearchError.invalidCharacter, offset: 1)),
        );
        expect(
          () => MailHeaderSearchQuery.parse('"a${control}b"'),
          throwsA(_error(MailHeaderSearchError.invalidCharacter, offset: 2)),
        );
      }
      expect(
        () => MailHeaderSearchQuery.parse('"a\nb"'),
        throwsA(_error(MailHeaderSearchError.invalidCharacter)),
      );
    });

    test('exception strings omit query and message content', () {
      const secret = 'sensitive-recipient@example.test';
      try {
        MailHeaderSearchQuery.parse('bcc:$secret');
        fail('Unknown fields must be refused.');
      } on MailHeaderSearchException catch (error) {
        expect(error.toString(), contains('unknownField'));
        expect(error.toString(), contains('offset=0'));
        expect(error.toString(), isNot(contains(secret)));
        expect(error.toString(), isNot(contains('bcc:')));
      }
    });
  });
}
