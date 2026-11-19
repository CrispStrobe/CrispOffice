/// Manual native IMAP access; the browser entry returns typed unsupported results.
library;

export 'src/configuration.dart';
export 'src/unsupported/provider.dart'
    if (dart.library.io) 'src/native/factory.dart';
