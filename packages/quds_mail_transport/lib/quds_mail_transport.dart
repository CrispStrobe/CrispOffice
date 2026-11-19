/// Native IMAP and Exchange Server EWS; browser entries return typed unsupported.
library;

export 'src/configuration.dart';
export 'src/ews/configuration.dart' hide validEwsAddress;
export 'src/ews/unsupported.dart'
    if (dart.library.io) 'src/ews/native/factory.dart';
export 'src/unsupported/provider.dart'
    if (dart.library.io) 'src/native/factory.dart';
