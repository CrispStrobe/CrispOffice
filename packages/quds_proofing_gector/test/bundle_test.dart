import 'dart:typed_data';

import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late TestBundle fixtures;
  setUpAll(() async {
    fixtures = await TestBundle.load();
  });

  test('all pinned metadata plus streamed model bytes authenticate', () {
    expect(fixtures.bundle.assetDigests.length, 13);
    expect(fixtures.bundle.configuration.labels.length, 5000);
    expect(fixtures.bundle.tokenizer.vocabulary.length, 31102);
    expect(fixtures.bundle.artifact.sourceModelSha256, gectorSourceModelSha256);
  });
  test(
    'changed metadata, truncated model and excess model bytes fail closed',
    () async {
      for (final name in <String>['config.json', 'test-model.bin']) {
        final files = Map<String, Uint8List>.from(fixtures.files);
        final changed = Uint8List.fromList(files[name]!);
        changed[0] ^= 1;
        files[name] = changed;
        await expectLater(
          GectorVerifiedBundle.load(
            read: (file) => Stream<List<int>>.value(files[file]!),
            artifact: fixtures.bundle.artifact,
          ),
          throwsFormatException,
        );
      }
      for (final length in <int>[
        1,
        fixtures.files['test-model.bin']!.length + 1,
      ]) {
        final files = Map<String, Uint8List>.from(fixtures.files);
        files['test-model.bin'] = Uint8List(length);
        await expectLater(
          GectorVerifiedBundle.load(
            read: (file) => Stream<List<int>>.value(files[file]!),
            artifact: fixtures.bundle.artifact,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('artifact filenames and source identities are bounded', () {
    expect(
      () => GectorModelArtifact(
        file: '../model.gguf',
        sha256: 'a' * 64,
        bytes: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => GectorModelArtifact(
        file: 'model.gguf',
        sha256: 'a' * 64,
        bytes: 1,
        sourceModelSha256: 'b' * 64,
      ),
      throwsArgumentError,
    );
  });
}
