/// Optional local Arabic morphological analysis. The analyzer is part of the
/// app; the Camel Morph MSA database is downloaded by the user and verified
/// against pinned hashes. No document text is sent to a remote service.
library;

export 'src/camel_arabic_morphology.dart';
export 'src/morph_analysis.dart';
export 'src/morph_catalog.dart';
export 'src/morph_transport.dart';
