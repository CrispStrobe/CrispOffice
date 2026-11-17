// SPDX-License-Identifier: MIT
// Evaluation-only in-process ORT backend, never registered by either app.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'incremental_quality.dart';

Future<String> fileHash(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

final class NativeOrtFactory implements GectorBackendFactory {
  const NativeOrtFactory(
    this.directory,
    this.shim,
    this.shimHash,
    this.ort,
    this.ortHash,
  );
  final String directory, shim, shimHash, ort, ortHash;
  @override
  Future<GectorBackend> open(GectorModelArtifact artifact) async {
    if (await fileHash(shim) != shimHash ||
        await fileHash(ort) != ortHash ||
        await fileHash('$directory/${artifact.file}') != artifact.sha256) {
      throw StateError('Native evaluation artifact changed');
    }
    return NativeOrtBackend(
      DynamicLibrary.open(shim),
      '$directory/${artifact.file}',
      artifact,
    );
  }
}

typedef _OpenN = Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, UintPtr);
typedef _OpenD = Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, int);
typedef _ForwardN =
    Int32 Function(
      Pointer<Void>,
      Pointer<Int64>,
      Int64,
      Pointer<Float>,
      UintPtr,
      Pointer<Float>,
      UintPtr,
      Pointer<Utf8>,
      UintPtr,
    );
typedef _ForwardD =
    int Function(
      Pointer<Void>,
      Pointer<Int64>,
      int,
      Pointer<Float>,
      int,
      Pointer<Float>,
      int,
      Pointer<Utf8>,
      int,
    );
typedef _CloseN = Void Function(Pointer<Void>);
typedef _CloseD = void Function(Pointer<Void>);

final class NativeOrtBackend implements GectorBackend {
  NativeOrtBackend(
    DynamicLibrary library,
    String model,
    GectorModelArtifact artifact,
  ) : identity = GectorBackendIdentity(
        artifactSha256: artifact.sha256,
        sourceModelSha256: artifact.sourceModelSha256,
      ),
      _forward = library.lookupFunction<_ForwardN, _ForwardD>(
        'quds_ort_forward',
      ),
      _close = library.lookupFunction<_CloseN, _CloseD>('quds_ort_close') {
    final path = model.toNativeUtf8();
    final error = calloc<Uint8>(1024).cast<Utf8>();
    try {
      _context = library.lookupFunction<_OpenN, _OpenD>('quds_ort_open')(
        path,
        error,
        1024,
      );
      if (_context == nullptr) {
        throw StateError('ORT admission: ${error.toDartString()}');
      }
    } finally {
      calloc.free(error);
      malloc.free(path);
    }
  }
  @override
  final GectorBackendIdentity identity;
  final _ForwardD _forward;
  final _CloseD _close;
  late Pointer<Void> _context;
  @override
  Future<GectorLogits> forward(GectorPreparedInput input) async {
    if (_context == nullptr) throw StateError('ORT disposed');
    final n = input.tokenCount;
    final ids = calloc<Int64>(n);
    final labels = calloc<Float>(n * 5000);
    final detection = calloc<Float>(n * 2);
    final error = calloc<Uint8>(1024).cast<Utf8>();
    try {
      ids.asTypedList(n).setAll(0, input.inputIds);
      final status = _forward(
        _context,
        ids,
        n,
        labels,
        n * 5000,
        detection,
        n * 2,
        error,
        1024,
      );
      if (status != 0) throw StateError('ORT forward: ${error.toDartString()}');
      final result = GectorLogits(
        tokenCount: n,
        labels: Float32List.fromList(labels.asTypedList(n * 5000)),
        detection: Float32List.fromList(detection.asTypedList(n * 2)),
      );
      result.validate(input, 5000);
      return result;
    } finally {
      calloc.free(ids);
      calloc.free(labels);
      calloc.free(detection);
      calloc.free(error);
    }
  }

  @override
  Future<void> dispose() async {
    if (_context != nullptr) {
      _close(_context);
      _context = nullptr;
    }
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 7) {
    throw ArgumentError(
      'Expected bundle shim shim-sha256 ort-library ort-sha256 cases-json new-output-json',
    );
  }
  final output = File(arguments[6]);
  if (output.existsSync()) throw StateError('Preserve existing evidence');
  final cases = parseQualityCases(
    jsonDecode(await File(arguments[5]).readAsString()),
  );
  final clock = Stopwatch()..start();
  final artifact = GectorModelArtifact(
    file: 'model.onnx',
    sha256: gectorSourceModelSha256,
    bytes: 452972247,
  );
  final bundle = await GectorVerifiedBundle.load(
    read: (name) => File('${arguments[0]}/$name').openRead(),
    artifact: artifact,
  );
  final model = await GectorProofingProvider.load(
    bundle: bundle,
    backendFactory: NativeOrtFactory(
      arguments[0],
      arguments[1],
      arguments[2],
      arguments[3],
      arguments[4],
    ),
    lexiconFactory: const GectorGermanLexiconFactory(),
  );
  final modelService = OfficeProofingService(providers: [model]);
  final writing = OfficeProofingService(
    providers: [GermanWritingRulesProvider()],
  );
  final spelling = GermanSpellingProvider();
  await spelling.warmUp();
  // Exact current editor default provider order; do not choose by gold output.
  final ordinary = OfficeProofingService(
    providers: [GermanWritingRulesProvider(), spelling],
  );
  final setup = clock.elapsedMicroseconds / 1000;
  final rows = <Map<String, Object?>>[];
  try {
    for (final c in cases) {
      final request = OfficeProofingRequest(
        documentId: 'native-evaluation',
        blockId: c.id,
        revision: 1,
        text: c.input,
        language: c.locale,
        startOffset: 7,
      );
      final begin = clock.elapsedMicroseconds;
      final primary = await ordinary.check(request);
      final secondary = await modelService.check(request);
      final reports = {
        'writing_only': await writing.check(request),
        'deterministic': primary,
        'model_only': secondary,
        'combined': mergeOfficeProofingReports(
          primary: primary,
          secondary: secondary,
        ),
      };
      rows.add({
        ...c.toJson(),
        'milliseconds': (clock.elapsedMicroseconds - begin) / 1000,
        'lanes': {
          for (final lane in reports.entries)
            lane.key: projectQualityReport(lane.value).toJson(c.expected),
        },
      });
    }
  } finally {
    await ordinary.dispose();
    await writing.dispose();
    await modelService.dispose();
  }
  final summary = <String, Object?>{};
  for (final lane in qualityLanes) {
    Map<String, Object?> projection(Map<String, Object?> r) =>
        (r['lanes']! as Map<String, Object?>)[lane]! as Map<String, Object?>;
    final errors = rows.where((r) => r['kind'] == 'error');
    final clean = rows.where((r) => r['kind'] == 'clean');
    summary[lane] = {
      'errors': errors.length,
      'exact_errors': errors
          .where((r) => projection(r)['exact_expected'] == true)
          .length,
      'clean': clean.length,
      'clean_changed': clean
          .where((r) => projection(r)['changed'] == true)
          .length,
      'clean_flagged': clean
          .where((r) => projection(r)['flagged'] == true)
          .length,
    };
  }
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'scope': 'In-process F32 ONNX Runtime C API evaluation with actual Quds worker, guards and editor-default projection. No daemon, pipes, subprocess inference or app registration; not shipping CrispEmbed precision qualification.', 'model_sha256': gectorSourceModelSha256, 'shim_sha256': arguments[2], 'ort_sha256': arguments[4], 'cases_sha256': await fileHash(arguments[5]), 'setup_milliseconds': setup, 'process_max_rss_bytes': ProcessInfo.maxRss, 'projection_policy': qualityProjectionPolicy, 'summary': summary, 'cases': rows})}\n',
  );
  stdout.writeln(jsonEncode(summary));
}
