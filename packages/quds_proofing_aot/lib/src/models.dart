import 'package:characters/characters.dart';

/// Language names accepted by the upstream SynanDaemon.
enum AotLanguage {
  german('German', true),
  russian('Russian', true),
  english('English', false);

  const AotLanguage(this.daemonName, this.supportsSyntax);
  final String daemonName;
  final bool supportsSyntax;
}

/// One POS and its distinct grammatical alternatives. Alternatives must not be
/// combined into a single purported case/number/person interpretation.
final class AotGrammar {
  AotGrammar({
    required this.raw,
    required this.partOfSpeech,
    required Iterable<Iterable<String>> alternatives,
  }) : alternatives = List<Set<String>>.unmodifiable(
         alternatives.map(Set<String>.unmodifiable),
       );

  factory AotGrammar.parse(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return AotGrammar(
        raw: raw,
        partOfSpeech: '',
        alternatives: const <Set<String>>[],
      );
    }
    final int split = trimmed.indexOf(RegExp(r'\s'));
    final String pos = split < 0 ? trimmed : trimmed.substring(0, split);
    final String rest = split < 0 ? '' : trimmed.substring(split).trim();
    return AotGrammar(
      raw: raw,
      partOfSpeech: pos,
      alternatives: <Set<String>>[
        for (final String alternative in rest.split(';'))
          if (alternative.trim().isNotEmpty) _features(alternative),
      ],
    );
  }

  factory AotGrammar.fromFeatures(
    String partOfSpeech,
    Iterable<String> features,
  ) {
    final Set<String> values = Set<String>.of(features);
    return AotGrammar(
      raw: '$partOfSpeech ${values.join(',')}',
      partOfSpeech: partOfSpeech,
      alternatives: <Set<String>>[values],
    );
  }

  final String raw;
  final String partOfSpeech;
  final List<Set<String>> alternatives;

  /// A display/search union, not a single valid grammatical alternative.
  Set<String> get features => Set<String>.unmodifiable(
    alternatives.expand((Set<String> alternative) => alternative),
  );
}

/// Immutable source token. AOT does not supply character offsets. [start] and
/// [end] are populated only after an exact sequential match to the input, at
/// grapheme boundaries. They are UTF-16 offsets and [end] is exclusive.
final class AotToken {
  AotToken({
    required this.text,
    required Iterable<String> homonyms,
    this.start,
    this.end,
  }) : homonyms = List<String>.unmodifiable(homonyms) {
    if ((start == null) != (end == null) ||
        (start != null && (start! < 0 || end! < start!))) {
      throw ArgumentError('AOT token requires a valid complete source range.');
    }
  }

  final String text;
  final List<String> homonyms;
  final int? start;
  final int? end;
  bool get isAligned => start != null && end != null;
}

final class AotUnit {
  const AotUnit({required this.homonymIndex, required this.grammar});
  final int homonymIndex;
  final AotGrammar grammar;
}

/// Clause-local inclusive token coordinates. For a subject relation [start]
/// identifies the subject and [last] identifies the predicate; it can point
/// backwards. These indexes are never source character offsets.
final class AotGroup {
  const AotGroup({
    required this.start,
    required this.last,
    required this.isGroup,
    required this.isSubject,
    required this.description,
  });
  final int start;
  final int last;
  final bool isGroup;
  final bool isSubject;
  final String description;
}

final class AotVariant {
  AotVariant({
    required Iterable<AotUnit> units,
    required Iterable<AotGroup> groups,
  }) : units = List<AotUnit>.unmodifiable(units),
       groups = List<AotGroup>.unmodifiable(groups);
  final List<AotUnit> units;
  final List<AotGroup> groups;
}

final class AotClause {
  AotClause({
    required Iterable<AotToken> words,
    required Iterable<AotVariant> variants,
  }) : words = List<AotToken>.unmodifiable(words),
       variants = List<AotVariant>.unmodifiable(variants);
  final List<AotToken> words;
  final List<AotVariant> variants;
}

final class AotSentence {
  AotSentence({required Iterable<AotClause> clauses})
    : clauses = List<AotClause>.unmodifiable(clauses);
  final List<AotClause> clauses;
}

/// The complete immutable input snapshot and the daemon's analysis. A lack of
/// analyses or grammatical groups is not evidence that the text is erroneous.
final class AotAnalysis {
  AotAnalysis({
    required this.text,
    required this.language,
    required Iterable<AotSentence> sentences,
  }) : sentences = List<AotSentence>.unmodifiable(sentences);

  factory AotAnalysis.fromJson(
    Object? json, {
    required String text,
    AotLanguage language = AotLanguage.german,
  }) {
    final _SourceAligner aligner = _SourceAligner(text);
    final List<AotSentence> sentences = <AotSentence>[];
    for (final Object? sentenceJson in _list(json, 'sentences')) {
      final List<AotClause> clauses = <AotClause>[];
      for (final Object? clauseJson in _list(sentenceJson, 'sentence')) {
        final Map<String, Object?> clause = _map(clauseJson, 'clause');
        final List<AotToken> words = <AotToken>[];
        for (final Object? wordJson in _list(clause['words'], 'words')) {
          final Map<String, Object?> word = _map(wordJson, 'word');
          final String surface = _string(word['str'], 'word.str');
          if (surface.isEmpty) _invalid('word.str must not be empty');
          final List<String> homonyms = <String>[
            for (final Object? value in _list(word['homonyms'], 'homonyms'))
              _string(value, 'homonym'),
          ];
          final (int, int)? range = aligner.match(surface);
          words.add(
            AotToken(
              text: surface,
              homonyms: homonyms,
              start: range?.$1,
              end: range?.$2,
            ),
          );
        }
        final List<AotVariant> variants = <AotVariant>[];
        for (final Object? variantJson in _list(
          clause['variants'],
          'variants',
        )) {
          final Map<String, Object?> variant = _map(variantJson, 'variant');
          final List<Object?> unitsJson = _list(variant['units'], 'units');
          if (unitsJson.length != words.length) {
            _invalid('variant units must correspond to all clause words');
          }
          final List<AotUnit> units = <AotUnit>[];
          for (int i = 0; i < unitsJson.length; i++) {
            final Map<String, Object?> unit = _map(unitsJson[i], 'unit');
            final int homonym = _int(unit['homNo'], 'homNo');
            if (homonym < 0 || homonym >= words[i].homonyms.length) {
              _invalid('homNo is outside the word homonyms');
            }
            units.add(
              AotUnit(
                homonymIndex: homonym,
                grammar: AotGrammar.parse(_string(unit['grm'], 'unit.grm')),
              ),
            );
          }
          final List<AotGroup> groups = <AotGroup>[];
          for (final Object? groupJson in _list(variant['groups'], 'groups')) {
            final Map<String, Object?> group = _map(groupJson, 'group');
            final int start = _int(group['start'], 'group.start');
            final int last = _int(group['last'], 'group.last');
            final bool isGroup = _bool(group['isGroup'], 'group.isGroup');
            final bool isSubject = _bool(group['isSubj'], 'group.isSubj');
            if (start < 0 ||
                last < 0 ||
                start >= words.length ||
                last >= words.length ||
                (isGroup && isSubject) ||
                (!isSubject && start > last)) {
              _invalid('invalid clause-local group coordinates or flags');
            }
            groups.add(
              AotGroup(
                start: start,
                last: last,
                isGroup: isGroup,
                isSubject: isSubject,
                description: _string(group['descr'], 'group.descr'),
              ),
            );
          }
          variants.add(AotVariant(units: units, groups: groups));
        }
        clauses.add(AotClause(words: words, variants: variants));
      }
      sentences.add(AotSentence(clauses: clauses));
    }
    return AotAnalysis(text: text, language: language, sentences: sentences);
  }

  final String text;
  final AotLanguage language;
  final List<AotSentence> sentences;

  Iterable<AotToken> get tokens => sentences
      .expand((AotSentence sentence) => sentence.clauses)
      .expand((AotClause clause) => clause.words);

  /// Every non-whitespace source character belongs to a correctly aligned
  /// token. Empty analysis for nonempty text is explicitly incomplete.
  bool get fullyAligned {
    int cursor = 0;
    final Set<int> boundaries = _graphemeBoundaries(text);
    for (final AotToken token in tokens) {
      final int? start = token.start;
      final int? end = token.end;
      if (start == null ||
          end == null ||
          start < cursor ||
          end < start ||
          end > text.length ||
          !boundaries.contains(start) ||
          !boundaries.contains(end) ||
          text.substring(cursor, start).trim().isNotEmpty ||
          text.substring(start, end) != token.text) {
        return false;
      }
      cursor = end;
    }
    return text.substring(cursor).trim().isEmpty;
  }
}

final class AotInflectedForm {
  const AotInflectedForm({required this.text, required this.grammar});
  final String text;
  final AotGrammar grammar;
}

final class AotParadigmForm {
  AotParadigmForm({required this.text, required Iterable<String> features})
    : features = Set<String>.unmodifiable(features);
  final String text;
  final Set<String> features;
}

final class AotParadigmGroup {
  AotParadigmGroup({
    required Iterable<String> features,
    required Iterable<AotParadigmForm> forms,
  }) : features = Set<String>.unmodifiable(features),
       forms = List<AotParadigmForm>.unmodifiable(forms);
  final Set<String> features;
  final List<AotParadigmForm> forms;
}

final class AotParadigmPart {
  AotParadigmPart({
    required this.grammar,
    required Iterable<AotParadigmGroup> groups,
  }) : groups = List<AotParadigmGroup>.unmodifiable(groups);
  final AotGrammar grammar;
  final List<AotParadigmGroup> groups;
}

final class AotMorphReading {
  AotMorphReading({
    required this.found,
    required this.lemma,
    required this.grammar,
    required Iterable<String> commonGrammems,
    this.sourceNorm,
    this.wordWeight = 0,
    this.homonymWeight = 0,
    Iterable<AotParadigmPart> paradigm = const <AotParadigmPart>[],
  }) : commonGrammems = Set<String>.unmodifiable(commonGrammems),
       paradigm = List<AotParadigmPart>.unmodifiable(paradigm);
  final bool found;
  final String lemma;
  final AotGrammar grammar;
  final Set<String> commonGrammems;
  final String? sourceNorm;
  final int wordWeight;
  final int homonymWeight;
  final List<AotParadigmPart> paradigm;

  /// Reconstitutes concrete forms from the three inherited feature levels.
  /// This does not infer a form from the union in the submitted morphInfo.
  Iterable<AotInflectedForm> get forms sync* {
    for (final AotParadigmPart part in paradigm) {
      for (final AotParadigmGroup group in part.groups) {
        for (final AotParadigmForm form in group.forms) {
          yield AotInflectedForm(
            text: form.text,
            grammar: AotGrammar.fromFeatures(
              part.grammar.partOfSpeech,
              <String>{
                ...part.grammar.features,
                ...group.features,
                ...form.features,
              },
            ),
          );
        }
      }
    }
  }
}

/// Per-word morphology. The daemon's wordForm field is the lemma, while [word]
/// retains the actual submitted surface form.
final class AotMorphology {
  AotMorphology({
    required this.word,
    required this.language,
    required Iterable<AotMorphReading> readings,
  }) : readings = List<AotMorphReading>.unmodifiable(readings);

  factory AotMorphology.fromJson(
    Object? json, {
    required String word,
    AotLanguage language = AotLanguage.german,
  }) {
    final List<AotMorphReading> readings = <AotMorphReading>[];
    for (final Object? readingJson in _list(json, 'morphology')) {
      final Map<String, Object?> reading = _map(readingJson, 'reading');
      final List<AotParadigmPart> paradigm = <AotParadigmPart>[];
      if (reading.containsKey('paradigm')) {
        for (final Object? partJson in _list(reading['paradigm'], 'paradigm')) {
          final Map<String, Object?> part = _map(partJson, 'paradigm part');
          final List<AotParadigmGroup> groups = <AotParadigmGroup>[];
          for (final Object? groupJson in _list(
            part['formsGroups'],
            'formsGroups',
          )) {
            final Map<String, Object?> group = _map(groupJson, 'form group');
            final List<AotParadigmForm> forms = <AotParadigmForm>[];
            for (final Object? formJson in _list(group['forms'], 'forms')) {
              final Map<String, Object?> form = _map(formJson, 'form');
              final String text = _string(form['f'], 'form.f');
              if (text.isEmpty) _invalid('form.f must not be empty');
              forms.add(
                AotParadigmForm(
                  text: text,
                  features: _features(_string(form['grm'], 'form.grm')),
                ),
              );
            }
            groups.add(
              AotParadigmGroup(
                features: _features(_string(group['grm'], 'group.grm')),
                forms: forms,
              ),
            );
          }
          paradigm.add(
            AotParadigmPart(
              grammar: AotGrammar.parse(_string(part['pos'], 'part.pos')),
              groups: groups,
            ),
          );
        }
      }
      readings.add(
        AotMorphReading(
          found: _bool(reading['found'], 'found'),
          lemma: _string(reading['wordForm'], 'wordForm'),
          grammar: AotGrammar.parse(_string(reading['morphInfo'], 'morphInfo')),
          commonGrammems: _features(
            _string(reading['commonGrammems'], 'commonGrammems'),
          ),
          sourceNorm: reading.containsKey('srcNorm')
              ? _string(reading['srcNorm'], 'srcNorm')
              : null,
          wordWeight: _int(reading['wordWeight'], 'wordWeight'),
          homonymWeight: _int(reading['homonymWeight'], 'homonymWeight'),
          paradigm: paradigm,
        ),
      );
    }
    return AotMorphology(word: word, language: language, readings: readings);
  }

  final String word;
  final AotLanguage language;
  final List<AotMorphReading> readings;
}

Set<String> _features(String text) => <String>{
  for (final String feature in text.split(','))
    if (feature.trim().isNotEmpty) feature.trim(),
};

List<Object?> _list(Object? value, String field) {
  if (value is! List<Object?>) _invalid('$field must be an array');
  return value;
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map<String, Object?>) _invalid('$field must be an object');
  return value;
}

String _string(Object? value, String field) {
  if (value is! String) _invalid('$field must be a string');
  return value;
}

int _int(Object? value, String field) {
  if (value is! int) _invalid('$field must be an integer');
  return value;
}

bool _bool(Object? value, String field) {
  if (value is! bool) _invalid('$field must be a boolean');
  return value;
}

Never _invalid(String message) =>
    throw FormatException('Invalid AOT response: $message.');

Set<int> _graphemeBoundaries(String text) {
  final Set<int> result = <int>{0};
  int offset = 0;
  for (final String grapheme in text.characters) {
    offset += grapheme.length;
    result.add(offset);
  }
  return result;
}

final class _SourceAligner {
  _SourceAligner(this.text) : boundaries = _graphemeBoundaries(text);
  final String text;
  final Set<int> boundaries;
  int cursor = 0;
  bool broken = false;

  (int, int)? match(String token) {
    if (broken) return null;
    while (cursor < text.length && text[cursor].trim().isEmpty) {
      cursor++;
    }
    final int end = cursor + token.length;
    if (end > text.length ||
        !text.startsWith(token, cursor) ||
        !boundaries.contains(cursor) ||
        !boundaries.contains(end)) {
      // Do not search ahead to a repeated word after an omitted/changed token.
      broken = true;
      return null;
    }
    final int start = cursor;
    cursor = end;
    return (start, end);
  }
}
