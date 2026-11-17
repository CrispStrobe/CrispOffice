import 'package:quds_office_studio/studio_spacy_config.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

Future<void> main() async {
  if (studioSpacyConfigurationId() != 'studio-spacy-browser-unavailable-v1') {
    throw StateError('Native host configuration reached browser import.');
  }
  try {
    await openStudioSpacyTransport();
    throw StateError('Browser unexpectedly started native analysis.');
  } on SpacyUnavailableException catch (error) {
    // This executable developer gate reports its explicit unsupported outcome.
    // ignore: avoid_print
    print(error.message);
  }
}
