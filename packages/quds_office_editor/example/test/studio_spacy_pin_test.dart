import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';

String _pin(String script, String name) {
  final match = RegExp(
    '^$name=([^\\s]+)\$',
    multiLine: true,
  ).firstMatch(script);
  expect(match, isNotNull, reason: '$name is missing from the build script');
  return match!.group(1)!;
}

void main() {
  test('the app build installs the grammar-qualified spaCy library', () {
    final script = File('tool/build_macos_app.sh').readAsStringSync();
    final sha = _pin(script, 'SPACY_PIN_SHA256');
    expect(sha, spacyGrammarMacosBundledSha256);
    expect(spacyGrammarNativeSha256s, contains(sha));
    final qualification = spacyQualificationFor(sha);
    expect(qualification, isNotNull);
    expect(qualification!.grammarQualified, isTrue);
    expect(_pin(script, 'SPACY_PIN_REVISION'), matches(r'^[0-9a-f]{40}$'));
    expect(_pin(script, 'SPACY_PIN_BYTES'), matches(r'^[1-9][0-9]*$'));
    expect(_pin(script, 'SPACY_PIN_REPOSITORY'), spacyHuggingFaceRepository);
  });
}
