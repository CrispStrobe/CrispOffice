import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_aot/quds_proofing_aot.dart';
import 'package:test/test.dart';

import 'grammar_support.dart';

Map<String, Object?> _word(
  String text, {
  String grammar = '',
  String? lemma,
  String? sourceText,
  int? start,
  int? end,
}) => <String, Object?>{
  'str': text,
  'homonyms': <String>[lemma ?? text.toUpperCase()],
  '_grammar': grammar,
  'sourceText': ?sourceText,
  'sourceStart': ?start,
  'sourceEnd': ?end,
};

List<Object?> _syntax(List<List<Map<String, Object?>>> clauses) => <Object?>[
  <Object?>[
    for (final words in clauses)
      <String, Object?>{
        'words': words,
        'variants': <Object?>[
          <String, Object?>{
            'units': <Object?>[
              for (final word in words)
                <String, Object?>{'homNo': 0, 'grm': word['_grammar']},
            ],
            'groups': <Object?>[],
          },
        ],
      },
  ],
];

void main() {
  test(
    'verified native merged token preserves source and analyzer surfaces',
    () {
      const text = 'Er versucht zu helfen.';
      final analysis = AotAnalysis.fromJson(
        _syntax([
          [
            _word('Er'),
            _word('versucht'),
            _word('zu-helfen', sourceText: 'zu helfen', start: 12, end: 21),
            _word('.'),
          ],
        ]),
        text: text,
      );
      final token = analysis.tokens.elementAt(2);
      expect(analysis.fullyAligned, isTrue);
      expect(token.text, 'zu helfen');
      expect(token.analysisText, 'zu-helfen');
      expect(token.isNormalized, isTrue);
      expect((token.start, token.end), (12, 21));
      expect(analysis.tokens.last.start, 21);
    },
  );

  test('native positions are verified as UTF-16 after astral characters', () {
    final analysis = AotAnalysis.fromJson(
      _syntax([
        [
          _word('🙂', sourceText: '🙂', start: 0, end: 2),
          _word('Ich', sourceText: 'Ich', start: 3, end: 6),
          _word('gehe', sourceText: 'gehe', start: 7, end: 11),
          _word('.'),
        ],
      ]),
      text: '🙂 Ich gehe.',
    );
    expect(analysis.fullyAligned, isTrue);
    expect(analysis.tokens.elementAt(1).start, 3);
    expect(analysis.tokens.every((word) => !word.isNormalized), isTrue);
  });

  test('HTTP without metadata remains incomplete for rewritten surfaces', () {
    final analysis = AotAnalysis.fromJson(
      _syntax([
        [_word('Er'), _word('versucht'), _word('zu-helfen'), _word('.')],
      ]),
      text: 'Er versucht zu helfen.',
    );
    expect(analysis.fullyAligned, isFalse);
    expect(analysis.tokens.elementAt(2).start, isNull);
    expect(analysis.tokens.last.start, isNull);
  });

  for (final bad in <Map<String, Object?>>[
    _word('Hund', sourceText: 'Hund'),
    _word('Hund', start: 0, end: 4),
    _word('Hund', sourceText: 'Katze', start: 0, end: 4),
    _word('Hund', sourceText: 'Hund', start: -1, end: 3),
    _word('Hund', sourceText: 'Hund', start: 0, end: 99),
    _word('Hund', sourceText: '', start: 0, end: 0),
    <String, Object?>{
      ..._word('Hund', sourceText: 'Hund', start: 0, end: 4),
      // Fractional offsets are invalid on VM and JS; JS cannot distinguish
      // integral numeric representations such as 0 and 0.0.
      'sourceStart': 0.5,
    },
  ].indexed) {
    test('invalid native source evidence ${bad.$1} is rejected', () {
      expect(
        () => AotAnalysis.fromJson(
          _syntax([
            [bad.$2],
          ]),
          text: 'Hund',
        ),
        throwsFormatException,
      );
    });
  }

  test(
    'matching substring cannot conceal an omitted non-whitespace prefix',
    () {
      expect(
        () => AotAnalysis.fromJson(
          _syntax([
            [_word('Hund', sourceText: 'Hund', start: 2, end: 6)],
          ]),
          text: 'X Hund',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'overlapping matching spans cannot create duplicate source ownership',
    () {
      expect(
        () => AotAnalysis.fromJson(
          _syntax([
            [
              _word('Hund', sourceText: 'Hund', start: 0, end: 4),
              _word('Hund', sourceText: 'Hund', start: 0, end: 4),
            ],
          ]),
          text: 'Hund',
        ),
        throwsFormatException,
      );
    },
  );

  test('native metadata cannot split combining or surrogate graphemes', () {
    for (final source in ['u\u0308', '🙂']) {
      expect(
        () => AotAnalysis.fromJson(
          _syntax([
            [_word('x', sourceText: source.substring(0, 1), start: 0, end: 1)],
          ]),
          text: source,
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'native metadata cannot restart alignment after an earlier mismatch',
    () {
      final analysis = AotAnalysis.fromJson(
        _syntax([
          [_word('wrong'), _word('Hund', sourceText: 'Hund', start: 2, end: 6)],
        ]),
        text: 'X Hund',
      );
      expect(analysis.fullyAligned, isFalse);
      expect(analysis.tokens.every((word) => !word.isAligned), isTrue);
    },
  );

  test(
    'normalized rule context abstains while an exact later clause checks',
    () async {
      final analyzer = GrammarAnalyzer(
        analyzeText: (text) async => AotAnalysis.fromJson(
          _syntax([
            [
              _word('Ich', lemma: ich.lemma, grammar: ich.grammar),
              _word(
                'geht',
                lemma: geht.lemma,
                grammar: geht.grammar,
                sourceText: 'GEHT',
                start: 4,
                end: 8,
              ),
              _word('.'),
            ],
            [
              _word('Ich', lemma: ich.lemma, grammar: ich.grammar),
              _word('geht', lemma: geht.lemma, grammar: geht.grammar),
              _word('.'),
            ],
          ]),
          text: text,
        ),
      );
      final provider = AotProofingProvider(analyzer: analyzer);
      addTearDown(provider.dispose);
      final result = await provider.check(
        OfficeProofingRequest(
          documentId: 'native',
          blockId: 'body',
          revision: 1,
          text: 'Ich GEHT. Ich geht.',
          language: 'de-DE',
        ),
      );
      expect(result.status, OfficeProofingStatus.success);
      expect(result.findings, hasLength(1));
      expect(result.findings.single.start, 14);
      expect(result.findings.single.originalText, 'geht');
      expect(result.findings.single.replacements, ['gehe']);
      expect(analyzer.morphologyCalls, isNot(contains('GEHT')));
    },
  );
}
