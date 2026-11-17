import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';

import 'bundle.dart';
import 'unicode_case.dart';

/// Read-only spelling knowledge used by conservative model guards. It must
/// not learn a replacement merely because the model proposed it.
abstract interface class GectorLexicon {
  Future<bool> isKnown(String word);
  Future<void> dispose();
}

/// Sent to the worker isolate; load dictionaries inside [open].
abstract interface class GectorLexiconFactory {
  Future<GectorLexicon> open();
}

/// A deliberately closed lexicon, useful for hosts with an existing word set.
final class GectorWordSetLexicon implements GectorLexicon {
  GectorWordSetLexicon(Iterable<String> words)
    : _words = Set<String>.unmodifiable(words.map(normalizeGermanWord));
  final Set<String> _words;
  @override
  Future<bool> isKnown(String word) async =>
      _words.contains(normalizeGermanWord(word));
  @override
  Future<void> dispose() async {}
}

final class GectorWordSetLexiconFactory implements GectorLexiconFactory {
  GectorWordSetLexiconFactory(Iterable<String> words)
    : words = Set<String>.unmodifiable(words);
  final Set<String> words;
  @override
  Future<GectorLexicon> open() async => GectorWordSetLexicon(words);
}

/// Quds conservative policy derived from the pinned declarative German guards.
/// It is not a claim of parity with Proofbird's unpublished application code.
/// Note-only built-ins use explicit conservative rejection rules documented in
/// the package README. Unknown rule types/fields fail at startup.
final class GectorGermanGuards {
  GectorGermanGuards._(this.configuration, this.lexicon, this._rules);

  factory GectorGermanGuards.fromJson(
    String source, {
    required GectorConfiguration configuration,
    required GectorLexicon lexicon,
  }) {
    final root = _map(jsonDecode(source));
    if (root.keys.any((key) => key != 'guards') ||
        root['guards'] is! List<Object?>) {
      throw const FormatException('Unsupported GECToR guard document.');
    }
    final rules = <Map<String, Object?>>[];
    for (final raw in root['guards']! as List<Object?>) {
      final value = _map(raw);
      final type = value['type'];
      if (type is! String ||
          !_fields.containsKey(type) ||
          value.keys.any((key) => !_fields[type]!.contains(key))) {
        throw const FormatException('Unknown GECToR guard rule or field.');
      }
      for (final entry in value.entries) {
        if (entry.key == 'keepCaseDiffering') {
          if (entry.value is! bool) {
            throw const FormatException('Invalid guard boolean.');
          }
        } else if (entry.value is! String) {
          throw const FormatException('Invalid guard string.');
        }
      }
      for (final key in _required[type] ?? const <String>[]) {
        if (value[key] is! String || (value[key]! as String).isEmpty) {
          throw const FormatException('Incomplete GECToR guard.');
        }
      }
      final scope = value['scope'];
      if (scope != null && scope != 'prev' && scope != 'strict') {
        throw const FormatException('Unsupported GECToR guard scope.');
      }
      rules.add(Map<String, Object?>.unmodifiable(value));
    }
    return GectorGermanGuards._(
      configuration,
      lexicon,
      List<Map<String, Object?>>.unmodifiable(rules),
    );
  }

  final GectorConfiguration configuration;
  final GectorLexicon lexicon;
  final List<Map<String, Object?>> _rules;
  final Map<String, bool> _known = <String, bool>{};

  void beginRequest() => _known.clear();

  Future<bool> _isKnown(String word) async {
    final normalized = normalizeGermanWord(word);
    if (_known.containsKey(normalized)) return _known[normalized]!;
    return _known[normalized] = await lexicon.isKnown(normalized);
  }

  Future<String> apply({
    required List<String> words,
    required int index,
    required String label,
    required String replacement,
    required Set<String> personalWords,
    bool isSourceStart = true,
  }) async {
    final word = index < 0 ? r'$START' : words[index];
    // A later sentence segment is not a new paragraph. Do not grant it the
    // original request's START insertion or case-differing duplicate exception.
    if (index < 0 && !isSourceStart) return word;
    if (replacement == word) return word;
    if (personalWords.contains(normalizeGermanWord(word))) return word;
    final lower = gectorLower(word);
    final before = index > 0 ? gectorLower(words[index - 1]) : '';
    final after = index >= 0 && index + 1 < words.length
        ? gectorLower(words[index + 1])
        : '';
    var candidate = replacement;
    for (final rule in _rules) {
      final type = rule['type']! as String;
      final target = gectorLower(candidate);
      final declaredWords = _split(rule['words']);
      switch (type) {
        case 'suppress_append_words':
          if (label.startsWith(r'$APPEND_') &&
              declaredWords.contains(gectorLower(label.substring(8)))) {
            return word;
          }
        case 'require_cue':
          if (_split(rule['pairs']).contains('$lower>$target') &&
              !_hasCue(rule, words, index)) {
            return word;
          }
        case 'delete_only_duplicates':
          if (candidate.isNotEmpty) break;
          if (index < 0 || (before != lower && after != lower)) return word;
          final other = before == lower ? words[index - 1] : words[index + 1];
          final first = before == lower ? index - 1 : index;
          if (rule['keepCaseDiffering'] == true &&
              (first > 0 || !isSourceStart) &&
              word != other) {
            return word;
          }
          final preceding = first > 0 ? gectorLower(words[first - 1]) : '';
          if (declaredWords.contains(lower) &&
              _split(rule['whenPrevIs']).contains(preceding)) {
            return word;
          }
        case 'redirect_replace':
          if (word == rule['from'] &&
              candidate == rule['to'] &&
              _split(rule['whenPrevIs']).contains(before)) {
            candidate = rule['redirect']! as String;
          }
        case 'block_replace':
          if (word == rule['from'] && candidate == rule['to']) return word;
        case 'no_replace_to_closed_class':
          if (declaredWords.contains(target) &&
              !declaredWords.contains(lower)) {
            return word;
          }
        case 'capital_needs_known_word':
          if (candidate != word &&
              gectorLower(candidate) == lower &&
              candidate == gectorCapital(word) &&
              !await _isKnown(word) &&
              !await _isKnown(candidate)) {
            return word;
          }
        case 'verb_person_needs_subject':
          final desired = _verbTargetPersons(word, candidate, label);
          if (desired.isNotEmpty && !_hasSubject(words, index, desired, rule)) {
            return word;
          }
        case 'keep_form_next_to':
          if ((declaredWords.contains(before) ||
                  declaredWords.contains(after)) &&
              _split(rule['suffixes']).any(lower.endsWith)) {
            return word;
          }
        case 'keep_plural_after':
          if (declaredWords.contains(before) &&
              candidate.length < word.length &&
              _split(rule['suffixes']).any(lower.endsWith)) {
            return word;
          }
        case 'velar_orthography':
          // The source supplies a note, not its app implementation. Reject
          // added h unless immediately after c/g and independently known.
          if (target.length == lower.length + 1) {
            for (var i = 0; i < target.length; i++) {
              if (target[i] == 'h' &&
                  target.replaceRange(i, i + 1, '') == lower &&
                  (i == 0 ||
                      !'cg'.contains(target[i - 1]) ||
                      !await _isKnown(candidate))) {
                return word;
              }
            }
          }
        case 'elision_echo':
          // Do not introduce the note's redundant apostrophe echo.
          if (index > 0 &&
              words[index - 1].contains("'") &&
              gectorLower(words[index - 1]).endsWith("'$target")) {
            return word;
          }
        case 'auxiliary_number':
          // Retain the source note's Italian e` construction in mixed text.
          if (target == 'sono' &&
              (lower == 'e' || lower == 'e`' || lower == 'è')) {
            return word;
          }
        case 'no_unknown_replacement':
          // Applied after every redirect below, independent of source order.
          break;
      }
    }
    if (candidate == word || candidate.isEmpty) return candidate;
    final lexical = _lexicalWords.allMatches(candidate);
    for (final match in lexical) {
      final proposed = match.group(0)!;
      // START is an internal prefix; APPEND guards still check appended words.
      if (index < 0 && proposed == 'START') continue;
      if (proposed == word && label.startsWith(r'$APPEND_')) continue;
      if (!await _isKnown(proposed)) return word;
    }
    return candidate;
  }

  Set<String> _verbTargetPersons(
    String word,
    String replacement,
    String label,
  ) {
    final result = <String>{};
    String? targetNumber;
    if (label.startsWith(r'$TRANSFORM_VERB_')) {
      final parts = label.substring(16).split('_');
      if (parts.length == 2 && RegExp(r'^P[123][SP]$').hasMatch(parts[1])) {
        result.add(parts[1].substring(1));
        targetNumber = parts[1].substring(2);
      }
    }
    final prefix = '${word}_';
    for (final entry in configuration.verbForms.entries) {
      if (entry.value != replacement || !entry.key.startsWith(prefix)) continue;
      final tag = entry.key.substring(entry.key.lastIndexOf('_') + 1);
      if (RegExp(r'^P[123][SP]$').hasMatch(tag) &&
          (targetNumber == null || tag.endsWith(targetNumber))) {
        // The authenticated table can encode the same replacement for several
        // persons: ist -> sind is both 1P and 3P. Match its surface form to the
        // subject, even when the model chose the other same-number label.
        // Do not expand a transform across singular/plural ambiguity (geht is
        // both 3S and 2P); the existing conservative number policy stays intact.
        result.add(tag.substring(1));
      }
    }
    return result;
  }

  static bool _hasSubject(
    List<String> words,
    int at,
    Set<String> desired,
    Map<String, Object?> rule,
  ) {
    final (clauseStart, clauseEnd) = _context(words, at, _clauseBoundary);
    if (desired.any((form) => form.endsWith('S')) &&
        words
            .sublist(clauseStart, clauseEnd)
            .map(gectorLower)
            .any(
              const <String>{
                'und',
                'oder',
                'sowie',
                'sowohl',
                'weder',
              }.contains,
            )) {
      // No parse is available to disambiguate coordination from objects or
      // predicates. Hold singular changes throughout this clause.
      return false;
    }
    final subjects = <String, Set<String>>{};
    for (final pair in _split(rule['pairs'])) {
      final parts = pair.split('>');
      if (parts.length == 2) {
        subjects.putIfAbsent(parts[0], () => <String>{}).add(parts[1]);
      }
    }
    for (var distance = 1; distance <= 5; distance++) {
      for (final index in <int>[at - distance, at + distance]) {
        if (index < 0 || index >= words.length) continue;
        final left = index < at ? index + 1 : at + 1;
        final right = index < at ? at : index;
        if (words.sublist(left, right).any(_clauseBoundary.contains)) continue;
        final forms = subjects[gectorLower(words[index])];
        if (forms != null) return forms.any(desired.contains);
      }
    }
    // Only unambiguous singular determiners provide a noun-phrase number cue.
    // Ambiguous determiners and unsupported person guesses are held.
    if (desired.contains('3S') &&
        at >= 2 &&
        const <String>{
          'der',
          'das',
          'ein',
          'eine',
          'dieser',
          'dieses',
          'jeder',
          'jedes',
        }.contains(gectorLower(words[at - 2]))) {
      return true;
    }
    return false;
  }

  static bool _hasCue(Map<String, Object?> rule, List<String> words, int at) {
    final cues = _split(rule['cues']);
    if (cues.isEmpty) return false;
    final (start, end) = _context(words, at, _sentenceBoundary);
    final lower = words
        .sublist(start, end)
        .map(gectorLower)
        .toList(growable: false);
    at -= start;
    final previousOnly = rule['scope'] == 'prev';
    for (final cue in cues) {
      if (cue == '#year') {
        if (lower.any((word) => RegExp(r'^[12][0-9]{3}$').hasMatch(word))) {
          return true;
        }
      } else if (cue == '#copula-end') {
        if (at >= 0 &&
            lower.skip(at + 1).every((word) => !_lexicalWords.hasMatch(word)) &&
            lower
                .take(at)
                .any(
                  const <String>{
                    'ist',
                    'sind',
                    'war',
                    'waren',
                    'sei',
                    'wäre',
                  }.contains,
                )) {
          return true;
        }
      } else if (previousOnly) {
        if (at > 0 && lower[at - 1] == cue) return true;
      } else {
        final parts = cue.split(' ');
        for (var start = 0; start + parts.length <= lower.length; start++) {
          var same = true;
          for (var i = 0; i < parts.length; i++) {
            if (lower[start + i] != parts[i]) {
              same = false;
              break;
            }
          }
          if (same) return true;
        }
      }
    }
    return false;
  }

  static final _lexicalWords = RegExp(r'[\p{L}\p{M}]+', unicode: true);
  static const _sentenceBoundary = <String>{'.', '!', '?'};
  static const _clauseBoundary = <String>{',', ';', ':', '.', '!', '?'};

  static (int, int) _context(
    List<String> words,
    int at,
    Set<String> boundaries,
  ) {
    var start = at < 0 ? 0 : at;
    var end = at < 0 ? 0 : at + 1;
    while (start > 0 && !boundaries.contains(words[start - 1])) {
      start--;
    }
    while (end < words.length && !boundaries.contains(words[end])) {
      end++;
    }
    return (start, end);
  }

  static Set<String> _split(Object? value) =>
      value is String && value.isNotEmpty
      ? value.split('|').toSet()
      : const <String>{};
  static Map<String, Object?> _map(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Invalid GECToR guard object.');
    }
    return value;
  }

  static const _required = <String, Set<String>>{
    'suppress_append_words': <String>{'words'},
    'require_cue': <String>{'pairs'},
    'redirect_replace': <String>{'from', 'to', 'redirect', 'whenPrevIs'},
    'block_replace': <String>{'from', 'to'},
    'no_replace_to_closed_class': <String>{'words'},
    'verb_person_needs_subject': <String>{'pairs', 'words'},
    'keep_form_next_to': <String>{'words', 'suffixes'},
    'keep_plural_after': <String>{'words', 'suffixes'},
  };
  static const _fields = <String, Set<String>>{
    'velar_orthography': <String>{'type', 'note'},
    'elision_echo': <String>{'type', 'note'},
    'auxiliary_number': <String>{'type', 'note'},
    'suppress_append_words': <String>{'type', 'note', 'words'},
    'require_cue': <String>{'type', 'note', 'pairs', 'cues', 'scope'},
    'delete_only_duplicates': <String>{
      'type',
      'note',
      'words',
      'whenPrevIs',
      'keepCaseDiffering',
    },
    'redirect_replace': <String>{
      'type',
      'note',
      'from',
      'to',
      'redirect',
      'whenPrevIs',
    },
    'capital_needs_known_word': <String>{'type', 'note'},
    'no_replace_to_closed_class': <String>{'type', 'note', 'words'},
    'block_replace': <String>{'type', 'note', 'from', 'to'},
    'verb_person_needs_subject': <String>{'type', 'note', 'pairs', 'words'},
    'keep_form_next_to': <String>{'type', 'note', 'words', 'suffixes'},
    'keep_plural_after': <String>{'type', 'note', 'words', 'suffixes'},
    'no_unknown_replacement': <String>{'type', 'note', 'scope'},
  };
}
