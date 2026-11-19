// Arabic rule findings over a corpus with the real analyzer, one JSON line
// per finding (sentence index, rule id, range, message), to compare backends
// or bundles finding by finding:
//   dart run tool/pud_rule_findings.dart <library> <bundle dir> <corpus.txt>
// The corpus has one sentence per line; the bundle's manifest variant
// selects the pinned bundle (proofing-bin or the earlier noprob).
import 'dart:convert';
import 'dart:io';

import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln('usage: pud_rule_findings.dart <library> <bundle> <corpus>');
    exit(64);
  }
  final [library, bundle, corpus] = args;
  final variant =
      (jsonDecode(File('$bundle/manifest.json').readAsStringSync())
          as Map)['variant'];
  final morphology = CamelArabicMorphology(
    database: MorphDatabaseFiles(
      variant == 'noprob' ? camelMorphMsaNoprob : camelMorphMsaProofingBin,
      manifestPath: '$bundle/manifest.json',
    ),
    nativeLibraryPath: library,
  );
  await morphology.load();
  if (!morphology.isAvailable) throw StateError('${morphology.failure}');
  final provider = ArabicWritingRulesProvider(morphology: morphology);
  final lines = File(corpus).readAsLinesSync();
  var count = 0;
  for (var i = 0; i < lines.length; i++) {
    final result = await provider.check(
      OfficeProofingRequest(
        documentId: 'corpus',
        blockId: 'line-$i',
        revision: 1,
        text: lines[i],
        language: 'ar',
      ),
    );
    for (final f in result.findings) {
      count++;
      stdout.writeln(
        jsonEncode({
          'line': i,
          'rule': f.ruleId,
          'start': f.start,
          'end': f.end,
          'message': f.message,
          'replacements': f.replacements,
        }),
      );
    }
  }
  stderr.writeln(jsonEncode({'sentences': lines.length, 'findings': count}));
  await provider.dispose();
  await morphology.dispose();
}
