import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

import 'studio_spacy_config_unsupported.dart'
    if (dart.library.io) 'studio_spacy_config_native.dart'
    as platform;

/// Identifies the explicit host installation without opening files or a worker.
String studioSpacyConfigurationId() => platform.configurationId();

/// Called only by the user's analysis action. There is no download/fallback;
/// acquisition is the separate explicit setup flow ([studioSpacyHost]).
Future<SpacyTransport> openStudioSpacyTransport({
  SpacyLanguage language = SpacyLanguage.german,
}) => platform.openTransport(language);
