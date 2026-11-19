import 'package:quds_language_id/quds_language_id.dart';

import 'studio_language_id_host.dart';

/// Browser host: the bundled WebAssembly classifier runs in a module Web
/// Worker served from `proofing/language_id_worker.mjs`.
StudioLanguageIdHost createLanguageIdHost() => BundledStudioLanguageIdHost(
  createIdentifier: (model) => Cld3LanguageIdentifier(model: model),
);
