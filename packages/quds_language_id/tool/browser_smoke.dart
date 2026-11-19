// Browser smoke of the real web transport (dart2js) and policy: fetches the
// bundled model and a corpus from the serving origin, opens the worker,
// checks known answers and measures load and per-paragraph latency. Driven
// by tool/browser_smoke.py, which serves the files and collects the report.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:quds_language_id/quds_language_id.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:web/web.dart' as web;

Future<Uint8List> _bytes(String path) async {
  final response = await web.window.fetch(path.toJS).toDart;
  if (!response.ok) throw StateError('GET $path: ${response.status}');
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

Future<void> _report(Map<String, Object?> report) async {
  await web.window
      .fetch(
        '/result'.toJS,
        web.RequestInit(method: 'POST', body: jsonEncode(report).toJS),
      )
      .toDart;
}

Future<void> main() async {
  final report = <String, Object?>{'userAgent': web.window.navigator.userAgent};
  try {
    final identifier = Cld3LanguageIdentifier(
      model: await _bytes('/model/cld3-f16.gguf'),
      workerUrl: Uri.base.resolve('/web/language_id_worker.mjs'),
    );
    final load = Stopwatch()..start();
    await identifier.load();
    report['load_ms'] = load.elapsedMicroseconds / 1000;
    report['available'] = identifier.isAvailable;
    report['failure'] = identifier.failure?.toString();
    final smoke = await identifier.detectBatch([
      'Bonjour le monde',
      'שלום עולם',
      'Das ist ein ganz normaler deutscher Satz über das Wetter.',
    ]);
    report['smoke'] = [for (final r in smoke) r.first.language];
    final detector = ParagraphLanguageDetector(identifier, cacheSize: 0);
    final mixed = await detector.detect(
      'Der Bericht wurde gestern veröffentlicht und sorgte für Aufsehen. '
      'وقد نشر التقرير أمس وأثار ضجة كبيرة في الأوساط السياسية.',
    );
    report['mixed'] = [for (final s in mixed.segments) s.language];

    final corpus = utf8
        .decode(await _bytes('/corpus.txt'))
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final times = <double>[];
    for (final paragraph in corpus) {
      final watch = Stopwatch()..start();
      await detector.detect(paragraph);
      times.add(watch.elapsedMicroseconds / 1000);
    }
    times.sort();
    report['paragraphs'] = times.length;
    report['single_mean_ms'] = times.reduce((a, b) => a + b) / times.length;
    report['single_p50_ms'] = times[times.length ~/ 2];
    report['single_p95_ms'] =
        times[min(times.length - 1, (times.length * 0.95).floor())];
    final batch = Stopwatch()..start();
    await detector.detectAll(corpus);
    report['batched_per_paragraph_ms'] =
        batch.elapsedMicroseconds / 1000 / corpus.length;
    await identifier.dispose();
    final ok =
        identifier.failure == null &&
        jsonEncode(report['smoke']) == jsonEncode(['fr', 'he', 'de']) &&
        jsonEncode(report['mixed']) == jsonEncode(['de', 'ar']);
    report['status'] = ok ? 'passed' : 'failed';
  } on Object catch (error, stack) {
    report['status'] = 'failed';
    report['error'] = '$error\n$stack';
  }
  await _report(report);
}
