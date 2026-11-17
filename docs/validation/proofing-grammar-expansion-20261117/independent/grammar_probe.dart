import 'dart:convert';
import 'dart:io';
import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';

Future<void> main(List<String> args) async {
  final texts = (jsonDecode(File(args.single).readAsStringSync()) as List)
      .cast<String>();
  final provider = GermanWritingRulesProvider();
  final results = <Map<String, Object?>>[];
  for (final text in texts) {
    final result = await provider.check(OfficeProofingRequest(
      documentId: 'independent-review',
      blockId: 'case',
      revision: 1,
      text: text,
      language: 'de-DE',
    ));
    results.add({
      'text': text,
      'status': result.status.name,
      'message': result.message,
      'findings': [
        for (final finding in result.findings)
          {
            'rule': finding.ruleId,
            'text': finding.originalText,
            'start': finding.start,
            'end': finding.end,
            'replacements': finding.replacements,
          },
      ],
    });
  }
  await provider.dispose();
  print(const JsonEncoder.withIndent('  ').convert(results));
}
