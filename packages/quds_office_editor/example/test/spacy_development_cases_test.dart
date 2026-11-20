import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/spacy_development_cases.g.dart';

/// The on-device spaCy parity gate embeds the frozen development panel; it
/// must stay identical to the authenticated repository fixtures.
void main() {
  test('embedded development panel equals the frozen fixtures', () {
    const root = '../../../tools/proofing/spacy/fixtures/development';
    final manifestBytes = File('$root/manifest.json').readAsBytesSync();
    final panel = jsonDecode(spacyDevelopmentPanelJson) as Map<String, dynamic>;
    expect(sha256.convert(manifestBytes).toString(), panel['manifest_sha256']);
    final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map;
    final cases = (panel['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases.map((c) => c['id']), [
      for (final item in manifest['cases'] as List) (item as Map)['id'],
    ]);
    for (final item in cases) {
      final bytes = File('$root/${item['id']}/case.json').readAsBytesSync();
      expect(sha256.convert(bytes).toString(), item['case_sha256']);
      final reference = jsonDecode(utf8.decode(bytes)) as Map;
      expect(item['text'], (reference['case'] as Map)['text']);
      final annotations = reference['annotations'] as Map;
      expect(item['tokens'], annotations['tokens']);
      expect(item['sentences'], annotations['sentences']);
    }
  });
}
