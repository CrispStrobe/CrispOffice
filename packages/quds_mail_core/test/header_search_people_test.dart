import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

const _incoming = MailHeaderSearchDocument(
  subject: 'Project review',
  sender: 'Alice Example <alice@example.test>',
  to: 'Owner <owner@example.test>',
);

const _sent = MailHeaderSearchDocument(
  subject: 'Project review',
  sender: 'Owner <owner@example.test>',
  to: 'Alice Example <alice@example.test>',
  cc: 'Review Team <team@example.test>',
);

const _copied = MailHeaderSearchDocument(
  subject: 'Project review',
  sender: 'Colleague <colleague@example.test>',
  to: 'Owner <owner@example.test>',
  cc: 'Alice Example <alice@example.test>',
);

const _subjectOnly = MailHeaderSearchDocument(
  subject: 'Alice Example',
  sender: 'Colleague <colleague@example.test>',
  to: 'Owner <owner@example.test>',
);

bool _matches(String query, MailHeaderSearchDocument document) =>
    MailHeaderSearchQuery.parse(query).matches(document);

Matcher _error(MailHeaderSearchError code) =>
    isA<MailHeaderSearchException>().having(
      (error) => error.code,
      'code',
      code,
    );

void main() {
  test('recipient finds To and Cc but excludes sender and subject', () {
    expect(_matches('recipient:alice', _incoming), isFalse);
    expect(_matches('recipient:alice', _sent), isTrue);
    expect(_matches('recipient:alice', _copied), isTrue);
    expect(_matches('recipient:alice', _subjectOnly), isFalse);
  });

  test('participant finds incoming, sent and copied correspondence', () {
    for (final document in [_incoming, _sent, _copied]) {
      expect(_matches('participant:alice', document), isTrue);
      expect(_matches('participant:missing', document), isFalse);
    }
    expect(_matches('participant:alice', _subjectOnly), isFalse);
  });

  test('people fields match names and addresses without case sensitivity', () {
    expect(_matches('ReCiPiEnT:"ALICE EXAMPLE"', _sent), isTrue);
    expect(_matches('recipient:"Review Team"', _sent), isTrue);
    expect(_matches('PARTICIPANT:ALICE@EXAMPLE.TEST', _incoming), isTrue);
    expect(_matches('participant:"Alice Example"', _copied), isTrue);
  });

  test('people fields preserve Unicode names and phrases', () {
    const unicode = MailHeaderSearchDocument(
      subject: '',
      sender: 'ÉMILIE <emilie@example.test>',
      to: 'فريق العمل <team@example.test>',
      cc: 'ÜBERGABE',
    );
    expect(_matches('participant:émilie', unicode), isTrue);
    expect(_matches('recipient:"فريق العمل"', unicode), isTrue);
    expect(_matches('recipient:übergabe', unicode), isTrue);
    expect(_matches('recipient:émilie', unicode), isFalse);
  });

  test('phrases cannot cross distinct header groups', () {
    const split = MailHeaderSearchDocument(
      subject: '',
      sender: 'Alice',
      to: 'Example',
      cc: 'Team',
    );
    expect(_matches('participant:"alice example"', split), isFalse);
    expect(_matches('recipient:"example team"', split), isFalse);
    expect(_matches('participant:alice recipient:example', split), isTrue);
  });

  test('negation excludes matches in every participating header group', () {
    expect(_matches('NOT participant:alice', _incoming), isFalse);
    expect(_matches('NOT participant:alice', _sent), isFalse);
    expect(_matches('-participant:alice', _copied), isFalse);
    expect(_matches('NOT participant:alice', _subjectOnly), isTrue);
    expect(_matches('-recipient:alice', _incoming), isTrue);
    expect(_matches('-recipient:alice', _sent), isFalse);
  });

  test('people fields compose with Boolean groups and other fields', () {
    const query = 'participant:alice NOT recipient:alice subject:project';
    expect(_matches(query, _incoming), isTrue);
    expect(_matches(query, _sent), isFalse);
    expect(_matches(query, _copied), isFalse);
    expect(
      _matches('(recipient:alice OR from:alice) subject:review', _incoming),
      isTrue,
    );
    expect(
      _matches(
        'participant:alice OR recipient:nobody AND subject:missing',
        _sent,
      ),
      isTrue,
    );
  });

  test('unknown flags retain three-valued Boolean behavior', () {
    expect(_matches('participant:alice NOT is:read', _incoming), isFalse);
    expect(_matches('participant:alice OR NOT is:read', _incoming), isTrue);
    expect(_matches('recipient:nobody OR NOT is:read', _incoming), isFalse);
  });

  test('quoted values retain escaped literals and operator words', () {
    const literal = MailHeaderSearchDocument(
      subject: '',
      sender: '',
      to: r'Alice "QA" C:\Mail AND OR NOT',
    );
    expect(_matches(r'recipient:"Alice \"QA\""', literal), isTrue);
    expect(_matches(r'participant:"C:\\Mail"', literal), isTrue);
    expect(_matches('recipient:OR', literal), isTrue);
    expect(_matches('participant:"AND OR NOT"', literal), isTrue);
  });

  test('new fields retain typed validation and term limits', () {
    for (final field in ['recipient', 'participant']) {
      expect(
        () => MailHeaderSearchQuery.parse('$field:'),
        throwsA(_error(MailHeaderSearchError.missingValue)),
      );
      expect(
        () => MailHeaderSearchQuery.parse('$field:""'),
        throwsA(_error(MailHeaderSearchError.emptyTerm)),
      );
      expect(
        () => MailHeaderSearchQuery.parse('$field:ali*'),
        throwsA(_error(MailHeaderSearchError.unsupportedOperator)),
      );
      expect(MailHeaderSearchQuery.parse('$field:alice').termCount, 1);
    }
    final maximum = List.filled(32, 'participant:alice').join(' ');
    expect(MailHeaderSearchQuery.parse(maximum).termCount, 32);
    expect(_matches(maximum, _incoming), isTrue);
    expect(
      () => MailHeaderSearchQuery.parse('$maximum participant:alice'),
      throwsA(_error(MailHeaderSearchError.tooManyTerms)),
    );
  });

  test('bare search and Bcc exclusion keep their existing meaning', () {
    expect(_matches('alice', _incoming), isTrue);
    expect(_matches('alice', _sent), isFalse);
    expect(_matches('alice', _subjectOnly), isTrue);
    expect(
      () => MailHeaderSearchQuery.parse('bcc:alice'),
      throwsA(_error(MailHeaderSearchError.unknownField)),
    );
  });

  test('saved searches accept people fields without widening account scope', () {
    final saved = MailSavedHeaderSearch(
      id: 'alice-correspondence',
      name: 'Alice correspondence',
      query: 'participant:alice NOT recipient:team',
      accountIds: const ['account-a'],
    );
    expect(saved.isValid, isTrue);
    expect(saved.accountIds, ['account-a']);
    expect(saved.query, 'participant:alice NOT recipient:team');
  });
}
