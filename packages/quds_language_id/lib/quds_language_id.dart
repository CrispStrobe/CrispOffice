/// Bundled automatic language identification for Quds Office: CrispASR's
/// CLD3 runtime (MIT) with Google's CLD3 model (Apache-2.0, about 440 KB,
/// shipped with the app and verified by SHA-256). Texts are classified
/// locally in a worker (a persistent isolate natively, a module Web Worker
/// in browsers); nothing is downloaded or sent anywhere.
library;

export 'src/cld3_labels.dart';
export 'src/cld3_language_identifier.dart';
export 'src/cld3_model.dart';
export 'src/language_id_transport.dart';
