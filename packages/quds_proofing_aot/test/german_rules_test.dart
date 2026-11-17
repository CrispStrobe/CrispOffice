import 'package:quds_proofing_aot/quds_proofing_aot.dart';
import 'package:test/test.dart';

import 'grammar_support.dart';

Future<List<AotGermanDiagnostic>> check(
  String text,
  List<List<GrammarWord>> clauses, {
  List<List<String>>? alternatives,
  AotMorphology Function(String)? morph,
}) => const AotGermanGrammar().check(
  grammarAnalysis(text, clauses, alternativeGrammars: alternatives),
  morphology: (word) async => (morph ?? standardMorphology)(word),
  protected: (_, _) => false,
);

void main() {
  test(
    'personal pronoun agreement uses source features, not SIE lemma',
    () async {
      final results = await check('Ich geht.', <List<GrammarWord>>[
        <GrammarWord>[ich, geht, punkt],
      ]);
      expect(results.single.ruleId, AotGermanGrammar.subjectVerbRule);
      expect(results.single.start, 4);
      expect(results.single.end, 8);
      expect(results.single.replacements, <String>['gehe']);
    },
  );

  test('subject correction preserves past tense', () async {
    final results = await check('Du ging.', <List<GrammarWord>>[
      <GrammarWord>[
        const GrammarWord('Du', 'SIE', 'PRO sin,2,nom,per,;'),
        const GrammarWord('ging', 'GEHEN', 'VER sin,1,prt,; sin,3,prt,;'),
        punkt,
      ],
    ]);
    expect(results.single.replacements, <String>['gingst']);
  });

  test(
    'does not turn imperative readings into errors without finite evidence',
    () async {
      expect(
        await check('Ihr geht!', <List<GrammarWord>>[
          <GrammarWord>[
            const GrammarWord('Ihr', 'SIE', 'PRO plu,2,nom,per,;'),
            const GrammarWord('geht', 'GEHEN', 'VER plu,2,imp,;'),
            const GrammarWord('!', '!', ''),
          ],
        ]),
        isEmpty,
      );
    },
  );

  test('every valid syntax variant is respected', () async {
    final result = await check(
      'Ich gehe.',
      <List<GrammarWord>>[
        <GrammarWord>[
          ich,
          const GrammarWord('gehe', 'GEHEN', 'VER sin,3,kj1,;'),
          punkt,
        ],
      ],
      alternatives: <List<String>>[
        <String>['PRO sin,1,nom,per,;', 'VER sin,1,prae,;', ''],
      ],
    );
    expect(result, isEmpty);
  });

  test('morphology restores valid alternatives pruned by syntax', () async {
    expect(
      await check('Ich gehe.', <List<GrammarWord>>[
        <GrammarWord>[
          ich,
          const GrammarWord('gehe', 'GEHEN', 'VER sin,3,kj1,;'),
          punkt,
        ],
      ]),
      isEmpty,
    );
  });

  for (final control in <({String text, List<GrammarWord> words})>[
    (
      text: 'Ich gehe.',
      words: <GrammarWord>[
        ich,
        const GrammarWord('gehe', 'GEHEN', 'VER sin,1,prae,; sin,3,kj1,;'),
        punkt,
      ],
    ),
    (
      text: 'Ich ginge.',
      words: <GrammarWord>[
        ich,
        const GrammarWord('ginge', 'GEHEN', 'VER sin,1,kj2,; sin,3,kj2,;'),
        punkt,
      ],
    ),
    (
      text: 'Ihr geht.',
      words: <GrammarWord>[
        const GrammarWord('Ihr', 'SIE', 'PRO plu,2,nom,per,;'),
        geht,
        punkt,
      ],
    ),
    (
      text: 'Sie geht.',
      words: <GrammarWord>[
        const GrammarWord(
          'Sie',
          'SIE',
          'PRO sin,3,fem,nom,per,; plu,3,nom,per,;',
        ),
        geht,
        punkt,
      ],
    ),
    (
      text: 'Er und ich geht.',
      words: <GrammarWord>[
        const GrammarWord('Er', 'SIE', 'PRO sin,3,mas,nom,per,;'),
        const GrammarWord('und', 'UND', 'KON'),
        const GrammarWord('ich', 'SIE', 'PRO sin,1,nom,per,;'),
        geht,
        punkt,
      ],
    ),
    (
      text: 'Geht heim!',
      words: <GrammarWord>[
        const GrammarWord('Geht', 'GEHEN', 'VER plu,2,imp,;'),
        const GrammarWord('heim', 'HEIM', 'ADV'),
        const GrammarWord('!', '!', ''),
      ],
    ),
    (
      text: '„Ich“ geht.',
      words: <GrammarWord>[
        const GrammarWord('„', '„', ''),
        ich,
        const GrammarWord('“', '“', ''),
        geht,
        punkt,
      ],
    ),
    (
      text: 'Ich, geht.',
      words: <GrammarWord>[ich, const GrammarWord(',', ',', ''), geht, punkt],
    ),
    (text: 'Ich\ngeht.', words: <GrammarWord>[ich, geht, punkt]),
  ]) {
    test(
      'abstains on clean or structurally ambiguous ${control.text}',
      () async {
        expect(
          await check(control.text, <List<GrammarWord>>[control.words]),
          isEmpty,
        );
      },
    );
  }

  test('fixed preposition checks article and noun together', () async {
    final results = await check('mit den Hund', <List<GrammarWord>>[
      <GrammarWord>[mit, den, hund],
    ]);
    expect(results.single.ruleId, AotGermanGrammar.prepositionRule);
    expect(results.single.replacements, <String>['dem']);
    expect(results.single.start, 4);
    expect(results.single.end, 7);
  });

  test('keeps valid dative plural alternative for den', () async {
    expect(
      await check('mit den Hunden', <List<GrammarWord>>[
        <GrammarWord>[
          mit,
          den,
          const GrammarWord('Hunden', 'HUND', 'SUB plu,dat,;'),
        ],
      ]),
      isEmpty,
    );
  });

  test('fixed-case pronoun correction retains person and number', () async {
    final results = await check('mit mich', <List<GrammarWord>>[
      <GrammarWord>[
        mit,
        const GrammarWord('mich', 'SIE', 'PRO sin,1,akk,per,;'),
      ],
    ]);
    expect(results.single.replacements, <String>['mir']);
  });

  test('valid fixed-case pronoun is unchanged', () async {
    expect(
      await check('mit dir', <List<GrammarWord>>[
        <GrammarWord>[
          mit,
          const GrammarWord('dir', 'SIE', 'PRO sin,2,dat,per,;'),
        ],
      ]),
      isEmpty,
    );
  });

  test('noun case correction uses the original lexeme paradigm', () async {
    final result = await check('mit dem Hundes', <List<GrammarWord>>[
      <GrammarWord>[
        mit,
        const GrammarWord('dem', 'DER', 'ART sin,mas,neu,dat,;'),
        const GrammarWord('Hundes', 'HUND', 'SUB mas,sin,gen,;'),
      ],
    ]);
    expect(result.single.start, 8);
    expect(result.single.replacements, <String>['Hund']);
  });

  for (final prep in <String>[
    'in',
    'an',
    'wegen',
    'trotz',
    'entlang',
    'nach',
  ]) {
    test(
      'does not impose a fixed case for omitted preposition $prep',
      () async {
        expect(
          await check('$prep den Hund', <List<GrammarWord>>[
            <GrammarWord>[
              GrammarWord(prep, prep.toUpperCase(), 'PRP dat,akk,;'),
              den,
              hund,
            ],
          ]),
          isEmpty,
        );
      },
    );
  }

  test('does not diagnose across coordination after a noun phrase', () async {
    expect(
      await check('mit den Hund und mir', <List<GrammarWord>>[
        <GrammarWord>[
          mit,
          den,
          hund,
          const GrammarWord('und', 'UND', 'KON'),
          const GrammarWord('mir', 'SIE', 'PRO sin,1,dat,per,;'),
        ],
      ]),
      isEmpty,
    );
  });

  test('definite article requires weak adjective declension', () async {
    final results = await check('Der kleines Hund.', <List<GrammarWord>>[
      <GrammarWord>[der, kleines, hund, punkt],
    ]);
    expect(results.single.ruleId, AotGermanGrammar.adjectiveRule);
    expect(results.single.replacements, <String>['kleine']);
  });

  test('indefinite article preserves mixed adjective declension', () async {
    final results = await check('ein kleines Hund', <List<GrammarWord>>[
      <GrammarWord>[
        const GrammarWord('ein', 'EIN', 'ART sin,mas,nom,; sin,neu,nom,akk,;'),
        kleines,
        hund,
      ],
    ]);
    expect(results.single.replacements, <String>['kleiner']);
  });

  test('valid weak adjective and ambiguous article remain unchanged', () async {
    expect(
      await check('Der kleine Hund.', <List<GrammarWord>>[
        <GrammarWord>[
          der,
          const GrammarWord(
            'kleine',
            'KLEIN',
            'ADJ sin,mas,nom,def,; sin,fem,nom,akk,def,;',
          ),
          hund,
          punkt,
        ],
      ]),
      isEmpty,
    );
  });

  test('predicted words and missing paradigms cannot prove errors', () async {
    for (final predicted in <bool>[true, false]) {
      final result = await check(
        'Ich geht.',
        <List<GrammarWord>>[
          <GrammarWord>[ich, geht, punkt],
        ],
        morph: (word) => word == 'geht'
            ? morphologyFixture(
                word,
                'GEHEN',
                'VER',
                predicted
                    ? <(String, String)>[
                        ('GEHT', 'sin,3,prae'),
                        ('GEHE', 'sin,1,prae'),
                      ]
                    : <(String, String)>[],
                found: !predicted,
              )
            : standardMorphology(word),
      );
      expect(result, isEmpty);
    }
  });

  test('never flags a missing syntax group as an error', () async {
    final results = await check('Hund.', <List<GrammarWord>>[
      <GrammarWord>[hund, punkt],
    ]);
    expect(results, isEmpty);
  });

  test(
    'unknown features and mixed POS alternatives cause abstention',
    () async {
      for (final grammar in <String>['VER sin,prae,;', 'SUB sin,mas,nom,;']) {
        expect(
          await check('Ich geht.', <List<GrammarWord>>[
            <GrammarWord>[ich, GrammarWord('geht', 'GEHEN', grammar), punkt],
          ]),
          isEmpty,
        );
      }
    },
  );

  test('uppercase source retains uppercase correction', () async {
    final results = await check('ICH GEHT.', <List<GrammarWord>>[
      <GrammarWord>[
        const GrammarWord('ICH', 'SIE', 'PRO sin,1,nom,per,;'),
        const GrammarWord('GEHT', 'GEHEN', 'VER sin,3,prae,;'),
        punkt,
      ],
    ]);
    expect(results.single.replacements, <String>['GEHE']);
  });
}
