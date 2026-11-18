import 'dart:convert';
import 'dart:io';

import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';

String configurationId() => jsonEncode([
  'studio-spacy-v1',
  Platform.environment['QUDS_SPACY_BUNDLE'],
  Platform.environment['QUDS_SPACY_LIBRARY'],
  Platform.environment['QUDS_SPACY_LIBRARY_SHA256'],
  Platform.environment['CRISPEMBED_SPACY'],
]);

Future<SpacyTransport> openTransport() async {
  final environment = Platform.environment;
  final gate = environment['CRISPEMBED_SPACY']?.toLowerCase();
  if (gate == null || const ['', '0', 'false', 'off', 'no'].contains(gate)) {
    throw const SpacyUnavailableException(
      'Local German text analysis is disabled. Enable the optional analysis '
      'installation in the host configuration.',
    );
  }
  final bundle = environment['QUDS_SPACY_BUNDLE'];
  final library = environment['QUDS_SPACY_LIBRARY'];
  final digest = environment['QUDS_SPACY_LIBRARY_SHA256'];
  if (bundle == null ||
      bundle.isEmpty ||
      library == null ||
      library.isEmpty ||
      digest == null ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    throw const SpacyUnavailableException(
      'Local German text analysis is not installed. Configure the verified '
      'German model bundle and native library in the host application.',
    );
  }
  return startSpacyWorker(
    bundle: const SpacyBundle.germanF32(),
    backendFactory: SpacyNativeBackendFactory(
      bundleDirectory: bundle,
      libraryPath: library,
      librarySha256: digest,
    ),
  );
}
