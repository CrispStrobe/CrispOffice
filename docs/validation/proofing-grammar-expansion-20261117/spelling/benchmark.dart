import 'dart:async';
import 'dart:convert';

import 'package:quds_office_engine/src/proofing/german_spelling.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';

OfficeProofingRequest request(String text) => OfficeProofingRequest(
  documentId: 'timing', blockId: 'paragraph', revision: 1, text: text,
);

String corrupt(String word) {
  final String missing = word.replaceRange(1, 2, '');
  final int swap = missing.length - 3;
  return missing.replaceRange(swap, swap + 2, '${missing[swap + 1]}${missing[swap]}');
}

Future<void> main() async {
  final GermanSpellingProvider provider = GermanSpellingProvider();
  final Stopwatch total = Stopwatch()..start();
  int lastTick = 0;
  int maximumGap = 0;
  int ticks = 0;
  final Timer heartbeat = Timer.periodic(const Duration(milliseconds: 5), (_) {
    final int now = total.elapsedMicroseconds;
    if (now - lastTick > maximumGap) maximumGap = now - lastTick;
    lastTick = now;
    ticks++;
  });
  final Stopwatch phase = Stopwatch()..start();
  await provider.warmUp();
  await Future<void>.delayed(const Duration(milliseconds: 10));
  final Map<String, Object?> output = <String, Object?>{
    'candidate_cap': provider.maximumCandidateChecks,
    'cold_init_ms': phase.elapsedMicroseconds / 1000,
    'cold_max_heartbeat_gap_ms': maximumGap / 1000,
    'cold_heartbeat_ticks': ticks,
  };
  const List<String> correct = <String>[
    'Kommunikation', 'Konfiguration', 'Verarbeitung', 'Rechtschreibung',
    'Wissenschaft', 'Schmetterling', 'Zusammenarbeit', 'Bearbeitung',
    'Entwicklung', 'Verbesserung', 'Texterkennung', 'Dokumentation',
    'Grammatik', 'Silbentrennung', 'Benutzeroberfläche', 'Einstellungen',
    'Veröffentlichung', 'Überprüfung', 'Rückmeldung', 'Geschwindigkeit',
    'Anwendung', 'Speicherplatz', 'Organisation', 'Voraussetzung',
    'Inhaltsverzeichnis',
  ];
  await provider.check(request('hier Komunikazion'));
  final List<String> typos = correct.map(corrupt).toList();
  final List<String> nonsense = <String>[
    for (int i = 0; i < 24; i++)
      'kommuniqxz${String.fromCharCode(97 + i)}',
  ];
  final String paragraph = <String>[...typos, ...nonsense].join(' ');
  final List<Map<String, Object?>> timings = <Map<String, Object?>>[];
  for (int trial = 0; trial < 3; trial++) {
    maximumGap = 0;
    ticks = 0;
    lastTick = total.elapsedMicroseconds;
    phase.reset();
    final OfficeProofingResult result = await provider.check(request(paragraph));
    final double elapsed = phase.elapsedMicroseconds / 1000;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    timings.add(<String, Object?>{
      'check_ms': elapsed,
      'max_heartbeat_gap_ms': maximumGap / 1000,
      'heartbeat_ticks': ticks,
      'findings': result.findings.length,
      'status': result.status.name,
    });
  }
  output['paragraph'] = paragraph;
  output['paragraph_tokens'] = typos.length + nonsense.length;
  output['paragraph_trials'] = timings;
  final List<Map<String, Object?>> recall = <Map<String, Object?>>[];
  for (int i = 0; i < correct.length; i++) {
    final String expected = correct[i];
    final bool listed = (await provider.check(request('hier $expected'))).findings.isEmpty;
    final OfficeProofingResult result = await provider.check(request('hier ${typos[i]}'));
    final List<String> replacements = result.findings.isEmpty
        ? const <String>[] : result.findings.single.replacements;
    recall.add(<String, Object?>{
      'expected': expected, 'typo': typos[i], 'listed_target': listed,
      'expected_rank': replacements.indexOf(expected) + 1,
      'replacements': replacements,
      'findings': result.findings.length,
    });
  }
  output['independent_varied_typos'] = recall;
  output['recalled_in_top5'] = recall.where((r) => (r['expected_rank']! as int) > 0).length;
  output['listed_targets'] = recall.where((r) => r['listed_target'] == true).length;
  output['total_ms'] = total.elapsedMicroseconds / 1000;
  heartbeat.cancel();
  await provider.dispose();
  print(const JsonEncoder.withIndent('  ').convert(output));
}
