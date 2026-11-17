import 'dart:convert';

import 'package:quds_proofing_aot/quds_proofing_aot.dart';
import 'package:test/test.dart';

import 'fixtures/upstream_german_morphology.dart';

void main() {
  final Map<String, Object?> cases =
      jsonDecode(upstreamGermanMorphologyJson) as Map<String, Object?>;
  for (final String word in <String>['Mutter', 'VÖGEL']) {
    test('pinned upstream LemmatizeJson output: $word', () {
      final AotMorphology result = AotMorphology.fromJson(
        cases[word],
        word: word,
      );
      final AotMorphReading reading = result.readings.single;
      expect(result.word, word);
      expect(reading.found, isTrue);
      expect(reading.lemma, word == 'Mutter' ? 'MUTTER' : 'VOGEL');
      expect(reading.commonGrammems, isEmpty);
      expect(reading.wordWeight, 0);
      expect(reading.homonymWeight, 0);
      expect(reading.forms.length, 8);
      // The submitted morphInfo is a union. Each concrete paradigm form
      // retains a single case/number tuple, including repeated surface forms.
      expect(
        reading.grammar.features.intersection({
          'nom',
          'gen',
          'dat',
          'akk',
        }).length,
        greaterThan(1),
      );
      for (final AotInflectedForm form in reading.forms) {
        expect(form.grammar.partOfSpeech, 'SUB');
        expect(
          form.grammar.features,
          contains(word == 'Mutter' ? 'fem' : 'mas'),
        );
        expect(form.grammar.features.intersection({'sin', 'plu'}).length, 1);
        expect(
          form.grammar.features.intersection({
            'nom',
            'gen',
            'dat',
            'akk',
          }).length,
          1,
        );
      }
      final AotInflectedForm dativePlural = reading.forms.singleWhere(
        (AotInflectedForm form) =>
            form.grammar.features.containsAll({'dat', 'plu'}),
      );
      expect(dativePlural.text, word == 'Mutter' ? 'MÜTTERN' : 'VÖGELN');
    });
  }
}
