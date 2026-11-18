import 'dart:convert';
import 'dart:io';

import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

import 'studio_spacy_host.dart';

String configurationId() => jsonEncode([
  'studio-spacy-v2',
  Platform.environment['QUDS_SPACY_BUNDLE'],
  Platform.environment['QUDS_SPACY_LIBRARY'],
  Platform.environment['QUDS_SPACY_LIBRARY_SHA256'],
  Platform.environment['CRISPEMBED_SPACY'],
  studioSpacyHost.status.configurationKey,
]);

/// Developer environment variables keep their original precedence; otherwise
/// the user-installed, re-verified package is used. Nothing downloads here.
Future<SpacyTransport> openTransport() => studioSpacyHost.openTransport();
