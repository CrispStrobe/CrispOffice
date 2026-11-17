// SPDX-License-Identifier: MIT
// Evaluation only: corroborate parser noun number with the real Quds lexicon.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/src/proofing/german_morphology.dart';
import 'package:quds_office_engine/src/proofing/german_spelling.dart'
    show normalizeGermanWord;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    throw ArgumentError('Expected: syntax-result-json new-evidence-json');
  }
  final output = File(arguments[1]);
  if (output.existsSync()) throw StateError('Preserve existing evidence');
  final report =
      jsonDecode(await File(arguments[0]).readAsString())
          as Map<String, dynamic>;
  final cases = report['cases'] as List<dynamic>;
  final morphology = GermanNounMorphology.shared;
  await morphology.prepareWords([
    for (final raw in cases)
      for (final token
          in ((raw as Map<String, dynamic>)['tokens'] as List<dynamic>)
              .cast<Map<String, dynamic>>())
        if (token['dependency'] == 'sb' && token['pos'] == 'NOUN')
          token['text'] as String,
  ]);
  // Independently authored nominative article facts, indexed by the existing
  // morphology's masculine/feminine/neuter/plural gender convention.
  const genders = <String, Set<int>>{
    'der': {0},
    'die': {1, 3},
    'das': {2},
    'ein': {0, 2},
    'eine': {1},
    'dieser': {0},
    'diese': {1, 3},
    'dieses': {2},
    'mein': {0, 2},
    'meine': {1, 3},
    'dein': {0, 2},
    'deine': {1, 3},
    'sein': {0, 2},
    'seine': {1, 3},
    'ihr': {0, 2},
    'ihre': {1, 3},
    'unser': {0, 2},
    'unsere': {1, 3},
    'euer': {0, 2},
    'eure': {1, 3},
  };
  final evidence = <Map<String, dynamic>>[];
  for (final raw in cases) {
    final c = raw as Map<String, dynamic>;
    final tokens = (c['tokens'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (var index = 0; index < tokens.length; index++) {
      final noun = tokens[index];
      if (noun['dependency'] != 'sb' || noun['pos'] != 'NOUN') continue;
      final determiners = tokens
          .where((token) => token['head'] == index && token['pos'] == 'DET')
          .toList();
      final determiner = determiners.length == 1
          ? (determiners.single['text'] as String).toLowerCase()
          : '';
      final selectedGenders = genders[determiner] ?? const <int>{};
      final word = noun['text'] as String;
      final numbers = <String>{};
      if (morphology.acceptsSpelling(word)) {
        for (final reading in morphology.lookup(word)) {
          if (selectedGenders.contains(reading.gender) &&
              reading
                  .formsForCase(0)
                  .any(
                    (form) =>
                        normalizeGermanWord(form).toLowerCase() ==
                        normalizeGermanWord(word).toLowerCase(),
                  )) {
            numbers.add(reading.gender == 3 ? 'Plur' : 'Sing');
          }
        }
      }
      evidence.add({
        'id': c['id'],
        'start': noun['start'],
        'text': word,
        'determiner': determiner,
        'numbers': numbers.toList()..sort(),
        'unresolved': morphology.hasUnresolvedReading(word),
      });
    }
  }
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'scope': 'Evaluation-only exact parser-input noun corroboration; no model changes or new dictionary assets.', 'cases_sha256': report['cases_sha256'], 'model_version': (report['model'] as Map<String, dynamic>)['version'], 'nouns': evidence})}\n',
  );
}
