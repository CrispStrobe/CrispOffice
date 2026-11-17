import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_proofing_gector/quds_proofing_gector_native.dart';
import 'package:test/test.dart';

void main() {
  test('native factory requires a pinned library and bounded thread count', () {
    for (final threads in [0, 65]) {
      expect(
        () => GectorNativeBackendFactory(
          modelDirectory: '.',
          libraryPath: 'library',
          librarySha256: '0' * 64,
          threads: threads,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => GectorNativeBackendFactory(
        modelDirectory: '.',
        libraryPath: 'library',
        librarySha256: 'unpinned',
      ),
      throwsArgumentError,
    );
  });

  test('rejects altered model bytes before loading native code', () async {
    final temporary = await Directory.systemTemp.createTemp('gector-adapter-');
    addTearDown(() => temporary.delete(recursive: true));
    final file = File('${temporary.path}/model.gguf');
    await file.writeAsBytes([1, 2, 3]);
    final factory = GectorNativeBackendFactory(
      modelDirectory: temporary.path,
      libraryPath: '${temporary.path}/does-not-exist',
      librarySha256: '0' * 64,
    );
    final artifact = GectorModelArtifact(
      file: 'model.gguf',
      bytes: 3,
      sha256: '0' * 64,
    );
    await expectLater(
      factory.open(artifact),
      throwsA(
        isA<GectorUnavailableException>().having(
          (e) => e.message,
          'message',
          contains('SHA-256'),
        ),
      ),
    );
  });

  final environment = Platform.environment;
  final libraryPath = environment['GECTOR_TEST_LIBRARY'];
  final modelPath = environment['GECTOR_TEST_MODEL'];
  final modelHash = environment['GECTOR_TEST_MODEL_SHA256'];
  final libraryHash = environment['GECTOR_TEST_LIBRARY_SHA256'];
  final available = [
    libraryPath,
    modelPath,
    modelHash,
    libraryHash,
  ].every((value) => value != null && value.isNotEmpty);

  test(
    'real native dual heads own their output and reject use after dispose',
    () async {
      final model = File(modelPath!);
      final backend =
          await GectorNativeBackendFactory(
            modelDirectory: model.parent.path,
            libraryPath: libraryPath!,
            librarySha256: libraryHash!,
          ).open(
            GectorModelArtifact(
              file: model.uri.pathSegments.last,
              bytes: await model.length(),
              sha256: modelHash!,
            ),
          );
      addTearDown(backend.dispose);
      expect(backend.identity.artifactSha256, modelHash);
      final input = GectorPreparedInput(
        inputIds: [3, 4],
        firstSubwordIndices: [0],
      );
      final first = await backend.forward(input);
      final saved = sha256
          .convert(first.labels.buffer.asUint8List())
          .toString();
      final second = await backend.forward(input);
      expect(first.labels, hasLength(10000));
      expect(first.detection, hasLength(4));
      expect(first.labels.every((value) => value.isFinite), isTrue);
      expect(second.labels, orderedEquals(first.labels));
      second.labels[0] = 123;
      expect(
        sha256.convert(first.labels.buffer.asUint8List()).toString(),
        saved,
      );
      input.inputIds[0] = -1;
      await expectLater(
        backend.forward(input),
        throwsA(isA<GectorUnavailableException>()),
      );
      await backend.dispose();
      await backend.dispose();
      await expectLater(
        backend.forward(input),
        throwsA(isA<GectorUnavailableException>()),
      );
    },
    skip: available
        ? false
        : 'Requires four explicitly pinned native fixture variables.',
  );
}
