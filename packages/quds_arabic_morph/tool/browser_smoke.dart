// Browser smoke of the real web transport (dart2js): fetches the verified
// proofing-bin bundle and a corpus from the serving origin, opens the bundled
// worker, checks known analyses and measures load and throughput. Driven by
// tool/browser_smoke.py, which serves the files and collects the report.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:web/web.dart' as web;

Future<Uint8List> _bytes(String path) async {
  final response = await web.window.fetch(path.toJS).toDart;
  if (!response.ok) throw StateError('GET $path: ${response.status}');
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

/// Chrome's page JS heap in MB (`performance.memory`, non-standard); the
/// worker's Wasm heap is reported separately by the worker.
int? _pageHeapMb() {
  final memory = (web.window.performance as JSObject).getProperty<JSObject?>(
    'memory'.toJS,
  );
  final used = memory?.getProperty<JSNumber?>('usedJSHeapSize'.toJS);
  return used == null ? null : used.toDartInt ~/ (1024 * 1024);
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
    final files = {
      for (final artifact in camelMorphMsaProofingBin.files)
        artifact.file: await _bytes('/bundle/${artifact.file}'),
    };
    final morphology = CamelArabicMorphology(
      database: MorphDatabaseBytes.verified(camelMorphMsaProofingBin, files),
      workerUrl: Uri.base.resolve('/web/arabic_morph_worker.mjs'),
    );
    report['page_heap_mb_with_bundle_bytes'] = _pageHeapMb();
    final load = Stopwatch()..start();
    await morphology.load();
    load.stop();
    report['load_seconds'] = load.elapsedMilliseconds / 1000;
    report['available'] = morphology.isAvailable;
    report['page_heap_mb_after_load'] = _pageHeapMb();
    report['failure'] = morphology.failure?.toString();
    report['info'] = morphology.info;
    // The transferred buffers now belong to the worker.
    report['database_bytes_left_in_page'] =
        files[camelMorphMsaProofingBin.database.file]!.lengthInBytes;

    final known = await morphology.analyzeWords(['كتبوا', 'والمدرسة']);
    report['katabu_verb_plural'] = known['كتبوا']!.any(
      (a) => a['lex'] == 'كَتَب' && a['pos'] == 'verb' && a['num'] == 'p',
    );
    report['walmadrasa_noun_wa_al'] = known['والمدرسة']!.any(
      (a) =>
          a['pos'] == 'noun' && a['prc2'] == 'wa_conj' && a['prc0'] == 'Al_det',
    );

    final corpus = utf8.decode(await _bytes('/corpus.txt'));
    final arabic = RegExp(r'[ؠ-يٮ-ۓ]');
    final word = RegExp(r'[\p{L}\p{M}]+', unicode: true);
    final words = {
      for (final line in corpus.split('\n'))
        for (final match in word.allMatches(line))
          if (arabic.hasMatch(match[0]!)) match[0]!,
    }.toList();
    final cold = Stopwatch()..start();
    final result = await morphology.analyzeWords(words);
    cold.stop();
    report['distinct_words'] = words.length;
    report['analyzed_words'] = result.values.where((v) => v.isNotEmpty).length;
    report['analyses'] = result.values.fold<int>(0, (s, v) => s + v.length);
    report['cold_seconds'] = cold.elapsedMilliseconds / 1000;
    report['page_heap_mb_with_cached_analyses'] = _pageHeapMb();
    report['words_per_second'] =
        (words.length / cold.elapsedMilliseconds * 1000).round();
    await morphology.dispose();
    final passed =
        morphology.failure == null &&
        report['available'] == true &&
        report['katabu_verb_plural'] == true &&
        report['walmadrasa_noun_wa_al'] == true &&
        (report['analyzed_words']! as int) > 7000;
    report['status'] = passed ? 'passed' : 'failed';
  } on Object catch (error, stack) {
    report['status'] = 'failed';
    report['error'] = '$error\n$stack';
  }
  await _report(report);
}
