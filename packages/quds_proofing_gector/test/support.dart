import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_proofing_gector/quds_proofing_gector.dart';

final class TestBundle {
  TestBundle(this.files, this.bundle);
  final Map<String, Uint8List> files;
  final GectorVerifiedBundle bundle;
  static Future<TestBundle> load() async {
    final data = gzip.decode(
      await File('test/fixtures/proofbird_metadata.json.gz').readAsBytes(),
    );
    final Object? raw = jsonDecode(utf8.decode(data));
    if (raw is! Map<String, Object?> || raw['files'] is! Map<String, Object?>) {
      throw const FormatException('Invalid fixture');
    }
    final files = <String, Uint8List>{};
    for (final entry in (raw['files']! as Map<String, Object?>).entries) {
      files[entry.key] = base64.decode(entry.value! as String);
    }
    final fakeModel = Uint8List.fromList(
      utf8.encode('unit-test backend has no model weights'),
    );
    files['test-model.bin'] = fakeModel;
    final bundle = await GectorVerifiedBundle.load(
      read: (name) => Stream<List<int>>.value(files[name]!),
      artifact: GectorModelArtifact(
        file: 'test-model.bin',
        sha256: sha256.convert(fakeModel).toString(),
        bytes: fakeModel.length,
      ),
    );
    return TestBundle(files, bundle);
  }
}

final class ScriptedBackend implements GectorBackend {
  ScriptedBackend(
    this.config,
    this.steps, {
    this.delay = Duration.zero,
    this.failOnCall,
    this.artifactSha256 = 'test',
  });
  final GectorConfiguration config;
  final List<List<String>> steps;
  final Duration delay;
  final int? failOnCall;
  final String artifactSha256;
  int calls = 0;
  bool disposed = false;
  @override
  GectorBackendIdentity get identity => GectorBackendIdentity(
    artifactSha256: artifactSha256,
    sourceModelSha256: gectorSourceModelSha256,
  );
  @override
  Future<GectorLogits> forward(GectorPreparedInput input) async {
    if (disposed) throw StateError('disposed');
    calls++;
    if (delay != Duration.zero) await Future<void>.delayed(delay);
    if (calls == failOnCall) throw StateError('Injected forward failure');
    final tags = steps.isEmpty
        ? List<String>.filled(input.firstSubwordIndices.length, r'$KEEP')
        : steps[(calls - 1).clamp(0, steps.length - 1)];
    final labels = Float32List(input.tokenCount * config.labels.length)
      ..fillRange(0, input.tokenCount * config.labels.length, -12);
    final detection = Float32List(input.tokenCount * 2);
    for (var row = 0; row < input.tokenCount; row++) {
      labels[row * config.labels.length + config.keepIndex] = 12;
      detection[row * 2 + 1] = 12;
    }
    for (var i = 0; i < input.firstSubwordIndices.length; i++) {
      final index = config.labels.indexOf(tags[i]);
      if (index < 0) throw StateError('No label ${tags[i]}');
      final row = input.firstSubwordIndices[i];
      labels[row * config.labels.length + config.keepIndex] = -12;
      labels[row * config.labels.length + index] = 12;
    }
    return GectorLogits(
      tokenCount: input.tokenCount,
      labels: labels,
      detection: detection,
      labelCount: config.labels.length,
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class TestBackendFactory implements GectorBackendFactory {
  const TestBackendFactory(
    this.config, {
    this.delayMillis = 0,
    this.failOnCall,
    this.wrongIdentity = false,
    this.steps = const <List<String>>[],
  });
  final GectorConfiguration config;
  final int delayMillis;
  final int? failOnCall;
  final bool wrongIdentity;
  final List<List<String>> steps;
  @override
  Future<GectorBackend> open(GectorModelArtifact artifact) async =>
      ScriptedBackend(
        config,
        steps,
        delay: Duration(milliseconds: delayMillis),
        failOnCall: failOnCall,
        artifactSha256: wrongIdentity ? 'wrong' : artifact.sha256,
      );
}
