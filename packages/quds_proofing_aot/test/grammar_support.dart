import 'package:quds_proofing_aot/quds_proofing_aot.dart';

// Source-authored contract fixtures, not recorded live-daemon accuracy data.
final class GrammarWord {
  const GrammarWord(this.text, this.lemma, this.grammar);
  final String text;
  final String lemma;
  final String grammar;
}

const ich = GrammarWord('Ich', 'SIE', 'PRO sin,1,nom,per,;');
const geht = GrammarWord(
  'geht',
  'GEHEN',
  'VER sin,3,prae,; plu,2,prae,; plu,2,imp,;',
);
const der = GrammarWord(
  'Der',
  'DER',
  'ART sin,mas,nom,; sin,fem,dat,; sin,fem,gen,; plu,gen,;',
);
const kleines = GrammarWord(
  'kleines',
  'KLEIN',
  'ADJ sin,neu,nom,sol,ind,; sin,neu,akk,sol,ind,; sin,mas,gen,sol,;',
);
const hund = GrammarWord('Hund', 'HUND', 'SUB mas,sin,nom,akk,dat,;');
const mit = GrammarWord('mit', 'MIT', 'PRP dat,;');
const den = GrammarWord('den', 'DER', 'ART sin,mas,akk,; plu,dat,;');
const punkt = GrammarWord('.', '.', '');

AotAnalysis grammarAnalysis(
  String text,
  List<List<GrammarWord>> clauses, {
  List<List<String>>? alternativeGrammars,
}) => AotAnalysis.fromJson(<Object?>[
  <Object?>[
    for (var clauseIndex = 0; clauseIndex < clauses.length; clauseIndex++)
      <String, Object?>{
        'words': <Object?>[
          for (final word in clauses[clauseIndex])
            <String, Object?>{
              'str': word.text,
              'homonyms': <String>[word.lemma],
            },
        ],
        'variants': <Object?>[
          <String, Object?>{
            'units': <Object?>[
              for (final word in clauses[clauseIndex])
                <String, Object?>{'homNo': 0, 'grm': word.grammar},
            ],
            'groups': <Object?>[],
          },
          if (alternativeGrammars != null)
            <String, Object?>{
              'units': <Object?>[
                for (final grammar in alternativeGrammars[clauseIndex])
                  <String, Object?>{'homNo': 0, 'grm': grammar},
              ],
              'groups': <Object?>[],
            },
        ],
      },
  ],
], text: text);

AotMorphology morphologyFixture(
  String word,
  String lemma,
  String partOfSpeech,
  List<(String, String)> forms, {
  bool found = true,
}) => AotMorphology.fromJson(<Object?>[
  <String, Object?>{
    'found': found,
    'commonGrammems': '',
    'wordForm': lemma,
    'morphInfo': '$partOfSpeech ',
    'wordWeight': 1,
    'homonymWeight': 1,
    'paradigm': <Object?>[
      <String, Object?>{
        'pos': partOfSpeech,
        'formsGroups': <Object?>[
          <String, Object?>{
            'grm': '',
            'forms': <Object?>[
              for (final form in forms)
                <String, Object?>{'f': form.$1, 'grm': form.$2},
            ],
          },
        ],
      },
    ],
  },
], word: word);

AotMorphology standardMorphology(String word) {
  final lower = word.toLowerCase();
  if (const <String>{
    'ich',
    'du',
    'er',
    'wir',
    'ihr',
    'mich',
    'mir',
    'dich',
    'dir',
  }.contains(lower)) {
    return morphologyFixture(word, 'SIE', 'PRO', <(String, String)>[
      ('ICH', 'sin,1,nom,per'),
      ('MICH', 'sin,1,akk,per'),
      ('MIR', 'sin,1,dat,per'),
      ('DU', 'sin,2,nom,per'),
      ('DICH', 'sin,2,akk,per'),
      ('DIR', 'sin,2,dat,per'),
      ('ER', 'sin,3,mas,nom,per'),
      ('WIR', 'plu,1,nom,per'),
      ('IHR', 'plu,2,nom,per'),
    ]);
  }
  if (const <String>{
    'geht',
    'gehe',
    'gehen',
    'gehst',
    'ging',
    'gingst',
    'ginge',
  }.contains(lower)) {
    return morphologyFixture(word, 'GEHEN', 'VER', <(String, String)>[
      ('GEHE', 'sin,1,prae'),
      ('GEHE', 'sin,imp'),
      ('GEHE', 'sin,1,kj1'),
      ('GEHE', 'sin,3,kj1'),
      ('GEHT', 'sin,3,prae'),
      ('GEHT', 'plu,2,prae'),
      ('GEHT', 'plu,2,imp'),
      ('GEHST', 'sin,2,prae'),
      ('GEHEN', 'plu,1,prae'),
      ('GEHEN', 'plu,3,prae'),
      ('GING', 'sin,1,prt'),
      ('GING', 'sin,3,prt'),
      ('GINGST', 'sin,2,prt'),
      ('GINGE', 'sin,1,kj2'),
      ('GINGE', 'sin,3,kj2'),
    ]);
  }
  if (const <String>{
    'der',
    'die',
    'das',
    'den',
    'dem',
    'des',
  }.contains(lower)) {
    return morphologyFixture(word, 'DER', 'ART', <(String, String)>[
      ('DER', 'sin,mas,nom'),
      ('DER', 'sin,fem,dat,gen'),
      ('DER', 'plu,gen'),
      ('DEN', 'sin,mas,akk'),
      ('DEN', 'plu,dat'),
      ('DEM', 'sin,mas,neu,dat'),
      ('DES', 'sin,mas,neu,gen'),
      ('DAS', 'sin,neu,nom,akk'),
      ('DIE', 'sin,fem,nom,akk'),
      ('DIE', 'plu,nom,akk'),
    ]);
  }
  if (const <String>{'ein', 'eine', 'einem', 'einen'}.contains(lower)) {
    return morphologyFixture(word, 'EIN', 'ART', <(String, String)>[
      ('EIN', 'sin,mas,nom'),
      ('EIN', 'sin,neu,nom,akk'),
      ('EINE', 'sin,fem,nom,akk'),
      ('EINEN', 'sin,mas,akk'),
      ('EINEM', 'sin,mas,neu,dat'),
    ]);
  }
  if (const <String>{
    'kleines',
    'kleine',
    'kleiner',
    'kleinen',
  }.contains(lower)) {
    return morphologyFixture(word, 'KLEIN', 'ADJ', <(String, String)>[
      ('KLEINES', 'sin,neu,nom,akk,sol,ind,gru'),
      ('KLEINES', 'sin,mas,gen,sol,gru'),
      ('KLEINE', 'sin,mas,nom,def,gru'),
      ('KLEINE', 'sin,fem,nom,akk,def,ind,gru'),
      ('KLEINER', 'sin,mas,nom,ind,sol,gru'),
      ('KLEINEN', 'sin,mas,akk,dat,gen,def,ind,gru'),
      ('KLEINEN', 'plu,nom,akk,dat,gen,def,gru'),
    ]);
  }
  if (const <String>{'hund', 'hundes', 'hunden', 'hunde'}.contains(lower)) {
    return morphologyFixture(word, 'HUND', 'SUB', <(String, String)>[
      ('HUND', 'mas,sin,nom,akk,dat'),
      ('HUNDES', 'mas,sin,gen'),
      ('HUNDE', 'plu,nom,akk,gen'),
      ('HUNDEN', 'plu,dat'),
    ]);
  }
  return AotMorphology(
    word: word,
    language: AotLanguage.german,
    readings: <AotMorphReading>[],
  );
}

final class GrammarAnalyzer implements AotAnalyzer {
  GrammarAnalyzer({
    required this.analyzeText,
    Future<AotMorphology> Function(String)? morph,
  }) : morph = morph ?? ((word) async => standardMorphology(word));

  final Future<AotAnalysis> Function(String) analyzeText;
  final Future<AotMorphology> Function(String) morph;
  bool disposed = false;
  int analyzeCalls = 0;
  final morphologyCalls = <String>[];

  @override
  Future<AotAnalysis> analyze(
    String text, {
    AotLanguage language = AotLanguage.german,
  }) {
    analyzeCalls++;
    return analyzeText(text);
  }

  @override
  Future<AotMorphology> morphology(
    String word, {
    AotLanguage language = AotLanguage.german,
    bool withParadigms = false,
  }) {
    if (!withParadigms) throw StateError('Grammar must request paradigms.');
    morphologyCalls.add(word);
    return morph(word);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
