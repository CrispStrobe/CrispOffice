import 'models.dart';

/// A bounded, independently authored diagnostic derived from positive AOT
/// morphology. Source coordinates are UTF-16 offsets in [AotAnalysis.text].
final class AotGermanDiagnostic {
  AotGermanDiagnostic({
    required this.start,
    required this.end,
    required this.ruleId,
    required this.message,
    required List<String> replacements,
  }) : replacements = List<String>.unmodifiable(replacements);

  final int start;
  final int end;
  final String ruleId;
  final String message;
  final List<String> replacements;
}

/// Conservative German agreement checks. Missing syntax groups, alternative
/// parses, unknown words and absent morphology are never grammatical errors.
/// Every emitted correction is a recognized form from the same AOT paradigm.
final class AotGermanGrammar {
  const AotGermanGrammar();

  static const subjectVerbRule = 'aot.de.subject-verb-agreement';
  static const prepositionRule = 'aot.de.preposition-case';
  static const adjectiveRule = 'aot.de.adjective-agreement';

  Future<List<AotGermanDiagnostic>> check(
    AotAnalysis analysis, {
    required Future<AotMorphology> Function(String) morphology,
    required bool Function(int start, int end) protected,
    Set<String> ignoredRuleIds = const <String>{},
    bool Function()? isCurrent,
  }) async {
    final diagnostics = <AotGermanDiagnostic>[];
    void checkCurrent() {
      if (isCurrent != null && !isCurrent()) {
        throw StateError('AOT grammar check was superseded or cancelled.');
      }
    }

    Future<_Lexeme?> lexeme(AotToken token, List<_Reading> syntax) async {
      checkCurrent();
      final value = await morphology(token.text);
      checkCurrent();
      if (value.word != token.text || value.language != AotLanguage.german) {
        throw const FormatException(
          'AOT returned morphology for another word.',
        );
      }
      final expected = <String>{for (final item in syntax) item.lemma};
      final actual = <String>{};
      final forms = <_Form>[];
      for (final item in value.readings) {
        final lemma = item.lemma.toUpperCase();
        if (!expected.contains(lemma)) continue;
        // Predicted/unknown homonyms cannot prove an error, even if another
        // reading happened to be found in the dictionary.
        if (!item.found) return null;
        actual.add(lemma);
        for (final form in item.forms) {
          for (final features in form.grammar.alternatives) {
            forms.add(
              _Form(
                form.text,
                _Reading(lemma, form.grammar.partOfSpeech, features),
              ),
            );
          }
        }
      }
      if (!actual.containsAll(expected)) return null;
      final source = <_Reading>[
        for (final form in forms)
          if (form.text.toLowerCase() == token.text.toLowerCase()) form.reading,
      ];
      return source.isEmpty ? null : _Lexeme(source, forms);
    }

    bool safe(List<AotToken> words) {
      if (words.any((word) => word.start == null || word.end == null)) {
        return false;
      }
      for (var i = 1; i < words.length; i++) {
        if (words[i - 1].end! > words[i].start! ||
            !_horizontal.hasMatch(
              analysis.text.substring(words[i - 1].end!, words[i].start!),
            )) {
          return false;
        }
      }
      return !protected(words.first.start!, words.last.end!);
    }

    void add(
      AotToken token,
      String rule,
      String message,
      Iterable<String> forms,
    ) {
      final replacements = <String>{
        for (final form in forms)
          if (_word.hasMatch(form)) _caseLike(token.text, form),
      }..remove(token.text);
      if (replacements.isEmpty || replacements.length > 6) return;
      if (diagnostics.any(
        (item) => item.start < token.end! && token.start! < item.end,
      )) {
        return;
      }
      diagnostics.add(
        AotGermanDiagnostic(
          start: token.start!,
          end: token.end!,
          ruleId: rule,
          message: message,
          replacements: replacements.toList()..sort(),
        ),
      );
    }

    for (final sentence in analysis.sentences) {
      for (final clause in sentence.clauses) {
        checkCurrent();
        final words = clause.words;
        if (!ignoredRuleIds.contains(subjectVerbRule) && words.length >= 2) {
          // Restrict the first rule to a clause-initial personal pronoun. An
          // adjacent pronoun inside a coordinated subject is not the subject.
          final expected = _subjects[words.first.text.toLowerCase()];
          final subject = _syntax(clause, 0, const <String>{'PRO'});
          final verb = _syntax(clause, 1, const <String>{'VER'});
          if (expected != null &&
              subject != null &&
              verb != null &&
              safe(words.take(2).toList()) &&
              _subjectEvidence(subject, expected) &&
              _finite(verb).isNotEmpty &&
              !_finite(verb).any((item) => _verbAgrees(item, expected))) {
            final subjectMorph = await lexeme(words[0], subject);
            final verbMorph = await lexeme(words[1], verb);
            if (subjectMorph != null && verbMorph != null) {
              final subjects = subjectMorph.source
                  .where((item) => item.pos == 'PRO')
                  .toList();
              final finite = _finite(verbMorph.source);
              if (_subjectEvidence(subjects, expected) &&
                  finite.isNotEmpty &&
                  !finite.any((item) => _verbAgrees(item, expected))) {
                add(
                  words[1],
                  subjectVerbRule,
                  'Die Verbform passt nicht zu diesem Personalpronomen.',
                  <String>[
                    for (final form in verbMorph.forms)
                      if (_isFinite(form.reading) &&
                          _verbAgrees(form.reading, expected) &&
                          finite.any(
                            (original) =>
                                original.lemma == form.reading.lemma &&
                                _intersects(
                                  original.features,
                                  form.reading.features,
                                  _finiteModes,
                                ),
                          ))
                        form.text,
                  ],
                );
              }
            }
          }
        }

        if (!ignoredRuleIds.contains(prepositionRule)) {
          for (var i = 0; i + 1 < words.length; i++) {
            final requiredCase = _prepositions[words[i].text.toLowerCase()];
            if (requiredCase == null ||
                _syntax(clause, i, const <String>{'PRP'}) == null) {
              continue;
            }
            final pronoun = _syntax(clause, i + 1, const <String>{'PRO'});
            if (pronoun != null &&
                safe(words.sublist(i, i + 2)) &&
                !_coordinatedAfter(words, i + 1) &&
                _personalCaseEvidence(pronoun) &&
                !pronoun.any((item) => item.features.contains(requiredCase))) {
              final morph = await lexeme(words[i + 1], pronoun);
              if (morph != null) {
                final source = morph.source
                    .where((item) => item.pos == 'PRO')
                    .toList();
                if (_personalCaseEvidence(source) &&
                    !source.any(
                      (item) => item.features.contains(requiredCase),
                    )) {
                  final candidates = <String>{
                    for (final form in morph.forms)
                      if (form.reading.pos == 'PRO' &&
                          form.reading.features.contains(requiredCase) &&
                          source.any(
                            (original) =>
                                original.lemma == form.reading.lemma &&
                                _samePersonalIdentity(original, form.reading),
                          ))
                        form.text.toLowerCase(),
                  };
                  // AOT's personal-pronoun paradigm spans several persons
                  // and genders. Abstain if the intended object stays unclear.
                  if (candidates.length == 1) {
                    add(
                      words[i + 1],
                      prepositionRule,
                      _caseMessage(requiredCase),
                      candidates,
                    );
                  }
                }
              }
              continue;
            }
            if (i + 2 >= words.length ||
                !safe(words.sublist(i, i + 3)) ||
                _coordinatedAfter(words, i + 2)) {
              continue;
            }
            final article = _syntax(clause, i + 1, const <String>{'ART'});
            final noun = _syntax(clause, i + 2, const <String>{'SUB'});
            if (article == null ||
                noun == null ||
                !_nominalsComplete(article) ||
                !_nominalsComplete(noun) ||
                _anyAgreement(article, noun, requiredCase: requiredCase)) {
              continue;
            }
            final articleMorph = await lexeme(words[i + 1], article);
            final nounMorph = await lexeme(words[i + 2], noun);
            if (articleMorph == null || nounMorph == null) continue;
            final articles = articleMorph.source
                .where((item) => item.pos == 'ART')
                .toList();
            final nouns = nounMorph.source
                .where((item) => item.pos == 'SUB')
                .toList();
            if (!_nominalsComplete(articles) ||
                !_nominalsComplete(nouns) ||
                _anyAgreement(articles, nouns, requiredCase: requiredCase)) {
              continue;
            }
            if (nouns.any((item) => item.features.contains(requiredCase))) {
              add(
                words[i + 1],
                prepositionRule,
                _caseMessage(requiredCase),
                <String>[
                  for (final form in articleMorph.forms)
                    if (form.reading.pos == 'ART' &&
                        nouns.any(
                          (noun) => _nominalAgreement(
                            form.reading,
                            noun,
                            requiredCase: requiredCase,
                          ),
                        ))
                      form.text,
                ],
              );
            } else if (articles.any(
              (item) => item.features.contains(requiredCase),
            )) {
              add(
                words[i + 2],
                prepositionRule,
                _caseMessage(requiredCase),
                <String>[
                  for (final form in nounMorph.forms)
                    if (form.reading.pos == 'SUB' &&
                        articles.any(
                          (article) => _nominalAgreement(
                            article,
                            form.reading,
                            requiredCase: requiredCase,
                          ),
                        ))
                      form.text,
                ],
              );
            }
          }
        }

        if (!ignoredRuleIds.contains(adjectiveRule)) {
          for (var i = 0; i + 2 < words.length; i++) {
            final declension = _articleDeclension(words[i].text);
            if (declension == null ||
                !safe(words.sublist(i, i + 3)) ||
                _coordinatedAfter(words, i + 2)) {
              continue;
            }
            final article = _syntax(clause, i, const <String>{'ART'});
            final adjective = _syntax(clause, i + 1, const <String>{'ADJ'});
            final noun = _syntax(clause, i + 2, const <String>{'SUB'});
            if (article == null ||
                adjective == null ||
                noun == null ||
                !_nominalsComplete(article) ||
                !_nominalsComplete(adjective) ||
                !_nominalsComplete(noun) ||
                !_anyAgreement(article, noun) ||
                _anyAdjectiveAgreement(article, adjective, noun, declension)) {
              continue;
            }
            final articleMorph = await lexeme(words[i], article);
            final adjectiveMorph = await lexeme(words[i + 1], adjective);
            final nounMorph = await lexeme(words[i + 2], noun);
            if (articleMorph == null ||
                adjectiveMorph == null ||
                nounMorph == null) {
              continue;
            }
            final articles = articleMorph.source
                .where((item) => item.pos == 'ART')
                .toList();
            final adjectives = adjectiveMorph.source
                .where((item) => item.pos == 'ADJ')
                .toList();
            final nouns = nounMorph.source
                .where((item) => item.pos == 'SUB')
                .toList();
            if (!_nominalsComplete(articles) ||
                !_nominalsComplete(adjectives) ||
                !_nominalsComplete(nouns) ||
                !_anyAgreement(articles, nouns) ||
                _anyAdjectiveAgreement(
                  articles,
                  adjectives,
                  nouns,
                  declension,
                )) {
              continue;
            }
            add(
              words[i + 1],
              adjectiveRule,
              'Die Adjektivform passt nicht zu Artikel und Substantiv.',
              <String>[
                for (final form in adjectiveMorph.forms)
                  if (form.reading.pos == 'ADJ' &&
                      _anyAdjectiveAgreement(
                        articles,
                        <_Reading>[form.reading],
                        nouns,
                        declension,
                      ))
                    form.text,
              ],
            );
          }
        }
      }
    }
    checkCurrent();
    diagnostics.sort((a, b) => a.start.compareTo(b.start));
    return List<AotGermanDiagnostic>.unmodifiable(diagnostics);
  }
}

final class _Reading {
  const _Reading(this.lemma, this.pos, this.features);
  final String lemma;
  final String pos;
  final Set<String> features;
}

final class _Form {
  const _Form(this.text, this.reading);
  final String text;
  final _Reading reading;
}

final class _Lexeme {
  const _Lexeme(this.source, this.forms);
  final List<_Reading> source;
  final List<_Form> forms;
}

const _numbers = <String>{'sin', 'plu'};
const _genders = <String>{'mas', 'fem', 'neu'};
const _cases = <String>{'nom', 'gen', 'dat', 'akk'};
const _persons = <String>{'1', '2', '3'};
const _finiteModes = <String>{'prae', 'prt', 'kj1', 'kj2'};
const _subjects = <String, ({String person, String number})>{
  'ich': (person: '1', number: 'sin'),
  'du': (person: '2', number: 'sin'),
  'er': (person: '3', number: 'sin'),
  'es': (person: '3', number: 'sin'),
  'wir': (person: '1', number: 'plu'),
  'ihr': (person: '2', number: 'plu'),
};
const _prepositions = <String, String>{
  'aus': 'dat',
  'bei': 'dat',
  'mit': 'dat',
  'seit': 'dat',
  'von': 'dat',
  'zu': 'dat',
  'durch': 'akk',
  'für': 'akk',
  'gegen': 'akk',
  'ohne': 'akk',
  'um': 'akk',
};
final _horizontal = RegExp(r'^[ \t\u00a0\u202f]+$');
final _word = RegExp(r'^[\p{L}\p{M}]+$', unicode: true);

List<_Reading>? _syntax(AotClause clause, int index, Set<String> parts) {
  if (clause.variants.isEmpty) return null;
  final output = <_Reading>[];
  for (final variant in clause.variants) {
    if (index >= variant.units.length) return null;
    final unit = variant.units[index];
    if (!parts.contains(unit.grammar.partOfSpeech) ||
        unit.grammar.alternatives.isEmpty ||
        unit.homonymIndex < 0 ||
        unit.homonymIndex >= clause.words[index].homonyms.length) {
      return null;
    }
    final lemma = clause.words[index].homonyms[unit.homonymIndex].toUpperCase();
    for (final features in unit.grammar.alternatives) {
      output.add(_Reading(lemma, unit.grammar.partOfSpeech, features));
    }
  }
  // An adversarial/unreasonably ambiguous phrase must not start a large
  // Cartesian product or lead to selecting just the first interpretation.
  return output.isEmpty || output.length > 64 ? null : output;
}

bool _intersects(Set<String> a, Set<String> b, Set<String> dimension) =>
    dimension.any((value) => a.contains(value) && b.contains(value));

bool _subjectEvidence(
  List<_Reading> readings,
  ({String person, String number}) subject,
) =>
    readings.isNotEmpty &&
    readings.every(
      (item) =>
          item.pos == 'PRO' &&
          item.features.contains('per') &&
          item.features.contains('nom') &&
          item.features.contains(subject.person) &&
          item.features.contains(subject.number),
    );

bool _isFinite(_Reading item) =>
    item.pos == 'VER' &&
    item.features.any(_finiteModes.contains) &&
    item.features.any(_persons.contains) &&
    item.features.any(_numbers.contains) &&
    !item.features.contains('inf') &&
    !item.features.contains('imp');

List<_Reading> _finite(List<_Reading> readings) {
  final relevant = readings
      .where(
        (item) => item.pos == 'VER' && item.features.any(_finiteModes.contains),
      )
      .toList();
  return relevant.every(_isFinite) ? relevant : <_Reading>[];
}

bool _verbAgrees(_Reading verb, ({String person, String number}) subject) =>
    verb.features.contains(subject.person) &&
    verb.features.contains(subject.number);

bool _nominalsComplete(List<_Reading> readings) =>
    readings.isNotEmpty &&
    readings.every(
      (item) =>
          item.features.any(_numbers.contains) &&
          item.features.any(_cases.contains) &&
          (!item.features.contains('sin') ||
              item.features.any(_genders.contains)),
    );

bool _nominalAgreement(_Reading a, _Reading b, {String? requiredCase}) {
  if (!_nominalsComplete(<_Reading>[a, b]) ||
      !_intersects(a.features, b.features, _numbers) ||
      (requiredCase != null &&
          (!a.features.contains(requiredCase) ||
              !b.features.contains(requiredCase))) ||
      !_intersects(a.features, b.features, _cases)) {
    return false;
  }
  return a.features.contains('plu') && b.features.contains('plu') ||
      _intersects(a.features, b.features, _genders);
}

bool _anyAgreement(
  List<_Reading> a,
  List<_Reading> b, {
  String? requiredCase,
}) => a.any(
  (left) => b.any(
    (right) => _nominalAgreement(left, right, requiredCase: requiredCase),
  ),
);

bool _anyAdjectiveAgreement(
  List<_Reading> articles,
  List<_Reading> adjectives,
  List<_Reading> nouns,
  String declension,
) => articles.any(
  (article) => nouns.any((noun) {
    if (!_nominalAgreement(article, noun)) return false;
    return adjectives.any((adjective) {
      if (!adjective.features.contains(declension)) return false;
      // All three must share one number/case/gender tuple. Pairwise overlap
      // could otherwise invent a compatible tuple from disjoint alternatives.
      final common = article.features.intersection(noun.features);
      final triple = common.intersection(adjective.features);
      return triple.any(_numbers.contains) &&
          triple.any(_cases.contains) &&
          (triple.contains('plu') || triple.any(_genders.contains));
    });
  }),
);

bool _personalCaseEvidence(List<_Reading> readings) =>
    readings.isNotEmpty &&
    readings.every(
      (item) =>
          item.features.contains('per') &&
          item.features.any(_cases.contains) &&
          item.features.any(_numbers.contains) &&
          item.features.any(_persons.contains),
    );

bool _samePersonalIdentity(_Reading a, _Reading b) =>
    b.features.contains('per') &&
    _intersects(a.features, b.features, _persons) &&
    _intersects(a.features, b.features, _numbers) &&
    (!a.features.any(_genders.contains) ||
        _intersects(a.features, b.features, _genders));

bool _coordinatedAfter(List<AotToken> words, int at) =>
    at + 1 < words.length &&
    const <String>{
      'und',
      'oder',
      'sowie',
      ',',
    }.contains(words[at + 1].text.toLowerCase());

String? _articleDeclension(String word) {
  final lower = word.toLowerCase();
  if (const <String>{
    'der',
    'die',
    'das',
    'den',
    'dem',
    'des',
  }.contains(lower)) {
    return 'def';
  }
  if (const <String>{
    'ein',
    'eine',
    'einen',
    'einem',
    'einer',
    'eines',
  }.contains(lower)) {
    return 'ind';
  }
  return null;
}

String _caseMessage(String grammaticalCase) => grammaticalCase == 'dat'
    ? 'Diese Präposition verlangt hier den Dativ.'
    : 'Diese Präposition verlangt hier den Akkusativ.';

String _caseLike(String original, String replacement) {
  final lower = replacement.toLowerCase();
  if (original == original.toUpperCase()) return replacement.toUpperCase();
  if (original.isNotEmpty && original[0] != original[0].toLowerCase()) {
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }
  return lower;
}
