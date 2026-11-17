// SPDX-License-Identifier: MIT
// ignore_for_file: depend_on_referenced_packages
// Evaluation-only ONNX transport. Not registered or shipped by either app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_gector/quds_proofing_gector.dart';

final class OrtFactory implements GectorBackendFactory {
  const OrtFactory(this.directory, this.python, this.server);
  final String directory;
  final String python;
  final String server;
  @override
  Future<GectorBackend> open(GectorModelArtifact artifact) async {
    final child = await Process.start(
      python,
      [server, '$directory/${artifact.file}'],
      environment: {'OMP_NUM_THREADS': '2', 'OPENBLAS_NUM_THREADS': '1'},
    );
    final errors = child.stderr.transform(utf8.decoder).listen(stderr.write);
    final lines = StreamIterator(
      child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    try {
      if (!await lines.moveNext().timeout(const Duration(seconds: 30))) {
        throw StateError('ORT failed to start');
      }
      final ready = jsonDecode(lines.current) as Map<String, dynamic>;
      if (ready['sha256'] != artifact.sha256 || ready['ready'] != true) {
        throw StateError('ORT model identity mismatch');
      }
      return OrtBackend(
        child,
        lines,
        errors,
        GectorBackendIdentity(
          artifactSha256: artifact.sha256,
          sourceModelSha256: artifact.sourceModelSha256,
        ),
      );
    } catch (_) {
      child.kill();
      await lines.cancel();
      await errors.cancel();
      rethrow;
    }
  }
}

final class OrtBackend implements GectorBackend {
  OrtBackend(this.child, this.lines, this.errors, this.identity);
  final Process child;
  final StreamIterator<String> lines;
  final StreamSubscription<String> errors;
  @override
  final GectorBackendIdentity identity;
  @override
  Future<GectorLogits> forward(GectorPreparedInput input) async {
    child.stdin.writeln(
      jsonEncode({'ids': input.inputIds, 'mask': input.attentionMask}),
    );
    await child.stdin.flush();
    if (!await lines.moveNext().timeout(const Duration(seconds: 12))) {
      throw StateError('ORT transport closed');
    }
    final row = jsonDecode(lines.current) as Map<String, dynamic>;
    if (row.containsKey('error')) throw StateError(row['error'] as String);
    Float32List values(String key) {
      final b = base64Decode(row[key] as String);
      return Float32List.fromList(
        b.buffer.asFloat32List(b.offsetInBytes, b.lengthInBytes ~/ 4),
      );
    }

    final logits = GectorLogits(
      tokenCount: input.tokenCount,
      labels: values('labels'),
      detection: values('detection'),
    );
    logits.validate(input, 5000);
    return logits;
  }

  @override
  Future<void> dispose() async {
    await child.stdin.close();
    try {
      await child.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      child.kill();
    }
    await lines.cancel();
    await errors.cancel();
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    throw ArgumentError(
      'Expected: bundle-directory python-executable cases-json output-json',
    );
  }
  final directory = arguments[0];
  final python = arguments[1];
  final cases =
      jsonDecode(await File(arguments[2]).readAsString()) as List<dynamic>;
  final server = File.fromUri(
    Platform.script.resolve('onnx_probe_backend.py'),
  ).path;
  final artifact = GectorModelArtifact(
    file: 'model.onnx',
    sha256: gectorSourceModelSha256,
    bytes: 452972247,
  );
  final bundle = await GectorVerifiedBundle.load(
    read: (name) => File('$directory/$name').openRead(),
    artifact: artifact,
  );
  final provider = await GectorProofingProvider.load(
    bundle: bundle,
    backendFactory: OrtFactory(directory, python, server),
    lexiconFactory: const GectorGermanLexiconFactory(),
  );
  final service = OfficeProofingService(providers: [provider]);
  final rows = <Map<String, dynamic>>[];
  try {
    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      final text = c['input'] as String;
      final clock = Stopwatch()..start();
      final request = OfficeProofingRequest(
        documentId: 'evaluation',
        blockId: c['id'] as String,
        revision: 0,
        text: text,
        language: (c['locale'] as String?) ?? 'de-DE',
        startOffset: 7,
      );
      final report = await service.check(request);
      final result = report.results.single;
      var corrected = text;
      final findings = result.findings.toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      for (final f in findings.reversed) {
        corrected = corrected.replaceRange(
          f.start - 7,
          f.end - 7,
          f.replacements.single,
        );
      }
      rows.add({
        ...c,
        'status': result.status.name,
        'output': corrected,
        'milliseconds': clock.elapsedMicroseconds / 1000,
        'exact': corrected == (c['expected'] ?? text),
        'findings': [
          for (final f in findings)
            {
              'start': f.start,
              'end': f.end,
              'original': f.originalText,
              'replacement': f.replacements.single,
            },
        ],
      });
      stdout.writeln('${c['id']}: ${result.status.name} -> $corrected');
    }
  } finally {
    await service.dispose();
  }
  final errors = rows.where((r) => r['kind'] == 'error').toList();
  final clean = rows.where((r) => r['kind'] == 'clean').toList();
  final summary = {
    'error_cases': errors.length,
    'exact_errors': errors.where((r) => r['exact'] == true).length,
    'clean_supported': clean.where((r) => r['status'] == 'success').length,
    'clean_supported_changed': clean
        .where((r) => r['status'] == 'success' && r['output'] != r['input'])
        .length,
    'unsupported': rows.where((r) => r['status'] == 'unsupported').length,
    'operational_failures': rows
        .where((r) => r['status'] != 'success' && r['status'] != 'unsupported')
        .length,
  };
  await File(arguments[3]).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'scope': 'Evaluation-only native ONNX F32 transport through the unchanged Quds persistent worker, tokenizer, decoder, guards and lexicon. Not CrispEmbed FFI or shipping-precision qualification.', 'model_sha256': gectorSourceModelSha256, 'dart_max_rss_bytes': ProcessInfo.maxRss, 'summary': summary, 'cases': rows})}\n',
  );
  stdout.writeln('SUMMARY ${jsonEncode(summary)}');
  if (summary['operational_failures'] != 0) exitCode = 1;
}
