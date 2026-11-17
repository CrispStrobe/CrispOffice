import 'dart:convert';
import 'package:quds_office_engine/quds_office_engine.dart';

Future<void> main() async {
  final p = GermanWritingRulesProvider();
  for (final text in <String>[
    'Weil ich Essen bestelle, bleibe ich hier.',
    'Wenn du Essen brauchst, ruf an.',
    'Dass ich Lesen liebe, weißt du.',
    'Ob du Lernen magst, ist deine Sache.',
    'Mit dem Du kommen wir gut zurecht.',
    'Vom Ich gehen wir zum Wir.',
    'Mit meinem Ich komme ich zurecht.',
    'Dem Du gibt man eine neue Bedeutung.',
    'Du geht nach Hause.',
    'ICH ESSEN GERN.',
    'Ich habe ihr seit sehr langer Zeit geholfen.',
    'Ihr seit hier angekommenes Gepäck ist noch nicht da.',
    'Meine Freundin und ich essen hier.',
    'Ich helfe ihr seit hier alle so freundlich sind.',
    '😀 ich\u00ad \u00adha\u00adst\u00ad hier.',
    '😀 ,\u00ad\u0308noch ich hast hier.',
    'https://example.invalid/\u0027ich hast',
    'Huas@bä\u0308r.de ich hast',
  ]) {
    final r = await p.check(OfficeProofingRequest(documentId:'d',blockId:'p',revision:0,text:text,startOffset:17));
    print(jsonEncode({'text':text,'findings':r.findings.map((f)=>{'rule':f.ruleId,'text':f.originalText,'start':f.start,'end':f.end,'replacements':f.replacements}).toList()}));
  }
  for(final text in <String>[
    'Huas@ba\u0308r.de',
    'https://example.invalid/\u0027Silbentrennung',
    'https://example.invalid/a\u0027/Silbentrennung',
    'Silbentrennung\u203fSchifffahrt',
    'dictionary\u203fhyphenation',
    'ht\u00adtps://example.invalid/Silbentrennung',
  ]) {
    final ranges=OfficeProofingTextRanges(text);
    print(jsonEncode({'rangesText':text,'ranges':ranges.ranges.map((r)=>text.substring(r.start,r.end)).toList(),'germanHyphens':GermanHyphenator.breakOffsets(text,language:'de-DE'),'englishHyphens':EnglishHyphenator.breakOffsets(text,language:'en-US')}));
  }
}
