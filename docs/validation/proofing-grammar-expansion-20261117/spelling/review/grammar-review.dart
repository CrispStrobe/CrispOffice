import 'dart:convert';
import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';

Future<void> main() async {
  final provider = GermanWritingRulesProvider();
  for (final text in <String>[
    'Ich weiß, dass er gehen kann.',
    'Wenn ich helfen kann, komme ich.',
    'Du sagst, dass du kommen willst.',
    'Wie schön es ist, wenn ich lesen darf.',
    'Ich weiß, dass er gehen wird.',
    'Er ist besser wie erwartet.',
    'Es geht mir besser wie jedes Jahr im Frühling.',
    'Er ist so gut als Lehrer.',
    'Er ist so gut als Arzt.',
    'Ich finde das, was er sagt, gut.',
    'Ich finde das sie liebt.',
    'Wir reden über die Änderung, nach der sie gefragt hat.',
    'Sie sagt, seit ich klein bin, kenne ich das.',
    'Ich freue mich auf die automatisch geänderte Datei.',
  ]) {
    final r = await provider.check(OfficeProofingRequest(documentId:'d',blockId:'p',revision:1,text:text));
    print(jsonEncode({'text':text,'status':r.status.name,'findings':[for(final f in r.findings){'rule':f.ruleId,'text':f.originalText,'replace':f.replacements}]}));
  }
}
