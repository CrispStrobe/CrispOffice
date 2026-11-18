import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

String configurationId() => 'studio-spacy-browser-unavailable-v1';

Future<SpacyTransport> openTransport(SpacyLanguage language) async {
  throw const SpacyUnavailableException(
    'Local text analysis is unavailable in this browser.',
  );
}
