import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

String configurationId() => 'studio-spacy-browser-unavailable-v1';

Future<SpacyTransport> openTransport() async {
  throw const SpacyUnavailableException(
    'Local German text analysis is unavailable in this browser.',
  );
}
