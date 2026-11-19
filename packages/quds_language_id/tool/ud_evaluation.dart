// Evaluates the bundled CLD3 identifier and the paragraph policy on UD r2.14
// test sentences (`# text` lines; evaluation only, never shipped).
//
//   dart run tool/ud_evaluation.dart <library> <ud dir> [out.json]
//
// <ud dir> holds the UD r2.14 test files named below (download them from
// github.com/UniversalDependencies/UD_<Treebank>/raw/r2.14/<file>). The
// report lists raw CLD3 top-1 accuracy, the policy's precision/coverage for
// a threshold sweep, length buckets, confusion pairs, mixed-script
// paragraphs, latency and memory.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:quds_language_id/quds_language_id.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const corpora = <String, List<String>>{
  'en': ['en_ewt-ud-test.conllu'],
  'de': ['de_gsd-ud-test.conllu'],
  'fr': ['fr_gsd-ud-test.conllu'],
  'ar': ['ar_pud-ud-test.conllu'],
  'he': ['he_htb-ud-test.conllu'],
  'la': ['la_perseus-ud-test.conllu', 'la_proiel-ud-test.conllu'],
  'es': ['es_gsd-ud-test.conllu'],
  'it': ['it_isdt-ud-test.conllu'],
};

String bucket(String text) => text.length < 20
    ? '<20'
    : text.length <= 50
    ? '20-50'
    : '>50';

double percentile(List<double> sorted, double p) =>
    sorted[min(sorted.length - 1, (p * sorted.length).floor())];

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: ud_evaluation.dart <library> <ud dir> [out.json]');
    exit(64);
  }
  final files = <String, String>{};
  final sentences = <String, List<String>>{};
  for (final MapEntry(key: language, value: names) in corpora.entries) {
    for (final name in names) {
      final bytes = File('${args[1]}/$name').readAsBytesSync();
      files[name] = sha256.convert(bytes).toString();
      sentences.putIfAbsent(language, () => []).addAll([
        for (final line in const LineSplitter().convert(utf8.decode(bytes)))
          if (line.startsWith('# text = ')) line.substring(9).trim(),
      ]);
    }
  }

  final rssBefore = ProcessInfo.currentRss;
  final model = File('assets/cld3-f16.gguf').readAsBytesSync();
  final identifier = Cld3LanguageIdentifier(
    model: model,
    nativeLibraryPath: args[0],
  );
  final loadWatch = Stopwatch()..start();
  await identifier.load();
  loadWatch.stop();
  if (!identifier.isAvailable) throw StateError('${identifier.failure}');
  final rssLoaded = ProcessInfo.currentRss;

  // Raw CLD3 on the dominant script segment of every sentence.
  final rows =
      <
        ({
          String gold,
          String text,
          ScriptSegment main,
          List<LanguageGuess> guesses,
        })
      >[];
  for (final MapEntry(key: gold, value: texts) in sentences.entries) {
    final mains = <ScriptSegment?>[];
    final queries = <String>[];
    for (final text in texts) {
      final segments = scriptSegments(text);
      final main = segments.isEmpty
          ? null
          : segments.reduce((a, b) => b.letters > a.letters ? b : a);
      mains.add(main);
      if (main != null) queries.add(text.substring(main.start, main.end));
    }
    final answers = await identifier.detectBatch(queries);
    var q = 0;
    for (var i = 0; i < texts.length; i++) {
      final main = mains[i];
      if (main == null) continue;
      rows.add((gold: gold, text: texts[i], main: main, guesses: answers[q++]));
    }
  }

  final raw = <String, Map<String, Object>>{};
  final confusions = <String, int>{};
  for (final gold in corpora.keys) {
    final mine = rows.where((r) => r.gold == gold).toList();
    final byBucket = <String, List<int>>{};
    for (final r in mine) {
      final top = r.guesses.isEmpty ? '-' : r.guesses.first.language;
      final ok = top == gold;
      (byBucket[bucket(r.text)] ??= [0, 0])
        ..[0] += ok ? 1 : 0
        ..[1] += 1;
      if (!ok) confusions['$gold→$top'] = (confusions['$gold→$top'] ?? 0) + 1;
    }
    final correct = byBucket.values.fold(0, (a, b) => a + b[0]);
    raw[gold] = {
      'sentences': mine.length,
      'top1_accuracy': correct / mine.length,
      'buckets': {
        for (final b in ['<20', '20-50', '>50'])
          if (byBucket[b] != null)
            b: {
              'n': byBucket[b]![1],
              'accuracy': byBucket[b]![0] / byBucket[b]![1],
            },
      },
    };
  }

  // The policy with a sweep of thresholds. Two questions per sentence:
  // * harm: with the sentence's own language as the document default, does
  //   detection wrongly take over (routing the text to other providers)?
  // * benefit: with another corpus language of the same script as the
  //   default, does detection correctly switch to the sentence's language?
  // Abstaining keeps the document language, which is neither.
  Map<String, Object> policyScore(LanguageDetectionPolicy policy) {
    final perLanguage = <String, Object>{};
    var wrongTotal = 0, rowsTotal = 0, switchedTotal = 0, crossTotal = 0;
    for (final gold in corpora.keys) {
      final mine = rows.where((r) => r.gold == gold);
      final others = [
        for (final other in corpora.keys)
          if (other != gold &&
              languageScript(other).isComplex == languageScript(gold).isComplex)
            other,
      ];
      var detected = 0, wrong = 0, n = 0, switched = 0, cross = 0;
      final buckets = <String, List<int>>{};
      final confusion = <String, int>{};
      for (final r in mine) {
        final decision = policy.decide(
          r.main,
          policy.needsClassifier(r.main) ? r.guesses : const [],
        );
        final b = buckets[bucket(r.text)] ??= [0, 0, 0];
        n++;
        b[2]++;
        if (decision.language == gold) {
          detected++;
          b[0]++;
        }
        final kept = resolveDetectedLanguage(
          current: gold,
          currentIsDefault: true,
          detection: decision,
          keepDefaultConfidence: policy.keepDefaultConfidence,
        );
        if (primaryLanguageSubtag(kept!) != gold) {
          wrong++;
          b[1]++;
          confusion[kept] = (confusion[kept] ?? 0) + 1;
        }
        for (final other in others) {
          cross++;
          final routed = resolveDetectedLanguage(
            current: other,
            currentIsDefault: true,
            detection: decision,
            keepDefaultConfidence: policy.keepDefaultConfidence,
          );
          if (primaryLanguageSubtag(routed!) == gold) switched++;
        }
      }
      wrongTotal += wrong;
      rowsTotal += n;
      switchedTotal += switched;
      crossTotal += cross;
      perLanguage[gold] = {
        'n': n,
        'detected': detected,
        'detected_rate': detected / n,
        'wrong_override': wrong,
        'wrong_override_rate': wrong / n,
        'wrong_override_to': confusion,
        'switch_rate': cross == 0 ? null : switched / cross,
        'buckets': {
          for (final e in buckets.entries)
            e.key: {
              'n': e.value[2],
              'detected': e.value[0],
              'wrong_override': e.value[1],
            },
        },
      };
    }
    return {
      'min_letters': policy.minLetters,
      'min_confidence': policy.minConfidence,
      'keep_default_confidence': policy.keepDefaultConfidence,
      'wrong_override_rate': wrongTotal / rowsTotal,
      'wrong_override': wrongTotal,
      'switch_rate': switchedTotal / crossTotal,
      'languages': perLanguage,
    };
  }

  final sweep = [
    for (final letters in [0, 12, 20, 30])
      for (final confidence in [0.7, 0.9, 0.95, 0.99])
        for (final keep in [1.1, 0.01])
          policyScore(
            LanguageDetectionPolicy(
              minLetters: letters,
              minConfidence: confidence,
              complexScriptMinLetters: letters,
              complexScriptMinConfidence: confidence,
              keepDefaultConfidence: keep,
            ),
          ),
  ];
  const chosen = LanguageDetectionPolicy();
  final chosenScore = policyScore(chosen);

  // Mixed-script paragraphs: a Latin-script sentence followed by an Arabic-
  // or Hebrew-script one. Each script segment must get its own language.
  final detector = ParagraphLanguageDetector(identifier, cacheSize: 0);
  final mixedPairs = [
    ('de', 'ar'),
    ('en', 'ar'),
    ('fr', 'he'),
    ('en', 'he'),
    ('la', 'ar'),
  ];
  final mixed = <String, Object>{};
  for (final (latin, complex) in mixedPairs) {
    final a = sentences[latin]!, b = sentences[complex]!;
    final count = min(200, min(a.length, b.length));
    final paragraphs = [for (var i = 0; i < count; i++) '${a[i]} ${b[i]}'];
    final results = await detector.detectAll(paragraphs);
    var latinCorrect = 0, latinWrong = 0, complexCorrect = 0, complexWrong = 0;
    for (final result in results) {
      DetectedSegment? largest(bool isComplex) {
        DetectedSegment? best;
        for (final s in result.segments) {
          if (s.script.isComplex != isComplex) continue;
          if (best == null || s.end - s.start > best.end - best.start) best = s;
        }
        return best;
      }

      final l = largest(false)?.language;
      final c = largest(true)?.language;
      if (l == latin) {
        latinCorrect++;
      } else if (l != null) {
        latinWrong++;
      }
      if (c == complex) {
        complexCorrect++;
      } else if (c != null) {
        complexWrong++;
      }
    }
    mixed['$latin+$complex'] = {
      'paragraphs': count,
      'latin_correct': latinCorrect,
      'latin_wrong': latinWrong,
      'latin_abstained': count - latinCorrect - latinWrong,
      'complex_correct': complexCorrect,
      'complex_wrong': complexWrong,
    };
  }

  // Latency: one paragraph per call through the policy and the worker
  // isolate (what proofing does when a paragraph changes), and batched.
  final single = <double>[];
  final all = [for (final r in rows) r.text];
  final probe = ParagraphLanguageDetector(identifier, cacheSize: 0);
  for (final text in all) {
    final watch = Stopwatch()..start();
    await probe.detect(text);
    single.add(watch.elapsedMicroseconds / 1000);
  }
  single.sort();
  final batchWatch = Stopwatch()..start();
  await probe.detectAll(all);
  batchWatch.stop();
  final rssAfter = ProcessInfo.currentRss;
  await identifier.dispose();

  final report = {
    'corpus': 'Universal Dependencies r2.14 test `# text` sentences',
    'files_sha256': files,
    'model_sha256': Cld3Model.sha256,
    'library': args[0],
    'library_bytes': File(args[0]).lengthSync(),
    'host':
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}; ${Platform.numberOfProcessors} cpus',
    'raw_cld3_top1': raw,
    'confusions': Map.fromEntries(
      (confusions.entries.toList()..sort((a, b) => b.value - a.value)).take(30),
    ),
    'policy_chosen': chosenScore,
    'policy_sweep': [
      for (final s in sweep)
        {
          'min_letters': s['min_letters'],
          'min_confidence': s['min_confidence'],
          'keep_default_confidence': s['keep_default_confidence'],
          'wrong_override_rate': s['wrong_override_rate'],
          'wrong_override': s['wrong_override'],
          'switch_rate': s['switch_rate'],
        },
    ],
    'mixed_script': mixed,
    'latency_ms': {
      'paragraphs': single.length,
      'single_mean': single.reduce((a, b) => a + b) / single.length,
      'single_p50': percentile(single, 0.5),
      'single_p95': percentile(single, 0.95),
      'single_max': single.last,
      'batched_per_paragraph':
          batchWatch.elapsedMicroseconds / 1000 / all.length,
      'load': loadWatch.elapsedMicroseconds / 1000,
    },
    'rss_bytes': {'before': rssBefore, 'loaded': rssLoaded, 'after': rssAfter},
  };
  final json = const JsonEncoder.withIndent('  ').convert(report);
  if (args.length > 2) File(args[2]).writeAsStringSync('$json\n');
  stdout.writeln(json);
}
