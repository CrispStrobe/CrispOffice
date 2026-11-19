/// Optional local Hunspell spelling. The engine is part of the app; the
/// dictionaries are downloaded by the user and verified against pinned hashes.
/// No document text is sent to a remote service.
library;

export 'src/hunspell_catalog.dart';
export 'src/hunspell_provider.dart';
export 'src/hunspell_transport.dart';
export 'src/hunspell_words.dart';
