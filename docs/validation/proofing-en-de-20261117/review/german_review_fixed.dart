import 'dart:convert';
import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';

Future<void> main() async {
  final p = GermanWritingRulesProvider();
  const negatives = <String>[
    'Weil ich Essen bestelle, bleibe ich hier.',
    'Wenn du Essen brauchst, ruf an.',
    'Dass ich Lesen liebe, weißt du.',
    'Ob du Lernen magst, ist deine Sache.',
    'Mit dem Du kommen wir gut zurecht.',
    'Vom Ich gehen wir zum Wir.',
    'Dem Du gibt man eine neue Bedeutung.',
  ];
  const positives = <String,String>{
    'Du geht nach Hause.':'gehst',
    'ich essen gern.':'esse',
    'du lesen gern.':'liest',
    'wir nimmst ein Buch.':'nehmen',
    'ICH NIMMST EIN BUCH.':'NEHME',
    'ICH HAST EIN BUCH.':'HABE',
  };
  var passed=0;
  for(final text in negatives) {
    final r=await p.check(OfficeProofingRequest(documentId:'d',blockId:'p',revision:0,text:text,startOffset:17));
    if(r.findings.isNotEmpty) throw StateError('False positive remains: $text');
    passed++;
  }
  for(final entry in positives.entries) {
    final r=await p.check(OfficeProofingRequest(documentId:'d',blockId:'p',revision:0,text:entry.key,startOffset:17));
    if(r.findings.length!=1 || r.findings.single.replacements.single!=entry.value) throw StateError('Positive regression: ${entry.key}');
    passed++;
  }
  const source='😀 ich\u00ad \u00adha\u00adst\u00ad hier.';
  final r=await p.check(OfficeProofingRequest(documentId:'d',blockId:'p',revision:0,text:source,startOffset:17));
  if(r.findings.length!=1 || r.findings.single.originalText!='ha\u00adst' || r.findings.single.start!=26 || r.findings.single.end!=31 || r.findings.single.replacements.single!='habe') throw StateError('Source mapping regression');
  passed++;
  print(jsonEncode({'passed':passed,'negative_controls':negatives.length,'positive_controls':positives.length,'source_mapping_controls':1}));
}
