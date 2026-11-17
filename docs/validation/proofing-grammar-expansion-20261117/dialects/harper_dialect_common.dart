import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_harper/quds_proofing_harper.dart';

Future<Map<String, Object?>> probeDialects(HarperProofingProvider provider) async {
  const cases = <(String, String, String, String)>[
    ('en-US', 'en-US', 'color', 'center'),
    ('en-GB', 'en-GB', 'colour', 'centre'),
    ('en-CA', 'en-CA', 'colour', 'centre'),
    ('en-AU', 'en-AU', 'colour', 'centre'),
    ('en-IN', 'en-IN', 'colour', 'centre'),
    ('en-Latn-US-u-co-standard', 'en-US', 'color', 'center'),
    ('en-Latn-GB-u-co-standard', 'en-GB', 'colour', 'centre'),
    ('en-Latn-CA-u-co-standard', 'en-CA', 'colour', 'centre'),
    ('en-Latn-AU-u-co-standard', 'en-AU', 'colour', 'centre'),
    ('en-Latn-IN-u-co-standard', 'en-IN', 'colour', 'centre'),
  ];
  final records = <Map<String, Object?>>[];
  final failures = <String>[];
  var revision = 0;
  Future<void> check((String, String, String, String) item, String phase) async {
    final text = '😀 `This is an test.` https://example.org/an/test name@example.org. The ${item.$3} at the ${item.$4} is vivid. This is an test.';
    const origin = 29;
    final result = await provider.check(OfficeProofingRequest(documentId: 'dialect-review', blockId: '$phase-${item.$1}', revision: ++revision,
      text: text, language: item.$1, startOffset: origin));
    final articles = result.findings.where((f) => f.ruleId == 'harper.AnA').toList();
    final spelling = result.findings.where((f) => f.category == OfficeProofingCategory.spelling && [item.$3, item.$4].contains(f.originalText)).toList();
    final protected = OfficeProofingTextRanges(text);
    final protectedFindings = result.findings.where((f) => protected.overlaps(f.start - origin, f.end - origin)).toList();
    if (result.status != OfficeProofingStatus.success) failures.add('$phase ${item.$1}: ${result.status} ${result.message}');
    if (normalizeProofingLanguage(item.$1) != item.$2) failures.add('$phase ${item.$1}: wrong canonical language');
    if (articles.length != 1 || articles.single.originalText != 'an' || !articles.single.replacements.contains('a') || articles.single.start != origin + text.lastIndexOf('an test') || articles.single.end != origin + text.lastIndexOf('an test') + 2) {
      failures.add('$phase ${item.$1}: incorrect prose article/source mapping');
    }
    if (spelling.isNotEmpty) failures.add('$phase ${item.$1}: valid regional words rejected');
    if (protectedFindings.isNotEmpty) failures.add('$phase ${item.$1}: protected text finding');
    records.add({'phase': phase, 'language': item.$1, 'canonical_language': normalizeProofingLanguage(item.$1), 'status': result.status.name,
      'accepted_regional_words': [item.$3,item.$4], 'findings': [for (final f in result.findings) {'rule': f.ruleId, 'text': f.originalText,'start': f.start,'end': f.end,'replacements':f.replacements}]});
  }
  try {
    for (final item in cases) { await check(item, 'sequential'); }
    await Future.wait([for (final item in cases.reversed) check(item, 'concurrent-reuse')]);
    for (final language in ['en-NZ', 'en-Cyrl', 'en-GB-oxendict', 'de-DE']) {
      final result = await provider.check(OfficeProofingRequest(documentId:'dialect-review',blockId:'unsupported-$language',revision:++revision,text:'This is an test.',language:language));
      if(result.status!=OfficeProofingStatus.unsupported) failures.add('$language should remain unsupported');
      records.add({'phase':'unsupported','language':language,'status':result.status.name});
    }
  } on Object catch(error) {
    failures.add(error.toString());
  } finally {
    await provider.dispose();
  }
  return {'status':failures.isEmpty?'passed':'failed','supported_dialects':5,'tags':10,'successful_requests':records.where((r)=>r['status']=='success').length,
    'unsupported_requests':records.where((r)=>r['status']=='unsupported').length,'records':records,'failures':failures,
    'scope':'Actual provider/runtime: regional valid spelling, grammar correction, canonical aliases, persistent provider reuse, concurrent dispatch, UTF-16 origins, URLs/email/backticks.'};
}
