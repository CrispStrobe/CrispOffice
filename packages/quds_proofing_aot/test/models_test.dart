import 'package:quds_proofing_aot/quds_proofing_aot.dart';
import 'package:test/test.dart';

import 'aot_fixture_data.dart';

void main() {
  group('SynanDaemon syntax contract', () {
    test(
      'preserves clauses, homonyms, variants, grammar and group semantics',
      () {
        final AotAnalysis analysis = AotAnalysis.fromJson(
          syntaxFixture(),
          text: 'Ich gehe nach Hause.',
        );
        final AotClause clause = analysis.sentences.single.clauses.single;
        expect(analysis.fullyAligned, isTrue);
        expect(analysis.tokens.map((AotToken t) => t.start), <int>[
          0,
          4,
          9,
          14,
          19,
        ]);
        expect(analysis.tokens.map((AotToken t) => t.end), <int>[
          3,
          8,
          13,
          19,
          20,
        ]);
        expect(clause.words.first.homonyms.single, 'SIE');
        expect(
          clause.variants.single.units[1].grammar.alternatives,
          <Set<String>>[
            <String>{'sin', '1', 'prae', 'non'},
            <String>{'sin', 'imp', 'non'},
            <String>{'sin', '3', 'kj1', 'non'},
          ],
        );
        final AotGroup phrase = clause.variants.single.groups.last;
        expect(phrase.start, 2);
        expect(phrase.last, 3);
        expect(phrase.isGroup, isTrue);
        expect(phrase.isSubject, isFalse);
        expect(phrase.description, 'pp');
        expect(clause.variants.single.units.last.grammar.partOfSpeech, '');
      },
    );

    test('retains backwards subject-predicate arcs', () {
      final List<Object?> fixture = syntaxFixture();
      final Map<String, Object?> clause =
          (fixture.single! as List<Object?>).single! as Map<String, Object?>;
      final Map<String, Object?> variant =
          (clause['variants']! as List<Object?>).single!
              as Map<String, Object?>;
      final Map<String, Object?> group =
          (variant['groups']! as List<Object?>)[1]! as Map<String, Object?>;
      group['start'] = 1;
      group['last'] = 0;
      final AotAnalysis analysis = AotAnalysis.fromJson(
        fixture,
        text: 'Ich gehe nach Hause.',
      );
      final AotGroup subject =
          analysis.sentences.single.clauses.single.variants.single.groups[1];
      expect(subject.start, 1);
      expect(subject.last, 0);
      expect(subject.isSubject, isTrue);
    });

    test('all nested collections and alternatives are immutable', () {
      final AotAnalysis analysis = AotAnalysis.fromJson(
        syntaxFixture(),
        text: 'Ich gehe nach Hause.',
      );
      final AotClause clause = analysis.sentences.single.clauses.single;
      expect(() => analysis.sentences.clear(), throwsUnsupportedError);
      expect(() => clause.words.clear(), throwsUnsupportedError);
      expect(() => clause.words.first.homonyms.clear(), throwsUnsupportedError);
      expect(() => clause.variants.clear(), throwsUnsupportedError);
      expect(
        () => clause.variants.single.units.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => clause.variants.single.groups.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => clause.variants.single.units.first.grammar.alternatives.first
            .clear(),
        throwsUnsupportedError,
      );
    });

    test('rejects CLI schema, missing fields and wrong scalar types', () {
      for (final Object? invalid in <Object?>[
        <String, Object?>{'sentences': <Object?>[]},
        <Object?>[
          <String, Object?>{'input': 'Hallo', 'result': <Object?>[]},
        ],
        <Object?>[
          <Object?>[
            <String, Object?>{'words': <Object?>[]},
          ],
        ],
        tokensFixture(<List<List<String>>>[
          <List<String>>[
            <String>['Hallo'],
          ],
        ])..add(null),
      ]) {
        expect(
          () => AotAnalysis.fromJson(invalid, text: 'Hallo'),
          throwsFormatException,
        );
      }
    });

    test('rejects invalid homonym/unit/group coordinates', () {
      for (final String field in <String>[
        'homNo',
        'units',
        'start',
        'last',
        'isSubj',
      ]) {
        final List<Object?> fixture = syntaxFixture();
        final Map<String, Object?> clause =
            (fixture.single! as List<Object?>).single! as Map<String, Object?>;
        final Map<String, Object?> variant =
            (clause['variants']! as List<Object?>).single!
                as Map<String, Object?>;
        final List<Object?> units = variant['units']! as List<Object?>;
        final Map<String, Object?> group =
            (variant['groups']! as List<Object?>).last! as Map<String, Object?>;
        switch (field) {
          case 'homNo':
            (units.first! as Map<String, Object?>)['homNo'] = 3;
          case 'units':
            units.removeLast();
          case 'start':
            group['start'] = -1;
          case 'last':
            group['last'] = 99;
          case 'isSubj':
            group['isSubj'] = true; // cannot be group and subject arc
        }
        expect(
          () => AotAnalysis.fromJson(fixture, text: 'Ich gehe nach Hause.'),
          throwsFormatException,
          reason: field,
        );
      }
    });
  });

  group('source alignment', () {
    test(
      'UTF-16, repeated tokens, whitespace and multiple clauses/sentences',
      () {
        const String source = '  Äpfel Äpfel.\n😀 Äpfel.';
        final AotAnalysis analysis = AotAnalysis.fromJson(
          tokensFixture(<List<List<String>>>[
            <List<String>>[
              <String>['Äpfel'],
              <String>['Äpfel', '.'],
            ],
            <List<String>>[
              <String>['😀', 'Äpfel', '.'],
            ],
          ]),
          text: source,
        );
        expect(analysis.fullyAligned, isTrue);
        expect(analysis.tokens.map((AotToken t) => t.start), <int>[
          2,
          8,
          13,
          15,
          18,
          23,
        ]);
        for (final AotToken token in analysis.tokens) {
          expect(source.substring(token.start!, token.end!), token.text);
        }
      },
    );

    test('does not guess a repeated-word position past an omitted token', () {
      final AotAnalysis analysis = AotAnalysis.fromJson(
        tokensFixture(<List<List<String>>>[
          <List<String>>[
            <String>['Ich', 'Ich'],
          ],
        ]),
        text: 'Ich fehlt Ich',
      );
      expect(analysis.tokens.first.start, 0);
      expect(analysis.tokens.last.start, isNull);
      expect(analysis.fullyAligned, isFalse);
    });

    test('normalized tokens stay visible without fabricated ranges', () {
      final AotAnalysis analysis = AotAnalysis.fromJson(
        tokensFixture(<List<List<String>>>[
          <List<String>>[
            <String>['dass', 'das'],
          ],
        ]),
        text: 'daß das',
      );
      expect(analysis.tokens.map((AotToken t) => t.start), <int?>[null, null]);
      expect(analysis.tokens.first.text, 'dass');
      expect(analysis.fullyAligned, isFalse);
    });

    test('never splits a source grapheme for diagnostics', () {
      final AotAnalysis analysis = AotAnalysis.fromJson(
        tokensFixture(<List<List<String>>>[
          <List<String>>[
            <String>['a', '\u0308'],
          ],
        ]),
        text: 'a\u0308',
      );
      expect(analysis.tokens.first.start, isNull);
      expect(analysis.fullyAligned, isFalse);
    });

    test('missing trailing text and empty parse are not fully aligned', () {
      expect(
        AotAnalysis.fromJson(<Object?>[], text: 'Hallo').fullyAligned,
        isFalse,
      );
      expect(
        AotAnalysis.fromJson(<Object?>[], text: ' \n').fullyAligned,
        isTrue,
      );
      expect(
        AotAnalysis.fromJson(
          tokensFixture(<List<List<String>>>[
            <List<String>>[
              <String>['Hallo'],
            ],
          ]),
          text: 'Hallo Welt',
        ).fullyAligned,
        isFalse,
      );
    });
  });

  group('morphology contract', () {
    test(
      'keeps submitted word separate from lemma and inherits form features',
      () {
        final AotMorphology morphology = AotMorphology.fromJson(
          morphologyFixture(),
          word: 'geht',
        );
        final AotMorphReading reading = morphology.readings.single;
        expect(morphology.word, 'geht');
        expect(reading.lemma, 'GEHEN');
        expect(reading.found, isTrue);
        expect(reading.commonGrammems, <String>{'intra', 'non'});
        expect(reading.forms.length, 6);
        expect(reading.forms.first.text, 'GEHE');
        expect(reading.forms.first.grammar.partOfSpeech, 'VER');
        expect(reading.forms.first.grammar.alternatives.single, <String>{
          'non',
          'sin',
          'prae',
          '1',
        });
        expect(reading.forms.last.grammar.features, <String>{
          'non',
          'plu',
          'prae',
          '3',
        });
        expect(() => reading.paradigm.clear(), throwsUnsupportedError);
        expect(
          () => reading.paradigm.single.groups.clear(),
          throwsUnsupportedError,
        );
      },
    );

    test('prediction and absent paradigms remain distinguishable', () {
      final Map<String, Object?> reading =
          morphologyFixture().single! as Map<String, Object?>;
      reading.remove('paradigm');
      reading['found'] = false;
      reading['srcNorm'] = 'GEHEN';
      final AotMorphReading parsed = AotMorphology.fromJson(<Object?>[
        reading,
      ], word: 'gehxyz').readings.single;
      expect(parsed.found, isFalse);
      expect(parsed.sourceNorm, 'GEHEN');
      expect(parsed.forms, isEmpty);
    });

    test('rejects malformed morphology and concrete forms', () {
      final Map<String, Object?> reading =
          morphologyFixture().single! as Map<String, Object?>;
      reading['found'] = 'true';
      expect(
        () => AotMorphology.fromJson(<Object?>[reading], word: 'geht'),
        throwsFormatException,
      );
      expect(
        () => AotMorphology.fromJson(<String, Object?>{}, word: 'geht'),
        throwsFormatException,
      );
    });
  });
}
