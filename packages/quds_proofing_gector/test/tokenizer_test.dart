import 'dart:convert';
import 'dart:io';

import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late GectorTokenizer tokenizer;
  setUpAll(() async {
    tokenizer = (await TestBundle.load()).bundle.tokenizer;
  });
  final Object? raw = jsonDecode(
    File('test/fixtures/tokenizer_oracle.json').readAsStringSync(),
  );
  for (final value in raw! as List<Object?>) {
    final row = value! as Map<String, Object?>;
    test('pinned tokenizers Unicode/alignment oracle ${row['id']}', () {
      final words = (row['words']! as List<Object?>).cast<String>();
      if (row['missing_word'] == true) {
        expect(() => tokenizer.encode(words), throwsFormatException);
      } else {
        final prepared = tokenizer.encode(words);
        expect(prepared.inputIds, row['input_ids']);
        expect(prepared.firstSubwordIndices, row['first_subword_indices']);
      }
    });
  }
}
